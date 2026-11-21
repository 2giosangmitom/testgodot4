extends SceneTree
## godot --path . -s res://levels/school/shot.gd -- --shot=/tmp/school.png --cam=cam_classroom --preset=day

const LEVEL := "res://levels/school/school.tscn"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var options := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var pair := arg.substr(2).split("=", true, 1)
			if pair.size() == 2:
				options[pair[0]] = pair[1]
	var path: String = options.get("shot", "")
	if path.is_empty() or DisplayServer.get_name() == "headless":
		printerr("school shot: run with a display and -- --shot=/path/to/image.png [--cam=<marker or spawn>] [--preset=day|night_ch3]")
		quit(1)
		return

	var level = load(LEVEL).instantiate()
	root.add_child(level)
	current_scene = level
	var preset: String = options.get("preset", "day")
	if not level.has_node("Presets/" + preset):
		printerr("school shot: unknown preset ", preset)
		await _finish(1)
		return
	if preset != level.default_preset:
		level.apply_preset(preset)
	if preset == "night_ch3":
		level.get_node("NPCs/BacTu").show()
		for crowd in level.get_node("Entities").get_children():
			crowd.activate()
	else:
		level.get_node("NPCs/Thay_Khai").show()
		level.get_node("NPCs/Linh").show()
		level.get_node("NPCs/Students").show()

	var camera_name: String = options.get("cam", "cam_courtyard")
	var marker: Node3D = level.get_marker(camera_name)
	if marker == null:
		marker = level.get_spawn(camera_name)
	if marker is Camera3D:
		marker.make_current()
	elif marker:
		var camera := Camera3D.new()
		level.add_child(camera)
		camera.global_transform = marker.global_transform
		if marker.get_parent().name == "Spawns":
			camera.global_position += Vector3.UP * 1.62
		camera.near = 0.04
		camera.fov = 72
		camera.make_current()
	else:
		printerr("school shot: unknown marker or spawn ", camera_name)
		await _finish(1)
		return

	level.add_child(load("res://render/post_fx.tscn").instantiate())
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png(path)
	if result != OK:
		printerr("school shot: cannot save ", path, ": ", error_string(result))
	else:
		print("school shot: ", path)
	await _finish(0 if result == OK else 1)


func _finish(code: int) -> void:
	root.get_node("AudioDirector").stop_all_ambience(0.0)
	await create_timer(1.6).timeout
	quit(code)
