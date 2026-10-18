extends SkeletonModifier3D

# After the authored animation (and RiderPose), keep a full-length polearm on
# the near side of the opponent's armour. Both palms move together; arm IK
# changes rotations only, so neither the weapon nor any bone is stretched.
const MAX_RETRACTION = 0.56
const SURFACE_MARGIN = 0.035
const RESIDUAL_TOLERANCE = 0.018

var fighter: Node3D
var rig: Skeleton3D
var _arms: Array[Dictionary] = []
var _upper_bones: Array[int] = []
var _ready_rotations: Dictionary = {}
var pose_cached = false
var right_palm_local = Vector3.ZERO
var left_palm_local = Vector3.ZERO
var right_wrist_basis = Basis.IDENTITY

func setup(owner_fighter: Node3D, skeleton: Skeleton3D) -> void:
	fighter = owner_fighter
	rig = skeleton
	for suffix in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "RightShoulder", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "LeftHand", "RightHand"]:
		var index = _bone(suffix)
		if index >= 0:
			_upper_bones.append(index)
	for side in ["Left", "Right"]:
		var upper = _bone(side + "Arm")
		var lower = _bone(side + "ForeArm")
		var hand = _bone(side + "Hand")
		assert(upper >= 0 and lower >= 0 and hand >= 0, "Thrust contact requires both complete arms")
		_arms.append({"upper": upper, "lower": lower, "hand": hand, "left": side == "Left"})
	rig.add_child(self)
	rig.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	influence = 1.0

func _bone(suffix: String) -> int:
	for index in rig.get_bone_count():
		if rig.get_bone_name(index).ends_with(suffix):
			return index
	return -1

func _rotations() -> Dictionary:
	var values: Dictionary = {}
	for index in _upper_bones:
		values[index] = rig.get_bone_pose_rotation(index)
	return values

func _blend_pose(authored: Dictionary, amount: float) -> void:
	for index in _upper_bones:
		var ready: Quaternion = _ready_rotations.get(index, authored[index])
		var current: Quaternion = authored[index]
		rig.set_bone_pose_rotation(index, ready.slerp(current, amount).normalized())

func _shaft() -> Dictionary:
	var right = rig.to_global(_palm_local(false))
	var left = rig.to_global(_palm_local(true))
	var axis = (right - left).normalized() * float(fighter.grip_config.get("axis_sign", -1.0))
	var length_m = float(fighter.grip_config.weapon_length) * (0.99 - float(fighter.grip_config.grip_fraction))
	return {"right": right, "left": left, "axis": axis, "length": length_m}

func _palm_local(left: bool) -> Vector3:
	var hand: int = fighter.left_hand_index if left else fighter.right_hand_index
	var values: Array = fighter.grip_config.left_palm if left else fighter.grip_config.right_palm
	return rig.get_bone_global_pose(hand) * Vector3(values[0], values[1], values[2])

func _cache_final_pose() -> void:
	# SkeletonModifier outputs are transient. Render-time grip updates must use
	# the final skinned pose, rather than re-reading restored animation inputs.
	right_palm_local = _palm_local(false)
	left_palm_local = _palm_local(true)
	right_wrist_basis = rig.get_bone_global_pose(fighter.right_hand_index).basis
	pose_cached = true

func _sphere_entry(origin: Vector3, direction: Vector3, centre: Vector3, radius: float, maximum: float) -> float:
	var offset = origin - centre
	var b = offset.dot(direction)
	var discriminant = b * b - (offset.length_squared() - radius * radius)
	if discriminant < 0.0:
		return INF
	var distance = -b - sqrt(discriminant)
	if distance < 0.0:
		distance = -b + sqrt(discriminant)
	return distance if distance >= 0.0 and distance <= maximum else INF

func _capsule_entry(origin: Vector3, direction: Vector3, maximum: float) -> float:
	var opponent = fighter.opponent
	if not is_instance_valid(opponent):
		return INF
	var low: Vector3 = opponent.thrust_body_low()
	var high: Vector3 = opponent.thrust_body_high()
	var radius = float(opponent.thrust_body_radius()) + SURFACE_MARGIN
	var nearest = Geometry3D.get_closest_point_to_segment(origin, low, high)
	if origin.distance_squared_to(nearest) <= radius * radius:
		return 0.0
	var result = minf(_sphere_entry(origin, direction, low, radius, maximum), _sphere_entry(origin, direction, high, radius, maximum))
	var offset = origin - low
	var a = direction.x * direction.x + direction.z * direction.z
	if a > 0.000001:
		var b = offset.x * direction.x + offset.z * direction.z
		var c = offset.x * offset.x + offset.z * offset.z - radius * radius
		var discriminant = b * b - a * c
		if discriminant >= 0.0:
			for distance in [(-b - sqrt(discriminant)) / a, (-b + sqrt(discriminant)) / a]:
				var y = origin.y + direction.y * distance
				if distance >= 0.0 and distance <= maximum and y >= low.y and y <= high.y:
					result = minf(result, distance)
	return result

func _required_retraction(shaft: Dictionary) -> float:
	var entry = _capsule_entry(shaft.right, shaft.axis, shaft.length)
	return maxf(0.0, float(shaft.length) - entry) if is_finite(entry) else 0.0

