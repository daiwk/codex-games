extends SkeletonModifier3D

# After the authored animation (and RiderPose), keep a full-length polearm on
# the near side of the opponent's armour. Both palms move together; arm IK
# changes rotations only, so neither the weapon nor any bone is stretched.
const WristSolver = preload("res://scripts/wrist_solver.gd")
const MAX_RETRACTION = 0.56
const SURFACE_MARGIN = 0.035
const RESIDUAL_TOLERANCE = 0.018

var fighter: Node3D
var rig: Skeleton3D
var _arms: Array[Dictionary] = []
var _upper_bones: Array[int] = []
var _ready_rotations: Dictionary = {}
var _previous_rotations: Dictionary = {}
var _previous_arm_frames: Dictionary = {}
var _previous_shaft_axis = Vector3.ZERO
var _fitting_shaft_axis = Vector3.ZERO
var _roll_recovering = false
var _grip_roll_weight = 1.0
var _grip_contact_session = false
var _guard_angle = 0.0
var _guard_step = 3.0
var _was_constrained = false
var _modifier_delta = 1.0 / 60.0
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
		_arms.append({"upper": upper, "lower": lower, "hand": hand, "left": side == "Left",
			"rest_hand": rig.get_bone_rest(hand).basis})
	rig.add_child(self)
	rig.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	influence = 1.0

func reset_motion() -> void:
	_ready_rotations.clear()
	_previous_rotations.clear()
	_previous_arm_frames.clear()
	_previous_shaft_axis = Vector3.ZERO
	_fitting_shaft_axis = Vector3.ZERO
	_guard_angle = 0.0
	_guard_step = 3.0
	_was_constrained = false
	_modifier_delta = 1.0 / 60.0
	_roll_recovering = false
	_grip_roll_weight = 1.0
	_grip_contact_session = false
	pose_cached = false
	right_palm_local = Vector3.ZERO
	left_palm_local = Vector3.ZERO
	right_wrist_basis = Basis.IDENTITY

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
	_previous_rotations = _rotations()
	_previous_arm_frames = _arm_frames()
	_previous_shaft_axis = (right_palm_local - left_palm_local).normalized() * float(fighter.grip_config.get("axis_sign", -1.0))
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

func _arm_ik(arm: Dictionary, target_palm_world: Vector3) -> bool:
	if not fighter.is_thrust_weapon() or not _previous_arm_frames.has(arm.lower) or _previous_shaft_axis.length_squared() < 0.5:
		return _arm_ik_candidate(arm, target_palm_world)
	# A round handle leaves palm roll free. Parallel-transport the actual prior
	# palm along the new shaft, then test that equivalent grip before asking
	# the wrist to compensate a different authored elbow/roll branch. Rotation
	# is around the target palm centre; the handle and blade trajectory remain
	# identical. Equivalent roll is available only for the current thrust-only weapon.
	var upper: Transform3D = rig.get_bone_global_pose(arm.upper)
	var lower: Transform3D = rig.get_bone_global_pose(arm.lower)
	var hand: Transform3D = rig.get_bone_global_pose(arm.hand)
	var axis: Vector3 = _fitting_shaft_axis
	var prior: Dictionary = _previous_arm_frames[arm.lower]
	var transported = Basis(Quaternion(_previous_shaft_axis, axis)) * Basis(prior.world_hand)
	var difference = (transported.get_rotation_quaternion() * hand.basis.get_rotation_quaternion().inverse()).normalized()
	if difference.w < 0.0:
		difference = -difference
	var projected = Vector3(difference.x, difference.y, difference.z).dot(axis)
	var roll = 2.0 * atan2(projected, difference.w) * _grip_roll_weight
	var best_score = INF
	var best: Array[Transform3D] = []
	var best_fraction = 0.0
	var fractions: Array[float] = [1.0, 0.0]
	var full_safe = false
	var arc_low = 0.0
	var arc_high = 1.0
	var trials = 0
	var candidate_index = 0
	while candidate_index < fractions.size():
		var fraction = fractions[candidate_index]
		candidate_index += 1
		rig.set_bone_global_pose(arm.upper, upper)
		rig.set_bone_global_pose(arm.lower, lower)
		rig.set_bone_global_pose(arm.hand, hand)
		var palm_pose = hand
		palm_pose.basis = Basis(axis, roll * fraction) * hand.basis
		rig.set_bone_global_pose(arm.hand, palm_pose)
		var safe = _arm_ik_candidate(arm, target_palm_world)
		if is_equal_approx(fraction, 1.0):
			full_safe = safe
		elif not full_safe:
			if safe:
				arc_low = fraction
			else:
				arc_high = fraction
			if trials < 7 and (safe or fraction > 0.0):
				fractions.append((arc_low + arc_high) * 0.5)
				trials += 1
		if not safe:
			continue
		var solved_upper: Transform3D = rig.get_bone_global_pose(arm.upper)
		var solved_lower: Transform3D = rig.get_bone_global_pose(arm.lower)
		var solved_hand: Transform3D = rig.get_bone_global_pose(arm.hand)
		var fore_turn = Basis(prior.world_forearm).get_rotation_quaternion().angle_to(solved_lower.basis.get_rotation_quaternion())
		var hand_turn = Basis(prior.world_hand).get_rotation_quaternion().angle_to(solved_hand.basis.get_rotation_quaternion())
		var score = fore_turn * fore_turn + hand_turn * hand_turn
		if score < best_score:
			best_score = score
			best = [solved_upper, solved_lower, solved_hand]
			best_fraction = fraction
		if score <= pow(_modifier_delta * deg_to_rad(850.0), 2.0) * 1.5:
			break
	if best.is_empty():
		rig.set_bone_global_pose(arm.upper, upper)
		rig.set_bone_global_pose(arm.lower, lower)
		rig.set_bone_global_pose(arm.hand, hand)
		return false
	rig.set_bone_global_pose(arm.upper, best[0])
	rig.set_bone_global_pose(arm.lower, best[1])
	rig.set_bone_global_pose(arm.hand, best[2])
	_roll_recovering = _roll_recovering or absf(roll * best_fraction) > 0.005
	return true

