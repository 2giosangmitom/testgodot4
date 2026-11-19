extends Node3D
## Visual test for the PSX pipeline: a tiny night street + store front built from primitives with
## procedural textures. Exercises PSXApply (StandardMaterial3D -> PSX), PSXMaterialFactory,
## FlickerLight, FixedCamera and PostFX.
## User args (after `--`): --preset=<fog preset>  --static=<0..1>  --distort=<0..1>
##   --orbit=<deg/s>  --angle=<deg>  --view=street|face  --no-post  --no-affine
## Keys: F flicker burst, O/P lights off/on, S toggle static.

var cam: FixedCamera
var head: MeshInstance3D
var orbit_speed := 9.0
var angle := 0.0
var street_view := false
var face_view := false
var focus: Node3D
var face_distort := -1.0
var _t := 0.0

func _ready() -> void:
	var args := _args()
	var preset: String = args.get("preset", "dusk")
	orbit_speed = float(args.get("orbit", "9"))
	angle = float(args.get("angle", "20"))
	street_view = args.get("view", "") == "street"
	face_view = args.get("view", "") == "face"
	face_distort = float(args.get("distort", "-1"))

	_env()
	_build_street()
	_build_store()
	_build_props()
	_build_lights()
	var n := PSXApply.apply_to(self)
	print("[test_psx] PSXApply converted %d surfaces" % n)

	cam = FixedCamera.new()
	cam.fov = 65.0
	cam.fov_jitter = 0.15
	cam.track_lag = 6.0
	add_child(cam)
	focus = Node3D.new()
	focus.position = Vector3(0, 1.3, 1.0)
	add_child(focus)
	cam.target_offset = Vector3.ZERO
	cam.track_target(focus)
	_place_cam()
	cam.cut_to()

	if not args.has("no-post"):
		add_child(load("res://render/post_fx.tscn").instantiate())

	var rs := get_node_or_null("/root/RenderSettings")
	if rs:
		rs.set_fog_preset(preset, 0.0)
		if args.has("fogcheck"):   # everything beyond 3 m must equal the clear colour exactly
			rs.set_fog(1.0, 3.0, Color(0.5, 0.3, 0.2), 0.0)
		if args.has("static"):
			rs.set_static(float(args.static))
	if args.has("snap"):   # e.g. --snap=160 for extra wobble, --snap=100000 to disable
		var r := float(args.snap)
		RenderingServer.global_shader_parameter_set("psx_snap_resolution", Vector2(r, r * 0.75))
	if args.has("no-affine"):
		RenderingServer.global_shader_parameter_set("psx_affine_strength", 0.0)

func _process(delta: float) -> void:
	_t += delta
	angle += orbit_speed * delta
	_place_cam()
	if head:
		var d := face_distort if face_distort >= 0.0 else clampf(sin(_t * 0.8) * 1.2, 0.0, 1.0)
		(head.get_surface_override_material(0) as ShaderMaterial).set_shader_parameter("distort", d)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		var ev := get_node_or_null("/root/EventBus")
		match e.keycode:
			KEY_F:
				ev.lights_flicker.emit("test_lights", 1.2)
			KEY_O:
				ev.lights_set.emit("test_lights", false)
			KEY_P:
				ev.lights_set.emit("test_lights", true)
			KEY_S:
				get_node("/root/RenderSettings").set_static(0.0 if get_node("/root/RenderSettings").get_static() > 0.0 else 0.7)

func _place_cam() -> void:
	if face_view:
		cam.position = Vector3(0.4 + sin(deg_to_rad(angle)) * 0.3, 1.62, -3.1)
		focus.position = Vector3(0.4, 1.6, -2.2)
		return
	if street_view:
		# Looking down the street into the fog, slowly panning.
		cam.position = Vector3(0.0, 1.62, -1.0)
		focus.position = Vector3(sin(deg_to_rad(angle)) * 3.0, 1.2, -12.0)
		return
	# Slow back-and-forth arc in front of the store (stays between the building rows).
	var a := PI + deg_to_rad(35.0) * sin(deg_to_rad(angle))
	cam.position = Vector3(sin(a) * 6.5, 1.62, cos(a) * 6.5 - 1.0)

