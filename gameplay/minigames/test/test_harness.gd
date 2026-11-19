extends Node3D
## Root script of the minigame test scenes. Builds a plain lit room, starts every top-level
## minigame, and supports a screenshot mode:
##   godot --path . res://gameplay/minigames/test/test_all.tscn -- --shot=/abs/out.png
##     [--view=<name of a Views/ child>] [--prep=<minigame node name>] [--shot-frames=N]
## --view teleports the player to Views/<name> and aims at its child "Look" (if any).
## --prep calls debug_shot_prep(player) on that minigame (puts it in an interesting state).

@export var room_size := Vector3(7, 2.8, 7)
@export var start_minigames := true
@export var ambient := Color(0.32, 0.33, 0.3)

var player: Node3D

func _ready() -> void:
	_build_room()
	player = get_node_or_null("Player")
	if player:
		GameState.player = player
	var args := _args()
	if start_minigames:
		for mg in get_tree().get_nodes_in_group("minigame"):
			if _is_top_level_minigame(mg):
				mg.start()
	if args.has("view"):
		set_view(args["view"])
	elif has_node("Views/main"):
		set_view("main")
	if args.has("prep"):
		await get_tree().process_frame
		await get_tree().physics_frame
		for n in args["prep"].split(","):
			var mg := find_child(n, true, false)
			if mg and mg.has_method("debug_shot_prep"):
				mg.debug_shot_prep(player)
	if args.has("shot"):
		_take_shot(args["shot"], int(args.get("shot-frames", "45")))

func _is_top_level_minigame(mg: Node) -> bool:
	var p := mg.get_parent()
	while p:
		if p is MinigameBase:
			return false
		p = p.get_parent()
	return true

func set_view(view_name: String) -> void:
	var v := get_node_or_null("Views/" + view_name) as Node3D
	if v == null or player == null:
		return
	player.global_position = v.global_position
	var look := v.get_node_or_null("Look") as Node3D
	if look and player.has_method("aim_at"):
		player.aim_at(look.global_position)
	elif player.has_method("teleport"):
		player.teleport(v.global_transform)

func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out

func _take_shot(path: String, frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("shot saved: ", path, " err=", err, " size=", img.get_size())
	get_tree().quit()

func _build_room() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.035)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = ambient
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var room := Node3D.new()
	room.name = "Room"
	add_child(room)
	var s := room_size
	var floor_body := MinigameUtil.solid_box(room, Vector3(s.x, 0.1, s.z), Color(0.5, 0.5, 0.47), Vector3(0, -0.05, 0), "Floor")
	var fm := floor_body.get_child(1) as MeshInstance3D
	(fm.mesh as BoxMesh).subdivide_width = 12
	(fm.mesh as BoxMesh).subdivide_depth = 12
	# checker tiles via a tiny nearest texture
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color(0.62, 0.62, 0.58)); img.set_pixel(1, 1, Color(0.62, 0.62, 0.58))
	img.set_pixel(1, 0, Color(0.48, 0.49, 0.46)); img.set_pixel(0, 1, Color(0.48, 0.49, 0.46))
	var mat := fm.material_override as StandardMaterial3D
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.uv1_scale = Vector3(s.x * 1.5, s.z * 1.5, 1) * 0.5
	var wall_c := Color(0.62, 0.64, 0.58)
	MinigameUtil.solid_box(room, Vector3(s.x, s.y, 0.1), wall_c, Vector3(0, s.y * 0.5, -s.z * 0.5))
	MinigameUtil.solid_box(room, Vector3(s.x, s.y, 0.1), wall_c, Vector3(0, s.y * 0.5, s.z * 0.5))
	MinigameUtil.solid_box(room, Vector3(0.1, s.y, s.z), wall_c.darkened(0.1), Vector3(-s.x * 0.5, s.y * 0.5, 0))
	MinigameUtil.solid_box(room, Vector3(0.1, s.y, s.z), wall_c.darkened(0.1), Vector3(s.x * 0.5, s.y * 0.5, 0))
	MinigameUtil.solid_box(room, Vector3(s.x, 0.1, s.z), Color(0.4, 0.4, 0.4), Vector3(0, s.y + 0.05, 0))
	# fluorescent-ish ceiling light, in the group the light switch test toggles
	var light := OmniLight3D.new()
	light.name = "CeilingLight"
	light.light_color = Color(0.92, 1.0, 0.9)
	light.light_energy = 1.4
	light.omni_range = maxf(s.x, s.z) * 1.2
	light.omni_attenuation = 0.6
	light.position = Vector3(0, s.y - 0.3, 0)
	light.add_to_group("room_lights")
	light.add_to_group("flicker_lights")
	room.add_child(light)
