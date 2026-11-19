class_name MinigameCheckout
extends MinigameBase
## "Quét mã vạch" — the customer puts items on the counter; the player picks one up (hold),
## rotates it (RMB + mouse / player's held_item_rotated) until the barcode face points at the
## scanner window, the scanner beeps, the price shows on the register display and the item slides
## to the bagging side. When everything is scanned, interact with the register -> drawer opens,
## total shown, completed. The customer then leaves (signal customer_done).
##
## Anchors (children of this scene, or MARKER_* under anchors_root):
##   Scanner      scanner model position
##   ScanPoint    beam origin; beam direction = its local -Z
##   Register     register position (display faces the cashier = local +Z)
##   item_spot_*  where the customer's items appear
##   BagSpot      bagging area (scanned items are stacked from here along local +X)
##   Customer / CustomerExit   placeholder customer stand + walk-away point

signal customer_done
signal item_scanned(item_name: String, price: int, total: int)

@export var item_count := 4
## Catalogue to draw from (empty = MinigameProduct.defaults()).
@export var products: Array[MinigameProduct] = []
## 0 = random each start.
@export var random_seed := 0
@export_range(5.0, 90.0) var scan_angle_deg := 35.0
@export var scan_range := 0.6
@export_range(10.0, 90.0) var beam_cone_deg := 70.0
@export var scanner_model: PackedScene
@export var register_model: PackedScene
## Optional NPC; placeholder capsule when empty. If it has walk_to(pos)/leave() they are used.
@export var customer_scene: PackedScene
@export var show_customer := true
@export var display_font: Font
@export var customer_leave_time := 2.0

var items: Array[MinigameItem] = []
var total := 0
var scanned := 0

var _rng := RandomNumberGenerator.new()
var _items_root: Node3D
var _display: Label3D
var _display_front: Label3D
var _drawer: Node3D
var _beam: MeshInstance3D
var _register_btn: MinigameButton
var _customer: Node3D
var _scan_point: Node3D

# ---------------------------------------------------------------- setup
func _build_placeholder() -> void:
	var ph := Node3D.new()
	ph.name = "Placeholder"
	add_child(ph)
	MinigameUtil.solid_box(ph, Vector3(1.9, 0.92, 0.7), Color(0.42, 0.4, 0.36), Vector3(0, 0.46, 0))
	MinigameUtil.solid_box(ph, Vector3(1.94, 0.04, 0.74), Color(0.6, 0.58, 0.52), Vector3(0, 0.94, 0))

func _setup() -> void:
	_items_root = Node3D.new()
	_items_root.name = "Items"
	add_child(_items_root)
	_scan_point = get_anchor("ScanPoint")
	# scanner
	var sc := get_anchor("Scanner")
	if sc:
		var m := MinigameUtil.instance_model(scanner_model)
		if m == null:
			m = Node3D.new()
			m.add_child(MinigameUtil.box(Vector3(0.22, 0.05, 0.16), Color(0.15, 0.15, 0.16), Vector3(0, 0.025, 0)))
			var window := MinigameUtil.box(Vector3(0.14, 0.006, 0.1), Color(0.7, 0.05, 0.05), Vector3(0, 0.052, 0), true)
			m.add_child(window)
		sc.add_child(m)
	if _scan_point:
		_beam = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.004
		cm.bottom_radius = 0.03
		cm.height = scan_range * 0.7
		cm.radial_segments = 6
		_beam.mesh = cm
		_beam.material_override = MinigameUtil.make_mat(Color(1, 0.1, 0.05, 0.25), true)
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# cylinder axis is Y; rotate so it runs along -Z of the scan point
		_beam.rotation = Vector3(-PI * 0.5, 0, 0)
		_beam.position = Vector3(0, 0, -cm.height * 0.5)
		_scan_point.add_child(_beam)
	# register
	var reg := get_anchor("Register")
	if reg:
		var m := MinigameUtil.instance_model(register_model)
		if m == null:
			m = _make_register_placeholder()
		reg.add_child(m)
		_drawer = m.find_child("Drawer", true, false) as Node3D
		_display = MinigameUtil.label("", 18, 0.0015, Color(0.55, 1.0, 0.55), display_font)
		_display.name = "Display"
		_display.line_spacing = -2
		var anchor := m.find_child("DisplayAnchor", true, false) as Node3D
		(anchor if anchor else reg).add_child(_display)
		if anchor == null:
			_display.position = Vector3(0, 0.2, 0.08)
		_display_front = MinigameUtil.label("", 16, 0.0016, Color(0.55, 1.0, 0.55), display_font)
		_display_front.rotation.y = PI
		var fa := m.find_child("CustomerDisplayAnchor", true, false) as Node3D
		(fa if fa else reg).add_child(_display_front)
		_register_btn = MinigameButton.create("RegisterButton", Vector3(0.36, 0.3, 0.32), _register_prompt, press_register, Vector3(0, 0.12, 0))
		reg.add_child(_register_btn)
	_set_display("ÁNH DƯƠNG 24H", "XIN CHÀO")

