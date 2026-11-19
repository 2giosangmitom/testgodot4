class_name CrowdGroup
extends EntityBase
## "Đám Đông" — a group of statue-like people frozen mid-life (bus stop, sweeping, sitting).
## Holds CrowdMember children. States:
##   frozen   -> noticing  (player within notice_radius of ANY member: all heads snap-track the player)
##   any      -> chase     (noise heard / flashlight held on a member > flashlight_time)  signal `alerted`
##   chase    -> returning (chase_time elapsed, or player hidden / out of lose_range for lose_time) signal `calmed`
##   returning-> frozen    (all members back on their posts)
## Touching a member = caught.

signal alerted
signal calmed

@export_group("Notice")
@export var notice_radius := 5.0
@export var max_head_yaw_deg := 110.0
## Seconds between the 3 discrete head snaps.
@export var head_step_interval := 0.09
@export var whisper_cooldown := 6.0
@export_group("Hearing")
## Noise is heard if loudness * (1 - dist / hear_range) >= hear_threshold.
@export var hear_range := 14.0
@export var hear_threshold := 0.3
@export_group("Flashlight")
@export var flashlight_range := 8.0
@export var flashlight_half_angle := 14.0
@export var flashlight_time := 1.0
@export_group("Chase")
## Slightly above player walk, below sprint.
@export var chase_speed := 3.4
@export var return_speed := 1.2
@export var chase_time := 20.0
@export var lose_range := 16.0
@export var lose_time := 4.0
@export var touch_distance := 0.75

## Injectable line of sight for the flashlight check: Callable(from, to) -> bool.
var los_override := Callable()
var flashlight_on := false
var chase_t := 0.0
var lost_t := 0.0
var flash_t := 0.0
var _whisper_t := 0.0

func _ready() -> void:
	EventBus.noise_emitted.connect(_on_noise)
	EventBus.flashlight_toggled.connect(func(on: bool): flashlight_on = on)
	super._ready()

func _on_activate() -> void:
	for m in get_members():
		m.global_transform = m.post     # back on the post (posts are recorded in CrowdMember._ready)
		m.body.set_head_yaw(0.0)
		m.body.set_head_pitch(0.0)
		m.freeze()
	chase_t = 0.0
	flash_t = 0.0
	set_state("frozen")

func get_members() -> Array[CrowdMember]:
	var out: Array[CrowdMember] = []
	for c in get_children():
		if c is CrowdMember:
			out.append(c)
	return out

## Smallest horizontal distance from any member to `p`.
func nearest_distance(p: Vector3) -> float:
	var best := INF
	for m in get_members():
		best = minf(best, m.horizontal_distance_to(p))
	return best

static func perceived_loudness(loudness: float, dist: float, range_m: float) -> float:
	return loudness * clampf(1.0 - dist / maxf(range_m, 0.01), 0.0, 1.0)

func tick(delta: float) -> void:
	var p := get_player()
	if p == null:
		return
	_whisper_t -= delta
	var eye := get_player_eye()
	var max_yaw := deg_to_rad(max_head_yaw_deg)
	var near := nearest_distance(p.global_position)
	match state:
		"frozen", "noticing":
			var noticing := near <= notice_radius
			if noticing and state == "frozen":
				set_state("noticing")
				if _whisper_t <= 0.0:
					_whisper_t = whisper_cooldown
					AudioDirector.play_sfx_3d("entity_whisper", _center() + Vector3.UP * 1.6, -10.0, 1.0, "Entity")
			elif not noticing and state == "noticing":
				set_state("frozen")
			for m in get_members():
				m.update_head(eye if noticing else null, delta, max_yaw, head_step_interval)
			_tick_flashlight(delta)
		"chase":
			chase_t += delta
			for m in get_members():
				m.chase_step(p.global_position, chase_speed, delta)
				m.update_head(eye, delta, max_yaw, head_step_interval)
				if m.horizontal_distance_to(p.global_position) <= touch_distance \
						and absf(m.global_position.y - p.global_position.y) < 1.5 and not is_passive():
					catch_player("crowd_touch", m)
					return
			if player_is_hidden() or near > lose_range:
				lost_t += delta
			else:
				lost_t = 0.0
			if chase_t >= chase_time or lost_t >= lose_time:
				calm()
		"returning":
			var all_home := true
			for m in get_members():
				if not m.return_step(return_speed, delta):
					all_home = false
			if all_home:
				set_state("frozen")

## Starts the chase (all members).
func alert() -> void:
	if not _active or is_passive() or state in ["chase", "caught"]:
		return
	chase_t = 0.0
	lost_t = 0.0
	flash_t = 0.0
	set_state("chase")
	alerted.emit()
	AudioDirector.play_sfx("stinger_low", -4.0, 1.0, "Entity")
	AudioDirector.play_sfx_3d("entity_whisper", _center() + Vector3.UP * 1.6, 0.0, 0.8, "Entity")

## Gives up the chase; members walk back to their posts and freeze.
func calm() -> void:
	if state != "chase":
		return
	set_state("returning")
	calmed.emit()

func _tick_flashlight(delta: float) -> void:
	var on := flashlight_on or GameState.flashlight_on
	var cam := get_player_camera()
	var lit := false
	if on and cam and cam.is_inside_tree():
		var xf := cam.global_transform
		for m in get_members():
			var c := m.chest_position()
			if EntityObservation.is_in_cone(xf, c, flashlight_half_angle, flashlight_range) and _los(xf.origin, c):
				lit = true
				break
	if lit:
		flash_t += delta
		if flash_t >= flashlight_time:
			alert()
	else:
		flash_t = maxf(0.0, flash_t - delta)

func _los(a: Vector3, b: Vector3) -> bool:
	if los_override.is_valid():
		return los_override.call(a, b)
	return EntityObservation.ray_clear(get_world_3d().direct_space_state, a, b)

func _on_noise(pos: Vector3, loudness: float) -> void:
	if not _active or state in ["chase", "caught"]:
		return
	var best := INF
	for m in get_members():
		best = minf(best, m.global_position.distance_to(pos))
	if perceived_loudness(loudness, best, hear_range) >= hear_threshold:
		alert()

func _center() -> Vector3:
	var ms := get_members()
	if ms.is_empty():
		return global_position
	var c := Vector3.ZERO
	for m in ms:
		c += m.global_position
	return c / ms.size()
