class_name DebugShot
extends Node
## Screenshot helper for automated visual checks.
## Run any scene that calls DebugShot.attach_if_requested(self) with
##   godot --path . res://some_scene.tscn -- --shot=/abs/path.png [--shot_frames=60]
## It saves the main viewport after N frames and quits.

var path := ""
var frames := 60
var _n := 0

static func get_arg(name: String, default := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
		if a == "--" + name:
			return "1"
	return default

static func attach_if_requested(parent: Node) -> void:
	var p := get_arg("shot")
	if p == "":
		return
	if parent.get_tree().root.has_node("DebugShot"):
		return
	var s := DebugShot.new()
	s.name = "DebugShot"
	s.path = p
	s.frames = int(get_arg("shot_frames", "60"))
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.get_tree().root.add_child.call_deferred(s)

func _process(_dt: float) -> void:
	_n += 1
	if _n == frames:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(path)
		print("DebugShot: saved ", path)
		get_tree().quit()
