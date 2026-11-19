extends SceneTree
## Headless sanity check for the Track C1 env glbs.
##   godot --headless --path . -s res://assets/models/env/_preview/inspect_env.gd
## For each glb: node counts, triangle count, -colonly -> StaticBody3D/CollisionShape3D,
## markers, material checks (shared external textures, vertex colours, glass/cutout/emissive),
## and a physics probe: a downward ray under every MARKER_spawn_* must hit collision.

const ENV_DIR := "res://assets/models/env/"
const FILES := ["school", "store", "alley", "dorm", "shrine", "door_wood", "door_dorm", "door_glass_shop",
	"gate_iron", "streetlight", "motorbike_parked", "cables_cluster", "potted_plant", "plastic_stool", "banyan_tree"]

var _fail := 0

## capsule walk tests: [start, direction, seconds, expected end, tolerance, label]
var WALKS := {
	"school": [
		[Vector3(0, 0.1, -15.0), Vector3(0, 0, -1), 1.6, Vector3(0, 0.45, -19.8), 0.8, "courtyard->steps->corridor"],
		[Vector3(-2.55, 0.55, -19.6), Vector3(0, 0, -1), 1.0, Vector3(-2.55, 0.45, -22.6), 0.5, "corridor->classroom door"],
		[Vector3(0.0, 0.0, 6.0), Vector3(0, 0, -1), 2.6, Vector3(0.0, 0.0, -1.8), 0.5, "road->curb->gate"],
	],
	"store": [
		[Vector3(3.5, 0.1, 4.5), Vector3(0, 0, -1), 1.6, Vector3(3.5, 0.0, -0.3), 0.5, "road->curb->shop door"],
		[Vector3(-0.8, 0.1, -2.0), Vector3(0, 0, -1), 1.4, Vector3(-0.8, 0.0, -6.2), 0.5, "aisle between gondolas"],
		[Vector3(4.0, 0.1, -6.8), Vector3(0, 0, -1), 1.6, Vector3(4.0, 0.0, -11.6), 0.5, "store->storeroom->back door"],
		[Vector3(2.2, 0.1, -5.0), Vector3(0, 0, 1), 0.7, Vector3(2.2, 0.0, -2.9), 0.5, "past gondola 4 to behind counter"],
	],
	"alley": [
		[Vector3(4.4, 0.1, -12.6), Vector3(0, 0, -1), 4.6, Vector3(4.4, 0.0, -26.4), 0.8, "alley first leg"],
		[Vector3(3.0, 0.1, -28.0), Vector3(-1, 0, 0), 5.5, Vector3(-13.5, 0.0, -28.0), 0.8, "alley second leg"],
		[Vector3(-13.85, 0.1, -30.0), Vector3(0, 0, -1), 7.5, Vector3(-13.85, 0.0, -52.5), 0.8, "alley third leg"],
	],
	"dorm": [
		[Vector3(0.0, 0.1, -15.6), Vector3(-1, 0, 0), 1.4, Vector3(-4.2, 0.0, -15.6), 0.5, "lane->dorm gate->hall"],
		[Vector3(-7.6, 0.1, -14.65), Vector3(1, 0, 0), 2.8, Vector3(-1.3, 3.2, -14.65), 0.6, "stair up to floor 2 (+landing)"],
		[Vector3(-1.7, 3.3, -15.0), Vector3(0, 0, -1), 3.6, Vector3(-1.7, 3.2, -25.8), 0.5, "corridor to P.204"],
		[Vector3(-1.7, 3.3, -25.85), Vector3(-1, 0, 0), 0.8, Vector3(-4.1, 3.2, -25.85), 0.5, "corridor->P.204 doorway"],
	],
	"shrine": [
		[Vector3(0.0, 0.1, -17.0), Vector3(0, 0, -1), 5.8, Vector3(0.0, 0.0, -34.4), 0.6, "lane narrowing"],
		[Vector3(1.55, 0.1, -36.7), Vector3(0, 0, -1), 0.9, Vector3(1.55, 0.35, -39.2), 0.6, "onto shrine plinth"],
	],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for f in FILES:
		await _inspect(f)
	print("[inspect] DONE failures=%d" % _fail)
	quit(1 if _fail > 0 else 0)


func _walk(n: Node, out: Array) -> void:
	out.append(n)
	for c in n.get_children():
		_walk(c, out)


func _inspect(name: String) -> void:
	var path := ENV_DIR + name + ".glb"
	var ps: PackedScene = load(path)
	if ps == null:
		printerr("[inspect] cannot load ", path)
		_fail += 1
		return
	var root: Node3D = ps.instantiate()
	get_root().add_child(root)
	var nodes: Array = []
	_walk(root, nodes)
	var meshes := 0
	var tris := 0
	var bodies := 0
	var shapes := 0
	var markers: Array[String] = []
	var ext_tex := 0
	var emb_tex := 0
	var vcol_mats := 0
	var glass_ok := 0
	var cut_ok := 0
	var emit_ok := 0
	var leftovers: Array[String] = []
	var seen_mats := {}
	for n in nodes:
		if n is MeshInstance3D:
			meshes += 1
			var m: Mesh = n.mesh
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null else arr[Mesh.ARRAY_VERTEX].size()) / 3
				var mat := m.surface_get_material(s) as BaseMaterial3D
				if mat == null or seen_mats.has(mat):
					continue
				seen_mats[mat] = true
				var t := mat.albedo_texture
				if t != null:
					if t.resource_path.begins_with("res://assets/textures/env/"):
						ext_tex += 1
					else:
						emb_tex += 1
				if mat.vertex_color_use_as_albedo:
					vcol_mats += 1
				var mn := String(mat.resource_name)
				if mn.ends_with("_glass") and mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					glass_ok += 1
				if mn.ends_with("_cut") and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
					cut_ok += 1
				if mn.ends_with("_emit") and mat.emission_enabled:
					emit_ok += 1
			if String(n.name).contains("colonly"):
				leftovers.append(n.name)
		elif n is StaticBody3D:
			bodies += 1
		elif n is CollisionShape3D:
			shapes += 1
		if String(n.name).begins_with("MARKER_"):
			markers.append(String(n.name))
	print("[inspect] %s: meshes=%d tris=%d static_bodies=%d shapes=%d markers=%d mats=%d ext_tex=%d emb_tex=%d vcol=%d glass=%d cut=%d emit=%d" % [
		name, meshes, tris, bodies, shapes, markers.size(), seen_mats.size(), ext_tex, emb_tex, vcol_mats, glass_ok, cut_ok, emit_ok])
	if not leftovers.is_empty():
		printerr("[inspect]   -colonly meshes left visible: ", leftovers)
		_fail += 1
	if emb_tex > 0:
		printerr("[inspect]   %d materials use embedded textures" % emb_tex)
		_fail += 1
	if name in ["school", "store", "alley", "dorm", "shrine"]:
		if bodies == 0:
			printerr("[inspect]   no collision in level glb!")
			_fail += 1
		# physics probe under spawns / key markers
		await physics_frame
		await physics_frame
		var space := root.get_world_3d().direct_space_state
		for mk in markers:
			if not (mk.begins_with("MARKER_spawn") or mk in ["MARKER_seat_nam", "MARKER_hide_counter", "MARKER_alley_exit", "MARKER_loft", "MARKER_ladder_bottom", "MARKER_shrine_front", "MARKER_bus_stop"]):
				continue
			var mnode: Node3D = root.find_child(mk, true, false)
			var p := mnode.global_position
			var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 2.0)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				printerr("[inspect]   no floor under %s at %s" % [mk, p])
				_fail += 1
			else:
				print("[inspect]   floor under %s: y=%.2f (marker y=%.2f)" % [mk, hit.position.y, p.y])
		if name == "school":
			print("[inspect]   tree sample: ", _tree_sample(root))
		for t in WALKS.get(name, []):
			var end: Vector3 = await _walk_test(root, t[0], t[1], t[2])
			var ok: bool = end.distance_to(t[3]) < t[4]
			print("[inspect]   walk %s: %s -> %s (expect %s) %s" % [t[5], t[0], end.snappedf(0.01), t[3], "OK" if ok else "FAIL"])
			if not ok:
				_fail += 1
	root.queue_free()
	await process_frame


