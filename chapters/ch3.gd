extends ChapterScript

const CROWDS := ["CrowdBusStop", "CrowdSweepers", "CrowdTeaShop", "CrowdSchoolyard"]

func run(from_checkpoint := "") -> void:
	await run_segments(3, {
		"": _room,
		"ch3_street": _street,
		"ch3_gate": _gate,
	}, from_checkpoint, ChapterDirector.start_chapter.bind(4))

func _room() -> void:
	if not await travel("dorm_shrine", "room", "day", "day", 16):
		return
	await card("Chương 3", "Phố không người")
	messages(["m_ch3_hanh_01", "m_ch3_linh_01", "m_ch3_hung_01"])
	if not GameState.get_flag("has_photo"):
		objective("photo", "Lấy tấm ảnh cũ trong túi đồ trên gác")
		if GameState.debug_autoplay:
			GameState.set_flag("has_photo")
		if not await wait_flag("has_photo"):
			return
		GameState.complete_objective("photo")
		if not await wait_until(func(): return not GameState.is_input_locked()):
			return

func _crowds() -> void:
	for id in CROWDS:
		var crowd := node("Entities/" + id) as CrowdGroup
		if crowd == null:
			return
		crowd.alerted.connect(func():
			if active():
				GameState.set_flag("ch3_alerted"))
		crowd.activate()

func _street() -> void:
	if not await travel("school", "street", "night_ch3", "night", 22):
		return
	checkpoint("ch3_street")
	_crowds()
	if not await wait_until(func(): return not GameState.is_input_locked()):
		return
	objective("find_linh", "Tìm Linh ở cổng trường")
	await say(["ch3_nam_01", "ch3_nam_02"])
	if not await wait_trigger("trig_ch3_gate"):
		return
	GameState.complete_objective("find_linh")
	GameState.set_clock(22, 7)
	messages(["m_ch3_linh_02"])
	await say(["ch3_nam_03"])

func _gate() -> void:
	if not await travel("school", "gate_outside", "night_ch3", "night", 22, 7):
		return
	checkpoint("ch3_gate")
	_crowds()
	npc("BacTu", true)
	var guard := node("NPCs/BacTu") as Node3D
	var poster := node("Interactables/MissingPoster") as Readable
	var incense := node("Interactables/IncensePickup") as PickupItem
	var oil := node("Interactables/GuardOilPickup") as PickupItem
	if not active():
		return
	award_on_flag("has_name_tag")
	poster.used.connect(func(_p: Node3D):
		award("has_name_tag")
		_poster_voice(), CONNECT_ONE_SHOT)
	objective("guard", "Nói chuyện với bác Tư ở chốt bảo vệ")
	if not await wait_until(func(): return GameState.debug_autoplay \
			or guard.global_position.distance_to(GameState.player.global_position) <= 3.2):
		return
	var heard := true
	for line in ["ch3_tu_01", "ch3_tu_02", "ch3_tu_03", "ch3_tu_04", "ch3_tu_05"]:
		if not active():
			return
		var left := [false]
		var start := GameState.player.global_position
		var on_frame := func():
			if not GameState.debug_autoplay and active() \
					and GameState.player.global_position.distance_to(start) > 4.0:
				left[0] = true
				Dialogue.skip_line()
		get_tree().process_frame.connect(on_frame)
		await say([line])
		if get_tree().process_frame.is_connected(on_frame):
			get_tree().process_frame.disconnect(on_frame)
		if left[0]:
			heard = false
			break
	if heard and (not GameState.debug_autoplay or good_run()):
		award("ch3_bac_tu_story")
	GameState.complete_objective("guard")
	objective("oil", "Lấy chai dầu lạc ở chốt bảo vệ")
	objective("incense", "Lấy nhang ở tạp hóa bên kia đường")
	if GameState.debug_autoplay:
		oil.interact(GameState.player)
		incense.interact(GameState.player)
		if good_run():
			GameState.set_flag("has_name_tag")
	if not await wait_flag("has_oil"):
		return
	GameState.complete_objective("oil")
	if not await wait_flag("has_incense"):
		return
	GameState.complete_objective("incense")
	await say(["ch3_nam_05"])
	objective("back_alley", "Đi về phía ngõ nhà Nam")
	if not await wait_trigger("trig_ch3_leave"):
		return
	GameState.complete_objective("back_alley")
	if not GameState.get_flag("ch3_alerted") and (not GameState.debug_autoplay or good_run()):
		award("ch3_silent")
	await card("Hết chương 3")

func _poster_voice() -> void:
	# The read overlay acquires its input lock before emitting used.
	if await wait_until(func(): return not GameState.is_input_locked()):
		await say(["ch3_nam_04"])
