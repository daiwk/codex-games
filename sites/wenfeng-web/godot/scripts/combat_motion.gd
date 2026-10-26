extends SkeletonModifier3D

## Small secondary motion on top of the authored clips. No root, leg or arm
## translations are changed. Contact/attack windows keep their baked poses;
## the final two-hand/contact modifier remains authoritative after this one.
var fighter: Node3D
var rig: Skeleton3D
var lean = Vector3.ZERO
var lean_velocity = Vector3.ZERO
var last_applied = Vector3.ZERO
var phase = 0.0
var _last_velocity = Vector3.ZERO
var _last_yaw = 0.0
var _sample_ready = false
var _spines: Array[int] = []
var _neck = -1
var _head = -1

func setup(owner_fighter: Node3D, skeleton: Skeleton3D) -> void:
	fighter = owner_fighter
	rig = skeleton
	for suffix in ["Spine", "Spine1", "Spine2"]:
		var bone = _bone(suffix)
		if bone >= 0:
			_spines.append(bone)
	_neck = _bone("Neck")
	_head = _bone("Head")
	rig.add_child(self)
	rig.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	influence = 1.0
	reset_motion()

func _bone(suffix: String) -> int:
	for index in rig.get_bone_count():
		if rig.get_bone_name(index).ends_with(suffix):
			return index
	return -1

func reset_motion() -> void:
	lean = Vector3.ZERO
	lean_velocity = Vector3.ZERO
	last_applied = Vector3.ZERO
	phase = 0.0
	_last_velocity = Vector3.ZERO
	_last_yaw = fighter.rotation.y if is_instance_valid(fighter) else 0.0
	_sample_ready = false

func activity_weight() -> float:
	if not is_instance_valid(fighter) or fighter.hp <= 0.0 or fighter.state in ["hit", "stagger", "dead", "dodge"]:
		return 0.0
	if fighter.state in ["attack", "skill"]:
		# Never alter anticipation/contact timing or the line of a spear. Ease
		# in only after the real contact window has finished.
		var window: Vector2 = fighter.attack.get("active", Vector2.ZERO)
		return smoothstep(window.y + 0.04, window.y + 0.22, fighter.action_time) * 0.45
	if fighter.state == "ultimate":
		return 0.0
	return 0.35 if fighter.state == "block" else 1.0

func _rotate_global(index: int, rotation_delta: Vector3) -> void:
	if index < 0:
		return
	var pose = rig.get_bone_global_pose(index)
	pose.basis = Basis.from_euler(rotation_delta) * pose.basis
	rig.set_bone_global_pose(index, pose)

func _process_modification_with_delta(delta: float) -> void:
	if not is_instance_valid(fighter) or _spines.is_empty():
		return
	var dt = clampf(delta, 0.0, 0.05)
	if dt <= 0.0:
		return
	phase = fmod(phase + dt * TAU * 0.23, TAU)
	var velocity: Vector3 = fighter.global_basis.inverse() * Vector3(fighter.velocity.x, 0.0, fighter.velocity.z)
	var acceleration = Vector3.ZERO
	var yaw_rate = 0.0
	if _sample_ready:
		acceleration = (velocity - _last_velocity) / maxf(dt, 0.001)
		yaw_rate = clampf(angle_difference(_last_yaw, fighter.rotation.y) / maxf(dt, 0.001), -7.0, 7.0)
	_last_velocity = velocity
	_last_yaw = fighter.rotation.y
	_sample_ready = true
	var target = Vector3.ZERO
	if not fighter.mounted:
		# The torso settles after acceleration and trails a turn a few degrees.
		# The hips, planted feet and actual CharacterBody heading stay untouched.
		target.x = clampf(-acceleration.z * 0.0014 + velocity.z * 0.006, -0.055, 0.055)
		target.z = clampf(acceleration.x * 0.0013 - yaw_rate * velocity.z * 0.003, -0.050, 0.050)
		target.y = clampf(-yaw_rate * 0.010, -0.042, 0.042)
	# A critically damped spring avoids a rigid return when movement stops.
	# Small substeps keep it stable when a browser frame is delayed.
	var steps = maxi(1, ceili(dt / 0.0084))
	var step = dt / float(steps)
	for index in steps:
		lean_velocity += ((target - lean) * 130.0 - lean_velocity * 22.8) * step
		lean += lean_velocity * step
	var weight = activity_weight()
	var breath = Vector3(sin(phase) * 0.006, sin(phase * 0.5) * 0.002, cos(phase) * 0.0025)
	last_applied = (lean + breath) * weight
	for index in _spines.size():
		var amount: float = [0.45, 0.35, 0.20][mini(index, 2)]
		_rotate_global(_spines[index], last_applied * amount)
	# A soft gaze counter-rotation keeps the helmet from swaying like the chest.
	_rotate_global(_neck, last_applied * -0.30)
	_rotate_global(_head, last_applied * -0.20)
