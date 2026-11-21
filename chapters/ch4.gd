extends ChapterScript

const ENDING_PATH := "res://chapters/ending_%s.gd"

func run(from_checkpoint := "") -> void:
	await run_segments(4, {
		"ch4_alley": _alley,
		"ch4_shrine": _shrine,
	}, from_checkpoint, _ending)

func _alley() -> void:
	if not await travel("store_alley", "front_street", "ch4_night", "night", 3):
		return
	checkpoint("ch4_alley")
	await card("Chương 4", "Đèn đường cuối ngõ")
	GameState.set_clock(3, 3)
	messages(["m_ch4_unknown_01"])
	var hunt := node("Entities/GazerHunt") as Gazer
	if hunt == null:
		return
	hunt.moved.connect(func(index: int):
		if not active():
			return
		if index == 1:
			say(["ch4_tuan_01"])
		elif index == 3:
			EventBus.lights_flicker.emit("alley_lights", 1.4)
			say(["ch4_tuan_02"]))
	objective("reach_shrine", "Men bên trái lách qua bóng người. Đừng nhìn nó quá lâu.")
	hunt.activate()
	if GameState.debug_autoplay:
		while hunt.index < hunt.marker_count() - 1:
			hunt.advance()
	if await wait_trigger("trig_alley_end"):
		GameState.complete_objective("reach_shrine")

func _shrine() -> void:
	if not await travel("dorm_shrine", "shrine_lane", "ch4_night", "night", 3, 8):
		return
	checkpoint("ch4_shrine")
	var tuan := node("Entities/GazerTuan") as Gazer
	var incense := node("Interactables/Ritual_Incense") as Interactable
	var photo := node("Interactables/Ritual_Photo") as Interactable
	var oil := node("Interactables/Ritual_Oil") as Interactable
	var lamp := node("Interactables/Ritual_Lamp") as Interactable
	if not active():
		return
	# At the shrine he waits under the streetlight. The player still has to avoid his gaze.
	tuan.start_index = maxi(0, tuan.marker_count() - 1)
	tuan.catch_distance = 0.5
	tuan.stare_limit = 7.0
	tuan.activate()
	var steps: Array[Interactable] = [incense, photo, oil]
	for step in steps:
		step.enabled = false
	lamp.enabled = false
	objective("shrine", "Đến bàn thờ miếu Ông Đèn")
	if not await wait_trigger("trig_shrine_close"):
		return
	GameState.complete_objective("shrine")
	var offering_steps := ["ritual_incense", "ritual_photo", "ritual_oil"]
	objective(offering_steps[0], "Thắp nhang ở bát hương")
	objective(offering_steps[1], "Đặt ảnh lên bàn thờ")
	objective(offering_steps[2], "Châm dầu vào chân đèn")
	objective("ritual_name", "Chọn tên người trông đèn")
	objective("ritual_light", "Thắp đèn dầu")
	lamp.enabled = true
	lamp.prompt = "Bỏ nghi thức"
	var abandoned := [false]
	var cancel := func(_p: Node3D): abandoned[0] = true
	lamp.used.connect(cancel)
	var items := ["has_incense", "has_photo", "has_oil"]
	var sounds := ["match_strike", "item_pickup", "water_pour"]
	for i in steps.size():
		var step := steps[i]
		step.enabled = GameState.get_flag(items[i])
		if not step.enabled:
			EventBus.toast.emit("Thiếu lễ vật. Nam không thể làm tiếp nghi thức.")
		var used := [false]
		step.used.connect(func(_p: Node3D): used[0] = true, CONNECT_ONE_SHOT)
		if GameState.debug_autoplay:
			if step.enabled:
				step.interact(GameState.player)
			else:
				lamp.interact(GameState.player)
		while active():
			if not await wait_until(func(): return used[0] or abandoned[0]):
				return
			if not abandoned[0]:
				break
			var leave := await choose("Rời bàn thờ khi đèn vẫn tắt?", ["Tiếp tục nghi thức", "Rời đi"],
				0 if good_run() else 1)
			if not active() or leave == 1:
				return
			abandoned[0] = false
		step.enabled = false
		AudioDirector.play_sfx(sounds[i])
		GameState.complete_objective(offering_steps[i])
		if i == 1:
			award("ch4_offering")
	lamp.used.disconnect(cancel)
	lamp.enabled = false
	var name_choice := await choose("Gọi tên người trông đèn", ["Tuấn", "Bà Sáu", "Ông Đèn", "Im lặng"],
		0 if good_run() else 1)
	if not active():
		return
	GameState.complete_objective("ritual_name")
	if name_choice == 0:
		award("ch4_called_name", 2)
	lamp.enabled = true
	lamp.prompt = "Thắp đèn dầu"
	if not await wait_use("Interactables/Ritual_Lamp"):
		return
	var light_choice := await choose("Nam đưa tay về phía ngọn đèn dầu.",
		["Thắp đèn", "Rời đi khi đèn vẫn tắt"], 0)
	if not active() or light_choice != 0:
		return
	lamp.enabled = false
	AudioDirector.play_sfx("match_strike")
	GameState.set_flag("shrine_lamp_relit")
	GameState.complete_objective("ritual_light")
	cutscene_begin("ritual_end", "cam_shrine_wide")
	var shrine_lamp := level.find_child("ShrineLamp", true, false) as Light3D
	if shrine_lamp:
		shrine_lamp.show()
	if name_choice == 0:
		await say(["ch4_nam_01"])
	tuan.deactivate()
	cutscene_end("ritual_end")

func _ending() -> void:
	await ChapterDirector.run_script(ENDING_PATH % GameState.compute_ending().to_lower())
