extends Node
## Headless unit tests for the entity state machines. Launched by run_logic_tests.gd:
##   godot --headless --path . -s res://gameplay/entities/test/run_logic_tests.gd
## Time is driven manually via entity.tick(dt) (manual_tick = true); observation is injected.
## (Separate from the SceneTree launcher so autoload globals exist when this compiles.)

signal done(exit_code: int)

const GAZER := "res://gameplay/entities/gazer/gazer.tscn"
const MIMIC := "res://gameplay/entities/mimic/mimic.tscn"
const GROUP := "res://gameplay/entities/crowd/crowd_group.tscn"
const MEMBER := "res://gameplay/entities/crowd/crowd_member.tscn"
const PLAYER := "res://gameplay/entities/test/stand_in_player.tscn"
const DOOR := preload("res://gameplay/entities/test/stand_in_door.gd")

const EXPECTED_CHECKS := 65  # bump when adding checks (guards against silently skipped sections)
var passes := 0
var fails := 0
var world: Node3D
var player: CharacterBody3D
var caught: Array = []      # [[entity_id, cause], ...]

var root: Window

func _ready() -> void:
	root = get_tree().root
	_run()

func check(cond: bool, label: String) -> void:
	if cond:
		passes += 1
		print("  PASS  ", label)
	else:
		fails += 1
		print("  FAIL  ", label)

func _run() -> void:
	await get_tree().process_frame
	var ev: Node = root.get_node("EventBus")
	ev.player_caught.connect(func(id, c): caught.append([id, c]))
	world = Node3D.new()
	world.name = "World"
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	fs.shape = box
	fs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fs)
	world.add_child(floor_body)
	player = load(PLAYER).instantiate()
	world.add_child(player)
	await get_tree().physics_frame
	await get_tree().physics_frame

	print("== observation")
	await _test_observation()
	print("== gazer")
	await _test_gazer()
	print("== mimic")
	await _test_mimic()
	print("== crowd")
	await _test_crowd()
	print("== director / autoplay")
	await _test_director()

	print("\n%d passed, %d failed" % [passes, fails])
	if passes + fails < EXPECTED_CHECKS:
		print("FAIL  only %d of %d checks ran (script error?)" % [passes + fails, EXPECTED_CHECKS])
	print("RESULT: ", "PASS" if fails == 0 and passes + fails >= EXPECTED_CHECKS else "FAIL")
	done.emit(0 if fails == 0 and passes + fails >= EXPECTED_CHECKS else 1)

func _reset_globals() -> void:
	var gs: Node = root.get_node("GameState")
	gs.input_locks.clear()
	gs.flashlight_on = false
	gs.debug_autoplay = false
	root.get_node("RenderSettings").set_static(0.0)
	caught.clear()

func _place_player(pos: Vector3, look_at := Vector3.INF) -> void:
	player.global_position = pos
	player.rotation = Vector3.ZERO
	player.cam.rotation = Vector3.ZERO
	if look_at != Vector3.INF:
		player.look_at_point(look_at, 0.0)

func _ticks(e: Node, n: int, dt := 0.1, until := Callable()) -> int:
	for i in n:
		e.tick(dt)
		if until.is_valid() and until.call():
			return i + 1
	return n

func _marker(pos: Vector3, nm: String) -> Marker3D:
	var m := Marker3D.new()
	m.name = nm
	world.add_child(m)
	m.global_position = pos
	return m

# ---------------------------------------------------------------------------- observation

