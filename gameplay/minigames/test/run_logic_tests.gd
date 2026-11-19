extends SceneTree
## Headless logic tests for the minigames:
##   godot --headless --path . -s res://gameplay/minigames/test/run_logic_tests.gd
## Drives every minigame programmatically (scans, placements, mopping, timers with fast time) and
## asserts completion. Prints PASS/FAIL per test; exit code = number of failed tests (0 = all good).
## NOTE: autoload singletons are fetched via root (identifiers are not known when -s compiles this).

const PLAYER := "res://gameplay/minigames/test/test_player.tscn"

var gs: Node
var bus: Node
var _fails := 0
var _passes := 0
var _cur := ""
var _cur_ok := true
var _cur_end := false
var _toasts: Array[String] = []
var _completed_ids: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	bus = root.get_node("EventBus")
	bus.toast.connect(func(t): _toasts.append(t))
	bus.minigame_completed.connect(func(id): _completed_ids.append(id))
	var tests := [
		"test_util", "test_barcode_axis_meta", "test_barcode_real_glb", "test_checkout", "test_shelf_stock", "test_mop",
		"test_noodles", "test_noodles_order", "test_room_routine", "test_autoplay_all",
	]
	for t in tests:
		_cur = t
		_cur_ok = true
		_cur_end = false
		gs.reset()
		gs.debug_autoplay = false
		_toasts.clear()
		_completed_ids.clear()
		await call(t)
		if not _cur_end:
			_cur_ok = false
			print("   test aborted before its end (script error?) [%s]" % t)
		_cleanup()
		await process_frame
		if _cur_ok:
			_passes += 1
			print("PASS  ", t)
		else:
			_fails += 1
			print("FAIL  ", t)
	print("---- minigame logic tests: %d passed, %d failed" % [_passes, _fails])
	quit(_fails)

# ------------------------------------------------------------------ helpers
var _container: Node3D

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_cur_ok = false
		print("   assert failed [%s]: %s" % [_cur, msg])

func _setup_scene(scene_path: String) -> Array:
	_container = Node3D.new()
	_container.name = "TestContainer"
	root.add_child(_container)
	var mg: Node = load(scene_path).instantiate()
	var pl: Node3D = load(PLAYER).instantiate()
	pl.show_hud = false
	return [mg, pl]

func _add(mg: Node, pl: Node3D) -> void:
	_container.add_child(mg)
	_container.add_child(pl)
	gs.player = pl

func _cleanup() -> void:
	if _container:
		_container.queue_free()
		_container = null
	gs.player = null
	gs.input_locks.clear()

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _wait_until(cond: Callable, timeout := 5.0) -> bool:
	var t := 0.0
	while not cond.call() and t < timeout:
		await process_frame
		t += 1.0 / 60.0
	return cond.call()

# ------------------------------------------------------------------ tests
func test_util() -> void:
	var U = load("res://gameplay/minigames/minigame_util.gd")
	_check(U.format_vnd(15000) == "15.000đ", "15000 -> " + U.format_vnd(15000))
	_check(U.format_vnd(5000) == "5.000đ", "5000")
	_check(U.format_vnd(147000) == "147.000đ", "147000")
	_check(U.format_vnd(1000000) == "1.000.000đ", "1e6")
	_check(U.format_vnd(0) == "0đ", "0")
	_check(U.axis_vector("+X") == Vector3(1, 0, 0), "+X")
	_check(U.axis_vector("-y") == Vector3(0, -1, 0), "-y")
	_check(U.axis_vector("") == Vector3(0, 0, 1), "default +Z")
	_cur_end = true

