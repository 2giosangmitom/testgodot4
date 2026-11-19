class_name EntityBody
extends Node3D
## Visual body of an entity (the `Body` node). Instances a character glb (`model_scene`) or, until
## Track C delivers models, builds a low-poly placeholder humanoid from primitives.
##
## Model contract (assets/models/chars/<name>.glb): AnimationPlayer with
##   idle walk run stiff_run sit sweep wait knock stand_stare
## Skeleton3D with a bone named `head`, shape keys `neck_tilt long_arms face_distort`.
## The placeholder emulates all of these procedurally so gameplay code is identical.

const LOOPING := ["idle", "walk", "run", "stiff_run", "sit", "sweep", "wait", "knock", "stand_stare"]
const SHAPE_KEYS := ["neck_tilt", "long_arms", "face_distort"]

@export var model_scene: PackedScene
## Uniform scale of the whole body (Gazer = 1.2: "20% taller").
@export var height_scale := 1.0
@export var head_bone_name := "head"
@export_group("Placeholder look")
@export var skin_color := Color(0.62, 0.52, 0.44)
@export var shirt_color := Color(0.30, 0.32, 0.34)
@export var pants_color := Color(0.12, 0.12, 0.14)
@export var hair_color := Color(0.05, 0.04, 0.04)
@export_enum("short", "long", "none") var hair := "short"
@export_enum("normal", "wide", "hollow") var eyes := "normal"

var model: Node3D
var anim_player: AnimationPlayer
var skeleton: Skeleton3D
var head_bone := -1
var is_placeholder := true

var head_yaw := 0.0
var head_pitch := 0.0
var shapes := {"neck_tilt": 0.0, "long_arms": 0.0, "face_distort": 0.0}
var breath_wrong := false

var _head_mod: HeadTurnModifier
var _parts := {}                 # placeholder pivots / meshes by name
var _anim := "idle"
var _anim_t := 0.0
var _anim_speed := 1.0
var _paused := false
var _breath_t := 0.0
var _breath_next := 2.0
var _mat_cache := {}
var _built := false

func _ready() -> void:
	# The owning entity normally calls build(model) in its own _ready; build here only if nobody did.
	_build_if_needed.call_deferred()

func _build_if_needed() -> void:
	if not _built:
		build()

## (Re)builds the visual. Call after changing model_scene.
func build(scene: PackedScene = null) -> void:
	if scene != null:
		model_scene = scene
	_built = true
	if model:
		model.queue_free()
		model = null
	anim_player = null
	skeleton = null
	head_bone = -1
	_parts.clear()
	scale = Vector3.ONE * height_scale
	if model_scene:
		model = model_scene.instantiate()
		model.name = "Model"
		add_child(model)
		is_placeholder = false
		_scan_model()
	else:
		is_placeholder = true
		model = _build_placeholder()
		add_child(model)
	for k in shapes:
		set_shape(k, shapes[k])
	play_anim(_anim)

# ---------------------------------------------------------------- public API

func play_anim(anim_name: String, speed := 1.0, from_time := -1.0) -> void:
	_anim = anim_name
	_anim_speed = speed
	_paused = false
	if from_time >= 0.0:
		_anim_t = from_time
	if anim_player:
		var real := _resolve_anim(anim_name)
		if real == "":
			return
		var a := anim_player.get_animation(real)
		if a and anim_name in LOOPING:
			a.loop_mode = Animation.LOOP_LINEAR
		if anim_player.current_animation != real or not anim_player.is_playing():
			anim_player.play(real)
		anim_player.speed_scale = speed
		if from_time >= 0.0:
			anim_player.seek(from_time, true)

## Plays `anim_name` at `t` seconds and freezes on that pose (Crowd statues).
func freeze_pose(anim_name: String, t := 0.0) -> void:
	play_anim(anim_name, 1.0, t)
	pause_anim()
	if is_placeholder:
		_update_placeholder(0.0)

func pause_anim() -> void:
	_paused = true
	if anim_player:
		anim_player.pause()

func resume_anim() -> void:
	_paused = false
	if anim_player:
		anim_player.play()

func set_anim_speed(s: float) -> void:
	_anim_speed = s
	if anim_player:
		anim_player.speed_scale = s

