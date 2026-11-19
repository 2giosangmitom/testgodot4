class_name MinigameRoomRoutine
extends MinigameBase
## Bedtime routine: groups child minigames (LightSwitch "lamp_switch_off", DoorLock
## "check_door_lock", Sleep "go_to_sleep" by default). start() starts every child; completed when all
## children are completed. With enforce_order the bed refuses until the others are done
## (toasting their pending_hint). Children can also be used on their own in levels.
##
## Pass-through exports so levels don't need editable children:
##   door_path   -> DoorLock.door_path (resolved relative to this node)
##   light_group -> LightSwitch.light_group

@export var enforce_order := true
@export var door_path: NodePath
@export var light_group := ""

var parts: Array[MinigameBase] = []

func _setup() -> void:
	parts.clear()
	var bed: MinigameSleep = null
	for c in get_children():
		if c is MinigameBase:
			parts.append(c)
			c.completed.connect(_on_part_done)
			if c is MinigameSleep:
				bed = c
			if c is MinigameDoorLock and not door_path.is_empty() and has_node(door_path):
				c.door_path = c.get_path_to(get_node(door_path))
			if c is MinigameLightSwitch and light_group != "":
				c.light_group = light_group
	if enforce_order and bed and bed.require.is_empty():
		for p in parts:
			if p != bed:
				bed.require.append(bed.get_path_to(p))

func _on_start() -> void:
	for p in parts:
		if not p.is_active() and not p.is_completed():
			p.start()

func _on_reset() -> void:
	for p in parts:
		p.reset()

func _on_part_done() -> void:
	if not _active:
		return
	for p in parts:
		if not p.is_completed():
			return
	complete()

func get_part(id: String) -> MinigameBase:
	for p in parts:
		if p.minigame_id == id:
			return p
	return null

func _autoplay() -> void:
	# children run their own autoplay (they were started with debug_autoplay on)
	while _active:
		await get_tree().create_timer(0.1).timeout
