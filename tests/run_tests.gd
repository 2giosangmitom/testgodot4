extends SceneTree
## Main-session logic tests: godot --headless --path . -s res://tests/run_tests.gd

var failures := 0

func check(cond: bool, name: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + name)
	if not cond:
		failures += 1

func _initialize() -> void:
	await process_frame
	_test_dialogue_data()
	_test_voice_coverage()
	_test_checkpoint_parse()
	_test_chapter_scripts()
	_test_ending_threshold()
	print("\n%s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures else 0)

func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _all_lines() -> Dictionary:
	var lines := {}
	for f in DirAccess.get_files_at("res://data/dialogue"):
		if f.begins_with("lines_") and f.ends_with(".json") and f != "lines_test.json":
			lines.merge(_json("res://data/dialogue/" + f))
	return lines

func _test_dialogue_data() -> void:
	var speakers: Dictionary = _json("res://data/dialogue/speakers.json")
	var lines := _all_lines()
	var msgs: Dictionary = _json("res://data/dialogue/messages.json")
	check(lines.size() >= 50, "dialogue has %d lines" % lines.size())
	var bad := []
	for k in lines:
		if not speakers.has(lines[k].speaker):
			bad.append(k)
	check(bad.is_empty(), "every line speaker exists %s" % [bad])
	bad.clear()
	for m in msgs:
		if not speakers.has(msgs[m].from):
			bad.append(m)
	check(bad.is_empty(), "every message sender exists %s" % [bad])
	var readables: Variant = _json("res://data/readables.json")
	check(readables is Dictionary and readables.has("rules_note"), "readables.json parses")

func _test_voice_coverage() -> void:
	var missing := []
	for k in _all_lines():
		var ok := false
		for ext in ["ogg", "wav"]:
			if FileAccess.file_exists("res://assets/audio/voice/%s.%s" % [k, ext]):
				ok = true
		if not ok:
			missing.append(k)
	check(missing.is_empty(), "voice file for every line (missing %d: %s)" % [missing.size(), missing.slice(0, 5)])

func _test_checkpoint_parse() -> void:
	var cd := root.get_node_or_null("ChapterDirector")
	if cd == null:
		check(false, "ChapterDirector is loaded")
		return
	check(cd.chapter_of("ch2_dorm") == 2 and cd.chapter_of("ch4_shrine") == 4 and cd.chapter_of("") == 0, "checkpoint -> chapter")

func _test_chapter_scripts() -> void:
	for chapter in ["ch1", "ch2", "ch3", "ch4", "ending_a", "ending_b"]:
		var path := "res://chapters/%s.gd" % chapter
		var script := load(path) as Script
		check(script != null and script.can_instantiate(), chapter + " script compiles")

func _test_ending_threshold() -> void:
	var state := root.get_node("GameState")
	state.set_flag("shrine_lamp_relit")
	state.resolve = 5
	check(state.compute_ending() == "B", "lit lamp with insufficient resolve ends in B")
	state.resolve = 6
	check(state.compute_ending() == "A", "lit lamp with minimum resolve ends in A")
	state.set_flag("shrine_lamp_relit", false)
	check(state.compute_ending() == "B", "unlit lamp ends in B even with sufficient resolve")