func test_barcode_axis_meta() -> void:
	# A fake "glb" model whose child mesh carries barcode_axis metadata and is rotated 90° (Y).
	var model := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Can"
	mesh.mesh = BoxMesh.new()
	mesh.rotation.y = PI * 0.5
	mesh.set_meta("barcode_axis", "+X")
	model.add_child(mesh)
	mesh.owner = model
	var ps := PackedScene.new()
	ps.pack(model)
	model.free()
	var P = load("res://gameplay/minigames/minigame_product.gd")
	var prod = P.new()
	prod.model = ps
	_container = Node3D.new()
	root.add_child(_container)
	var holder := Node3D.new()
	_container.add_child(holder)
	var axis: Vector3 = prod.build_visual(holder)
	_check(axis.is_equal_approx(Vector3(0, 0, -1)), "meta axis rotated -> %s" % axis)
	prod.barcode_axis = "-Y"
	var h2 := Node3D.new()
	_container.add_child(h2)
	_check(prod.build_visual(h2).is_equal_approx(Vector3(0, -1, 0)), "explicit barcode_axis wins")
	var plain = P.new()
	var h3 := Node3D.new()
	_container.add_child(h3)
	_check(plain.build_visual(h3).is_equal_approx(Vector3(0, 0, 1)), "default +Z")
	_cur_end = true

func test_barcode_real_glb() -> void:
	# Real Track C2 prop: barcode is on the back face = Godot -Z, stored in glTF "extras".
	var ps: PackedScene = load("res://assets/models/props/can_tra_xanh.glb")
	_check(ps != null, "can_tra_xanh.glb loads")
	if ps:
		var P = load("res://gameplay/minigames/minigame_product.gd")
		var prod = P.new()
		prod.model = ps
		_container = Node3D.new()
		root.add_child(_container)
		var holder := Node3D.new()
		_container.add_child(holder)
		var axis: Vector3 = prod.build_visual(holder)
		_check(axis.is_equal_approx(Vector3(0, 0, -1)), "real glb barcode axis from extras -> %s" % axis)
	_cur_end = true

func test_checkout() -> void:
	var a := _setup_scene("res://gameplay/minigames/checkout/checkout.tscn")
	var mg = a[0]
	var pl: Node3D = a[1]
	mg.item_count = 3
	mg.random_seed = 7
	mg.objective_id = "obj_checkout"
	mg.customer_leave_time = 0.05
	_add(mg, pl)
	gs.add_objective("obj_checkout", "Tính tiền")
	var cust_done := [false]
	mg.customer_done.connect(func(): cust_done[0] = true)
	await process_frame
	mg.start()
	_check(mg.is_active(), "active after start")
	_check(mg.items.size() == 3, "3 items spawned")
	_check(mg._register_btn.get_prompt() == "", "register hidden before scanning")
	var sp: Node3D = mg._scan_point
	var beam: Vector3 = -sp.global_basis.z.normalized()
	var expected_total := 0
	for i in mg.items.size():
		var it = mg.items[i]
		_check(it.get_prompt() != "", "item has pickup prompt")
		it.interact(pl)
		_check(it.is_held(), "item %d held" % i)
		_check(pl.get_held_item() == it, "player holds item")
		var axis: Vector3 = it.data.axis
		# 1) out of range
		it.global_position = sp.global_position + beam * 1.0
		it.global_basis = Basis(Quaternion(axis, -beam))
		mg._tick(0.016)
		_check(it.consumed == false, "no scan out of range")
		# 2) in range, barcode facing away
		it.global_position = sp.global_position + beam * 0.3
		it.global_basis = Basis(Quaternion(axis, beam))
		mg._tick(0.016)
		_check(it.consumed == false, "no scan when barcode faces away")
		# 3) in range, 45° off
		var off45 := (-beam).rotated(sp.global_basis.x.normalized(), deg_to_rad(45))
		it.global_basis = Basis(Quaternion(axis, off45))
		mg._tick(0.016)
		_check(it.consumed == false, "no scan at 45°")
		# 4) 25° off -> scans
		var off25 := (-beam).rotated(sp.global_basis.x.normalized(), deg_to_rad(25))
		it.global_basis = Basis(Quaternion(axis, off25))
		mg._tick(0.016)
		_check(it.consumed, "scanned at 25° (item %d)" % i)
		_check(not it.is_held(), "released after scan")
		expected_total += it.data.product.price
		_check(mg.total == expected_total, "running total %d" % mg.total)
	_check(mg.all_scanned(), "all scanned")
	_check(mg._display.text.contains(load("res://gameplay/minigames/minigame_util.gd").format_vnd(expected_total)), "display shows total: " + mg._display.text)
	_check(mg._register_btn.get_prompt() == "Tính tiền", "register prompt")
	mg._register_btn.interact(pl)
	_check(mg.is_completed(), "completed after register")
	_check(gs.is_objective_done("obj_checkout"), "objective done")
	_check("checkout" in _completed_ids, "EventBus.minigame_completed(checkout)")
	await _wait_until(func(): return cust_done[0], 4.0)
	_check(cust_done[0], "customer_done emitted")
	_cur_end = true

