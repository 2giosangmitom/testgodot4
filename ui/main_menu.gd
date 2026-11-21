extends Node3D
## Main menu (project main scene): content-warning splash, fogged PSX alley background with a
## flickering sodium streetlight, and the menu (continue / new game / chapter select / settings / quit).
## Debug: `-- --shot=<png> [--demo=chapters|settings|warning]`

const THEME := preload("res://ui/theme.tres")
const ACCENT := Color(1, 0.62, 0.25)
const CHAPTERS := [
	[1, "Chương 1 — Ca đêm đầu tiên"],
	[2, "Chương 2 — Người gõ cửa"],
	[3, "Chương 3 — Phố không người"],
	[4, "Chương 4 — Đèn đường cuối ngõ"],
]

static var warning_shown := false

var cam: Camera3D
var lamp: OmniLight3D
var lamp_head: MeshInstance3D
var far_lamp: OmniLight3D
var figure: MeshInstance3D
var ui: Control
var main_box: VBoxContainer
var chapter_box: VBoxContainer
var settings: SettingsMenu
var warning: Control
var fade: FadeLayer
var _t := 0.0
var _flicker := 0.0
var _next_flicker := 3.0
var _busy := false

func _ready() -> void:
	get_tree().paused = false
	GameState.input_locks.clear()
	GameState.phone_open = false
	SettingsMenu.apply_saved()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	RenderSettings.set_static(0.0)
	RenderSettings.set_fog(3.5, 21.0, Color(0.045, 0.035, 0.035), 0.0)
	_build_world()
	_build_ui()
	fade = FadeLayer.new()
	add_child(fade)
	if GameState.debug_autoplay and DebugShot.get_arg("shot") == "":
		ChapterDirector.start_autoplay.call_deferred()
		return
	if ResourceLoader.exists("res://render/post_fx.tscn"):
		add_child(load("res://render/post_fx.tscn").instantiate())
	var demo := DebugShot.get_arg("demo")
	if not warning_shown and DebugShot.get_arg("shot") == "" or demo == "warning":
		_show_warning()
	else:
		_enter_menu()
	if demo == "chapters":
		_show_chapters()
	elif demo == "settings":
		_open_settings()
	DebugShot.attach_if_requested(self)

