class_name HideSpot
extends Area3D
## Volume under a desk / counter / bed. The player is hidden while CROUCHED inside it
## (Player checks overlapping areas in group `hide_spot`). Layer 5 (trigger), mask 2 (player).

@export var size := Vector3(1.0, 0.8, 0.8)

signal player_entered
signal player_exited

func _ready() -> void:
	add_to_group("hide_spot")
	collision_layer = 16
	collision_mask = 2
	monitorable = true
	monitoring = true
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
	body_entered.connect(func(b: Node): if b.is_in_group("player"): player_entered.emit())
	body_exited.connect(func(b: Node): if b.is_in_group("player"): player_exited.emit())
