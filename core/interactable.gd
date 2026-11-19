class_name Interactable
extends StaticBody3D
## Base for anything the player can use with E / left click.
## Put the collider on physics layer 3 ("interactable"). Player's raycast calls get_prompt()/interact().
## Subclass and override _on_interact(), or connect to `used`.

signal used(player: Node3D)

@export var prompt := "Tương tác"
@export var enabled := true
@export var one_shot := false
## Optional objective completed on use.
@export var objective_id := ""

func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 1 << 2
	collision_mask = 0

func get_prompt() -> String:
	return prompt if enabled else ""

func can_interact(_player: Node3D) -> bool:
	return enabled

func interact(player: Node3D) -> void:
	if not can_interact(player):
		return
	_on_interact(player)
	used.emit(player)
	EventBus.interacted.emit(self)
	if objective_id != "":
		GameState.complete_objective(objective_id)
	if one_shot:
		enabled = false

func _on_interact(_player: Node3D) -> void:
	pass
