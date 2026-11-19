class_name MinigameButton
extends Interactable
## An Interactable whose prompt / availability / action are supplied by its minigame through
## callables, so one class serves registers, stove knobs, shelf slots, switches, beds...
##   prompt_func: func() -> String   ("" = not interactable right now, prompt hidden)
##   action_func: func(player) -> void

var prompt_func: Callable
var action_func: Callable
## Arbitrary data for the owner (slot type, index, ...).
var data: Dictionary = {}

static func create(p_name: String, size: Vector3, p_prompt: Callable, p_action: Callable, offset := Vector3.ZERO) -> MinigameButton:
	var b := MinigameButton.new()
	b.name = p_name
	b.prompt_func = p_prompt
	b.action_func = p_action
	MinigameUtil.add_box_collider(b, size, offset)
	return b

func get_prompt() -> String:
	if not enabled:
		return ""
	if prompt_func.is_valid():
		return prompt_func.call()
	return prompt

func can_interact(_player: Node3D) -> bool:
	return enabled and get_prompt() != ""

func _on_interact(player: Node3D) -> void:
	if action_func.is_valid():
		action_func.call(player)
