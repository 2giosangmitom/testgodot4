extends SceneTree
## godot --path . -s res://levels/dorm_shrine/shot.gd -- --shot=out.png --cam=cam_room --preset=night

func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var options := {"cam": "cam_shrine_wide", "preset": "ch4_night", "shot": "dorm_shrine.png"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var pair := arg.substr(2).split("=", true, 1)
			if pair.size() == 2 and options.has(pair[0]):
				options[pair[0]] = pair[1]
	if DisplayServer.get_name() == "headless":
		printerr("dorm_shrine shot: a graphical renderer is required")
		quit(1)
		return
	var level := (load("res://levels/dorm_shrine/dorm_shrine.tscn") as PackedScene).instantiate()
	if not level.has_method("apply_preset"):
		printerr("dorm_shrine shot: level script did not load")
		level.free()
		quit(1)
		return
	if options.preset not in ["night", "day", "ch4_night", "dawn"]:
		printerr("dorm_shrine shot: unknown preset ", options.preset)
		level.free()
		quit(1)
		return
	level.default_preset = options.preset
	root.add_child(level)
	current_scene = level
	var cam := level.get_node_or_null("Markers/" + options.cam) as Camera3D
	if cam == null:
		var spawn := level.get_node_or_null("Spawns/" + options.cam) as Marker3D
		if spawn == null:
			printerr("dorm_shrine shot: unknown camera or spawn ", options.cam)
			quit(1)
			return
		cam = Camera3D.new()
		level.add_child(cam)
		cam.global_transform = spawn.global_transform.translated(Vector3.UP * 1.62)
		cam.fov = 70
		cam.near = 0.035
	cam.make_current()
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(options.shot)
	if error == OK:
		print("Saved %s (%d × %d)" % [options.shot, image.get_width(), image.get_height()])
	else:
		printerr("dorm_shrine shot: could not save ", options.shot, " (", error_string(error), ")")
	root.get_node("AudioDirector").stop_all_ambience(0.0)
	await create_timer(0.15).timeout
	quit(0 if error == OK else 1)
