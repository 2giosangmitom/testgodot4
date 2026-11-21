extends Node
## Owns scene flow: level loading with fades, player spawning, and running chapter scripts.

const PLAYER_SCENE := "res://player/player.tscn"
const LEVELS := {
	"school": "res://levels/school/school.tscn",
	"store_alley": "res://levels/store_alley/store_alley.tscn",
	"dorm_shrine": "res://levels/dorm_shrine/dorm_shrine.tscn",
}

var current_level: Node = null
var current_chapter: Node = null
var transitioning := false
var _handling_death := false
var menu_error := ""

const CAUGHT_FALLBACK_TIMEOUT := 6.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.player_caught.connect(_on_player_caught)

## Chapter number from a checkpoint id like "ch2_dorm" (0 if unknown).
static func chapter_of(checkpoint_id: String) -> int:
	if checkpoint_id.begins_with("ch") and checkpoint_id.length() > 2:
		return int(checkpoint_id.substr(2, 1))
	return 0

## Main menu "Tiếp tục".
func continue_from_checkpoint() -> void:
	var id := SaveSystem.load_checkpoint()
	var ch := chapter_of(id)
	if ch == 0:
		GameState.reset()
		await start_chapter(1)
	else:
		await start_chapter(ch, id)

## Main menu "Chọn chương".
func start_new_at(chapter: int) -> void:
	GameState.reset()
	# Keep the previous save until the new run reaches a valid checkpoint.
	# Restarting at the finale supplies its prerequisites, not its ritual decisions.
	if chapter == 4:
		for item in ["has_photo", "has_incense", "has_oil"]:
			GameState.set_flag(item)
		GameState.add_resolve(3, "chapter_select")
	await start_chapter(chapter)

func start_autoplay() -> void:
	if GameState.autoplay_ending not in ["A", "B"]:
		fail_story("Dùng --autoplay --ending=A hoặc --ending=B.")
		return
	get_tree().create_timer(90).timeout.connect(func(): fail_story("Autoplay quá thời gian."))
	await start_new_at(1)

func _on_player_caught(_entity_id: String, _cause: String) -> void:
	# Standalone sandboxes and logic tests have no story checkpoint to restore.
	if _handling_death or GameState.debug_autoplay or not is_instance_valid(current_chapter):
		return
	_handling_death = true
	current_chapter.set_meta("cancelled", true)
	GameState.lock_input("dead")
	# Normal path: CaughtSequence finishes (~2.5 s + fade) and emits entity_state_changed(id, "caught_done").
	# Fallback: if nothing reports completion (e.g. Player.kill without a sequence), reload after a timeout.
	var done := [false]
	var cb := func(_id: String, state: String):
		if state == "caught_done":
			done[0] = true
	EventBus.entity_state_changed.connect(cb)
	var t := 0.0
	while not done[0] and t < CAUGHT_FALLBACK_TIMEOUT:
		await get_tree().process_frame
		t += get_process_delta_time()
	EventBus.entity_state_changed.disconnect(cb)
	await get_tree().create_timer(0.3).timeout
	RenderSettings.set_static(0.0)
	Dialogue.cancel()
	GameState.reset()
	_handling_death = false
	await continue_from_checkpoint()

func return_to_menu() -> void:
	if is_instance_valid(current_chapter):
		current_chapter.set_meta("cancelled", true)
		current_chapter.queue_free()
	current_chapter = null
	current_level = null
	transitioning = false
	get_tree().paused = false
	GameState.input_locks.clear()
	GameState.phone_open = false
	Dialogue.cancel()
	AudioDirector.stop_all_ambience(0.5)
	AudioDirector.stop_music(0.5)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

func fail_story(message: String) -> void:
	push_error("ChapterDirector: " + message)
	if GameState.debug_autoplay:
		get_tree().quit(1)
	else:
		menu_error = message
		return_to_menu.call_deferred()

## Loads a level by id (see LEVELS) or path, applies a lighting preset and spawns the player.
func goto_level(level: String, spawn := "default", preset := "", fade := 0.8) -> Node:
	var path: String = LEVELS.get(level, level)
	if not ResourceLoader.exists(path, "PackedScene"):
		fail_story("Không thể tải màn: " + level)
		return null
	transitioning = true
	GameState.lock_input("transition")
	var owner := current_chapter
	var tree := get_tree()
	if fade > 0.0:
		EventBus.fade_request.emit(true, fade)
		await tree.create_timer(fade, false).timeout
	else:
		# A beat can finish during a physics or input callback.
		await tree.process_frame
	if owner != current_chapter or (is_instance_valid(owner) and owner.has_meta("cancelled")):
		return null
	var err := tree.change_scene_to_file(path)
	if err != OK:
		fail_story("Không thể tải màn: " + level)
		return null
	await tree.scene_changed
	if owner != current_chapter or (is_instance_valid(owner) and owner.has_meta("cancelled")):
		return null
	current_level = tree.current_scene
	var scene := current_level as LevelBase
	if scene == null or (preset != "" and not scene.has_node("Presets/" + preset)) \
			or (spawn != "" and scene.get_spawn(spawn) == null):
		fail_story("Màn không khớp quy ước: %s / %s / %s" % [level, spawn, preset])
		return null
	if preset != "":
		scene.apply_preset(preset)
	if spawn != "":
		scene.spawn_player(spawn)
	EventBus.fade_request.emit(false, fade)
	if fade > 0.0:
		await tree.create_timer(fade, false).timeout
	if owner != current_chapter or (is_instance_valid(owner) and owner.has_meta("cancelled")):
		return null
	GameState.unlock_input("transition")
	transitioning = false
	return current_level

## Runs chapters/ch<n>.gd (or an ending script path) as a child node.
func start_chapter(n: int, from_checkpoint := "") -> void:
	await run_script("res://chapters/ch%d.gd" % n, from_checkpoint)

func run_script(path: String, from_checkpoint := "") -> void:
	if is_instance_valid(current_chapter):
		current_chapter.set_meta("cancelled", true)
		current_chapter.queue_free()
	var script := load(path) as Script if ResourceLoader.exists(path, "Script") else null
	if script == null or not script.can_instantiate():
		fail_story("Không thể chạy kịch bản: " + path)
		return
	current_chapter = script.new()
	current_chapter.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(current_chapter)
	await current_chapter.run(from_checkpoint)

func get_marker(name: String) -> Node3D:
	if current_level and current_level.has_method("get_marker"):
		return current_level.get_marker(name)
	return null
