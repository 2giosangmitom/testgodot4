extends Node
## Drives PSX global shader params (declared in project.godot [shader_globals]).
## Every PSX material reads these, so fog/snap/static change globally.

const FOG_PRESETS := {
	"day":        {"near": 15.0, "far": 25.0, "color": Color(0.62, 0.63, 0.62)},
	"overcast":   {"near": 12.0, "far": 22.0, "color": Color(0.48, 0.49, 0.50)},
	"dusk":       {"near": 10.0, "far": 18.0, "color": Color(0.32, 0.24, 0.24)},
	"night":      {"near": 6.0,  "far": 10.0, "color": Color(0.03, 0.03, 0.04)},
	"night_store":{"near": 8.0,  "far": 14.0, "color": Color(0.04, 0.05, 0.05)},
	"dread":      {"near": 3.0,  "far": 7.0,  "color": Color(0.02, 0.01, 0.01)},
	"dawn":       {"near": 12.0, "far": 24.0, "color": Color(0.55, 0.50, 0.46)},
}

var low_res := false            # true -> 320x240 snapping ("extreme" mode)
var current_preset := "night"
var _static := 0.0

func _ready() -> void:
	low_res = SaveSystem.get_setting("low_res", false)
	apply_snap()
	set_fog_preset("night", 0.0)

func apply_snap() -> void:
	# Normal: render 640x480, vertices snap to a 320x240 grid (visible PS1 wobble).
	# Extreme: render 320x240, snap to 160x120.
	var render := Vector2i(320, 240) if low_res else Vector2i(640, 480)
	get_tree().root.content_scale_size = render
	RenderingServer.global_shader_parameter_set("psx_snap_resolution", Vector2(render) * 0.5)

func set_low_res(on: bool) -> void:
	low_res = on
	SaveSystem.set_setting("low_res", on)
	apply_snap()

func set_fog_preset(name: String, duration := 1.0) -> void:
	if not FOG_PRESETS.has(name):
		push_warning("RenderSettings: unknown fog preset " + name)
		return
	current_preset = name
	var p: Dictionary = FOG_PRESETS[name]
	set_fog(p.near, p.far, p.color, duration)

func set_fog(near: float, far: float, color: Color, duration := 1.0) -> void:
	RenderingServer.set_default_clear_color(color)
	if duration <= 0.0:
		_apply_fog(near, far, color)
		return
	var from_near: float = RenderingServer.global_shader_parameter_get("psx_fog_near")
	var from_far: float = RenderingServer.global_shader_parameter_get("psx_fog_far")
	var from_col: Color = RenderingServer.global_shader_parameter_get("psx_fog_color")
	var t := create_tween()
	t.tween_method(func(k: float):
		_apply_fog(lerp(from_near, near, k), lerp(from_far, far, k), from_col.lerp(color, k)), 0.0, 1.0, duration)

func _apply_fog(near: float, far: float, color: Color) -> void:
	RenderingServer.global_shader_parameter_set("psx_fog_near", near)
	RenderingServer.global_shader_parameter_set("psx_fog_far", far)
	RenderingServer.global_shader_parameter_set("psx_fog_color", color)
	RenderingServer.set_default_clear_color(color)

func set_static(v: float) -> void:
	_static = clampf(v, 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("psx_static", _static)
	EventBus.static_amount.emit(_static)

func get_static() -> float:
	return _static