func _apply_round_grip() -> bool:
	if not _grip_contact_session:
		return true
	var shaft = _shaft()
	_fitting_shaft_axis = (rig.global_basis.inverse() * Vector3(shaft.axis)).normalized()
	var safe = true
	for arm in _arms:
		safe = _arm_ik(arm, shaft.left if arm.left else shaft.right) and safe
	return safe

func _arm_ik_candidate(arm: Dictionary, target_palm_world: Vector3) -> bool:
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
		return false
	var distance = clampf(direction.length(), absf(l1 - l2) + 0.00001, (l1 + l2) * 0.997)
	direction = direction.normalized()
	var along = (l1 * l1 - l2 * l2 + distance * distance) / (2.0 * distance)
	var centre = shoulder + direction * along
	var wrist_target = shoulder + direction * distance
	# Select the elbow circle from the palm's neutral forearm direction. The
	# former authored elbow plane could be correct before retraction but fold
	# the wrist sharply afterwards, forcing an unnecessary side-guard fallback.
	var axis_local: Vector3 = rig.get_bone_rest(arm.hand).origin.normalized()
	var hand_forward: Vector3 = Basis(arm.rest_hand).inverse() * axis_local
	var neutral_forearm = (hand.basis * hand_forward).normalized()
	var ideal_elbow = wrist_target - neutral_forearm * l2
	var preferred = ideal_elbow - centre
	preferred -= direction * preferred.dot(direction)
	var authored = lower.origin - shoulder
	authored -= direction * authored.dot(direction)
	if authored.length_squared() < 0.0000001:
		authored = direction.cross(Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT)
	var bend = authored.normalized()
	if _previous_arm_frames.has(arm.lower):
		var parent: int = rig.get_bone_parent(arm.upper)
		var parent_basis: Basis = rig.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		var continuous: Vector3 = parent_basis * Vector3(_previous_arm_frames[arm.lower].bend)
		continuous -= direction * continuous.dot(direction)
		if continuous.length_squared() > 0.0000001:
			bend = continuous.normalized()
	if preferred.length_squared() > 0.0000001:
		# Near the circle's pole, all elbow branches have almost equal wrist
		# swing. Retain the continuous authored branch there instead of letting
		# a numerically tiny projection flip the elbow by 180 degrees.
		var confidence = smoothstep(0.005, 0.040, preferred.length())
		bend = bend.slerp(preferred.normalized(), confidence).normalized()
	var bends: Array[Vector3] = [bend]
	var preceding_bend = Vector3.ZERO
	if _previous_arm_frames.has(arm.lower):
		var parent: int = rig.get_bone_parent(arm.upper)
		var parent_basis: Basis = rig.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		var preceding: Vector3 = parent_basis * Vector3(_previous_arm_frames[arm.lower].bend)
		preceding -= direction * preceding.dot(direction)
		if preceding.length_squared() > 0.0000001:
			preceding_bend = preceding.normalized()
			bends.append(preceding_bend)
	bends.append(authored.normalized())
	var parameters: Array[float] = []
	for index in bends.size():
		parameters.append(-1.0)
	var best_score = INF
	var best: Array[Transform3D] = []
	var neutral_safe = false
	var arc_low = 0.0
	var arc_high = 1.0
	var arc_trials = 0
	var candidate_index = 0
	while candidate_index < bends.size():
		var candidate: Vector3 = bends[candidate_index]
		var parameter: float = parameters[candidate_index]
		var is_neutral: bool = candidate_index == 0
		var is_preceding: bool = candidate_index == 1 and preceding_bend != Vector3.ZERO
		candidate_index += 1
		rig.set_bone_global_pose(arm.upper, upper)
		rig.set_bone_global_pose(arm.lower, lower)
		rig.set_bone_global_pose(arm.hand, hand)
		var elbow = centre + candidate * sqrt(maxf(0.0, l1 * l1 - along * along))
		var solved_upper = upper
		solved_upper.basis = Basis(Quaternion((lower.origin - shoulder).normalized(), (elbow - shoulder).normalized())) * upper.basis
		rig.set_bone_global_pose(arm.upper, solved_upper)
		var solved_lower: Transform3D = rig.get_bone_global_pose(arm.lower)
		var current_hand: Transform3D = rig.get_bone_global_pose(arm.hand)
		var desired_wrist = shoulder + direction * distance
		solved_lower.basis = Basis(Quaternion((current_hand.origin - solved_lower.origin).normalized(), (desired_wrist - solved_lower.origin).normalized())) * solved_lower.basis
		rig.set_bone_global_pose(arm.lower, solved_lower)
		current_hand = rig.get_bone_global_pose(arm.hand)
		# Share longitudinal twist with the forearm while retaining the actual
		# target palm centre, authored palm direction and unchanged bone lengths.
		var preferred_forearm: Variant = _previous_arm_frames[arm.lower].world_forearm if _previous_arm_frames.has(arm.lower) else null
		var wrist = WristSolver.distribute(solved_lower.basis, hand.basis, arm.rest_hand, current_hand.origin - solved_lower.origin, preferred_forearm)
		if is_neutral:
			neutral_safe = wrist.safe
		# The preceding elbow may lie just outside the anatomical cone while
		# the neutral solution is far away. Search that circle arc for the first
		# feasible boundary instead of jumping directly to the neutral branch.
		if neutral_safe and ((is_preceding and not wrist.safe) or parameter > 0.0):
			if parameter > 0.0:
				if wrist.safe:
					arc_high = parameter
				else:
					arc_low = parameter
			if arc_trials < 7:
				var middle = (arc_low + arc_high) * 0.5
				var arc = preceding_bend.signed_angle_to(bend, direction)
				bends.append(preceding_bend.rotated(direction, arc * middle))
				parameters.append(middle)
				arc_trials += 1
		if not wrist.safe:
			continue
		solved_lower.basis = wrist.basis
		rig.set_bone_global_pose(arm.lower, solved_lower)
		current_hand = rig.get_bone_global_pose(arm.hand)
		current_hand.basis = hand.basis
		rig.set_bone_global_pose(arm.hand, current_hand)
		var score = 0.0
		if _previous_arm_frames.has(arm.lower):
			var prior: Dictionary = _previous_arm_frames[arm.lower]
			var forearm_turn = Basis(prior.world_forearm).get_rotation_quaternion().angle_to(solved_lower.basis.get_rotation_quaternion())
			var upper_turn = Basis(prior.world_upper).get_rotation_quaternion().angle_to(solved_upper.basis.get_rotation_quaternion())
			var hand_turn = Basis(prior.world_hand).get_rotation_quaternion().angle_to(current_hand.basis.get_rotation_quaternion())
			score = forearm_turn * forearm_turn + hand_turn * hand_turn + upper_turn * upper_turn * 0.5
		if score < best_score:
			best_score = score
			best = [solved_upper, solved_lower, current_hand]
		if score <= pow(_modifier_delta * deg_to_rad(850.0), 2.0) * 1.5:
			break
	if not best.is_empty():
		rig.set_bone_global_pose(arm.upper, best[0])
		rig.set_bone_global_pose(arm.lower, best[1])
		rig.set_bone_global_pose(arm.hand, best[2])
		return true
	rig.set_bone_global_pose(arm.upper, upper)
	rig.set_bone_global_pose(arm.lower, lower)
	rig.set_bone_global_pose(arm.hand, hand)
	return false

