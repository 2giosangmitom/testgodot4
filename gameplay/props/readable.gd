class_name Readable
extends Interactable
## Note / notice board / poster / photo. Interact shows its text on a paper overlay
## (ui/paper_overlay.tscn) and sets GameState flag `read_<readable_id>` if an id is given.
## If `title`/`text` are empty they are loaded from data/readables.json[readable_id]
## ({title, text (BBCode), style: handwritten|printed|card|photo}).

signal closed

const DATA := "res://data/readables.json"

@export var readable_id := ""
@export var title := ""
@export_multiline var text := ""
@export_enum("printed", "handwritten", "card", "photo") var style := "printed"

func _init() -> void:
	prompt = "Đọc"

func _ready() -> void:
	super._ready()
	if text == "" and readable_id != "" and FileAccess.file_exists(DATA):
		var d = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if d is Dictionary and d.has(readable_id):
			title = d[readable_id].get("title", title)
			text = d[readable_id].get("text", "")
			style = d[readable_id].get("style", style)
	var has_col := false
	for c in get_children():
		if c is CollisionShape3D:
			has_col = true
	if not has_col:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3(0.3, 0.4, 0.05)
		cs.shape = b
		add_child(cs)

func _on_interact(_player: Node3D) -> void:
	if readable_id != "":
		GameState.set_flag("read_" + readable_id, true)
	var o := PaperOverlay.show_paper(get_tree(), title, text, style)
	o.closed.connect(closed.emit)
