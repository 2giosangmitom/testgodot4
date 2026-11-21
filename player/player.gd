class_name Player
extends CharacterBody3D
## First-person player: slow walk, sprint with stamina, crouch, head bob, footsteps with
## surface detection, interaction raycast, item holding, flashlight, forced look, death.
## Public API: see docs/conventions.md ("Player").

## RMB held + mouse while holding an item: mouse motion in pixels. Camera look is suppressed.
## Items that listen rotate themselves; with no listener the player rotates the item.
signal held_item_rotated(relative: Vector2)
signal died(cause: String)

const HUD_SCENE := "res://ui/hud.tscn"
const POST_FX_SCENE := "res://render/post_fx.tscn"

# --- tuning ---
@export var walk_speed := 1.6
@export var sprint_speed := 3.6
@export var crouch_speed := 0.9
@export var accel := 9.0
@export var stand_eye := 1.62
@export var crouch_eye := 0.60
@export var stand_height := 1.75
@export var crouch_height := 0.68
@export var radius := 0.3
@export var gravity := 9.8
@export var stamina_drain := 20.0
@export var stamina_regen := 12.0
@export var stamina_regen_delay := 1.0
@export var stamina_recover_at := 30.0
@export var interact_range := 2.0
## Pressing interact with nothing targeted drops the held item.
@export var drop_on_empty_interact := true

# --- state ---
var stamina := 100.0
var exhausted := false
var controls_enabled := true
var dying := false
var _crouching := false
var _crouch_toggled := false
var _crouch_press_ms := 0
var _sprinting := false
var _hidden := false
var _yaw := 0.0
var _pitch := 0.0
var _eye := 1.62
var _bob_dist := 0.0
var _step_dist := 0.0
var _stamina_idle := 0.0
var _sway := 0.0
var _forced_look := false
var _caught_emitted := false
var _target: Node = null
var _last_prompt := "__none__"
var _held: Node3D = null
var _held_info := {}
var _hold_tween: Tween
var _flicker_t := 0.0
var _flicker_frames := 0
var _shake_t := 0.0
var _shake_str := 0.0
var _capture_frame := 0
## Screenshot runs (-- --shot=...) ignore the real mouse so shots are deterministic.
var _ignore_mouse := "--shot" in " ".join(OS.get_cmdline_user_args())

@onready var col: CollisionShape3D = $Collision
@onready var head: Node3D = $Head
@onready var cam: Camera3D = $Head/Camera3D
@onready var ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var hold_point: Node3D = $Head/Camera3D/HoldPoint
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var phone_light: OmniLight3D = $Head/Camera3D/PhoneLight
@onready var hide_probe: Area3D = $HideProbe

func _enter_tree() -> void:
	add_to_group("player")
	GameState.player = self

func _ready() -> void:
	GameState.player = self
	collision_layer = 2
	collision_mask = 1 | 4
	col.shape = col.shape.duplicate()
	_eye = stand_eye
	_yaw = rotation.y
	rotation = Vector3(0, _yaw, 0)
	ray.target_position = Vector3(0, 0, -interact_range)
	ray.collision_mask = 1 | 4 | 32
	ray.add_exception(self)
	flashlight.visible = GameState.flashlight_on
	phone_light.visible = false
	_flicker_t = randf_range(4.0, 12.0)
	EventBus.player_caught.connect(_on_player_caught)
	EventBus.phone_toggled.connect(func(open: bool): phone_light.visible = open)
	EventBus.camera_shake.connect(func(s: float, d: float): _shake_str = s; _shake_t = d)
	if ResourceLoader.exists(HUD_SCENE):
		add_child(load(HUD_SCENE).instantiate())
	if ResourceLoader.exists(POST_FX_SCENE):
		add_child(load(POST_FX_SCENE).instantiate())
	_capture_mouse(true)
	EventBus.player_spawned.emit.call_deferred(self)

func _exit_tree() -> void:
	if GameState.player == self:
		GameState.player = null
	GameState.unlock_input("player_dead")
	GameState.unlock_input("player_look")
	if _hidden:
		_hidden = false
		EventBus.player_hidden_changed.emit(false)

