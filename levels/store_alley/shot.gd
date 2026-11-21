extends SceneTree
## godot --path . -s res://levels/store_alley/shot.gd -- --shot=/tmp/store.png --cam=cam_store_wide --preset=night_store

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var options := {"shot": "", "cam": "cam_store_wide", "preset": "night_store"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var parts := arg.substr(2).split("=", true, 1)
			if options.has(parts[0]):
				options[parts[0]] = parts[1]
	if options.shot.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Pass --shot=<png> and run with a renderer (not --headless).")
		quit(1)
		return
	var level: Node3D = load("res://levels/store_alley/store_alley.tscn").instantiate()
	root.add_child(level)
	if not level.has_node("Presets/" + options.preset):
		push_error("Unknown lighting preset: " + options.preset)
		quit(1)
		return
	level.apply_preset(options.preset)
	var marker: Node3D = level.get_marker(options.cam)
	if marker is Camera3D:
		marker.make_current()
	else:
		if marker == null:
			marker = level.get_spawn(options.cam)
		if marker == null:
			push_error("Unknown camera marker or spawn: " + options.cam)
			quit(1)
			return
		var camera := Camera3D.new()
		level.add_child(camera)
		camera.global_transform = marker.global_transform
		if marker is Marker3D and marker.get_parent().name == &"Spawns":
			camera.global_position += Vector3.UP * 1.62
		camera.make_current()
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(options.shot)
	if error != OK:
		push_error("Could not save %s: %s" % [options.shot, error_string(error)])
	else:
		print("Saved %s (%d × %d)" % [options.shot, image.get_width(), image.get_height()])
	_finish.call_deferred(level, 0 if error == OK else 1)

func _finish(level: Node3D, code: int) -> void:
	level.queue_free()
	root.get_node("AudioDirector").stop_all_ambience(0.0)
	await process_frame
	await process_frame
	load("res://render/psx_apply.gd").clear_cache()
	quit(code)
