extends LevelBase
## Glue between the level-coordinate environment models and the chapter-facing scene.

const PRODUCT_MODELS := [
	["Nước cam", "nuoc_cam", 11000, Vector3(0.066, 0.122, 0.066), Color("ed892b"), preload("res://assets/models/props/can_cam.glb")],
	["Mì gói", "mi_goi", 4000, Vector3(0.13, 0.17, 0.036), Color("dbc24a"), preload("res://assets/models/props/instant_noodle_pack.glb")],
	["Trà xanh", "tra_xanh", 12000, Vector3(0.066, 0.122, 0.066), Color("69ab37"), preload("res://assets/models/props/can_tra_xanh.glb")],
	["Cà phê", "ca_phe", 14000, Vector3(0.066, 0.122, 0.066), Color("744039"), preload("res://assets/models/props/can_cafe.glb")],
	["Nước suối", "nuoc_suoi", 5000, Vector3(0.064, 0.210, 0.064), Color("7ab7d5"), preload("res://assets/models/props/water_bottle.glb")],
]

const IMPORTED_MARKERS := {
	"Spawns/default": "spawn_default",
	"Spawns/door": "spawn_door",
	"Spawns/alley_start": "spawn_alley_start",
	"Markers/cam_store_wide": "cam_store_wide",
	"Markers/cam_outside_glass": "cam_outside_glass",
	"Markers/cam_counter": "cam_counter_pov",
	"Markers/cam_alley": "cam_alley",
	"Markers/cam_alley_corner": "cam_alley_corner",
	"Markers/cam_alley_exit": "cam_alley_exit",
	"Markers/alley_exit": "alley_exit",
	"Interactables/AlleyAltar": "alley_altar",
	"Triggers/HideCounter": "hide_counter",
}

var _fixture_meshes: Array[GeometryInstance3D] = []
var _navigation_map := RID()
var _navigation_cells := Vector2.ZERO
@onready var _env: Node3D = $Env
@onready var _presets: Node3D = $Presets
@onready var _checkout: MinigameCheckout = $Interactables/Checkout

func _enter_tree() -> void:
	# Minigame children consume their catalogues in their own ready/start callbacks.
	var products: Array[MinigameProduct] = []
	for spec in PRODUCT_MODELS:
		var p := MinigameProduct.make(spec[0], spec[1], spec[2], spec[3], spec[4], 0, "", "-Z")
		# Real product meshes are grounded, while MinigameProduct expects centered origins.
		var holder := Node3D.new()
		var model := (spec[5] as PackedScene).instantiate() as Node3D
		model.position.y = -p.size.y * 0.5
		holder.add_child(model)
		model.owner = holder
		p.model = PackedScene.new()
		p.model.pack(holder)
		holder.free()
		products.append(p)
	$Interactables/Checkout.products = products
	$Interactables/ShelfStock.products.assign(products.slice(0, 2))

func _ready() -> void:
	super._ready()
	for path in IMPORTED_MARKERS:
		_place_at_marker(get_node(path), IMPORTED_MARKERS[path])
	for i in range(1, 7):
		_place_at_marker(get_marker("gazer_%d" % i), "gazer_%d" % i)
	$Triggers/trig_alley_end.global_position = get_marker("alley_exit").global_position
	# The GLB's shelf marker orientations point into the shelf; the game's price
	# tags and aiming targets need their local +Z pointing out into the aisle.
	for marker in LevelKit.markers(_env, "slot_2_"):
		marker.rotate_y(PI)
	_place_npcs()
	_wire_readables()
	_split_store_glass_collision()
	_refit_alley_bike_collision()
	# Door already creates a solid, interactable moving collider. The GLB collision is
	# redundant, and both panes and door must be see-through for Gazer observation.
	for door: Door in $Doors.get_children():
		for body: StaticBody3D in door.get_node("Leaf").find_children("*", "StaticBody3D", true, false):
			body.collision_layer = 0
	_checkout.get_anchor("ScanPoint").get_child(0).set_meta("psx_skip", true)
	_checkout.started.connect(func():
		PSXApply.apply_to(_checkout.get_node("Items"))
		if _checkout._customer:
			_play_idle(_checkout._customer)
			PSXApply.apply_to(_checkout._customer)
	)
	_make_emissives_double_sided()
	PSXApply.apply_to(self)
	_tune_glazing()
	_make_lighting()
	apply_preset(default_preset)
	# Use a fine grid for the narrow shop apertures and the parked scooters.
	_navigation_map = get_world_3d().navigation_map
	_navigation_cells = Vector2(NavigationServer3D.map_get_cell_size(_navigation_map),
		NavigationServer3D.map_get_cell_height(_navigation_map))
	var mesh: NavigationMesh = $NavigationRegion3D.navigation_mesh
	NavigationServer3D.map_set_cell_size(_navigation_map, mesh.cell_size)
	NavigationServer3D.map_set_cell_height(_navigation_map, mesh.cell_height)
	$NavigationRegion3D.bake_navigation_mesh.call_deferred()

