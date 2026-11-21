extends SceneTree
## Regression: a death resumes the same segment and restores its saved state.
## Run with a disposable XDG_DATA_HOME (see docs/playtest.md).

func _initialize() -> void:
	if OS.get_environment("XDG_DATA_HOME").is_empty() \
			or not OS.get_environment("XDG_DATA_HOME").get_file().begins_with("test-game-checkpoint-") \
			or FileAccess.file_exists("user://checkpoint.json"):
		push_error("checkpoint smoke needs a fresh test-game-checkpoint-* XDG_DATA_HOME")
		quit(1)
		return
	create_timer(15.0).timeout.connect(func():
		push_error("checkpoint smoke timed out")
		quit(1))
	await process_frame
	var director := root.get_node("ChapterDirector")
	var game := root.get_node("GameState")
	var bus := root.get_node("EventBus")
	var checkpoints: Array[String] = []
	bus.checkpoint_reached.connect(func(id: String): checkpoints.append(id))
	change_scene_to_file("res://ui/main_menu.tscn")
	await scene_changed
	current_scene._dismiss_warning()
	for button in current_scene.main_box.get_children():
		if button is Button and button.text == "Chơi mới":
			button.pressed.emit()
			break
	while checkpoints.is_empty():
		await process_frame
	if checkpoints != ["ch1_school"] or director.current_level.level_id != "school":
		push_error("New Game did not start chapter one")
		quit(1)
		return
	game.set_flag("has_oil")
	game.add_resolve(5, "fixture")
	director.start_chapter(4, "ch4_shrine")
	while checkpoints.size() < 2:
		await process_frame
	var old_level_id: int = director.current_level.get_instance_id()
	# Simulate progress made after the checkpoint was stored.
	game.add_resolve(2, "unsaved")
	game.set_flag("unsaved")
	bus.player_caught.emit("fixture", "test")
	await process_frame
	bus.entity_state_changed.emit("fixture", "caught_done")
	while checkpoints.size() < 3:
		await process_frame
	var passed: bool = checkpoints == ["ch1_school", "ch4_shrine", "ch4_shrine"] \
		and director.current_level.get_instance_id() != old_level_id \
		and game.resolve == 5 and game.get_flag("has_oil") and not game.get_flag("unsaved") \
		and not game.is_input_locked()
	print("new game and checkpoint smoke: ", "PASS" if passed else "FAIL")
	quit(0 if passed else 1)
