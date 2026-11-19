extends Node3D
## Entity sandbox: a dark street, a store with a glass front, a small room with a door,
## a bus stop. Uses the stand-in player.
##
## Run:   godot --path . res://gameplay/entities/test/test_entities.tscn
## Shot:  godot --path . res://gameplay/entities/test/test_entities.tscn -- --shot=/abs/out.png [--view=store|crowd|mimic|caught|hunt]
##
## Keys: 1 glass Gazer on/off · 2 hunting Gazer on/off · 3 teleport into the room + restart Mimic
##       4 crowd on/off · L flicker store lights · K test caught sequence · R "read" the truth message
##       Y / N answer / stay silent when asked · F flashlight · Shift sprint (noise)

var shot_path := ""
var view := "store"
var hud_sub: Label
var hud_choice: Label
var hud_state: Label
var static_rect: ColorRect
var fade_rect: ColorRect
var _states := {}
var _choice_open := false
var _store_lights: Array[OmniLight3D] = []

@onready var player: CharacterBody3D = $StandInPlayer
@onready var director: EntityDirector = $EntityDirector
@onready var gazer_glass: Gazer = $Entities/GazerGlass
@onready var gazer_hunt: Gazer = $Entities/GazerHunt
@onready var mimic: Mimic = $Entities/Mimic
@onready var crowd: CrowdGroup = $Entities/BusStopCrowd

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--view="):
			view = a.substr(7)
	_build_world()
	_build_hud()
	EventBus.subtitle.connect(func(sp, tx, _d): hud_sub.text = "%s: %s" % [sp, tx] if sp != "" else tx)
	EventBus.subtitle_clear.connect(func(): hud_sub.text = "")
	EventBus.choice_requested.connect(_on_choice_requested)
	EventBus.choice_made.connect(func(_i): _choice_open = false; hud_choice.text = "")
	EventBus.static_amount.connect(func(v): static_rect.material.set_shader_parameter("amount", v))
	EventBus.fade_request.connect(_on_fade)
	EventBus.lights_flicker.connect(_on_flicker)
	EventBus.entity_state_changed.connect(_on_entity_state)
	EventBus.player_caught.connect(func(id, c): print("[test] player_caught ", id, " ", c))
	gazer_glass.stared_out.connect(func(): print("[test] gazer stared out"))
	mimic.survived.connect(func(): print("[test] mimic: survived"))
	await get_tree().process_frame
	await get_tree().process_frame
	_setup_view()
	if shot_path != "":
		_take_shot()

func _setup_view() -> void:
	match view:
		"crowd":
			director.activate_only(["crowd_bus_stop"])
			player.teleport(Transform3D(Basis(), Vector3(9.5, 0, 6.6)))
			player.look_at_point(Vector3(12, 1.2, 10.6), 0.0)
		"mimic":
			director.activate_only(["mimic_hung"])
			mimic.manual_tick = true     # keep it standing at the door for the picture
			player.teleport(Transform3D(Basis(), Vector3(-4.6, 0, 6.2)))
			player.look_at_point(Vector3(-7.4, 1.0, 4.1), 0.0)
		"hunt":
			director.activate_only(["gazer_hunt"])
			gazer_hunt.manual_tick = true
			gazer_hunt.index = 3
			gazer_hunt._snap_to_marker(3)
			player.teleport(Transform3D(Basis(), Vector3(-1, 0, 1.5)))
			player.look_at_point(Vector3(-6, 1.8, 2), 0.0)
		"caught":
			director.activate_only(["gazer_glass"])
			gazer_glass.manual_tick = true
			gazer_glass.index = 2
			gazer_glass._snap_to_marker(2)
			player.look_at_point(Vector3(0.3, 1.7, 4.2), 0.0)
		_:
			director.activate_only(["gazer_glass", "crowd_bus_stop", "mimic_hung"])
			if shot_path != "":
				gazer_glass.manual_tick = true
				gazer_glass.index = 2
				gazer_glass._snap_to_marker(2)
			player.look_at_point(Vector3(4.0, 1.3, 8.0), 0.0)

