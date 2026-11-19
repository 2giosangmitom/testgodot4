@tool
extends EditorScenePostImport
## Post-import for Track C1 env glbs (set as import_script/path in each *.glb.import).
## glTF has no way to say "multiply albedo by COLOR_0", so the baked vertex AO is enabled here:
##  - opaque / cutout surfaces with vertex colours -> vertex_color_use_as_albedo = true
##  - every material -> nearest filtering (PSX), no specular
##  - `_emit` surfaces keep full-bright emission, `_glass` stay alpha blended.
## Markers (MARKER_*) and -colonly bodies are untouched.


func _post_import(scene: Node) -> Object:
	_fix(scene)
	return scene


func _fix(n: Node) -> void:
	if n is MeshInstance3D and n.mesh != null:
		var mesh: Mesh = n.mesh
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				continue
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mat.metallic_specular = 0.0
			var mname := String(mat.resource_name)
			var has_col: bool = (mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR) != 0
			if has_col and not mname.ends_with("_emit") and not mname.ends_with("_glass"):
				mat.vertex_color_use_as_albedo = true
				mat.vertex_color_is_srgb = false
	for c in n.get_children():
		_fix(c)
