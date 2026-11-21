class_name Credits
extends CanvasLayer
## Scrolling credits over black. `await Credits.roll(get_tree(), "A")`.

const THEME := preload("res://ui/theme.tres")

const LINES := [
	["ĐÈN ĐƯỜNG CUỐI NGÕ", 44],
	["", 20],
	["Một trò chơi kinh dị siêu nhiên", 22],
	["", 40],
	["Thiết kế, lập trình, kịch bản", 18],
	["Claude Code cùng Võ Quang Chiến", 22],
	["", 24],
	["Engine", 18], ["Godot 4", 22],
	["", 24],
	["Mô hình và texture", 18], ["Dựng bằng Blender (headless), texture tự vẽ bằng Python", 22],
	["", 24],
	["Giọng nói", 18], ["VieNeu-TTS v3 Turbo", 22],
	["", 24],
	["Âm thanh", 18], ["Kenney, OpenGameArt (CC0) và âm thanh tổng hợp. Xem CREDITS.md", 22],
	["", 24],
	["Font", 18], ["VT323 — SIL Open Font License", 22],
	["", 40],
	["Mọi tên người, thương hiệu và địa danh trong game đều là hư cấu.", 18],
	["", 40],
	["Cảm ơn bạn đã chơi.", 26],
	["", 80],
]

static func roll(tree: SceneTree, ending: String, seconds := 32.0, host: Node = null) -> void:
	if GameState.debug_autoplay:
		seconds = 0.1
	var c := Credits.new()
	(host if host else tree.root).add_child(c)
	await c._run(ending, seconds)
	c.queue_free()

func _init() -> void:
	layer = 130
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _run(ending: String, seconds: float) -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.theme = THEME
	col.custom_minimum_size = Vector2(560, 0)
	col.position = Vector2(40, 480)
	col.add_theme_constant_override("separation", 6)
	bg.add_child(col)
	for l in LINES:
		var lab := Label.new()
		lab.text = l[0]
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size = Vector2(560, 0)
		lab.add_theme_font_size_override("font_size", l[1])
		lab.add_theme_color_override("font_color", Color(0.9, 0.86, 0.76) if ending == "A" else Color(0.75, 0.7, 0.68))
		col.add_child(lab)
	await get_tree().process_frame
	var end_y := -col.size.y
	var t := create_tween()
	t.tween_property(col, "position:y", end_y, seconds)
	await t.finished
