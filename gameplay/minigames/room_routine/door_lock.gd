class_name MinigameDoorLock
extends MinigameBase
## "Kiểm tra khóa cửa" — interact the lock. Works with a Door node (door_path) duck-typed:
##   lock()/unlock(), `locked` property or is_locked(), optional `is_open`/is_open() + close().
## Without a door it keeps its own locked state. Checking an unlocked door locks it (door_lock).
## Emits lock_checked(was_locked) and completes while active.
## Anchor: lock plate at this node's origin (faces local +Z).

signal lock_checked(was_locked: bool)

@export var door_path: NodePath
@export var lock_model: PackedScene
@export var pending_hint := "Chưa khóa cửa."
@export var start_locked := false

var _own_locked := false
var _bolt: Node3D

func _setup() -> void:
	_own_locked = start_locked
	var m := MinigameUtil.instance_model(lock_model)
	if m == null:
		m = Node3D.new()
		m.add_child(MinigameUtil.box(Vector3(0.07, 0.16, 0.02), Color(0.55, 0.5, 0.35)))
		_bolt = MinigameUtil.box(Vector3(0.05, 0.018, 0.03), Color(0.75, 0.72, 0.6), Vector3(0, 0.03, 0.02))
		m.add_child(_bolt)
		m.add_child(MinigameUtil.cylinder(0.012, 0.02, Color(0.2, 0.2, 0.2), Vector3(0, -0.04, 0.015)))
	add_child(m)
	var b := MinigameButton.create("LockButton", Vector3(0.14, 0.22, 0.1), _prompt, func(_p): check_lock())
	add_child(b)
	_update_bolt()

func get_door() -> Node:
	return get_node_or_null(door_path) if not door_path.is_empty() else null

func is_locked() -> bool:
	var d := get_door()
	if d:
		if d.has_method("is_locked"):
			return d.is_locked()
		if "locked" in d:
			return bool(d.get("locked"))
	return _own_locked

func _door_open(d: Node) -> bool:
	if d == null:
		return false
	if d.has_method("is_open"):
		return d.is_open()
	if "is_open" in d:
		return bool(d.get("is_open"))
	if "open" in d and typeof(d.get("open")) == TYPE_BOOL:
		return d.get("open")
	return false

func _prompt() -> String:
	if not _active and is_locked():
		return "Mở khóa"
	return "Kiểm tra khóa" if _active else "Khóa cửa"

func check_lock() -> void:
	var was := is_locked()
	var d := get_door()
	if not _active and was:
		# outside the routine the player may unlock again
		_set_locked(false)
		return
	if was:
		toast("Cửa đã khóa.")
		sfx("door_handle_rattle", self, -10.0)
	else:
		if _door_open(d) and d.has_method("close"):
			d.close()
		_set_locked(true)
		toast("Đã khóa cửa.")
	lock_checked.emit(was)
	if _active:
		complete()

func _set_locked(on: bool) -> void:
	var d := get_door()
	if d:
		if on and d.has_method("lock"):
			d.lock()
		elif not on and d.has_method("unlock"):
			d.unlock()
		elif "locked" in d:
			d.set("locked", on)
	_own_locked = on
	sfx("door_lock" if on else "door_unlock", self)
	_update_bolt()

func _update_bolt() -> void:
	if _bolt:
		_bolt.position.x = 0.03 if is_locked() else 0.0

func _autoplay() -> void:
	check_lock()
