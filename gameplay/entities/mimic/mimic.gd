class_name Mimic
extends EntityBase
## "Kẻ Nhại" — copies a friend (Hùng / Linh). Tells: neck tilted, arms hang below the knees,
## casts NO shadow, stands too still, breathes wrong.
##
## DOOR mode state machine (state names are emitted via EventBus.entity_state_changed):
##   idle -> knock -> talk <-> asking -> wait -> leaving -> gone           (signal `survived`)
##                       \-- answer / door opened / patience / lights --> breach -> caught  (signal `breached`)
## Survival = stay silent and keep the door shut until it gives up.
##
## CORRIDOR mode: stands at `outside_marker` facing away; turns its head when the player is within
## `notice_distance`; follows (snapping steps) only while the player is not looking; leaves when the
## player is in the room (`inside_marker`, `room_radius`) with the door closed and locked.

signal survived
signal breached

enum Mode { DOOR, CORRIDOR }

@export var mode: Mode = Mode.DOOR
@export_enum("hung", "linh") var impersonates := "hung"
## Character glb; default tries res://assets/models/chars/<impersonates>.glb, else a placeholder.
@export var model_scene: PackedScene
## Dialogue keys played one by one (Dialogue.say -> subtitle + voice).
@export var voice_lines: Array[String] = []
## Lines after which the player is asked to answer (lines whose text contains "?" also ask).
@export var ask_after_lines: Array[String] = []
@export var ask_prompt := "Trả lời?"
@export var ask_options: PackedStringArray = PackedStringArray(["Trả lời", "Im lặng"])
@export var ask_timeout := 6.0
## Door node (duck-typed: door_id, is_open()/open, lock(), is_locked()/locked, optional force_open()).
@export var door_path: NodePath
## Used when door_path is empty (EventBus-only doors).
@export var door_id := ""
## Where it stands outside the door (DOOR) / in the corridor (CORRIDOR).
@export var outside_marker: NodePath
## DOOR: where it appears on breach (in the doorway). CORRIDOR: the safe room position.
@export var inside_marker: NodePath

@export_group("Timing")
@export var start_delay := 1.0
@export var knock_pause := 4.0
@export var line_pause := 2.0
@export var wait_duration := 14.0
@export var leave_time := 4.0
## > 0: if the door is still UNLOCKED this many seconds after activation -> breach.
@export var patience := 0.0
## Door creaking open -> caught.
@export var breach_time := 2.2

@export_group("Triggers")
## Breach if `lights_group` lights are on while it waits silently at the door.
@export var breach_if_lights_on := false
@export var lights_group := ""
@export var lights_on := true
## Phone message that reveals the truth. GameState flag "read_<id>" set while talking -> on_ignored_line.
@export var truth_message_id := ""
@export var on_ignored_line := ""
@export var flicker_group := "flicker_lights"

@export_group("Corridor")
@export var notice_distance := 5.0
@export var follow_step := 0.9
@export var follow_interval := 0.8
@export var catch_distance := 0.9
@export var room_radius := 2.5

## Injectable observation for CORRIDOR mode (tests): Callable() -> bool.
var observation_override := Callable()

var line_index := 0
var cause := ""
var _t := 0.0                # time in current state
var _total := 0.0            # time since activation
var _line_left := 0.0
var _line_is_question := false
var _ask_token := 0
var _wait_events := 0
var _ignored_pending := false
var _ignored_said := false
var _step_t := 0.0
var _foot_i := 0
var _rest_xform := Transform3D()

@onready var body: EntityBody = $Body

func _ready() -> void:
	if model_scene == null:
		model_scene = find_char_model(impersonates)
	if model_scene == null:
		_style_placeholder()
	body.build(model_scene)
	body.set_shape("neck_tilt", 1.0)
	body.set_shape("long_arms", 1.0)
	body.set_cast_shadow(false)
	body.breath_wrong = true
	body.play_anim("idle")
	EventBus.door_state_changed.connect(_on_door_state_changed)
	EventBus.flag_changed.connect(_on_flag_changed)
	EventBus.lights_set.connect(_on_lights_set)
	super._ready()

