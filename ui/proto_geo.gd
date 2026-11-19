class_name ProtoGeo
extends RefCounted
## Tiny helpers to build primitive geometry (test rooms, menu background) with PSX materials
## when res://render/psx_material_factory.gd exists (StandardMaterial3D otherwise).

const FACTORY := "res://render/psx_material_factory.gd"

static var _noise_tex: Texture2D

static func mat(color: Color, opts := {}) -> Material:
	if ResourceLoader.exists(FACTORY):
		var f: Script = load(FACTORY)
		var o: Dictionary = opts.duplicate()
		o["tint"] = color
		return f.make(opts.get("texture", noise_texture()), o)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = opts.get("texture", noise_texture())
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if opts.get("unlit", false):
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

## 32x32 grayscale value noise: gives flat surfaces a dirty PSX texture feel.
static func noise_texture() -> Texture2D:
	if _noise_tex:
		return _noise_tex
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	for y in 32:
		for x in 32:
			var v := 0.82 + rng.randf() * 0.18
			if (x + y * 3) % 17 == 0:
				v -= 0.08
			img.set_pixel(x, y, Color(v, v, v))
	_noise_tex = ImageTexture.create_from_image(img)
	return _noise_tex

static func box(parent: Node, size: Vector3, pos: Vector3, color: Color, collide := true, opts := {}) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	# vertex lighting needs vertices: ~1 per 0.6 m
	bm.subdivide_width = clampi(int(size.x / 0.6), 0, 24)
	bm.subdivide_height = clampi(int(size.y / 0.6), 0, 24)
	bm.subdivide_depth = clampi(int(size.z / 0.6), 0, 24)
	mi.mesh = bm
	mi.material_override = mat(color, opts)
	mi.position = pos
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		sb.add_child(cs)
		mi.add_child(sb)
		if opts.has("surface"):
			sb.set_meta("surface", opts.surface)
	parent.add_child(mi)
	return mi