func _take_shot() -> void:
	var frames := 40
	if view == "caught":
		for i in 10:
			await get_tree().process_frame
		gazer_glass.passive_override = 0
		gazer_glass.catch_player("test", gazer_glass)
		await get_tree().create_timer(0.75).timeout
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(shot_path)
	print("[test] shot saved: ", shot_path, " err=", err)
	get_tree().quit()

# ---------------------------------------------------------------- input

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	if _choice_open:
		if e.keycode == KEY_Y:
			EventBus.choice_made.emit(0)
		elif e.keycode == KEY_N:
			EventBus.choice_made.emit(1)
		return
	match e.keycode:
		KEY_1:
			_toggle(gazer_glass)
		KEY_2:
			_toggle(gazer_hunt)
		KEY_3:
			mimic.deactivate()
			$RoomDoor.set_open(false)
			player.teleport($Markers/RoomSpawn.global_transform)
			mimic.activate()
		KEY_4:
			_toggle(crowd)
		KEY_L:
			EventBus.lights_flicker.emit("store_lights", 1.5)
		KEY_K:
			var e2: EntityBase = gazer_glass if gazer_glass.is_active() else crowd
			e2.catch_player("test_key", e2 if e2 is Gazer else crowd.get_members()[0])
		KEY_R:
			GameState.set_flag("read_m_test_01", true)
			EventBus.toast.emit("Đã đọc tin nhắn")

func _toggle(e: EntityBase) -> void:
	if e.is_active():
		e.deactivate()
	else:
		e.activate()

func _on_choice_requested(prompt: String, options: PackedStringArray) -> void:
	_choice_open = true
	hud_choice.text = "%s   [Y] %s   [N] %s" % [prompt, options[0], options[1] if options.size() > 1 else ""]

func _on_entity_state(id: String, s: String) -> void:
	_states[id] = s
	var t := ""
	for k in _states:
		t += "%s: %s\n" % [k, _states[k]]
	hud_state.text = t
	if s == "caught_done":
		await get_tree().create_timer(0.6).timeout
		_reset_after_caught()

func _reset_after_caught() -> void:
	RenderSettings.set_static(0.0)
	for e in [gazer_glass, gazer_hunt, mimic, crowd]:
		var was: bool = e.is_active()
		e.deactivate()
		if was and shot_path == "":
			e.activate()
	player.teleport(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -3)))
	EventBus.fade_request.emit(false, 0.6)

func _on_fade(to_black: bool, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0 if to_black else 0.0, dur)
	tw.tween_callback(func(): EventBus.fade_done.emit())

func _on_flicker(group_name: String, dur: float) -> void:
	if group_name != "store_lights" and group_name != "flicker_lights":
		return
	AudioDirector.play_sfx("fluorescent_flicker")
	var t := 0.0
	while t < dur:
		var off := randf() < 0.5
		for l in _store_lights:
			l.visible = not off
		var step := randf_range(0.04, 0.16)
		await get_tree().create_timer(step).timeout
		t += step
	for l in _store_lights:
		l.visible = true

# ---------------------------------------------------------------- world

func _mat(c: Color, unshaded := false, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, alpha)
	m.roughness = 1.0
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