func get_anim() -> String:
	return _anim

## Head yaw in radians relative to the body (positive = to the body's left, Godot convention).
func set_head_yaw(rad: float) -> void:
	head_yaw = rad
	_apply_head()

func set_head_pitch(rad: float) -> void:
	head_pitch = rad
	_apply_head()

## Sets a shape key (0..1) on every mesh that has it. Placeholder emulates the three standard keys.
## `face_distort` also drives a `distort` shader parameter on materials that declare one.
func set_shape(key: String, value: float) -> void:
	shapes[key] = value
	if key == "face_distort":
		set_distort(value)
	if is_placeholder:
		_apply_placeholder_shapes()
		_apply_head()
		return
	for mi in get_meshes():
		var idx := mi.find_blend_shape_by_name(key)
		if idx >= 0:
			mi.set_blend_shape_value(idx, value)

func get_shape(key: String) -> float:
	return shapes.get(key, 0.0)

func set_distort(value: float) -> void:
	for mi in get_meshes():
		var mats: Array = []
		if mi.material_override:
			mats.append(mi.material_override)
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s)
				if m:
					mats.append(m)
		for m in mats:
			if m is ShaderMaterial and m.shader and _shader_has_param(m.shader, "distort"):
				m.set_shader_parameter("distort", value)

func set_cast_shadow(on: bool) -> void:
	for mi in get_meshes():
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func get_meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if model:
		for n in model.find_children("*", "MeshInstance3D", true, false):
			out.append(n)
		if model is MeshInstance3D:
			out.append(model)
	return out

## World position of the face (between the eyes).
func get_head_global_position() -> Vector3:
	if is_placeholder and _parts.has("head_mesh"):
		var h: Node3D = _parts.head_mesh
		return h.global_position
	if skeleton and head_bone >= 0:
		var p := skeleton.get_bone_global_pose(head_bone).origin
		return skeleton.to_global(p) + Vector3.UP * 0.08 * height_scale
	return global_position + Vector3.UP * 1.62 * height_scale

## Points used for visibility checks (head, chest, knees).
func get_sample_points() -> Array:
	var base := global_position
	var head := get_head_global_position()
	return [head, base.lerp(head, 0.6), base + Vector3.UP * 0.4 * height_scale]

func get_height() -> float:
	return 1.75 * height_scale

# ---------------------------------------------------------------- internals

func _process(delta: float) -> void:
	if is_placeholder:
		_update_placeholder(delta)

func _resolve_anim(n: String) -> String:
	if anim_player == null:
		return ""
	if anim_player.has_animation(n):
		return n
	var low := n.to_lower()
	for a in anim_player.get_animation_list():
		var al := String(a).to_lower()
		if al == low or al.ends_with("/" + low) or al.ends_with("|" + low) or al.ends_with("_" + low):
			return a
	return ""

func _scan_model() -> void:
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		anim_player = aps[0]
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty():
		skeleton = sks[0]
		head_bone = skeleton.find_bone(head_bone_name)
		if head_bone < 0:
			for i in skeleton.get_bone_count():
				if skeleton.get_bone_name(i).to_lower().contains("head"):
					head_bone = i
					break
		if head_bone >= 0:
			_head_mod = HeadTurnModifier.new()
			_head_mod.bone_idx = head_bone
			skeleton.add_child(_head_mod)

func _apply_head() -> void:
	if is_placeholder:
		if _parts.has("head"):
			var h: Node3D = _parts.head
			h.rotation = Vector3(head_pitch, head_yaw, shapes.neck_tilt * 0.62)
	elif _head_mod:
		_head_mod.yaw = head_yaw
		_head_mod.pitch = head_pitch

static func _shader_has_param(sh: Shader, p: String) -> bool:
	for u in sh.get_shader_uniform_list():
		if u.get("name", "") == p:
			return true
	return false

# ---------------------------------------------------------------- placeholder humanoid

func _mat(c: Color) -> StandardMaterial3D:
	if _mat_cache.has(c):
		return _mat_cache[c]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_mat_cache[c] = m
	return m

func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, col: Color, nm := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(col)
	if nm != "":
		mi.name = nm
	parent.add_child(mi)
	return mi

