class_name MinigameShelfStock
extends MinigameBase
## "Sắp xếp kệ" — a cardboard box (storeroom) holds N products of 2–3 types.
## Interact the box -> box_open; interact again -> carry it (holdable). While carrying, aim at an
## empty shelf slot and interact: the NEXT product in the box (shown on top of the box) is placed if
## the slot's price tag matches its type (can_place), otherwise "Sai chỗ rồi" + error blip.
## All products placed -> box is put back, completed.
##
## Anchors:  BoxSpot (box rest position)  ·  slot_* Marker3Ds (origin = bottom-centre of the slot on
## the shelf board, local +Z = facing the aisle). Levels can provide MARKER_slot_* under anchors_root.
## Slot type: metadata "product_type" on the marker (a type_id), else types are assigned in
## contiguous blocks over the used slots (in natural name order).

signal product_placed(type_id: String, remaining: int)
signal wrong_slot(type_id: String)

@export var product_count := 8
## Product types (empty = first `type_count` of MinigameProduct.defaults()).
@export var products: Array[MinigameProduct] = []
@export_range(1, 3) var type_count := 2
@export var slot_prefix := "slot_"
@export var box_model: PackedScene
@export var wrong_toast := "Sai chỗ rồi"
@export var slot_size := Vector3(0.2, 0.18, 0.26)
@export var show_price_tags := true
## Price tag position relative to the slot marker (front edge of the shelf board).
@export var tag_offset := Vector3(0, -0.04, 0.18)
@export var random_seed := 0
@export var display_font: Font

var box: MinigameItem
var slots: Array[MinigameButton] = []
var box_open := false
var placed := 0
var _contents: Array[MinigameProduct] = []
var _types: Array[MinigameProduct] = []
var _flaps: Array[Node3D] = []
var _preview_root: Node3D
var _rng := RandomNumberGenerator.new()
var _placed_nodes: Array[Node] = []

# ---------------------------------------------------------------- setup
func _build_placeholder() -> void:
	var ph := Node3D.new()
	ph.name = "Placeholder"
	add_child(ph)
	var c := Color(0.55, 0.57, 0.6)
	# gondola: back panel + 3 boards + base
	MinigameUtil.solid_box(ph, Vector3(1.3, 1.6, 0.04), c.darkened(0.2), Vector3(0, 0.8, -0.22))
	MinigameUtil.solid_box(ph, Vector3(1.3, 0.25, 0.45), c.darkened(0.35), Vector3(0, 0.125, 0))
	for y in [0.5, 0.95, 1.4]:
		MinigameUtil.solid_box(ph, Vector3(1.3, 0.03, 0.44), c, Vector3(0, y - 0.015, 0))
	MinigameUtil.solid_box(ph, Vector3(0.04, 1.6, 0.45), c.darkened(0.25), Vector3(-0.67, 0.8, 0))
	MinigameUtil.solid_box(ph, Vector3(0.04, 1.6, 0.45), c.darkened(0.25), Vector3(0.67, 0.8, 0))
	# storeroom crate stack under the box spot
	var bs := get_anchor("BoxSpot")
	if bs:
		var crate := MinigameUtil.solid_box(ph, Vector3(0.6, bs.position.y, 0.5), Color(0.45, 0.35, 0.22), Vector3.ZERO)
		crate.global_position = bs.global_position - Vector3(0, bs.position.y * 0.5, 0)

func _setup() -> void:
	_build_box()

func _build_box() -> void:
	box = MinigameItem.new()
	box.name = "Box"
	box.pickup_prompt = "Bê thùng"
	box.held_offset = Vector3(-0.12, -0.24, -0.02)
	box.prompt_override = _box_prompt
	box.interact_override = _box_interact
	box.pickable = false
	var size := Vector3(0.34, 0.2, 0.26)
	var m := MinigameUtil.instance_model(box_model)
	if m:
		box.add_child(m)
	else:
		box.add_child(MinigameUtil.box(size, Color(0.62, 0.47, 0.3), Vector3(0, size.y * 0.5, 0)))
		box.add_child(MinigameUtil.box(Vector3(size.x + 0.004, 0.04, 0.06), Color(0.75, 0.68, 0.5), Vector3(0, size.y * 0.5, 0)))
		for side in [-1.0, 1.0]:
			var hinge := Node3D.new()
			hinge.position = Vector3(0, size.y, side * size.z * 0.5)
			box.add_child(hinge)
			var flap := MinigameUtil.box(Vector3(size.x, 0.006, size.z * 0.5), Color(0.66, 0.5, 0.32), Vector3(0, 0, -side * size.z * 0.25))
			hinge.add_child(flap)
			hinge.set_meta("side", side)
			_flaps.append(hinge)
	MinigameUtil.add_box_collider(box, size + Vector3(0.02, 0.02, 0.02), Vector3(0, size.y * 0.5, 0))
	_preview_root = Node3D.new()
	_preview_root.name = "NextProduct"
	_preview_root.position = Vector3(0, size.y + 0.01, 0)
	box.add_child(_preview_root)
	add_child(box)
	var bs := get_anchor("BoxSpot")
	if bs:
		box.global_transform = bs.global_transform
	box.remember_home()

