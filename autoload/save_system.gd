extends Node
## Checkpoint save + persistent profile (endings seen, settings).

const SAVE_PATH := "user://checkpoint.json"
const PROFILE_PATH := "user://profile.json"

var profile: Dictionary = {"endings_seen": [], "settings": {}}
var last_checkpoint_id := ""

func _ready() -> void:
	profile = _read(PROFILE_PATH, profile)

func save_checkpoint(id: String) -> void:
	last_checkpoint_id = id
	var data := {"id": id, "state": GameState.to_dict()}
	if not GameState.debug_autoplay:
		_write(SAVE_PATH, data)
	EventBus.checkpoint_reached.emit(id)

func has_checkpoint() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## Restores GameState and returns the checkpoint id ("" if none).
func load_checkpoint() -> String:
	var data := _read(SAVE_PATH, {})
	if data.is_empty():
		return ""
	GameState.from_dict(data.get("state", {}))
	last_checkpoint_id = data.get("id", "")
	return last_checkpoint_id

func clear_checkpoint() -> void:
	if has_checkpoint():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

func mark_ending_seen(ending: String) -> void:
	if not ending in profile.endings_seen:
		profile.endings_seen.append(ending)
		save_profile()

func has_seen_any_ending() -> bool:
	return not profile.endings_seen.is_empty()

func get_setting(key: String, default: Variant) -> Variant:
	return profile.settings.get(key, default)

func set_setting(key: String, value: Variant) -> void:
	profile.settings[key] = value
	save_profile()

func save_profile() -> void:
	_write(PROFILE_PATH, profile)

func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))

func _read(path: String, default: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return default.duplicate(true)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else default.duplicate(true)
