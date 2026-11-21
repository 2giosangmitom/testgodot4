extends LevelBase
## Assembles gameplay over the level-space dorm and shrine imports.

const ENV_MODELS := "res://assets/models/env/"
const PROPS := "res://assets/models/props/"
const CHARS := "res://assets/models/chars/"
const MIMIC := preload("res://gameplay/entities/mimic/mimic.tscn")
const GAZER := preload("res://gameplay/entities/gazer/gazer.tscn")
const NOODLES := preload("res://gameplay/minigames/noodles/noodles.tscn")
const ROUTINE := preload("res://gameplay/minigames/room_routine/room_routine.tscn")
const F2 := 3.2
const LOFT := 5.1
const LOFT_BOTTOM := Vector3(-4.21, F2 + 0.02, -26.85)
const LOFT_TOP := Vector3(-5.59, LOFT + 0.02, -27.12)

@onready var env: Node3D = $Env
@onready var spawns: Node3D = $Spawns
@onready var markers: Node3D = $Markers
@onready var presets: Node3D = $Presets
@onready var doors: Node3D = $Doors
@onready var interactables: Node3D = $Interactables
@onready var triggers: Node3D = $Triggers
@onready var entities: Node3D = $Entities

var _room_switch: LightSwitch
var _routine_switch: MinigameLightSwitch
var _street_driver: FlickerLight
var _active_preset := ""
var _climbing := false

class InwardGate extends Door:
	func _on_interact(_p: Node3D) -> void:
		if is_open or locked:
			super._on_interact(_p)
		else:
			open_door() # keep the narrow lane clear, even when leaving the dorm


func _ready() -> void:
	super._ready()
	_build_markers()
	_build_doors()
	_refit_room_geometry()
	_build_room()
	_build_shrine()
	_build_encounters()
	_build_presets()
	_build_navigation()
	PSXApply.apply_to(self)
	EventBus.lights_set.connect(_sync_room_switch)
	apply_preset(default_preset)


func _build_markers() -> void:
	_marker(spawns, "default", Vector3.ZERO)
	_marker(spawns, "room", Vector3(-3.92, F2 + 0.01, -25.86), -90)
	_marker(spawns, "corridor_stairs", Vector3(-1.73, F2 + 0.01, -14.69))
	_marker(spawns, "ground_floor", Vector3(-2.04, 0.01, -15.69), 90)
	_marker(spawns, "shrine_lane", _source("spawn_shrine").global_position)
	_marker(spawns, "shrine", Vector3(0.05, 0.01, -35.45), -17)
	for id in ["cam_corridor", "cam_room", "cam_dorm_gate", "cam_lane"]:
		_camera(id, _source(id).global_transform)
	_camera("cam_lane_end", _looking_from(Vector3(0.44, 1.67, -12.7), Vector3(0, 1.20, -7.25)))
	_camera("cam_shrine_wide", _looking_from(Vector3(-0.08, 2.27, -35.20), Vector3(0.5, 1.95, -39.0)))
	_camera("cam_streetlight_low", _looking_from(Vector3(0.05, 0.35, -35.53), Vector3(0.7, 2.47, -38.72)))
	_marker(markers, "mimic_door_out", Vector3(-1.78, F2, -25.86), 90)
	_marker(markers, "mimic_door_in", Vector3(-2.85, F2, -25.86), -90)
	_marker(markers, "mimic_corridor", Vector3(-2.40, F2, -17.00), 180)
	_marker(markers, "mimic_room_safe", Vector3(-4.28, F2, -25.92), -90)
	_marker(markers, "CallNamePoint", _source("shrine_altar").global_position)
	_marker(markers, "hung_ending", Vector3(0.02, 0, -7.25), 180)
	var positions := [Vector3(-0.15, 0, -18.90), Vector3(-0.32, 0, -24.20),
		Vector3(-0.18, 0, -30.4), Vector3(-0.10, 0, -34.55), Vector3(-0.85, 0, -36.9)]
	for i in positions.size():
		_marker(markers, "tuan_%d" % (i + 1), positions[i], 180)
	for spec in [
		["trig_lane_enter", Vector3(0, 0, -0.5), Vector3(2.1, 2.4, 2.0)],
		["trig_stairs_up", Vector3(-2.0, F2, -14.7), Vector3(1.4, 2.1, 0.96)],
		["trig_corridor", Vector3(-1.76, F2, -20.65), Vector3(1.25, 2.1, 10.6)],
		["trig_room", Vector3(-4.67, F2, -26.64), Vector3(3.6, 2.5, 2.95)],
		["trig_square", Vector3(0, 0, -35.85), Vector3(5.5, 2.3, 1.7)],
		["trig_shrine_close", Vector3(1.55, 0, -38.49), Vector3(1.65, 2.2, 1.65)],
	]:
		var trigger := TriggerZone.new()
		trigger.name = spec[0]
		trigger.trigger_id = spec[0]
		trigger.position = spec[1]
		trigger.size = spec[2]
		triggers.add_child(trigger)