# ------------------------------------------------------------------ public API
func get_camera() -> Camera3D:
	return cam

func get_hold_point() -> Node3D:
	return hold_point

func teleport(xform: Transform3D) -> void:
	global_position = xform.origin
	var fwd := -xform.basis.z
	_yaw = atan2(-fwd.x, -fwd.z)
	_pitch = 0.0
	rotation = Vector3(0, _yaw, 0)
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	reset_physics_interpolation()

func is_crouching() -> bool:
	return _crouching

func is_sprinting() -> bool:
	return _sprinting

func is_hidden() -> bool:
	return _hidden

func set_controls_enabled(on: bool) -> void:
	controls_enabled = on

func can_control() -> bool:
	return controls_enabled and not dying and not GameState.is_input_locked()

## Turns the camera toward a world point over ~35% of `duration`, holds, then returns control.
## Awaitable: `await player.look_at_point(pos, 1.5)`.
func look_at_point(pos: Vector3, duration := 1.0) -> void:
	_forced_look = true
	GameState.lock_input("player_look")
	var from := cam.global_position
	var dir := (pos - from).normalized()
	var target_yaw := atan2(-dir.x, -dir.z)
	var target_pitch := clampf(asin(clampf(dir.y, -1.0, 1.0)), deg_to_rad(-85), deg_to_rad(85))
	var start_yaw := _yaw
	var start_pitch := _pitch
	var turn_time := clampf(duration * 0.35, 0.15, 0.8)
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_method(func(k: float):
		_yaw = lerp_angle(start_yaw, target_yaw, k)
		_pitch = lerpf(start_pitch, target_pitch, k), 0.0, 1.0, turn_time)
	await t.finished
	await get_tree().create_timer(maxf(duration - turn_time, 0.0)).timeout
	_forced_look = false
	if not dying:
		GameState.unlock_input("player_look")

func hold_item(node: Node3D) -> void:
	if node == null or node == _held:
		return
	if _held:
		release_item()
	_held = node
	var info := {"parent": node.get_parent(), "layer": 0, "mask": 0, "frozen": false}
	if node is CollisionObject3D:
		info.layer = node.collision_layer
		info.mask = node.collision_mask
		node.collision_layer = 0
		node.collision_mask = 0
	if node is RigidBody3D:
		info.frozen = node.freeze
		node.freeze = true
	if node is Interactable:
		info.enabled = node.enabled
		node.enabled = false
	_held_info = info
	if node.get_parent():
		node.reparent(hold_point, true)
	else:
		hold_point.add_child(node)
	var offset: Vector3 = node.get_meta("hold_offset", Vector3.ZERO)
	if _hold_tween:
		_hold_tween.kill()
	_hold_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hold_tween.tween_property(node, "position", offset, 0.25)
	_hold_tween.tween_property(node, "quaternion", Quaternion.IDENTITY, 0.25)
	AudioDirector.play_sfx("item_pickup", -4.0)

## Puts the held item back into its original parent where it is now (dropped in front of the
## player). StaticBody items are snapped to the floor below. Returns the item (or null).
func release_item() -> Node3D:
	if _held == null or not is_instance_valid(_held):
		_held = null
		return null
	var node := _held
	_held = null
	if _hold_tween:
		_hold_tween.kill()
	var parent: Node = _held_info.get("parent")
	if parent == null or not is_instance_valid(parent):
		parent = get_tree().current_scene
	node.reparent(parent, true)
	if node is CollisionObject3D:
		node.collision_layer = _held_info.get("layer", 0)
		node.collision_mask = _held_info.get("mask", 0)
	if node is RigidBody3D:
		node.freeze = _held_info.get("frozen", false)
		node.linear_velocity = velocity * 0.5
	else:
		_snap_to_floor(node)
	if node is Interactable:
		node.enabled = _held_info.get("enabled", true)
	_held_info = {}
	AudioDirector.play_sfx_3d("item_drop", node.global_position, -6.0)
	return node

func get_held_item() -> Node3D:
	return _held if _held and is_instance_valid(_held) else null

