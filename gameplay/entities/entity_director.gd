class_name EntityDirector
extends Node
## Small registry a level / chapter adds to control which entities are active.
##   var dir := EntityDirector.new(); level.add_child(dir)
##   dir.activate_only(["gazer_store"]); dir.get_entity("mimic_hung").survived.connect(...)
## Finds entities (group `entity`) under the level's `Entities/` node (or `entities_root`).

## Root to scan. Empty = "<parent>/Entities", else the current level's Entities/, else the parent.
@export var entities_root: NodePath
## Deactivate everything found on ready (chapters then activate what they need).
@export var deactivate_on_ready := false

var entities: Dictionary = {}     # entity_id -> Node

func _ready() -> void:
	# entities may become ready after us (sibling order), so scan deferred
	_initial_scan.call_deferred()

func _initial_scan() -> void:
	refresh()
	if deactivate_on_ready:
		deactivate_all()

## Re-scans the entities root for nodes in group `entity` and registers them.
func refresh() -> void:
	var root := _find_root()
	if root == null:
		return
	_scan(root)

func _find_root() -> Node:
	if not entities_root.is_empty():
		return get_node_or_null(entities_root)
	var p := get_parent()
	if p and p.has_node("Entities"):
		return p.get_node("Entities")
	var lvl := get_tree().get_first_node_in_group("level") if is_inside_tree() else null
	if lvl and lvl.has_node("Entities"):
		return lvl.get_node("Entities")
	return p

func _scan(n: Node) -> void:
	for c in n.get_children():
		if c.is_in_group("entity"):
			register(c)
		else:
			_scan(c)

func register(entity: Node) -> void:
	if entity == null:
		return
	var id: String = str(entity.get("entity_id")) if "entity_id" in entity else String(entity.name)
	if id == "":
		id = String(entity.name).to_snake_case()
	entities[id] = entity

func unregister(id: String) -> void:
	entities.erase(id)

func get_entity(id: String) -> Node:
	var e: Node = entities.get(id)
	if e == null or not is_instance_valid(e):
		refresh()
		e = entities.get(id)
	return e if e and is_instance_valid(e) else null

func get_ids() -> Array:
	return entities.keys()

## Activates the listed entity ids and deactivates every other registered entity.
func activate_only(ids: Array) -> void:
	if entities.is_empty():
		refresh()
	for id in entities.keys():
		var e: Node = entities[id]
		if not is_instance_valid(e):
			continue
		if id in ids:
			e.activate()
		elif e.has_method("deactivate"):
			e.deactivate()
	for id in ids:
		if not entities.has(id):
			push_warning("EntityDirector: unknown entity '%s'" % id)

func activate(id: String) -> void:
	var e := get_entity(id)
	if e:
		e.activate()

func deactivate(id: String) -> void:
	var e := get_entity(id)
	if e:
		e.deactivate()

func deactivate_all() -> void:
	for e in entities.values():
		if is_instance_valid(e) and e.has_method("deactivate"):
			e.deactivate()
