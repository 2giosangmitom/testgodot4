class_name MinigameMop
extends MinigameBase
## "Lau sàn" — pick up the mop (hold). While held, the mop head rests on the floor in front of the
## player; moving / turning with the head over a stain scrubs it (opacity drops, mop_squeak).
## All stains clean -> completed. Optional haunted stain (haunted_stain_index) comes back once after
## being cleaned (signal haunted_event, stinger) and must be cleaned again.
##
## Anchors: MopSpot (where the mop leans) · stain_* Marker3Ds on the floor (origin = floor point).
## Stain visual: stain_scene (if it has set_dirt(v 0..1) that is called, else GeometryInstance3D
## transparency / Decal modulate is driven) or a procedural alpha quad.

signal stain_cleaned(index: int)
signal haunted_event

@export var stain_prefix := "stain_"
## -1 = use every stain marker.
@export var stain_count := -1
@export var haunted_stain_index := -1
@export var haunted_delay := 3.0
## Dirt removed per metre of mop-head travel over a stain (1.0 = fully dirty).
@export var scrub_per_meter := 0.45
@export var stain_radius := 0.42
## Mop head distance in front of the player's feet.
@export var mop_reach := 0.85
@export var mop_model: PackedScene
@export var stain_scene: PackedScene
@export var stain_texture: Texture2D
@export var stain_size := 0.9

var mop: MinigameItem
var stains: Array[Dictionary] = []    # {node, dirt, marker, haunted_done}
var _last_head := Vector3.INF
var _squeak_cd := 0.0
var _haunt_timer := -1.0
var _haunt_fired := false
var _mop_len := 1.25

# ---------------------------------------------------------------- setup
func _build_placeholder() -> void:
	var ph := Node3D.new()
	ph.name = "Placeholder"
	add_child(ph)
	var spot := get_anchor("MopSpot")
	if spot:
		var bucket := MinigameUtil.cylinder(0.16, 0.3, Color(0.2, 0.35, 0.6), Vector3.ZERO, 10)
		ph.add_child(bucket)
		bucket.global_position = spot.global_position + spot.global_basis.x * 0.35 + Vector3(0, 0.15, 0)

func _setup() -> void:
	mop = MinigameItem.new()
	mop.name = "Mop"
	mop.pickup_prompt = "Cầm cây lau nhà"
	mop.return_home_on_release = true
	mop.self_rotate = false
	var m := MinigameUtil.instance_model(mop_model)
	if m:
		mop.add_child(m)
	else:
		# local +Y = handle up, origin = mop head on the floor
		mop.add_child(MinigameUtil.cylinder(0.014, _mop_len, Color(0.55, 0.45, 0.3), Vector3(0, _mop_len * 0.5 + 0.06, 0), 6))
		mop.add_child(MinigameUtil.box(Vector3(0.3, 0.05, 0.08), Color(0.25, 0.25, 0.28), Vector3(0, 0.06, 0)))
		for k in 6:
			var strand := MinigameUtil.box(Vector3(0.05, 0.06, 0.07), Color(0.82, 0.8, 0.72), Vector3(-0.125 + k * 0.05, 0.02, 0))
			mop.add_child(strand)
	MinigameUtil.add_box_collider(mop, Vector3(0.3, _mop_len, 0.12), Vector3(0, _mop_len * 0.5, 0))
	add_child(mop)
	var spot := get_anchor("MopSpot")
	if spot:
		# leaning against the wall
		mop.global_transform = spot.global_transform * Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3.ZERO)
	mop.remember_home()

func _make_stains() -> void:
	for s in stains:
		if is_instance_valid(s.node):
			s.node.queue_free()
	stains.clear()
	var markers := get_anchors(stain_prefix)
	var n := markers.size() if stain_count < 0 else mini(stain_count, markers.size())
	for i in n:
		var mk: Node3D = markers[i]
		var node := _make_stain_visual(i)
		add_child(node)
		node.global_position = mk.global_position + Vector3(0, 0.004, 0)
		node.global_basis = mk.global_basis
		stains.append({"node": node, "dirt": 1.0, "marker": mk})
		_apply_dirt(i)

func _make_stain_visual(i: int) -> Node3D:
	var inst := MinigameUtil.instance_model(stain_scene)
	if inst:
		return inst
	var mi := MeshInstance3D.new()
	mi.name = "Stain%d" % i
	var pm := PlaneMesh.new()
	pm.size = Vector2(stain_size, stain_size) * randf_range(0.85, 1.15)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_texture = stain_texture if stain_texture else MinigameUtil.stain_texture(1234 + i * 77)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.y = randf() * TAU
	return mi

func _apply_dirt(i: int) -> void:
	var s: Dictionary = stains[i]
	var node: Node = s.node
	var dirt: float = s.dirt
	if node.has_method("set_dirt"):
		node.set_dirt(dirt)
		return
	_apply_dirt_rec(node, dirt, s.get("haunted_done", false))