func _test_observation() -> void:
	var cam := Transform3D(Basis(), Vector3(0, 1.6, 0))   # looks down -Z
	var O := EntityObservation
	check(O.is_point_in_view(cam, 70.0, 4.0 / 3.0, Vector3(0, 1.6, -5)), "point ahead is in view")
	check(not O.is_point_in_view(cam, 70.0, 4.0 / 3.0, Vector3(0, 1.6, 5)), "point behind is not in view")
	check(not O.is_point_in_view(cam, 70.0, 4.0 / 3.0, Vector3(10, 1.6, -5)), "point far to the side is outside frustum")
	check(O.is_point_in_view(cam, 70.0, 4.0 / 3.0, Vector3(4.8, 1.6, -5), 4.0), "point just outside edge counts with margin")
	check(not O.is_point_in_view(cam, 70.0, 4.0 / 3.0, Vector3(0, 1.6, -12), 4.0, 10.0), "point beyond fog distance is not seen")
	var pts := [Vector3(0, 1.6, -5)]
	check(O.is_observed(cam, 70.0, 1.333, pts, 10.0, 4.0, func(_a, _b): return true), "observed with clear LOS")
	check(not O.is_observed(cam, 70.0, 1.333, pts, 10.0, 4.0, func(_a, _b): return false), "not observed when LOS blocked")
	check(CrowdGroup.perceived_loudness(0.8, 5.0, 14.0) > 0.3 and CrowdGroup.perceived_loudness(0.15, 1.0, 14.0) < 0.3,
		"hearing: sprint at 5 m heard, walk at 1 m not")
	# physics LOS: glass (see_through) does not block, a wall does
	var glass := _wall(Vector3(0, 1.5, -3), true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := world.get_world_3d().direct_space_state
	check(O.ray_clear(space, Vector3(0, 1.6, 0), Vector3(0, 1.6, -6)), "glass (see_through) does not block sight")
	glass.queue_free()
	var wall := _wall(Vector3(0, 1.5, -3), false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not O.ray_clear(space, Vector3(0, 1.6, 0), Vector3(0, 1.6, -6)), "opaque wall blocks sight")
	wall.queue_free()
	await get_tree().physics_frame

func _wall(pos: Vector3, see_through: bool) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = "Pane" if see_through else "Wall"
	var s := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(4, 3, 0.1)
	s.shape = bx
	b.add_child(s)
	if see_through:
		b.add_to_group("see_through")
	world.add_child(b)
	b.global_position = pos
	return b

# ---------------------------------------------------------------------------- gazer

func _make_gazer(mode: int, markers: Array) -> Gazer:
	var g: Gazer = load(GAZER).instantiate()
	g.mode = mode
	g.manual_tick = true
	g.passive_override = 0
	g.cooldown_min = 1.0
	g.cooldown_max = 1.0
	g.first_move_delay = 0.0
	world.add_child(g)
	var paths: Array[NodePath] = []
	for m in markers:
		paths.append(g.get_path_to(m))
	g.path_markers = paths
	return g

func _test_gazer() -> void:
	_reset_globals()
	_place_player(Vector3.ZERO)
	var ms := [_marker(Vector3(0, 0, -12), "g0"), _marker(Vector3(0, 0, -8), "g1"),
		_marker(Vector3(0, 0, -4), "g2"), _marker(Vector3(0, 0, -1.5), "g3")]
	var obs := [true]
	var g := _make_gazer(Gazer.Mode.OUTSIDE_GLASS, ms)
	g.stare_distance = 3.0         # far away: no stare meter for the movement tests
	g.observation_override = func(): return obs[0]
	g.activate()
	check(g.global_position.is_equal_approx(ms[0].global_position), "gazer starts at first marker")
	_ticks(g, 50)
	check(g.index == 0, "gazer does not move while observed (5 s)")
	obs[0] = false
	_ticks(g, 1)
	check(g.index == 1 and g.global_position.is_equal_approx(ms[1].global_position), "gazer snaps to next marker when not observed")
	var fwd := -g.global_basis.z
	check(fwd.dot((player.global_position - g.global_position).normalized()) > 0.95, "gazer faces the player after moving")
	_ticks(g, 5)
	check(g.index == 1, "gazer respects cooldown between moves")
	# flicker lets it move even while observed
	obs[0] = true
	_ticks(g, 12)
	var before := g.index
	root.get_node("EventBus").lights_flicker.emit("store_lights", 1.0)
	_ticks(g, 1)
	check(g.index == before + 1, "gazer moves during a light flicker even when observed")
	# reach end in outside_glass mode -> reached_end, no death
	var ended := [false]
	g.reached_end.connect(func(): ended[0] = true)
	obs[0] = false
	_ticks(g, 40, 0.1, func(): return ended[0])
	check(ended[0] and g.state == "at_glass", "outside_glass: last marker -> reached_end + glass scare")
	check(caught.is_empty(), "outside_glass: reaching the glass does not kill")
	g.deactivate()
	g.queue_free()

	# --- stare meter (hunt mode)
	_reset_globals()
	var h := _make_gazer(Gazer.Mode.HUNT, ms)
	h.cooldown_min = 2.5
	h.cooldown_max = 2.5
	h.stare_distance = 14.0
	h.observation_override = func(): return obs[0]
	var stared := [false]
	h.stared_out.connect(func(): stared[0] = true)
	h.activate()
	obs[0] = true
	_ticks(h, 25)
	check(h.stare > 2.4 and root.get_node("RenderSettings").get_static() > 0.0, "stare > 2 s raises static")
	obs[0] = false
	_ticks(h, 30)
	check(h.stare == 0.0 and root.get_node("RenderSettings").get_static() == 0.0, "looking away decays meter and static")
	check(h.index >= 1, "hunt gazer advanced while unobserved")
	h.index = 0
	h._snap_to_marker(0)
	obs[0] = true
	_ticks(h, 49)
	check(not stared[0] and caught.is_empty(), "no stare-out before 5 s")
	_ticks(h, 2)
	check(stared[0] and h.state == "staring_out", "stare meter hits 5 s -> stared_out")
	check(root.get_node("GameState").is_input_locked(), "stare-out locks input")
	_ticks(h, 13)
	check(caught.size() == 1 and caught[0][1] == "gazer_stare", "stare-out ends in player_caught(gazer_stare)")
	var seq: Node = h.last_sequence
	check(seq != null, "caught sequence started")
	if seq:
		var done_state := [""]
		root.get_node("EventBus").entity_state_changed.connect(func(id, s): if s == "caught_done": done_state[0] = id)
		await seq.finished
		check(done_state[0] == h.entity_id, "caught sequence finished -> entity_state_changed(caught_done)")
		check(not root.get_node("GameState").is_input_locked(), "caught sequence releases its input lock")
	h.deactivate()
	h.queue_free()

	# --- hunt: reaching last marker = caught
	_reset_globals()
	var h2 := _make_gazer(Gazer.Mode.HUNT, ms)
	h2.stare_distance = 0.5
	h2.observation_override = func(): return false
	h2.activate()
	_ticks(h2, 60, 0.1, func(): return not caught.is_empty())
	check(caught.size() == 1 and caught[0][1] in ["gazer_reach", "gazer_touch"], "hunt: last marker -> caught")
	h2.deactivate()
	h2.queue_free()
	for m in ms:
		m.queue_free()
	await _settle()

# ---------------------------------------------------------------------------- mimic

func _make_mimic(door: Node3D, outside: Marker3D, inside: Marker3D) -> Mimic:
	var m: Mimic = load(MIMIC).instantiate()
	m.manual_tick = true
	m.passive_override = 0
	m.voice_lines = ["test_01", "test_01"] as Array[String]
	m.ask_after_lines = ["test_01"] as Array[String]
	m.ask_timeout = 30.0
	m.start_delay = 0.1
	m.knock_pause = 0.2
	m.line_pause = 0.2
	m.wait_duration = 2.0
	m.leave_time = 1.0
	m.breach_time = 1.0
	world.add_child(m)
	m.door_path = m.get_path_to(door)
	m.outside_marker = m.get_path_to(outside)
	m.inside_marker = m.get_path_to(inside)
	return m

func _new_door() -> Node3D:
	var d := Node3D.new()
	d.set_script(DOOR)
	d.name = "Door"
	world.add_child(d)
	d.global_position = Vector3(5, 0, 0)
	return d

func _test_mimic() -> void:
	var ev: Node = root.get_node("EventBus")
	var outside := _marker(Vector3(5, 0, 1), "m_out")
	var inside := _marker(Vector3(5, 0, -0.6), "m_in")
	_place_player(Vector3(5, 0, -3))

	# --- answering -> breach -> caught
	_reset_globals()
	var door := _new_door()
	var m := _make_mimic(door, outside, inside)
	var knocks := [0]
	ev.door_knock.connect(func(id): if id == "test_door": knocks[0] += 1)
	var flags := {"breached": false, "survived": false}
	m.breached.connect(func(): flags.breached = true)
	m.survived.connect(func(): flags.survived = true)
	m.activate()
	check(m.body.get_shape("neck_tilt") == 1.0 and m.body.get_shape("long_arms") == 1.0, "mimic tells: neck tilt + long arms")
	var shadowless := true
	for mi in m.body.get_meshes():
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			shadowless = false
	check(shadowless, "mimic casts no shadow")
	_ticks(m, 300, 0.1, func(): return m.state == "asking")
	check(knocks[0] >= 1, "mimic knocked (EventBus.door_knock)")
	check(m.state == "asking", "mimic asks after a question line")
	ev.choice_made.emit(0)
	for i in 3:
		await get_tree().process_frame
	check(m.state == "breach" and flags.breached, "answering -> breach")
	check(door.is_open(), "breach opens the door by itself")
	_ticks(m, 15)
	check(caught.size() == 1 and caught[0][1] == "mimic_answered", "breach -> player_caught(mimic_answered)")
	if m.last_sequence:
		await m.last_sequence.finished
	m.deactivate()
	m.queue_free()
	door.queue_free()

	# --- silence -> gives up -> survived
	_reset_globals()
	door = _new_door()
	m = _make_mimic(door, outside, inside)
	flags = {"breached": false, "survived": false}
	m.breached.connect(func(): flags.breached = true)
	m.survived.connect(func(): flags.survived = true)
	m.activate()
	_ticks(m, 300, 0.1, func(): return m.state == "asking")
	ev.choice_made.emit(1)
	for i in 3:
		await get_tree().process_frame
	check(m.state == "talk", "silence -> keeps talking")
	for round in 5:   # second line asks again -> stay silent again
		_ticks(m, 400, 0.1, func(): return flags.survived or m.state == "asking")
		if m.state != "asking":
			break
		ev.choice_made.emit(1)
		for i in 3:
			await get_tree().process_frame
	check(flags.survived and not flags.breached and caught.is_empty(), "silence + door shut -> survived")
	check(not m.is_active() and not door.is_open(), "mimic leaves, door stays shut")
	m.queue_free()
	door.queue_free()

	# --- player opens the door -> breach
	_reset_globals()
	door = _new_door()
	m = _make_mimic(door, outside, inside)
	flags = {"breached": false, "survived": false}
	m.breached.connect(func(): flags.breached = true)
	m.activate()
	_ticks(m, 100, 0.1, func(): return m.state == "talk")
	door.set_open(true)
	check(m.state == "breach" and flags.breached, "door opened by player -> breach")
	check(m.global_position.is_equal_approx(inside.global_position), "mimic stands in the doorway on breach")
	_ticks(m, 15)
	check(caught.size() == 1 and caught[0][1] == "mimic_door_opened", "door breach -> caught")
	if m.last_sequence:
		await m.last_sequence.finished
	m.deactivate()
	m.queue_free()
	door.queue_free()

	# --- truth message read while talking -> ignored line queued
	_reset_globals()
	door = _new_door()
	m = _make_mimic(door, outside, inside)
	m.truth_message_id = "m_test_01"
	m.on_ignored_line = "test_01"
	m.activate()
	_ticks(m, 100, 0.1, func(): return m.state == "talk")
	root.get_node("GameState").set_flag("read_m_test_01", true)
	check(m._ignored_pending, "reading the truth message while it talks -> on_ignored_line queued")
	root.get_node("GameState").flags.clear()
	m.deactivate()
	m.queue_free()
	door.queue_free()

	# --- corridor mode: follows when unobserved, leaves when player locked in room
	_reset_globals()
	door = _new_door()
	var c_out := _marker(Vector3(0, 0, 10), "c_out")
	var room := _marker(Vector3(0, 0, 20), "c_room")
	m = _make_mimic(door, c_out, room)
	m.mode = Mimic.Mode.CORRIDOR
	var obs := [true]
	m.observation_override = func(): return obs[0]
	flags = {"breached": false, "survived": false}
	m.survived.connect(func(): flags.survived = true)
	_place_player(Vector3(3, 0, 10))
	m.activate()
	_ticks(m, 20)
	check(m.state == "following" and absf(m.body.head_yaw) > 0.5, "corridor: notices player within range, head turns")
	var p0 := m.global_position
	_ticks(m, 20)
	check(m.global_position.is_equal_approx(p0), "corridor: does not follow while watched")
	obs[0] = false
	_ticks(m, 3)
	check(m.global_position.distance_to(player.global_position) < p0.distance_to(player.global_position), "corridor: follows when not watched")
	_place_player(room.global_position)
	door.lock()
	_ticks(m, 60, 0.1, func(): return flags.survived)
	check(flags.survived and caught.is_empty(), "corridor: leaves when player locks himself in the room")
	m.queue_free()
	door.queue_free()
	for n in [outside, inside, c_out, room]:
		n.queue_free()
	await _settle()

# ---------------------------------------------------------------------------- crowd

func _make_group() -> CrowdGroup:
	var g: CrowdGroup = load(GROUP).instantiate()
	g.manual_tick = true
	g.passive_override = 0
	g.los_override = func(_a, _b): return true
	var poses := ["wait", "wait", "sit", "sweep"]
	var offs := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1)]
	for i in 4:
		var mem: CrowdMember = load(MEMBER).instantiate()
		mem.pose = poses[i]
		mem.look_seed = i
		mem.position = Vector3(20, 0, 0) + offs[i]
		g.add_child(mem)
	world.add_child(g)
	return g

