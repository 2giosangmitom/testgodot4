extends LevelBase

const CROWD_MEMBER := preload("res://gameplay/entities/crowd/crowd_member.tscn")
const BROOM := preload("res://assets/models/props/broom.glb")
const STOOL := preload("res://assets/models/props/plastic_stool.glb")

@onready var env: Node3D = $Env
@onready var nav: NavigationRegion3D = $NavigationRegion3D
var _flickers: Array[FlickerLight] = []


func _ready() -> void:
	super._ready()
	_place_markers()
	_build_grocery()
	_build_interactables()
	_place_people()
	_build_lights()
	PSXApply.apply_to(self, {"glass_tint": Color(0.56, 0.65, 0.62, 0.18)})
	_tune_glass()
	apply_preset(default_preset)
	nav.bake_navigation_mesh.call_deferred(true)


func apply_preset(preset_id: String) -> void:
	if not $Presets.has_node(preset_id):
		return
	super.apply_preset(preset_id)
	if preset_id == "day":
		GameState.set_clock(16, 40)
	for flicker in _flickers:
		var active := (flicker.get_parent().get_parent() as LightingPreset).is_active()
		flicker.set_process(active)
		if flicker.mesh:
			flicker.mesh.set_instance_shader_parameter("emit_level", 1.0 if active else 0.12)


func _place_markers() -> void:
	for id in ["default", "classroom", "street"]:
		get_spawn(id).transform = _import_marker("spawn_" + id).transform
	var seat := Marker3D.new()
	seat.name = "MARKER_seat_nam"
	seat.transform = _import_marker("seat_nam").transform
	$Markers.add_child(seat)

	_camera("cam_courtyard", _import_marker("cam_courtyard_wide").transform, 70.0)
	var class_camera := _import_marker("cam_classroom").position + Vector3(-0.14, 0.03, -2.25)
	_camera("cam_classroom", Transform3D(
		Basis.looking_at(Vector3(0.55, 1.30, -24.5) - class_camera), class_camera), 71.0)
	_camera("cam_gate", _import_marker("cam_gate").transform, 67.0)
	_camera("cam_street", _import_marker("cam_street_long").transform, 68.0)
	var guard_camera := Vector3(-3.67, 1.72, -1.95)
	_camera("cam_guard_booth", Transform3D(
		Basis.looking_at(Vector3(-6.1, 1.24, -1.4) - guard_camera), guard_camera), 63.0)
	var bus := _import_marker("bus_stop").position
	var bus_camera := bus + Vector3(3.2, 1.72, 4.2)
	_camera("cam_bus_stop", Transform3D(
		Basis.looking_at(bus + Vector3(0, 1.02, 0) - bus_camera), bus_camera), 58.0)


func _camera(id: String, pose: Transform3D, fov_degrees: float) -> void:
	var cam := FixedCamera.new()
	cam.name = id
	cam.transform = pose
	cam.fov = fov_degrees
	cam.near = 0.05
	$Markers.add_child(cam)


func _import_marker(id: String) -> Node3D:
	return LevelKit.marker(env, id)


