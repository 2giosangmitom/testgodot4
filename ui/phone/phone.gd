extends CanvasLayer
## Nam's cheap 2012 Android phone. Toggle with `phone` (Tab).
## Screen is a 112x168 SubViewport scaled 2x with nearest filtering.
## Lock screen -> home (apps) -> "Việc cần làm" / "Tin nhắn" / "Đèn pin".
## Keys while open: W/S (or arrows, wheel) move, E/Enter select, Q/Backspace/RMB back, Tab close.

const THEME := preload("res://ui/theme.tres")
const SCREEN := Vector2i(112, 168)
const SCALE := 2
const HOLO := Color(0.2, 0.71, 0.9)
const TEXT := Color(0.88, 0.9, 0.9)
const DIM := Color(0.5, 0.53, 0.55)
const BODY_SIZE := Vector2(SCREEN.x * SCALE + 24, SCREEN.y * SCALE + 70)
const DAYS := {0: "Thứ Hai, 06/11", 1: "Thứ Hai, 06/11", 2: "Thứ Ba, 07/11", 3: "Thứ Tư, 08/11", 4: "Thứ Tư, 08/11"}

enum View { LOCK, HOME, TODO, THREADS, THREAD }

var is_open := false
var view: int = View.LOCK
var sel := 0
var thread_from := ""

var body: Panel
var container: SubViewportContainer
var vp: SubViewport
var screen: Control
var status_time: Label
var content: Control
var softkeys: Label
var items: Array[Control] = []
var scroll: ScrollContainer
var notif: PanelContainer
var notif_label: Label
var _tween: Tween
var _shake := 0.0
var _home_y := 0.0

func _ready() -> void:
	layer = 95
	add_to_group("phone")
	_build()
	body.position = Vector2(640 - BODY_SIZE.x - 14, 480 + 8)
	_home_y = 480 - BODY_SIZE.y + 34
	body.visible = false
	EventBus.message_received.connect(_on_message)
	EventBus.player_caught.connect(func(_e: String, _c: String): close())

func _exit_tree() -> void:
	if is_open:
		GameState.phone_open = false

# ------------------------------------------------------------------ build
func _build() -> void:
	body = Panel.new()
	body.name = "Body"
	body.size = BODY_SIZE
	body.theme = THEME
	body.add_to_group("ui_cursor")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.11)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.25, 0.25, 0.27)
	sb.set_corner_radius_all(14)
	sb.anti_aliasing = false
	body.add_theme_stylebox_override("panel", sb)
	add_child(body)
	# earpiece + brand
	var ear := ColorRect.new()
	ear.color = Color(0.04, 0.04, 0.04)
	ear.position = Vector2(BODY_SIZE.x / 2 - 18, 10)
	ear.size = Vector2(36, 3)
	body.add_child(ear)
	var brand := Label.new()
	brand.text = "NOVA"
	brand.add_theme_font_size_override("font_size", 14)
	brand.add_theme_color_override("font_color", Color(0.4, 0.4, 0.42))
	brand.position = Vector2(14, 4)
	body.add_child(brand)
	# screen bezel
	var bezel := ColorRect.new()
	bezel.color = Color(0.02, 0.02, 0.02)
	bezel.position = Vector2(10, 22)
	bezel.size = Vector2(SCREEN * SCALE) + Vector2(4, 4)
	body.add_child(bezel)
	container = SubViewportContainer.new()
	container.stretch = true
	container.stretch_shrink = SCALE
	container.position = Vector2(12, 24)
	container.size = Vector2(SCREEN * SCALE)
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_child(container)
	vp = SubViewport.new()
	vp.size = SCREEN
	vp.transparent_bg = false
	vp.handle_input_locally = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.snap_2d_transforms_to_pixel = true
	container.add_child(vp)
	# hardware softkeys (drawn)
	for i in 3:
		var k := PixelIcon.new()
		k.kind = ["back", "home", "menu"][i]
		k.color = Color(0.42, 0.42, 0.45)
		k.scale = Vector2(2, 2)
		k.position = Vector2(BODY_SIZE.x * (0.25 + i * 0.25) - 7, 24 + SCREEN.y * SCALE + 12)
		body.add_child(k)
	_build_screen()
	# small notification banner (when closed)
	notif = PanelContainer.new()
	notif.theme = THEME
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color(0.03, 0.05, 0.07, 0.9)
	nsb.border_width_left = 2
	nsb.border_color = HOLO
	nsb.set_content_margin_all(4)
	nsb.content_margin_left = 8
	nsb.anti_aliasing = false
	notif.add_theme_stylebox_override("panel", nsb)
	notif_label = Label.new()
	notif_label.add_theme_font_size_override("font_size", 16)
	notif.add_child(notif_label)
	notif.position = Vector2(640, 380)
	notif.visible = false
	notif.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(notif)

