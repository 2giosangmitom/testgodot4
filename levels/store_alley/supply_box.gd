extends MinigameShelfStock
## Use the modeled open carton in place of the shared game's placeholder flap animation.

const OPEN_CARTON := preload("res://assets/models/props/cardboard_box_open.glb")
var _closed_carton: Node3D
var _open_carton: Node3D

func _setup() -> void:
	super._setup()
	_closed_carton = box.get_child(0) as Node3D
	_open_carton = OPEN_CARTON.instantiate()
	box.add_child(_open_carton)
	_open_carton.hide()
	var shape: CollisionShape3D
	for child in box.get_children():
		if child is CollisionShape3D:
			shape = child
			break
	if shape:
		(shape.shape as BoxShape3D).size = Vector3(0.4, 0.3, 0.3)
		shape.position.y = 0.15
	_preview_root.position.y = 0.32

func _set_box_open(on: bool) -> void:
	super._set_box_open(on)
	_closed_carton.visible = not on
	_open_carton.visible = on

func _update_preview() -> void:
	super._update_preview()
	PSXApply.apply_to(_preview_root)

func try_place(i: int, player: Node3D = null) -> bool:
	if not super.try_place(i, player):
		return false
	PSXApply.apply_to(_placed_nodes.back())
	return true
