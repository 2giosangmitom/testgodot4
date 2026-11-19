class_name FlickerLight
extends Node
## Drives a Light3D's energy (and an optional emissive tube mesh) with PS1-horror flicker.
## Add as a child of any Light3D, or set `target_light`.
##
## Joins group "flicker_lights" + every name in `groups`. Reacts to
##   EventBus.lights_flicker(group, duration) -> strong flicker burst
##   EventBus.lights_set(group, on)           -> switch on/off (fluorescent start-up stutter)
## You can also call flicker(duration) / set_on(on) directly or via get_tree().call_group().
##
## emissive_mesh: a GeometryInstance3D using a PSX shader; its `emit_level` instance uniform
## follows the light (unlit tubes dim to off_level, lit emission goes to 0).

enum Mode { STEADY, FLUORESCENT, DYING, SODIUM }

@export var mode: Mode = Mode.FLUORESCENT
@export var target_light: NodePath
@export var emissive_mesh: NodePath
@export var groups: PackedStringArray = []
@export var start_on := true
## Seconds between fluorescent stutters (random in range).
@export var stutter_interval := Vector2(5.0, 16.0)
@export var play_sound := true
@export var sfx_name := "fluorescent_flicker"
@export var sfx_volume_db := -4.0

var light: Light3D
var mesh: GeometryInstance3D
var base_energy := 1.0
var level := 1.0          # current multiplier 0..1 (read-only for others)

var _on := true
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _burst_left := 0.0     # strong flicker (event) time left
var _stutter_left := 0.0   # natural stutter / start-up time left
var _next_event := 0.0     # time until next natural stutter/dropout
var _hold := 0.0           # current random value hold time
var _held := 1.0
var _phase := 0.0
var _last_sfx := -10.0

func _ready() -> void:
	_rng.randomize()
	add_to_group("flicker_lights")
	for g in groups:
		if g != "":
			add_to_group(g)
	if target_light != NodePath():
		light = get_node_or_null(target_light) as Light3D
	if light == null:
		light = get_parent() as Light3D
	if emissive_mesh != NodePath():
		mesh = get_node_or_null(emissive_mesh) as GeometryInstance3D
	if light:
		base_energy = light.light_energy
	_on = start_on
	_phase = _rng.randf() * TAU
	_schedule_next()
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.lights_flicker.connect(_on_lights_flicker)
		bus.lights_set.connect(_on_lights_set)
	_apply(1.0 if _on else 0.0)

## Strong flicker burst; the light ends in its current on/off state.
func flicker(duration := 0.8) -> void:
	_burst_left = maxf(_burst_left, duration)
	_hold = 0.0
	_play_sfx(true)

func set_on(on: bool) -> void:
	if on == _on:
		return
	_on = on
	if on and (mode == Mode.FLUORESCENT or mode == Mode.DYING):
		_stutter_left = _rng.randf_range(0.35, 0.8)   # tube start-up
		_play_sfx(true)
	elif not on:
		_stutter_left = 0.0

func is_on() -> bool:
	return _on

## True while the light is visibly stuttering / bursting (entities may move then).
func is_flickering() -> bool:
	return _burst_left > 0.0 or _stutter_left > 0.0

## Change the "full" energy (e.g. from a lighting preset).
func set_base_energy(e: float) -> void:
	base_energy = e

func _matches(group_name: String) -> bool:
	return group_name == "" or is_in_group(group_name)

func _on_lights_flicker(group_name: String, duration: float) -> void:
	if _matches(group_name):
		flicker(duration)

func _on_lights_set(group_name: String, on: bool) -> void:
	if _matches(group_name):
		set_on(on)

func _process(delta: float) -> void:
	_t += delta
	var target := 0.0
	if _burst_left > 0.0:
		_burst_left -= delta
		target = _random_hold(delta, 0.02, 0.09, [0.0, 0.0, 0.08, 0.35, 1.0, 1.0])
	elif _stutter_left > 0.0:
		_stutter_left -= delta
		target = _random_hold(delta, 0.03, 0.08, [0.0, 0.1, 1.0, 0.7])
	elif not _on:
		target = 0.0
	else:
		target = _mode_level(delta)
	_apply(target)

func _mode_level(delta: float) -> float:
	match mode:
		Mode.STEADY:
			return 1.0
		Mode.FLUORESCENT:
			_next_event -= delta
			if _next_event <= 0.0:
				_stutter_left = _rng.randf_range(0.12, 0.55)
				_schedule_next()
				_play_sfx(false)
			# 60 Hz-ish micro flicker: tiny per-frame jitter.
			return 0.94 + _rng.randf() * 0.06
		Mode.DYING:
			_next_event -= delta
			if _next_event <= 0.0:
				_stutter_left = _rng.randf_range(0.05, 0.45)
				_schedule_next()
				if _rng.randf() < 0.4:
					_play_sfx(false)
			var buzz := 0.8 + _rng.randf() * 0.2
			if _rng.randf() < 0.03:
				buzz *= 0.4
			return buzz
		Mode.SODIUM:
			var pulse := 0.9 + 0.1 * sin(_t * TAU / 5.5 + _phase) + 0.025 * sin(_t * 1.7 + _phase * 2.0)
			_next_event -= delta
			if _next_event <= 0.0:
				_stutter_left = 0.0
				_burst_left = 0.0
				_hold = 0.25
				_held = 0.6
				_schedule_next()
			if _hold > 0.0:
				_hold -= delta
				return pulse * _held
			return pulse
	return 1.0

func _random_hold(delta: float, tmin: float, tmax: float, choices: Array) -> float:
	_hold -= delta
	if _hold <= 0.0:
		_hold = _rng.randf_range(tmin, tmax)
		_held = choices[_rng.randi() % choices.size()]
	return _held

func _schedule_next() -> void:
	match mode:
		Mode.FLUORESCENT:
			_next_event = _rng.randf_range(stutter_interval.x, stutter_interval.y)
		Mode.DYING:
			_next_event = _rng.randf_range(0.25, 2.5)
		Mode.SODIUM:
			_next_event = _rng.randf_range(12.0, 30.0)
		_:
			_next_event = 1e9

func _apply(v: float) -> void:
	level = v
	if light:
		light.light_energy = base_energy * v
	if mesh:
		mesh.set_instance_shader_parameter("emit_level", v)

func _play_sfx(force: bool) -> void:
	if not play_sound or sfx_name == "" or not light:
		return
	if not force and _t - _last_sfx < 2.0:
		return
	if _t - _last_sfx < 0.3:
		return
	_last_sfx = _t
	var ad := get_node_or_null("/root/AudioDirector")
	if ad and light.is_inside_tree():
		ad.play_sfx_3d(sfx_name, light.global_position, sfx_volume_db)