func _build_screen() -> void:
	screen = Control.new()
	screen.theme = THEME
	screen.size = Vector2(SCREEN)
	vp.add_child(screen)
	var bg := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.08, 0.12))
	g.set_color(1, Color(0.0, 0.0, 0.01))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 16
	gt.height = 32
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	bg.texture = gt
	bg.size = Vector2(SCREEN)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.add_child(bg)
	# status bar
	var sbar := ColorRect.new()
	sbar.color = Color(0, 0, 0, 0.85)
	sbar.size = Vector2(SCREEN.x, 11)
	screen.add_child(sbar)
	var sig := PixelIcon.new()
	sig.kind = "signal"
	sig.color = DIM
	sig.position = Vector2(2, 2)
	screen.add_child(sig)
	var g3 := Label.new()
	g3.text = "3G"
	g3.add_theme_font_size_override("font_size", 12)
	g3.add_theme_color_override("font_color", DIM)
	g3.add_theme_constant_override("shadow_offset_x", 0)
	g3.add_theme_constant_override("shadow_offset_y", 0)
	g3.position = Vector2(13, -2)
	screen.add_child(g3)
	var bat := PixelIcon.new()
	bat.kind = "battery"
	bat.color = DIM
	bat.position = Vector2(SCREEN.x - 12, 3)
	screen.add_child(bat)
	status_time = Label.new()
	status_time.add_theme_font_size_override("font_size", 12)
	status_time.add_theme_constant_override("shadow_offset_x", 0)
	status_time.add_theme_constant_override("shadow_offset_y", 0)
	status_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_time.position = Vector2(40, -2)
	status_time.size = Vector2(SCREEN.x - 55, 12)
	screen.add_child(status_time)
	content = Control.new()
	content.position = Vector2(0, 11)
	content.size = Vector2(SCREEN.x, SCREEN.y - 11 - 11)
	content.clip_contents = true
	screen.add_child(content)
	var kbar := ColorRect.new()
	kbar.color = Color(0, 0, 0, 0.85)
	kbar.position = Vector2(0, SCREEN.y - 11)
	kbar.size = Vector2(SCREEN.x, 11)
	screen.add_child(kbar)
	softkeys = Label.new()
	softkeys.add_theme_font_size_override("font_size", 12)
	softkeys.add_theme_color_override("font_color", DIM)
	softkeys.add_theme_constant_override("shadow_offset_x", 0)
	softkeys.add_theme_constant_override("shadow_offset_y", 0)
	softkeys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	softkeys.position = Vector2(0, SCREEN.y - 13)
	softkeys.size = Vector2(SCREEN.x, 12)
	screen.add_child(softkeys)

# ------------------------------------------------------------------ open / close
func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	if is_open:
		return
	is_open = true
	GameState.phone_open = true
	EventBus.phone_toggled.emit(true)
	AudioDirector.play_sfx("phone_open", -4.0)
	EventBus.interact_prompt.emit("")
	notif.visible = false
	view = View.LOCK
	sel = 0
	_refresh()
	body.visible = true
	_slide(_home_y)