func _args() -> Dictionary:
	var d := {}
	for a in OS.get_cmdline_user_args():
		var s := a.trim_prefix("--")
		var i := s.find("=")
		if i >= 0:
			d[s.substr(0, i)] = s.substr(i + 1)
		else:
			d[s] = "1"
	return d

# ---------------------------------------------------------------- scene

func _env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.33, 0.40)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _std(tex: Texture2D, mat_name: String, color := Color.WHITE, uv := Vector2.ONE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	m.albedo_texture = tex
	m.albedo_color = color
	m.uv1_scale = Vector3(uv.x, uv.y, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # PSXApply must force nearest
	return m

func _box(name_: String, size: Vector3, pos: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	return mi

func _build_street() -> void:
	var road := MeshInstance3D.new()
	road.name = "road"
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	pm.subdivide_width = 7
	pm.subdivide_depth = 7
	road.mesh = pm
	road.set_surface_override_material(0, _std(_tex_checker(64, Color(0.30, 0.30, 0.32), Color(0.22, 0.22, 0.24)), "road_asphalt", Color.WHITE, Vector2(20, 20)))
	add_child(road)
	var brick := _std(_tex_brick(), "wall_brick", Color.WHITE, Vector2(6, 2))
	# Building rows on both sides receding into the fog.
	for i in 8:
		var z := -2.0 - i * 4.2
		_box("bld_l%d" % i, Vector3(3.0, 4.0 + (i % 3) * 1.4, 4.0), Vector3(-6.0, 2.0 + (i % 3) * 0.7, z), brick)
		_box("bld_r%d" % i, Vector3(3.0, 3.5 + ((i + 1) % 3) * 1.2, 4.0), Vector3(6.0, 1.75 + ((i + 1) % 3) * 0.6, z), brick)
	# Poles marching away to show fog falloff.
	var pole := _std(null, "pole_metal", Color(0.45, 0.45, 0.42))
	for i in 10:
		_box("pole%d" % i, Vector3(0.15, 4.5, 0.15), Vector3(2.8, 2.25, 2.0 - i * 3.5), pole)

func _build_store() -> void:
	var store := Node3D.new()
	store.name = "Store"
	store.position = Vector3(0, 0, 3.0)
	add_child(store)
	var wall := _std(_tex_tiles(), "store_wall", Color(0.85, 0.85, 0.8), Vector2(4, 2))
	_box("store_back", Vector3(6.0, 3.0, 0.2), Vector3(0, 1.5, 2.0), wall, store)
	_box("store_side_l", Vector3(0.2, 3.0, 4.0), Vector3(-3.0, 1.5, 0.0), wall, store)
	_box("store_side_r", Vector3(0.2, 3.0, 4.0), Vector3(3.0, 1.5, 0.0), wall, store)
	_box("store_roof", Vector3(6.2, 0.2, 4.2), Vector3(0, 3.0, 0.0), wall, store)
	_box("store_floor", Vector3(6.0, 0.05, 4.0), Vector3(0, 0.025, 0.0), _std(_tex_checker(32, Color(0.85, 0.85, 0.82), Color(0.55, 0.6, 0.58)), "store_floor_tile", Color.WHITE, Vector2(6, 4)), store)
	# Front glass (name -> transparent).
	var glass := _std(null, "store_glass", Color(0.7, 0.85, 0.8, 0.2))
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_box("front_glass", Vector3(4.6, 2.4, 0.05), Vector3(0.6, 1.3, -2.0), glass, store)
	_box("front_frame", Vector3(0.12, 2.6, 0.12), Vector3(-1.75, 1.3, -2.0), _std(null, "frame_alu", Color(0.6, 0.6, 0.62)), store)
	# Sign (name -> unlit).
	var sign_m := _std(_tex_sign(), "sign_store", Color(1, 1, 1))
	var sign_mi := MeshInstance3D.new()
	sign_mi.name = "sign"
	var q := QuadMesh.new()
	q.size = Vector2(4.8, 1.2)
	sign_mi.mesh = q
	sign_mi.position = Vector3(0, 3.5, -2.12)
	sign_mi.rotation_degrees.y = 180.0
	sign_mi.set_surface_override_material(0, sign_m)
	store.add_child(sign_mi)
	_box("sign_box", Vector3(5.0, 1.3, 0.15), Vector3(0, 3.5, -2.0), _std(null, "sign_frame", Color(0.2, 0.2, 0.22)), store)
	# Shelves inside.
	var shelf := _std(_tex_checker(16, Color(0.75, 0.3, 0.25), Color(0.25, 0.45, 0.7)), "shelf_goods", Color.WHITE, Vector2(4, 2))
	for i in 3:
		_box("shelf%d" % i, Vector3(0.5, 1.6, 2.6), Vector3(-1.6 + i * 1.6, 0.8, 0.4), shelf, store)
	# Fluorescent tube (unlit, emit_level driven by FlickerLight).
	var tube_m := _std(null, "tube_emit", Color(0.95, 1.0, 0.95))
	var tube := _box("tube", Vector3(1.2, 0.06, 0.1), Vector3(0, 2.85, -0.5), tube_m, store)
	var l := OmniLight3D.new()
	l.name = "StoreLight"
	l.light_color = Color(0.85, 1.0, 0.9)
	l.light_energy = 2.2
	l.omni_range = 7.0
	l.omni_attenuation = 0.8
	l.position = Vector3(0, 2.6, -0.5)
	store.add_child(l)
	var fl := FlickerLight.new()
	fl.mode = FlickerLight.Mode.DYING
	fl.groups = PackedStringArray(["test_lights"])
	fl.emissive_mesh = NodePath("../../tube")
	l.add_child(fl)

func _build_props() -> void:
	var crate := _std(_tex_crate(), "crate_wood", Color.WHITE)
	_box("crate_a", Vector3(0.8, 0.8, 0.8), Vector3(-1.8, 0.4, -1.2), crate)
	_box("crate_b", Vector3(0.6, 0.6, 0.6), Vector3(-1.7, 1.1, -1.1), crate)
	_box("crate_c", Vector3(0.8, 0.8, 0.8), Vector3(1.6, 0.4, -3.0), crate)
	# A figure with a face (PSXMaterialFactory directly) standing in the street.
	var body_m := PSXMaterialFactory.make(null, {"tint": Color(0.12, 0.12, 0.14)})
	var body := _box("figure_body", Vector3(0.5, 1.4, 0.3), Vector3(0.4, 0.7, -2.2), body_m)
	body.set_meta("psx_skip", true)
	head = MeshInstance3D.new()
	head.name = "figure_head"
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.36
	sm.radial_segments = 12
	sm.rings = 8
	head.mesh = sm
	head.position = Vector3(0.4, 1.6, -2.2)
	head.rotation_degrees.y = 180.0
	var ftex := _tex_face()
	head.set_surface_override_material(0, PSXMaterialFactory.make(ftex, {"face": true, "emission": 0.25}))
	head.set_meta("psx_skip", true)
	add_child(head)

func _build_lights() -> void:
	# Sodium streetlight.
	var lamp_m := _std(null, "lamp_emit", Color(1.0, 0.65, 0.3))
	_box("lamp_head", Vector3(0.5, 0.12, 0.25), Vector3(2.5, 4.4, -1.5), lamp_m)
	var s := OmniLight3D.new()
	s.name = "Sodium"
	s.light_color = Color(1.0, 0.62, 0.28)
	s.light_energy = 3.0
	s.omni_range = 9.0
	s.position = Vector3(2.3, 4.2, -1.5)
	add_child(s)
	var fs := FlickerLight.new()
	fs.mode = FlickerLight.Mode.SODIUM
	fs.groups = PackedStringArray(["test_lights", "street_lights"])
	fs.emissive_mesh = NodePath("../../lamp_head")
	s.add_child(fs)
	# Cold fluorescent spill on the left building.
	var f := OmniLight3D.new()
	f.light_color = Color(0.75, 0.9, 1.0)
	f.light_energy = 1.4
	f.omni_range = 6.0
	f.position = Vector3(-3.2, 2.6, -6.0)
	add_child(f)
	var ff := FlickerLight.new()
	ff.mode = FlickerLight.Mode.FLUORESCENT
	ff.groups = PackedStringArray(["test_lights"])
	f.add_child(ff)

# ---------------------------------------------------------------- textures

func _img_tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)

func _noise(x: int, y: int, seed_: int) -> float:
	var h := hash(Vector3i(x, y, seed_))
	return float(h & 0xffff) / 65535.0

func _tex_checker(n: int, a: Color, b: Color) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := n / 4
	for y in n:
		for x in n:
			var base := a if ((x / c) + (y / c)) % 2 == 0 else b
			img.set_pixel(x, y, base.darkened(_noise(x, y, 1) * 0.15))
	return _img_tex(img)

func _tex_brick() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var mortar := Color(0.55, 0.52, 0.48)
	for y in 64:
		var row := y / 8
		for x in 64:
			var xo := x + (8 if row % 2 == 1 else 0)
			var is_m := y % 8 == 0 or xo % 16 == 0
			var col := mortar if is_m else Color(0.52, 0.24, 0.17).lerp(Color(0.38, 0.18, 0.14), _noise(xo / 16, row, 2))
			img.set_pixel(x, y, col.darkened(_noise(x, y, 3) * 0.2))
	return _img_tex(img)

func _tex_tiles() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var line := x % 16 == 0 or y % 16 == 0
			img.set_pixel(x, y, Color(0.5, 0.52, 0.5) if line else Color(0.82, 0.84, 0.8).darkened(_noise(x, y, 4) * 0.1))
	return _img_tex(img)

func _tex_crate() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var edge: bool = x < 3 or y < 3 or x > 28 or y > 28 or abs(x - y) < 2
			var plank := Color(0.55, 0.4, 0.22).darkened(float((y / 6) % 2) * 0.12 + _noise(x, y, 5) * 0.12)
			img.set_pixel(x, y, Color(0.35, 0.24, 0.12) if edge else plank)
	return _img_tex(img)

func _tex_sign() -> ImageTexture:
	# 64x16 sign: green band, white blocky "24h" glyphs, sun-ish disc.
	var img := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.55, 0.35))
	for x in 64:
		img.set_pixel(x, 0, Color(1, 0.8, 0.2))
		img.set_pixel(x, 15, Color(1, 0.8, 0.2))
	var glyphs := ["111001010100", "001001010100", "111001110111", "100000010101", "111000010101"]
	for gy in glyphs.size():
		var row: String = glyphs[gy]
		for gx in row.length():
			if row[gx] == "1":
				for sy in 2:
					for sx in 2:
						img.set_pixel(24 + gx * 2 + sx, 3 + gy * 2 + sy, Color(1, 1, 1))
	for y in 16:
		for x in 16:
			if Vector2(x - 10, y - 8).length() < 4.5:
				img.set_pixel(x, y, Color(1.0, 0.75, 0.15))
	return _img_tex(img)

func _tex_face() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.78, 0.66, 0.56))
	for y in 64:
		for x in 64:
			img.set_pixel(x, y, img.get_pixel(x, y).darkened(_noise(x, y, 6) * 0.08))
	# Sphere UV wraps around: repeat the face 4x so one always looks at the camera.
	for base_u in [8, 24, 40, 56]:
		for side in [-3, 3]:
			for y in range(24, 31):
				for x in range(-2, 3):
					if Vector2(x, (y - 27) * 0.7).length() < 2.2:
						img.set_pixel(posmod(base_u + side + x, 64), y, Color(0.05, 0.03, 0.03))
		for x in range(-3, 4):
			for y in range(45, 47):
				img.set_pixel(posmod(base_u + x, 64), y, Color(0.3, 0.08, 0.08))
	return _img_tex(img)