func _build_grocery() -> void:
	# The imported far-side shutters are closed. This shallow shop sits against them
	# with 1.35 m of sidewalk still clear in front; threshold and sidewalk share y=0.
	var shop := Node3D.new()
	shop.name = "GroceryInterior"
	env.add_child(shop)
	_panel(shop, "WestWall", Vector3(13.26, 1.37, 11.94), Vector3(0.12, 2.74, 2.1),
		"wall_green", Vector3(1, 0.8, 1))
	_panel(shop, "EastWall", Vector3(17.54, 1.37, 11.94), Vector3(0.12, 2.74, 2.1),
		"wall_green", Vector3(1, 0.8, 1))
	_panel(shop, "BackWall", Vector3(15.4, 1.37, 12.93), Vector3(4.28, 2.74, 0.12),
		"wall_white", Vector3(1.5, 0.8, 1))
	_panel(shop, "FrontWest", Vector3(14.005, 1.05, 10.95), Vector3(1.49, 2.1, 0.13),
		"shutter_green", Vector3(1, 1, 1))
	_panel(shop, "FrontEast", Vector3(16.75, 1.05, 10.95), Vector3(1.7, 2.1, 0.13),
		"shutter_green", Vector3(1, 1, 1))
	_panel(shop, "Lintel", Vector3(15.4, 2.42, 10.95), Vector3(4.4, 0.64, 0.13),
		"wall_green", Vector3(1.5, 1, 1))
	_panel(shop, "Ceiling", Vector3(15.4, 2.69, 11.94), Vector3(4.52, 0.10, 2.18),
		"concrete_dark", Vector3(2, 1, 1), false)
	_panel(shop, "ShopFloor", Vector3(15.4, -0.034, 11.94), Vector3(4.20, 0.08, 1.97),
		"tile_checker", Vector3(4, 2, 1), false)
	_panel(shop, "Awning", Vector3(15.4, 2.16, 10.70), Vector3(4.54, 0.10, 0.57),
		"shutter_green", Vector3(4, 1, 1), false)

	var signboard := MeshInstance3D.new()
	signboard.name = "grocery_sign"
	var sign_quad := QuadMesh.new()
	sign_quad.size = Vector2(3.82, 0.43)
	signboard.mesh = sign_quad
	signboard.material_override = _material("sign_taphoa", Vector3.ONE)
	signboard.position = Vector3(15.4, 2.45, 10.88)
	signboard.rotation.y = PI
	shop.add_child(signboard)

	var desk: PackedScene = preload("res://assets/models/props/small_desk.glb")
	_model(shop, desk, "Counter", Vector3(16.79, 0, 12.49))
	_box_collision(shop, "CounterCollision", Vector3(16.79, 0.36, 12.49), Vector3(0.8, 0.72, 0.5))
	_model(shop, desk, "Display", Vector3(13.68, 0, 12.46))
	_box_collision(shop, "DisplayCollision", Vector3(13.68, 0.36, 12.46), Vector3(0.8, 0.72, 0.5))
	_model(shop, preload("res://assets/models/props/cash_register.glb"), "Register", Vector3(17.0, 0.72, 12.59), PI)
	_model(shop, preload("res://assets/models/props/instant_noodle_pack.glb"), "Noodles", Vector3(13.52, 0.72, 12.46))
	_model(shop, preload("res://assets/models/props/can_tra_xanh.glb"), "Tea", Vector3(13.9, 0.72, 12.45))
	_model(shop, preload("res://assets/models/props/cardboard_box_closed.glb"), "StockBox", Vector3(13.65, 0, 11.64))
	_box_collision(shop, "StockBoxCollision", Vector3(13.65, 0.19, 11.64), Vector3(0.40, 0.38, 0.40))


func _build_interactables() -> void:
	var classroom: Door = $Doors/ClassroomA
	classroom.transform = _import_marker("door_classA").transform
	for door in $Doors.get_children():
		# Door owns the moving collider; drop the extra imported collision on each leaf.
		for collider in door.get_node("Leaf").find_children("*", "StaticBody3D", true, false):
			collider.free()
	$Interactables/MissingPoster.used.connect(func(_player: Node3D): GameState.set_flag("has_name_tag", true))
	# The matching poster art is baked onto the courtyard notice board.
	_box_collision(env, "GuardDesk", Vector3(-6.25, 0.375, -0.725), Vector3(1.3, 0.75, 0.45))
	var oil := $Interactables/GuardOilPickup/OilBottle.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var bottle_material := oil.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
	bottle_material.albedo_color = Color(1.0, 0.82, 0.45)
	oil.set_surface_override_material(0, bottle_material)