# ------------------------------------------------------------------ 3D background
func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.09, 0.08, 0.1)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var world := Node3D.new()
	world.name = "Alley"
	add_child(world)
	var asphalt := Color(0.3, 0.29, 0.28)
	ProtoGeo.box(world, Vector3(4.2, 0.2, 60), Vector3(0, -0.1, -24), asphalt, false, {"uv_scale": 12.0})
	# curbs / sidewalks
	for side in [-1, 1]:
		ProtoGeo.box(world, Vector3(1.0, 0.16, 60), Vector3(side * 2.6, 0.0, -24), Color(0.42, 0.41, 0.39), false, {"uv_scale": 10.0})
	# building facades with windows, uneven heights (tube houses)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2204
	var z := 4.0
	while z > -52.0:
		var depth := rng.randf_range(3.5, 5.0)
		for side in [-1, 1]:
			var h := rng.randf_range(5.5, 11.0)
			var shade := rng.randf_range(0.42, 0.62)
			var tint := Color(shade, shade * rng.randf_range(0.93, 1.0), shade * rng.randf_range(0.82, 0.95))
			var x: float = side * (3.1 + rng.randf_range(0.0, 0.35))
			ProtoGeo.box(world, Vector3(1.0, h, depth - 0.1), Vector3(x + side * 0.5, h * 0.5, z - depth * 0.5), tint, false, {"uv_scale": 3.0})
			# windows: some lit (warm / TV blue), most dark
			for floor_i in int(h / 3.0):
				var wy := 1.6 + floor_i * 3.0
				if wy > h - 0.8:
					break
				var lit := rng.randf() < 0.22
				var wc := Color(0.05, 0.05, 0.06)
				if lit:
					wc = Color(1.0, 0.78, 0.45) if rng.randf() < 0.7 else Color(0.45, 0.6, 0.9)
				var win := ProtoGeo.box(world, Vector3(0.05, 1.0, 1.1), Vector3(x - side * 0.01, wy, z - depth * 0.5), wc, false, {"unlit": lit})
				win.name = "Window"
			# rolling shutter on ground floor
			if rng.randf() < 0.5:
				ProtoGeo.box(world, Vector3(0.05, 2.2, depth * 0.6), Vector3(x - side * 0.02, 1.1, z - depth * 0.5), Color(0.33, 0.35, 0.36), false)
		# sagging power lines
		if rng.randf() < 0.6:
			var wh := rng.randf_range(4.8, 6.0)
			for k in 2:
				ProtoGeo.box(world, Vector3(6.4, 0.025, 0.025), Vector3(0, wh + k * 0.25, z - 1.0), Color(0.05, 0.05, 0.05), false)
		z -= depth
	# clutter: parked motorbike-ish blocks, AC units
	ProtoGeo.box(world, Vector3(0.4, 0.7, 1.6), Vector3(-1.9, 0.35, -5.5), Color(0.18, 0.2, 0.24), false)
	ProtoGeo.box(world, Vector3(0.6, 0.45, 0.4), Vector3(2.75, 3.2, -11.0), Color(0.6, 0.6, 0.58), false)
	ProtoGeo.box(world, Vector3(0.6, 0.45, 0.4), Vector3(-2.75, 4.0, -17.0), Color(0.6, 0.6, 0.58), false)
	# the streetlight
	var pole_x := 1.9
	var pole_z := -9.0
	ProtoGeo.box(world, Vector3(0.14, 5.2, 0.14), Vector3(pole_x, 2.6, pole_z), Color(0.25, 0.25, 0.24), false)
	ProtoGeo.box(world, Vector3(1.2, 0.08, 0.08), Vector3(pole_x - 0.55, 5.1, pole_z), Color(0.25, 0.25, 0.24), false)
	lamp_head = ProtoGeo.box(world, Vector3(0.5, 0.12, 0.26), Vector3(pole_x - 1.1, 5.02, pole_z), Color(1.0, 0.62, 0.25), false, {"unlit": true})
	lamp = OmniLight3D.new()
	lamp.position = Vector3(pole_x - 1.1, 4.7, pole_z)
	lamp.light_color = Color(1.0, 0.58, 0.22)
	lamp.light_energy = 2.4
	lamp.omni_range = 11.0
	lamp.omni_attenuation = 0.9
	world.add_child(lamp)
	far_lamp = OmniLight3D.new()
	far_lamp.position = Vector3(-1.2, 4.6, -27.0)
	far_lamp.light_color = Color(1.0, 0.55, 0.2)
	far_lamp.light_energy = 1.4
	far_lamp.omni_range = 8.0
	world.add_child(far_lamp)
	ProtoGeo.box(world, Vector3(0.12, 5.0, 0.12), Vector3(-1.9, 2.5, -27.0), Color(0.25, 0.25, 0.24), false)
	ProtoGeo.box(world, Vector3(0.5, 0.12, 0.26), Vector3(-1.2, 4.9, -27.0), Color(1.0, 0.6, 0.25), false, {"unlit": true})
	# someone standing under the far light (only sometimes there)
	figure = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.2
	cap.height = 1.85
	cap.radial_segments = 6
	cap.rings = 2
	figure.mesh = cap
	figure.material_override = ProtoGeo.mat(Color(0.02, 0.02, 0.02), {"unlit": true})
	figure.position = Vector3(-0.9, 0.95, -27.4)
	figure.visible = false
	world.add_child(figure)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.05
	cam.far = 60.0
	cam.position = Vector3(-0.3, 1.55, 2.0)
	add_child(cam)
	cam.current = true

