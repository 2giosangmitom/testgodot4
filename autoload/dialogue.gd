extends Node
## Loads dialogue/message data and plays lines (voice + subtitle).
## UI (Track B) only listens to EventBus.subtitle / subtitle_clear / choice_requested.
##
## Files: data/dialogue/speakers.json, data/dialogue/lines_*.json, data/dialogue/messages.json
## See docs/conventions.md for the JSON schema.

var speakers: Dictionary = {}
var lines: Dictionary = {}
var messages: Dictionary = {}
var _skip := false

const CHARS_PER_SEC := 14.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reload()

func reload() -> void:
	speakers = _load("res://data/dialogue/speakers.json")
	messages = _load("res://data/dialogue/messages.json")
	lines.clear()
	var dir := DirAccess.open("res://data/dialogue")
	if dir == null:
		return
	for f in dir.get_files():
		if f.begins_with("lines_") and f.ends_with(".json"):
			lines.merge(_load("res://data/dialogue/" + f))

func has_line(key: String) -> bool:
	return lines.has(key)

func get_line(key: String) -> Dictionary:
	return lines.get(key, {"speaker": "", "text": "[%s]" % key})

func speaker_name(id: String) -> String:
	return speakers.get(id, {}).get("name", id)

func get_message(id: String) -> Dictionary:
	return messages.get(id, {})

## Plays one line and waits until it is finished. Usage: await Dialogue.say("ch1_hung_01")
func say(key: String, extra_hold := 0.35) -> void:
	var line := get_line(key)
	var text: String = line.get("text", "")
	var voice_len := AudioDirector.play_voice(key)
	var dur: float = voice_len if voice_len > 0.0 else max(1.6, text.length() / CHARS_PER_SEC)
	if GameState.debug_autoplay:
		dur = 0.05
	EventBus.subtitle.emit(speaker_name(line.get("speaker", "")), text, dur)
	_skip = false
	var t := 0.0
	while t < dur + extra_hold and not _skip:
		await get_tree().process_frame
		t += get_process_delta_time()
	AudioDirector.stop_voice()
	EventBus.subtitle_clear.emit()

func say_seq(keys: Array) -> void:
	for k in keys:
		await say(k)

## Skips the current line (bound to "skip" in UI).
func skip_line() -> void:
	_skip = true

## Shows a choice and waits for the answer index. Usage: var i = await Dialogue.ask("...", ["A","B"])
func ask(prompt: String, options: PackedStringArray, timeout := 0.0, default_index := -1) -> int:
	if GameState.debug_autoplay:
		return max(default_index, 0)
	EventBus.choice_requested.emit(prompt, options)
	if timeout <= 0.0:
		return await EventBus.choice_made
	var result := [default_index]
	var done := [false]
	var cb := func(i: int): result[0] = i; done[0] = true
	EventBus.choice_made.connect(cb, CONNECT_ONE_SHOT)
	var t := 0.0
	while not done[0] and t < timeout:
		await get_tree().process_frame
		t += get_process_delta_time()
	if not done[0]:
		EventBus.choice_made.disconnect(cb)
		EventBus.choice_made.emit(default_index)   # lets UI close itself
	return result[0]

func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("Dialogue: bad JSON " + path)
	return {}