func _place_people() -> void:
	_npc($NPCs/Thay_Khai, "thay_khai")
	_npc($NPCs/Linh, "linh", "sit")
	_npc($NPCs/Hung, "hung")
	$NPCs/BacTu.transform = _import_marker("guard_booth").transform
	_npc($NPCs/BacTu, "bac_tu", "sit")
	var students: Node3D = $NPCs/Students
	_npc(students, "student_f1", "sit", Vector3(-0.47, 0.45, -23.47), 90.0)
	_npc(students, "student_m1", "sit", Vector3(0.93, 0.45, -26.15), 90.0)
	_npc(students, "student_m2", "sit", Vector3(2.33, 0.45, -23.41), 90.0)

	var bus: CrowdGroup = $Entities/CrowdBusStop
	_member_at_marker(bus, "passerby_m1", "wait", "crowd_1")
	_member_at_marker(bus, "passerby_f1", "wait", "crowd_2")
	_member_at_marker(bus, "passerby_m2", "wait", "crowd_3")
	_member(bus, "student_f2", "wait", Vector3(14.0, 0, 2.7), 160.0)

	var sweepers: CrowdGroup = $Entities/CrowdSweepers
	_broom(_member_at_marker(sweepers, "passerby_f1", "sweep", "crowd_5"))
	_broom(_member(sweepers, "ba_cu", "sweep", Vector3(5.45, -0.15, 7.5), -125.0))

	var tea: CrowdGroup = $Entities/CrowdTeaShop
	_member(tea, "passerby_m2", "sit", Vector3(18.0, 0, 11.8), -18.0)
	_member(tea, "passerby_m1", "sit", Vector3(18.5, 0, 12.2), 3.0)
	_member(tea, "passerby_f1", "sit", Vector3(19.1, 0, 11.7), 29.0)

	var yard: CrowdGroup = $Entities/CrowdSchoolyard
	for post in [Vector3(-8.75, 0, -15.85), Vector3(-6.34, 0, -15.9), Vector3(-5.68, 0, -16.16)]:
		var stool := _model(env, STOOL, "YardStool", post)
		stool.scale.y = 1.65
	_member(yard, "student_f1", "sit", Vector3(-8.75, 0, -15.85), 143.0)
	_member(yard, "student_m1", "sit", Vector3(-6.34, 0, -15.9), 207.0)
	_member(yard, "student_f2", "sit", Vector3(-5.68, 0, -16.16), 212.0)
	_member(yard, "student_m2", "wait", Vector3(-6.62, 0, -14.05), -60.0)


func _npc(parent: Node3D, id: String, anim := "idle", at := Vector3.ZERO, yaw := 0.0) -> void:
	# Imported characters face +Z; level markers and entity turns use -Z forward.
	var model := _model(parent, EntityBase.find_char_model(id), id, at, deg_to_rad(yaw) + PI)
	var player := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	if anim == "sit":
		player.play(anim)
		player.seek(0.43, true)
		player.pause()
	else:
		player.get_animation(anim).loop_mode = Animation.LOOP_LINEAR
		player.play(anim)


func _member_at_marker(group: CrowdGroup, id: String, pose: String, marker: String) -> CrowdMember:
	var post := _import_marker(marker)
	return _member(group, id, pose, post.position, post.rotation_degrees.y)


func _member(group: CrowdGroup, id: String, pose: String, at: Vector3, yaw: float) -> CrowdMember:
	var member := CROWD_MEMBER.instantiate() as CrowdMember
	member.name = "Member%d" % (group.get_child_count() + 1)
	member.position = at
	member.rotation_degrees.y = yaw
	member.pose = pose
	member.pose_time = 0.18 + group.get_child_count() * 0.13
	member.model_scene = EntityBase.find_char_model(id)
	group.add_child(member)
	member.body.model.rotation.y = PI
	return member


func _broom(member: CrowdMember) -> void:
	var hand := BoneAttachment3D.new()
	hand.bone_name = "hand_R"
	member.body.skeleton.add_child(hand)
	var broom := _model(hand, BROOM, "Broom", Vector3(0, -0.68, 0.03))
	broom.rotation_degrees.x = -18.0


