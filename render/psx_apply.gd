class_name PSXApply
extends RefCounted
## Converts StandardMaterial3D/ORMMaterial3D (e.g. from imported .glb) to PSX ShaderMaterials.
##
##   func _ready() -> void:
##       PSXApply.apply_to(self)                       # whole level
##       PSXApply.apply_to($Store, {"floor_affine_mult": 0.25})
##
## Rules (matched on lower-case material resource_name + node name + mesh surface name):
##   "glass" (e.g. "store_glass")  -> psx_transparent (tint = albedo colour; default alpha 0.18)
##   "emit" / "sign" ("tube_emit") -> psx_unlit (signs, screens, tubes)
##   "floor" "ground" "road" "san_" -> affine_mult = floor_affine_mult (big planes warp a lot)
##   "face"                         -> psx_face
##   "cut" ("fence_cut")            -> alpha scissor cutout
##   material unshaded             -> psx_unlit;  cull disabled -> double-sided variant
##   alpha scissor / hash / blend  -> alpha scissor (unless glass)
##   emission enabled              -> emission texture/colour/energy kept
## Albedo texture + colour, uv1 scale/offset and vertex-colour use are preserved. Converted
## materials are cached by (texture, colour, flags) so shared source materials stay shared.
## Surfaces get *override* materials, so the imported Mesh resources are never mutated.
## A node with meta "psx_skip" = true (and its children) is left alone.
##
## opts: affine_mult (float, default 1.0), floor_affine_mult (0.3), unlit_all (bool),
##       glass_tint (Color), skip (Array of node names), fog_mult (float), color_reduce (bool)

# Keys match at the start of a word (preceded by start or a non-letter): "store_glass" and
# "signboard" match, "design" / "surface" do not.
const GLASS_KEYS := ["glass"]
const EMIT_KEYS := ["emit", "sign"]
const FLOOR_KEYS := ["floor", "ground", "road", "san_", "pavement", "terrain"]
const FACE_KEYS := ["face"]
const CUT_KEYS := ["cut"]   # "fence_cut" -> alpha scissor cutout (Track C1 naming)

static var _cache: Dictionary = {}
static var _word_re: Dictionary = {}

## Walk `root` and every descendant. Returns the number of surfaces converted.
static func apply_to(root: Node, opts := {}) -> int:
	if root == null:
		return 0
	var count := 0
	var stack: Array[Node] = [root]
	var skip: Array = opts.get("skip", [])
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.get_meta("psx_skip", false) or skip.has(String(n.name)):
			continue
		if n is MeshInstance3D:
			count += _apply_mesh_instance(n, opts)
		elif n is CSGShape3D:
			count += _apply_csg(n, opts)
		elif n is SpriteBase3D:
			(n as SpriteBase3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		elif n is Label3D:
			(n as Label3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		for c in n.get_children():
			stack.push_back(c)
	return count

## Convert one material (returns the input unchanged if it is not a BaseMaterial3D).
static func convert_material(src: Material, hint_name := "", opts := {}) -> Material:
	if not (src is BaseMaterial3D):
		return src
	var m := src as BaseMaterial3D
	var name := (m.resource_name + " " + hint_name).to_lower()
	var popts := {}
	var glass := _has_any(name, GLASS_KEYS)
	var emit := _has_any(name, EMIT_KEYS)
	var unlit: bool = emit or opts.get("unlit_all", false) or m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
	var tex: Texture2D = m.albedo_texture
	if glass:
		popts.transparent = true
		var t: Color = opts.get("glass_tint", m.albedo_color)
		if not opts.has("glass_tint") and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			t.a = 0.18
		popts.tint = t
	else:
		if _has_any(name, FACE_KEYS) and not unlit:
			popts.face = true
		elif unlit:
			popts.unlit = true
		popts.tint = m.albedo_color
		if m.cull_mode == BaseMaterial3D.CULL_DISABLED:
			popts.double_sided = true
		match m.transparency:
			BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				popts.alpha_scissor = m.alpha_scissor_threshold
			BaseMaterial3D.TRANSPARENCY_ALPHA_HASH, BaseMaterial3D.TRANSPARENCY_ALPHA, \
			BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
				popts.alpha_scissor = 0.5
		if _has_any(name, CUT_KEYS) and not popts.has("alpha_scissor"):
			popts.alpha_scissor = 0.5
		if m.vertex_color_use_as_albedo:
			popts.vertex_color = true
		if m.emission_enabled and not unlit:
			popts.emission = m.emission_texture if m.emission_texture else m.emission
			popts.emission_strength = m.emission_energy_multiplier
			if m.emission_texture == null:
				popts.emission_ignore_albedo = true
		elif unlit and m.emission_enabled:
			popts.emission = maxf(1.0, m.emission_energy_multiplier)
	if m.uv1_scale != Vector3.ONE:
		popts.uv_scale = Vector2(m.uv1_scale.x, m.uv1_scale.y)
	if m.uv1_offset != Vector3.ZERO:
		popts.uv_offset = Vector2(m.uv1_offset.x, m.uv1_offset.y)
	var aff: float = opts.get("affine_mult", 1.0)
	if _has_any(name, FLOOR_KEYS):
		aff = opts.get("floor_affine_mult", 0.3)
	if aff != 1.0:
		popts.affine_mult = aff
	if opts.has("fog_mult"):
		popts.fog_mult = opts.fog_mult
	if opts.has("color_reduce"):
		popts.color_reduce = opts.color_reduce
	var key := "%d|%s" % [tex.get_instance_id() if tex else 0, var_to_str(popts)]
	if _cache.has(key):
		return _cache[key]
	var out := PSXMaterialFactory.make(tex, popts)
	out.resource_name = "psx_" + m.resource_name
	_cache[key] = out
	return out

static func clear_cache() -> void:
	_cache.clear()

static func _apply_mesh_instance(mi: MeshInstance3D, opts: Dictionary) -> int:
	var count := 0
	var node_name := String(mi.name)
	if mi.material_override is BaseMaterial3D:
		mi.material_override = convert_material(mi.material_override, node_name, opts)
		count += 1
	var mesh := mi.mesh
	if mesh == null or mi.material_override != null:
		return count
	for i in mesh.get_surface_count():
		var mat := mi.get_surface_override_material(i)
		if mat == null:
			mat = mesh.surface_get_material(i)
		var hint := node_name
		if mesh is ArrayMesh:
			hint += " " + (mesh as ArrayMesh).surface_get_name(i)
		if mat == null:
			mat = _default_for(hint, opts)
			mi.set_surface_override_material(i, mat)
			count += 1
		elif mat is BaseMaterial3D:
			mi.set_surface_override_material(i, convert_material(mat, hint, opts))
			count += 1
	return count

static func _apply_csg(csg: CSGShape3D, opts: Dictionary) -> int:
	if "material" in csg and csg.get("material") is BaseMaterial3D:
		csg.set("material", convert_material(csg.get("material"), String(csg.name), opts))
		return 1
	return 0

static func _default_for(hint: String, opts: Dictionary) -> Material:
	var sm := StandardMaterial3D.new()
	sm.resource_name = "default"
	sm.albedo_color = Color(0.8, 0.8, 0.8)
	return convert_material(sm, hint, opts)

static func _has_any(s: String, keys: Array) -> bool:
	for k in keys:
		if not s.contains(k):
			continue
		if not _word_re.has(k):
			var re := RegEx.new()
			re.compile("(^|[^a-z])" + k)
			_word_re[k] = re
		if (_word_re[k] as RegEx).search(s):
			return true
	return false
