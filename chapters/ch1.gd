extends ChapterScript

func run(from_checkpoint := "") -> void:
	await run_segments(1, {
		"ch1_school": _school,
		"ch1_store": _store,
		"ch1_alley": _alley,
	}, from_checkpoint, ChapterDirector.start_chapter.bind(2))

func _school() -> void:
	if not await travel("school", "classroom", "day", "day", 16, 40):
		return
	checkpoint("ch1_school")
	await card("Chương 1", "Ca đêm đầu tiên")
	cutscene_begin("ch1_class", "cam_courtyard")
	await wait(2.0)
	npc("Thay_Khai", true)
	npc("Students", true)
	npc("Linh", true)
	camera("cam_classroom")
	await say(["ch1_thay_01", "ch1_thay_02", "ch1_linh_01", "ch1_nam_01",
		"ch1_linh_02", "ch1_nam_02", "ch1_linh_03"])
	cutscene_end("ch1_class")
	GameState.set_clock(16, 50)
	messages(["m_ch1_hung_01", "m_ch1_me_01"])
	objective("school_gate", "Ra cổng trường")
	if not await wait_trigger("trig_gate"):
		return
	GameState.complete_objective("school_gate")
	npc("BacTu", true)
	cutscene_begin("ch1_guard", "cam_gate")
	await say(["ch1_tu_01", "ch1_nam_03", "ch1_tu_02", "ch1_tu_03"])
	cutscene_end("ch1_guard")

func _store() -> void:
	if not await travel("store_alley", "default", "night_store", "night", 22):
		return
	checkpoint("ch1_store")
	await card("22:00", "Tiện Lợi 24h Ánh Dương")
	messages(["m_ch1_spam_01"])
	var checkout := node("Interactables/Checkout") as MinigameCheckout
	var shelves := node("Interactables/ShelfStock") as MinigameBase
	var mop := node("Interactables/Mop") as MinigameBase
	var front := node("Doors/ShopDoor") as Door
	var back := node("Doors/BackDoor") as Door
	var gazer := node("Entities/Gazer") as Gazer
	var note := node("Interactables/RulesNote") as Readable
	if not active():
		return
	front.locked = true
	back.locked = true
	award_on_flag("read_rules")
	note.used.connect(func(_p: Node3D): award("read_rules"))
	npc("Hanh", true)
	cutscene_begin("ch1_handover", "cam_counter")
	await say(["ch1_hanh_01", "ch1_hanh_02", "ch1_hanh_03"])
	cutscene_end("ch1_handover")
	npc("Hanh", false)
	if not active():
		return
	if good_run():
		# Readable still uses its usual flag and scoring path; don't open the paper UI in autoplay.
		GameState.set_flag("read_rules")
	objective("night_stock", "Xếp hàng lên kệ số 2")
	objective("night_clean", "Lau sàn")
	objective("night_checkout", "Tính tiền cho hai khách")
	shelves.completed.connect(func(): GameState.complete_objective("night_stock"))
	mop.completed.connect(func(): GameState.complete_objective("night_clean"))
	shelves.start()
	mop.start()
	GameState.set_clock(22, 30)
	checkout.customer_scene = EntityBase.find_char_model("passerby_m1")
	checkout.item_count = 3
	AudioDirector.play_sfx("shop_bell")
	await say(["ch1_khach_01"])
	if not await play_minigame(checkout):
		return
	GameState.set_clock(23, 50)
	checkout.customer_scene = EntityBase.find_char_model("student_f2")
	checkout.item_count = 7
	var drink := checkout.products[0] if not checkout.products.is_empty() else MinigameProduct.defaults()[1]
	checkout.products = [drink]
	AudioDirector.play_sfx("shop_bell")
	if not await play_minigame(checkout):
		return
	GameState.complete_objective("night_checkout")
	GameState.set_clock(0, 30)
	gazer.nonlethal_stare = true
	var froze := [false]
	gazer.stared_out.connect(func(): froze[0] = true)
	gazer.activate()
	await say(["ch1_nam_04"])
	if not active():
		return
	if GameState.debug_autoplay:
		while gazer.index < gazer.marker_count() - 1:
			gazer.advance()
	var elapsed := [0.0]
	if not await wait_until(func():
		elapsed[0] += get_process_delta_time()
		return not gazer.is_active() or (elapsed[0] >= 28.0 and gazer.state == "watching")):
		return
	if gazer.is_active():
		EventBus.lights_flicker.emit("store_lights", 2.0)
		while gazer.index < gazer.marker_count() - 1:
			gazer.advance()
		if not await wait_until(func(): return not gazer.is_active()):
			return
	if not froze[0] and (not GameState.debug_autoplay or good_run()):
		award("ch1_no_stare")
	await say(["ch1_nam_05"])
	if not await wait_until(func(): return shelves.is_completed() and mop.is_completed()):
		return
	GameState.set_clock(2, 10)
	npc("OldLady", true)
	AudioDirector.play_sfx("shop_bell")
	cutscene_begin("ch1_old_lady", "cam_counter")
	await say(["ch1_bacu_01", "ch1_bacu_02", "ch1_bacu_03"])
	var answer := await choose("Bà cụ nhìn Nam, chờ tính tiền.",
		["Hỏi bà cụ", "Im lặng tính tiền"], 1 if good_run() else 0)
	if not active():
		return
	if answer == 1:
		GameState.set_flag("ch1_incense_left")
		EventBus.toast.emit("Bà cụ để lại một nén nhang.")
	else:
		await say(["ch1_nam_06"])
		EventBus.lights_flicker.emit("store_lights", 1.0)
		EventBus.toast.emit("Trên quầy chỉ còn tờ tiền âm phủ.")
	npc("OldLady", false)
	cutscene_end("ch1_old_lady")
	GameState.set_clock(4, 31)
	messages(["m_ch1_hanh_01"])

