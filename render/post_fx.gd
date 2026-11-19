class_name PostFX
extends CanvasLayer
## Full-screen PSX/VHS post-process. Instance res://render/post_fx.tscn once (HUD/level).
## Static glitch follows EventBus.static_amount (and the psx_static shader global set by
## RenderSettings.set_static). Never blocks mouse input.

@export_range(0.0, 2.0) var base_intensity := 1.0:
	set(v):
		base_intensity = v
		if _mat:
			_mat.set_shader_parameter("intensity", v)

@onready var _rect: ColorRect = $Rect
var _mat: ShaderMaterial
var _static := 0.0
var _static_tween: Tween

func _ready() -> void:
	layer = 90
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = _rect.material as ShaderMaterial
	_mat.set_shader_parameter("intensity", base_intensity)
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("static_amount"):
		bus.static_amount.connect(_on_static_amount)

## Strength of the always-on VHS look (wobble, chroma, scanlines, vignette, grain). 0 = off.
func set_intensity(base: float) -> void:
	base_intensity = clampf(base, 0.0, 2.0)

func set_enabled(on: bool) -> void:
	visible = on

## Toggle 15-bit quantise + dither.
func set_quantize(on: bool) -> void:
	_mat.set_shader_parameter("quantize", on)

## Local static (0..1) without touching the global; the shader uses max(global, local).
func set_static(v: float) -> void:
	_static = clampf(v, 0.0, 1.0)
	_mat.set_shader_parameter("static_amount", _static)

## One-shot static burst that decays back to 0 over `duration`.
func pulse_static(amount: float, duration := 0.5) -> void:
	if _static_tween:
		_static_tween.kill()
	set_static(maxf(_static, amount))
	_static_tween = create_tween()
	_static_tween.tween_method(set_static, _static, 0.0, duration)

func _on_static_amount(v: float) -> void:
	if _static_tween:
		_static_tween.kill()
	set_static(v)
