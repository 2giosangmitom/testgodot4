extends CharacterBody3D
## Minimal stand-in first-person player for minigame testing ONLY. Implements the subset of the
## documented Player API the minigames use (docs/conventions.md) with the same method names:
##   get_camera(), get_hold_point(), hold_item(node), release_item(), get_held_item(),
##   set_controls_enabled(b), teleport(xform), is_crouching(), is_sprinting(), is_hidden()
##   signal held_item_rotated(relative: Vector2)  — RMB + mouse while holding (camera look suppressed)
## Also draws a tiny HUD (crosshair, prompt, toasts, fade) so screenshots are meaningful.

signal held_item_rotated(relative: Vector2)

@export var speed := 2.0
@export var mouse_sensitivity := 0.0025
@export var show_hud := true

var _head: Node3D
var _camera: Camera3D
var _hold_point: Node3D
var _held: Node3D
var _pitch := 0.0
var _controls := true
var _prompt_label: Label
var _toast_label: Label
var _toast_time := 0.0
var _fade: ColorRect

func _ready() -> void:
	add_to_group("player")
	GameState.player = self
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	_head = Node3D.new()
	_head.name = "Head"
	_head.position.y = 1.62
	add_child(_head)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 70.0
	_camera.near = 0.05
	_camera.current = true
	_head.add_child(_camera)
	_hold_point = Node3D.new()
	_hold_point.name = "HoldPoint"
	_hold_point.position = Vector3(0.12, -0.2, -0.45)
	_camera.add_child(_hold_point)
	if show_hud:
		_build_hud()
	EventBus.toast.connect(_on_toast)
	EventBus.fade_request.connect(_on_fade)

func _exit_tree() -> void:
	if GameState.player == self:
		GameState.player = null

# ------------------------------------------------------------- Player API subset
func get_camera() -> Camera3D:
	return _camera

func get_hold_point() -> Node3D:
	return _hold_point

func get_held_item() -> Node3D:
	if _held and not is_instance_valid(_held):
		_held = null
	return _held

func hold_item(node: Node3D) -> void:
	if _held or node == null:
		return
	_held = node
	node.reparent(_hold_point, true)
	node.position = Vector3.ZERO

func release_item() -> void:
	if _held == null:
		return
	var n := _held
	_held = null
	if is_instance_valid(n) and n.is_inside_tree():
		var root := get_tree().current_scene if get_tree().current_scene else get_parent()
		n.reparent(root, true)

func set_controls_enabled(on: bool) -> void:
	_controls = on

func teleport(xform: Transform3D) -> void:
	global_position = xform.origin
	var fwd := -xform.basis.z
	rotation = Vector3(0, atan2(-fwd.x, -fwd.z), 0)
	_pitch = 0.0
	_head.rotation.x = 0.0
	velocity = Vector3.ZERO

## Turns body (yaw) and head (pitch) to look at a world point.
func aim_at(point: Vector3) -> void:
	var eye := global_position + Vector3(0, 1.62, 0)
	var d := point - eye
	rotation = Vector3(0, atan2(-d.x, -d.z), 0)
	_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	_head.rotation.x = _pitch

func is_crouching() -> bool:
	return false

func is_sprinting() -> bool:
	return false

func is_hidden() -> bool:
	return false

# ------------------------------------------------------------- input
func _can_control() -> bool:
	return _controls and not GameState.is_input_locked()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not _can_control():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _held and Input.is_action_pressed("secondary"):
			held_item_rotated.emit(event.relative)
		else:
			rotation.y -= event.relative.x * mouse_sensitivity
			_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.45, 1.45)
			_head.rotation.x = _pitch
	if event.is_action_pressed("interact"):
		var t := get_aimed()
		if t and t.has_method("interact") and (not t.has_method("get_prompt") or t.get_prompt() != ""):
			t.interact(self)

func get_aimed() -> Object:
	var from := _camera.global_position
	var to := from - _camera.global_basis.z * 2.0
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 32)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).get("collider")

func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if _can_control():
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (global_basis * Vector3(input.x, 0, input.y)).normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * delta
	move_and_slide()
	if _prompt_label:
		var t := get_aimed()
		var p := ""
		if t and t.has_method("get_prompt"):
			p = t.get_prompt()
		_prompt_label.text = ("[E] " + p) if p != "" else ""

func _process(delta: float) -> void:
	if _toast_label and _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast_label.text = ""

# ------------------------------------------------------------- HUD
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var cross := Label.new()
	cross.text = "+"
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.position = Vector2(316, 226)
	cross.add_theme_font_size_override("font_size", 16)
	layer.add_child(cross)
	_prompt_label = Label.new()
	_prompt_label.position = Vector2(0, 300)
	_prompt_label.size = Vector2(640, 24)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	layer.add_child(_prompt_label)
	_toast_label = Label.new()
	_toast_label.position = Vector2(0, 40)
	_toast_label.size = Vector2(640, 24)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 16)
	_toast_label.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	_toast_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	layer.add_child(_toast_label)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.size = Vector2(640, 480)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)

func _on_toast(text: String) -> void:
	if _toast_label:
		_toast_label.text = text
		_toast_time = 2.5

func _on_fade(to_black: bool, duration: float) -> void:
	if _fade == null:
		EventBus.fade_done.emit.call_deferred()
		return
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0 if to_black else 0.0, maxf(duration, 0.01))
	t.tween_callback(EventBus.fade_done.emit)
