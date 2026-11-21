class_name TitleCard
extends CanvasLayer
## Persistent full-screen black card with big text (chapter titles, "Ba tháng sau", credits).
## Lives under the ChapterDirector autoload so it survives scene changes.
##   await TitleCard.show_card(get_tree(), "Hết chương 1", "", 3.0)
## Layer 130 (above HUD/fade).

const THEME := preload("res://ui/theme.tres")

var _rect: ColorRect
var _title: Label
var _sub: Label

static func show_card(tree: SceneTree, title: String, subtitle := "", seconds := 3.0, fade := 0.8, host: Node = null) -> void:
	if GameState.debug_autoplay:
		seconds = 0.05
		fade = 0.02
	var card := TitleCard.new()
	(host if host else tree.root).add_child(card)
	card.setup(title, subtitle)
	await card.play(seconds, fade)
	card.queue_free()

func _init() -> void:
	layer = 130
	process_mode = Node.PROCESS_MODE_PAUSABLE

func setup(title: String, subtitle: String) -> void:
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.modulate.a = 0.0
	add_child(_rect)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	_rect.add_child(box)
	_title = Label.new()
	_title.theme = THEME
	_title.text = title
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", Color(0.92, 0.88, 0.78))
	box.add_child(_title)
	_sub = Label.new()
	_sub.theme = THEME
	_sub.text = subtitle
	_sub.visible = subtitle != ""
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.add_theme_font_size_override("font_size", 22)
	_sub.add_theme_color_override("font_color", Color(0.62, 0.6, 0.56))
	box.add_child(_sub)

func play(seconds: float, fade: float) -> void:
	var t := create_tween()
	t.tween_property(_rect, "modulate:a", 1.0, fade)
	t.tween_interval(seconds)
	t.tween_property(_rect, "modulate:a", 0.0, fade)
	await t.finished