func _box(size: Vector3, pos: Vector3, col: Color, collide := true, parent: Node = self, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat if mat else _mat(col)
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		sb.add_child(cs)
		mi.add_child(sb)
	return mi

func _light(pos: Vector3, col: Color, energy: float, rng: float, shadow := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadow
	add_child(l)
	return l

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.03, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.16, 0.17, 0.2)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var asphalt := Color(0.13, 0.13, 0.14)
	var concrete := Color(0.3, 0.29, 0.27)
	var wallc := Color(0.42, 0.42, 0.36)
	# ground: near sidewalk, road, far sidewalk
	_box(Vector3(70, 0.2, 3), Vector3(0, -0.1, 1.5), concrete)
	_box(Vector3(70, 0.2, 6), Vector3(0, -0.12, 6), asphalt)
	_box(Vector3(70, 0.2, 3.5), Vector3(0, -0.1, 10.75), concrete)
	for i in 14:
		_box(Vector3(1.6, 0.01, 0.12), Vector3(-30 + i * 5, 0.0, 6), Color(0.7, 0.68, 0.5), false)
	# shuttered houses on the far side
	for i in 8:
		var x := -28 + i * 8
		_box(Vector3(7.6, 6, 0.4), Vector3(x, 3, 12.7), wallc.darkened(0.2 + 0.1 * (i % 3)))
		_box(Vector3(3.2, 2.4, 0.06), Vector3(x - 1, 1.2, 12.47), Color(0.35, 0.36, 0.38), false)
	# store: floor, walls, ceiling, glass front with a door gap at x 3.05..3.95
	_box(Vector3(10, 0.2, 8), Vector3(0, -0.1, -4), Color(0.55, 0.56, 0.52))
	_box(Vector3(0.2, 3, 8), Vector3(-5, 1.5, -4), wallc)
	_box(Vector3(0.2, 3, 8), Vector3(5, 1.5, -4), wallc)
	_box(Vector3(10, 3, 0.2), Vector3(0, 1.5, -8), wallc)
	_box(Vector3(10, 0.2, 8), Vector3(0, 3.0, -4), Color(0.6, 0.6, 0.58))
	_box(Vector3(10, 0.6, 0.25), Vector3(0, 2.75, 0), Color(0.1, 0.35, 0.3))   # sign box
	var glass_mat := _mat(Color(0.6, 0.75, 0.8), true, 0.07)
	for seg in [[-5.0, 3.05], [3.95, 5.0]]:
		var w: float = seg[1] - seg[0]
		var g := _box(Vector3(w, 2.45, 0.04), Vector3((seg[0] + seg[1]) * 0.5, 1.225, 0), Color.WHITE, true, self, glass_mat)
		g.name = "store_front_glass"
		(g.get_child(0) as StaticBody3D).add_to_group("see_through")
	# shelves + counter
	for x in [-3.2, -1.6, 0.0]:
		_box(Vector3(0.5, 1.6, 4.5), Vector3(x, 0.8, -4.8), Color(0.5, 0.5, 0.55))
	_box(Vector3(1.8, 1.0, 0.6), Vector3(3, 0.5, -1.5), Color(0.4, 0.3, 0.22))
	for i in 3:
		var l := _light(Vector3(-2 + i * 2.2, 2.7, -3.5), Color(0.85, 1.0, 0.9), 1.4, 7.0)
		l.add_to_group("flicker_lights")
		l.add_to_group("store_lights")
		_store_lights.append(l)
	# store light spilling onto the sidewalk through the glass
	_light(Vector3(0, 2.2, 2.0), Color(0.8, 0.95, 0.9), 0.9, 6.0).add_to_group("store_lights")
	# streetlights (sodium)
	for p in [Vector3(-7, 0, 9.8), Vector3(9, 0, 9.8)]:
		_box(Vector3(0.15, 5, 0.15), p + Vector3(0, 2.5, 0), Color(0.2, 0.2, 0.2), false)
		_box(Vector3(0.5, 0.12, 0.25), p + Vector3(0, 5, -0.3), Color(1, 0.7, 0.35), false, self, _mat(Color(1, 0.7, 0.35), true))
		_light(p + Vector3(0, 4.7, -0.6), Color(1.0, 0.6, 0.25), 2.2, 10.0)
	# bus stop at x=12 on the far sidewalk
	_box(Vector3(4.2, 0.1, 1.8), Vector3(12, 2.5, 11.0), Color(0.25, 0.27, 0.3), false)
	_box(Vector3(4.2, 2.4, 0.06), Vector3(12, 1.25, 11.9), Color(0.3, 0.35, 0.4))
	_box(Vector3(0.08, 2.5, 0.08), Vector3(10, 1.25, 10.2), Color(0.2, 0.2, 0.22), false)
	_box(Vector3(0.08, 2.5, 0.08), Vector3(14, 1.25, 10.2), Color(0.2, 0.2, 0.22), false)
	_box(Vector3(2.5, 0.08, 0.45), Vector3(11.8, 0.45, 11.35), Color(0.35, 0.3, 0.25), false)
	_box(Vector3(0.9, 0.6, 0.04), Vector3(13.4, 1.6, 11.85), Color(0.75, 0.75, 0.6), false)  # timetable
	_light(Vector3(12, 2.35, 11.0), Color(0.75, 0.85, 1.0), 0.8, 4.5)
	# small room with a door (x -12..-8, z 2..6), door gap on the +x wall at z 3.55..4.45
	var roomc := Color(0.5, 0.47, 0.4)
	_box(Vector3(4, 0.2, 4), Vector3(-10, -0.05, 4), Color(0.4, 0.33, 0.25))
	_box(Vector3(4, 3, 0.2), Vector3(-10, 1.5, 2), roomc)
	_box(Vector3(4, 3, 0.2), Vector3(-10, 1.5, 6), roomc)
	_box(Vector3(0.2, 3, 4), Vector3(-12, 1.5, 4), roomc)
	_box(Vector3(0.2, 3, 1.55), Vector3(-8, 1.5, 2.775), roomc)
	_box(Vector3(0.2, 3, 1.55), Vector3(-8, 1.5, 5.225), roomc)
	_box(Vector3(0.2, 0.9, 0.9), Vector3(-8, 2.55, 4), roomc)
	_box(Vector3(4, 0.2, 4), Vector3(-10, 3.0, 4), roomc)
	_light(Vector3(-10, 2.6, 4), Color(1.0, 0.85, 0.6), 0.9, 5.0)
	# corridor bulb outside the door (casts shadows: the mimic has none)
	var bulb := _light(Vector3(-6.6, 2.7, 3.2), Color(1.0, 0.85, 0.6), 1.6, 6.0, true)
	bulb.add_to_group("flicker_lights")
	_box(Vector3(0.12, 0.12, 0.12), Vector3(-6.6, 2.75, 3.2), Color(1, 0.9, 0.6), false, self, _mat(Color(1, 0.9, 0.6), true))
	# a crate next to the mimic so the missing shadow is obvious
	_box(Vector3(0.5, 0.5, 0.5), Vector3(-6.5, 0.25, 4.9), Color(0.45, 0.35, 0.2))

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	static_rect = ColorRect.new()
	static_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	static_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float amount = 0.0;
float h(vec2 p){ return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment(){
	vec2 px = floor(UV * vec2(320.0, 240.0));
	float n = h(px + vec2(TIME * 61.0, TIME * 37.0));
	COLOR = vec4(vec3(n), amount * 0.55 * step(0.02, amount));
}"""
	sm.shader = sh
	static_rect.material = sm
	cl.add_child(static_rect)
	fade_rect = ColorRect.new()
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(fade_rect)
	hud_sub = Label.new()
	hud_sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hud_sub.position = Vector2(20, 420)
	hud_sub.size = Vector2(600, 30)
	hud_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.add_child(hud_sub)
	hud_choice = Label.new()
	hud_choice.position = Vector2(20, 390)
	hud_choice.size = Vector2(600, 30)
	hud_choice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_choice.modulate = Color(1, 0.85, 0.5)
	cl.add_child(hud_choice)
	hud_state = Label.new()
	hud_state.position = Vector2(6, 4)
	hud_state.add_theme_font_size_override("font_size", 10)
	hud_state.modulate = Color(1, 1, 1, 0.6)
	cl.add_child(hud_state)