func _process(dt: float) -> void:
	_t += dt
	# slow drift down the alley + breathing sway
	cam.position = Vector3(-0.3 + sin(_t * 0.13) * 0.25, 1.55 + sin(_t * 0.7) * 0.02, 1.0 - sin(_t * 0.04) * 2.5)
	cam.rotation = Vector3(deg_to_rad(2.0 + sin(_t * 0.21) * 0.8), deg_to_rad(2.0 + sin(_t * 0.09) * 2.5), deg_to_rad(sin(_t * 0.17) * 0.6))
	# sodium flicker
	_next_flicker -= dt
	if _next_flicker <= 0.0:
		_flicker = randf_range(0.25, 0.9)
		_next_flicker = randf_range(4.0, 11.0)
		AudioDirector.play_sfx("fluorescent_flicker", -18.0, 0.7)
	if _flicker > 0.0:
		_flicker -= dt
		var on := randf() < 0.45
		lamp.light_energy = 2.4 if on else 0.15
		lamp_head.visible = on
		if _flicker <= 0.0:
			lamp.light_energy = 2.4
			lamp_head.visible = true
			figure.visible = randf() < 0.35
	else:
		lamp.light_energy = 2.4 + sin(_t * 9.0) * 0.05

# ------------------------------------------------------------------ UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	ui = Control.new()
	ui.theme = THEME
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)
	# readability gradient on the left
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.75))
	g.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 4
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(grad)
	grad.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	grad.offset_right = 360
	var title := Label.new()
	title.text = "ĐÈN ĐƯỜNG\nCUỐI NGÕ"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", ACCENT)
	title.add_theme_color_override("font_shadow_color", Color(0.25, 0.05, 0.0, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.add_theme_constant_override("line_spacing", -8)
	title.position = Vector2(40, 40)
	ui.add_child(title)
	var sub := Label.new()
	sub.text = "một câu chuyện ca đêm"
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.7, 0.66, 0.6))
	sub.position = Vector2(44, 148)
	ui.add_child(sub)
	main_box = _menu_box()
	if SaveSystem.has_checkpoint():
		_btn(main_box, "Tiếp tục", _continue)
	_btn(main_box, "Chơi mới", _new_game)
	if SaveSystem.has_seen_any_ending():
		_btn(main_box, "Chọn chương", _show_chapters)
	_btn(main_box, "Cài đặt", _open_settings)
	_btn(main_box, "Thoát", func(): get_tree().quit())
	chapter_box = _menu_box()
	var ct := Label.new()
	ct.text = "CHỌN CHƯƠNG"
	ct.add_theme_color_override("font_color", ACCENT)
	ct.add_theme_font_size_override("font_size", 20)
	chapter_box.add_child(ct)
	for c in CHAPTERS:
		_btn(chapter_box, c[1], _start_chapter.bind(c[0]))
	_btn(chapter_box, "Quay lại", _back_to_main)
	chapter_box.visible = false
	var ver := Label.new()
	ver.text = "v0.1  ·  W/S chọn · E xác nhận"
	ver.add_theme_font_size_override("font_size", 14)
	ver.add_theme_color_override("font_color", Color(0.45, 0.43, 0.4))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -260
	ver.offset_top = -22
	ver.offset_right = -10
	ver.offset_bottom = -4
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(ver)
	if ChapterDirector.menu_error != "":
		var error := Label.new()
		error.text = ChapterDirector.menu_error
		error.position = Vector2(40, 420)
		error.add_theme_color_override("font_color", Color.SALMON)
		ui.add_child(error)
		ChapterDirector.menu_error = ""
	settings = SettingsMenu.new()
	settings.visible = false
	settings.closed.connect(_back_to_main)
	ui.add_child(settings)

func _menu_box() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = Vector2(40, 210)
	v.size = Vector2(300, 200)
	v.add_theme_constant_override("separation", 2)
	ui.add_child(v)
	return v

