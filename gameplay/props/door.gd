class_name Door
extends Interactable
## Hinged door. The node origin is the HINGE; the leaf extends along local +X (0.9 m wide),
## 2.1 m tall, thin along Z. Put any mesh as a child (e.g. door_wood.glb instanced with its
## hinge at the origin); if there is no visual child a default box is created. Collision
## (child CollisionShape3D, auto-created if missing) rotates with the door because the whole
## body rotates around local Y.
##
## Interact: opens SLOWLY away from the player (~1.6 s ease-in creak); interact again closes.

@export var door_id := ""
@export var locked := false:
	set(v):
		locked = v
@export var open_angle := 95.0
@export var open_time := 1.6
@export var close_time := 0.9
@export var width := 0.9
@export var height := 2.1
@export var thickness := 0.05
@export var prompt_open := "Mở cửa"
@export var prompt_close := "Đóng cửa"
@export var prompt_locked := "Khóa"
## Emit noise when opened (Crowd/entities hear it).
@export var noise := 0.25

var is_open := false
var moving := false
var _closed_yaw := 0.0
var _angle := 0.0          # current swing in degrees (+ = towards local -Z)
var _tween: Tween

func _ready() -> void:
	_ensure_default_parts()
	if Engine.is_editor_hint():
		return
	super._ready()
	collision_layer = 1 | 4      # blocks like a wall, targetable like an interactable
	_closed_yaw = rotation.y
	add_to_group("doors")

func _ensure_default_parts() -> void:
	var has_visual := false
	var has_col := false
	for c in get_children():
		if c is CollisionShape3D:
			has_col = true
		elif c is VisualInstance3D or (c is Node3D and c.get_child_count() > 0):
			has_visual = true
	if not has_col:
		var cs := CollisionShape3D.new()
		cs.name = "DoorCollision"
		var box := BoxShape3D.new()
		box.size = Vector3(width, height, maxf(thickness, 0.06))
		cs.shape = box
		cs.position = Vector3(width * 0.5, height * 0.5, 0)
		add_child(cs)
	if not has_visual:
		var mi := MeshInstance3D.new()
		mi.name = "DefaultMesh"
		var bm := BoxMesh.new()
		bm.size = Vector3(width, height, thickness)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.42, 0.3, 0.2)
		bm.material = mat
		mi.mesh = bm
		mi.position = Vector3(width * 0.5, height * 0.5, 0)
		add_child(mi)
		var knob := MeshInstance3D.new()
		knob.name = "Knob"
		var km := BoxMesh.new()
		km.size = Vector3(0.06, 0.06, thickness + 0.1)
		var kmat := StandardMaterial3D.new()
		kmat.albedo_color = Color(0.6, 0.55, 0.4)
		km.material = kmat
		knob.mesh = km
		knob.position = Vector3(width - 0.1, 1.0, 0)
		add_child(knob)

func get_prompt() -> String:
	if not enabled or moving:
		return ""
	if locked and not is_open:
		return prompt_locked
	return prompt_close if is_open else prompt_open

func can_interact(_p: Node3D) -> bool:
	return enabled and not moving

func _on_interact(player: Node3D) -> void:
	if is_open:
		close()
	elif locked:
		AudioDirector.play_sfx_3d("door_handle_rattle", _handle_pos())
	else:
		open(player.global_position if player else Vector3.INF)

## Opens away from `from_pos` (world). Pass Vector3.INF to use the default (+ angle).
func open(from_pos := Vector3.INF, duration := -1.0) -> void:
	if locked or is_open:
		return
	var dir := 1.0
	if from_pos != Vector3.INF:
		var local := _closed_xform().affine_inverse() * from_pos
		dir = 1.0 if local.z >= 0.0 else -1.0
	AudioDirector.play_sfx_3d("door_open_creak", _handle_pos())
	if noise > 0.0:
		EventBus.noise_emitted.emit(global_position, noise)
	_set_open_state(true)
	_swing_to(open_angle * dir, open_time if duration < 0.0 else duration, Tween.EASE_IN_OUT)

func close(duration := -1.0) -> void:
	if not is_open and is_zero_approx(_angle):
		return
	_set_open_state(false)
	_swing_to(0.0, close_time if duration < 0.0 else duration, Tween.EASE_IN)
	await _tween.finished
	AudioDirector.play_sfx_3d("door_close", _handle_pos())

## Scripted scare: opens a crack by `angle` degrees (sign picks the side) slowly.
func peek_open(angle := 12.0, duration := 1.8) -> void:
	if locked:
		return
	AudioDirector.play_sfx_3d("door_open_creak", _handle_pos(), -4.0, 0.85)
	_set_open_state(true)
	_swing_to(angle, duration, Tween.EASE_OUT)

func lock() -> void:
	if locked:
		return
	locked = true
	AudioDirector.play_sfx_3d("door_lock", _handle_pos())

func unlock() -> void:
	if not locked:
		return
	locked = false
	AudioDirector.play_sfx_3d("door_unlock", _handle_pos())

func set_locked(on: bool) -> void:
	if on:
		lock()
	else:
		unlock()

## Instantly set state without sounds (level setup / checkpoints).
func set_open_instant(open_state: bool, angle := 95.0) -> void:
	if _tween:
		_tween.kill()
	is_open = open_state
	_apply_angle(angle if open_state else 0.0)

func _set_open_state(o: bool) -> void:
	if is_open != o:
		is_open = o
		EventBus.door_state_changed.emit(door_id, o)

func _swing_to(target: float, dur: float, ease: int) -> void:
	if _tween:
		_tween.kill()
	moving = true
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(ease)
	_tween.tween_method(_apply_angle, _angle, target, maxf(dur, 0.01))
	_tween.tween_callback(func(): moving = false)

func _apply_angle(a: float) -> void:
	_angle = a
	rotation.y = _closed_yaw + deg_to_rad(a)

func _closed_xform() -> Transform3D:
	var t := global_transform
	var parent_basis := Basis()
	if get_parent() is Node3D:
		parent_basis = (get_parent() as Node3D).global_transform.basis
	t.basis = parent_basis * Basis.from_euler(Vector3(rotation.x, _closed_yaw, rotation.z))
	return t

func _handle_pos() -> Vector3:
	return global_transform * Vector3(width - 0.1, 1.0, 0)
