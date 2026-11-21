extends ChapterScript

func run(from_checkpoint := "") -> void:
	await run_segments(2, {
		"ch2_store": _store,
		"ch2_dorm": _dorm,
		"ch2_breaker": _breaker,
	}, from_checkpoint, ChapterDirector.start_chapter.bind(3))

func _store() -> void:
	if not await travel("store_alley", "default", "dusk_store", "day", 17):
		return
	checkpoint("ch2_store")
	await card("Chương 2", "Người gõ cửa")
	npc("Hanh", true)
	cutscene_begin("ch2_shift", "cam_counter")
	await say(["ch2_hanh_01", "ch2_hanh_02"])
	cutscene_end("ch2_shift")
	var shelves := node("Interactables/ShelfStock") as MinigameBase
	var checkout := node("Interactables/Checkout") as MinigameCheckout
	if not active():
		return
	objective("afternoon_stock", "Xếp hàng lên kệ số 2")
	objective("afternoon_drawer", "Dọn ngăn kéo trong kho")
	shelves.completed.connect(func(): GameState.complete_objective("afternoon_stock"))
	shelves.start()
	if GameState.debug_autoplay:
		GameState.set_flag("found_name_tag_store")
	if not await wait_flag("found_name_tag_store"):
		return
	GameState.complete_objective("afternoon_drawer")
	# Let the player finish reading the card before starting the next conversation.
	if not await wait_until(func(): return not GameState.is_input_locked()):
		return
	await say(["ch2_nam_01", "ch2_hanh_03"])
	npc("Hanh", false)
	npc("Linh", true)
	cutscene_begin("ch2_linh_visit", "cam_store_wide")
	await say(["ch2_linh_01", "ch2_nam_02", "ch2_linh_02"])
	cutscene_end("ch2_linh_visit")
	npc("Linh", false)
	objective("afternoon_checkout", "Tính tiền cho khách")
	checkout.item_count = 3
	if not await play_minigame(checkout):
		return
	GameState.complete_objective("afternoon_checkout")
	if not await wait_until(shelves.is_completed):
		return
	GameState.set_clock(18, 20)
	messages(["m_ch2_hung_01"])
	objective("afternoon_home", "Đi qua ngõ về khu trọ")
	if await wait_trigger("trig_alley_end"):
		GameState.complete_objective("afternoon_home")

func _dorm() -> void:
	if not await travel("dorm_shrine", "default", "night", "night", 21):
		return
	checkpoint("ch2_dorm")
	messages(["m_ch2_me_01"])
	var noodles := node("Interactables/Noodles") as MinigameBase
	var routine := node("Interactables/RoomRoutine") as MinigameRoomRoutine
	var mimic := node("Entities/MimicDoor") as Mimic
	if not active():
		return
	objective("ch2_noodles", "Về P.204 và nấu mì")
	if not await play_minigame(noodles):
		return
	GameState.complete_objective("ch2_noodles")
	GameState.set_clock(22, 5)
	messages(["m_ch2_linh_01"])
	if not await _bedtime(routine, "ch2_bedtime"):
		return
	var room_spawn := level.get_spawn("room")
	GameState.player.teleport(room_spawn.global_transform)
	GameState.set_clock(23, 40)
	var switch_ := routine.get_part("lamp_switch_off") as MinigameLightSwitch
	# Nam turns the light on when he wakes; it can be switched back off at any point during the knock.
	switch_.set_lights(true)
	mimic.lights_group = "room_lights"
	mimic.breach_if_lights_on = false
	mimic.voice_lines.assign(["ch2_mimic_hung_01", "ch2_mimic_hung_02", "ch2_mimic_hung_03",
		"ch2_mimic_hung_04", "ch2_mimic_hung_05"])
	mimic.state_changed.connect(func(state: String):
		if not active():
			return
		if state == "talk" and mimic.line_index == 0:
			if GameState.get_flag("read_m_ch2_hung_01") or good_run():
				award("read_m_ch2_hung_01")
		elif state == "asking" and not GameState.get_flag("ch2_fake_delivered"):
			GameState.set_flag("ch2_fake_delivered")
			_door_messages())
	switch_.toggled.connect(func(on: bool):
		if not on and mimic.is_active():
			award("ch2_lights_off"))
	wake_up()
	objective("ch2_knock", "Có tiếng gõ cửa. Đừng vội mở.")
	mimic.activate()
	if good_run():
		switch_.set_lights(false)
	if not await wait_until(func(): return not mimic.is_active()):
		return
	GameState.complete_objective("ch2_knock")