func _exit_tree() -> void:
	if _navigation_map.is_valid():
		NavigationServer3D.map_set_cell_size(_navigation_map, _navigation_cells.x)
		NavigationServer3D.map_set_cell_height(_navigation_map, _navigation_cells.y)

func _place_at_marker(node: Node3D, id: String) -> void:
	var imported := LevelKit.marker(_env, id)
	if imported:
		node.global_transform = imported.global_transform.orthonormalized()

func _place_npcs() -> void:
	var spots := {"Hanh": "npc_counter", "Customer1": "npc_counter",
		"Customer2": "npc_door", "OldLady": "npc_counter", "Linh": "npc_door"}
	for npc: Node3D in $NPCs.get_children():
		npc.global_transform = get_marker(spots[npc.name]).global_transform
		_play_idle(npc)

func _play_idle(npc: Node3D) -> void:
	var animation := npc.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation and animation.has_animation("idle"):
		animation.play("idle")

func _wire_readables() -> void:
	var rules: Readable = $Interactables/RulesNote
	var drawer: Interactable = $Interactables/Drawer
	var card: Readable = $Interactables/Drawer/NameTagStore
	rules.used.connect(func(_reader: Node3D): GameState.set_flag("read_rules", true))
	drawer.used.connect(func(reader: Node3D):
		GameState.set_flag("found_name_tag_store", true)
		card.enabled = true
		card.interact(reader)
		card.enabled = false
	)

func _split_store_glass_collision() -> void:
	# The importer merges the panes with the opaque walls in one concave shape. Split
	# out just the two panes, rather than make every store wall transparent to entities.
	var walls := _env.get_node_or_null("Store/store_walls") as StaticBody3D
	if not walls:
		return
	var wall_shape := walls.get_child(0) as CollisionShape3D
	var source := wall_shape.shape as ConcavePolygonShape3D
	var faces := source.get_faces()
	var opaque := PackedVector3Array()
	var glazing := PackedVector3Array()
	for i in range(0, faces.size(), 3):
		var is_glass := true
		for j in range(i, i + 3):
			var p := wall_shape.transform * faces[j]
			if absf(p.z) > 0.061 or p.y > 2.801 or p.x < -5.001 or p.x > 5.001 \
					or (p.x > 3.051 and p.x < 3.949):
				is_glass = false
				break
		# The remaining front-wall strip is the door's overhead transom.
		if is_glass and faces[i].x >= 3.049 and faces[i + 1].x >= 3.049 and faces[i + 2].x >= 3.049 \
				and faces[i].x <= 3.951 and faces[i + 1].x <= 3.951 and faces[i + 2].x <= 3.951:
			is_glass = false
		for j in range(i, i + 3):
			if is_glass:
				glazing.append(faces[j])
			else:
				opaque.append(faces[j])
	if glazing.is_empty():
		return
	var wall_collision := ConcavePolygonShape3D.new()
	wall_collision.set_faces(opaque)
	wall_shape.shape = wall_collision
	var pane_collision := ConcavePolygonShape3D.new()
	pane_collision.set_faces(glazing)
	var pane := StaticBody3D.new()
	pane.name = "StorefrontGlass"
	pane.add_to_group("see_through")
	var shape_node := CollisionShape3D.new()
	shape_node.transform = wall_shape.transform
	shape_node.shape = pane_collision
	pane.add_child(shape_node)
	walls.add_child(pane)