func close() -> void:
	if not is_open:
		return
	is_open = false
	GameState.phone_open = false
	EventBus.phone_toggled.emit(false)
	AudioDirector.play_sfx("phone_tap", -8.0, 0.8)
	_slide(480 + 8, true)

func _slide(y: float, hide_after := false) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(body, "position:y", y, 0.22)
	if hide_after:
		_tween.tween_callback(func(): body.visible = false)

# ------------------------------------------------------------------ input
func _can_toggle() -> bool:
	if get_tree().paused:
		return false
	var p := GameState.player
	if p and is_instance_valid(p) and p.get("dying"):
		return false
	return is_open or not GameState.is_input_locked()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("phone") and not event.is_echo():
		if _can_toggle():
			toggle()
			get_viewport().set_input_as_handled()
		return
	if not is_open or get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var handled := true
		if event.is_action("move_forward"):
			_move(-1)
		elif event.is_action("move_back"):
			_move(1)
		elif event.is_action("interact") or event.physical_keycode == KEY_ENTER:
			_activate()
		elif event.is_action("phone_next") or event.physical_keycode == KEY_BACKSPACE:
			_back()
		else:
			handled = false
		if handled:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_back()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_move(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_move(1)

func _move(d: int) -> void:
	if view == View.THREAD:
		if scroll:
			scroll.scroll_vertical += d * 12
		return
	var count := _threads().size() if view == View.THREADS else items.size()
	if count == 0:
		return
	sel = wrapi(sel + d, 0, count)
	if view == View.THREADS:
		_refresh()   # list scrolls with the selection
	AudioDirector.play_sfx("phone_tap", -12.0)
	_highlight()

func _activate() -> void:
	AudioDirector.play_sfx("phone_tap", -8.0)
	match view:
		View.LOCK:
			view = View.HOME
			sel = 0
		View.HOME:
			match sel:
				0: view = View.TODO
				1: view = View.THREADS
				2: _toggle_flashlight()
			if view != View.HOME:
				sel = 0
		View.THREADS:
			var threads := _threads()
			if sel < threads.size():
				thread_from = threads[sel].from
				view = View.THREAD
		_:
			return
	_refresh()

func _back() -> void:
	AudioDirector.play_sfx("phone_tap", -10.0, 0.9)
	match view:
		View.LOCK:
			close()
			return
		View.HOME:
			view = View.LOCK
		View.TODO, View.THREADS:
			sel = 1 if view == View.THREADS else 0
			view = View.HOME
		View.THREAD:
			view = View.THREADS
			sel = 0
	_refresh()

func _toggle_flashlight() -> void:
	var p := GameState.player
	if p and is_instance_valid(p) and p.has_method("toggle_flashlight"):
		p.toggle_flashlight()
	else:
		GameState.flashlight_on = not GameState.flashlight_on
		EventBus.flashlight_toggled.emit(GameState.flashlight_on)

# ------------------------------------------------------------------ data helpers
func unread_count() -> int:
	var n := 0
	for id in GameState.unlocked_messages:
		if not GameState.get_flag("read_" + id):
			n += 1
	return n

## [{from, name, ids:[...], unread}] newest thread first.
func _threads() -> Array:
	var by_from := {}
	var order: Array = []
	for id in GameState.unlocked_messages:
		var m := Dialogue.get_message(id)
		var from: String = m.get("from", "?")
		if not by_from.has(from):
			by_from[from] = {"from": from, "name": Dialogue.speaker_name(from), "ids": [], "unread": 0}
		by_from[from].ids.append(id)
		if not GameState.get_flag("read_" + id):
			by_from[from].unread += 1
		order.erase(from)
		order.push_front(from)
	var out: Array = []
	for f in order:
		out.append(by_from[f])
	return out

func _date_string() -> String:
	return str(GameState.get_flag("phone_date", DAYS.get(GameState.chapter, "Thứ Hai, 06/11")))

# ------------------------------------------------------------------ views
func _refresh() -> void:
	for c in content.get_children():
		c.queue_free()
	items.clear()
	scroll = null
	status_time.text = GameState.clock_string()
	match view:
		View.LOCK: _view_lock()
		View.HOME: _view_home()
		View.TODO: _view_todo()
		View.THREADS: _view_threads()
		View.THREAD: _view_thread()
	_highlight()

func _label(text: String, size := 14, color := TEXT, pos := Vector2.ZERO, width := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 0)
	l.position = pos
	if width > 0:
		l.size = Vector2(width, 0)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(l)
	return l

func _header(text: String) -> void:
	var r := ColorRect.new()
	r.color = Color(0.06, 0.1, 0.13)
	r.size = Vector2(SCREEN.x, 14)
	content.add_child(r)
	var line := ColorRect.new()
	line.color = HOLO
	line.position = Vector2(0, 14)
	line.size = Vector2(SCREEN.x, 1)
	content.add_child(line)
	_label(text, 14, HOLO, Vector2(4, -1))

func _view_lock() -> void:
	var clock := _label(GameState.clock_string(), 40, Color(0.92, 0.95, 0.97), Vector2(0, 14))
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.size = Vector2(SCREEN.x, 40)
	var date := _label(_date_string(), 14, DIM, Vector2(0, 52))
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	date.size = Vector2(SCREEN.x, 14)
	var unread := unread_count()
	if unread > 0:
		var n := _label("%d tin nhắn mới" % unread, 14, HOLO, Vector2(4, 82), SCREEN.x - 8)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ring := _label("Nhấn E", 14, Color(0.7, 0.75, 0.78), Vector2(0, 112))
	ring.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ring.size = Vector2(SCREEN.x, 16)
	softkeys.text = "E: mở khóa"

func _view_home() -> void:
	_header("Ứng dụng")
	var unread := unread_count()
	var apps := [
		["Việc cần làm", Color(0.95, 0.75, 0.3), ""],
		["Tin nhắn", Color(0.45, 0.8, 0.4), str(unread) if unread > 0 else ""],
		["Đèn pin", Color(0.9, 0.9, 0.85), "BẬT" if GameState.flashlight_on else "TẮT"],
	]
	for i in apps.size():
		var y := 20 + i * 24
		var row := _row(Vector2(2, y), Vector2(SCREEN.x - 4, 22), i)
		var icon := ColorRect.new()
		icon.color = apps[i][1]
		icon.position = Vector2(4, 4)
		icon.size = Vector2(14, 14)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var glyph := PixelIcon.new()
		glyph.kind = ["todo", "mail", "torch"][i]
		glyph.color = Color(0.06, 0.06, 0.06)
		glyph.position = Vector2(6, 6)
		row.add_child(glyph)
		var l := Label.new()
		l.text = apps[i][0]
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 0)
		l.position = Vector2(22, 2)
		row.add_child(l)
		if apps[i][2] != "":
			var b := Label.new()
			b.text = apps[i][2]
			b.add_theme_font_size_override("font_size", 12)
			b.add_theme_color_override("font_color", Color.WHITE if i == 1 else DIM)
			b.add_theme_constant_override("shadow_offset_x", 0)
			b.add_theme_constant_override("shadow_offset_y", 0)
			b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			if i == 1:
				var badge := ColorRect.new()
				badge.color = Color(0.85, 0.15, 0.12)
				badge.size = Vector2(10, 10)
				badge.position = Vector2(SCREEN.x - 18, 6)
				badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(badge)
				b.position = Vector2(SCREEN.x - 18, 3)
				b.size = Vector2(10, 10)
			else:
				b.position = Vector2(SCREEN.x - 28, 4)
				b.size = Vector2(22, 10)
			row.add_child(b)
	softkeys.text = "E: mở   Q: về"

