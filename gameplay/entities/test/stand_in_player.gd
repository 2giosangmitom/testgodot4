extends CharacterBody3D
## Minimal stand-in for res://player/player.tscn (Track B) used only by entity tests.
## Implements the documented Player API: get_camera(), teleport(), is_crouching(), is_sprinting(),
## is_hidden(), look_at_point(pos, duration), set_controls_enabled(), kill(cause).
## WASD + mouse (click to capture), Shift sprint, C crouch, F flashlight, E toggles a nearby door.

const WALK := 2.6
const SPRINT := 5.2
const CROUCH := 1.3

var controls_enabled := true
var hidden := false
var crouching := false
var sprinting := false
var pitch := 0.0
var _noise_t := 0.0
var _look_tween: Tween

@onready var cam: Camera3D = $Camera3D
@onready var flashlight: SpotLight3D = $Camera3D/Flashlight

func _enter_tree() -> void:
	add_to_group("player")
	GameState.player = self

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	flashlight.visible = false
	EventBus.player_spawned.emit(self)

func get_camera() -> Camera3D:
	return cam

func is_hidden() -> bool:
	return hidden

func is_crouching() -> bool:
	return crouching

func is_sprinting() -> bool:
	return sprinting

func set_controls_enabled(on: bool) -> void:
	controls_enabled = on

func teleport(xform: Transform3D) -> void:
	global_position = xform.origin
	rotation.y = xform.basis.get_euler().y
	pitch = 0.0
	cam.rotation.x = 0.0
	velocity = Vector3.ZERO

func kill(cause: String) -> void:
	EventBus.player_caught.emit("", cause)

## Forced look (scares). duration <= 0 snaps instantly.
func look_at_point(pos: Vector3, duration := 0.3) -> void:
	var eye := cam.global_position
	var d := pos - eye
	if d.length() < 0.01:
		return
	var yaw := atan2(-d.x, -d.z)
	var p := atan2(d.y, Vector2(d.x, d.z).length())
	# shortest rotation for yaw
	var cur := rotation.y
	yaw = cur + wrapf(yaw - cur, -PI, PI)
	if _look_tween:
		_look_tween.kill()
	if duration <= 0.0:
		rotation.y = yaw
		pitch = p
		cam.rotation.x = p
		return
	_look_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_look_tween.tween_property(self, "rotation:y", yaw, duration)
	_look_tween.tween_method(func(v: float): pitch = v; cam.rotation.x = v, pitch, p, duration)

func _can_control() -> bool:
	return controls_enabled and not GameState.is_input_locked()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not _can_control():
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= e.relative.x * 0.003
		pitch = clampf(pitch - e.relative.y * 0.003, -1.4, 1.4)
		cam.rotation.x = pitch
	if e.is_action_pressed("flashlight"):
		flashlight.visible = not flashlight.visible
		GameState.flashlight_on = flashlight.visible
		EventBus.flashlight_toggled.emit(flashlight.visible)
		AudioDirector.play_sfx("flashlight_click")
	if e.is_action_pressed("interact"):
		_toggle_nearest_door()
	if e.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _toggle_nearest_door() -> void:
	for d in get_tree().get_nodes_in_group("test_door"):
		if d.global_position.distance_to(global_position) < 2.2 and d.has_method("toggle"):
			d.toggle()
			return

func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	if _can_control():
		var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = (global_basis * Vector3(iv.x, 0, iv.y))
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
		crouching = Input.is_action_pressed("crouch")
		sprinting = Input.is_action_pressed("sprint") and not crouching and dir != Vector3.ZERO
	else:
		sprinting = false
	var speed := CROUCH if crouching else (SPRINT if sprinting else WALK)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * delta
	move_and_slide()
	cam.position.y = lerpf(cam.position.y, 0.9 if crouching else 1.62, 10.0 * delta)
	if dir != Vector3.ZERO:
		_noise_t -= delta
		if _noise_t <= 0.0:
			_noise_t = 0.35
			EventBus.noise_emitted.emit(global_position, 0.05 if crouching else (0.8 if sprinting else 0.15))