func _style_placeholder() -> void:
	match impersonates:
		"linh":
			body.shirt_color = Color(0.82, 0.82, 0.78)
			body.pants_color = Color(0.1, 0.12, 0.2)
			body.hair = "long"
		_:
			body.shirt_color = Color(0.2, 0.3, 0.45)
			body.pants_color = Color(0.2, 0.2, 0.22)
			body.hair = "short"

func _on_activate() -> void:
	_total = 0.0
	line_index = 0
	cause = ""
	_ignored_pending = false
	_ignored_said = false
	body.set_shape("face_distort", 0.0)
	body.set_head_yaw(0.0)
	var m := node3d(outside_marker)
	if m:
		global_transform = Transform3D(Basis(Vector3.UP, m.global_rotation.y), m.global_position)
	_rest_xform = global_transform
	_enter("idle" if mode == Mode.DOOR else "corridor")

func _on_deactivate() -> void:
	_ask_token += 1

# ------------------------------------------------------------------ door helpers (duck-typed)

func get_door() -> Node:
	return get_node_or_null(door_path) if not door_path.is_empty() else null

func get_door_id() -> String:
	var d := get_door()
	if d and "door_id" in d:
		return str(d.door_id)
	return door_id

func door_is_open() -> bool:
	var d := get_door()
	if d == null:
		return false
	if d.has_method("is_open"):
		return d.is_open()
	if "open" in d:
		return bool(d.get("open"))
	return false

func door_is_locked() -> bool:
	var d := get_door()
	if d == null:
		return false
	if d.has_method("is_locked"):
		return d.is_locked()
	if "locked" in d:
		return bool(d.get("locked"))
	return false

func _door_force_open() -> void:
	var d := get_door()
	if d == null:
		return
	if d.has_method("force_open"):
		d.force_open(breach_time)
	elif d.has_method("open_slowly"):
		d.open_slowly()
	elif d.has_method("set_open"):
		d.set_open(true)
	elif "open" in d:
		d.set("open", true)
	elif d.has_method("open"):
		d.open()
	elif d is Node3D:
		create_tween().tween_property(d, "rotation:y", (d as Node3D).rotation.y + deg_to_rad(80.0), breach_time)
	EventBus.door_state_changed.emit(get_door_id(), true)

func _door_pos() -> Vector3:
	var d := get_door()
	if d is Node3D:
		return (d as Node3D).global_position + Vector3.UP * 1.2
	return global_position + Vector3.UP * 1.2

# ------------------------------------------------------------------ state machine

func _enter(s: String) -> void:
	_t = 0.0
	set_state(s)
	match s:
		"knock":
			_knock(false)
		"talk":
			_line_left = 0.0
		"wait":
			_wait_events = 0
			body.play_anim("idle")
		"leaving":
			_step_t = 0.0
			_foot_i = 0
			body.play_anim("walk")
		"breach":
			_start_breach_fx()

func tick(delta: float) -> void:
	if is_passive():
		delta *= 6.0     # autoplay: hurry through the encounter, never breach
	_t += delta
	_total += delta
	match state:
		"idle":
			if _t >= start_delay:
				_enter("knock")
		"knock":
			if _t >= knock_pause:
				_enter("talk" if not voice_lines.is_empty() else "wait")
		"talk":
			_tick_talk(delta)
		"asking":
			_check_patience()
		"wait":
			_tick_wait()
		"leaving":
			_tick_leaving(delta)
		"breach":
			_tick_breach()
		"corridor", "noticed", "following":
			_tick_corridor(delta)

func _tick_talk(delta: float) -> void:
	if _check_patience():
		return
	_line_left -= delta
	if _line_left > 0.0:
		return
	if _line_is_question:
		_line_is_question = false
		_start_ask()
		return
	if _ignored_pending and on_ignored_line != "":
		_ignored_pending = false
		_ignored_said = true
		_say(on_ignored_line)
		return
	if line_index >= voice_lines.size():
		_enter("wait")
		return
	var key := voice_lines[line_index]
	line_index += 1
	_say(key)