func _refit_alley_bike_collision() -> void:
	# The broad imported box on the scooter opposite the altar constricts the
	# lane for the full length of the scooter. Fit it to the narrower body.
	var shape := _env.get_node("Alley/alley_props").get_child(0) as CollisionShape3D
	var faces := (shape.shape as ConcavePolygonShape3D).get_faces()
	var bounds := AABB(Vector3(-8.0, -0.01, -28.85), Vector3(2.0, 1.03, 0.79))
	for i in range(0, faces.size(), 3):
		if not bounds.has_point(faces[i]) or not bounds.has_point(faces[i + 1]) or not bounds.has_point(faces[i + 2]):
			continue
		for j in range(i, i + 3):
			faces[j].z = lerpf(-28.48, faces[j].z, 0.70)
	var fitted := ConcavePolygonShape3D.new()
	fitted.set_faces(faces)
	shape.shape = fitted

func _make_emissives_double_sided() -> void:
	for mesh: MeshInstance3D in _env.find_children("*_emit", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(i) as BaseMaterial3D
			if original:
				var material := original.duplicate() as BaseMaterial3D
				material.cull_mode = BaseMaterial3D.CULL_DISABLED
				mesh.set_surface_override_material(i, material)

func _tune_glazing() -> void:
	# The GLBs carry opacity in their texture, while PSX glass uses a separate
	# tint alpha. Leaving the imported white base-color alpha would hide the street.
	var store_glass := _env.get_node("Store/store_front_glass") as MeshInstance3D
	var fridge_glass := _env.get_node("Store/fridge_glass") as MeshInstance3D
	var shop_door_glass := $Doors/ShopDoor/Leaf.find_child("door_glass", true, false) as MeshInstance3D
	_set_glass_tint(store_glass, Color(0.56, 0.67, 0.63, 0.10))
	_set_glass_tint(fridge_glass, Color(0.62, 0.78, 0.78, 0.16))
	_set_glass_tint(shop_door_glass, Color(0.56, 0.67, 0.63, 0.10))

func _set_glass_tint(mesh: MeshInstance3D, tint: Color) -> void:
	if not mesh:
		return
	for i in mesh.mesh.get_surface_count():
		var original := mesh.get_surface_override_material(i) as ShaderMaterial
		if original:
			var material := original.duplicate() as ShaderMaterial
			material.set_shader_parameter("tint", tint)
			material.set_shader_parameter("texture_opacity", 0.13)
			mesh.set_surface_override_material(i, material)

func _make_lighting() -> void:
	var fluorescent := FlickerLight.Mode.FLUORESCENT
	var sodium := FlickerLight.Mode.SODIUM
	var dying := FlickerLight.Mode.DYING
	for preset: LightingPreset in _presets.get_children():
		var world := WorldEnvironment.new()
		var environment := Environment.new()
		environment.background_mode = Environment.BG_CLEAR_COLOR
		environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_sky_contribution = 0.0
		environment.ambient_light_color = Color("818d9b")
		environment.ambient_light_energy = 0.25
		match preset.name:
			&"night_store":
				environment.ambient_light_energy = 0.34
			&"dusk_store":
				environment.ambient_light_color = Color("c5aca5")
				environment.ambient_light_energy = 0.56
			&"alley_predawn":
				environment.ambient_light_energy = 0.20
			&"ch4_night":
				environment.ambient_light_color = Color("746268")
				environment.ambient_light_energy = 0.12
		world.environment = environment
		preset.add_child(world)
		match preset.name:
			&"night_store", &"dusk_store":
				for i in range(1, 7):
					_light(preset, "light_tube_%d" % i, "tube_%d_emit" % i,
						Color("d0f0e5"), 1.38 if preset.name == &"night_store" else 0.64, 5.0,
						"store_lights", fluorescent)
				for i in range(1, 3):
					_light(preset, "streetlight_%d" % i, "streetlight_%d_lamp_emit" % i,
						Color("ffb76d"), 1.0, 10.0, "", sodium)
				_light(preset, "light_storeroom", "storeroom_bulb_emit", Color("ffd2a1"), 0.9, 4.6, "", fluorescent)
				if preset.name == &"night_store":
					var scan := _checkout.get_anchor("ScanPoint")
					var task := LevelKit.omni(preset, scan, Color("d0f0e5"), 0.48, 3.15,
						"store_lights", FlickerLight.Mode.STEADY)
					task.position.y += 1.2
				# The dusk chapter also walks the alley without a scene reload.
				if preset.name == &"dusk_store":
					for i in [1, 3, 5]:
						_alley_light(preset, i, 0.43, sodium)
			&"alley_predawn", &"ch4_night":
				var dark := preset.name == &"ch4_night"
				for i in range(1, 6):
					_alley_light(preset, i, 0.46 if dark else 0.95, dying if dark else sodium)
				_light(preset, "alley_far_light", "alley_far_streetlight_lamp_emit",
					Color("ff9c44"), 0.75 if dark else 1.76, 13.0, "alley_lights", dying if dark else sodium)
				_light(preset, "light_storeroom", "storeroom_bulb_emit", Color("ffb963"),
					0.24 if dark else 0.46, 4.0, "", dying if dark else fluorescent)
				if dark:
					_light(preset, "light_tube_4", "tube_4_emit", Color("879e96"), 0.17, 5.0, "store_lights", dying)

func _alley_light(preset: LightingPreset, index: int, energy: float, mode: FlickerLight.Mode) -> void:
	_light(preset, "alley_lamp_%d" % index, "alley_lamp_%d_emit" % index,
		Color("ffcf95"), energy, 6.0, "alley_lights", mode)

func _light(preset: LightingPreset, marker_id: String, mesh_id: String, color: Color,
		energy: float, reach: float, group: String, mode: FlickerLight.Mode) -> void:
	var marker := LevelKit.marker(_env, marker_id)
	if marker == null:
		return
	var light := LevelKit.omni(preset, marker, color, energy, reach, group)
	light.name = marker_id
	var flicker := FlickerLight.new()
	flicker.mode = mode
	flicker.groups = PackedStringArray([group]) if group != "" else PackedStringArray()
	flicker.play_sound = false
	var mesh := _env.find_child(mesh_id, true, false) as GeometryInstance3D
	if mesh:
		flicker.emissive_mesh = light.get_path_to(mesh)
		# FlickerLight resolves paths from itself, one hop below the light.
		flicker.emissive_mesh = NodePath("../" + String(flicker.emissive_mesh))
		if not _fixture_meshes.has(mesh):
			_fixture_meshes.append(mesh)
	light.add_child(flicker)

func apply_preset(preset_id: String) -> void:
	if not _presets.has_node(preset_id):
		return
	# Turn off every previous WorldEnvironment before enabling the new one.
	for p: LightingPreset in _presets.get_children():
		p.set_active(false)
		p.process_mode = Node.PROCESS_MODE_DISABLED
		for driver: FlickerLight in p.find_children("*", "Node", true, false).filter(func(n): return n is FlickerLight):
			driver.play_sound = false
	for mesh in _fixture_meshes:
		mesh.set_instance_shader_parameter("emit_level", 0.0)
	var active := _presets.get_node(preset_id) as LightingPreset
	active.process_mode = Node.PROCESS_MODE_INHERIT
	# Only one tube plays the shared electrical buzz; all six still respond visually.
	var audible: Node = active.get_node_or_null("light_tube_4")
	if audible:
		(audible.get_child(0) as FlickerLight).play_sound = true
	active.set_active(true)
