class_name Gazer
extends EntityBase
## "Kẻ Nhìn" — a normal-looking person, 20% taller, never blinks. Stands motionless at the edge of
## the fog / outside the store glass. Advances along `path_markers` (far -> near) ONLY while the
## player is not looking (or during a light flicker). Moves are instant snaps, always facing the player.
## Staring at it too long (stare meter) -> static -> lose control -> caught.
##
## Modes:
##  OUTSIDE_GLASS: never enters. Reaching the last marker = glass_tap + scare + vanish (no death).
##  HUNT:          reaching the last marker (or touching the player) = caught.

signal reached_end
signal stared_out
signal moved(index: int)

enum Mode { OUTSIDE_GLASS, HUNT }

@export var mode: Mode = Mode.OUTSIDE_GLASS
## Ordered positions far -> near. Last one = catch position (at the glass / behind the player).
@export var path_markers: Array[NodePath] = []
## Character glb; default tries res://assets/models/chars/gazer.glb, else a placeholder.
@export var model_scene: PackedScene
@export var start_index := 0
@export_group("Movement")
@export var cooldown_min := 4.0
@export var cooldown_max := 10.0
## Extra cooldown before the very first move after activation.
@export var first_move_delay := 3.0
## Only listen to lights_flicker for this group ("" = any group).
@export var flicker_group := ""
## HUNT: the last step appears right behind the player instead of at the last marker.
@export var final_behind_player := false
## HUNT: player closer than this = caught.
@export var catch_distance := 1.0
@export_group("Observation")
## Frustum margin in degrees (counts as observed slightly before it is on screen).
@export var view_margin_deg := 4.0
## Max distance at which it can be seen. <= 0 = use psx_fog_far * 0.95.
@export var visible_distance := -1.0
@export_group("Stare")
@export var stare_distance := 14.0
@export var stare_grace := 2.0
@export var stare_limit := 5.0
## Meter decay speed (seconds of stare removed per second of looking away).
@export var stare_decay := 1.2
@export var stare_kills := true
## Time between losing control and the catch.
@export var lose_control_time := 1.2

## Injectable observation (tests): Callable() -> bool. Invalid = real camera test.
var observation_override := Callable()
## Injectable line of sight: Callable(from, to) -> bool. Invalid = physics raycast (glass ignored).
var los_override := Callable()

var index := 0
var stare := 0.0
var observed := false
var rng := RandomNumberGenerator.new()

var _cooldown := 0.0
var _time := 0.0
var _flicker_until := -1.0
var _flicker_move := false
var _heart_t := 0.0
var _shake_t := 0.0
var _static_applied := 0.0
var _out_t := 0.0
var _out_static_from := 0.0

@onready var body: EntityBody = $Body

func _ready() -> void:
	if model_scene == null:
		model_scene = find_char_model("gazer")
	body.build(model_scene)
	body.play_anim("stand_stare")
	EventBus.lights_flicker.connect(_on_lights_flicker)
	super._ready()

func _on_activate() -> void:
	index = clampi(start_index, 0, maxi(path_markers.size() - 1, 0))
	stare = 0.0
	_cooldown = first_move_delay + rng.randf_range(cooldown_min, cooldown_max) * 0.5
	_snap_to_marker(index)
	body.set_shape("face_distort", 0.0)
	set_state("watching")

func _on_deactivate() -> void:
	_clear_fx()
	GameState.unlock_input("gazer_stare")

func marker_count() -> int:
	return path_markers.size()

func get_marker_position(i: int) -> Vector3:
	if i < 0 or i >= path_markers.size():
		return global_position
	var m := node3d(path_markers[i])
	return m.global_position if m else global_position

# ------------------------------------------------------------------ logic

func tick(delta: float) -> void:
	_time += delta
	match state:
		"watching":
			_tick_watching(delta)
		"staring_out":
			_tick_stare_out(delta)

func _tick_watching(delta: float) -> void:
	var p := get_player()
	if p == null:
		return
	observed = compute_observed()
	var dist := global_position.distance_to(p.global_position)
	# --- stare meter
	if observed and dist <= stare_distance and not is_passive():
		stare += delta
	else:
		stare = maxf(0.0, stare - delta * stare_decay)
	_apply_stare_fx(delta)
	if stare_kills and stare >= stare_limit:
		_begin_stare_out()
		return
	# --- touching in hunt mode
	if mode == Mode.HUNT and dist <= catch_distance and not is_passive():
		_catch("gazer_touch")
		return
	# --- movement
	_cooldown -= delta
	var flicker := _time < _flicker_until and _flicker_move
	var can_move := (not observed and _cooldown <= 0.0) or flicker
	if is_passive():
		can_move = _cooldown <= 0.0
	if can_move and index < path_markers.size() - 1:
		advance()

## Snaps to the next marker. Public so chapters can force a step.
func advance() -> void:
	if index >= path_markers.size() - 1:
		return
	index += 1
	_flicker_move = false
	_cooldown = rng.randf_range(cooldown_min, cooldown_max)
	var last := index == path_markers.size() - 1
	if last and mode == Mode.HUNT and final_behind_player and get_player():
		var p := get_player()
		var cam := get_player_camera()
		var fwd := -(cam.global_basis.z if cam else p.global_basis.z)
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		global_position = p.global_position - fwd * 0.9
		face_player()
	else:
		_snap_to_marker(index)
	moved.emit(index)
	EventBus.entity_state_changed.emit(entity_id, "moved_%d" % index)
	if last:
		_on_reached_end()