func _test_crowd() -> void:
	_reset_globals()
	var ev: Node = root.get_node("EventBus")
	var g := _make_group()
	await get_tree().physics_frame
	var flags := {"alerted": 0, "calmed": 0}
	g.alerted.connect(func(): flags.alerted += 1)
	g.calmed.connect(func(): flags.calmed += 1)
	g.activate()
	check(g.get_members().size() == 4, "group has 4 members")
	# far: nothing
	_place_player(Vector3(28, 0, -2))     # ~7.3 m from nearest
	_ticks(g, 10)
	var all_zero := true
	for m in g.get_members():
		if not is_zero_approx(m.body.head_yaw):
			all_zero = false
	check(g.state == "frozen" and all_zero, "outside 5 m: heads stay still")
	ev.noise_emitted.emit(player.global_position, 0.15)
	check(g.state == "frozen", "walking noise at 7 m does not alert")
	# near: all heads turn together, in discrete steps
	_place_player(Vector3(24, 0, -2))     # ~3.6 m
	_ticks(g, 1, 0.01)
	var targets := []
	var first_step_ok := true
	for m in g.get_members():
		var tgt := wrapf(EntityObservation.yaw_to(m.global_position, player.cam.global_position) - m.global_rotation.y, -PI, PI)
		targets.append(tgt)
		if absf(m.body.head_yaw - tgt / 3.0) > 0.03:
			first_step_ok = false
	check(g.state == "noticing", "within 5 m -> noticing")
	check(first_step_ok, "all heads snap the first of 3 steps simultaneously")
	_ticks(g, 6, 0.05)
	var tracking := true
	var i := 0
	for m in g.get_members():
		if absf(m.body.head_yaw - targets[i]) > 0.05:
			tracking = false
		i += 1
	check(tracking, "after 3 snaps all heads face the player")
	# noise -> alert
	_place_player(Vector3(26, 0, -4))
	ev.noise_emitted.emit(player.global_position, 0.8)
	check(g.state == "chase" and flags.alerted == 1, "sprint noise nearby -> alerted chase")
	var start_d := g.nearest_distance(player.global_position)
	_ticks(g, 5)
	check(g.nearest_distance(player.global_position) < start_d, "crowd closes distance while chasing")
	# calm after chase_time (player kept out of reach)
	g.chase_time = 2.0
	g.chase_speed = 0.3
	_place_player(Vector3(35, 0, -10))
	_ticks(g, 30, 0.1, func(): return g.state != "chase")
	check(g.state == "returning" and flags.calmed == 1, "gives up after chase_time -> calmed")
	_ticks(g, 400, 0.1, func(): return g.state == "frozen")
	var home := true
	for m in g.get_members():
		if not m.is_at_post():
			home = false
	check(g.state == "frozen" and home, "members walk back to their posts and freeze")
	# flashlight held on a member > 1 s -> alert
	_place_player(Vector3(20.5, 0, -6))
	player.look_at_point(g.get_members()[0].chest_position(), 0.0)
	root.get_node("GameState").flashlight_on = true
	_ticks(g, 8)
	check(g.state != "chase", "flashlight < 1 s does not alert")
	_ticks(g, 4)
	check(g.state == "chase" and flags.alerted == 2, "flashlight on a member > 1 s -> alert")
	root.get_node("GameState").flashlight_on = false
	# touch -> caught
	g.chase_speed = 3.4
	g.chase_time = 20.0
	_ticks(g, 60, 0.1, func(): return not caught.is_empty())
	check(caught.size() == 1 and caught[0][1] == "crowd_touch", "crowd touches player -> caught")
	if g.last_sequence:
		await g.last_sequence.finished
	g.deactivate()
	g.queue_free()
	await _settle()