func _build_doors() -> void:
	for number in range(201, 206):
		var at := _source("door_%d" % number)
		var door := _door("Door%d" % number, "door_%d" % number, "door_dorm", at.position,
			at.rotation_degrees.y, 0.9, 2.1, number != 204)
		door.force_open_sign = 1
		var plate := MinigameUtil.label("P.%d" % number, 24, 0.004, Color(0.84, 0.79, 0.63))
		plate.position = _source("plate_%d" % number).position
		plate.rotation_degrees.y = 90
		env.add_child(plate)
		if number == 205:
			door.prompt_locked = "Ổ khóa"
			_padlock(door)
	var wc := _door("RoomWCDoor", "room_wc_door", "door_wood", Vector3(-6.35, F2, -25.30),
		90, 0.75, 1.74, false)
	wc.open_angle = 94.0
	# A full-width leaf: two panels on a single interaction, no middle obstruction.
	var gate_at := _source("door_gate_l")
	var gate := _door("DormGate", "dorm_gate", "gate_iron", gate_at.position, gate_at.rotation_degrees.y, 2.0, 2.2, false)
	gate.open_angle = 90.0


func _door(node_name: String, id: String, model: String, pos: Vector3, yaw: float,
		width: float, height: float, locked: bool) -> Door:
	var door: Door = InwardGate.new() if model == "gate_iron" else Door.new()
	door.name = node_name
	door.door_id = id
	door.position = pos
	door.rotation_degrees.y = yaw
	door.width = width
	door.height = height
	door.locked = locked
	var leaf := _model(door, ENV_MODELS, model)
	# Door's own layer-1/3 collider rotates around the hinge and supplies the interaction.
	for body in leaf.find_children("*", "StaticBody3D", true, false):
		body.free()
	if model == "gate_iron":
		var other := leaf.duplicate() as Node3D
		other.position.x = 2.0
		other.rotation.y = PI
		door.add_child(other)
	else:
		leaf.scale = Vector3(width / 0.9, height / 2.1, 1)
	doors.add_child(door)
	return door


func _padlock(door: Door) -> void:
	var shell := MinigameUtil.box(Vector3(0.065, 0.08, 0.038), Color(0.37, 0.27, 0.14), Vector3(0.81, 1.14, 0.057))
	shell.name = "Padlock"
	door.add_child(shell)
	var shackle := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.023
	ring.outer_radius = 0.035
	ring.rings = 8
	ring.ring_segments = 4
	ring.material = MinigameUtil.make_mat(Color(0.36, 0.36, 0.34))
	shackle.mesh = ring
	shackle.rotation.x = PI / 2.0
	shackle.position = Vector3(0.81, 1.18, 0.053)
	door.add_child(shackle)


