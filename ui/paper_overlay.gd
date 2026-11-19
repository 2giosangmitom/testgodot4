class_name PaperOverlay
extends CanvasLayer
## Full-screen "paper" reader for notes / notice boards. Locks input while open.
## Usage: PaperOverlay.show_paper(get_tree(), "Thông báo", "Nội dung...")  (awaitable via `closed`)

signal closed

const SCENE := "res://ui/paper_overlay.tscn"

var title := ""
var body := ""
var _opened_ms := 0
var root: Control

static func show_paper(tree: SceneTree, p_title: String, p_body: String) -> PaperOverlay:
	var o: PaperOverlay = load(SCENE).instantiate()
	o.title = p_title
	o.body = p_body
	tree.root.add_child(o)
	return o

func _ready() -> void:
	layer = 60
	_opened_ms = Time.get_ticks_msec()
	GameState.lock_input("paper")
	EventBus.interact_prompt.emit("")
	AudioDirector.play_sfx("page_turn", -4.0)
	root = Control.new()
	root.theme = preload("res://ui/theme.tres")
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_to_group("ui_cursor")
	root.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_close())
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(dim)
	var paper := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.78, 0.74, 0.62)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.45, 0.4, 0.3)
	sb.set_content_margin_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_offset = Vector2(4, 4)
	sb.anti_aliasing = false
	paper.add_theme_stylebox_override("panel", sb)
	paper.set_anchors_preset(Control.PRESET_CENTER)
	paper.custom_minimum_size = Vector2(380, 300)
	paper.offset_left = -190
	paper.offset_right = 190
	paper.offset_top = -170
	paper.offset_bottom = 150
	paper.rotation_degrees = -1.0
	paper.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(paper)
	var v := VBoxContainer.new()
	paper.add_child(v)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color(0.15, 0.1, 0.08))
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 0)
	t.visible = title != ""
	v.add_child(t)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = body
	rt.fit_content = true
	rt.scroll_active = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_color_override("default_color", Color(0.12, 0.1, 0.09))
	rt.add_theme_constant_override("shadow_offset_x", 0)
	rt.add_theme_constant_override("shadow_offset_y", 0)
	rt.add_theme_font_size_override("normal_font_size", 18)
	rt.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(rt)
	var hint := Label.new()
	hint.text = "[E] Đóng"
	hint.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -60
	hint.offset_right = 60
	hint.offset_top = -40
	hint.offset_bottom = -20
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint)

func _input(event: InputEvent) -> void:
	if Time.get_ticks_msec() - _opened_ms < 250:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("pause") or event.is_action_pressed("skip"):
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	if is_queued_for_deletion():
		return
	AudioDirector.play_sfx("page_turn", -8.0, 1.1)
	GameState.unlock_input("paper")
	closed.emit()
	queue_free()

func _exit_tree() -> void:
	GameState.unlock_input("paper")
