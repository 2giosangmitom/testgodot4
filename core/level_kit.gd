class_name LevelKit
extends RefCounted
## Helpers for assembling levels from Blender env glbs (markers are Node3D named "MARKER_<name>").

## Finds MARKER_<name> anywhere under root (null if missing).
static func marker(root: Node, name: String) -> Node3D:
	return root.find_child("MARKER_" + name, true, false) as Node3D

## All markers whose name (without the MARKER_ prefix) starts with `prefix`, sorted by name (natural order).
static func markers(root: Node, prefix: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in root.find_children("MARKER_" + prefix + "*", "Node3D", true, false):
		out.append(n)
	out.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return out

## Instances `scene` as a child of `parent` at the marker's global transform (position + rotation, unit scale).
static func place(parent: Node, scene: PackedScene, at: Node3D, node_name := "") -> Node3D:
	var inst := scene.instantiate() as Node3D
	if node_name != "":
		inst.name = node_name
	parent.add_child(inst)
	inst.global_transform = Transform3D(at.global_basis.orthonormalized(), at.global_position)
	return inst

## Adds an OmniLight3D (cheap PS1-style) at a marker. Returns the light.
static func omni(parent: Node, at: Node3D, color: Color, energy: float, range_m: float, group := "", flicker_mode := -1) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = at.global_position
	if group != "":
		l.add_to_group(group)
	if flicker_mode >= 0:
		var f := FlickerLight.new()
		f.mode = flicker_mode
		f.groups = PackedStringArray([group]) if group != "" else PackedStringArray()
		l.add_child(f)
	return l

## Adds a SpotLight3D pointing along the marker's -Z (markers for lamps point down).
static func spot(parent: Node, at: Node3D, color: Color, energy: float, range_m: float, angle_deg := 60.0, group := "") -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.spot_range = range_m
	l.spot_angle = angle_deg
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_transform = Transform3D(at.global_basis.orthonormalized(), at.global_position)
	if group != "":
		l.add_to_group(group)
	return l
