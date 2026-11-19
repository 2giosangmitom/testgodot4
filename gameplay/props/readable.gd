class_name Readable
extends Interactable
## Note / notice board / poster. Interact shows its text on a paper overlay
## (ui/paper_overlay.tscn) and sets GameState flag `read_<readable_id>` if an id is given.

signal closed

@export var readable_id := ""
@export var title := ""
@export_multiline var text := ""

func _init() -> void:
	prompt = "Đọc"

func _ready() -> void:
	super._ready()
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
	var o := PaperOverlay.show_paper(get_tree(), title, text)
	o.closed.connect(closed.emit)