func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 6
	c.rings = 1
	return c

func _pivot(parent: Node3D, nm: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	parent.add_child(n)
	_parts[nm] = n
	return n

func _build_placeholder() -> Node3D:
	var root := Node3D.new()
	root.name = "Placeholder"
	var hips := _pivot(root, "hips", Vector3(0, 0.95, 0))
	# legs
	for side in [-1, 1]:
		var leg := _pivot(hips, "leg_l" if side < 0 else "leg_r", Vector3(0.1 * side, 0, 0))
		_mesh(leg, _capsule(0.075, 0.95), Vector3(0, -0.47, 0), pants_color)
		_mesh(leg, _box(Vector3(0.1, 0.06, 0.22)), Vector3(0, -0.92, -0.04), Color(0.06, 0.06, 0.06))
	var torso := _pivot(hips, "torso", Vector3.ZERO)
	_parts["torso_mesh"] = _mesh(torso, _capsule(0.19, 0.66), Vector3(0, 0.3, 0), shirt_color)
	_mesh(torso, _capsule(0.05, 0.12), Vector3(0, 0.6, 0), skin_color)   # neck
	# arms (pivot at shoulder; scale.y stretches them -> long_arms)
	for side in [-1, 1]:
		var arm := _pivot(torso, "arm_l" if side < 0 else "arm_r", Vector3(0.235 * side, 0.54, 0))
		_mesh(arm, _capsule(0.055, 0.58), Vector3(0, -0.29, 0), shirt_color)
		_mesh(arm, _box(Vector3(0.07, 0.11, 0.06)), Vector3(0, -0.62, 0), skin_color)
	# head (pivot at neck)
	var head := _pivot(torso, "head", Vector3(0, 0.62, 0))
	var head_mesh := _mesh(head, _box(Vector3(0.21, 0.25, 0.23)), Vector3(0, 0.12, 0), skin_color, "HeadMesh")
	_parts["head_mesh"] = head_mesh
	var face := Node3D.new()
	face.name = "Face"
	face.position = Vector3(0, 0, -0.116)
	head_mesh.add_child(face)
	_parts["face"] = face
	var dark := Color(0.02, 0.02, 0.02)
	for side in [-1, 1]:
		var eye := Node3D.new()
		eye.position = Vector3(0.05 * side, 0.025, 0)
		face.add_child(eye)
		match eyes:
			"wide":
				_mesh(eye, _box(Vector3(0.055, 0.04, 0.01)), Vector3.ZERO, Color(0.85, 0.84, 0.78))
				_mesh(eye, _box(Vector3(0.02, 0.02, 0.012)), Vector3(0, 0, -0.002), dark)
			"hollow":
				_mesh(eye, _box(Vector3(0.05, 0.05, 0.012)), Vector3.ZERO, Color(0, 0, 0))
			_:
				_mesh(eye, _box(Vector3(0.035, 0.022, 0.01)), Vector3.ZERO, dark)
		_parts["eye_l" if side < 0 else "eye_r"] = eye
	_mesh(face, _box(Vector3(0.022, 0.05, 0.03)), Vector3(0, -0.02, -0.01), skin_color.darkened(0.1))  # nose
	_parts["mouth"] = _mesh(face, _box(Vector3(0.075, 0.014, 0.01)), Vector3(0, -0.07, 0), Color(0.2, 0.05, 0.05))
	match hair:
		"short":
			_mesh(head_mesh, _box(Vector3(0.23, 0.07, 0.25)), Vector3(0, 0.13, 0.01), hair_color)
			_mesh(head_mesh, _box(Vector3(0.23, 0.2, 0.05)), Vector3(0, 0.04, 0.105), hair_color)
		"long":
			_mesh(head_mesh, _box(Vector3(0.24, 0.07, 0.26)), Vector3(0, 0.13, 0.01), hair_color)
			_mesh(head_mesh, _box(Vector3(0.25, 0.48, 0.06)), Vector3(0, -0.08, 0.11), hair_color)
			for side in [-1, 1]:
				_mesh(head_mesh, _box(Vector3(0.03, 0.36, 0.2)), Vector3(0.115 * side, -0.04, 0.02), hair_color)
	return root

func _apply_placeholder_shapes() -> void:
	if _parts.is_empty():
		return
	var la: float = shapes.long_arms
	for a in ["arm_l", "arm_r"]:
		(_parts[a] as Node3D).scale = Vector3(1.0 - 0.15 * la, 1.0 + 0.75 * la, 1.0 - 0.15 * la)
	var fd: float = shapes.face_distort
	var hm: Node3D = _parts.head_mesh
	hm.scale = Vector3(1.0 + 0.2 * fd, 1.0 + 0.45 * fd, 1.0 + 0.1 * fd)
	(_parts.mouth as Node3D).scale = Vector3(1.0 + 0.4 * fd, 1.0 + 9.0 * fd, 1.0)
	for e in ["eye_l", "eye_r"]:
		(_parts[e] as Node3D).scale = Vector3(1.0 + 0.6 * fd, 1.0 + 2.5 * fd, 1.0)

func _update_placeholder(delta: float) -> void:
	if _parts.is_empty():
		return
	if not _paused:
		_anim_t += delta * _anim_speed
	var t := _anim_t
	var hips: Node3D = _parts.hips
	var torso: Node3D = _parts.torso
	var al: Node3D = _parts.arm_l
	var ar: Node3D = _parts.arm_r
	var ll: Node3D = _parts.leg_l
	var lr: Node3D = _parts.leg_r
	hips.position = Vector3(0, 0.95, 0)
	torso.rotation = Vector3.ZERO
	al.rotation = Vector3(0, 0, -0.06)
	ar.rotation = Vector3(0, 0, 0.06)
	ll.rotation = Vector3.ZERO
	lr.rotation = Vector3.ZERO
	match _anim:
		"walk", "run":
			var amp := 0.45 if _anim == "walk" else 0.8
			var s := sin(t * (6.0 if _anim == "walk" else 10.0))
			ll.rotation.x = s * amp
			lr.rotation.x = -s * amp
			al.rotation.x = -s * amp * 0.7
			ar.rotation.x = s * amp * 0.7
			if _anim == "run":
				torso.rotation.x = -0.2
		"stiff_run":
			# legs in hard steps, arms rigid at the sides, torso bent forward
			var s := signf(sin(t * 9.0))
			ll.rotation.x = s * 0.6
			lr.rotation.x = -s * 0.6
			torso.rotation.x = -0.3
			hips.position.y = 0.95 - absf(sin(t * 9.0)) * 0.05
		"sit":
			hips.position.y = 0.5
			ll.rotation.x = PI * 0.5
			lr.rotation.x = PI * 0.5
			al.rotation.x = 0.55
			ar.rotation.x = 0.55
		"sweep":
			torso.rotation.x = -0.35
			torso.rotation.y = sin(t * 2.2) * 0.3
			al.rotation = Vector3(0.9, 0, 0.25)
			ar.rotation = Vector3(0.7, 0, -0.25)
		"wait":
			al.rotation = Vector3(0.25, 0, 0.12)
			ar.rotation = Vector3(0.25, 0, -0.12)
		"knock":
			ar.rotation.x = 1.5 + sin(t * 10.0) * 0.15
		"stand_stare":
			pass
		_:
			pass
	# breathing
	var ts: Node3D = _parts.torso_mesh
	if breath_wrong:
		_breath_t += delta
		if _breath_t > _breath_next:
			_breath_t = 0.0
			_breath_next = randf_range(1.2, 4.5)
		var k := clampf(_breath_t / 0.18, 0.0, 1.0) if _breath_t < 0.6 else clampf(1.0 - (_breath_t - 0.6) * 4.0, 0.0, 1.0)
		ts.scale = Vector3(1.0 + 0.05 * k, 1.0 + 0.03 * k, 1.0 + 0.07 * k)
	elif not _paused:
		ts.scale = Vector3.ONE * (1.0 + sin(t * 1.6) * 0.008)
	# distorted face jitters
	var fd: float = shapes.face_distort
	var hm: Node3D = _parts.head_mesh
	if fd > 0.01:
		hm.rotation = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.12 * fd
	else:
		hm.rotation = Vector3.ZERO
