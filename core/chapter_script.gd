class_name ChapterScript
extends Node
## One instance per chapter. On death a new instance starts at the saved segment.

var level: LevelBase

func active() -> bool:
	return not has_meta("cancelled") and is_inside_tree()

func run(_from_checkpoint := "") -> void:
	pass

func run_segments(number: int, segments: Dictionary, from_checkpoint: String, next: Callable) -> void:
	var keys := segments.keys()
	var start := 0 if from_checkpoint == "" else keys.find(from_checkpoint)
	if start < 0:
		fail("Checkpoint không hợp lệ: " + from_checkpoint)
		return
	GameState.chapter = number
	EventBus.chapter_started.emit(number, GameState.phase)
	for i in range(start, keys.size()):
		if not active():
			return
		GameState.clear_objectives()
		var beat: Callable = segments[keys[i]]
		await beat.call()
	if active():
		EventBus.chapter_finished.emit(number)
		next.call_deferred()

func fail(message: String) -> void:
	set_meta("cancelled", true)
	ChapterDirector.fail_story(message)

func wait(seconds: float) -> void:
	if GameState.debug_autoplay:
		seconds = min(seconds, 0.05)
	await get_tree().create_timer(seconds, false).timeout

func wait_until(condition: Callable) -> bool:
	while active():
		if not get_tree().paused and condition.call():
			return true
		await get_tree().process_frame
	return false

func travel(id: String, spawn: String, preset: String, phase: String, hour: int, minute := 0) -> bool:
	if not active():
		return false
	level = await ChapterDirector.goto_level(id, spawn, preset, 0.0 if GameState.debug_autoplay else 0.5)
	if not active() or level == null:
		return false
	GameState.phase = phase
	GameState.set_clock(hour, minute)
	return true

func node(path: String) -> Node:
	if not active():
		return null
	var result := level.get_node_or_null(path) if is_instance_valid(level) else null
	if result == null:
		fail("Thiếu nút %s trong %s" % [path, level.level_id if is_instance_valid(level) else "level"])
	return result

func npc(id: String, show: bool) -> void:
	var actor := node("NPCs/" + id) as Node3D
	if actor:
		actor.visible = show

func camera(id: String) -> void:
	var cam := node("Markers/" + id) as Camera3D
	if cam:
		cam.make_current()

func cutscene_begin(id: String, cam := "") -> void:
	if not active():
		return
	GameState.lock_input("cutscene")
	EventBus.cutscene_started.emit(id)
	EventBus.letterbox.emit(true)
	if cam != "":
		camera(cam)

func cutscene_end(id: String) -> void:
	if not active():
		return
	if is_instance_valid(GameState.player):
		GameState.player.get_camera().make_current()
	GameState.unlock_input("cutscene")
	EventBus.letterbox.emit(false)
	EventBus.cutscene_finished.emit(id)

func card(title: String, subtitle := "", seconds := 2.0) -> void:
	if not active():
		return
	GameState.lock_input("card")
	await TitleCard.show_card(get_tree(), title, subtitle, seconds, 0.4, self)
	if active():
		GameState.unlock_input("card")

func say(keys: Array) -> void:
	for key in keys:
		if not active():
			return
		if not Dialogue.has_line(key):
			fail("Thiếu thoại: " + str(key))
			return
		await Dialogue.say(key)

func messages(ids: Array) -> void:
	for id in ids:
		if not active():
			return
		if Dialogue.get_message(id).is_empty():
			fail("Thiếu tin nhắn: " + str(id))
			return
		GameState.unlock_message(id)

func choose(prompt: String, options: PackedStringArray, autoplay_index: int) -> int:
	if not active():
		return -1
	GameState.lock_input("story_choice")
	var result := await Dialogue.ask(prompt, options, 0.0, autoplay_index)
	if active():
		GameState.unlock_input("story_choice")
	return result

func good_run() -> bool:
	return GameState.debug_autoplay and GameState.autoplay_ending == "A"

func objective(id: String, text: String) -> void:
	GameState.add_objective(id, text)

func wait_trigger(id: String) -> bool:
	var zone := node("Triggers/" + id) as TriggerZone
	if zone == null:
		return false
	if GameState.debug_autoplay and not zone.fired:
		zone._on_enter(GameState.player)
	return await wait_until(func(): return zone.fired)

func wait_flag(flag: String) -> bool:
	return await wait_until(func(): return GameState.get_flag(flag))

func wait_use(path: String) -> bool:
	var target := node(path) as Interactable
	if target == null:
		return false
	var used := [false]
	target.used.connect(func(_player: Node3D): used[0] = true, CONNECT_ONE_SHOT)
	if GameState.debug_autoplay:
		target.interact(GameState.player)
	return await wait_until(func(): return used[0])

func play_minigame(game: MinigameBase) -> bool:
	if not active() or game == null:
		return false
	game.start()
	return await wait_until(game.is_completed)

## Score receipts are separate from flags already set by Readable / Phone / Pickup.
func award(flag: String, amount := 1) -> void:
	if not active() or GameState.get_flag("resolve_awarded_" + flag):
		return
	GameState.set_flag("resolve_awarded_" + flag)
	GameState.set_flag(flag)
	GameState.add_resolve(amount, flag)

func award_on_flag(flag: String, amount := 1) -> void:
	if GameState.get_flag(flag):
		award(flag, amount)
	var connection := func(key: String, value: Variant):
		if key == flag and value:
			award(flag, amount)
	EventBus.flag_changed.connect(connection)
	# Do not let a prior scene's pickup score a later segment.
	level.tree_exiting.connect(func():
		if EventBus.flag_changed.is_connected(connection):
			EventBus.flag_changed.disconnect(connection), CONNECT_ONE_SHOT)

func checkpoint(id: String) -> void:
	if active():
		SaveSystem.save_checkpoint(id)
		if GameState.debug_autoplay:
			print("AUTOPLAY checkpoint=%s resolve=%d" % [id, GameState.resolve])

func wake_up() -> void:
	GameState.unlock_input("sleep")
	EventBus.fade_request.emit(false, 0.05 if GameState.debug_autoplay else 0.7)

func finish_story(ending: String) -> void:
	if not active():
		return
	if GameState.debug_autoplay:
		if ending != GameState.autoplay_ending or ending != GameState.compute_ending():
			fail("Autoplay: kết thúc không đúng (%s, dự kiến %s)" % [ending, GameState.autoplay_ending])
		else:
			print("AUTOPLAY PASS ending=%s resolve=%d" % [ending, GameState.resolve])
			get_tree().quit()
		return
	SaveSystem.mark_ending_seen(ending)
	ChapterDirector.return_to_menu.call_deferred()