func _refit_room_geometry() -> void:
	# The art import batches furniture by material. Remove just the worktop, laptop
	# and stool triangles before fitting a real desk with a 1 m crouch clearance.
	_prune_mesh("dorm_desk_wood", AABB(Vector3(-3.21, 3.19, -27.86), Vector3(0.60, 0.79, 1.23)))
	_prune_mesh("dorm_metal_dark", AABB(Vector3(-3.06, 3.955, -27.56), Vector3(0.32, 0.26, 0.47)))
	_prune_mesh("dorm_plastic_red", AABB(Vector3(-3.81, 3.19, -27.51), Vector3(0.63, 0.5, 0.63)))
	env.find_child("laptop_screen_emit", true, false).hide()
	_prune_collision("dorm_props", AABB(Vector3(-3.21, 3.79, -27.86), Vector3(0.60, 0.18, 1.22)))
	# Remove the few centimetres of collider hanging below the loft slab in the
	# WC lintel. The visible jamb and lintel keep their original silhouette.
	_prune_collision("dorm_walls", AABB(Vector3(-6.405, 4.945, -26.055), Vector3(0.11, 0.04, 0.76)))

	var desk := _model(env, PROPS, "small_desk", Vector3(-2.98, F2, -27.25), -90)
	desk.scale = Vector3(1.50, 1.565, 1.32)
	var laptop := _model(env, PROPS, "laptop", Vector3(-2.94, F2 + 1.127, -27.28), -90)
	laptop.scale = Vector3.ONE * 1.15
	_model(env, PROPS, "plastic_stool", Vector3(-3.53, F2, -27.86))
	_world_box("DeskTopCollision", Vector3(-2.98, F2 + 1.107, -27.25), Vector3(0.66, 0.04, 1.20))
	for x in [-3.27, -2.69]:
		for z in [-27.81, -26.69]:
			_world_box("DeskLeg", Vector3(x, F2 + 0.544, z), Vector3(0.046, 1.088, 0.053))
	_world_box("LoftCeiling", Vector3(-5.1, 6.28, -26.6), Vector3(4.99, 0.16, 2.98))


func _prune_mesh(id: String, space: AABB) -> void:
	var m := env.find_child(id, true, false) as MeshInstance3D
	if m == null:
		return
	var original := m.mesh
	var result := ArrayMesh.new()
	var local_to_level := global_transform.affine_inverse() * m.global_transform
	for surface in original.get_surface_count():
		var arrays := original.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var keep := PackedInt32Array()
		for i in range(0, indices.size(), 3):
			if not (space.has_point(local_to_level * points[indices[i]]) and
					space.has_point(local_to_level * points[indices[i + 1]]) and
					space.has_point(local_to_level * points[indices[i + 2]])):
				keep.append(indices[i])
				keep.append(indices[i + 1])
				keep.append(indices[i + 2])
		if not keep.is_empty():
			arrays[Mesh.ARRAY_INDEX] = keep
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			result.surface_set_material(result.get_surface_count() - 1, original.surface_get_material(surface))
	m.mesh = result


func _prune_collision(id: String, space: AABB) -> void:
	var body := env.find_child(id, true, false) as StaticBody3D
	if body == null:
		return
	for child in body.get_children():
		var c := child as CollisionShape3D
		if c == null or not c.shape is ConcavePolygonShape3D:
			continue
		var faces: PackedVector3Array = c.shape.get_faces()
		var keep := PackedVector3Array()
		var local_to_level := global_transform.affine_inverse() * c.global_transform
		for i in range(0, faces.size(), 3):
			if not (space.has_point(local_to_level * faces[i]) and
					space.has_point(local_to_level * faces[i + 1]) and
					space.has_point(local_to_level * faces[i + 2])):
				keep.append(faces[i])
				keep.append(faces[i + 1])
				keep.append(faces[i + 2])
		var trimmed := c.shape.duplicate() as ConcavePolygonShape3D
		trimmed.set_faces(keep)
		c.shape = trimmed


