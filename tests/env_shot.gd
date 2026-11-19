extends Node3D
## Visual check of an env glb with PSX materials.
## godot --path . res://tests/env_shot.tscn -- --glb=store --cam=cam_store_wide --preset=night_store --shot=/abs/out.png
## --glb accepts one or more comma separated names from assets/models/env/. --cam is a MARKER_<name> node.

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var root := Node3D.new()
	root.name = "Env"
	add_child(root)
	for g in String(args.get("glb", "store")).split(","):
		var ps: PackedScene = load("res://assets/models/env/%s.glb" % g)
		root.add_child(ps.instantiate())
	PSXApply.apply_to(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.47, 0.5)
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	add_child(env)
	RenderSettings.set_fog_preset(args.get("preset", "night_store"), 0.0)
	var cam := Camera3D.new()
	cam.fov = 70
	cam.near = 0.05
	add_child(cam)
	var m := root.find_child("MARKER_" + args.get("cam", "cam_store_wide"), true, false) as Node3D
	if m:
		cam.global_transform = m.global_transform
	else:
		push_warning("marker not found; known: %s" % [_markers(root)])
	cam.current = true
	for l in root.find_children("MARKER_light*", "Node3D", true, false).slice(0, 6):
		var o := OmniLight3D.new()
		o.omni_range = 6.0
		o.light_energy = 1.2
		add_child(o)
		o.global_position = l.global_position
	var out: String = args.get("shot", "")
	if out != "":
		for i in 45:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out)
		get_tree().quit()

func _markers(n: Node) -> Array:
	return n.find_children("MARKER_*", "Node3D", true, false).map(func(x): return x.name)
