extends SceneTree
## godot --headless --path . -s res://levels/dorm_shrine/test_level.gd

const LEVEL := "res://levels/dorm_shrine/dorm_shrine.tscn"
const PATHS := {
	"Spawns": ["default", "room", "corridor_stairs", "ground_floor", "shrine_lane", "shrine"],
	"Presets": ["night", "day", "ch4_night", "dawn"],
	"Doors": ["Door201", "Door202", "Door203", "Door204", "Door205", "RoomWCDoor", "DormGate"],
	"Interactables": ["Noodles", "RoomRoutine", "NoticeBoard", "PhotoInBag", "Breaker", "Mirror",
		"LightSwitch204", "HideDesk", "HideWardrobe", "Ritual_Incense", "Ritual_Photo", "Ritual_Oil", "Ritual_Lamp",
		"LoftLadder", "LoftLadderDown"],
	"Triggers": ["trig_lane_enter", "trig_stairs_up", "trig_corridor", "trig_room", "trig_square", "trig_shrine_close"],
	"Markers": ["cam_corridor", "cam_room", "cam_shrine_wide", "cam_streetlight_low", "cam_lane_end",
		"mimic_door_out", "mimic_corridor", "CallNamePoint", "tuan_1", "tuan_2", "tuan_3", "tuan_4", "tuan_5", "tuan_final"],
	"Entities": ["MimicDoor", "MimicCorridor", "GazerTuan"],
	"NPCs": ["Hung"],
}

var failures := 0


func _initialize() -> void:
	_run.call_deferred()
	create_timer(45.0).timeout.connect(func():
		printerr("FAIL: dorm_shrine smoke timed out")
		quit(1))


