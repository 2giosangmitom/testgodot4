extends SceneTree
## godot --headless --path . -s res://levels/school/test_level.gd

const SCENE := "res://levels/school/school.tscn"
const SPAWNS := ["default", "classroom", "street", "gate_outside"]
const CAMERAS := ["cam_courtyard", "cam_classroom", "cam_gate", "cam_street", "cam_bus_stop"]
const TRIGGERS := ["trig_gate", "trig_ch3_gate", "trig_ch3_leave"]
const CROWDS := {
	"CrowdBusStop": ["wait", "wait", "wait", "wait"],
	"CrowdSweepers": ["sweep", "sweep"],
	"CrowdTeaShop": ["sit", "sit", "sit"],
	"CrowdSchoolyard": ["sit", "sit", "sit", "wait"],
}

class ScriptErrorCounter extends Logger:
	var _mutex := Mutex.new()
	var _count := 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_SCRIPT:
			_mutex.lock()
			_count += 1
			_mutex.unlock()

	func count() -> int:
		_mutex.lock()
		var result := _count
		_mutex.unlock()
		return result

var level
var player
var state
var failures := 0
var script_errors := ScriptErrorCounter.new()


func _initialize() -> void:
	OS.add_logger(script_errors)
	_run.call_deferred()


func _run() -> void:
	create_timer(15.0).timeout.connect(func():
		printerr("FAIL: school smoke timed out")
		quit(1))
	state = root.get_node("GameState")
	var scene := load(SCENE) as PackedScene
	if not scene or not state:
		_check(false, "level and GameState load")
		quit(1)
		return
	level = scene.instantiate()
	root.add_child(level)
	current_scene = level
	if _check_paths():
		_check_presets()
		_check_crowds()
		await _check_spawns()
		if player:
			await _check_routes()
			await _check_navigation()
	await _finish()


func _check_paths() -> bool:
	_check(level.level_id == "school", "school level id")
	var paths := ["Env/SchoolGeometry", "NavigationRegion3D", "Doors/Grocery", "Doors/ClassroomA",
		"Presets/day/WorldEnvironment", "Presets/night_ch3/WorldEnvironment", "Markers/MARKER_seat_nam",
		"Interactables/MissingPoster", "Interactables/IncensePickup", "Interactables/GuardOilPickup",
		"NPCs/Thay_Khai", "NPCs/Linh", "NPCs/Hung", "NPCs/BacTu", "NPCs/Students"]
	for spawn in SPAWNS:
		paths.append("Spawns/" + spawn)
	for camera in CAMERAS:
		paths.append("Markers/" + camera)
	for trigger in TRIGGERS:
		paths.append("Triggers/" + trigger)
	for crowd in CROWDS:
		paths.append("Entities/" + crowd)
	for path in paths:
		_check(level.has_node(path), path)
	return failures == 0


func _check_presets() -> void:
	var day_env: WorldEnvironment = level.get_node("Presets/day/WorldEnvironment")
	var night_env: WorldEnvironment = level.get_node("Presets/night_ch3/WorldEnvironment")
	var render = root.get_node("RenderSettings")
	_check(day_env.environment != null and night_env.environment == null, "one active day environment")
	_check(state.clock_minutes == 16 * 60 + 40 and render.current_preset == "day", "day fog and 16:40 clock")
	level.apply_preset("night_ch3")
	_check(day_env.environment == null and night_env.environment != null, "one active night environment")
	_check(state.clock_minutes == 22 * 60 and render.current_preset == "night", "night fog and 22:00 clock")
	var flickers := get_nodes_in_group("school_streetlights")
	_check(flickers.size() == 4 and flickers.all(func(f): return f.mode == 3 and f.mesh != null),
		"four sodium lamps drive the imported emitters")


func _check_crowds() -> void:
	for id in CROWDS:
		var group = level.get_node("Entities/" + id)
		var members: Array = group.get_members()
		_check(not group.is_active() and not group.visible and members.size() == CROWDS[id].size(), id + " inactive with correct count")
		for i in mini(members.size(), CROWDS[id].size()):
			_check(members[i].pose == CROWDS[id][i] and not members[i].body.is_placeholder,
				"%s member %d uses real model and pose" % [id, i + 1])
		group.activate()
		_check(group.is_active() and group.visible, id + " activates")
		group.deactivate()
	for npc in level.get_node("NPCs").get_children():
		_check(not npc.visible and npc.get_child_count() == (3 if npc.name == "Students" else 1),
			String(npc.name) + " hidden with imported character(s)")


func _check_spawns() -> void:
	for id in SPAWNS:
		var marker: Marker3D = level.get_spawn(id)
		player = level.spawn_player(id)
		if not player:
			_check(false, id + " spawns the player")
			return
		_check(player.global_position.is_equal_approx(marker.global_position), id + " teleports to marker")
		for i in 12:
			await physics_frame
		_check(player.is_on_floor() and absf(player.global_position.y - marker.global_position.y) < 0.06,
			id + " lands on solid ground")


