extends SceneTree
## Headless check for Track C2 character glbs:
##   godot --headless --path . -s res://tools/blender/chars/verify_chars.gd
## Prints AnimationPlayer animations (+loop mode), Skeleton3D bones, blend shapes, tri count, textures.

const NAMES := ["nam", "hung", "linh", "bac_tu", "chi_hanh", "thay_khai", "ba_cu", "student_m1", "student_m2",
	"student_f1", "student_f2", "passerby_m1", "passerby_m2", "passerby_f1", "gazer", "mimic_hung", "mimic_linh"]
const REQUIRED_ANIMS := ["idle", "walk", "run", "stiff_run", "head_turn_left", "head_turn_right", "sit", "sweep",
	"wait", "knock", "stand_stare", "death_fall"]
const REQUIRED_SHAPES := ["neck_tilt", "long_arms", "face_distort"]


func _init() -> void:
	var ok := true
	for n in NAMES:
		var path := "res://assets/models/chars/%s.glb" % n
		var ps: PackedScene = load(path)
		if ps == null:
			printerr("FAIL load ", path)
			ok = false
			continue
		var inst := ps.instantiate()
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		var sks := inst.find_children("*", "Skeleton3D", true, false)
		var mis := inst.find_children("*", "MeshInstance3D", true, false)
		if sks.is_empty() or mis.is_empty():
			printerr("FAIL %s: no skeleton/mesh" % n)
			ok = false
			inst.free()
			continue
		var sk: Skeleton3D = sks[0]
		var mi: MeshInstance3D = mis[0]
		var anims: Array = []
		if ap:
			for a in ap.get_animation_list():
				var anim := ap.get_animation(a)
				anims.append("%s(%.2fs%s)" % [a, anim.length, ",loop" if anim.loop_mode != Animation.LOOP_NONE else ""])
		var bones: Array = []
		for i in sk.get_bone_count():
			bones.append(sk.get_bone_name(i))
		var shapes: Array = []
		for i in mi.mesh.get_blend_shape_count():
			shapes.append(mi.mesh.get_blend_shape_name(i))
		var tris := 0
		var texs: Array = []
		for s in mi.mesh.get_surface_count():
			tris += mi.mesh.surface_get_array_index_len(s) / 3
			var mat := mi.mesh.surface_get_material(s)
			if mat is BaseMaterial3D and mat.albedo_texture:
				texs.append("%s(filter=%d)" % [mat.albedo_texture.resource_path.get_file(), mat.texture_filter])
		print("[%s] tris=%d bones=%d anims=%s" % [n, tris, bones.size(), ", ".join(anims)])
		print("    bones: ", ", ".join(bones))
		print("    shapes: ", shapes, " textures: ", texs, " skeleton_path: ", inst.get_path_to(sk))
		if sk.find_bone("head") < 0:
			printerr("FAIL %s: no head bone" % n)
			ok = false
		for a in REQUIRED_ANIMS:
			if ap == null or not ap.has_animation(a):
				printerr("FAIL %s: missing anim %s" % [n, a])
				ok = false
		for s in REQUIRED_SHAPES:
			if not shapes.has(s):
				printerr("FAIL %s: missing shape %s" % [n, s])
				ok = false
		if texs.size() < 2:
			printerr("FAIL %s: textures not resolved %s" % [n, texs])
			ok = false
		inst.free()
	print("VERIFY_CHARS ", "OK" if ok else "FAILED")
	quit(0 if ok else 1)