func _snap_to_marker(i: int) -> void:
	if path_markers.is_empty():
		return
	global_position = get_marker_position(i)
	face_player()

func face_player() -> void:
	var p := get_player()
	if p == null:
		return
	var tgt := p.global_position
	if Vector2(tgt.x - global_position.x, tgt.z - global_position.z).length() < 0.01:
		return
	rotation.y = EntityObservation.yaw_to(global_position, tgt)

## True if the player currently sees the Gazer (frustum + fog distance + line of sight).
func compute_observed() -> bool:
	if observation_override.is_valid():
		return observation_override.call()
	if player_is_hidden():
		return false
	var cam := get_player_camera()
	if cam == null or not cam.is_inside_tree():
		return false
	var vp := cam.get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var maxd := visible_distance if visible_distance > 0.0 else EntityObservation.fog_visible_distance() * 0.95
	var los := los_override if los_override.is_valid() else Callable(self, "_default_los")
	return EntityObservation.is_observed(cam.global_transform, cam.fov, aspect, body.get_sample_points(),
		maxd, view_margin_deg, los)

func _default_los(from: Vector3, to: Vector3) -> bool:
	if not is_inside_tree():
		return true
	return EntityObservation.ray_clear(get_world_3d().direct_space_state, from, to)

func _on_lights_flicker(group_name: String, duration: float) -> void:
	if not _active:
		return
	if flicker_group != "" and group_name != flicker_group:
		return
	_flicker_until = _time + maxf(duration, 0.2)
	_flicker_move = true

# ------------------------------------------------------------------ stare

func stare_fraction() -> float:
	return clampf((stare - stare_grace) / maxf(stare_limit - stare_grace, 0.01), 0.0, 1.0)

func _apply_stare_fx(delta: float) -> void:
	var k := stare_fraction()
	if k > 0.0:
		var s := 0.12 + 0.6 * k
		RenderSettings.set_static(s)
		_static_applied = s
		_heart_t -= delta
		if _heart_t <= 0.0:
			_heart_t = lerpf(1.0, 0.4, k)
			AudioDirector.play_sfx("heartbeat", lerpf(-10.0, 0.0, k), 1.0, "SFX")
		_shake_t -= delta
		if _shake_t <= 0.0:
			_shake_t = 0.35
			EventBus.camera_shake.emit(0.04 + 0.3 * k, 0.4)
	elif _static_applied > 0.0:
		_clear_fx()

func _clear_fx() -> void:
	if _static_applied > 0.0:
		RenderSettings.set_static(0.0)
	_static_applied = 0.0

func _begin_stare_out() -> void:
	if is_passive():
		return
	set_state("staring_out")
	stared_out.emit()
	_out_t = 0.0
	_out_static_from = _static_applied
	GameState.lock_input("gazer_stare")
	var p := get_player()
	if p and p.has_method("look_at_point"):
		p.look_at_point(body.get_head_global_position(), lose_control_time * 0.7)
	AudioDirector.play_sfx("static_burst", -8.0, 0.8, "SFX")

func _tick_stare_out(delta: float) -> void:
	_out_t += delta
	var k := clampf(_out_t / maxf(lose_control_time, 0.01), 0.0, 1.0)
	var s := lerpf(_out_static_from, 1.0, k)
	RenderSettings.set_static(s)
	_static_applied = s
	_heart_t -= delta
	if _heart_t <= 0.0:
		_heart_t = 0.3
		AudioDirector.play_sfx("heartbeat", 0.0, 1.1, "SFX")
	EventBus.camera_shake.emit(0.3 + 0.5 * k, 0.2)
	var p := get_player()
	if p and p.has_method("look_at_point"):
		p.look_at_point(body.get_head_global_position(), 0.1)
	if _out_t >= lose_control_time:
		GameState.unlock_input("gazer_stare")
		_catch("gazer_stare")

# ------------------------------------------------------------------ endings

func _catch(cause: String) -> void:
	_static_applied = 0.0   # the caught sequence owns static from here
	if is_passive():
		set_state("watching")
		return
	var seq := catch_player(cause, self)
	if seq == null:
		set_state("caught")

func _on_reached_end() -> void:
	reached_end.emit()
	if mode == Mode.HUNT:
		_catch("gazer_reach")
		return
	set_state("at_glass")
	_glass_scare()

func _glass_scare() -> void:
	AudioDirector.play_sfx_3d("glass_tap", body.get_head_global_position(), 2.0, 1.0, "Entity")
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.7).timeout
	if not _active or state != "at_glass":
		return
	var p := get_player()
	if is_passive() or p == null:
		vanish()
		return
	var seq := CaughtSequence.scare(self, p)
	if seq == null:
		vanish()
		return
	await seq.peak
	vanish()

## Disappears (no death). Chapter decides what happens next.
func vanish() -> void:
	AudioDirector.play_sfx("static_burst", -10.0, 1.3, "SFX")
	_clear_fx()
	set_state("vanished")
	deactivate()
	visible = false