# ---------------------------------------------------------------------------- director / autoplay

func _test_director() -> void:
	_reset_globals()
	var lvl := Node3D.new()
	lvl.name = "Level"
	world.add_child(lvl)
	var ents := Node3D.new()
	ents.name = "Entities"
	lvl.add_child(ents)
	var g: Gazer = load(GAZER).instantiate()
	g.entity_id = "g1"
	ents.add_child(g)
	var mm: Mimic = load(MIMIC).instantiate()
	mm.entity_id = "m1"
	ents.add_child(mm)
	var grp := _make_group()
	grp.entity_id = "c1"
	grp.reparent(ents)
	var dir := EntityDirector.new()
	lvl.add_child(dir)
	await get_tree().process_frame
	await get_tree().process_frame
	check(dir.get_entity("g1") == g and dir.get_entity("m1") == mm and dir.get_entity("c1") == grp, "director finds entities under Entities/")
	dir.activate_only(["g1", "c1"])
	check(g.is_active() and grp.is_active() and not mm.is_active(), "activate_only")
	dir.deactivate_all()
	check(not g.is_active() and not grp.is_active(), "deactivate_all")
	# autoplay: passive entities never catch / alert
	root.get_node("GameState").debug_autoplay = true
	grp.passive_override = -1
	grp.manual_tick = true
	grp.activate()
	root.get_node("EventBus").noise_emitted.emit(grp.get_members()[0].global_position, 1.0)
	check(grp.state != "chase", "debug_autoplay: crowd ignores noise")
	g.passive_override = -1
	g.manual_tick = true
	g.observation_override = func(): return true
	g.activate()
	_place_player(g.global_position + Vector3(0, 0, 3))
	_ticks(g, 80)
	check(caught.is_empty() and g.stare == 0.0, "debug_autoplay: gazer never stares the player out")
	root.get_node("GameState").debug_autoplay = false
	lvl.queue_free()
	await _settle()

func _settle() -> void:
	for i in 3:
		await get_tree().process_frame
