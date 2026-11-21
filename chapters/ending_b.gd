extends ChapterScript

func run(_from_checkpoint := "") -> void:
	level = ChapterDirector.current_level as LevelBase
	cutscene_begin("ending_b", "cam_streetlight_low")
	var tuan := node("Entities/GazerTuan") as Gazer
	if tuan == null:
		return
	tuan.manual_tick = true
	tuan.activate()
	var lamp := level.find_child("ShrineLamp", true, false) as Light3D
	if lamp and lamp.visible:
		for on in [false, true, false]:
			lamp.visible = on
			await wait(0.24)
	await say(["endB_tuan_01", "endB_tuan_02"])
	if not active():
		return
	var mark := level.get_marker("tuan_final")
	tuan.body.play_anim("walk")
	var walk := create_tween()
	walk.tween_property(tuan, "global_position", tuan.global_position + Vector3(-2.0, 0, 2.0),
		0.05 if GameState.debug_autoplay else 1.75)
	await walk.finished
	tuan.deactivate()
	RenderSettings.set_static(0.62)
	if mark:
		var nam := LevelKit.place(level, EntityBase.find_char_model("nam"), mark, "NamOnWatch")
		PSXApply.apply_to(nam)
		var stretch := create_tween()
		stretch.tween_property(nam, "scale:y", 1.2, 0.05 if GameState.debug_autoplay else 1.4)
	await wait(1.6)
	await card("Ba tháng sau")
	RenderSettings.set_static(0.0)
	if not await travel("store_alley", "default", "night_store", "night", 0, 30):
		return
	var gazer := node("Entities/Gazer") as Gazer
	if gazer == null:
		return
	gazer.body.build(EntityBase.find_char_model("nam"))
	gazer.body.play_anim("idle")
	gazer.body.scale.y = 1.2
	gazer.manual_tick = true
	gazer.activate()
	cutscene_begin("ending_b_shift", "cam_outside_glass")
	AudioDirector.play_sfx("scanner_beep")
	await say(["endB_new_01"])
	if not active():
		return
	await card("ĐÈN ĐƯỜNG CUỐI NGÕ", "Ca trực vĩnh viễn")
	AudioDirector.stop_all_ambience()
	AudioDirector.play_music("music_ending_b")
	await Credits.roll(get_tree(), "B", 32.0, self)
	finish_story("B")
