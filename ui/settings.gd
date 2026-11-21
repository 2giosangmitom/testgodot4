class_name SettingsMenu
extends Control
## Settings panel used by the main menu and the pause menu. All values persist via
## SaveSystem.set_setting. Call SettingsMenu.apply_saved() once at startup (main menu does).
##
## Keys: vol_<Bus> (0..1 linear), mouse_sens (deg/px), low_res (bool), fullscreen (bool), subtitles (bool)

signal closed

const BUSES := [["Master", "Âm lượng chung"], ["Music", "Nhạc"], ["Amb", "Môi trường"], ["SFX", "Hiệu ứng"], ["Voice", "Lồng tiếng"]]
const MIX_TRIM_DB := {"Music": -3.0, "Amb": -3.0}

var _first: Control
var _panel: PanelContainer

static func apply_saved() -> void:
	for b in BUSES:
		_apply_bus(b[0], float(SaveSystem.get_setting("vol_" + b[0], 1.0 if b[0] != "Music" else 0.8)))
	_apply_fullscreen(bool(SaveSystem.get_setting("fullscreen", true)))

static func _apply_bus(bus: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)) + float(MIX_TRIM_DB.get(bus, 0.0)))
	AudioServer.set_bus_mute(idx, v <= 0.001)

static func _apply_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)

func _ready() -> void:
	theme = preload("res://ui/theme.tres")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("ui_cursor")
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(440, 0)
	panel.offset_left = -220
	panel.offset_right = 220
	panel.offset_top = -150
	panel.offset_bottom = 150
	add_child(panel)
	_panel = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	var title := Label.new()
	title.text = "CÀI ĐẶT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 0.62, 0.25))
	v.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	for b in BUSES:
		var bus: String = b[0]
		var cur := float(SaveSystem.get_setting("vol_" + bus, 1.0 if bus != "Music" else 0.8))
		_slider_row(grid, b[1], 0.0, 1.0, 0.05, cur, func(x: float):
			SaveSystem.set_setting("vol_" + bus, x)
			_apply_bus(bus, x))
	_slider_row(grid, "Độ nhạy chuột", 0.03, 0.4, 0.01, float(SaveSystem.get_setting("mouse_sens", 0.12)), func(x: float):
		SaveSystem.set_setting("mouse_sens", x))
	_check_row(v, "Độ phân giải 3D thấp", bool(SaveSystem.get_setting("low_res", false)), func(on: bool):
		RenderSettings.set_low_res(on))
	_check_row(v, "Toàn màn hình", bool(SaveSystem.get_setting("fullscreen", true)), func(on: bool):
		SaveSystem.set_setting("fullscreen", on)
		_apply_fullscreen(on))
	_check_row(v, "Phụ đề", bool(SaveSystem.get_setting("subtitles", true)), func(on: bool):
		SaveSystem.set_setting("subtitles", on))
	var back := Button.new()
	back.text = "Quay lại"
	back.pressed.connect(close)
	back.mouse_entered.connect(back.grab_focus)
	var c := CenterContainer.new()
	c.add_child(back)
	v.add_child(c)
	_fit.call_deferred()
	visibility_changed.connect(func():
		if visible and _first:
			_first.grab_focus.call_deferred())

func _fit() -> void:
	var h := _panel.get_combined_minimum_size().y
	_panel.offset_top = -roundf(h / 2)
	_panel.offset_bottom = roundf(h / 2)

func open() -> void:
	visible = true
	if _first:
		_first.grab_focus()

func close() -> void:
	AudioDirector.play_sfx("ui_back", -6.0)
	visible = false
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()

func _slider_row(grid: GridContainer, label: String, mn: float, mx: float, step: float, value: float, cb: Callable) -> void:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 18)
	grid.add_child(l)
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(170, 16)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := Label.new()
	val.custom_minimum_size = Vector2(40, 0)
	val.text = _fmt(value, mx)
	s.value_changed.connect(func(x: float):
		val.text = _fmt(x, mx)
		cb.call(x))
	s.drag_ended.connect(func(_c: bool): AudioDirector.play_sfx("ui_move", -10.0))
	s.mouse_entered.connect(s.grab_focus)
	h.add_child(s)
	h.add_child(val)
	grid.add_child(h)
	if _first == null:
		_first = s

func _check_row(parent: Control, label: String, value: bool, cb: Callable) -> void:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = value
	c.toggled.connect(func(on: bool):
		AudioDirector.play_sfx("ui_select", -8.0)
		cb.call(on))
	c.mouse_entered.connect(c.grab_focus)
	parent.add_child(c)

func _fmt(x: float, mx: float) -> String:
	return "%d%%" % roundi(x * 100) if mx <= 1.0 else "%.2f" % x
