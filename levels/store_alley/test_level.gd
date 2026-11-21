extends SceneTree
## godot --headless --path . -s res://levels/store_alley/test_level.gd

var failures := 0
var level: Node3D
var player: CharacterBody3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var resource := load("res://levels/store_alley/store_alley.tscn") as PackedScene
	if resource == null:
		quit(1)
		return
	level = resource.instantiate()
	root.add_child(level)
	var paths := [
		"Env/Store", "Env/Alley", "NavigationRegion3D",
		"Presets/night_store", "Presets/dusk_store", "Presets/alley_predawn", "Presets/ch4_night",
		"Doors/ShopDoor", "Doors/StoreroomDoor", "Doors/BackDoor",
		"Interactables/Checkout", "Interactables/ShelfStock", "Interactables/Mop",
		"Interactables/RulesNote", "Interactables/Drawer", "Interactables/Drawer/NameTagStore", "Interactables/AlleyAltar",
		"NPCs/Hanh", "NPCs/Customer1", "NPCs/Customer2", "NPCs/OldLady", "NPCs/Linh",
		"Entities/Gazer", "Entities/GazerHunt",
		"Triggers/trig_alley_enter", "Triggers/trig_alley_end", "Triggers/trig_store_front_ch4", "Triggers/HideCounter",
		"Markers/cam_store_wide", "Markers/cam_outside_glass", "Markers/cam_alley", "Markers/cam_counter",
		"Markers/npc_counter", "Markers/npc_door", "Markers/npc_exit",
	]
	for i in range(1, 7):
		paths.append("Markers/gazer_%d" % i)
	for i in range(1, 6):
		paths.append("Markers/hunt_%d" % i)
	for path in paths:
		_check(level.has_node(path), "missing contract node " + path)
	for id in ["default", "door", "alley_start", "front_street", "alley_mid"]:
		var marker: Marker3D = level.get_spawn(id)
		_check(marker != null, "spawn exists: " + id)
		if marker == null:
			continue
		player = level.spawn_player(id)
		_check(player != null and player.global_position.is_equal_approx(marker.global_position), "spawn: " + id)
		for i in 6:
			await physics_frame
		_check(player.is_on_floor(), "supported spawn: " + id)
		_check(player.global_position.distance_to(marker.global_position) < 0.10, "unobstructed spawn: " + id)
	if failures:
		_finish()
		return
	for preset in level.get_node("Presets").get_children():
		level.apply_preset(preset.name)
		var worlds := 0
		var lights := 0
		for n in level.find_children("*", "WorldEnvironment", true, false):
			worlds += 1 if n.environment else 0
		for n in level.find_children("*", "Light3D", true, false):
			lights += 1 if n.is_visible_in_tree() else 0
		_check(worlds == 1 and lights > 0 and lights <= 12, "%s: one environment, 1–12 enabled lights" % preset.name)
	level.apply_preset("night_store")
	_test_door_ids()
	await _test_traversal()
	await _test_tasks()
	var nav: NavigationRegion3D = level.get_node("NavigationRegion3D")
	while nav.is_baking():
		await process_frame
	_check(nav.navigation_mesh.get_polygon_count() > 0, "baked walkable navigation")
	await physics_frame
	var map := nav.get_navigation_map()
	var from: Vector3 = level.get_spawn("default").global_position
	var to: Vector3 = level.get_marker("alley_exit").global_position
	var route := NavigationServer3D.map_get_path(map, from, to, true)
	_check(route.size() > 1 and route[-1].distance_to(to) < 0.8, "navigation joins the store and alley exit: %s" % str(route))
	level.queue_free()
	await process_frame
	await process_frame
	root.get_node("AudioDirector").stop_all_ambience(0.0)
	await create_timer(2.2).timeout
	load("res://render/psx_apply.gd").clear_cache()
	_finish.call_deferred()

func _test_door_ids() -> void:
	var ids := {"ShopDoor": "shop_front", "StoreroomDoor": "storeroom", "BackDoor": "back_door"}
	for key in ids:
		var door = level.get_node("Doors/" + key)
		_check(door.door_id == ids[key] and not door.is_open and not door.locked, "initial door state: " + key)

