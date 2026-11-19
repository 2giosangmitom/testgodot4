class_name CaughtSequence
extends Node
## Shared "you were caught" jumpscare (~2.5 s) and a non-lethal scare variant.
##
##   var seq := CaughtSequence.play(entity_node, player)   # lethal
##   await seq.finished
##   var s := CaughtSequence.scare(entity_node, player)    # non-lethal: look + snap back
##
## Lethal flow: lock input -> forced look at the face -> entity snaps right in front of the camera,
## face_distort / shader `distort` ramps to 1, jumpscare_sting + static_burst, static 1, shake,
## fade to black (EventBus.fade_request(true, 0.4)) -> `finished` and
## EventBus.entity_state_changed(<entity_id>, "caught_done"). It does NOT reload anything:
## the main session reloads the checkpoint after `finished` / "caught_done".
## (EventBus.player_caught is emitted by the entity when the catch starts.)

signal finished
## Emitted at the scariest frame (face closest / most distorted). Gazer vanishes on it.
signal peak

const SCENE_PATH := "res://gameplay/entities/caught_sequence.tscn"

static var current: CaughtSequence = null

@export var look_time := 0.2
@export var snap_distance := 0.55
@export var hold_time := 1.35
@export var fade_time := 0.4

var entity: Node3D
var player: Node3D
var lethal := true
var running := false

static func play(entity_node: Node3D, player_node: Node3D) -> CaughtSequence:
	var seq := _make(entity_node, player_node, true)
	if seq:
		seq._run_caught()
	return seq

static func scare(entity_node: Node3D, player_node: Node3D) -> CaughtSequence:
	var seq := _make(entity_node, player_node, false)
	if seq:
		seq._run_scare()
	return seq

static func _make(entity_node: Node3D, player_node: Node3D, is_lethal: bool) -> CaughtSequence:
	if entity_node == null or not entity_node.is_inside_tree():
		return null
	var seq: CaughtSequence
	if ResourceLoader.exists(SCENE_PATH):
		seq = load(SCENE_PATH).instantiate()
	else:
		seq = CaughtSequence.new()
	seq.entity = entity_node
	seq.player = player_node
	seq.lethal = is_lethal
	seq.name = "CaughtSequence" if is_lethal else "ScareSequence"
	entity_node.get_tree().root.add_child(seq)
	if is_lethal:
		current = seq
	return seq

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# ------------------------------------------------------------------ lethal

func _run_caught() -> void:
	running = true
	var lock := "caught"
	GameState.lock_input(lock)
	_controls(false)
	var body := find_body(entity)
	_look(_face(body), look_time)
	AudioDirector.play_sfx("breath_scared", -6.0, 1.0, "SFX")
	await _wait(look_time + 0.05)
	if not _valid():
		_finish(lock)
		return
	# snap right in front of the camera
	_snap_in_front(body)
	_look(_face(body), 0.05)
	AudioDirector.play_sfx("jumpscare_sting", 0.0, 1.0, "Entity")
	AudioDirector.play_sfx("static_burst", -4.0, 1.0, "SFX")
	RenderSettings.set_static(1.0)
	EventBus.camera_shake.emit(1.0, hold_time)
	if body:
		var tw := create_tween()
		tw.tween_method(func(v: float):
			if is_instance_valid(body):
				body.set_shape("face_distort", v), body.get_shape("face_distort"), 1.0, 0.5)
	await _wait(0.35)
	peak.emit()
	await _wait(maxf(hold_time - 0.35 - fade_time * 0.5, 0.1))
	EventBus.fade_request.emit(true, fade_time)
	await _wait(fade_time + 0.1)
	_finish(lock)

# ------------------------------------------------------------------ non-lethal

func _run_scare() -> void:
	running = true
	var lock := "scare"
	GameState.lock_input(lock)
	_controls(false)
	var cam := _cam()
	var back_point := Vector3.ZERO
	if cam:
		back_point = cam.global_position - cam.global_basis.z * 5.0
	var body := find_body(entity)
	AudioDirector.play_sfx("stinger_low", 0.0, 1.0, "Entity")
	_look(_face(body), 0.18)
	EventBus.camera_shake.emit(0.35, 0.5)
	RenderSettings.set_static(0.45)
	var prev_distort: float = body.get_shape("face_distort") if body else 0.0
	if body:
		body.set_shape("face_distort", 0.55)
	await _wait(0.6)
	peak.emit()
	await _wait(0.3)
	if body and is_instance_valid(body):
		body.set_shape("face_distort", prev_distort)
	RenderSettings.set_static(0.0)
	if cam and is_instance_valid(cam):
		_look(back_point, 0.1)   # snap back
	await _wait(0.15)
	_finish(lock)

# ------------------------------------------------------------------ helpers

func _finish(lock: String) -> void:
	if lethal:
		RenderSettings.set_static(0.0)
	GameState.unlock_input(lock)
	_controls(true)
	running = false
	if current == self:
		current = null
	if lethal:
		EventBus.entity_state_changed.emit(_entity_id(), "caught_done")
	finished.emit()
	queue_free()

func _valid() -> bool:
	return is_instance_valid(entity) and entity.is_inside_tree()

func _controls(on: bool) -> void:
	if player and is_instance_valid(player) and player.has_method("set_controls_enabled"):
		player.set_controls_enabled(on)

func _cam() -> Camera3D:
	if player and is_instance_valid(player) and player.has_method("get_camera"):
		return player.get_camera()
	return get_viewport().get_camera_3d()

func _face(body: EntityBody) -> Vector3:
	if body and is_instance_valid(body):
		return body.get_head_global_position()
	if _valid():
		return entity.global_position + Vector3.UP * 1.6
	return Vector3.ZERO

func _look(pos: Vector3, dur: float) -> void:
	if player and is_instance_valid(player) and player.has_method("look_at_point"):
		player.look_at_point(pos, dur)
		return
	var cam := _cam()
	if cam and not cam.global_position.is_equal_approx(pos):
		cam.look_at(pos, Vector3.UP)

func _snap_in_front(body: EntityBody) -> void:
	var cam := _cam()
	if cam == null or not _valid():
		return
	var cp := cam.global_position
	var fwd := -cam.global_basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.01:
		flat = Vector3(entity.global_position.x - cp.x, 0.0, entity.global_position.z - cp.z)
	flat = flat.normalized() if flat.length() > 0.001 else Vector3.FORWARD
	# face the camera
	entity.global_rotation = Vector3(0.0, atan2(flat.x, flat.z), 0.0)
	if body:
		body.set_head_yaw(0.0)
		body.set_head_pitch(0.0)
	var target_face := cp + flat * snap_distance + Vector3.DOWN * 0.04
	var off := _face(body) - entity.global_position
	entity.global_position = target_face - off

func _wait(t: float) -> Signal:
	return get_tree().create_timer(t, true, false, true).timeout

func _entity_id() -> String:
	var n: Node = entity if is_instance_valid(entity) else null
	while n:
		if n is EntityBase:
			return (n as EntityBase).entity_id
		n = n.get_parent()
	return ""

## Finds the EntityBody of an entity node (its `Body` child, or the first EntityBody below it).
static func find_body(n: Node) -> EntityBody:
	if n == null or not is_instance_valid(n):
		return null
	if n is EntityBody:
		return n
	var b := n.get_node_or_null("Body")
	if b is EntityBody:
		return b
	for c in n.get_children():
		var r := find_body(c)
		if r:
			return r
	return null