func _walk_test(root: Node3D, start: Vector3, dir: Vector3, secs: float) -> Vector3:
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	body.add_child(cs)
	body.floor_snap_length = 0.3
	body.floor_max_angle = deg_to_rad(46.0)
	root.add_child(body)
	body.global_position = start
	var t := 0.0
	while t < secs:
		await physics_frame
		var dt := 1.0 / 60.0
		var v := dir.normalized() * 3.0
		v.y = body.velocity.y - 9.8 * dt
		if body.is_on_floor():
			v.y = min(v.y, 0.0)
		body.velocity = v
		body.move_and_slide()
		t += dt
	for i in body.get_slide_collision_count():
		var c := body.get_slide_collision(i)
		if absf(c.get_normal().y) < 0.7:
			print("[inspect]     blocked by %s at %s n=%s" % [c.get_collider().name, c.get_position().snappedf(0.01), c.get_normal().snappedf(0.01)])
	var end := body.global_position
	body.queue_free()
	return end


func _tree_sample(root: Node) -> String:
	var parts: Array[String] = []
	for c in root.get_children():
		if parts.size() >= 12:
			break
		if not (c is StaticBody3D or String(c.name).begins_with("MARKER_spawn")):
			continue
		var s := "%s(%s)" % [c.name, c.get_class()]
		if c is StaticBody3D and c.get_child_count() > 0:
			var sh = c.get_child(0)
			s += "->%s(%s)" % [sh.get_class(), sh.shape.get_class() if sh is CollisionShape3D else ""]
		parts.append(s)
	return ", ".join(parts)
