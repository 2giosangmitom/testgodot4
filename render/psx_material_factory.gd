class_name PSXMaterialFactory
extends RefCounted
## Builds PSX ShaderMaterials.
##
##   var m := PSXMaterialFactory.make(tex)                                  # lit, opaque
##   var m := PSXMaterialFactory.make(tex, {"uv_scale": 4.0, "affine_mult": 0.3})  # floor
##   var m := PSXMaterialFactory.make(sign_tex, {"unlit": true, "emission": 1.5})
##   var m := PSXMaterialFactory.make(null, {"transparent": true, "tint": Color(0.7, 0.8, 0.8, 0.2)})
##
## opts keys (all optional):
##   unlit: bool            unshaded variant (signs, screens, sky cards, tubes)
##   transparent: bool      glass variant (tint = glass colour incl. alpha)
##   face: bool             face variant (distort uniform)
##   double_sided: bool     no backface culling (lit/unlit)
##   tint: Color            albedo_color (glass: tint)
##   uv_scale: float|Vector2, uv_offset: Vector2
##   affine_mult: float     0..1 scale of the global affine warp (floors 0.2-0.5)
##   emission: float|Color|Texture2D
##                          lit: emission strength (float, uses albedo as emission tex) / colour /
##                          texture; unlit: float = brightness
##   emission_strength: float   explicit strength when emission is a Color/Texture2D
##   alpha_scissor: bool|float  discard below threshold (float = threshold, true = 0.5)
##   vertex_color: bool     multiply by mesh vertex colour
##   fog_mult: float        0 = ignore fog (sky cards)
##   snap: bool             vertex snapping on/off
##   color_reduce: bool     in-material 15-bit colour + dither
##   params: Dictionary     raw shader_parameter overrides applied last

const SHADER_LIT := preload("res://render/shaders/psx_lit.gdshader")
const SHADER_LIT_DS := preload("res://render/shaders/psx_lit_doublesided.gdshader")
const SHADER_UNLIT := preload("res://render/shaders/psx_unlit.gdshader")
const SHADER_UNLIT_DS := preload("res://render/shaders/psx_unlit_doublesided.gdshader")
const SHADER_GLASS := preload("res://render/shaders/psx_transparent.gdshader")
const SHADER_FACE := preload("res://render/shaders/psx_face.gdshader")

static var _shared: Dictionary = {}

static func make(albedo: Texture2D, opts := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var unlit: bool = opts.get("unlit", false)
	var glass: bool = opts.get("transparent", false)
	var face: bool = opts.get("face", false)
	var ds: bool = opts.get("double_sided", false)
	if glass:
		m.shader = SHADER_GLASS
	elif face:
		m.shader = SHADER_FACE
	elif unlit:
		m.shader = SHADER_UNLIT_DS if ds else SHADER_UNLIT
	else:
		m.shader = SHADER_LIT_DS if ds else SHADER_LIT

	if albedo:
		m.set_shader_parameter("albedo_texture", albedo)
	if opts.has("tint"):
		m.set_shader_parameter("tint" if glass else "albedo_color", opts.tint)
	if opts.has("uv_scale"):
		var s = opts.uv_scale
		m.set_shader_parameter("uv_scale", Vector2(s, s) if (s is float or s is int) else s)
	if opts.has("uv_offset"):
		m.set_shader_parameter("uv_offset", opts.uv_offset)
	if opts.has("affine_mult"):
		m.set_shader_parameter("affine_mult", float(opts.affine_mult))
	if opts.has("fog_mult"):
		m.set_shader_parameter("fog_mult", float(opts.fog_mult))
	if opts.has("snap"):
		m.set_shader_parameter("vertex_snap", bool(opts.snap))
	if opts.has("color_reduce"):
		m.set_shader_parameter("color_reduce", bool(opts.color_reduce))
	if opts.get("vertex_color", false):
		m.set_shader_parameter("use_vertex_color", true)
	if opts.has("alpha_scissor") and not glass:
		var a = opts.alpha_scissor
		if a is bool:
			m.set_shader_parameter("use_alpha_scissor", a)
		else:
			m.set_shader_parameter("use_alpha_scissor", true)
			m.set_shader_parameter("alpha_scissor_threshold", float(a))
	if opts.has("emission") and not glass:
		_apply_emission(m, albedo, opts, unlit)

	var params: Dictionary = opts.get("params", {})
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m

## Same as make() but returns a cached instance for identical (texture, opts) so meshes share it.
static func get_shared(albedo: Texture2D, opts := {}) -> ShaderMaterial:
	var key := "%d|%s" % [albedo.get_instance_id() if albedo else 0, var_to_str(opts)]
	if _shared.has(key):
		return _shared[key]
	var m := make(albedo, opts)
	_shared[key] = m
	return m

static func clear_cache() -> void:
	_shared.clear()

static func _apply_emission(m: ShaderMaterial, albedo: Texture2D, opts: Dictionary, unlit: bool) -> void:
	var e = opts.emission
	var strength: float = opts.get("emission_strength", 1.0)
	if e is Texture2D:
		m.set_shader_parameter("emission_texture", e)
		m.set_shader_parameter("emission_strength", strength)
	elif e is Color:
		if albedo and not opts.get("emission_ignore_albedo", false):
			m.set_shader_parameter("emission_texture", albedo)
		m.set_shader_parameter("emission_color", e)
		m.set_shader_parameter("emission_strength", strength)
	elif e is float or e is int:
		if unlit:
			m.set_shader_parameter("brightness", float(e))
		else:
			if albedo:
				m.set_shader_parameter("emission_texture", albedo)
			m.set_shader_parameter("emission_strength", float(e))