func _view_todo() -> void:
	_header("Việc cần làm")
	var rt := _scroll_text()
	var txt := ""
	if GameState.objectives.is_empty():
		txt = "[color=#808890](Không có việc gì)[/color]"
	for o in GameState.objectives:
		if o.done:
			txt += "[color=#707478][s]· %s[/s][/color]\n" % str(o.text).replace("[", "[lb]")
		else:
			txt += "· %s\n" % str(o.text).replace("[", "[lb]")
	rt.text = txt
	softkeys.text = "W/S: cuộn  Q: về"

func _view_threads() -> void:
	_header("Tin nhắn")
	var threads := _threads()
	if threads.is_empty():
		_label("(Không có tin nhắn)", 14, DIM, Vector2(4, 20), SCREEN.x - 8)
	var first := clampi(sel - 3, 0, maxi(threads.size() - 4, 0))
	for i in range(first, mini(first + 4, threads.size())):
		var th: Dictionary = threads[i]
		var y := 17 + (i - first) * 30
		var row := _row(Vector2(1, y), Vector2(SCREEN.x - 2, 29), i)
		var name := Label.new()
		name.text = th.name
		name.add_theme_font_size_override("font_size", 14)
		name.add_theme_color_override("font_color", Color.WHITE if th.unread > 0 else TEXT)
		name.add_theme_constant_override("shadow_offset_x", 0)
		name.add_theme_constant_override("shadow_offset_y", 0)
		name.position = Vector2(3, -1)
		name.size = Vector2(SCREEN.x - 48, 14)
		name.clip_text = true
		row.add_child(name)
		var last := Dialogue.get_message(th.ids[-1])
		var prev := Label.new()
		prev.text = str(last.get("text", ""))
		prev.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		prev.clip_text = true
		prev.add_theme_font_size_override("font_size", 12)
		prev.add_theme_color_override("font_color", DIM)
		prev.add_theme_constant_override("shadow_offset_x", 0)
		prev.add_theme_constant_override("shadow_offset_y", 0)
		prev.position = Vector2(3, 12)
		prev.size = Vector2(SCREEN.x - 10, 12)
		row.add_child(prev)
		var tm := Label.new()
		tm.text = str(last.get("time", ""))
		tm.add_theme_font_size_override("font_size", 12)
		tm.add_theme_color_override("font_color", HOLO if th.unread > 0 else DIM)
		tm.add_theme_constant_override("shadow_offset_x", 0)
		tm.add_theme_constant_override("shadow_offset_y", 0)
		tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tm.size = Vector2(30, 12)
		tm.position = Vector2(SCREEN.x - 9 - maxf(tm.get_minimum_size().x, 30), 0)
		row.add_child(tm)
		if th.unread > 0:
			var dot := ColorRect.new()
			dot.color = HOLO
			dot.size = Vector2(3, 3)
			dot.position = Vector2(SCREEN.x - 6, 15)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(dot)
	softkeys.text = "E: đọc   Q: về"

