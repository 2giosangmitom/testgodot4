class_name MinigameLightSwitch
extends MinigameBase
## Wall switch. Always usable (it is a real switch); while the minigame is active, turning the
## lights OFF completes it ("Tắt đèn trước khi ngủ"). Emits EventBus.lights_set(light_group, on) and,
## if direct_toggle, also shows/hides Light3D nodes in that group itself.
## Anchor: the switch sits at this node's origin (plate faces local +Z).

signal toggled(on: bool)

@export var light_group := "room_lights"
@export var lights_on := true
@export var direct_toggle := true
@export var switch_model: PackedScene
## Hint shown by RoomRoutine/bed when this is still pending.
@export var pending_hint := "Chưa tắt đèn."

var _lever: Node3D

func _setup() -> void:
	var m := MinigameUtil.instance_model(switch_model)
	if m == null:
		m = Node3D.new()
		m.add_child(MinigameUtil.box(Vector3(0.08, 0.12, 0.015), Color(0.88, 0.86, 0.8)))
		_lever = MinigameUtil.box(Vector3(0.02, 0.035, 0.015), Color(0.95, 0.95, 0.92), Vector3(0, 0, 0.012))
		m.add_child(_lever)
	add_child(m)
	if _lever == null:
		_lever = m.find_child("Lever", true, false) as Node3D
	var b := MinigameButton.create("SwitchButton", Vector3(0.14, 0.18, 0.08), _prompt, func(_p): toggle())
	add_child(b)
	_update_lever()

func _prompt() -> String:
	return "Tắt đèn" if lights_on else "Bật đèn"

func toggle() -> void:
	set_lights(not lights_on)

func set_lights(on: bool) -> void:
	lights_on = on
	sfx("light_switch", self)
	EventBus.lights_set.emit(light_group, on)
	if direct_toggle and is_inside_tree():
		for l in get_tree().get_nodes_in_group(light_group):
			if l is Light3D:
				l.visible = on
	_update_lever()
	toggled.emit(on)
	if _active and not on:
		complete()

func _update_lever() -> void:
	if _lever:
		_lever.rotation.x = 0.0 if lights_on else deg_to_rad(35.0)
		_lever.position.y = 0.012 if lights_on else -0.012

func _on_start() -> void:
	if not lights_on:
		# already dark: counts as done
		complete.call_deferred()

func _autoplay() -> void:
	if lights_on:
		set_lights(false)