func set_flashlight(on: bool) -> void:
	if GameState.flashlight_on == on and flashlight.visible == on:
		return
	GameState.flashlight_on = on
	flashlight.visible = on
	AudioDirector.play_sfx("flashlight_click", -6.0)
	EventBus.flashlight_toggled.emit(on)

func toggle_flashlight() -> void:
	set_flashlight(not GameState.flashlight_on)

## Death: locks input, camera drops and tilts. Emits player_caught unless an entity already did.
func kill(cause := "") -> void:
	if dying:
		return
	if not _caught_emitted:
		_caught_emitted = true
		EventBus.player_caught.emit("", cause)
	_play_death(cause)

## Clears death state (used if a chapter respawns the same player instead of reloading).
func revive() -> void:
	dying = false
	_caught_emitted = false
	GameState.unlock_input("player_dead")
	cam.position = Vector3.ZERO
	cam.rotation = Vector3.ZERO
	_capture_mouse(true)

# ------------------------------------------------------------------ internals
func _on_player_caught(_entity_id: String, cause: String) -> void:
	_caught_emitted = true
	_play_death(cause)

func _play_death(cause: String) -> void:
	if dying:
		return
	dying = true
	GameState.lock_input("player_dead")
	if _held:
		release_item()
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(cam, "position:y", -(_eye - 0.25), 0.7)
	t.tween_property(cam, "rotation:z", deg_to_rad(randf_range(60, 80) * (1 if randf() < 0.5 else -1)), 0.75)
	t.tween_property(cam, "rotation:x", deg_to_rad(-20), 0.75)
	died.emit(cause)