func _make_register_placeholder() -> Node3D:
	var m := Node3D.new()
	m.add_child(MinigameUtil.box(Vector3(0.34, 0.1, 0.3), Color(0.2, 0.2, 0.22), Vector3(0, 0.05, 0)))
	var drawer := MinigameUtil.box(Vector3(0.3, 0.07, 0.26), Color(0.3, 0.3, 0.32), Vector3(0, -0.02, 0.01))
	drawer.name = "Drawer"
	m.add_child(drawer)
	# keypad
	m.add_child(MinigameUtil.box(Vector3(0.2, 0.02, 0.1), Color(0.55, 0.55, 0.5), Vector3(0, 0.11, 0.08)))
	# cashier screen (tilted toward +Z)
	var scr := Node3D.new()
	scr.name = "ScreenPivot"
	scr.position = Vector3(0, 0.24, -0.05)
	scr.rotation.x = deg_to_rad(-15)
	m.add_child(scr)
	scr.add_child(MinigameUtil.box(Vector3(0.34, 0.18, 0.03), Color(0.1, 0.1, 0.1)))
	scr.add_child(MinigameUtil.box(Vector3(0.32, 0.16, 0.002), Color(0.02, 0.09, 0.03), Vector3(0, 0, 0.016), true))
	var da := Node3D.new()
	da.name = "DisplayAnchor"
	da.position = Vector3(0, 0, 0.019)
	scr.add_child(da)
	var stem := MinigameUtil.box(Vector3(0.03, 0.14, 0.03), Color(0.1, 0.1, 0.1), Vector3(0, 0.15, -0.08))
	m.add_child(stem)
	# customer-facing pole display
	var cd := Node3D.new()
	cd.name = "CustomerDisplayAnchor"
	cd.position = Vector3(0, 0.24, -0.075)
	m.add_child(cd)
	return m

# ---------------------------------------------------------------- flow
func _on_start() -> void:
	_clear_items()
	total = 0
	scanned = 0
	if random_seed != 0:
		_rng.seed = random_seed
	else:
		_rng.randomize()
	_spawn_customer()
	_spawn_items()
	_set_display("XIN CHÀO", MinigameUtil.format_vnd(0))
	if _drawer:
		_drawer.position.z = 0.01

func _on_reset() -> void:
	_clear_items()
	total = 0
	scanned = 0
	if _customer:
		_customer.queue_free()
		_customer = null
	_set_display("ÁNH DƯƠNG 24H", "XIN CHÀO")
	if _drawer:
		_drawer.position.z = 0.01

func _catalogue() -> Array[MinigameProduct]:
	return products if not products.is_empty() else MinigameProduct.defaults()

func _spawn_items() -> void:
	var cat := _catalogue()
	var spots := get_anchors("item_spot")
	for i in item_count:
		var prod: MinigameProduct = cat[_rng.randi() % cat.size()]
		var it := MinigameItem.new()
		it.name = "Item%d" % i
		it.pickup_prompt = "Cầm " + prod.display_name.to_lower()
		it.data = {"product": prod}
		var axis := prod.build_visual(it)
		it.data["axis"] = axis
		MinigameUtil.add_box_collider(it, prod.size.max(Vector3(0.07, 0.07, 0.07)) * 1.15)
		_items_root.add_child(it)
		var base := global_transform * Vector3(-0.5 + 0.12 * i, 0.96, 0.0)
		var spot_basis := global_basis
		if not spots.is_empty():
			var s: Node3D = spots[i % spots.size()]
			base = s.global_position + s.global_basis.z * (-0.13 * floorf(float(i) / spots.size()))
			spot_basis = s.global_basis
		# random yaw so the barcode rarely faces the player initially
		var yaw := float(_rng.randi() % 4) * PI * 0.5 + _rng.randf_range(-0.3, 0.3)
		var b := spot_basis * Basis(Vector3.UP, yaw)
		var final := Transform3D(b, base + Vector3(0, prod.size.y * 0.5, 0))
		it.global_transform = Transform3D(b, final.origin + Vector3(0, 0.25, -0.15))
		it.remember_home()
		it.home_transform = final
		it.move_to(final, 0.25 + 0.15 * i)
		items.append(it)

func _clear_items() -> void:
	for it in items:
		if is_instance_valid(it):
			if it.is_held():
				it.release_from_player()
			it.queue_free()
	items.clear()