func _world_box(id: String, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = id
	body.position = pos
	body.collision_mask = 0
	MinigameUtil.add_box_collider(body, size)
	env.add_child(body, true)


func _build_room() -> void:
	var board := Readable.new()
	board.name = "NoticeBoard"
	board.readable_id = "notice_board"
	board.prompt = "Đọc bảng tin"
	board.transform = _source("notice_board").transform
	MinigameUtil.add_box_collider(board, Vector3(1.35, 0.86, 0.045))
	interactables.add_child(board)

	var breaker := _usable("Breaker", "Bật cầu dao", Vector3(-1.27, 1.43, -17.63), Vector3(0.16, 0.32, 0.25))
	breaker.add_child(MinigameUtil.box(Vector3(0.09, 0.31, 0.23), Color(0.23, 0.23, 0.20)))
	breaker.add_child(MinigameUtil.box(Vector3(0.06, 0.10, 0.045), Color(0.42, 0.16, 0.09), Vector3(-0.055, 0.01, 0)))
	breaker.used.connect(func(_p: Node3D):
		GameState.set_flag("breaker_on", true)
		EventBus.lights_set.emit("dorm_lights", true)
		AudioDirector.play_sfx_3d("light_switch", breaker.global_position))
	_usable("Mirror", "Nhìn gương", _source("mirror").position + Vector3(0.035, 0, 0), Vector3(0.06, 0.54, 0.45))

	_room_switch = LightSwitch.new()
	_room_switch.name = "LightSwitch204"
	_room_switch.light_group = "room_lights"
	_room_switch.transform = _source("switch_room").transform
	_room_switch.position.x -= 0.055
	interactables.add_child(_room_switch)

	var photo := Readable.new()
	photo.name = "PhotoInBag"
	photo.readable_id = "old_photo"
	photo.prompt = "Xem ảnh cũ trong túi"
	photo.position = Vector3(-6.32, LOFT + 0.15, -27.32)
	MinigameUtil.add_box_collider(photo, Vector3(0.38, 0.29, 0.41))
	_model(photo, PROPS, "cardboard_box_open", Vector3(0, -0.15, 0))
	_model(photo, PROPS, "old_photo_frame", Vector3(0, 0.02, 0.05), -55)
	photo.used.connect(func(_p: Node3D):
		GameState.set_flag("seen_photo_room", true)
		GameState.set_flag("has_photo", true))
	interactables.add_child(photo)

	var up := _usable("LoftLadder", "Leo lên gác", Vector3(-4.51, F2 + 1.37, -26.85), Vector3(0.16, 0.89, 0.46))
	up.used.connect(func(p: Node3D): _climb_loft(p as Player, true))
	var down := _usable("LoftLadderDown", "Xuống gác", Vector3(-5.12, LOFT + 0.59, -26.84), Vector3(0.12, 0.78, 0.42))
	down.used.connect(func(p: Node3D): _climb_loft(p as Player, false))

	_hide("HideDesk", _source("hide_desk").position + Vector3(-0.55, 0, 0), Vector3(1.62, 1.18, 1.08))
	_hide("HideWardrobe", Vector3(-5.55, F2, -25.63), Vector3(0.83, 1.20, 0.83))
	_build_noodles()
	_build_routine()


func _build_noodles() -> void:
	var noodles := NOODLES.instantiate() as MinigameNoodles
	noodles.build_placeholder = false
	noodles.stove_model = load(PROPS + "gas_stove.glb")
	noodles.noodle_model = load(PROPS + "instant_noodle_pack.glb")
	noodles.pot_model = load(PROPS + "pot.glb")
	# Burner pivot in the real stove GLB is at its feet; MinigameNoodles expects
	# the burner top. Raise the anchor to the top, then sink just the model.
	var burner := _source("stove")
	noodles.position = burner.position
	noodles.rotation_degrees.y = 90.0
	noodles.get_node("Stove").position = Vector3(0, 0.095, 0.078)
	noodles.get_node("NoodlePack").position = Vector3(-0.48, 0.015, 0.14)
	noodles.get_node("TimerDisplay").position = Vector3(-0.48, 0.39, -0.11)
	_marker(noodles, "Knob", Vector3(0.115, 0.045, 0.235))
	# The original gas bottle stays where the environment artist placed it.
	_model(noodles, PROPS, "water_bottle", Vector3(0.34, -0.095, 0.068))
	interactables.add_child(noodles)
	var stove := noodles.get_node("Stove").get_child(0) as Node3D
	stove.position.y = -0.117
	var lid := noodles.find_child("pot_lid", true, false) as Node3D
	if lid:
		lid.position += Vector3(-0.17, -0.173, 0)


func _build_routine() -> void:
	var routine := ROUTINE.instantiate() as MinigameRoomRoutine
	routine.build_placeholder = false
	routine.door_path = NodePath("../../Doors/Door204")
	routine.light_group = "room_lights"
	_routine_switch = routine.get_node("LightSwitch") as MinigameLightSwitch
	_routine_switch.build_placeholder = false
	_routine_switch.position = _room_switch.position
	_routine_switch.direct_toggle = false
	var lock_part := routine.get_node("DoorLock") as MinigameDoorLock
	lock_part.build_placeholder = false
	lock_part.position = Vector3(-2.665, F2 + 1.01, -26.19)
	lock_part.rotation_degrees.y = -90.0
	var bed := routine.get_node("Bed") as MinigameSleep
	bed.build_placeholder = false
	bed.bed_model = load(PROPS + "bed_mattress.glb")
	bed.bed_size = Vector3(1.28, 0.22, 2.0)
	bed.position = Vector3(-6.52, LOFT + 0.14, -26.05)
	bed.rotation_degrees.y = 90.0
	interactables.add_child(routine)
	# Use exactly one physical plate for the switch; both chapter APIs share its state.
	_routine_switch.hide()
	(_routine_switch.get_node("SwitchButton") as MinigameButton).collision_layer = 0
	_room_switch.used.connect(func(_p: Node3D): _routine_switch.toggled.emit(_room_switch.is_on))


func _sync_room_switch(group: String, on: bool) -> void:
	if group != "room_lights":
		return
	_room_switch.is_on = on
	_routine_switch.lights_on = on
	if not on and _routine_switch.is_active():
		_routine_switch.complete()


func _climb_loft(p: Player, going_up: bool) -> void:
	if not is_instance_valid(p) or _climbing or not p.can_control():
		return
	if going_up == (p.global_position.y >= LOFT - 0.3):
		return
	_climbing = true
	GameState.lock_input("dorm_ladder")
	p.set_physics_process(false)
	# Clearance on the loft is 1.1 m; use the same capsule change as player input.
	p._set_crouch(true)
	p._crouch_toggled = going_up
	p.velocity = Vector3.ZERO
	var lip := Vector3(-4.79, LOFT + 0.02, -26.84)
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if going_up:
		tween.tween_property(p, "global_position", LOFT_BOTTOM, 0.23)
		tween.tween_property(p, "global_position", lip, 0.57)
		tween.tween_property(p, "global_position", LOFT_TOP, 0.24)
	else:
		tween.tween_property(p, "global_position", lip, 0.38)
		tween.tween_property(p, "global_position", LOFT_BOTTOM, 0.58)
	await tween.finished
	if is_instance_valid(p):
		p.reset_physics_interpolation()
		p.set_physics_process(true)
	GameState.unlock_input("dorm_ladder")
	_climbing = false


func _build_shrine() -> void:
	var incense_at := _source("incense_bowl").position
	var offering := _usable("Ritual_Incense", "Thắp nhang", incense_at + Vector3(0, 0.08, 0.06), Vector3(0.24, 0.24, 0.22))
	_model(offering, PROPS, "incense_bowl", Vector3(0, -0.21, 0.09), 14)
	var smoke_incense := _model(offering, PROPS, "incense_bundle_lit", Vector3(0, -0.11, 0.09), 14)
	smoke_incense.hide()
	offering.used.connect(func(_p: Node3D): smoke_incense.show())
	var photo_at := _source("photo_frame").position
	var photo := _usable("Ritual_Photo", "Đặt ảnh", photo_at + Vector3(0, 0.07, 0.165), Vector3(0.30, 0.31, 0.25))
	var frame := _model(photo, PROPS, "old_photo_frame", Vector3(-0.16, -0.21, 0.02), 8)
	frame.hide()
	photo.used.connect(func(_p: Node3D): frame.show())
	var lamp_base := _source("shrine_lamp").position + Vector3(0.08, -0.10, 0.105)
	_usable("Ritual_Oil", "Châm dầu", lamp_base + Vector3(0, 0.055, 0.061), Vector3(0.19, 0.11, 0.14))
	_usable("Ritual_Lamp", "Thắp đèn", lamp_base + Vector3(0, 0.19, 0.031), Vector3(0.16, 0.144, 0.13))
	var lamp_model := _model(env, PROPS, "oil_lamp", lamp_base)
	lamp_model.name = "ShrineLampModel"
	var flame := lamp_model.find_child("*flame_emit", true, false) as Node3D
	var lamp := OmniLight3D.new()
	lamp.name = "ShrineLamp"
	lamp.position = lamp_base + Vector3.UP * 0.23
	lamp.omni_range = 3.15
	lamp.light_energy = 1.7
	lamp.light_color = Color(1.0, 0.64, 0.29)
	lamp.visible = false
	add_child(lamp)
	if flame:
		flame.visible = false
		lamp.visibility_changed.connect(func(): flame.visible = lamp.visible)

	# Replace the version fused into the environment with the reusable pole GLB.
	env.find_child("the_streetlight", true, false).hide()
	env.find_child("the_streetlight_lamp_emit", true, false).hide()
	var street := Node3D.new()
	street.name = "TheStreetlight"
	street.position = _source("the_streetlight_base").position
	add_child(street)
	var pole := _model(street, ENV_MODELS, "streetlight", Vector3.ZERO, 145)
	pole.scale = Vector3(1, 0.85, 1)
	pole.rotation_degrees.z = 3
	for body in pole.find_children("*", "StaticBody3D", true, false):
		body.free() # the imported shrine already has the pole-base collider
	var head := LevelKit.marker(pole, "lamp")
	var glow := LevelKit.omni(street, head, Color(1.0, 0.61, 0.24), 3.2, 9.0, "streetlight", FlickerLight.Mode.SODIUM)
	glow.name = "StreetlightGlow"
	_street_driver = glow.get_child(0) as FlickerLight
	_link_emission(_street_driver, pole.find_child("*lamp_emit", true, false))
	# Stand in the near edge of the sodium pool, off the path to the ritual targets.
	_marker(markers, "tuan_final", Vector3(0.07, 0, -38.30), 180)


func _build_encounters() -> void:
	var mimic_door := MIMIC.instantiate() as Mimic
	mimic_door.name = "MimicDoor"
	mimic_door.entity_id = "mimic_door"
	mimic_door.mode = Mimic.Mode.DOOR
	mimic_door.impersonates = "hung"
	mimic_door.model_scene = load(CHARS + "mimic_hung.glb")
	mimic_door.door_path = NodePath("../../Doors/Door204")
	mimic_door.outside_marker = NodePath("../../Markers/mimic_door_out")
	mimic_door.inside_marker = NodePath("../../Markers/mimic_door_in")
	mimic_door.voice_lines.assign(["ch2_mimic_hung_01", "ch2_mimic_hung_02", "ch2_mimic_hung_03", "ch2_mimic_hung_04", "ch2_mimic_hung_05"])
	mimic_door.truth_message_id = "m_ch2_hung_02"
	mimic_door.lights_group = "room_lights"
	mimic_door.flicker_group = "room_lights"
	entities.add_child(mimic_door)
	var mimic_corridor := MIMIC.instantiate() as Mimic
	mimic_corridor.name = "MimicCorridor"
	mimic_corridor.entity_id = "mimic_corridor"
	mimic_corridor.mode = Mimic.Mode.CORRIDOR
	mimic_corridor.impersonates = "linh"
	mimic_corridor.model_scene = load(CHARS + "mimic_linh.glb")
	mimic_corridor.door_path = NodePath("../../Doors/Door204")
	mimic_corridor.outside_marker = NodePath("../../Markers/mimic_corridor")
	mimic_corridor.inside_marker = NodePath("../../Markers/mimic_room_safe")
	mimic_corridor.catch_distance = 0.54 # enough room to squeeze past on the railing side
	mimic_corridor.room_radius = 1.65
	entities.add_child(mimic_corridor)
	var tuan := GAZER.instantiate() as Gazer
	tuan.name = "GazerTuan"
	tuan.entity_id = "gazer_tuan"
	tuan.mode = Gazer.Mode.HUNT
	tuan.model_scene = load(CHARS + "gazer.glb")
	tuan.flicker_group = "streetlight"
	for i in range(1, 6):
		tuan.path_markers.append(NodePath("../../Markers/tuan_%d" % i))
	tuan.path_markers.append(NodePath("../../Markers/tuan_final"))
	entities.add_child(tuan)
	var hung := EntityBody.new()
	hung.name = "Hung"
	hung.visible = false
	hung.transform = get_marker("hung_ending").transform
	$NPCs.add_child(hung)
	hung.build(load(CHARS + "hung.glb"))
	hung.play_anim("idle")


func _build_presets() -> void:
	_preset("night", "night", "amb_dorm_night", 21, Color(0.60, 0.65, 0.78), 0.48)
	_preset("day", "overcast", "amb_room_day", 16, Color(0.84, 0.86, 0.91), 0.64, Color(0.93, 0.96, 1.0), 0.34)
	_preset("ch4_night", "dread", "amb_shrine", 3, Color(0.62, 0.53, 0.50), 0.36)
	_preset("dawn", "dawn", "", 5, Color(0.90, 0.78, 0.67), 0.64, Color(1.0, 0.79, 0.56), 0.6)
	# Shared fixtures preserve switch/flicker identity across presets and chapters.
	var fixtures := Node3D.new()
	fixtures.name = "Fixtures"
	presets.add_child(fixtures)
	for i in range(1, 4):
		var id := "corridor_bulb_%d" % i
		_fixture(fixtures, id, id + "_emit", "dorm_lights", Color(0.93, 0.96, 0.76), 1.52, 5.2, FlickerLight.Mode.FLUORESCENT)
	_fixture(fixtures, "light_hall", "hall_bulb_emit", "dorm_lights", Color(0.95, 0.89, 0.67), 1.72, 6.5, FlickerLight.Mode.FLUORESCENT)
	_fixture(fixtures, "lane_lamp_1", "lane_lamp_1_emit", "dorm_lights", Color(1.0, 0.73, 0.46), 1.2, 8.0, FlickerLight.Mode.SODIUM)
	_fixture(fixtures, "light_room", "room_bulb_emit", "room_lights", Color(1.0, 0.84, 0.61), 1.68, 4.45, FlickerLight.Mode.STEADY)
	_fixture(fixtures, "light_loft", "loft_bulb_emit", "room_lights", Color(1.0, 0.86, 0.76), 0.85, 2.36, FlickerLight.Mode.STEADY)
	_fixture(fixtures, "light_wc", "wc_bulb_emit", "room_lights", Color(0.78, 0.89, 0.91), 0.52, 1.95, FlickerLight.Mode.STEADY)


func apply_preset(id: String) -> void:
	var target := presets.get_node_or_null(id) as LightingPreset
	if target == null or _active_preset == id:
		return
	for child in presets.get_children():
		if child is LightingPreset and child != target:
			child.set_active(false)
	target.set_active(true)
	_active_preset = id
	var daylight := id in ["day", "dawn"]
	EventBus.lights_set.emit("dorm_lights", id == "night")
	EventBus.lights_set.emit("room_lights", id == "night" or id == "day")
	EventBus.lights_set.emit("streetlight", not daylight)
	_street_driver.set_base_energy(3.6 if id == "ch4_night" else 2.8)
	if id == "ch4_night":
		AudioDirector.play_ambience("drone_dread", "drone", -10.0)
	else:
		AudioDirector.stop_ambience("drone")
	if id == "dawn":
		AudioDirector.stop_ambience("base")


func _preset(id: String, fog: String, ambience: String, hour: int, tint: Color,
		energy: float, sun_color := Color.WHITE, sun_energy := 0.0) -> void:
	var p := LightingPreset.new()
	p.name = id
	p.visible = false
	p.fog_preset = fog
	p.ambience = ambience
	p.clock_hours = hour
	var world := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = tint
	e.ambient_light_energy = energy
	e.fog_enabled = false
	world.environment = e
	p.add_child(world)
	if sun_energy > 0:
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation_degrees = Vector3(-26 if id == "dawn" else -53, -35, 0)
		sun.light_color = sun_color
		sun.light_energy = sun_energy
		sun.shadow_enabled = id == "dawn"
		p.add_child(sun)
	presets.add_child(p)


func _fixture(parent: Node3D, marker_id: String, emitter: String, group: String, color: Color,
		energy: float, radius: float, mode: FlickerLight.Mode) -> void:
	var light := LevelKit.omni(parent, _source(marker_id), color, energy, radius, group, mode)
	light.name = marker_id
	var driver := light.get_child(0) as FlickerLight
	_link_emission(driver, env.find_child(emitter, true, false))


func _link_emission(driver: FlickerLight, mesh: Node) -> void:
	if mesh is GeometryInstance3D:
		driver.mesh = mesh
		driver.emissive_mesh = driver.get_path_to(mesh)


func _build_navigation() -> void:
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	var map_mesh := NavigationMesh.new()
	map_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	map_mesh.geometry_source_group_name = &"dorm_shrine_navigation"
	map_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	map_mesh.geometry_collision_mask = 1
	map_mesh.agent_height = 1.75
	map_mesh.agent_radius = 0.25
	map_mesh.agent_max_climb = 0.25
	map_mesh.agent_max_slope = 45.0
	region.navigation_mesh = map_mesh
	add_child(region)
	region.bake_navigation_mesh.call_deferred(false)


func _source(id: String) -> Node3D:
	return LevelKit.marker(env, id)


func _marker(parent: Node3D, id: String, at: Vector3, yaw := 0.0) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = id
	marker.position = at
	marker.rotation_degrees.y = yaw
	parent.add_child(marker)
	return marker


func _camera(id: String, pose: Transform3D) -> void:
	var camera := FixedCamera.new()
	camera.name = id
	camera.transform = pose
	camera.fov = 67.0
	camera.near = 0.035
	markers.add_child(camera)

func _looking_from(from: Vector3, to: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(to - from), from)


func _model(parent: Node, base: String, id: String, pos := Vector3.ZERO, yaw := 0.0) -> Node3D:
	var scene := load(base + id + ".glb") as PackedScene
	var p := scene.instantiate() as Node3D
	p.position = pos
	p.rotation_degrees.y = yaw
	parent.add_child(p)
	return p


func _usable(id: String, prompt: String, pos: Vector3, box: Vector3) -> Interactable:
	var obj := Interactable.new()
	obj.name = id
	obj.prompt = prompt
	obj.position = pos
	MinigameUtil.add_box_collider(obj, box)
	interactables.add_child(obj)
	return obj


func _hide(id: String, p: Vector3, size: Vector3) -> void:
	var spot := HideSpot.new()
	spot.name = id
	spot.position = p
	spot.size = size
	interactables.add_child(spot)


func _exit_tree() -> void:
	if _climbing:
		GameState.unlock_input("dorm_ladder")
	if _active_preset == "ch4_night":
		AudioDirector.stop_ambience("drone")