func _say(key: String) -> void:
	Dialogue.say(key)
	var dur := _line_duration(key)
	_line_is_question = is_question(key)
	# questions are asked right after the line; others get a pause before the next
	_line_left = dur if _line_is_question else dur + line_pause
	body.play_anim("idle")

func is_question(key: String) -> bool:
	if key in ask_after_lines:
		return true
	return String(Dialogue.get_line(key).get("text", "")).contains("?")

func _line_duration(key: String) -> float:
	if GameState.debug_autoplay:
		return 0.4
	var text: String = Dialogue.get_line(key).get("text", "")
	var dur := maxf(1.6, text.length() / Dialogue.CHARS_PER_SEC)
	if ResourceLoader.exists("res://assets/audio/voice/%s.ogg" % key) or ResourceLoader.exists("res://assets/audio/voice/%s.wav" % key):
		var s := AudioDirector.get_stream("voice", key)
		if s:
			dur = s.get_length()
	return dur + 0.4

func _start_ask() -> void:
	_enter("asking")
	_ask_token += 1
	var tok := _ask_token
	var i: int = await Dialogue.ask(ask_prompt, ask_options, ask_timeout, 1)
	if tok != _ask_token or state != "asking" or not _active:
		return
	answered(i)

## Result of the "answer?" choice (0 = answered -> breach). Public for tests / custom UI.
func answered(i: int) -> void:
	if state != "asking":
		return
	if i == 0 and not is_passive():
		begin_breach("answered")
	else:
		_enter("talk")
		_line_left = line_pause

func _tick_wait() -> void:
	if _check_patience():
		return
	if breach_if_lights_on and lights_on and not is_passive():
		begin_breach("lights_on")
		return
	var k := _t / maxf(wait_duration, 0.01)
	if _wait_events == 0 and k >= 0.15:
		_wait_events = 1
		AudioDirector.play_sfx_3d("door_handle_rattle", _door_pos(), 0.0, 1.0, "Entity")
	elif _wait_events == 1 and k >= 0.45:
		_wait_events = 2
		AudioDirector.play_sfx_3d("entity_whisper", _door_pos(), -6.0, 0.9, "Entity")
	elif _wait_events == 2 and k >= 0.7:
		_wait_events = 3
		_knock(true)
	if _t >= wait_duration:
		_enter("leaving")

func _knock(slow: bool) -> void:
	AudioDirector.play_sfx_3d("door_knock_slow" if slow else "door_knock_3", _door_pos(), 0.0, 1.0, "SFX")
	EventBus.door_knock.emit(get_door_id())
	body.play_anim("knock")

func _tick_leaving(delta: float) -> void:
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = 0.55
		_foot_i += 1
		# footsteps walking away from the door
		var away := global_basis.z.normalized()
		var pos := global_position + away * (0.6 * _foot_i)
		var vol := -2.0 - 2.0 * _foot_i
		AudioDirector.play_sfx_3d("footstep_stiff_%d" % (1 + _foot_i % 2), pos, vol, 1.0, "Entity")
		if mode == Mode.CORRIDOR:
			global_position = pos
	if _t >= leave_time:
		_survive()

func _survive() -> void:
	set_state("gone")
	survived.emit()
	deactivate()

func _check_patience() -> bool:
	if patience > 0.0 and _total >= patience and not door_is_locked() and not is_passive():
		begin_breach("patience")
		return true
	return false

# ------------------------------------------------------------------ breach

## Door opens slowly by itself, it stands in the doorway, lights flicker, face distorts -> caught.
func begin_breach(reason: String) -> void:
	if is_passive() or state in ["breach", "caught", "gone", "inactive"]:
		return
	cause = reason
	_ask_token += 1
	_enter("breach")
	breached.emit()

func _start_breach_fx() -> void:
	Dialogue.skip_line()
	AudioDirector.stop_voice()
	if not door_is_open():
		AudioDirector.play_sfx_3d("door_open_creak", _door_pos(), 0.0, 0.85, "SFX")
		_door_force_open()
	var m := node3d(inside_marker)
	if m and mode == Mode.DOOR:
		global_position = m.global_position
	_face_player()
	body.play_anim("stand_stare")
	EventBus.lights_flicker.emit(flicker_group, breach_time)
	AudioDirector.play_sfx_3d("entity_whisper", global_position + Vector3.UP * 1.6, 0.0, 0.8, "Entity")

