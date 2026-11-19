class_name EntityObservation
extends RefCounted
## Pure, testable helpers for "is the player looking at this?" logic.
## No rendering needed: everything works from transforms, so headless tests can call it.

const WORLD_MASK := 1          # layer 1 "world" blocks sight
const DEFAULT_FOG_FAR := 10.0

## True if `point` lies inside a perspective frustum described by a camera transform.
## fov_deg is the VERTICAL fov (Camera3D.KEEP_HEIGHT default), aspect = width/height.
## margin_deg widens the frustum (so an entity half off-screen still counts as seen).
static func is_point_in_view(cam_xform: Transform3D, fov_deg: float, aspect: float, point: Vector3,
		margin_deg := 4.0, max_dist := INF, near := 0.05) -> bool:
	var local := cam_xform.affine_inverse() * point
	var depth := -local.z
	if depth <= near:
		return false
	if local.length() > max_dist:
		return false
	var half_v := deg_to_rad(fov_deg * 0.5)
	var half_h := atan(tan(half_v) * aspect)
	var margin := deg_to_rad(margin_deg)
	if atan2(absf(local.y), depth) > half_v + margin:
		return false
	if atan2(absf(local.x), depth) > half_h + margin:
		return false
	return true

## True if `point` is within a cone along the camera's forward axis (flashlight beam).
static func is_in_cone(cam_xform: Transform3D, point: Vector3, half_angle_deg: float, max_dist: float) -> bool:
	var to := point - cam_xform.origin
	var d := to.length()
	if d > max_dist or d < 0.001:
		return false
	var fwd := -cam_xform.basis.z.normalized()
	return fwd.angle_to(to / d) <= deg_to_rad(half_angle_deg)

## Full observation test over several sample points (head / chest / feet).
## `los` is a Callable(from: Vector3, to: Vector3) -> bool (true = unobstructed); pass an invalid
## Callable to skip line-of-sight (tests).
static func is_observed(cam_xform: Transform3D, fov_deg: float, aspect: float, points: Array,
		max_dist: float, margin_deg := 4.0, los := Callable()) -> bool:
	for p in points:
		if not is_point_in_view(cam_xform, fov_deg, aspect, p, margin_deg, max_dist):
			continue
		if los.is_valid() and not los.call(cam_xform.origin, p):
			continue
		return true
	return false

## Current fog far distance. RenderingServer.global_shader_parameter_get() is editor-only at
## runtime, so ask RenderSettings: get_fog_far() if it exists, else its current preset's "far".
static func fog_visible_distance(fallback := DEFAULT_FOG_FAR) -> float:
	var ml := Engine.get_main_loop() as SceneTree
	var rs: Node = ml.root.get_node_or_null("RenderSettings") if ml else null
	if rs == null:
		return fallback
	if rs.has_method("get_fog_far"):
		return float(rs.get_fog_far())
	var presets = rs.get("FOG_PRESETS")
	var cur = rs.get("current_preset")
	if presets is Dictionary and presets.has(cur):
		return float(presets[cur].get("far", fallback))
	return fallback

## Is a collider see-through (glass)? Group or metadata `see_through`.
static func is_see_through(collider: Object) -> bool:
	if collider == null:
		return false
	if collider is Node and (collider as Node).is_in_group("see_through"):
		return true
	if collider.has_meta("see_through") and collider.get_meta("see_through"):
		return true
	# glass meshes imported as "*_glass" get a collision sibling named "*_glass*"
	if collider is Node and String((collider as Node).name).to_lower().contains("glass"):
		return true
	var parent = collider.get_parent() if collider is Node else null
	if parent and (parent.is_in_group("see_through") or (parent.has_meta("see_through") and parent.get_meta("see_through"))
			or String(parent.name).to_lower().contains("glass")):
		return true
	return false

## Raycast from -> to on `mask`, ignoring see-through colliders. True = nothing opaque in between.
static func ray_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		exclude: Array[RID] = [], mask := WORLD_MASK) -> bool:
	if space == null:
		return true
	var ex: Array[RID] = exclude.duplicate()
	for i in 6:
		var q := PhysicsRayQueryParameters3D.create(from, to, mask, ex)
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		if is_see_through(hit.collider):
			ex.append(hit.rid)
			continue
		return false
	return true

## Horizontal yaw (radians) that makes a node at `from` face `to` (Godot forward = -Z).
static func yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(-d.x, -d.z)
