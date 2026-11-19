class_name TriggerZone
extends Area3D
## Player-only trigger volume. Layer 5 (16), mask player (2).
## On enter: emits `triggered`, sets GameState flag `trig_<trigger_id>`.
## Chapter scripts can `await GameState flag` via ChapterScript.wait_flag("trig_<id>").

signal triggered(body: Node3D)
signal exited(body: Node3D)

@export var trigger_id := ""
@export var once := true
@export var size := Vector3(2, 2, 2)
## Optional objective completed when triggered.
@export var objective_id := ""

var fired := false

func _ready() -> void:
	collision_layer = 16
	collision_mask = 2
	monitoring = true
	monitorable = false
	var has_shape := false
	for c in get_children():
		if c is CollisionShape3D:
			has_shape = true
	if not has_shape:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = size
		cs.shape = b
		cs.position = Vector3(0, size.y * 0.5, 0)
		add_child(cs)
	body_entered.connect(_on_enter)
	body_exited.connect(func(b: Node3D): if b.is_in_group("player"): exited.emit(b))

func _on_enter(b: Node3D) -> void:
	if not b.is_in_group("player"):
		return
	if once and fired:
		return
	fired = true
	if trigger_id != "":
		GameState.set_flag("trig_" + trigger_id, true)
	if objective_id != "":
		GameState.complete_objective(objective_id)
	triggered.emit(b)
	if once:
		set_deferred("monitoring", false)

func reset() -> void:
	fired = false
	monitoring = true