func _tick_breach() -> void:
	body.set_shape("face_distort", clampf(_t / maxf(breach_time, 0.01), 0.0, 1.0) * 0.6)
	if _t >= breach_time:
		catch_player("mimic_" + cause, self)

func _face_player() -> void:
	var p := get_player()
	if p:
		rotation.y = EntityObservation.yaw_to(global_position, p.global_position)

# ------------------------------------------------------------------ corridor mode

func _tick_corridor(delta: float) -> void:
	var p := get_player()
	if p == null:
		return
	var to := p.global_position - global_position
	if absf(to.y) > 1.75:
		return
	to.y = 0.0
	var dist := to.length()
	# safe: player in the room with the door shut and locked
	var room := node3d(inside_marker)
	if room and not door_is_open() and door_is_locked() \
			and p.global_position.distance_to(room.global_position) <= room_radius:
		_enter("leaving")
		return
	if dist <= catch_distance and not is_passive():
		catch_player("mimic_corridor", self)
		return
	if state == "corridor":
		if dist <= notice_distance:
			_enter("noticed")
			AudioDirector.play_sfx_3d("entity_whisper", body.get_head_global_position(), -8.0, 1.0, "Entity")
		return
	# head turns toward the player (unnaturally far)
	var rel := wrapf(EntityObservation.yaw_to(global_position, p.global_position) - rotation.y, -PI, PI)
	rel = clampf(rel, -2.9, 2.9)
	body.set_head_yaw(move_toward(body.head_yaw, rel, 1.6 * delta))
	if state == "noticed" and _t > 1.0:
		_enter("following")
	if state == "following":
		_step_t -= delta
		if _step_t <= 0.0 and not _observed_by_player() and not is_passive():
			_step_t = follow_interval
			var step := minf(follow_step, maxf(dist - catch_distance * 0.5, 0.0))
			global_position += to.normalized() * step
			_face_player()
			body.set_head_yaw(0.0)
			AudioDirector.play_sfx_3d("footstep_stiff_%d" % (1 + randi() % 2), global_position, -4.0, 1.0, "Entity")

func _observed_by_player() -> bool:
	if observation_override.is_valid():
		return observation_override.call()
	var cam := get_player_camera()
	if cam == null or not cam.is_inside_tree():
		return false
	var vp := cam.get_viewport().get_visible_rect().size
	var los := func(a: Vector3, b: Vector3) -> bool:
		return EntityObservation.ray_clear(get_world_3d().direct_space_state, a, b)
	return EntityObservation.is_observed(cam.global_transform, cam.fov, vp.x / maxf(vp.y, 1.0),
		body.get_sample_points(), EntityObservation.fog_visible_distance() * 0.95, 4.0, los)

func is_directly_observed() -> bool:
	var cam := get_player_camera()
	if cam == null or not cam.is_inside_tree():
		return false
	var direction := (body.get_head_global_position() - cam.global_position).normalized()
	return -cam.global_basis.z.dot(direction) > 0.97 and _observed_by_player()

# ------------------------------------------------------------------ event listeners

func _on_door_state_changed(id: String, open: bool) -> void:
	if not _active or not open or mode != Mode.DOOR:
		return
	if id != get_door_id() or id == "":
		return
	if state in ["knock", "talk", "asking", "wait", "leaving"]:
		begin_breach("door_opened")

func _on_flag_changed(flag: String, value: Variant) -> void:
	if not _active or truth_message_id == "" or _ignored_said:
		return
	if flag == "read_" + truth_message_id and value and state in ["talk", "asking", "wait"]:
		_ignored_pending = true
		if state == "wait":
			_enter("talk")
			_line_left = 0.5

func _on_lights_set(group_name: String, on: bool) -> void:
	if lights_group != "" and group_name == lights_group:
		lights_on = on
