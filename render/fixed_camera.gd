class_name FixedCamera
extends Camera3D
## PS1-style fixed cutscene camera.
##   $Cam.cut_to()                         # hard cut (make current)
##   await $Cam.push_in(0.8, 4.0).finished # slow dolly forward 0.8 m over 4 s (negative = pull out)
##   $Cam.track_target($Gazer)             # lagged look-at; track_target(null) stops
##   $Cam.fov_jitter = 0.6                 # stepped low-FOV jitter (degrees)

signal cut

@export var track_lag := 3.0               ## higher = snappier tracking
@export var target_offset := Vector3(0, 1.5, 0)
@export var fov_jitter := 0.0              ## degrees of stepped random FOV jitter (0 = off)
@export var fov_jitter_rate := 10.0        ## jitter steps per second
@export var react_to_camera_shake := true  ## respond to EventBus.camera_shake while current

var target: Node3D
var _base_fov := 0.0
var _jit_t := 0.0
var _push_tween: Tween
var _shake_strength := 0.0
var _shake_left := 0.0

func _ready() -> void:
	_base_fov = fov
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("camera_shake"):
		bus.camera_shake.connect(_on_camera_shake)

## Hard cut to this camera. Optionally snap to look at the tracked target immediately.
func cut_to(snap_to_target := true) -> void:
	make_current()
	if snap_to_target and target:
		_look_now()
	cut.emit()

## Dolly along the view direction by `dist` metres over `dur` seconds. Returns the Tween.
func push_in(dist: float, dur: float) -> Tween:
	if _push_tween:
		_push_tween.kill()
	var to := global_position - global_basis.z * dist
	_push_tween = create_tween()
	_push_tween.tween_property(self, "global_position", to, dur) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return _push_tween

## Zoom by changing FOV (another PS1 favourite). Returns the Tween.
func zoom_to(new_fov: float, dur: float) -> Tween:
	var t := create_tween()
	t.tween_property(self, "_base_fov", new_fov, dur).set_trans(Tween.TRANS_SINE)
	return t

## Follow `node` with a lagged look-at. lag < 0 keeps track_lag. null stops tracking.
func track_target(node: Node3D, lag := -1.0) -> void:
	target = node
	if lag >= 0.0:
		track_lag = lag

func stop_tracking() -> void:
	target = null

func _look_now() -> void:
	var dir := target.global_position + target_offset - global_position
	if dir.length_squared() > 0.0001 and absf(dir.normalized().dot(Vector3.UP)) < 0.999:
		look_at(global_position + dir, Vector3.UP)

func _process(delta: float) -> void:
	if target and is_instance_valid(target):
		var p := target.global_position + target_offset
		var dir := p - global_position
		if dir.length_squared() > 0.0001 and absf(dir.normalized().dot(Vector3.UP)) < 0.999:
			var want := Basis.looking_at(dir, Vector3.UP).get_rotation_quaternion()
			var cur := global_basis.get_rotation_quaternion()
			var w := 1.0 - exp(-track_lag * delta) if track_lag > 0.0 else 1.0
			global_basis = Basis(cur.slerp(want, w))
	# Stepped FOV jitter.
	if fov_jitter > 0.0:
		_jit_t -= delta
		if _jit_t <= 0.0:
			_jit_t = 1.0 / maxf(fov_jitter_rate, 0.1)
			fov = _base_fov + randf_range(-fov_jitter, fov_jitter)
	elif fov != _base_fov:
		fov = _base_fov
	# Shake (h_offset/v_offset so it doesn't fight tracking).
	if _shake_left > 0.0:
		_shake_left -= delta
		var s := _shake_strength * clampf(_shake_left * 4.0, 0.0, 1.0)
		h_offset = randf_range(-s, s) * 0.1
		v_offset = randf_range(-s, s) * 0.1
		if _shake_left <= 0.0:
			h_offset = 0.0
			v_offset = 0.0

func shake(strength: float, duration: float) -> void:
	_shake_strength = strength
	_shake_left = duration

func _on_camera_shake(strength: float, duration: float) -> void:
	if react_to_camera_shake and current:
		shake(strength, duration)
