extends CanvasLayer
## In-game HUD (instanced by the Player). Crosshair, interact prompt, stamina, toasts,
## subtitles (typewriter), choices, letterbox, fade, plus the phone and pause menu.

const THEME := preload("res://ui/theme.tres")
const PHONE_SCENE := "res://ui/phone/phone.tscn"
const PAUSE_SCENE := "res://ui/pause_menu.tscn"

const SPEAKER_COLORS := {
	"Nam": Color(0.95, 0.88, 0.55),
	"Hùng": Color(0.55, 0.78, 1.0),
	"Linh": Color(1.0, 0.68, 0.78),
	"Bác Tư bảo vệ": Color(0.7, 0.88, 0.55),
	"Chị Hạnh": Color(1.0, 0.72, 0.45),
	"Thầy Khải": Color(0.75, 0.75, 0.95),
	"Bà cụ": Color(0.85, 0.7, 0.6),
	"Mẹ": Color(1.0, 0.85, 0.7),
	"Radio": Color(0.65, 0.65, 0.65),
	"???": Color(0.9, 0.18, 0.15),
}
const ACCENT := Color(1, 0.62, 0.25)

var root: Control
var crosshair: Crosshair
var prompt_label: Label
var stamina_bar: ProgressBar
var toast_box: VBoxContainer
var sub_panel: PanelContainer
var sub_label: RichTextLabel
var choice_panel: PanelContainer
var choice_prompt: Label
var choice_list: VBoxContainer
var lb_top: ColorRect
var lb_bottom: ColorRect
var fade_layer: FadeLayer
var phone: Node
var pause_menu: Node

var _sub_total := 0
var _sub_prefix := 0
var _sub_rate := 14.0
var _sub_t := 0.0
var _sub_active := false
var _choice_count := 0
var _letterbox := false
var _last_objective_text := ""
var _last_objective_ms := 0

func _ready() -> void:
	layer = 100
	add_to_group("hud")
	root = Control.new()
	root.name = "Root"
	root.theme = THEME
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_build_letterbox()
	_build_crosshair()
	_build_stamina()
	_build_toasts()
	_build_subtitles()
	_build_choices()
	fade_layer = FadeLayer.new()
	fade_layer.name = "Fade"
	add_child(fade_layer)
	if ResourceLoader.exists(PHONE_SCENE):
		phone = load(PHONE_SCENE).instantiate()
		add_child(phone)
	if ResourceLoader.exists(PAUSE_SCENE):
		pause_menu = load(PAUSE_SCENE).instantiate()
		add_child(pause_menu)
	EventBus.interact_prompt.connect(_on_prompt)
	EventBus.subtitle.connect(show_subtitle)
	EventBus.subtitle_clear.connect(clear_subtitle)
	EventBus.choice_requested.connect(show_choice)
	EventBus.choice_made.connect(func(_i: int): _hide_choice())
	EventBus.letterbox.connect(set_letterbox)
	EventBus.toast.connect(_on_toast)
	EventBus.objective_added.connect(_on_objective_added)
	EventBus.objective_completed.connect(_on_objective_completed)
	EventBus.checkpoint_reached.connect(func(_id: String): toast("Đã lưu tiến trình", Color(0.6, 0.6, 0.6)))
	EventBus.player_caught.connect(func(_e: String, _c: String): _on_prompt(""); clear_subtitle(); _hide_choice())

# ------------------------------------------------------------------ build
func _build_crosshair() -> void:
	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	prompt_label = Label.new()
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 16)
	prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	prompt_label.offset_left = -200
	prompt_label.offset_right = 200
	prompt_label.offset_top = 14
	prompt_label.offset_bottom = 34
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prompt_label)

func _build_stamina() -> void:
	stamina_bar = ProgressBar.new()
	stamina_bar.show_percentage = false
	stamina_bar.max_value = 100
	stamina_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	stamina_bar.offset_left = -70
	stamina_bar.offset_right = 70
	stamina_bar.offset_top = -10
	stamina_bar.offset_bottom = -7
	stamina_bar.custom_minimum_size = Vector2(0, 3)
	stamina_bar.modulate.a = 0.0
	stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stamina_bar)

func _build_toasts() -> void:
	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	toast_box.position = Vector2(12, 10)
	toast_box.size = Vector2(380, 10)
	toast_box.add_theme_constant_override("separation", 2)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)