func test_shelf_stock() -> void:
	var a := _setup_scene("res://gameplay/minigames/shelf_stock/shelf_stock.tscn")
	var mg = a[0]
	var pl: Node3D = a[1]
	mg.product_count = 6
	mg.type_count = 2
	mg.random_seed = 3
	_add(mg, pl)
	await process_frame
	mg.start()
	_check(mg.slots.size() == 6, "6 slots used")
	_check(mg.remaining() == 6, "6 products in box")
	var types := {}
	for s in mg.slots:
		types[s.data.type] = true
	_check(types.size() == 2, "2 product types")
	_check(mg.slots[0].get_prompt() == "", "slot prompt hidden without box")
	_check(mg.box.get_prompt() == "Mở thùng", "box prompt open: " + mg.box.get_prompt())
	mg.box.interact(pl)
	_check(mg.box_open, "box opened")
	_check(not mg.box.is_held(), "opening does not pick up")
	mg.box.interact(pl)
	_check(mg.box.is_held(), "box carried")
	# wrong slot
	var nxt = mg.next_product()
	var wrong := -1
	for i in mg.slots.size():
		if mg.slots[i].data.type != nxt.type_id:
			wrong = i
			break
	_check(wrong >= 0, "found a wrong slot")
	_check(mg.slots[wrong].get_prompt() != "", "slot prompt while carrying")
	mg.slots[wrong].interact(pl)
	_check(mg.remaining() == 6, "wrong slot rejected")
	_check("Sai chỗ rồi" in _toasts, "wrong toast")
	# correct placements
	var guard := 0
	while mg.next_product() and guard < 20:
		guard += 1
		var i: int = mg.index_of_slot_for(mg.next_product().type_id)
		mg.slots[i].interact(pl)
	_check(mg.remaining() == 0, "box emptied")
	_check(mg.placed == 6, "6 placed")
	_check(mg.is_completed(), "completed")
	_check(not mg.box.is_held(), "box released at the end")
	_check("shelf_stock" in _completed_ids, "EventBus.minigame_completed(shelf_stock)")
	_cur_end = true

func test_mop() -> void:
	var a := _setup_scene("res://gameplay/minigames/mop/mop.tscn")
	var mg = a[0]
	var pl: Node3D = a[1]
	mg.haunted_stain_index = 1
	mg.haunted_delay = 1.0
	_add(mg, pl)
	await process_frame
	mg.start()
	var haunted := [0]
	mg.haunted_event.connect(func(): haunted[0] += 1)
	_check(mg.stains.size() == 4, "4 stains")
	mg.mop.interact(pl)
	_check(mg.mop.is_held(), "mop held")
	pl.rotation = Vector3.ZERO     # facing -Z: head = feet + (0,0,-reach)
	var start_dirt: float = mg.dirt_left()
	for idx in mg.stains.size():
		await _scrub_stain(mg, pl, idx)
	_check(mg.dirt_left() < start_dirt, "dirt reduced")
	_check(not mg.is_completed(), "not complete while haunted stain pending")
	mg.advance(1.2)
	_check(haunted[0] == 1, "haunted_event fired once")
	_check(mg.stains[1].dirt == 1.0, "haunted stain reappeared")
	await _scrub_stain(mg, pl, 1)
	mg.advance(2.0)
	_check(haunted[0] == 1, "haunted only once")
	_check(mg.is_completed(), "completed after cleaning all")
	_check(not mg.mop.is_held(), "mop released")
	_cur_end = true