func _arm_ik(arm: Dictionary, target_palm_world: Vector3) -> void:
	var upper: Transform3D = rig.get_bone_global_pose(arm.upper)
	var lower: Transform3D = rig.get_bone_global_pose(arm.lower)
	var hand: Transform3D = rig.get_bone_global_pose(arm.hand)
	var palm: Array = fighter.grip_config.left_palm if arm.left else fighter.grip_config.right_palm
	var offset = Vector3(palm[0], palm[1], palm[2])
	var target = rig.to_local(target_palm_world) - hand.basis * offset
	var shoulder = upper.origin
	var l1 = shoulder.distance_to(lower.origin)
	var l2 = lower.origin.distance_to(hand.origin)
	var direction = target - shoulder
	if direction.length_squared() < 0.0000001 or l1 < 0.00001 or l2 < 0.00001:
		return
	var distance = clampf(direction.length(), absf(l1 - l2) + 0.00001, (l1 + l2) * 0.997)
	direction = direction.normalized()
	var bend = lower.origin - shoulder
	bend -= direction * bend.dot(direction)
	if bend.length_squared() < 0.0000001:
		bend = direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT)
	bend = bend.normalized()
	var along = (l1 * l1 - l2 * l2 + distance * distance) / (2.0 * distance)
	var elbow = shoulder + direction * along + bend * sqrt(maxf(0.0, l1 * l1 - along * along))
	upper.basis = Basis(Quaternion((lower.origin - shoulder).normalized(), (elbow - shoulder).normalized())) * upper.basis
	rig.set_bone_global_pose(arm.upper, upper)
	lower = rig.get_bone_global_pose(arm.lower)
	var current_hand: Transform3D = rig.get_bone_global_pose(arm.hand)
	var desired_wrist = shoulder + direction * distance
	lower.basis = Basis(Quaternion((current_hand.origin - lower.origin).normalized(), (desired_wrist - lower.origin).normalized())) * lower.basis
	rig.set_bone_global_pose(arm.lower, lower)
	current_hand = rig.get_bone_global_pose(arm.hand)
	current_hand.basis = hand.basis
	rig.set_bone_global_pose(arm.hand, current_hand)

func _fit_pose(authored: Dictionary, amount: float) -> Dictionary:
	_blend_pose(authored, amount)
	return _fit_current_pose()

func _fit_current_pose() -> Dictionary:
	var shaft = _shaft()
	var retraction = _required_retraction(shaft)
	if retraction > MAX_RETRACTION:
		return {"safe": false, "retraction": retraction}
	if retraction > 0.0001:
		# Translate the two target palm centres by the same world-space offset.
		var shift: Vector3 = shaft.axis * (retraction + 0.002)
		for arm in _arms:
			_arm_ik(arm, (shaft.left if arm.left else shaft.right) - shift)
	var residual = _required_retraction(_shaft())
	return {"safe": residual <= RESIDUAL_TOLERANCE, "retraction": minf(retraction, MAX_RETRACTION)}

func _close_guard(authored: Dictionary) -> Dictionary:
	# At touching-body distance even the normal diagonal guard can cross the
	# opponent. Turn the upper torso to carry the point alongside their body,
	# rather than trying to pull a two-metre shaft through the rider's chest.
	var spine = _bone("Spine")
	for angle in [15.0, -15.0, 30.0, -30.0, 45.0, -45.0, 65.0, -65.0, 85.0, -85.0]:
		_blend_pose(authored, 0.0)
		var pose: Transform3D = rig.get_bone_global_pose(spine)
		pose.basis = Basis(Vector3.UP, deg_to_rad(angle)) * pose.basis
		rig.set_bone_global_pose(spine, pose)
		var result = _fit_current_pose()
		if result.safe:
			return result
	_blend_pose(authored, 0.0)
	fighter._contact_backstep_requested = true
	return {"safe": false, "retraction": 0.0}

func _process_modification_with_delta(_delta: float) -> void:
	if not is_instance_valid(fighter) or not is_instance_valid(fighter.opponent):
		return
	fighter._contact_backstep_requested = false
	if not fighter.is_physical_thrust():
		fighter.contact_active = false
		fighter.contact_retraction = 0.0
		if fighter.state in ["idle", "move"]:
			_ready_rotations = _rotations()
		_cache_final_pose()
		return
	var authored = _rotations()
	if _ready_rotations.is_empty():
		_ready_rotations = authored.duplicate()
	var raw_depth = _required_retraction(_shaft())
	if raw_depth <= 0.0001:
		fighter.contact_active = false
		fighter.contact_retraction = 0.0
		_cache_final_pose()
		return
	var result = _fit_pose(authored, 1.0)
	var amount = 1.0
	if not result.safe:
		# At body-to-body range, a full two-metre extension cannot fit. Retain
		# a short jab/withdrawal towards the captured ready stance instead of
		# stretching arms, telescoping the spear or teleporting the fighter.
		var low = 0.0
		var high = 1.0
		var ready = _fit_pose(authored, 0.0)
		if ready.safe:
			for iteration in 7:
				var middle = (low + high) * 0.5
				var trial = _fit_pose(authored, middle)
				if trial.safe:
					low = middle
				else:
					high = middle
			amount = low
			result = _fit_pose(authored, amount)
		else:
			amount = 0.0
			result = _close_guard(authored)
	fighter.contact_active = raw_depth > 0.0001 or amount < 0.999
	fighter.contact_retraction = float(result.retraction)
	if fighter.contact_active:
		var shaft = _shaft()
		var tip: Vector3 = shaft.right + shaft.axis * float(shaft.length)
		var nearest = Geometry3D.get_closest_point_to_segment(tip, fighter.opponent.thrust_body_low(), fighter.opponent.thrust_body_high())
		var normal = (tip - nearest).normalized()
		if normal.length_squared() < 0.1:
			normal = -fighter.forward()
		fighter.contact_point = nearest + normal * float(fighter.opponent.thrust_body_radius())
	_cache_final_pose()
