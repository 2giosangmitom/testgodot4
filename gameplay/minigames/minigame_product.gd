class_name MinigameProduct
extends Resource
## A store product used by checkout / shelf stocking. Visual is `model` (e.g. a glb from
## assets/models/props/) or a primitive placeholder built from shape/size/color.
## Barcode face: `barcode_axis` here, else a `barcode_axis` metadata/property on the model
## (or any of its descendants), else "+Z".

@export var display_name := "Sản phẩm"
@export var type_id := "item"
@export var price := 10000
@export var model: PackedScene
## "+X" "-X" "+Y" "-Y" "+Z" "-Z" ("" = read from model, default +Z).
@export var barcode_axis := ""
@export var size := Vector3(0.08, 0.12, 0.08)
@export var color := Color(0.7, 0.7, 0.7)
@export_enum("box", "cylinder") var shape := 0

static func make(p_name: String, p_type: String, p_price: int, p_size: Vector3, p_color: Color,
		p_shape := 0, model_path := "", p_axis := "") -> MinigameProduct:
	var p := MinigameProduct.new()
	p.display_name = p_name
	p.type_id = p_type
	p.price = p_price
	p.size = p_size
	p.color = p_color
	p.shape = p_shape
	p.barcode_axis = p_axis
	p.model = MinigameUtil.load_if_exists(model_path)
	return p

## Default catalogue (prices in VND). Real glbs are used automatically once they exist.
static func defaults() -> Array[MinigameProduct]:
	var out: Array[MinigameProduct] = []
	out.append(make("Mì gói", "mi_goi", 5000, Vector3(0.13, 0.04, 0.10), Color(0.85, 0.65, 0.15), 0,
		"res://assets/models/props/instant_noodle_pack.glb"))
	out.append(make("Nước ngọt", "nuoc_ngot", 12000, Vector3(0.066, 0.12, 0.066), Color(0.75, 0.12, 0.1), 1,
		"res://assets/models/props/can_drink.glb"))
	out.append(make("Bánh quy", "banh_quy", 18000, Vector3(0.14, 0.05, 0.09), Color(0.55, 0.35, 0.2), 0))
	out.append(make("Sữa hộp", "sua_hop", 8000, Vector3(0.06, 0.1, 0.04), Color(0.85, 0.88, 0.95), 0))
	out.append(make("Nước suối", "nuoc_suoi", 6000, Vector3(0.065, 0.16, 0.065), Color(0.45, 0.65, 0.85), 1))
	return out

## Builds the visual for this product under `parent` and returns the barcode axis in the
## parent's local space. Adds a stripe quad on the barcode face for primitive placeholders.
func build_visual(parent: Node3D, show_barcode := true) -> Vector3:
	var inst := MinigameUtil.instance_model(model)
	if inst:
		inst.name = "Model"
		parent.add_child(inst)
		var a := MinigameUtil.axis_vector(barcode_axis) if barcode_axis != "" else MinigameUtil.find_barcode_axis(inst, parent)
		return a if a != Vector3.ZERO else Vector3(0, 0, 1)
	var axis := MinigameUtil.axis_vector(barcode_axis if barcode_axis != "" else "+Z")
	var mi: MeshInstance3D
	if shape == 1:
		mi = MinigameUtil.cylinder(size.x * 0.5, size.y, color)
	else:
		mi = MinigameUtil.box(size, color)
	mi.name = "Model"
	parent.add_child(mi)
	# a lighter label band so items read at 640x480
	var band := MinigameUtil.box(Vector3(size.x * 1.02, size.y * 0.35, size.z * 1.02), color.lightened(0.45)) if shape == 0 \
		else MinigameUtil.cylinder(size.x * 0.51, size.y * 0.35, color.lightened(0.45))
	parent.add_child(band)
	if show_barcode:
		var q := MeshInstance3D.new()
		q.name = "Barcode"
		var qm := QuadMesh.new()
		var face_extent := absf(axis.dot(size * 0.5))
		var w := 0.05
		qm.size = Vector2(w, w * 0.5)
		q.mesh = qm
		var mat := MinigameUtil.make_mat(Color.WHITE, true)
		mat.albedo_texture = MinigameUtil.barcode_texture()
		q.material_override = mat
		parent.add_child(q)
		# QuadMesh faces +Z; orient it so its normal = axis.
		var up := Vector3.UP if absf(axis.y) < 0.9 else Vector3.FORWARD
		q.basis = Basis.looking_at(-axis, up)
		q.position = axis * (face_extent + 0.002)
	return axis
