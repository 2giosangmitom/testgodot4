class_name PickupItem
extends Interactable
## Small item on physics layer 6 (pickup = 32). Interact:
##  - inventory_item = false: the player holds it in front of the camera (player.hold_item).
##    Pressing interact with nothing targeted drops it (snapped to the floor).
##  - inventory_item = true: sets GameState flag `has_<item_id>`, shows a toast and disappears
##    (incense, old photo, lamp oil in Ch3).
## Default mesh/collision: a soda can (r 0.033, h 0.12) if no children are given.

@export var item_id := ""
@export var display_name := ""
@export var inventory_item := false
@export var hold_offset := Vector3.ZERO

func _init() -> void:
	prompt = "Nhặt"

func _ready() -> void:
	super._ready()
	collision_layer = 32
	set_meta("hold_offset", hold_offset)
	add_to_group("pickup")
	var has_col := false
	var has_vis := false
	for c in get_children():
		if c is CollisionShape3D:
			has_col = true
		elif c is Node3D:
			has_vis = true
	if not has_col:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.05
		cyl.height = 0.12
		cs.shape = cyl
		cs.position.y = 0.06
		add_child(cs)
	if not has_vis:
		var mi := MeshInstance3D.new()
		var m := CylinderMesh.new()
		m.top_radius = 0.033
		m.bottom_radius = 0.033
		m.height = 0.12
		m.radial_segments = 8
		m.rings = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.7, 0.15, 0.12)
		m.material = mat
		mi.mesh = m
		mi.position.y = 0.06
		add_child(mi)

func _on_interact(player: Node3D) -> void:
	if inventory_item:
		GameState.set_flag("has_" + item_id, true)
		AudioDirector.play_sfx("item_pickup", -4.0)
		if display_name != "":
			EventBus.toast.emit("Đã nhặt: " + display_name)
		queue_free()
	elif player and player.has_method("hold_item"):
		player.hold_item(self)
