class_name LightSwitch
extends Interactable
## Wall switch: toggles every light in `light_group` via EventBus.lights_set(group, on).
## Also directly toggles Light3D nodes in that group so it works without another listener.

@export var light_group := ""
@export var is_on := true
@export var prompt_on := "Tắt đèn"
@export var prompt_off := "Bật đèn"

func _ready() -> void:
	super._ready()
	if not _has_child_of("CollisionShape3D"):
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.12, 0.16, 0.06)
		cs.shape = b
		add_child(cs)
	if not _has_child_of("VisualInstance3D"):
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.08, 0.12, 0.02)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.83, 0.76)
		m.material = mat
		mi.mesh = m
		add_child(mi)

func _has_child_of(cls: String) -> bool:
	for c in get_children():
		if c.is_class(cls):
			return true
	return false

func get_prompt() -> String:
	if not enabled:
		return ""
	return prompt_on if is_on else prompt_off

func _on_interact(_player: Node3D) -> void:
	set_on(not is_on)

func set_on(on: bool, play_sound := true) -> void:
	is_on = on
	if play_sound:
		AudioDirector.play_sfx_3d("light_switch", global_position, -2.0)
	if light_group == "":
		return
	for n in get_tree().get_nodes_in_group(light_group):
		if n is Light3D:
			n.visible = on
	EventBus.lights_set.emit(light_group, on)
