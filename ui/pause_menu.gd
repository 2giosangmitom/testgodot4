extends CanvasLayer
## Esc pause menu (instanced by the HUD). Pauses the tree.

const MAIN_MENU := "res://ui/main_menu.tscn"

var root: Control
var menu: VBoxContainer
var settings: SettingsMenu
var _buttons: Array[Button] = []

func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.theme = preload("res://ui/theme.tres")
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_to_group("ui_cursor")
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	menu = VBoxContainer.new()
	menu.set_anchors_preset(Control.PRESET_CENTER)
	menu.offset_left = -120
	menu.offset_right = 120
	menu.offset_top = -80
	menu.offset_bottom = 80
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", 4)
	root.add_child(menu)
	var title := Label.new()
	title.text = "TẠM DỪNG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.62, 0.25))
	menu.add_child(title)
	_add_button("Tiếp tục", resume)
	_add_button("Cài đặt", _open_settings)
	_add_button("Về menu chính", _to_main_menu)
	settings = SettingsMenu.new()
	settings.visible = false
	settings.closed.connect(func(): menu.visible = true; _buttons[1].grab_focus())
	root.add_child(settings)
	root.visible = false

func _add_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	b.mouse_entered.connect(b.grab_focus)
	b.focus_entered.connect(func(): AudioDirector.play_sfx("ui_move", -12.0))
	menu.add_child(b)
	_buttons.append(b)

func is_open() -> bool:
	return root.visible

func open() -> void:
	if root.visible:
		return
	var phone := get_tree().get_first_node_in_group("phone")
	if phone and phone.get("is_open"):
		phone.close()
		return
	root.visible = true
	menu.visible = true
	settings.visible = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDirector.play_sfx("ui_select", -8.0)
	_buttons[0].grab_focus()

func resume() -> void:
	root.visible = false
	get_tree().paused = false
	AudioDirector.play_sfx("ui_back", -8.0)
	var p := GameState.player
	if p and is_instance_valid(p) and not p.get("dying") and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _open_settings() -> void:
	menu.visible = false
	settings.open()

func _to_main_menu() -> void:
	get_tree().paused = false
	var ch = ChapterDirector.get("current_chapter")
	if ch and is_instance_valid(ch):
		ch.queue_free()
		ChapterDirector.set("current_chapter", null)
	GameState.input_locks.clear()
	GameState.phone_open = false
	AudioDirector.stop_all_ambience(0.5)
	AudioDirector.stop_voice()
	get_tree().change_scene_to_file(MAIN_MENU)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if root.visible:
		if not settings.visible:
			resume()
	else:
		var p := GameState.player
		if p and is_instance_valid(p) and p.get("dying"):
			return
		open()
	get_viewport().set_input_as_handled()
