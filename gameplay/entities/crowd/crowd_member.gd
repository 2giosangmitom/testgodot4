class_name CrowdMember
extends CharacterBody3D
## One statue-like person in a CrowdGroup. Frozen on a pose ("living": waiting, sweeping, sitting).
## All behaviour is driven by the parent CrowdGroup; the member only knows how to turn its head in
## snappy steps, run stiffly toward a point, and walk back to its post.

@export_enum("wait", "sweep", "sit", "idle", "stand_stare") var pose := "wait"
## Time in the pose animation to freeze on (< 0 = random).
@export var pose_time := -1.0
## Character glb (assets/models/chars/<name>.glb). Empty -> `model_name` lookup -> placeholder.
@export var model_scene: PackedScene
@export var model_name := ""
## Randomize placeholder clothes (>= 0 = seed).
@export var look_seed := -1

var post := Transform3D()
var rng := RandomNumberGenerator.new()

var _turn_from := Vector2.ZERO
var _turn_to := Vector2.ZERO
var _turn_step := 3
var _turn_timer := 0.0
var _stall := 0.0
var _stutter_t := 0.0
var _lurch := false
var _foot_t := 0.0
var _moving := false

@onready var body: EntityBody = $Body
@onready var agent: NavigationAgent3D = get_node_or_null("NavAgent")

func _ready() -> void:
	collision_layer = 8
	collision_mask = 1
	if look_seed >= 0:
		rng.seed = look_seed
	else:
		rng.randomize()
	if model_scene == null:
		model_scene = EntityBase.find_char_model(model_name)
	if model_scene == null:
		_random_look()
	body.build(model_scene)
	post = global_transform
	freeze()

func _random_look() -> void:
	var shirts := [Color(0.35, 0.33, 0.3), Color(0.22, 0.26, 0.3), Color(0.5, 0.48, 0.42),
		Color(0.3, 0.22, 0.2), Color(0.18, 0.2, 0.18), Color(0.55, 0.55, 0.52)]
	body.shirt_color = shirts[rng.randi() % shirts.size()]
	body.pants_color = Color(0.1, 0.1, 0.12).lerp(Color(0.25, 0.22, 0.18), rng.randf())
	body.skin_color = Color(0.6, 0.5, 0.42).lerp(Color(0.5, 0.4, 0.33), rng.randf())
	body.hair = "long" if rng.randf() < 0.35 else "short"
	body.eyes = "hollow" if rng.randf() < 0.2 else "normal"

## Freeze on the pose (statue).
func freeze() -> void:
	_moving = false
	var t := pose_time if pose_time >= 0.0 else rng.randf_range(0.0, 1.5)
	body.freeze_pose(pose, t)

func remember_post() -> void:
	post = global_transform

func chest_position() -> Vector3:
	return global_position + Vector3.UP * 1.2 * body.height_scale

