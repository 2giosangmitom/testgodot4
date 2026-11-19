extends Node3D
## Minimal duck-typed door for entity tests (the real Door is Track props).
## Node origin = hinge. API used by Mimic: door_id, is_open(), is_locked(), lock(), unlock(),
## force_open(duration). Emits EventBus.door_state_changed.

@export var door_id := "test_door"
@export var locked := false

var _open := false
var _tween: Tween

func _enter_tree() -> void:
	add_to_group("test_door")

func is_open() -> bool:
	return _open

func is_locked() -> bool:
	return locked

func lock() -> void:
	locked = true
	AudioDirector.play_sfx_3d("door_lock", global_position + Vector3.UP)

func unlock() -> void:
	locked = false
	AudioDirector.play_sfx_3d("door_unlock", global_position + Vector3.UP)

func toggle() -> void:
	if _open:
		set_open(false)
	elif locked:
		unlock()
	else:
		set_open(true)

func set_open(on: bool, duration := 0.6) -> void:
	if on == _open:
		return
	_open = on
	if on:
		locked = false
	_swing(deg_to_rad(95.0) if on else 0.0, duration)
	AudioDirector.play_sfx_3d("door_open_creak" if on else "door_close", global_position + Vector3.UP)
	EventBus.door_state_changed.emit(door_id, on)

## Opens slowly by itself (entity breach). Does not re-emit if already open.
func force_open(duration := 2.0) -> void:
	if _open:
		return
	_open = true
	locked = false
	_swing(deg_to_rad(80.0), duration)

func _swing(angle: float, duration: float) -> void:
	if _tween:
		_tween.kill()
	if not is_inside_tree():
		rotation.y = angle
		return
	_tween = create_tween()
	_tween.tween_property(self, "rotation:y", angle, duration)