func _fit_pose(authored: Dictionary, amount: float) -> Dictionary:
	_blend_pose(authored, amount)
	return _fit_current_pose()

func _fit_current_pose() -> Dictionary:
	var shaft = _shaft()
	var retraction = _required_retraction(shaft)
	if retraction > MAX_RETRACTION:
		return {"safe": false, "retraction": retraction}
	var wrists_safe = true
	if retraction > 0.0001:
		# Both targets use one fixed shaft axis. The intermediate first-arm
		# solve must not tilt the second arm's equivalent roll reference.
		_fitting_shaft_axis = (rig.global_basis.inverse() * Vector3(shaft.axis)).normalized()
		var shift: Vector3 = shaft.axis * (retraction + 0.002)
		for arm in _arms:
			var arm_safe = _arm_ik(arm, (shaft.left if arm.left else shaft.right) - shift)
			wrists_safe = wrists_safe and arm_safe
	else:
		wrists_safe = _apply_round_grip()
	var residual = _required_retraction(_shaft())
	return {"safe": residual <= RESIDUAL_TOLERANCE and wrists_safe, "retraction": minf(retraction, MAX_RETRACTION)}

func _close_guard(authored: Dictionary) -> Dictionary:
	# At touching-body distance even the normal diagonal guard can cross the
	# opponent. Turn the upper torso to carry the point alongside their body,
	# rather than trying to pull a two-metre shaft through the rider's chest.
	var spine = _bone("Spine")
	# The first feasible +/- angle can swap elbow branches on adjacent ticks.
	# Evaluate feasible solutions against the actual previous output instead,
	# including small steps around that guard's current side. Physical capsule
	# clearance and wrist limits remain the acceptance conditions for every
	# candidate; continuity never makes an otherwise invalid pose valid.
	var angles: Array[float] = [_guard_angle,
		clampf(_guard_angle + _guard_step, -85.0, 85.0),
		clampf(_guard_angle - _guard_step, -85.0, 85.0),
		clampf(_guard_angle + _guard_step * 0.5, -85.0, 85.0),
		clampf(_guard_angle - _guard_step * 0.5, -85.0, 85.0),
		15.0, -15.0, 30.0, -30.0, 45.0, -45.0, 65.0, -65.0, 85.0, -85.0]
	var best_score = INF
	var best_pose: Dictionary = {}
	var best_result: Dictionary = {}
	var best_angle = _guard_angle
	for angle in angles:
		_blend_pose(authored, 0.0)
		var pose: Transform3D = rig.get_bone_global_pose(spine)
		pose.basis = Basis(Vector3.UP, deg_to_rad(angle)) * pose.basis
		rig.set_bone_global_pose(spine, pose)
		var result = _fit_current_pose()
		if result.safe:
			var current = _rotations()
			var score = 0.0
			for index in _upper_bones:
				var prior: Quaternion = _previous_rotations.get(index, authored[index])
				var turn: float = prior.angle_to(current[index])
				var weight = 4.0 if rig.get_bone_name(index).ends_with("ForeArm") else 1.0
				score += turn * turn * weight
			if score < best_score:
				best_score = score
				best_pose = current
				best_result = result
				best_angle = angle
	if not best_pose.is_empty():
		for index in _upper_bones:
			rig.set_bone_pose_rotation(index, best_pose[index])
		_guard_angle = best_angle
		return best_result
	_blend_pose(authored, 0.0)
	fighter._contact_backstep_requested = true
	return {"safe": false, "retraction": 0.0}

