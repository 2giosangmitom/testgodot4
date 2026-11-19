class_name FadeLayer
extends CanvasLayer
## Full-screen black overlay driven by EventBus.fade_request -> emits EventBus.fade_done.
## Used by the HUD (every level) and the main menu. Starts opaque when a level transition is
## in progress so a scene change behind a fade never flashes.

var rect: ColorRect
var _tween: Tween

func _init() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	rect = ColorRect.new()
	rect.color = Color.BLACK
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	var start_black: bool = ChapterDirector.get("transitioning") == true
	rect.modulate.a = 1.0 if start_black else 0.0
	EventBus.fade_request.connect(fade)

func fade(to_black: bool, duration: float) -> void:
	if _tween:
		_tween.kill()
	var target := 1.0 if to_black else 0.0
	if duration <= 0.0:
		rect.modulate.a = target
		EventBus.fade_done.emit()
		return
	_tween = create_tween()
	_tween.tween_property(rect, "modulate:a", target, duration)
	_tween.tween_callback(EventBus.fade_done.emit)

func set_black(on: bool) -> void:
	if _tween:
		_tween.kill()
	rect.modulate.a = 1.0 if on else 0.0
