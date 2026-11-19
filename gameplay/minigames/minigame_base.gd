class_name MinigameBase
extends Node3D
## Base for every minigame scene root.
##   start() / is_active() / is_completed() / reset() / complete()
##   signal started, signal completed  (+ EventBus.minigame_completed(minigame_id),
##   GameState.complete_objective(objective_id))
## Game logic runs in _tick(delta) (only while active) so tests can fast-forward time by calling
## advance(seconds). With GameState.debug_autoplay the minigame finishes itself shortly after start().
##
## Anchors: subclasses look up placement markers with get_anchor("BagSpot") / get_anchors("slot_").
## Lookup order: descendants of `anchors_root` (a level's Markers node; names may carry a "MARKER_"
## prefix), then this scene's own descendants. Levels can therefore reposition everything without
## editing the minigame scene.

signal started
signal completed

@export var minigame_id := ""
## Objective completed when the minigame is done ("" = none).
@export var objective_id := ""
## If set (and objective_id too) start() adds the objective with this text.
@export var objective_text := ""
@export var auto_start := false
## Optional node (e.g. a level's Markers/) searched first for anchors.
@export var anchors_root: NodePath
## Build primitive furniture (counter, shelf, table, bed...) for standalone testing. Levels: false.
@export var build_placeholder := true
## Multiplies game time (tests / tuning).
@export var time_scale := 1.0
## Seconds before debug autoplay finishes the minigame.
@export var autoplay_delay := 0.6

var _active := false
var _done := false
var _setup_done := false

func _ready() -> void:
	add_to_group("minigame")
	_ensure_setup()
	if auto_start:
		start.call_deferred()

func _ensure_setup() -> void:
	if _setup_done:
		return
	_setup_done = true
	if build_placeholder:
		_build_placeholder()
	_setup()

# ---------------------------------------------------------------- public API
func start() -> void:
	_ensure_setup()
	if _active:
		return
	if _done:
		reset()
	_active = true
	if objective_id != "" and objective_text != "":
		GameState.add_objective(objective_id, objective_text)
	_on_start()
	started.emit()
	if GameState.debug_autoplay:
		_run_autoplay()

func is_active() -> bool:
	return _active

func is_completed() -> bool:
	return _done

func reset() -> void:
	_active = false
	_done = false
	_on_reset()

## Finishes the minigame (idempotent).
func complete() -> void:
	if _done:
		return
	_done = true
	_active = false
	_on_complete()
	if objective_id != "":
		GameState.complete_objective(objective_id)
	completed.emit()
	EventBus.minigame_completed.emit(minigame_id)

## Fast-forward game logic (tests). Steps in small increments so thresholds are hit in order.
func advance(seconds: float, step := 0.1) -> void:
	var t := 0.0
	while t < seconds and _active:
		var d := minf(step, seconds - t)
		_tick(d)
		t += d

# ---------------------------------------------------------------- overridables
func _build_placeholder() -> void:
	pass

func _setup() -> void:
	pass

func _on_start() -> void:
	pass

func _on_reset() -> void:
	pass

func _on_complete() -> void:
	pass

func _tick(_delta: float) -> void:
	pass

## Debug autoplay: simulate the minigame quickly. Default just waits; complete() follows.
func _autoplay() -> void:
	pass

# ---------------------------------------------------------------- internals / helpers
func _process(delta: float) -> void:
	if _active:
		_tick(delta * time_scale)

func _run_autoplay() -> void:
	await get_tree().create_timer(autoplay_delay).timeout
	if not _active:
		return
	await _autoplay()
	if _active:
		complete()

func get_player() -> Node3D:
	return MinigameItem.find_player(self)

func toast(text: String) -> void:
	EventBus.toast.emit(text)

func sfx(name: String, at: Node3D = null, volume_db := 0.0, pitch := 1.0) -> void:
	MinigameUtil.sfx(name, at if at else self, volume_db, pitch)

func get_anchor(anchor_name: String) -> Node3D:
	var roots: Array[Node] = []
	if not anchors_root.is_empty() and has_node(anchors_root):
		roots.append(get_node(anchors_root))
	roots.append(self)
	for r in roots:
		for n in [anchor_name, "MARKER_" + anchor_name]:
			var found := r.find_child(n, true, false)
			if found is Node3D:
				return found
	return null

## All Node3D anchors whose name starts with `prefix` (or "MARKER_" + prefix), naturally sorted.
## Searches anchors_root first; falls back to own descendants when nothing is found there.
func get_anchors(prefix: String) -> Array:
	var roots: Array[Node] = []
	if not anchors_root.is_empty() and has_node(anchors_root):
		roots.append(get_node(anchors_root))
	roots.append(self)
	for r in roots:
		var out := []
		var stack: Array[Node] = [r]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			var nm := String(n.name)
			if n != r and n is Node3D and (nm.begins_with(prefix) or nm.begins_with("MARKER_" + prefix)):
				out.append(n)
			stack.append_array(n.get_children())
		if not out.is_empty():
			return MinigameUtil.sort_by_name(out)
	return []

## Interactable/pickup aimed at by the player's camera (own short raycast, for highlights).
func get_aimed_collider(length := 2.0, mask := 1 | 4 | 32) -> Object:
	var p := get_player()
	if p == null or not p.has_method("get_camera"):
		return null
	var cam: Camera3D = p.get_camera()
	if cam == null or not cam.is_inside_tree():
		return null
	var from := cam.global_position
	var to := from - cam.global_basis.z * length
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	if p is CollisionObject3D:
		q.exclude = [p.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.get("collider")

func held_item() -> Node3D:
	var p := get_player()
	if p and p.has_method("get_held_item"):
		return p.get_held_item()
	return null