func _scrub_stain(mg, pl: Node3D, idx: int) -> void:
	var c: Vector3 = (mg.stains[idx].node as Node3D).global_position
	var guard := 0
	var k := 0
	while mg.stains[idx].dirt > 0.0 and guard < 600:
		guard += 1
		k += 1
		var dx := sin(k * 0.6) * 0.2   # sweep left/right over the stain
		pl.global_position = Vector3(c.x + dx, 0, c.z + mg.mop_reach)
		mg._tick(1.0 / 60.0)
	_check(mg.stains[idx].dirt == 0.0, "stain %d cleaned (%d ticks)" % [idx, guard])

func test_noodles() -> void:
	var a := _setup_scene("res://gameplay/minigames/noodles/noodles.tscn")
	var mg = a[0]
	var pl: Node3D = a[1]
	_add(mg, pl)
	await process_frame
	mg.start()
	var over := [false]
	mg.boiled_over.connect(func(): over[0] = true)
	var S = mg.State
	_check(mg._pack.get_prompt() == "", "no noodles before water")
	mg._knob.interact(pl)
	_check(not mg.stove_on, "stove refuses without water")
	_check("Nồi chưa có nước." in _toasts, "no water toast")
	mg._pot_btn.interact(pl)
	_check(mg.state == S.WATER, "water in")
	mg._knob.interact(pl)
	_check(mg.stove_on, "stove on")
	mg.advance(mg.heat_time - 1.0)
	_check(mg.state == S.WATER, "not boiling yet")
	mg._pack.interact(pl)
	_check(mg.state == S.WATER, "noodles refused before boil")
	mg.advance(1.5)
	_check(mg.state == S.BOILING, "boiling after heat_time")
	_check(mg._steam.emitting, "steam")
	mg._pack.interact(pl)
	_check(mg.state == S.COOKING, "cooking")
	mg.advance(mg.cook_time - 1.0)
	_check(mg.state == S.COOKING, "still cooking")
	_check(mg._timer_label.text == "00:01", "timer shows 00:01: " + mg._timer_label.text)
	mg.advance(1.5)
	_check(mg.state == S.READY, "ready")
	mg.advance(mg.overboil_time + 0.5)
	_check(over[0] and mg.did_boil_over, "boiled over when ignored")
	_check(mg._knob.get_prompt() == "Tắt bếp", "knob prompt off")
	mg._knob.interact(pl)
	_check(mg.is_completed(), "completed after turning off")
	_check(not mg.stove_on, "stove off")
	_cur_end = true

func test_noodles_order() -> void:
	# turning the stove off mid-way pauses heating; it is still completable.
	var a := _setup_scene("res://gameplay/minigames/noodles/noodles.tscn")
	var mg = a[0]
	var pl: Node3D = a[1]
	mg.heat_time = 2.0
	mg.cook_time = 3.0
	_add(mg, pl)
	await process_frame
	mg.start()
	mg.fill_water()
	mg.toggle_stove()
	mg.advance(1.0)
	mg.toggle_stove()
	mg.advance(5.0)
	_check(mg.state == mg.State.WATER, "no heating while off")
	mg.toggle_stove()
	mg.advance(1.2)
	_check(mg.state == mg.State.BOILING, "boils after resuming")
	mg.add_noodles()
	mg.advance(3.2)
	mg.toggle_stove()
	_check(mg.is_completed(), "completed")
	_check(not mg.did_boil_over, "no boil over")
	_cur_end = true

