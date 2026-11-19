class_name MinigameSleep
extends MinigameBase
## "Đi ngủ" — interact the bed/mattress: locks input (input_lock_reason), requests a fade to black,
## waits fade_time, then completes. The chapter decides what happens next and must call
## GameState.unlock_input(input_lock_reason) + EventBus.fade_request(false, ...) itself.
## Optional `require` (MinigameBase NodePaths) must be completed first; otherwise their
## pending_hint is toasted.
## Anchor: mattress centre at this node's origin.

signal slept

@export var require: Array[NodePath] = []
@export var fade_time := 1.5
@export var input_lock_reason := "sleep"
@export var bed_model: PackedScene
@export var bed_size := Vector3(0.9, 0.25, 1.9)
@export var prompt_text := "Đi ngủ"

var _sleeping := false

func _setup() -> void:
	var m := MinigameUtil.instance_model(bed_model)
	if m == null:
		m = Node3D.new()
		m.add_child(MinigameUtil.box(bed_size, Color(0.6, 0.62, 0.66), Vector3(0, bed_size.y * 0.5, 0)))
		m.add_child(MinigameUtil.box(Vector3(bed_size.x * 0.6, 0.08, 0.3), Color(0.85, 0.85, 0.82), Vector3(0, bed_size.y + 0.04, -bed_size.z * 0.5 + 0.22)))
		m.add_child(MinigameUtil.box(Vector3(bed_size.x * 1.01, 0.03, bed_size.z * 0.55), Color(0.35, 0.42, 0.55), Vector3(0, bed_size.y + 0.01, bed_size.z * 0.2)))
	add_child(m)
	var b := MinigameButton.create("BedButton", bed_size + Vector3(0, 0.1, 0), _prompt, func(_p): try_sleep(), Vector3(0, bed_size.y * 0.5, 0))
	add_child(b)

func _prompt() -> String:
	return prompt_text if _active and not _sleeping else ""

func missing_hints() -> PackedStringArray:
	var out := PackedStringArray()
	for np in require:
		var n := get_node_or_null(np)
		if n is MinigameBase and not n.is_completed():
			var hint: String = n.get("pending_hint") if "pending_hint" in n else "Còn việc chưa làm."
			out.append(hint)
	return out

## Returns false (and toasts what is missing) when requirements are not met.
func try_sleep() -> bool:
	if not _active or _sleeping:
		return false
	var miss := missing_hints()
	if not miss.is_empty():
		toast(" ".join(miss))
		return false
	_sleeping = true
	GameState.lock_input(input_lock_reason)
	EventBus.fade_request.emit(true, fade_time)
	await get_tree().create_timer(maxf(fade_time, 0.0) + 0.1).timeout
	_sleeping = false
	slept.emit()
	complete()
	return true

func _on_reset() -> void:
	_sleeping = false

func _autoplay() -> void:
	for np in require:
		var n := get_node_or_null(np)
		if n is MinigameBase and not n.is_completed():
			if not n.is_active():
				n.start()
			n.complete()
	await try_sleep()
