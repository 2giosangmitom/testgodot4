extends Control
## Font check: renders Vietnamese sample text at several sizes.

const SAMPLE := "Đèn Đường Cuối Ngõ — ả ẫ ặ ố ợ ữ ỹ"

func _ready() -> void:
	var font: Font = load("res://assets/fonts/VT323-Regular.ttf")
	var y := 4
	for s in [10, 12, 13, 14, 16, 18, 20, 24, 32]:
		var l := Label.new()
		l.text = "%d: %s" % [s, SAMPLE]
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", s)
		l.position = Vector2(4, y)
		add_child(l)
		y += s + 8
	var t := Label.new()
	t.text = "Ê Nam, tối nay mày trực à? Nhiệm vụ: Quét mã vạch. Việc cần làm. Tin nhắn."
	t.position = Vector2(4, y)
	add_child(t)
	DebugShot.attach_if_requested(self)