func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(func():
		if _busy:
			return
		AudioDirector.play_sfx("ui_select", -6.0)
		cb.call())
	b.mouse_entered.connect(b.grab_focus)
	b.focus_entered.connect(func(): AudioDirector.play_sfx("ui_move", -12.0))
	parent.add_child(b)
	return b

func _first_button(box: Control) -> Button:
	for c in box.get_children():
		if c is Button and c.visible:
			return c
	return null

func _enter_menu() -> void:
	ui.visible = true
	AudioDirector.play_music("music_menu", -4.0, 3.0)
	var b := _first_button(main_box)
	if b:
		b.grab_focus()

func _show_warning() -> void:
	warning_shown = true
	ui.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 110
	add_child(layer)
	warning = ColorRect.new()
	(warning as ColorRect).color = Color.BLACK
	warning.theme = THEME
	warning.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(warning)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	warning.add_child(v)
	var t := Label.new()
	t.text = "CẢNH BÁO NỘI DUNG"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 32)
	t.add_theme_color_override("font_color", Color(0.85, 0.2, 0.15))
	v.add_child(t)
	var m := Label.new()
	m.text = "Trò chơi có yếu tố kinh dị, âm thanh lớn đột ngột\nvà hình ảnh nhấp nháy."
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.add_theme_font_size_override("font_size", 22)
	v.add_child(m)
	var m2 := Label.new()
	m2.text = "Nên chơi với tai nghe, trong phòng tối."
	m2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m2.add_theme_font_size_override("font_size", 18)
	m2.add_theme_color_override("font_color", Color(0.55, 0.53, 0.5))
	v.add_child(m2)
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_callback(_dismiss_warning)

func _dismiss_warning() -> void:
	if warning == null or not is_instance_valid(warning):
		return
	var w := warning
	warning = null
	var tw := create_tween()
	tw.tween_property(w, "modulate:a", 0.0, 1.2)
	tw.tween_callback(w.get_parent().queue_free)
	_enter_menu()

func _input(event: InputEvent) -> void:
	if warning and (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_dismiss_warning()
		get_viewport().set_input_as_handled()
		return
	if settings.visible or _busy:
		return
	# W/S + E navigation on top of the arrow keys / Enter
	if event.is_action_pressed("move_forward") or event.is_action_pressed("move_back"):
		var f := get_viewport().gui_get_focus_owner()
		if f:
			var nxt := f.find_valid_focus_neighbor(SIDE_TOP if event.is_action_pressed("move_forward") else SIDE_BOTTOM)
			if nxt:
				nxt.grab_focus()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.is_action_pressed("interact"):
		var f := get_viewport().gui_get_focus_owner()
		if f is Button:
			f.pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and chapter_box.visible:
		_back_to_main()

func _show_chapters() -> void:
	main_box.visible = false
	chapter_box.visible = true
	_first_button(chapter_box).grab_focus()

func _back_to_main() -> void:
	settings.visible = false
	chapter_box.visible = false
	main_box.visible = true
	var b := _first_button(main_box)
	if b:
		b.grab_focus()

func _open_settings() -> void:
	main_box.visible = false
	chapter_box.visible = false
	settings.open()

# ------------------------------------------------------------------ start game
func _begin() -> void:
	_busy = true
	ui.mouse_filter = Control.MOUSE_FILTER_STOP
	AudioDirector.stop_music(1.2)

func _continue() -> void:
	_begin()
	if ChapterDirector.has_method("continue_from_checkpoint"):
		ChapterDirector.continue_from_checkpoint()
	else:
		var id := SaveSystem.load_checkpoint()
		ChapterDirector.start_chapter(maxi(GameState.chapter, 1), id)

func _new_game() -> void:
	_start_chapter(1)

func _start_chapter(n: int) -> void:
	_begin()
	if ChapterDirector.has_method("start_new_at"):
		ChapterDirector.start_new_at(n)
	else:
		GameState.reset()
		SaveSystem.clear_checkpoint()
		ChapterDirector.start_chapter(n)
