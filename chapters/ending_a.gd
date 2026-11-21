extends ChapterScript

func run(_from_checkpoint := "") -> void:
	level = ChapterDirector.current_level as LevelBase
	cutscene_begin("ending_a", "cam_streetlight_low")
	var tuan := node("Entities/GazerTuan") as Gazer
	if tuan == null:
		return
	tuan.manual_tick = true
	tuan.activate()
	tuan.body.set_shape("long_arms", 0.0)
	tuan.body.set_shape("face_distort", 0.0)
	EventBus.lights_set.emit("streetlight", false)
	var tween := create_tween()
	tween.tween_property(tuan.body, "scale:y", 0.83, 0.05 if GameState.debug_autoplay else 2.2)
	await say(["endA_tuan_01", "endA_tuan_02"])
	if not active():
		return
	tuan.body.play_anim("walk")
	var walk := create_tween()
	walk.tween_property(tuan, "global_position", tuan.global_position + tuan.global_basis.z * 4.5,
		0.05 if GameState.debug_autoplay else 3.0)
	await walk.finished
	tuan.deactivate()
	level.apply_preset("dawn")
	GameState.set_clock(5, 45)
	AudioDirector.play_ambience("amb_street_day", "base", -6.0, 2.0)
	cutscene_end("ending_a")
	objective("dawn_home", "Đi về phía đầu ngõ")
	if not await wait_trigger("trig_lane_enter"):
		return
	GameState.complete_objective("dawn_home")
	npc("Hung", true)
	cutscene_begin("ending_a_hung", "cam_lane_end")
	await say(["endA_hung_01", "endA_nam_01", "endA_hung_02"])
	camera("cam_shrine_wide")
	await wait(2.0)
	if not active():
		return
	await card("ĐÈN ĐƯỜNG CUỐI NGÕ", "Bình minh")
	AudioDirector.stop_all_ambience()
	AudioDirector.play_music("music_ending_a")
	await Credits.roll(get_tree(), "A", 32.0, self)
	finish_story("A")