func test_room_routine() -> void:
	_container = Node3D.new()
	root.add_child(_container)
	var door: Node3D = load("res://gameplay/minigames/test/test_door.gd").new()
	door.name = "TestDoor"
	_container.add_child(door)
	var light := OmniLight3D.new()
	light.add_to_group("room_lights")
	_container.add_child(light)
	var rr: Node = load("res://gameplay/minigames/room_routine/room_routine.tscn").instantiate()
	rr.door_path = NodePath("../TestDoor")
	rr.objective_id = "obj_room"
	var pl: Node3D = load(PLAYER).instantiate()
	pl.show_hud = false
	_add(rr, pl)
	gs.add_objective("obj_room", "Đi ngủ")
	var lights_events := []
	var cb := func(g, on): lights_events.append([g, on])
	bus.lights_set.connect(cb)
	await process_frame
	rr.start()
	_check(rr.parts.size() == 3, "3 parts")
	var sw = rr.get_part("lamp_switch_off")
	var lock = rr.get_part("check_door_lock")
	var bed = rr.get_part("go_to_sleep")
	_check(sw and lock and bed, "parts by id")
	bed.fade_time = 0.05
	var bed_btn: Node = bed.get_node("BedButton")
	bed_btn.interact(pl)
	_check(not bed.is_completed(), "bed refuses before chores")
	_check(_toasts.size() > 0 and _toasts[-1].contains("Chưa tắt đèn") and _toasts[-1].contains("Chưa khóa cửa"), "bed hint: " + (_toasts[-1] if _toasts.size() else ""))
	sw.get_node("SwitchButton").interact(pl)
	_check(sw.is_completed(), "lamp switched off")
	_check(lights_events.size() == 1 and lights_events[0] == ["room_lights", false], "EventBus.lights_set(room_lights,false)")
	_check(not light.visible, "light hidden (direct toggle)")
	var checked := []
	lock.lock_checked.connect(func(was): checked.append(was))
	lock.get_node("LockButton").interact(pl)
	_check(door.locked, "door locked through duck-typed lock()")
	_check(checked == [false], "lock_checked(false)")
	_check(lock.is_completed(), "lock check complete")
	bed_btn.interact(pl)
	await _wait(0.3)
	_check(bed.is_completed(), "slept")
	_check(gs.is_input_locked(), "input locked after sleep")
	_check(rr.is_completed(), "routine completed")
	_check(gs.is_objective_done("obj_room"), "objective done")
	for id in ["lamp_switch_off", "check_door_lock", "go_to_sleep", "room_routine"]:
		_check(id in _completed_ids, "minigame_completed(%s)" % id)
	bus.lights_set.disconnect(cb)
	_cur_end = true

func test_autoplay_all() -> void:
	gs.debug_autoplay = true
	var scenes := {
		"checkout": "res://gameplay/minigames/checkout/checkout.tscn",
		"shelf_stock": "res://gameplay/minigames/shelf_stock/shelf_stock.tscn",
		"mop": "res://gameplay/minigames/mop/mop.tscn",
		"noodles": "res://gameplay/minigames/noodles/noodles.tscn",
		"room_routine": "res://gameplay/minigames/room_routine/room_routine.tscn",
	}
	_container = Node3D.new()
	root.add_child(_container)
	var pl: Node3D = load(PLAYER).instantiate()
	pl.show_hud = false
	_container.add_child(pl)
	gs.player = pl
	var mgs := []
	var x := 0.0
	for id in scenes:
		var mg: Node3D = load(scenes[id]).instantiate()
		mg.position.x = x
		x += 10.0
		if id == "mop":
			mg.haunted_stain_index = 0
		_container.add_child(mg)
		if id == "room_routine":
			mg.get_node("Bed").fade_time = 0.05
		mgs.append(mg)
	await process_frame
	for mg in mgs:
		mg.start()
	var ok := await _wait_until(func():
		for mg in mgs:
			if not mg.is_completed():
				return false
		return true, 8.0)
	for mg in mgs:
		_check(mg.is_completed(), "autoplay completed " + mg.minigame_id)
	_check(ok, "all autoplay done in time")
	gs.debug_autoplay = false
	_cur_end = true