func _test_traversal() -> void:
	var shop = level.get_node("Doors/ShopDoor")
	var stock = level.get_node("Doors/StoreroomDoor")
	var back = level.get_node("Doors/BackDoor")
	var entrance := Vector3(3.52, 0, 1.0)
	var interior := Vector3(3.52, 0, -1.28)
	_check(not _clear(entrance, interior), "closed shop doors block the capsule")
	shop.set_open_instant(true, 95.0)
	stock.set_open_instant(true, 95.0)
	back.set_open_instant(true, -90.0)
	await physics_frame
	_walk("sidewalk through the glass door to the till", [
		Vector3(3.55, 0, 2.05), entrance, interior, Vector3(2.24, 0, -1.28),
		Vector3(2.24, 0, -2.95), Vector3(3.8, 0, -2.95)])
	for x in [-4.04, -2.4, -0.8, 0.8, 2.24]:
		_walk("gondola aisle x=%.2f" % x, [Vector3(x, 0, -1.4), Vector3(x, 0, -6.0)])
	_walk("till to storeroom and alley entrance", [
		Vector3(3.8, 0, -2.95), Vector3(2.24, 0, -2.95), Vector3(2.24, 0, -4.4),
		Vector3(3.99, 0, -4.4), Vector3(3.99, 0, -8.62), Vector3(3.87, 0, -9.45),
		Vector3(3.87, 0, -11.44), Vector3(4.4, 0, -11.55), Vector3(4.4, 0, -12.8)])
	_walk("alley entrance, both turns, shrine exit", [
		Vector3(4.4, 0, -12.8), Vector3(4.04, 0, -14.0), Vector3(4.04, 0, -26.9),
		Vector3(4.33, 0, -28.0), Vector3(-5.5, 0, -28.0), Vector3(-6.4, 0, -27.80),
		Vector3(-7.8, 0, -27.79), Vector3(-8.30, 0, -27.93),
		Vector3(-8.62, 0, -28.19), Vector3(-9.95, 0, -28.19), Vector3(-14.0, 0, -28.05), Vector3(-14.0, 0, -41.95),
		Vector3(-13.82, 0, -43.05), Vector3(-13.82, 0, -46.0), Vector3(-14.0, 0, -52.5)])
	var space := player.get_world_3d().direct_space_state
	var glass: MeshInstance3D = level.get_node("Env/Store/store_front_glass")
	var glass_tint: Color = glass.get_surface_override_material(0).get_shader_parameter("tint")
	_check(glass_tint.a < 0.3, "front glass visibly transparent")
	_check(not _clear(Vector3(0.8, 0, -1), Vector3(0.8, 0, 1)), "storefront glass blocks movement")
	_check(EntityObservation.ray_clear(space, Vector3(0.8, 1.6, -1), Vector3(0.8, 1.6, 1)), "Gazer sight goes through storefront glass")
	_check(not EntityObservation.ray_clear(space, Vector3(-4.5, 1.6, -1), Vector3(-5.7, 1.6, -1)), "opaque walls still block Gazer sight")
	shop.set_open_instant(true, -95.0)
	stock.set_open_instant(true, -95.0)
	back.set_open_instant(true, 90.0)
	await physics_frame
	_walk("shop door opened from the other side", [interior, entrance])
	_walk("storage door opened from the other side", [
		Vector3(4.0, 0, -8.75), Vector3(4.0, 0, -7.2)])
	_walk("back door opened from the other side", [
		Vector3(4.4, 0, -12.8), Vector3(4.4, 0, -11.57), Vector3(3.87, 0, -11.44)])
	for id in ["trig_alley_enter", "trig_alley_end", "trig_store_front_ch4"]:
		var trigger = level.get_node("Triggers/" + id)
		trigger.reset()
		player.teleport(trigger.global_transform)
		await physics_frame
		await physics_frame
		_check(trigger.fired, "%s fires on player passage" % id)

func _walk(label: String, points: Array) -> void:
	for i in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		var result := KinematicCollision3D.new()
		_check(_clear(a, b, result), "%s blocked: %s → %s at %s by %s" % [
			label, a, b, a + result.get_travel(), result.get_collider() if result.get_collision_count() else ""])
		var steps := ceili(a.distance_to(b) / 0.38)
		for step in range(steps + 1):
			var p := a.lerp(b, float(step) / steps)
			var hit := _ray(p + Vector3.UP * 0.12, p - Vector3.UP * 0.11, 1)
			if hit == null:
				_check(false, "%s lacks floor at %s" % [label, p])
				break

func _clear(a: Vector3, b: Vector3, result: KinematicCollision3D = null) -> bool:
	return not player.test_move(Transform3D(Basis.IDENTITY, a + Vector3.UP * 0.045), b - a, result, 0.001, true)

func _ray(from: Vector3, to: Vector3, mask := 37) -> Object:
	var ray := PhysicsRayQueryParameters3D.create(from, to, mask)
	return player.get_world_3d().direct_space_state.intersect_ray(ray).get("collider")