func _apply_rotations(values: Dictionary) -> void:
	for index in _upper_bones:
		rig.set_bone_pose_rotation(index, values[index])

func _arm_frames() -> Dictionary:
	var values: Dictionary = {}
	for arm in _arms:
		var upper: Basis = rig.get_bone_global_pose(arm.upper).basis
		var lower: Transform3D = rig.get_bone_global_pose(arm.lower)
		var hand: Transform3D = rig.get_bone_global_pose(arm.hand)
		var parent: int = rig.get_bone_parent(arm.upper)
		var parent_basis: Basis = rig.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		values[arm.lower] = {"bend": (parent_basis.inverse() * (lower.origin - rig.get_bone_global_pose(arm.upper).origin)).normalized(),
			"world_forearm": lower.basis, "world_hand": hand.basis, "world_upper": upper}
	return values

func _arm_motion_ratio(delta: float) -> float:
	# This visual withdrawal budget uses actual model-space bone motion.
	# Local counter-rotation can legitimately be faster while cancelling a
	# parent's turn; it is not a proxy for the visible forearm/hand speed.
	var largest = 0.0
	var budget = maxf(0.0001, delta * deg_to_rad(850.0))
	var current = _arm_frames()
	for index in current:
		if not _previous_arm_frames.has(index):
			continue
		var prior: Dictionary = _previous_arm_frames[index]
		var next: Dictionary = current[index]
		var forearm = Basis(prior.world_forearm).get_rotation_quaternion().angle_to(Basis(next.world_forearm).get_rotation_quaternion())
		var hand = Basis(prior.world_hand).get_rotation_quaternion().angle_to(Basis(next.world_hand).get_rotation_quaternion())
		largest = maxf(largest, maxf(forearm, hand) / budget)
	return largest

