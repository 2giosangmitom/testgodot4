extends SceneTree
## Headless check for Track C2 prop glbs:
##   godot --headless --path . -s res://tools/blender/props/verify_props.gd
## Prints per prop: tri count, child node names, root metadata (glTF extras), textures + filter.


func _init() -> void:
	var ok := true
	var dir := DirAccess.open("res://assets/models/props")
	var files: Array = []
	for f in dir.get_files():
		if f.ends_with(".glb"):
			files.append(f)
	files.sort()
	for f in files:
		var ps: PackedScene = load("res://assets/models/props/" + f)
		if ps == null:
			printerr("FAIL load ", f)
			ok = false
			continue
		var inst := ps.instantiate()
		var tris := 0
		var names: Array = []
		var texs := {}
		var meta := {}
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			names.append(String(mi.name))
			if mi.has_meta("extras"):
				meta = mi.get_meta("extras")
			for s in mi.mesh.get_surface_count():
				tris += mi.mesh.surface_get_array_index_len(s) / 3
				var mat: Material = mi.mesh.surface_get_material(s)
				if mat is BaseMaterial3D:
					var t: Texture2D = mat.albedo_texture
					if t == null:
						printerr("FAIL %s: surface without texture" % f)
						ok = false
					else:
						var tag := t.resource_path.get_file()
						if mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
							tag += "(alpha)"
						texs[tag] = true
		if tris > 300:
			printerr("FAIL %s: %d tris > 300" % [f, tris])
			ok = false
		print("[%s] tris=%d nodes=%s textures=%s extras=%s" % [f.get_basename(), tris, names, texs.keys(), meta])
		inst.free()
	print("VERIFY_PROPS ", "OK" if ok else "FAILED")
	quit(0 if ok else 1)