func _apply_dirt_rec(node: Node, dirt: float, haunted: bool) -> void:
	if node is Decal:
		node.modulate.a = dirt
	elif node is MeshInstance3D and node.material_override is StandardMaterial3D:
		var mat := node.material_override as StandardMaterial3D
		mat.albedo_color = Color(0.45, 0.08, 0.06, dirt) if haunted else Color(1, 1, 1, dirt)
	elif node is GeometryInstance3D:
		node.transparency = 1.0 - dirt
	for c in node.get_children():
		_apply_dirt_rec(c, dirt, haunted)

# ---------------------------------------------------------------- flow
func _on_start() -> void:
	_make_stains()
	_haunt_timer = -1.0
	_haunt_fired = false
	_last_head = Vector3.INF
	mop.pickable = true
	mop.enabled = true

func _on_reset() -> void:
	if mop.is_held():
		mop.release_from_player(false)
	for s in stains:
		if is_instance_valid(s.node):
			s.node.queue_free()
	stains.clear()

func _on_complete() -> void:
	if mop.is_held():
		mop.release_from_player(false)
	mop.top_level = false

## Where the mop head touches the floor for the current player pose.
func mop_head_point() -> Vector3:
	var p := get_player()
	if p == null:
		return global_position
	var fwd: Vector3
	var cam: Camera3D = p.get_camera() if p.has_method("get_camera") else null
	fwd = -(cam.global_basis.z if cam else p.global_basis.z)
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = -p.global_basis.z
	fwd = fwd.normalized()
	var floor_y := global_position.y
	if not stains.is_empty():
		floor_y = (stains[0].marker as Node3D).global_position.y
	var pt := p.global_position + fwd * mop_reach
	pt.y = floor_y
	return pt

func _tick(delta: float) -> void:
	_squeak_cd = maxf(_squeak_cd - delta, 0.0)
	if _haunt_timer >= 0.0:
		_haunt_timer -= delta
		if _haunt_timer < 0.0:
			_haunt_reappear()
	if mop.is_held():
		var head := mop_head_point()
		_pose_mop(head)
		if _last_head != Vector3.INF:
			var moved := Vector2(head.x - _last_head.x, head.z - _last_head.z).length()
			if moved < 0.5:
				scrub_at(head, moved)
		_last_head = head
	else:
		if mop.top_level:
			mop.top_level = false
		_last_head = Vector3.INF
	_check_done()

## Mop head stands on the floor; handle leans back toward the player's hand.
func _pose_mop(head: Vector3) -> void:
	var p := get_player()
	if not mop.top_level:
		mop.top_level = true
	var hand := p.global_position + Vector3(0, 1.05, 0)
	if p.has_method("get_hold_point") and p.get_hold_point():
		hand = p.get_hold_point().global_position
	var up := (hand - head).normalized()
	var side := up.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var fwd := side.cross(up).normalized()
	mop.global_transform = Transform3D(Basis(side, up, -fwd).orthonormalized(), head)

## Scrubs every stain under `point` by `distance` metres of mop travel.
func scrub_at(point: Vector3, distance: float) -> void:
	if distance <= 0.0005:
		return
	var scrubbed := false
	for i in stains.size():
		var s: Dictionary = stains[i]
		if s.dirt <= 0.0:
			continue
		var c: Vector3 = (s.node as Node3D).global_position
		if Vector2(point.x - c.x, point.z - c.z).length() > stain_radius:
			continue
		s.dirt = maxf(0.0, s.dirt - distance * scrub_per_meter)
		if s.dirt < 0.03:
			s.dirt = 0.0
		_apply_dirt(i)
		scrubbed = true
		if s.dirt == 0.0:
			_on_stain_clean(i)
	if scrubbed and _squeak_cd <= 0.0 and distance > 0.004:
		sfx("mop_squeak", mop, -3.0, randf_range(0.9, 1.12))
		_squeak_cd = 0.55

func _on_stain_clean(i: int) -> void:
	stain_cleaned.emit(i)
	if i == haunted_stain_index and not _haunt_fired:
		_haunt_timer = haunted_delay

func _haunt_reappear() -> void:
	if haunted_stain_index < 0 or haunted_stain_index >= stains.size():
		return
	_haunt_fired = true
	var s: Dictionary = stains[haunted_stain_index]
	s.dirt = 1.0
	s["haunted_done"] = true
	_apply_dirt(haunted_stain_index)
	sfx("stinger_low", s.node, -4.0)
	haunted_event.emit()

func _check_done() -> void:
	if stains.is_empty() or _haunt_timer >= 0.0:
		return
	for s in stains:
		if s.dirt > 0.0:
			return
	complete()

func dirt_left() -> float:
	var t := 0.0
	for s in stains:
		t += s.dirt
	return t

# ---------------------------------------------------------------- debug / tests
func _autoplay() -> void:
	for i in stains.size():
		await get_tree().create_timer(0.1).timeout
		if not _active:
			return
		scrub_at((stains[i].node as Node3D).global_position, 10.0)
	if _haunt_timer >= 0.0:
		_haunt_timer = 0.0
		_tick(0.01)
		scrub_at((stains[haunted_stain_index].node as Node3D).global_position, 10.0)
	_check_done()

func debug_shot_prep(player: Node3D) -> void:
	mop.pick_up(player)
	if stains.size() > 1:
		scrub_at((stains[0].node as Node3D).global_position, 1.0)
		scrub_at((stains[1].node as Node3D).global_position, 1.4)