func _spawn_customer() -> void:
	if not show_customer or _customer:
		return
	var spot := get_anchor("Customer")
	if spot == null:
		return
	_customer = MinigameUtil.instance_model(customer_scene)
	if _customer == null:
		_customer = Node3D.new()
		var body := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.22
		cap.height = 1.45
		cap.radial_segments = 8
		cap.rings = 2
		body.mesh = cap
		body.material_override = MinigameUtil.make_mat(Color(0.25, 0.28, 0.33))
		body.position.y = 0.72
		_customer.add_child(body)
		var head := MinigameUtil.box(Vector3(0.2, 0.24, 0.2), Color(0.72, 0.6, 0.5), Vector3(0, 1.58, 0))
		_customer.add_child(head)
	_customer.name = "Customer"
	add_child(_customer)
	_customer.global_transform = spot.global_transform

func _customer_leave() -> void:
	if _customer == null:
		customer_done.emit()
		return
	var exit := get_anchor("CustomerExit")
	if _customer.has_method("leave"):
		_customer.leave()
	if exit:
		if _customer.has_method("walk_to"):
			_customer.walk_to(exit.global_position)
		else:
			var t := create_tween()
			t.tween_interval(0.6)
			t.tween_property(_customer, "global_position", exit.global_position, customer_leave_time)
			await t.finished
	else:
		await get_tree().create_timer(customer_leave_time).timeout
	if _customer and not _customer.has_method("walk_to"):
		_customer.visible = false
	customer_done.emit()

# ---------------------------------------------------------------- scanning
func _tick(_delta: float) -> void:
	var held := held_item()
	if _beam:
		var bright: bool = held is MinigameItem and held in items and not held.consumed
		(_beam.material_override as StandardMaterial3D).albedo_color.a = 0.45 if bright else 0.18
	for it in items:
		if not it.consumed and it.is_held() and can_scan(it):
			scan_item(it)
			break

## Geometric test: item within range of the scan point, inside the beam cone, barcode face
## pointing at the scanner within scan_angle_deg.
func can_scan(it: MinigameItem) -> bool:
	if _scan_point == null or it.consumed:
		return false
	var origin := _scan_point.global_position
	var d := it.global_position - origin
	var dist := d.length()
	if dist > scan_range:
		return false
	if dist > 0.03:
		var beam_dir := -_scan_point.global_basis.z.normalized()
		if beam_dir.angle_to(d) > deg_to_rad(beam_cone_deg):
			return false
	if dist <= 0.001:
		return true
	return barcode_normal(it).dot(-d.normalized()) >= cos(deg_to_rad(scan_angle_deg))

func barcode_normal(it: MinigameItem) -> Vector3:
	var axis: Vector3 = it.data.get("axis", Vector3(0, 0, 1))
	return (it.global_basis * axis).normalized()

## Registers the item (no geometry check). Used by can_scan hits, autoplay and tests.
func scan_item(it: MinigameItem) -> void:
	if it.consumed or not it in items:
		return
	var prod: MinigameProduct = it.data.product
	it.release_from_player(true)
	it.enabled = false
	scanned += 1
	total += prod.price
	sfx("scanner_beep", _scan_point if _scan_point else self)
	_set_display(_short(prod.display_name) + "\n" + MinigameUtil.format_vnd(prod.price), "TỔNG " + MinigameUtil.format_vnd(total))
	var bag := get_anchor("BagSpot")
	if bag:
		var idx := scanned - 1
		var pos := bag.global_position + bag.global_basis.x * (0.11 * (idx % 4)) + bag.global_basis.z * (-0.12 * floorf(idx / 4.0))
		it.move_to(Transform3D(bag.global_basis, pos + Vector3(0, prod.size.y * 0.5, 0)), 0.35)
	item_scanned.emit(prod.display_name, prod.price, total)
	if all_scanned():
		toast("Bấm máy tính tiền")

func all_scanned() -> bool:
	return scanned >= items.size() and not items.is_empty()

func _register_prompt() -> String:
	return "Tính tiền" if _active and all_scanned() else ""

func press_register(_player: Node3D = null) -> void:
	if not _active or not all_scanned():
		return
	sfx("register_open", _register_btn)
	if _drawer:
		create_tween().tween_property(_drawer, "position:z", 0.22, 0.25).set_trans(Tween.TRANS_BACK)
	_set_display("TỔNG CỘNG", MinigameUtil.format_vnd(total))
	_display_front.text = MinigameUtil.format_vnd(total)
	complete()

func _on_complete() -> void:
	_customer_leave()

func _set_display(line1: String, line2: String) -> void:
	if _display:
		_display.text = line1 + "\n" + line2
	if _display_front:
		_display_front.text = line2

func _short(s: String) -> String:
	return s.to_upper().left(10)

# ---------------------------------------------------------------- debug / tests
func _autoplay() -> void:
	for it in items:
		await get_tree().create_timer(0.12).timeout
		if not _active:
			return
		scan_item(it)
	press_register()

## For screenshots: scan one item and put the next in the player's hands, barcode half-turned.
func debug_shot_prep(player: Node3D) -> void:
	if items.size() < 2:
		return
	scan_item(items[0])
	items[1].pick_up(player)
