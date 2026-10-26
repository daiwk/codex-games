extends SkeletonModifier3D

# Rotate the complete upper branch after the seated legs and before contact IK.
# The horse/hips remain aligned with travel; both arms share the same transform.
var fighter: Node3D
var rig: Skeleton3D
var spine = -1
func setup(actor: Node3D, skeleton: Skeleton3D) -> void:
	fighter = actor
	rig = skeleton
	for index in rig.get_bone_count():
		if rig.get_bone_name(index).ends_with("Spine"):
			spine = index
			break
	rig.add_child(self)
	influence = 1.0
func _process_modification_with_delta(_delta: float) -> void:
	if spine < 0 or not is_instance_valid(fighter) or not fighter.mounted: return
	var pose = rig.get_bone_global_pose(spine)
	pose.basis = Basis(Vector3.UP, float(fighter.cavalry_body_yaw)) * pose.basis
	rig.set_bone_global_pose(spine, pose)