func _test_tasks() -> void:
	var checkout = level.get_node("Interactables/Checkout")
	var shelf = level.get_node("Interactables/ShelfStock")
	var mop = level.get_node("Interactables/Mop")
	var rules = level.get_node("Interactables/RulesNote")
	var drawer = level.get_node("Interactables/Drawer")
	var altar = level.get_node("Interactables/AlleyAltar")
	var state := root.get_node("GameState")
	_check(_ray(Vector3(3.8, 1.62, -2.95), rules.global_position) == rules, "rules paper is aimable from behind counter")
	_check(_ray(Vector3(3.7, 1.62, -9.52), drawer.global_position) == drawer, "drawer is aimable from storeroom")
	var altar_origin: Vector3 = altar.global_position
	var altar_hit := _ray(Vector3(altar_origin.x, 1.62, -28.16), altar_origin + Vector3(0, 0.3, -0.055))
	_check(altar_hit == altar, "altar is aimable from lane; at %s but hit %s" % [altar_origin, altar_hit])
	rules.interact(player)
	_check(state.flags.get("read_rules") == true, "rules interaction sets chapter flag")
	_close_paper()
	await process_frame
	drawer.interact(player)
	_check(state.flags.get("found_name_tag_store") == true and state.flags.get("read_name_tag_store") == true, "drawer reveals the employee card")
	_close_paper()
	_check(checkout.minigame_id == "checkout" and shelf.minigame_id == "shelf_stock" and mop.minigame_id == "mop", "minigame IDs")
	_check(not checkout.build_placeholder and not shelf.build_placeholder and not mop.build_placeholder, "minigames use level furniture")
	level.spawn_player("default")
	checkout.item_count = 7
	checkout.start()
	shelf.start()
	mop.start()
	await create_timer(1.3).timeout
	for item in checkout.items:
		var eye := Vector3(item.global_position.x, 1.62, -2.94)
		_check(_ray(eye, item.global_position) == item, "checkout pickup %s is aimable" % item.name)
	var item = checkout.items[0]
	var scan: Node3D = checkout.get_anchor("ScanPoint")
	var scan_dir := -scan.global_basis.z
	item.global_position = scan.global_position + scan_dir * 0.30
	var barcode: Vector3 = item.data.axis
	item.global_basis = Basis(Quaternion(barcode, -scan_dir))
	_check(checkout.can_scan(item), "scanner beam accepts real prop barcode angle")
	player.teleport(Transform3D(Basis(Vector3.UP, PI), Vector3(4.42, 0, -2.95)))
	player.set("_pitch", deg_to_rad(-10.0))
	item.interact(player)
	await create_timer(0.30).timeout
	var held_scan_dir: Vector3 = (scan.global_position - item.global_position).normalized()
	item.global_basis = Basis(Quaternion(barcode, held_scan_dir))
	await process_frame
	await process_frame
	_check(item.consumed, "actual player hold pose can scan the barcode")
	for product in checkout.items:
		checkout.scan_item(product)
	var register = checkout.get_anchor("Register").get_node("RegisterButton")
	_check(_ray(Vector3(3.6, 1.62, -2.95), register.global_position + Vector3.UP * 0.15) == register, "checkout register is aimable")
	register.interact(player)
	_check(checkout.is_completed(), "checkout completes on register interaction")
	var box_y: float = shelf.box.global_position.y
	_check(_ray(Vector3(3.88, 1.62, -9.52), shelf.box.global_position + Vector3.UP * 0.14) == shelf.box, "supply carton is aimable (y=%.2f)" % box_y)
	shelf.box.interact(player)
	shelf.box.interact(player)
	_check(shelf.box_open and player.get_held_item() == shelf.box, "open and carry real supply carton")
	_check(shelf.slots.size() == 8, "eight slots on gondola 2")
	for slot in shelf.slots:
		var aisle: Vector3 = slot.global_position + slot.global_basis.z * 0.7
		var aim: Vector3 = slot.global_position + slot.global_basis.z * 0.16 + Vector3.UP * 0.10
		aisle.y = 1.62
		var slot_hit := _ray(aisle, aim)
		_check(slot_hit == slot, "%s is aimable from aisle %s to %s; hit %s" % [slot.name, aisle, aim, slot_hit])
	while shelf.remaining() > 0:
		var slot: int = shelf.index_of_slot_for(shelf.next_product().type_id)
		shelf.slots[slot].interact(player)
		if not shelf.slots[slot].data.filled:
			_check(false, "held carton cannot place product")
			break
	_check(shelf.is_completed(), "shelf stocking completes")
	_check(_ray(Vector3(3.45, 1.62, -10.9), mop.mop.global_position + Vector3.UP * 0.8) == mop.mop, "mop is aimable in storeroom")
	mop.mop.interact(player)
	_check(player.get_held_item() == mop.mop, "real mop is holdable")
	_check(mop.stains.size() == 4, "four aisle stains")
	for stain in mop.stains:
		mop.scrub_at(stain.marker.global_position, 3.0)
	mop.advance(mop.haunted_delay + 0.1)
	mop.scrub_at(mop.stains[mop.haunted_stain_index].marker.global_position, 3.0)
	mop.advance(0.1)
	_check(mop.is_completed(), "mopping completes after the haunted stain is cleaned again")

func _close_paper() -> void:
	var overlay := root.get_node_or_null("PaperOverlay")
	if overlay:
		overlay.call("_close")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("store_alley: " + message)

func _finish() -> void:
	print("store_alley smoke: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)