func _build_subtitles() -> void:
	sub_panel = PanelContainer.new()
	sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub_panel.custom_minimum_size = Vector2(540, 0)
	sub_panel.offset_left = -270
	sub_panel.offset_right = 270
	sub_panel.offset_bottom = -22
	sub_panel.offset_top = -22
	sub_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.72)
	sb.set_content_margin_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.anti_aliasing = false
	sub_panel.add_theme_stylebox_override("panel", sb)
	sub_label = RichTextLabel.new()
	sub_label.bbcode_enabled = true
	sub_label.fit_content = true
	sub_label.scroll_active = false
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_label.add_theme_font_size_override("normal_font_size", 18)
	sub_label.custom_minimum_size = Vector2(520, 0)
	sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_panel.add_child(sub_label)
	sub_panel.visible = false
	root.add_child(sub_panel)

func _build_choices() -> void:
	choice_panel = PanelContainer.new()
	choice_panel.add_to_group("ui_cursor")
	choice_panel.set_anchors_preset(Control.PRESET_CENTER)
	choice_panel.custom_minimum_size = Vector2(360, 0)
	choice_panel.offset_left = -180
	choice_panel.offset_right = 180
	choice_panel.offset_top = 40
	choice_panel.offset_bottom = 40
	choice_panel.grow_vertical = Control.GROW_DIRECTION_END
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	choice_panel.add_child(v)
	choice_prompt = Label.new()
	choice_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	choice_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choice_prompt.add_theme_font_size_override("font_size", 18)
	choice_prompt.add_theme_color_override("font_color", ACCENT)
	choice_prompt.custom_minimum_size = Vector2(340, 0)
	v.add_child(choice_prompt)
	choice_list = VBoxContainer.new()
	choice_list.add_theme_constant_override("separation", 0)
	v.add_child(choice_list)
	choice_panel.visible = false
	root.add_child(choice_panel)

func _build_letterbox() -> void:
	lb_top = ColorRect.new()
	lb_bottom = ColorRect.new()
	for r in [lb_top, lb_bottom]:
		r.color = Color.BLACK
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(r)
	lb_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	lb_bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	lb_top.offset_bottom = 0
	lb_bottom.offset_top = 0

# ------------------------------------------------------------------ prompt / crosshair
func _on_prompt(text: String) -> void:
	if text == "":
		prompt_label.text = ""
		crosshair.set_active(false)
	else:
		prompt_label.text = "[E] " + text
		crosshair.set_active(true)

# ------------------------------------------------------------------ toasts
func toast(text: String, color := Color(0.86, 0.84, 0.78), seconds := 4.0) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	l.modulate.a = 0.0
	toast_box.add_child(l)
	while toast_box.get_child_count() > 4:
		toast_box.get_child(0).free()
	var t := l.create_tween()
	t.tween_property(l, "modulate:a", 1.0, 0.25)
	t.tween_interval(seconds)
	t.tween_property(l, "modulate:a", 0.0, 0.8)
	t.tween_callback(l.queue_free)

func _on_toast(text: String) -> void:
	# ChapterScript.objective() emits objective_added AND toast(text): avoid a duplicate.
	if text == _last_objective_text and Time.get_ticks_msec() - _last_objective_ms < 1500:
		return
	toast(text)

func _on_objective_added(_id: String, text: String) -> void:
	_last_objective_text = text
	_last_objective_ms = Time.get_ticks_msec()
	toast("Nhiệm vụ: " + text, ACCENT, 5.0)
	AudioDirector.play_sfx("ui_select", -10.0)

func _on_objective_completed(id: String) -> void:
	for o in GameState.objectives:
		if o.id == id:
			toast("Đã xong: " + str(o.text), Color(0.6, 0.6, 0.55), 3.0)

# ------------------------------------------------------------------ subtitles
func show_subtitle(speaker: String, text: String, duration: float) -> void:
	if not SaveSystem.get_setting("subtitles", true):
		return
	var prefix := ""
	if speaker != "":
		var c: Color = SPEAKER_COLORS.get(speaker, _hash_color(speaker))
		prefix = "[color=#%s]%s:[/color] " % [c.to_html(false), _escape(speaker)]
		_sub_prefix = speaker.length() + 2
	else:
		_sub_prefix = 0
	sub_label.text = prefix + _escape(text)
	_sub_total = sub_label.get_total_character_count()
	var body := maxi(_sub_total - _sub_prefix, 1)
	_sub_rate = maxf(body / maxf(duration * 0.6, 0.05), 10.0)
	_sub_t = 0.0
	_sub_active = true
	sub_label.visible_characters = _sub_prefix
	sub_panel.visible = true
	_fit_bottom.call_deferred()