func _alley() -> void:
	# Load the same map from the register on both normal entry and checkpoint resume.
	if not await travel("store_alley", "default", "alley_predawn", "night", 5):
		return
	checkpoint("ch1_alley")
	var altar := node("Interactables/AlleyAltar") as Interactable
	if not active():
		return
	altar.enabled = GameState.get_flag("has_incense_single")
	if GameState.get_flag("ch1_incense_left") and not GameState.get_flag("has_incense_single"):
		var checkout := node("Interactables/Checkout") as MinigameCheckout
		if checkout == null:
			return
		var pickup := PickupItem.new()
		pickup.name = "SingleIncense"
		pickup.item_id = "incense_single"
		pickup.display_name = "Nén nhang"
		pickup.inventory_item = true
		var bundle: Node3D = preload("res://assets/models/props/incense_bundle.glb").instantiate()
		bundle.scale *= 0.6
		pickup.add_child(bundle)
		level.add_child(pickup)
		var spot := checkout.get_anchor("item_spot")
		if not spot:
			var spots := checkout.get_anchors("item_spot")
			if not spots.is_empty():
				spot = spots[0]
		pickup.global_position = spot.global_position if spot else checkout.to_global(Vector3(-0.4, 0.95, 0))
		PSXApply.apply_to(pickup)
		pickup.used.connect(func(_p: Node3D): altar.enabled = true)
		if good_run():
			pickup.interact(GameState.player)
	altar.used.connect(func(_p: Node3D):
		if GameState.get_flag("has_incense_single") and not GameState.get_flag("ch1_incense_alley"):
			GameState.set_flag("has_incense_single", false)
			AudioDirector.play_sfx("match_strike")
			award("ch1_incense_alley")
			altar.enabled = false)
	objective("home_alley", "Đi qua kho, ra cửa sau rồi về khu trọ")
	if not await wait_trigger("trig_alley_enter"):
		return
	if good_run():
		altar.interact(GameState.player)
	if not await wait_trigger("trig_alley_end"):
		return
	GameState.complete_objective("home_alley")
	await say(["ch1_nam_07"])
	if not await travel("dorm_shrine", "default", "night", "night", 5, 5):
		return
	objective("ch1_sleep", "Lên phòng P.204 và đi ngủ")
	var routine := node("Interactables/RoomRoutine") as MinigameRoomRoutine
	if routine == null:
		return
	# The first dawn skips the safety checklist.
	var bed := routine.get_part("go_to_sleep") as MinigameSleep
	bed.require.clear()
	if not await play_minigame(bed):
		return
	GameState.complete_objective("ch1_sleep")
	await card("Hết chương 1")
	wake_up()
