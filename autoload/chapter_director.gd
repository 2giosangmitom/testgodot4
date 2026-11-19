extends Node
## Owns scene flow: level loading with fades, player spawning, and running chapter scripts.
## Phase 3 fills chapters/chN.gd; each chapter script extends ChapterScript and implements run().

const PLAYER_SCENE := "res://player/player.tscn"
const LEVELS := {
	"school": "res://levels/school/school.tscn",
	"store_alley": "res://levels/store_alley/store_alley.tscn",
	"dorm_shrine": "res://levels/dorm_shrine/dorm_shrine.tscn",
}

var current_level: Node = null
var current_chapter: Node = null
var transitioning := false
var _handling_death := false

const CAUGHT_FALLBACK_TIMEOUT := 6.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.player_caught.connect(_on_player_caught)

## Chapter number from a checkpoint id like "ch2_dorm" (0 if unknown).
static func chapter_of(checkpoint_id: String) -> int:
	if checkpoint_id.begins_with("ch") and checkpoint_id.length() > 2:
		return int(checkpoint_id.substr(2, 1))
	return 0

## Main menu "Tiếp tục".
func continue_from_checkpoint() -> void:
	var id := SaveSystem.load_checkpoint()
	var ch := chapter_of(id)
	if ch == 0:
		GameState.reset()
		await start_chapter(1)
	else:
		await start_chapter(ch, id)

## Main menu "Chọn chương".
func start_new_at(chapter: int) -> void:
	GameState.reset()
	SaveSystem.clear_checkpoint()
	await start_chapter(chapter)

func _on_player_caught(_entity_id: String, _cause: String) -> void:
	if _handling_death or GameState.debug_autoplay:
		return
	_handling_death = true
	GameState.lock_input("dead")
	# Normal path: CaughtSequence finishes (~2.5 s + fade) and emits entity_state_changed(id, "caught_done").
	# Fallback: if nothing reports completion (e.g. Player.kill without a sequence), reload after a timeout.
	var done := [false]
	var cb := func(_id: String, state: String):
		if state == "caught_done":
			done[0] = true
	EventBus.entity_state_changed.connect(cb)
	var t := 0.0
	while not done[0] and t < CAUGHT_FALLBACK_TIMEOUT:
		await get_tree().process_frame
		t += get_process_delta_time()
	EventBus.entity_state_changed.disconnect(cb)
	await get_tree().create_timer(0.3).timeout
	RenderSettings.set_static(0.0)
	AudioDirector.stop_voice()
	EventBus.subtitle_clear.emit()
	GameState.input_locks.clear()
	_handling_death = false
	await continue_from_checkpoint()

func return_to_menu() -> void:
	if current_chapter:
		current_chapter.queue_free()
		current_chapter = null
	get_tree().paused = false
	GameState.input_locks.clear()
	AudioDirector.stop_all_ambience(0.5)
	AudioDirector.stop_music(0.5)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")

## Loads a level by id (see LEVELS) or path, applies a lighting preset and spawns the player.
func goto_level(level: String, spawn := "default", preset := "", fade := 0.8) -> Node:
	transitioning = true
	GameState.lock_input("transition")
	if fade > 0.0:
		EventBus.fade_request.emit(true, fade)
		await get_tree().create_timer(fade).timeout
	var path: String = LEVELS.get(level, level)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("ChapterDirector: cannot load " + path)
	await get_tree().process_frame
	await get_tree().process_frame
	current_level = get_tree().current_scene
	if preset != "" and current_level.has_method("apply_preset"):
		current_level.apply_preset(preset)
	if spawn != "" and current_level.has_method("spawn_player"):
		current_level.spawn_player(spawn)
	if fade > 0.0:
		EventBus.fade_request.emit(false, fade)
	GameState.unlock_input("transition")
	transitioning = false
	return current_level

## Runs chapters/ch<n>.gd (or an ending script path) as a child node.
func start_chapter(n: int, from_checkpoint := "") -> void:
	await run_script("res://chapters/ch%d.gd" % n, from_checkpoint)

func run_script(path: String, from_checkpoint := "") -> void:
	if current_chapter:
		current_chapter.set_meta("cancelled", true)
		current_chapter.queue_free()
	var script: Script = load(path)
	if script == null:
		push_error("ChapterDirector: missing " + path)
		return
	current_chapter = script.new()
	add_child(current_chapter)
	await current_chapter.run(from_checkpoint)

func get_marker(name: String) -> Node3D:
	if current_level and current_level.has_method("get_marker"):
		return current_level.get_marker(name)
	return null