func _view_thread() -> void:
	var th: Dictionary = {}
	for t in _threads():
		if t.from == thread_from:
			th = t
	_header(Dialogue.speaker_name(thread_from))
	var rt := _scroll_text()
	var txt := ""
	for id in th.get("ids", []):
		var m := Dialogue.get_message(id)
		txt += "[color=#5aa8c8]%s[/color]\n%s\n\n" % [str(m.get("time", "")), str(m.get("text", "")).replace("[", "[lb]")]
		if not GameState.get_flag("read_" + id):
			GameState.set_flag("read_" + id, true)
	rt.text = txt.strip_edges()
	softkeys.text = "W/S: cuộn  Q: về"
	await get_tree().process_frame
	if scroll and is_instance_valid(scroll):
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

func _scroll_text() -> RichTextLabel:
	scroll = ScrollContainer.new()
	scroll.position = Vector2(2, 17)
	scroll.size = Vector2(SCREEN.x - 4, content.size.y - 18)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	content.add_child(scroll)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.custom_minimum_size = Vector2(SCREEN.x - 6, 0)
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.add_theme_font_size_override("normal_font_size", 14)
	rt.add_theme_constant_override("shadow_offset_x", 0)
	rt.add_theme_constant_override("shadow_offset_y", 0)
	rt.add_theme_constant_override("line_separation", -2)
	scroll.add_child(rt)
	return rt