func _capture_mouse(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	_capture_frame = Engine.get_process_frames()

func _ui_wants_cursor() -> bool:
	for n in get_tree().get_nodes_in_group("ui_cursor"):
		if n is CanvasItem and n.is_visible_in_tree():
			return true
	return GameState.phone_open or get_tree().paused

func _look_allowed() -> bool:
	return can_control() and not _forced_look and not _ui_wants_cursor()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# ignore the warp jump right after the mouse gets captured
		if Engine.get_process_frames() - _capture_frame < 4 or event.relative.length() > 250.0 or _ignore_mouse:
			return
		var sens: float = float(SaveSystem.get_setting("mouse_sens", 0.12))
		if _held and Input.is_action_pressed("secondary") and can_control():
			_rotate_held(event.relative)
			return
		if _look_allowed():
			_yaw -= deg_to_rad(event.relative.x * sens)
			_pitch = clampf(_pitch - deg_to_rad(event.relative.y * sens), deg_to_rad(-85), deg_to_rad(85))
		return
	if not can_control() or GameState.phone_open:
		return
	if event.is_action_pressed("flashlight"):
		toggle_flashlight()
	elif event.is_action_pressed("interact") and not GameState.phone_open and not _ui_wants_cursor():
		_do_interact()
	elif event.is_action_pressed("crouch"):
		# tap = toggle, hold = crouch while held
		_crouch_press_ms = Time.get_ticks_msec()
		_crouch_toggled = not _crouch_toggled
	elif event.is_action_released("crouch"):
		if Time.get_ticks_msec() - _crouch_press_ms > 350:
			_crouch_toggled = false

func _rotate_held(rel: Vector2) -> void:
	var k := 0.012
	var cb := cam.global_transform.basis
	held_item_rotated.emit(rel)
	if not held_item_rotated.get_connections().is_empty():
		return
	var gb := _held.global_transform.basis
	gb = Basis(cb.y, rel.x * k) * gb
	gb = Basis(cb.x, rel.y * k) * gb
	_held.global_transform.basis = gb.orthonormalized()

func _do_interact() -> void:
	if _target and is_instance_valid(_target):
		_target.interact(self)
		_last_prompt = "__none__"   # refresh prompt (e.g. door "Mở" -> "Đóng")
	elif _held and drop_on_empty_interact:
		release_item()

func _process(dt: float) -> void:
	# mouse mode follows UI state
	var want_captured := not _ui_wants_cursor() and not dying
	if want_captured != (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED) and DisplayServer.get_name() != "headless":
		if not get_tree().paused or not want_captured:
			_capture_mouse(want_captured)
	_update_flashlight(dt)
	_update_camera(dt)

func _physics_process(dt: float) -> void:
	if dying:
		velocity.x = move_toward(velocity.x, 0, dt * 6)
		velocity.z = move_toward(velocity.z, 0, dt * 6)
		velocity.y -= gravity * dt
		move_and_slide()
		return
	rotation.y = _yaw
	var ctrl := can_control()
	var input := Vector2.ZERO
	if GameState.phone_open:
		velocity.x = 0.0
		velocity.z = 0.0
	elif ctrl:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# crouch: hold OR toggle (tap). Holding while toggled keeps crouched.
	var want_crouch := ctrl and _crouch_toggled
	if not ctrl:
		want_crouch = _crouching
	if not want_crouch and _crouching and _ceiling_blocked():
		want_crouch = true
	_set_crouch(want_crouch)
	# sprint / stamina
	var moving := input.length() > 0.1
	var want_sprint := ctrl and moving and input.y < -0.3 and Input.is_action_pressed("sprint") \
			and not _crouching and not exhausted and not GameState.phone_open
	_sprinting = want_sprint and stamina > 0.0
	if _sprinting:
		stamina = maxf(stamina - stamina_drain * dt, 0.0)
		_stamina_idle = 0.0
		if stamina <= 0.0:
			exhausted = true
			_sprinting = false
			AudioDirector.play_sfx("breath_heavy", -2.0)
	else:
		_stamina_idle += dt
		if _stamina_idle >= stamina_regen_delay:
			stamina = minf(stamina + stamina_regen * dt, 100.0)
		if exhausted and stamina >= stamina_recover_at:
			exhausted = false
	_sway = move_toward(_sway, 1.0 if exhausted else 0.0, dt * 0.8)
	var speed := walk_speed
	if _crouching:
		speed = crouch_speed
	elif _sprinting:
		speed = sprint_speed
	if _held and _held.has_meta("heavy"):
		speed *= 0.7
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	dir.y = 0
	dir = dir.normalized() * minf(input.length(), 1.0)
	var target_v := dir * speed
	velocity.x = move_toward(velocity.x, target_v.x, accel * dt)
	velocity.z = move_toward(velocity.z, target_v.z, accel * dt)
	if is_on_floor():
		velocity.y = -0.1
	else:
		velocity.y -= gravity * dt
	var before := global_position
	move_and_slide()
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if is_on_floor() and moved > 0.0005:
		_bob_dist += moved
		_step_dist += moved
		var stride := 0.62 if _crouching else (1.05 if _sprinting else 0.78)
		if _step_dist >= stride:
			_step_dist = 0.0
			_footstep()
	_update_interact()
	_update_hidden()

func _set_crouch(on: bool) -> void:
	if on == _crouching:
		return
	_crouching = on
	var shape := col.shape as CapsuleShape3D
	var h := crouch_height if on else stand_height
	shape.height = h
	col.position.y = h * 0.5
	if not on:
		_crouch_toggled = false

func _ceiling_blocked() -> bool:
	# Test the standing capsule in place.
	var params := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius - 0.02
	cap.height = stand_height - 0.1
	params.shape = cap
	params.transform = Transform3D(Basis(), global_position + Vector3(0, stand_height * 0.5 + 0.05, 0))
	params.collision_mask = 1
	params.exclude = [get_rid()]
	return not get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()

func _footstep() -> void:
	var surface := _detect_surface()
	var n := randi_range(1, 4)
	var vol := -14.0 if _crouching else (-3.0 if _sprinting else -8.0)
	AudioDirector.play_sfx("footstep_%s_%d" % [surface, n], vol, randf_range(0.92, 1.06))
	var loud := 0.05 if _crouching else (0.8 if _sprinting else 0.15)
	EventBus.noise_emitted.emit(global_position, loud)

func _detect_surface() -> String:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.2, global_position + Vector3.DOWN * 0.4, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return "concrete"
	var n: Node = hit.collider
	for i in 3:
		if n == null:
			break
		if n.has_meta("surface"):
			return str(n.get_meta("surface"))
		if n.is_in_group("surface_tile"):
			return "tile"
		if n.is_in_group("surface_wood"):
			return "wood"
		if n.is_in_group("surface_concrete"):
			return "concrete"
		n = n.get_parent()
	return "concrete"

func _find_interactable(n: Node) -> Node:
	while n and n != get_tree().root:
		if n.has_method("interact"):
			return n
		n = n.get_parent()
	return null

func _update_interact() -> void:
	var target: Node = null
	if can_control() and not GameState.phone_open:
		ray.force_raycast_update()
		if ray.is_colliding():
			target = _find_interactable(ray.get_collider())
			if target == _held:
				target = null
	var text := ""
	if target:
		if target.has_method("get_prompt"):
			text = target.get_prompt()
		else:
			text = "Tương tác"
		if target.has_method("can_interact") and not target.can_interact(self) and text == "":
			target = null
	if text == "":
		target = null
	_target = target
	if text != _last_prompt:
		_last_prompt = text
		EventBus.interact_prompt.emit(text)

func _update_hidden() -> void:
	var inside := false
	if _crouching:
		for a in hide_probe.get_overlapping_areas():
			if a.is_in_group("hide_spot"):
				inside = true
				break
	if inside != _hidden:
		_hidden = inside
		EventBus.player_hidden_changed.emit(_hidden)

func _update_flashlight(dt: float) -> void:
	if not flashlight.visible:
		return
	if _flicker_frames > 0:
		_flicker_frames -= 1
		flashlight.light_energy = randf_range(0.05, 0.6)
		if _flicker_frames == 0:
			flashlight.light_energy = 1.2
		return
	_flicker_t -= dt
	if _flicker_t <= 0.0:
		_flicker_t = randf_range(5.0, 16.0)
		_flicker_frames = randi_range(3, 9)

func _update_camera(dt: float) -> void:
	if dying:
		return
	var target_eye := crouch_eye if _crouching else stand_eye
	_eye = move_toward(_eye, target_eye, dt * 2.8)
	head.position.y = _eye
	# head bob
	var spd := Vector2(velocity.x, velocity.z).length()
	var amp := clampf(spd / sprint_speed, 0.0, 1.0)
	var freq := 2.0 * PI / (1.56 if not _sprinting else 2.1)
	var bob_y := sin(_bob_dist * freq) * 0.018 * (0.4 + amp)
	var bob_x := cos(_bob_dist * freq * 0.5) * 0.012 * (0.4 + amp)
	if spd < 0.1:
		bob_y = 0.0
		bob_x = 0.0
	var tsec := Time.get_ticks_msec() / 1000.0
	var sway_roll := sin(tsec * 1.7) * deg_to_rad(1.6) * _sway
	var sway_pitch := sin(tsec * 2.3) * deg_to_rad(1.2) * _sway
	var shake := Vector3.ZERO
	if _shake_t > 0.0:
		_shake_t -= dt
		shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake_str * 0.03
	cam.position = cam.position.lerp(Vector3(bob_x, bob_y, 0) + shake, minf(dt * 12.0, 1.0))
	cam.rotation.z = lerp_angle(cam.rotation.z, sway_roll - velocity.dot(global_transform.basis.x) * 0.006, minf(dt * 6.0, 1.0))
	cam.rotation.x = sway_pitch
	head.rotation.x = _pitch
	rotation.y = _yaw

func _snap_to_floor(node: Node3D) -> void:
	var from := node.global_position + Vector3.UP * 0.1
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var basis_y := node.global_transform.basis.get_euler().y
	node.global_rotation = Vector3(0, basis_y, 0)
	if not hit.is_empty():
		var bottom := _visual_bottom(node)
		node.global_position = hit.position + Vector3.UP * (-bottom + 0.002)

func _visual_bottom(node: Node3D) -> float:
	# Lowest point of the node's meshes relative to its origin (local Y, unrotated).
	var lowest := 0.0
	var found := false
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var aabb := mi.get_aabb()
		var rel := node.global_transform.affine_inverse() * mi.global_transform
		var y := (rel * aabb.position).y
		if not found or y < lowest:
			lowest = y
			found = true
	return lowest