func _fit_bottom() -> void:
	# keep the box anchored to the bottom and exactly as tall as its (fully revealed) text
	await get_tree().process_frame
	var vc := sub_label.visible_characters
	sub_label.visible_characters = -1
	var h := clampi(sub_label.get_content_height(), 18, 140) + 12
	sub_label.visible_characters = vc
	sub_panel.offset_top = sub_panel.offset_bottom - h
	sub_panel.size.y = h

func _fit_choice() -> void:
	var h := choice_panel.get_combined_minimum_size().y
	choice_panel.offset_bottom = choice_panel.offset_top + h

func clear_subtitle() -> void:
	_sub_active = false
	sub_panel.visible = false

func is_subtitle_visible() -> bool:
	return sub_panel.visible

func _hash_color(s: String) -> Color:
	var h := float(abs(s.hash()) % 360) / 360.0
	return Color.from_hsv(h, 0.35, 0.95)

func _escape(s: String) -> String:
	return s.replace("[", "[lb]")

# ------------------------------------------------------------------ choices
func show_choice(prompt: String, options: PackedStringArray) -> void:
	for c in choice_list.get_children():
		c.queue_free()
	choice_prompt.text = prompt
	choice_prompt.visible = prompt != ""
	_choice_count = options.size()
	for i in options.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, options[i]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_pick.bind(i))
		b.mouse_entered.connect(b.grab_focus)
		choice_list.add_child(b)
	choice_panel.visible = true
	_fit_choice.call_deferred()
	AudioDirector.play_sfx("ui_move", -8.0)

func _pick(i: int) -> void:
	if not choice_panel.visible:
		return
	AudioDirector.play_sfx("ui_select", -6.0)
	_hide_choice()
	EventBus.choice_made.emit(i)

func _hide_choice() -> void:
	choice_panel.visible = false
	_choice_count = 0

func is_choice_open() -> bool:
	return choice_panel.visible

# ------------------------------------------------------------------ letterbox
func set_letterbox(on: bool) -> void:
	_letterbox = on
	var h := 52.0 if on else 0.0
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	t.tween_property(lb_top, "offset_bottom", h, 0.6)
	t.tween_property(lb_bottom, "offset_top", -h, 0.6)
	crosshair.visible = not on
	prompt_label.visible = not on

# ------------------------------------------------------------------ input / update
func _input(event: InputEvent) -> void:
	if choice_panel.visible and event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_9 and k - KEY_1 < _choice_count:
			_pick(k - KEY_1)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("skip") and sub_panel.visible and not get_tree().paused:
		Dialogue.skip_line()
		get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	if _sub_active:
		_sub_t += dt
		var n := _sub_prefix + int(_sub_t * _sub_rate)
		sub_label.visible_characters = mini(n, _sub_total)
	var p := GameState.player
	if p and is_instance_valid(p) and "stamina" in p:
		stamina_bar.value = p.stamina
		var want := 0.0 if p.stamina >= 99.9 else 0.8
		stamina_bar.modulate.a = move_toward(stamina_bar.modulate.a, want, dt * 3.0)
		stamina_bar.self_modulate = Color(1, 0.45, 0.35) if p.get("exhausted") else Color.WHITE


## Center dot that grows into a small bracket when something is targeted.
class Crosshair extends Control:
	var active := false
	var k := 0.0
	func set_active(on: bool) -> void:
		active = on
	func _process(dt: float) -> void:
		var target := 1.0 if active else 0.0
		if not is_equal_approx(k, target):
			k = move_toward(k, target, dt * 8.0)
			queue_redraw()
	func _draw() -> void:
		var c := Color(0.9, 0.88, 0.8, 0.75 + 0.25 * k)
		var s := 1.0 + roundf(k)
		draw_rect(Rect2(Vector2(-s, -s), Vector2(s * 2, s * 2)), c)
		if k > 0.05:
			var r := roundf(3.0 + 3.0 * k)
			draw_rect(Rect2(Vector2(-r, -r), Vector2(r * 2, r * 2)), Color(c, k * 0.7), false, 1.0)
