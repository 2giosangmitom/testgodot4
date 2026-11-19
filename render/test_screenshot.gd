extends Node
## Screenshot helper for render tests. Run a scene containing this node with
##   godot --path . res://render/test_psx.tscn -- --shot=/abs/path.png [--shot_frame=60] [--shot_pair]
## Waits `shot_frame` frames, saves the viewport image, (with --shot_pair also saves
## <path>_b.png 3 frames later to compare vertex jitter), then quits.

var _path := ""
var _frame := 60
var _pair := false
var _count := 0
var _busy := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_path = a.substr(7)
		elif a.begins_with("--shot_frame="):
			_frame = int(a.substr(13))
		elif a == "--shot_pair":
			_pair = true
	set_process(_path != "")

func _process(_dt: float) -> void:
	_count += 1
	if _count >= _frame and not _busy:
		_busy = true
		_capture()

func _capture() -> void:
	await RenderingServer.frame_post_draw
	_save(_path)
	if _pair:
		for i in 3:
			await RenderingServer.frame_post_draw
		_save(_path.get_basename() + "_b." + _path.get_extension())
	get_tree().quit()

func _save(p: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(p)
	print("[test_screenshot] saved %s (%dx%d) err=%d" % [p, img.get_width(), img.get_height(), err])
