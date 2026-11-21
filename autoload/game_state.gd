extends Node
## Run-time story state. Serialized by SaveSystem at checkpoints.

var chapter: int = 0
var phase: String = "day"              # "day" | "night"
var flags: Dictionary = {}
var resolve: int = 0                   # accumulated "kept the rules" score -> ending
var resolve_log: Array = []
var objectives: Array = []             # [{id, text, done}]
var unlocked_messages: Array[String] = []
var clock_minutes: int = 8 * 60        # in-game clock shown on the phone
var player: Node3D = null
var input_locks: Dictionary = {}       # reason -> true
var flashlight_on := false
var phone_open := false
var debug_autoplay := false
var autoplay_ending := "A"

const RESOLVE_ENDING_A := 6            # >= this -> Ending A "Bình minh"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	debug_autoplay = "--autoplay" in args
	for arg in args:
		if arg.begins_with("--ending="):
			autoplay_ending = arg.trim_prefix("--ending=").to_upper()

func reset() -> void:
	chapter = 0
	phase = "day"
	flags.clear()
	resolve = 0
	resolve_log.clear()
	objectives.clear()
	unlocked_messages.clear()
	clock_minutes = 8 * 60
	input_locks.clear()
	flashlight_on = false
	phone_open = false

# --- flags ---
func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value
	EventBus.flag_changed.emit(flag, value)

func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(flag, default)

# --- resolve / ending ---
func add_resolve(delta: int, reason: String) -> void:
	resolve += delta
	resolve_log.append({"delta": delta, "reason": reason, "chapter": chapter})
	EventBus.resolve_changed.emit(resolve, delta, reason)

func compute_ending() -> String:
	if get_flag("shrine_lamp_relit") and resolve >= RESOLVE_ENDING_A:
		return "A"
	return "B"

# --- objectives ---
func add_objective(id: String, text: String) -> void:
	for o in objectives:
		if o.id == id:
			return
	objectives.append({"id": id, "text": text, "done": false})
	EventBus.objective_added.emit(id, text)

func complete_objective(id: String) -> void:
	for o in objectives:
		if o.id == id and not o.done:
			o.done = true
			EventBus.objective_completed.emit(id)

func is_objective_done(id: String) -> bool:
	for o in objectives:
		if o.id == id:
			return o.done
	return false

func clear_objectives() -> void:
	objectives.clear()

# --- phone messages ---
func unlock_message(msg_id: String) -> void:
	if msg_id in unlocked_messages:
		return
	unlocked_messages.append(msg_id)
	EventBus.message_received.emit(msg_id)

# --- clock ---
func set_clock(hours: int, minutes: int = 0) -> void:
	clock_minutes = hours * 60 + minutes

func clock_string() -> String:
	return "%02d:%02d" % [(clock_minutes / 60) % 24, clock_minutes % 60]

# --- input locking (cutscenes, minigames, phone, death) ---
func lock_input(reason: String) -> void:
	input_locks[reason] = true

func unlock_input(reason: String) -> void:
	input_locks.erase(reason)

func is_input_locked() -> bool:
	return not input_locks.is_empty()

# --- serialization ---
func to_dict() -> Dictionary:
	return {
		"chapter": chapter, "phase": phase, "flags": flags, "resolve": resolve,
		"resolve_log": resolve_log, "objectives": objectives,
		"unlocked_messages": unlocked_messages, "clock_minutes": clock_minutes,
	}

func from_dict(d: Dictionary) -> void:
	chapter = int(d.get("chapter", 0))
	phase = d.get("phase", "day")
	flags = d.get("flags", {})
	resolve = int(d.get("resolve", 0))
	resolve_log = d.get("resolve_log", [])
	objectives = d.get("objectives", [])
	unlocked_messages.assign(d.get("unlocked_messages", []))
	clock_minutes = int(d.get("clock_minutes", 480))
