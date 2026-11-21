extends PanelContainer
## Pinned, read-only checklist for the current story segment.

const ACCENT := Color(1.0, 0.70, 0.40)
const PENDING := Color(0.94, 0.90, 0.82)
const COMPLETE := Color(0.58, 0.74, 0.62)
const WIDTH := 280.0
const EDGE := 14.0
const PHONE_GUTTER := 252.0
const TEXT_WIDTH := 238.0

var _count: Label
var _list: VBoxContainer
var _cinematic := false
var _checked: Texture2D
var _unchecked: Texture2D
var _empty_style := StyleBoxEmpty.new()
var _fit_pending := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -WIDTH - EDGE
	offset_right = -EDGE
	offset_top = EDGE
	offset_bottom = EDGE
	custom_minimum_size.x = WIDTH
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END

	_checked = _make_icon(true)
	_unchecked = _make_icon(false)
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.03, 0.03, 0.04, 0.84)
	frame.border_width_top = 2
	frame.border_color = Color(0.83, 0.48, 0.25)
	frame.set_content_margin_all(8)
	frame.content_margin_left = 10
	frame.content_margin_right = 10
	frame.anti_aliasing = false
	add_theme_stylebox_override("panel", frame)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 5)
	add_child(stack)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(header)
	var title := Label.new()
	title.text = "NHIỆM VỤ"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", ACCENT)
	title.add_theme_font_size_override("font_size", 19)
	header.add_child(title)
	_count = Label.new()
	_count.add_theme_color_override("font_color", COMPLETE)
	header.add_child(_count)

	_list = VBoxContainer.new()
	_list.name = "Checklist"
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_theme_constant_override("separation", 3)
	stack.add_child(_list)
	EventBus.objective_added.connect(func(_id: String, _text: String): _refresh())
	EventBus.objective_completed.connect(func(_id: String): _refresh())
	EventBus.objectives_reset.connect(_refresh)
	EventBus.letterbox.connect(_set_cinematic)
	EventBus.phone_toggled.connect(_set_phone_open)
	_set_phone_open(GameState.phone_open)
	_refresh()

func _set_phone_open(open: bool) -> void:
	# Keep the pinned panel visible next to the phone, not over its screen.
	position.x = get_parent_area_size().x - WIDTH - EDGE - (PHONE_GUTTER if open else 0.0)

func _set_cinematic(on: bool) -> void:
	_cinematic = on
	visible = not on and not GameState.objectives.is_empty()

func _refresh() -> void:
	for row in _list.get_children():
		_list.remove_child(row)
		row.queue_free()
	var done := 0
	for task in GameState.objectives:
		var checked: bool = task.done
		done += int(checked)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 6)
		_list.add_child(row)
		var box := CheckBox.new()
		box.name = "Status"
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.focus_mode = Control.FOCUS_NONE
		box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		box.button_pressed = checked
		box.add_theme_icon_override("checked", _checked)
		box.add_theme_icon_override("unchecked", _unchecked)
		for key in ["normal", "pressed", "hover", "hover_pressed", "focus"]:
			box.add_theme_stylebox_override(key, _empty_style)
		row.add_child(box)
		var text := Label.new()
		text.text = task.text
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.custom_minimum_size.x = TEXT_WIDTH
		text.add_theme_color_override("font_color", COMPLETE if checked else PENDING)
		text.add_theme_font_size_override("font_size", 17)
		row.add_child(text)
	_count.text = "%d/%d" % [done, GameState.objectives.size()]
	visible = not _cinematic and not GameState.objectives.is_empty()
	if not _fit_pending:
		_fit_pending = true
		_fit_height.call_deferred()

func _fit_height() -> void:
	await get_tree().process_frame
	_fit_pending = false
	size.y = get_combined_minimum_size().y

func _make_icon(checked: bool) -> Texture2D:
	var image := Image.create_empty(14, 14, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(1, 1, 12, 12), COMPLETE if checked else Color(0.72, 0.66, 0.55))
	image.fill_rect(Rect2i(2, 2, 10, 10), Color(0.16, 0.29, 0.21) if checked else Color(0.07, 0.06, 0.055))
	if checked:
		for point in [Vector2i(3, 7), Vector2i(4, 8), Vector2i(5, 9), Vector2i(6, 8),
				Vector2i(7, 7), Vector2i(8, 6), Vector2i(9, 5), Vector2i(10, 4)]:
			image.set_pixelv(point, COMPLETE)
			image.set_pixelv(point + Vector2i.DOWN, COMPLETE)
	return ImageTexture.create_from_image(image)