func _run() -> void:
	var level := (load(LEVEL) as PackedScene).instantiate()
	if not level.has_method("spawn_player"):
		level.free()
		printerr("FAIL: dorm_shrine level script did not load")
		quit(1)
		return
	root.add_child(level)
	current_scene = level
	var state := root.get_node("GameState")
	var bus := root.get_node("EventBus")
	var audio := root.get_node("AudioDirector")
	_check(level.level_id == "dorm_shrine", "level id")
	for group in PATHS:
		for id in PATHS[group]:
			_check(level.has_node(group + "/" + id), group + "/" + id)
	for id in ["Env/Dorm", "Env/Shrine", "ShrineLamp", "TheStreetlight", "NavigationRegion3D"]:
		_check(level.has_node(id), id)
	if failures:
		quit(1)
		return

	var p := level.spawn_player("default") as CharacterBody3D
	_check(p != null, "real player scene loads")
	for id in PATHS.Spawns:
		_check(level.spawn_player(id) == p, id + " reuses player")
		await _frames(5)
		var spawn := level.get_node("Spawns/" + id) as Marker3D
		_check(p.global_position.distance_to(spawn.global_position) < 0.18, id + " settles on the floor")
		_check(p.is_on_floor(), id + " has floor")

	for id in PATHS.Presets:
		level.apply_preset(id)
		var active := level.get_node("Presets/" + id)
		var world_count := 0
		for world in level.find_children("*", "WorldEnvironment", true, false):
			if world.environment != null:
				world_count += 1
				_check(not world.environment.fog_enabled, id + " uses PSX fog only")
		_check(active.is_active() and world_count == 1, id + " activates exactly one environment")
	_check(not level.get_node("ShrineLamp").visible, "oil lamp begins off")
	_check(not level.get_node("NPCs/Hung").visible, "ending NPC starts hidden")
	for id in PATHS.Entities:
		var entity := level.get_node("Entities/" + id)
		_check(not entity.is_active() and not entity.visible and not entity.body.is_placeholder, id + " starts inactive with real model")
	var gazer := level.get_node("Entities/GazerTuan")
	_check(gazer.mode == 1 and gazer.marker_count() == 6, "Tuấn hunt follows six markers")
	_check(gazer.get_marker_position(5).is_equal_approx(level.get_node("Markers/tuan_final").global_position), "Tuấn ends below the streetlight")
	var nav := level.get_node("NavigationRegion3D") as NavigationRegion3D
	_check(nav.navigation_mesh.get_polygon_count() > 0, "navigation mesh bakes")
	level.apply_preset("night")

	var gate := level.get_node("Doors/DormGate")
	var room_door := level.get_node("Doors/Door204")
	var wc := level.get_node("Doors/RoomWCDoor")
	for id in ["Door201", "Door202", "Door203", "Door205"]:
		_check(level.get_node("Doors/" + id).locked, id + " locked")
	gate.set_open_instant(true, 90.0)
	room_door.set_open_instant(true)
	wc.set_open_instant(true)
	await _frames(2)
	_check(await _walk(p, Vector3(0, 0.08, -15.64), Vector3(-4.15, 0, -15.64)), "walk lane → dorm gate → hall")
	_check(await _walk(p, Vector3(-7.54, 0.08, -14.65), Vector3(-1.63, 3.2, -14.65), 0.85), "walk up the stair ramp")
	_check(await _walk(p, Vector3(-1.74, 3.26, -15.0), Vector3(-1.74, 3.2, -25.85)), "walk upstairs corridor")
	_check(await _walk(p, Vector3(-1.74, 3.26, -25.85), Vector3(-3.53, 3.2, -25.85)), "walk through P.204 doorway")
	_check(await _walk(p, Vector3(-5.40, 3.22, -25.67), Vector3(-7.02, 3.2, -25.67)), "walk into WC")
	_check(await _walk(p, Vector3(-0.18, 0.06, -15.62), Vector3(-0.18, 0, -35.45)), "walk alley → shrine square")
	_check(await _walk(p, Vector3(1.55, 0.06, -36.71), Vector3(1.55, 0.35, -38.94)), "walk up the shrine plinth")
	for id in ["Ritual_Incense", "Ritual_Photo", "Ritual_Oil", "Ritual_Lamp"]:
		var obj := level.get_node("Interactables/" + id) as Node3D
		var eye := Vector3(obj.position.x, 1.97, -38.72)
		_check(_aim_at(p, eye, obj), id + " is reachable by interaction ray")

	bus.lights_set.emit("dorm_lights", false)
	var breaker := level.get_node("Interactables/Breaker")
	breaker.interact(p)
	var dormant: Array[Node] = get_nodes_in_group("dorm_lights")
	_check(state.get_flag("breaker_on") and not dormant.filter(func(n): return n.has_method("is_on") and n.is_on()).is_empty(),
		"breaker restores dorm lights and sets flag")

	var noodles := level.get_node("Interactables/Noodles")
	_check(not noodles.build_placeholder and noodles.stove_model and noodles.pot_model and noodles.noodle_model, "cooking uses real prop scenes")
	noodles.start()
	for spec in [["Stove/Pot/PotButton", Vector3(-6.47, 4.82, -27.63)],
		["Knob/KnobButton", Vector3(-6.44, 4.82, -27.83)],
		["NoodlePack/NoodlePack", Vector3(-6.42, 4.82, -27.27)]]:
		_check(_aim_at(p, spec[1], noodles.get_node(spec[0])), spec[0] + " is targetable")
	noodles.fill_water()
	noodles.toggle_stove()
	noodles.advance(noodles.heat_time + 0.1)
	noodles.add_noodles()
	noodles.advance(noodles.cook_time + 0.1)
	noodles.toggle_stove()
	_check(noodles.is_completed(), "noodles complete from water to stove off")

	var room_switch := level.get_node("Interactables/LightSwitch204")
	var routine := level.get_node("Interactables/RoomRoutine")
	var lock_part: Node = routine.get_part("check_door_lock")
	var sleep: Node = routine.get_part("go_to_sleep")
	var lamp_part: Node = routine.get_part("lamp_switch_off")
	_check(routine.get_node(routine.door_path) == room_door and lock_part.get_door() == room_door, "routine uses real P.204 door")
	routine.start()
	_check(sleep.missing_hints().size() == 2, "bed waits for switch and lock")
	room_switch.interact(p)
	lock_part.check_lock()
	_check(lamp_part.is_completed() and room_door.locked and sleep.missing_hints().is_empty(), "room switch and lock complete bedtime steps")
	p.teleport(Transform3D(Basis(), Vector3(-4.2, 3.21, -26.85)))
	await _frames(3)
	level.get_node("Interactables/LoftLadder").interact(p)
	await create_timer(1.17).timeout
	if not p.is_crouching() or absf(p.global_position.y - 5.1) >= 0.15:
		print("  loft landing ", p.global_position, " crouch=", p.is_crouching())
	_check(p.is_crouching() and absf(p.global_position.y - 5.1) < 0.15, "ladder gets a crouching player onto the loft")
	var photo := level.get_node("Interactables/PhotoInBag")
	_check(_aim_at(p, p.get_camera().global_position, photo), "loft photo is reachable")
	_check(_aim_at(p, p.get_camera().global_position, sleep.get_node("BedButton")), "loft mattress is reachable")
	photo.interact(p)
	_check(state.get_flag("has_photo") and state.get_flag("seen_photo_room") and state.get_flag("read_old_photo"), "photo sets both story flags and opens its readable")
	for child in root.get_children():
		if child.has_method("_close") and child.has_signal("closed"):
			child._close()
	sleep.fade_time = 0.0
	await sleep.try_sleep()
	_check(routine.is_completed(), "room routine can finish")

	state.unlock_input("sleep")
	_check(await _walk(p, Vector3(-4, 3.21, -27.45), Vector3(-3.04, 3.2, -27.45), 0.0, true), "crouch-walk under the physical desk")
	for id in ["HideDesk", "HideWardrobe"]:
		var spot := level.get_node("Interactables/" + id) as Node3D
		p.teleport(Transform3D(Basis(), spot.global_position + Vector3.UP * 0.01))
		p._crouch_toggled = true
		await _frames(6)
		_check(p.is_hidden(), "crouched player can use " + id)

	audio.stop_all_ambience(0.0)
	level.queue_free()
	await create_timer(1.4).timeout
	print("dorm_shrine smoke: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)


func _aim_at(player: CharacterBody3D, eye: Vector3, target: Node3D) -> bool:
	var shape := target.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape == null:
		for child in target.get_children():
			if child is CollisionShape3D:
				shape = child
				break
	var to := shape.global_position if shape else target.global_position
	if eye.distance_to(to) > 2.0:
		return false
	var ray := PhysicsRayQueryParameters3D.create(eye, to, 1 | 4, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.get("collider") != target:
		print("  ray to ", target.name, " from ", eye, " hit ", hit.get("collider"), " at ", hit.get("position"))
		return false
	return true


func _walk(p: CharacterBody3D, start: Vector3, goal: Vector3, extra_time := 0.0, crouch := false) -> bool:
	var dir := Vector3(goal.x - start.x, 0, goal.z - start.z)
	var heading := Basis.looking_at(dir.normalized())
	p.teleport(Transform3D(heading, start))
	p._set_crouch(crouch)
	p._crouch_toggled = crouch
	p.walk_speed = 3.0
	Input.action_press("move_forward")
	var steps := ceili((dir.length() / (p.crouch_speed if crouch else p.walk_speed) + 0.14 + extra_time) * 60.0)
	await _frames(steps)
	Input.action_release("move_forward")
	var end := p.global_position
	var ok := end.distance_to(goal) < (0.16 if crouch else 0.50)
	if not ok:
		print("  wanted ", goal, ", reached ", end)
		for i in p.get_slide_collision_count():
			var hit := p.get_slide_collision(i)
			print("  collision ", hit.get_collider().name, " at ", hit.get_position(), " normal ", hit.get_normal())
	return ok


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _check(ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", detail)