func _build_lights() -> void:
	var day: LightingPreset = $Presets/day
	var night: LightingPreset = $Presets/night_ch3
	for i in range(1, 5):
		_fixture(day, "ClassroomTube%d" % i, "light_class_%d" % i, "class_tube_%d_emit" % i,
			Color(0.86, 0.94, 1), 1.24, 5.8, FlickerLight.Mode.FLUORESCENT)
		_fixture(night, "Sodium%d" % i, "streetlight_%d" % i, "streetlight_%d_lamp_emit" % i,
			Color(1, 0.63, 0.24), 2.85, 16.0, FlickerLight.Mode.SODIUM)
	for i in range(1, 4):
		_fixture(night, "CorridorTube%d" % i, "light_corridor_%d" % i, "corridor_tube_%d_emit" % i,
			Color(0.79, 0.91, 1), 0.7, 5.7, FlickerLight.Mode.FLUORESCENT)
	for i in range(1, 3):
		_fixture(night, "CourtyardLamp%d" % i, "light_courtyard_%d" % i, "courtyard_lamp_%d_emit" % i,
			Color(0.95, 0.82, 0.57), 0.84, 7.5, FlickerLight.Mode.STEADY)
	var guard := _fixture(night, "GuardBooth", "light_booth", "booth_bulb_emit",
		Color(1, 0.86, 0.65), 1.45, 4.0, FlickerLight.Mode.STEADY)
	guard.shadow_enabled = true

	var grocery := OmniLight3D.new()
	grocery.name = "GroceryLight"
	grocery.position = Vector3(15.6, 2.40, 12.08)
	grocery.light_color = Color(0.93, 0.96, 0.84)
	grocery.light_energy = 0.95
	grocery.omni_range = 3.15
	grocery.visible = false
	night.add_child(grocery)


func _fixture(preset: LightingPreset, light_name: String, marker: String, emitter: String,
		color: Color, energy: float, radius: float, mode: FlickerLight.Mode) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = light_name
	light.position = _import_marker(marker).position
	light.visible = preset.visible
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.35
	preset.add_child(light)
	var flicker := FlickerLight.new()
	flicker.name = "FlickerLight"
	flicker.mode = mode
	flicker.groups = ["school_streetlights"] if mode == FlickerLight.Mode.SODIUM else ["school_lights"]
	flicker.play_sound = mode == FlickerLight.Mode.FLUORESCENT
	var glowing_mesh := env.find_child(emitter, true, false)
	flicker.emissive_mesh = NodePath("../" + String(light.get_path_to(glowing_mesh)))
	light.add_child(flicker)
	_flickers.append(flicker)
	return light


func _tune_glass() -> void:
	# Keep the bus shelter, booth windows and closed shop door readable in the dark.
	for instance in find_children("*glass*", "MeshInstance3D", true, false):
		for i in instance.mesh.get_surface_count():
			var source := instance.get_surface_override_material(i) as ShaderMaterial
			if not source or source.shader != PSXMaterialFactory.SHADER_GLASS:
				continue
			var glass := source.duplicate() as ShaderMaterial
			glass.set_shader_parameter("reflection_strength", 0.07)
			glass.set_shader_parameter("streak_strength", 0.035)
			glass.set_shader_parameter("texture_opacity", 0.1)
			instance.set_surface_override_material(i, glass)


func _model(parent: Node, scene: PackedScene, id: String, at: Vector3, yaw := 0.0) -> Node3D:
	var model := scene.instantiate() as Node3D
	model.name = id
	model.position = at
	model.rotation.y = yaw
	parent.add_child(model, true)
	return model


func _material(texture: String, uv_scale: Vector3) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/env/%s.png" % texture)
	mat.uv1_scale = uv_scale
	return mat


func _panel(parent: Node3D, id: String, at: Vector3, size: Vector3, texture: String,
		uv_scale: Vector3, solid := true) -> void:
	var visual := MeshInstance3D.new()
	visual.name = id
	visual.position = at
	var box := BoxMesh.new()
	box.size = size
	visual.mesh = box
	visual.material_override = _material(texture, uv_scale)
	parent.add_child(visual)
	if solid:
		_box_collision(parent, id + "Collision", at, size)


func _box_collision(parent: Node3D, id: String, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = id
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