func _check_routes() -> void:
	level.spawn_player("classroom")
	player.set_physics_process(false)
	await _walk_to(Vector2(-2.55, -21.85), "reach classroom doorway from Nam's seat")
	await _open_door("ClassroomA", Vector3(-2.55, 1.57, -21.0))
	await _walk_to(Vector2(-2.55, -19.5), "walk out of Classroom A")
	await _walk_to(Vector2(0, -19.5), "walk along school corridor")
	await _walk_to(Vector2(0, -16.3), "descend the school steps")
	await _walk_to(Vector2(1.45, -16.3), "enter courtyard")
	await _walk_to(Vector2(1.45, -4.0), "cross courtyard beside flagpole")
	await _walk_to(Vector2(0, -1.2), "reach inside gate trigger")
	_check(state.get_flag("trig_trig_gate"), "inside gate trigger fires")
	await _walk_to(Vector2(0, 0.95), "cross open sliding gate")
	_check(state.get_flag("trig_trig_ch3_gate"), "night gate trigger fires")
	await _walk_to(Vector2(0, -3.0), "return via gate")
	await _walk_to(Vector2(-6.3, -3.0), "reach guard booth entrance")
	await _walk_to(Vector2(-6.3, -1.65), "enter guard booth")
	_use("GuardOilPickup", Vector3(-6.45, 0.86, -0.89))
	_check(state.get_flag("has_oil"), "guard oil sets inventory flag")

	await _walk_to(Vector2(-6.3, -3.0), "leave guard booth")
	await _walk_to(Vector2(-7.6, -15.12), "reach courtyard notice board")
	_use("MissingPoster", Vector3(-7.6, 1.55, -16.534))
	_check(state.get_flag("read_missing_poster") and state.get_flag("has_name_tag"), "poster sets readable and name flags")
	for child in root.get_children():
		if child.has_signal("closed") and child.has_method("_close"):
			child._close()

	level.spawn_player("gate_outside")
	await _walk_to(Vector2(6.0, 4.5), "walk down the street curb")
	await _walk_to(Vector2(15.325, 4.5), "follow the road past the bus stop")
	await _walk_to(Vector2(15.325, 10.35), "cross road and climb far curb")
	await _open_door("Grocery", Vector3(15.325, 1.13, 10.95))
	await _walk_to(Vector2(15.325, 12.34), "enter grocery through its open door")
	_use("IncensePickup", Vector3(16.78, 0.88, 12.36))
	_check(state.get_flag("has_incense"), "grocery incense sets inventory flag")
	await _walk_to(Vector2(15.325, 9.0), "leave grocery")
	await _walk_to(Vector2(37.8, 8.5), "reach street end")
	_check(state.get_flag("trig_trig_ch3_leave"), "alley exit trigger fires")


func _open_door(id: String, look_target: Vector3) -> void:
	var door = level.get_node("Doors/" + id)
	_check(not door.locked and _ray_target(look_target) == door, id + " is unlocked and targetable")
	door.open_time = 0.02
	door.interact(player)
	for i in 6:
		await physics_frame
	_check(door.is_open and not door.moving, id + " swings open")


func _use(id: String, look_target: Vector3) -> void:
	var target = level.get_node("Interactables/" + id)
	if _check(_ray_target(look_target) == target, id + " is targetable with the player ray"):
		target.interact(player)


func _ray_target(look_target: Vector3) -> Object:
	var origin: Vector3 = player.get_camera().global_position
	var dir := (look_target - origin).normalized()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * player.interact_range,
		1 | 4 | 32, [player.get_rid()])
	return level.get_world_3d().direct_space_state.intersect_ray(query).get("collider")


func _walk_to(goal: Vector2, label: String) -> void:
	# Real player motion/capsule, without waiting for keyboard acceleration at each waypoint.
	var player_at := Vector2(player.position.x, player.position.z)
	for i in int(player_at.distance_to(goal) * 20.0) + 60:
		var remaining := goal - Vector2(player.position.x, player.position.z)
		if remaining.length() < 0.035:
			break
		var move := remaining.limit_length(0.064) * 60.0
		player.velocity = Vector3(move.x, -2.0, move.y)
		player.move_and_slide()
	for i in 4:
		await physics_frame
	var end := Vector2(player.position.x, player.position.z)
	_check(end.distance_to(goal) < 0.08 and player.position.y > -0.3, label + (" (stopped at %s)" % [end] if end.distance_to(goal) >= 0.08 else ""))


func _check_navigation() -> void:
	var nav: NavigationRegion3D = level.get_node("NavigationRegion3D")
	for i in 120:
		if nav.navigation_mesh.get_polygon_count() > 0:
			break
		await physics_frame
	_check(nav.navigation_mesh.get_polygon_count() > 0, "crowd navigation mesh bakes")
	await physics_frame
	await physics_frame
	var map := nav.get_navigation_map()
	_nav_route(map, Vector3(12, 0, 2.4), Vector3(0, 0, -5), "crowd navigation connects sidewalk and courtyard")
	_nav_route(map, Vector3(12, 0, 2.4), Vector3(15.3, 0, 12.0), "crowd navigation crosses the road into the grocery")


func _nav_route(map: RID, start: Vector3, goal: Vector3, label: String) -> void:
	var path := NavigationServer3D.map_get_path(map, start, goal, true)
	var end := path[-1] if not path.is_empty() else Vector3.INF
	_check(Vector2(end.x, end.z).distance_to(Vector2(goal.x, goal.z)) < 0.35
		and absf(end.y - goal.y) < 0.5, label)


func _check(ok: bool, label: String) -> bool:
	if not ok:
		printerr("FAIL: ", label)
		failures += 1
	return ok


func _finish() -> void:
	var audio := root.get_node("AudioDirector")
	for child in audio.get_children() + level.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
	audio.stop_all_ambience(0.0)
	# Allow the headless audio server to release old crossfades and one-shots.
	await create_timer(1.6).timeout
	var errors := script_errors.count()
	_check(errors == 0, "%d script errors (see log)" % errors)
	print("school smoke: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures else 0)