func _make_slots() -> void:
	for s in slots:
		s.queue_free()
	slots.clear()
	var markers := get_anchors(slot_prefix)
	var used := mini(product_count, markers.size())
	for i in used:
		var mk: Node3D = markers[i]
		var t := _slot_type(mk, i, used)
		var b := MinigameButton.create("Slot%d" % i, slot_size, _slot_prompt.bind(i), _slot_action.bind(i), Vector3(0, slot_size.y * 0.5, 0))
		b.data = {"type": t.type_id, "product": t, "filled": false, "marker": mk}
		add_child(b)
		b.global_transform = mk.global_transform
		# translucent silhouette of the expected product (shown while carrying the box)
		var ghost := Node3D.new()
		ghost.name = "Ghost"
		ghost.visible = false
		ghost.position.y = t.size.y * 0.5 + 0.002
		b.add_child(ghost)
		t.build_visual(ghost, false)
		var gmat := MinigameUtil.make_mat(Color(t.color, 0.3), true)
		_set_material_rec(ghost, gmat)
		ghost.set_meta("mat", gmat)
		ghost.set_meta("base", Color(t.color.lightened(0.3), 0.3))
		if show_price_tags:
			var tag := Node3D.new()
			tag.name = "Tag"
			tag.position = tag_offset
			b.add_child(tag)
			tag.add_child(MinigameUtil.box(Vector3(0.19, 0.07, 0.004), Color(1.0, 0.95, 0.75), Vector3.ZERO, true))
			tag.add_child(MinigameUtil.box(Vector3(0.19, 0.016, 0.005), t.color.lightened(0.15), Vector3(0, 0.027, 0), true))
			var l := MinigameUtil.label(t.display_name.to_upper() + "\n" + MinigameUtil.format_vnd(t.price), 16, 0.0015, Color(0.08, 0.08, 0.08), display_font)
			l.position = Vector3(0, -0.006, 0.004)
			l.line_spacing = -4
			tag.add_child(l)
		slots.append(b)

func _set_material_rec(n: Node, mat: Material) -> void:
	if n is GeometryInstance3D:
		n.material_override = mat
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_set_material_rec(c, mat)

func _slot_type(marker: Node3D, i: int, used: int) -> MinigameProduct:
	if marker.has_meta("product_type"):
		var id := str(marker.get_meta("product_type"))
		for t in _types:
			if t.type_id == id:
				return t
	var idx := mini(int(floor(float(i) * _types.size() / maxf(used, 1))), _types.size() - 1)
	return _types[idx]

