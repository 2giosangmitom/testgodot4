class_name MinigameUtil
extends RefCounted
## Static helpers shared by the minigames: VND formatting, primitive placeholder meshes,
## low-res diegetic labels, axis parsing and small procedural PSX textures.

const LAYER_WORLD := 1
const LAYER_INTERACTABLE := 4
const LAYER_PICKUP := 32

## 15000 -> "15.000đ"
static func format_vnd(amount: int) -> String:
	var neg := amount < 0
	var s := str(absi(amount))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if neg else "") + out + "đ"

## "+X" / "-y" / "z" -> unit vector (default +Z).
static func axis_vector(axis: String) -> Vector3:
	var a := axis.strip_edges().to_upper()
	var sgn := -1.0 if a.begins_with("-") else 1.0
	a = a.trim_prefix("+").trim_prefix("-")
	match a:
		"X": return Vector3(sgn, 0, 0)
		"Y": return Vector3(0, sgn, 0)
		_: return Vector3(0, 0, sgn)

## Looks for a `barcode_axis` property or metadata on `node` and its descendants and returns the
## axis expressed in `relative_to`'s local space. Returns Vector3.ZERO when nothing is found.
static func find_barcode_axis(node: Node, relative_to: Node3D) -> Vector3:
	var found: Node = null
	var axis_str := ""
	var stack: Array[Node] = [node]
	while not stack.is_empty() and found == null:
		var n: Node = stack.pop_front()
		if n.has_meta("barcode_axis"):
			found = n
			axis_str = str(n.get_meta("barcode_axis"))
		elif n.has_meta("extras") and n.get_meta("extras") is Dictionary and n.get_meta("extras").has("barcode_axis"):
			# glTF custom properties imported by Godot live in the "extras" meta dictionary.
			found = n
			axis_str = str(n.get_meta("extras")["barcode_axis"])
		elif "barcode_axis" in n and typeof(n.get("barcode_axis")) == TYPE_STRING and n.get("barcode_axis") != "":
			found = n
			axis_str = n.get("barcode_axis")
		else:
			stack.append_array(n.get_children())
	if found == null:
		return Vector3.ZERO
	var v := axis_vector(axis_str)
	if found is Node3D and relative_to and found != relative_to:
		# Products build their visuals before they are added to the tree. Compose the
		# local bases along the model hierarchy instead of querying global transforms.
		var ancestor := found
		var basis := Basis.IDENTITY
		while ancestor != null and ancestor != relative_to:
			if ancestor is Node3D:
				basis = (ancestor as Node3D).basis * basis
			ancestor = ancestor.get_parent()
		if ancestor == relative_to:
			v = (basis * v).normalized()
		elif found.is_inside_tree() and relative_to.is_inside_tree():
			v = (relative_to.global_basis.inverse() * (found as Node3D).global_basis * v).normalized()
	return v

static func make_mat(color: Color, unshaded := false, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

static func box(size: Vector3, color: Color, pos := Vector3.ZERO, unshaded := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = make_mat(color, unshaded)
	mi.position = pos
	return mi

static func cylinder(radius: float, height: float, color: Color, pos := Vector3.ZERO, segments := 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = make_mat(color)
	mi.position = pos
	return mi

## Static furniture block with a world-layer collider (placeholders only).
static func solid_box(parent: Node, size: Vector3, color: Color, pos: Vector3, name := "") -> StaticBody3D:
	var body := StaticBody3D.new()
	if name != "":
		body.name = name
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	body.position = pos
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	body.add_child(box(size, color))
	parent.add_child(body)
	return body

static func add_box_collider(body: CollisionObject3D, size: Vector3, offset := Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = offset
	body.add_child(cs)
	return cs

## Low-res diegetic text (pixelated: small font size, nearest filter, scaled up).
static func label(text: String, font_size := 16, pixel := 0.004, color := Color(0.9, 0.9, 0.85), font: Font = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	if font:
		l.font = font
	return l

## Black/white stripe texture used as a placeholder barcode.
static func barcode_texture() -> ImageTexture:
	var w := 24
	var h := 12
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	var pattern := [1, 0, 1, 1, 0, 1, 0, 0, 1, 1, 1, 0, 1, 0, 1, 1, 0, 0, 1, 0]
	for x in range(2, w - 2):
		if pattern[(x - 2) % pattern.size()] == 1:
			for y in range(1, h - 3):
				img.set_pixel(x, y, Color.BLACK)
	return ImageTexture.create_from_image(img)

## Soft irregular blob (alpha) used for dirt stains. Deterministic per seed.
static func stain_texture(seed_value: int, tint := Color(0.22, 0.17, 0.1)) -> ImageTexture:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var blobs := []
	for i in 6:
		blobs.append([Vector2(rng.randf_range(10, 22), rng.randf_range(10, 22)), rng.randf_range(4, 9)])
	for y in size:
		for x in size:
			var a := 0.0
			for b in blobs:
				var d: float = Vector2(x, y).distance_to(b[0])
				a = maxf(a, clampf(1.0 - d / b[1], 0.0, 1.0))
			a = clampf(a * 1.6 + rng.randf_range(-0.15, 0.15), 0.0, 1.0)
			if a < 0.2:
				a = 0.0
			img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, snappedf(a, 0.25)))
	return ImageTexture.create_from_image(img)

## Instantiates a swappable model scene, or returns null.
static func instance_model(scene: PackedScene) -> Node3D:
	if scene == null:
		return null
	var n := scene.instantiate()
	return n as Node3D

static func load_if_exists(path: String) -> PackedScene:
	if path != "" and ResourceLoader.exists(path):
		return load(path) as PackedScene
	return null

## Natural sort of nodes by name ("slot_2" < "slot_10").
static func sort_by_name(nodes: Array) -> Array:
	nodes.sort_custom(func(a: Node, b: Node): return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return nodes

## Plays a positional sfx when inside the tree, else a 2D one (AudioDirector tolerates missing files).
static func sfx(name: String, at: Node3D, volume_db := 0.0, pitch := 1.0) -> void:
	if at and at.is_inside_tree():
		AudioDirector.play_sfx_3d(name, at.global_position, volume_db, pitch)
	else:
		AudioDirector.play_sfx(name, volume_db, pitch)
