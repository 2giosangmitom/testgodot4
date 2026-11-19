extends Node3D
## Test-only stand-in for the real Door (duck-typed lock()/unlock()/locked/is_open/close()).

signal lock_changed(locked: bool)

@export var locked := false
@export var is_open := false

func _ready() -> void:
	var panel := MinigameUtil.box(Vector3(0.9, 2.1, 0.05), Color(0.45, 0.3, 0.2), Vector3(0, 1.05, 0))
	add_child(panel)
	add_child(MinigameUtil.box(Vector3(0.04, 0.04, 0.08), Color(0.7, 0.7, 0.6), Vector3(0.36, 0.95, 0.03)))
	add_child(MinigameUtil.label("P.204", 16, 0.003, Color(0.9, 0.9, 0.8)))
	get_child(get_child_count() - 1).position = Vector3(0, 1.75, 0.03)

func lock() -> void:
	locked = true
	lock_changed.emit(true)

func unlock() -> void:
	locked = false
	lock_changed.emit(false)

func close() -> void:
	is_open = false