# ---------------------------------------------------------------- flow
func _on_start() -> void:
	_rng.seed = random_seed if random_seed != 0 else randi()
	_types.clear()
	var src := products if not products.is_empty() else MinigameProduct.defaults()
	var n_types := mini(type_count, src.size()) if products.is_empty() else src.size()
	for i in n_types:
		_types.append(src[i])
	_clear_placed()
	_make_slots()
	_contents.clear()
	for s in slots:
		_contents.append(s.data.product)
	# shuffle
	for i in range(_contents.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := _contents[i]
		_contents[i] = _contents[j]
		_contents[j] = tmp
	placed = 0
	_set_box_open(false)
	box.visible = true
	box.enabled = true
	box.global_transform = box.home_transform
	_update_preview()

func _on_reset() -> void:
	if box and box.is_held():
		box.release_from_player(false)
	_clear_placed()
	for s in slots:
		s.queue_free()
	slots.clear()
	_contents.clear()
	placed = 0
	_set_box_open(false)
	_update_preview()

func _clear_placed() -> void:
	for n in _placed_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_placed_nodes.clear()

func remaining() -> int:
	return _contents.size()

func next_product() -> MinigameProduct:
	return _contents[0] if not _contents.is_empty() else null

func _box_prompt() -> String:
	if not _active or box.is_held():
		return ""
	if not box_open:
		return "Mở thùng"
	return ""   # default pickup prompt ("Bê thùng")

func _box_interact(_player: Node3D) -> bool:
	if not _active:
		return true
	if not box_open:
		open_box()
		return true
	return false

func open_box() -> void:
	if box_open:
		return
	sfx("box_open", box)
	_set_box_open(true)
	if next_product():
		toast("Xếp hàng lên kệ đúng bảng giá")

func _set_box_open(on: bool) -> void:
	box_open = on
	box.pickable = on and _active
	for h in _flaps:
		var side: float = h.get_meta("side")
		var target := side * deg_to_rad(120.0) if on else 0.0
		if is_inside_tree() and on:
			create_tween().tween_property(h, "rotation:x", target, 0.25).set_trans(Tween.TRANS_BACK)
		else:
			h.rotation.x = target

func _update_preview() -> void:
	for c in _preview_root.get_children():
		c.queue_free()
	var p := next_product()
	if p and box_open:
		var holder := Node3D.new()
		_preview_root.add_child(holder)
		p.build_visual(holder, false)
		holder.position.y = -p.size.y * 0.3

func _slot_prompt(i: int) -> String:
	if not _active or i >= slots.size():
		return ""
	var s := slots[i]
	if s.data.filled or not box.is_held() or next_product() == null:
		return ""
	return "Đặt " + next_product().display_name.to_lower()

func _slot_action(player: Node3D, i: int) -> void:
	try_place(i, player)

## Places the next product into slot i. Returns true on success.
func try_place(i: int, _player: Node3D = null) -> bool:
	if not _active or i < 0 or i >= slots.size():
		return false
	var s := slots[i]
	var p := next_product()
	if s.data.filled or p == null:
		return false
	if s.data.type != p.type_id:
		sfx("ui_back", s, -2.0)
		toast(wrong_toast)
		wrong_slot.emit(p.type_id)
		return false
	_contents.pop_front()
	s.data.filled = true
	s.enabled = false
	(s.get_node("Ghost") as Node3D).visible = false
	var vis := Node3D.new()
	vis.name = "Placed%d" % i
	add_child(vis)
	p.build_visual(vis, false)
	var target := Transform3D(s.global_basis, s.global_position + s.global_basis.y * (p.size.y * 0.5 + 0.002))
	vis.global_transform = Transform3D(target.basis, target.origin + s.global_basis.z * 0.12 + Vector3(0, 0.05, 0))
	create_tween().tween_property(vis, "global_transform", target, 0.15)
	_placed_nodes.append(vis)
	placed += 1
	sfx("can_place", s, 0.0, _rng.randf_range(0.92, 1.08))
	product_placed.emit(p.type_id, _contents.size())
	_update_preview()
	if _contents.is_empty():
		_finish()
	elif next_product().type_id != p.type_id:
		toast("Tiếp theo: " + next_product().display_name)
	return true

func _finish() -> void:
	if box.is_held():
		box.release_from_player(false)   # returns home
	box.pickable = false
	_set_box_open(false)
	complete()

# ---------------------------------------------------------------- highlight
func _tick(_delta: float) -> void:
	var carrying := box.is_held()
	var aimed := get_aimed_collider(2.0, 1 | 4) if carrying else null
	var p := next_product()
	for s in slots:
		var ghost := s.get_node("Ghost") as Node3D
		ghost.visible = carrying and not s.data.filled
		if not ghost.visible:
			continue
		var mat := ghost.get_meta("mat") as StandardMaterial3D
		if aimed == s and p:
			mat.albedo_color = Color(0.3, 1, 0.3, 0.55) if s.data.type == p.type_id else Color(1, 0.2, 0.15, 0.55)
		else:
			mat.albedo_color = ghost.get_meta("base")

# ---------------------------------------------------------------- debug / tests
func index_of_slot_for(type_id: String) -> int:
	for i in slots.size():
		if not slots[i].data.filled and slots[i].data.type == type_id:
			return i
	return -1

func _autoplay() -> void:
	open_box()
	while _active and next_product():
		await get_tree().create_timer(0.08).timeout
		if not _active or next_product() == null:
			return
		try_place(index_of_slot_for(next_product().type_id))

func debug_shot_prep(player: Node3D) -> void:
	open_box()
	box.pick_up(player)
	for k in 3:
		try_place(index_of_slot_for(next_product().type_id))