func _door_messages() -> void:
	GameState.set_clock(23, 41)
	messages(["m_ch2_fake_01"])
	await wait(1.1)
	if active():
		GameState.set_clock(23, 42)
		messages(["m_ch2_hung_02"])

func _breaker() -> void:
	if not await travel("dorm_shrine", "room", "night", "night", 2, 10):
		return
	checkpoint("ch2_breaker")
	var corridor := node("Entities/MimicCorridor") as Mimic
	var routine := node("Interactables/RoomRoutine") as MinigameRoomRoutine
	var door := node("Doors/Door204") as Door
	if not active():
		return
	door.locked = false
	GameState.set_flag("breaker_on", false)
	EventBus.lights_set.emit("dorm_lights", false)
	EventBus.lights_set.emit("room_lights", false)
	AudioDirector.stop_ambience("hum", 0.15)
	await say(["ch2_nam_04"])
	objective("ch2_power", "Xuống tầng trệt bật cầu dao")
	var stared := [0.0, false]
	corridor.activate()
	corridor.state_changed.connect(func(state: String):
		if state == "noticed" and active():
			_corridor_voice(corridor))
	if GameState.debug_autoplay:
		if not await wait_use("Interactables/Breaker"):
			return
	else:
		if not await wait_until(func():
			if corridor.is_active() and corridor.is_directly_observed():
				stared[0] += get_process_delta_time()
				if stared[0] > 2.0:
					stared[1] = true
			else:
				stared[0] = 0.0
			return GameState.get_flag("breaker_on")):
			return
	corridor.deactivate()
	if not stared[1] and (not GameState.debug_autoplay or good_run()):
		award("ch2_ignored_linh")
	GameState.complete_objective("ch2_power")
	GameState.set_clock(3)
	objective("ch2_return", "Quay về phòng P.204")
	var room_entry := node("Triggers/trig_room") as TriggerZone
	if room_entry == null:
		return
	room_entry.reset()
	var mirror := node("Interactables/Mirror") as Interactable
	if not active():
		return
	mirror.used.connect(func(_p: Node3D):
		EventBus.camera_shake.emit(0.12, 0.5)
		AudioDirector.play_sfx("static_burst", -16.0)
		if active():
			say(["ch2_nam_05"]), CONNECT_ONE_SHOT)
	if not await wait_trigger("trig_room"):
		return
	GameState.complete_objective("ch2_return")
	if not await _bedtime(routine, "ch2_after_power"):
		return
	await card("Hết chương 2")
	wake_up()

func _corridor_voice(corridor: Mimic) -> void:
	await say(["ch2_mimic_linh_01"])
	if active() and is_instance_valid(corridor) and corridor.is_active():
		await say(["ch2_mimic_linh_02"])

func _bedtime(routine: MinigameRoomRoutine, prefix: String) -> bool:
	for entry in [["check_door_lock", "Khóa cửa P.204"], ["lamp_switch_off", "Tắt đèn phòng"],
			["go_to_sleep", "Đi ngủ trên gác"]]:
		var task_id := "%s_%s" % [prefix, entry[0]]
		var part := routine.get_part(entry[0])
		objective(task_id, entry[1])
		part.completed.connect(GameState.complete_objective.bind(task_id))
	return await play_minigame(routine)