func horizontal_distance_to(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()

# ------------------------------------------------------------------ head

## Steps the head toward `target` (or back to rest when null) in 3 discrete snaps.
func update_head(target: Variant, delta: float, max_yaw: float, interval: float) -> void:
	var desired := Vector2.ZERO
	if target is Vector3:
		var head := body.get_head_global_position()
		var t: Vector3 = target
		var yaw := wrapf(EntityObservation.yaw_to(global_position, t) - global_rotation.y, -PI, PI)
		var flat := Vector2(t.x - head.x, t.z - head.z).length()
		var pitch := atan2(t.y - head.y, maxf(flat, 0.01))
		desired = Vector2(clampf(yaw, -max_yaw, max_yaw), clampf(pitch, -0.6, 0.5))
	var current := Vector2(body.head_yaw, body.head_pitch)
	if _turn_step >= 3:
		if current.distance_to(desired) <= 0.06:
			return
		_turn_from = current
		_turn_to = desired
		_turn_step = 0
		_turn_timer = interval      # first snap happens right now
	_turn_timer += delta
	if _turn_timer >= interval:
		_turn_timer = 0.0
		_turn_step += 1
		var v := _turn_from.lerp(_turn_to, _turn_step / 3.0)
		body.set_head_yaw(v.x)
		body.set_head_pitch(v.y)

func is_head_turning() -> bool:
	return _turn_step < 3

# ------------------------------------------------------------------ movement

## One frame of broken, stiff running toward `target`.
func chase_step(target: Vector3, speed: float, delta: float) -> void:
	if not _moving:
		_moving = true
		body.play_anim("stiff_run")
	if _stall > 0.0:
		_stall -= delta
		body.set_anim_speed(0.0)
		return
	_stutter_t -= delta
	if _stutter_t <= 0.0:
		_stutter_t = 0.15
		if rng.randf() < 0.14:
			_stall = rng.randf_range(0.06, 0.22)     # frame skip / stutter
			_lurch = true
			return
	body.set_anim_speed(rng.randf_range(0.8, 1.6))
	var dir := _steer_dir(target)
	if dir == Vector3.ZERO:
		return
	rotation.y = snappedf(atan2(-dir.x, -dir.z), PI / 4.0)       # snap rotations
	var mult := 1.8 if _lurch else 1.0
	_lurch = false
	_move(dir * speed * delta * mult)
	_foot_t -= delta
	if _foot_t <= 0.0:
		_foot_t = 0.34
		AudioDirector.play_sfx_3d("footstep_stiff_%d" % (1 + rng.randi() % 2), global_position, -6.0,
			rng.randf_range(0.95, 1.05), "Entity")

## Walks stiffly back to the post. Returns true when arrived (then frozen again).
func return_step(speed: float, delta: float) -> bool:
	var to := post.origin - global_position
	to.y = 0.0
	if to.length() <= maxf(speed * delta, 0.12):
		global_transform = post
		body.set_head_yaw(0.0)
		body.set_head_pitch(0.0)
		_turn_step = 3
		freeze()
		return true
	if not _moving or body.get_anim() != "walk":
		_moving = true
		body.play_anim("walk", 0.7)
	var dir := _steer_dir(post.origin)
	rotation.y = snappedf(atan2(-dir.x, -dir.z), PI / 4.0)
	_move(dir * speed * delta)
	_foot_t -= delta
	if _foot_t <= 0.0:
		_foot_t = 0.6
		AudioDirector.play_sfx_3d("footstep_stiff_%d" % (1 + rng.randi() % 2), global_position, -10.0, 0.9, "Entity")
	return false

func is_at_post() -> bool:
	return horizontal_distance_to(post.origin) <= 0.13

func _nav_ready() -> bool:
	if agent == null or not is_inside_tree():
		return false
	var map := get_world_3d().navigation_map
	return NavigationServer3D.map_get_iteration_id(map) > 0 and not NavigationServer3D.map_get_regions(map).is_empty()

func _steer_dir(target: Vector3) -> Vector3:
	var d := target - global_position
	d.y = 0.0
	if d.length() < 0.001:
		return Vector3.ZERO
	if _nav_ready():
		agent.target_position = target
		var nxt := agent.get_next_path_position() - global_position
		nxt.y = 0.0
		if nxt.length() > 0.05:
			return nxt.normalized()
	d = d.normalized()
	if not _blocked(d):
		return d
	for a in [0.6, -0.6, 1.2, -1.2, 1.9, -1.9]:
		var dd := d.rotated(Vector3.UP, a)
		if not _blocked(dd):
			return dd
	return d

func _blocked(dir: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var from := global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 0.9, 1, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _move(motion: Vector3) -> void:
	if not is_inside_tree():
		position += motion
		return
	var col := move_and_collide(motion)
	if col:
		var rem := col.get_remainder().slide(col.get_normal())
		rem.y = 0.0
		move_and_collide(rem)
	# stay on the floor
	var from := global_position + Vector3.UP * 0.8
	var q := PhysicsRayQueryParameters3D.create(from, global_position + Vector3.DOWN * 1.2, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position.y = hit.position.y
