class_name HeadTurnModifier
extends SkeletonModifier3D
## Applied after the AnimationPlayer each frame: rotates the head bone around the model's
## up axis (yaw) and optionally pitches/rolls it. Used by EntityBody on imported character glbs.

var bone_idx := -1
var yaw := 0.0
var pitch := 0.0
var roll := 0.0

func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or bone_idx < 0 or (is_zero_approx(yaw) and is_zero_approx(pitch) and is_zero_approx(roll)):
		return
	var g := sk.get_bone_global_pose(bone_idx)
	var turn := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, roll)
	var new_global := turn * g.basis
	var parent := sk.get_bone_parent(bone_idx)
	var parent_basis := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	var local := parent_basis.inverse() * new_global
	sk.set_bone_pose_rotation(bone_idx, local.get_rotation_quaternion())
