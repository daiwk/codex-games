extends SkeletonModifier3D

# Read-only final-pose publisher. It changes neither bones nor weapon sockets.
var fighter: Node3D
var host: Node
var rig: Skeleton3D
var hand = -1

func setup(owner_fighter: Node3D, receiver: Node) -> void:
	fighter=owner_fighter
	host=receiver
	rig=fighter.skeleton
	for index in rig.get_bone_count():
		if rig.get_bone_name(index).ends_with("RightHand"):hand=index;break
	assert(hand>=0)
	rig.add_child(self)
	influence=1.0

func _process_modification_with_delta(delta: float) -> void:
	if not is_instance_valid(fighter) or not is_instance_valid(host):return
	var pose=rig.global_transform*rig.get_bone_global_pose(hand)*fighter.grip.transform
	host.capture_blade_hand_pose(fighter,pose,Engine.get_physics_frames(),delta)