func _row(pos: Vector2, size: Vector2, index: int) -> Control:
	var row := ColorRect.new()
	row.color = Color(0, 0, 0, 0)
	row.position = pos
	row.size = size
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_entered.connect(func():
		if sel != index:
			sel = index
			_highlight())
	row.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			sel = index
			_activate())
	content.add_child(row)
	row.set_meta("idx", index)
	items.append(row)
	return row

func _highlight() -> void:
	for r in items:
		(r as ColorRect).color = Color(HOLO, 0.35) if r.get_meta("idx", -1) == sel else Color(0, 0, 0, 0)

# ------------------------------------------------------------------ notifications
func _on_message(msg_id: String) -> void:
	AudioDirector.play_sfx("phone_vibrate", -2.0)
	_shake = 0.6
	if is_open:
		if view == View.THREAD and Dialogue.get_message(msg_id).get("from", "") == thread_from:
			_refresh()
		elif view != View.THREAD:
			_refresh()
		return
	var m := Dialogue.get_message(msg_id)
	notif_label.text = "» Tin nhắn mới: " + Dialogue.speaker_name(str(m.get("from", "?")))
	notif.visible = true
	notif.reset_size()
	var w := notif.size.x
	notif.position = Vector2(640, 404)
	var t := notif.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(notif, "position:x", 640 - w - 12, 0.25)
	t.tween_interval(3.5)
	t.tween_property(notif, "position:x", 640.0, 0.3)
	t.tween_callback(func(): notif.visible = false)

func _process(dt: float) -> void:
	if _shake > 0.0:
		_shake -= dt
		var off := Vector2(randf_range(-2, 2), randf_range(-1, 1)).round() if _shake > 0.0 else Vector2.ZERO
		if is_open:
			body.position.x = 640 - BODY_SIZE.x - 14 + off.x
		if notif.visible:
			notif.position.y = 404 + off.y
	if is_open and Engine.get_process_frames() % 30 == 0:
		status_time.text = GameState.clock_string()


## Tiny pixel-art icons drawn with rects (VT323 has no symbol glyphs).
class PixelIcon extends Control:
	var kind := ""
	var color := Color.WHITE
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _px(x: int, y: int, w := 1, h := 1) -> void:
		draw_rect(Rect2(x, y, w, h), color)
	func _draw() -> void:
		match kind:
			"signal":
				_px(0, 5, 2, 2); _px(3, 3, 2, 4); _px(6, 1, 2, 6)
			"battery":
				_px(0, 0, 9, 1); _px(0, 5, 9, 1); _px(0, 0, 1, 6); _px(8, 0, 1, 6); _px(9, 2, 1, 2)
				_px(2, 2, 2, 2)
			"todo":
				for r in 3:
					_px(0, r * 3, 2, 2); _px(3, r * 3, 7, 1)
			"mail":
				_px(0, 0, 10, 1); _px(0, 7, 10, 1); _px(0, 0, 1, 8); _px(9, 0, 1, 8)
				_px(1, 1); _px(2, 2); _px(3, 3); _px(4, 4, 2, 1); _px(6, 3); _px(7, 2); _px(8, 1)
			"torch":
				_px(0, 2, 5, 4); _px(5, 1, 2, 6); _px(7, 0, 1, 8); _px(9, 1); _px(9, 4, 1, 1); _px(9, 7)
			"back":
				_px(0, 3, 1, 1); _px(1, 2, 1, 3); _px(2, 1, 1, 5); _px(3, 0, 1, 7); _px(4, 3, 3, 1)
			"home":
				_px(0, 0, 7, 1); _px(0, 6, 7, 1); _px(0, 0, 1, 7); _px(6, 0, 1, 7)
			"menu":
				_px(0, 0, 7, 1); _px(0, 3, 7, 1); _px(0, 6, 7, 1)