func _wrists_safe() -> bool:
	for arm in _arms:
		var lower: Transform3D = rig.get_bone_global_pose(arm.lower)
		var hand: Transform3D = rig.get_bone_global_pose(arm.hand)
		var wrist = WristSolver.measure(lower.basis, hand.basis, arm.rest_hand, hand.origin - lower.origin)
		if wrist.swing > WristSolver.MAX_WRIST_SWING + 0.000001 or absf(wrist.twist) > WristSolver.MAX_WRIST_TWIST + 0.000001:
			return false
	return true

func _continuous_fit(target_result: Dictionary, delta: float) -> Dictionary:
	# Binary search finds a feasible pose, but disconnected feasible regions
	# can make its chosen amount jump. Continue from the actual preceding
	# output and validate each small angular step against the same capsule,
	# full-length handle and anatomical wrist limits.
	var target = _rotations()
	var result = target_result.duplicate()
	result["smoothed"] = false
	if _previous_rotations.is_empty():
		return result
	var ratio = _arm_motion_ratio(delta)
	if bool(result.safe) and ratio <= 1.0:
		return result
	var fraction = minf(1.0, 1.0 / maxf(ratio, 0.0001))
	for attempt in 9:
		for index in _upper_bones:
			var previous: Quaternion = _previous_rotations[index]
			rig.set_bone_pose_rotation(index, previous.slerp(target[index], fraction).normalized())
		var trial = _fit_current_pose()
		if trial.safe and _wrists_safe() and _arm_motion_ratio(delta) <= 1.001:
			trial["smoothed"] = true
			return trial
		fraction *= 0.5
	# Keep an existing feasible branch while the authored motion catches up.
	# The visual budget never requests body backstep: the original capsule /
	# anatomical solver alone decides when actual withdrawal is necessary.
	_apply_rotations(_previous_rotations)
	var retained = _fit_current_pose()
	if retained.safe and _wrists_safe() and _arm_motion_ratio(delta) <= 1.001:
		retained["smoothed"] = true
		return retained
	_apply_rotations(target)
	return result

func _process_modification_with_delta(_delta: float) -> void:
	if not is_instance_valid(fighter) or not is_instance_valid(fighter.opponent):
		return
	fighter._contact_backstep_requested = false
	_modifier_delta = maxf(_delta, 0.0001)
	_guard_step = maxf(0.1, rad_to_deg(_delta * 12.0))
	if not fighter.is_physical_thrust():
		var authored_ready = _rotations()
		if not fighter.is_thrust_weapon():
			_roll_recovering = false
		if not _roll_recovering:
			_grip_contact_session = false
		if _roll_recovering:
			_roll_recovering = false
			_grip_roll_weight = exp(-_delta * 12.0)
			_apply_round_grip()
		if _was_constrained:
			var release = _continuous_fit({"safe": true, "retraction": 0.0}, _delta)
			_was_constrained = bool(release.get("smoothed", false))
		fighter.contact_active = false
		fighter.contact_retraction = 0.0
		if fighter.state in ["idle", "move"]:
			_ready_rotations = authored_ready
		_cache_final_pose()
		return
	_grip_roll_weight = 1.0
	var authored = _rotations()
	if _ready_rotations.is_empty():
		_ready_rotations = authored.duplicate()
	var raw_depth = _required_retraction(_shaft())
	_grip_contact_session = _grip_contact_session or raw_depth > 0.0001 or fighter.contact_latched
	if raw_depth <= 0.0001:
		_apply_round_grip()
		var recovery = {"safe": true, "retraction": 0.0, "smoothed": false}
		if fighter.contact_latched or _was_constrained:
			recovery = _continuous_fit(recovery, _delta)
		_was_constrained = bool(recovery.smoothed)
		fighter.contact_active = _was_constrained
		fighter.contact_retraction = float(recovery.retraction)
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
	# A visual rate limit must never delay an unlanded strike or brake a horse
	# before impact. Only post-contact withdrawal uses a temporal path;
	# pre-hit safety selects feasible anatomical/capsule branches geometrically.
	if fighter.contact_latched:
		result = _continuous_fit(result, _delta)
	_was_constrained = bool(result.get("smoothed", false))
	fighter.contact_active = raw_depth > 0.0001 or amount < 0.999 or _was_constrained
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
