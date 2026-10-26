extends RefCounted

# A wrist must not absorb the forearm's complete pronation/supination after
# elbow IK. Share twist along the elbow-to-wrist axis before restoring the
# authored palm orientation. This changes rotation only, never bone length.
const MAX_FOREARM_ROLL = deg_to_rad(100.0)
const MAX_WRIST_SWING = deg_to_rad(40.0)
const MAX_WRIST_TWIST = deg_to_rad(35.0)

static func _shortest(rotation: Quaternion) -> Quaternion:
	var unit = rotation.normalized()
	return Quaternion(-unit.x, -unit.y, -unit.z, -unit.w) if unit.w < 0.0 else unit

static func _split(rotation: Quaternion, axis: Vector3) -> Dictionary:
	var unit = _shortest(rotation)
	var direction = axis.normalized()
	var projection = Vector3(unit.x, unit.y, unit.z).dot(direction)
	var twist = Quaternion(direction.x * projection, direction.y * projection, direction.z * projection, unit.w)
	if projection * projection + unit.w * unit.w < 0.00000001:
		twist = Quaternion.IDENTITY
	else:
		twist = _shortest(twist)
	var swing = _shortest(unit * twist.inverse())
	return {"swing": swing.get_angle(),
		"twist": 2.0 * atan2(Vector3(twist.x, twist.y, twist.z).dot(direction), twist.w)}

static func measure(forearm: Basis, hand: Basis, rest_hand: Basis, axis: Vector3) -> Dictionary:
	var neutral = forearm.orthonormalized() * rest_hand.orthonormalized()
	var delta = hand.orthonormalized() * neutral.inverse()
	return _split(delta.get_rotation_quaternion(), axis)

static func distribute(forearm: Basis, desired_hand: Basis, rest_hand: Basis, axis: Vector3, preferred_forearm: Variant = null) -> Dictionary:
	if axis.length_squared() < 0.00000001:
		return {"basis": forearm, "safe": false, "swing": PI, "twist": PI, "roll": 0.0}
	var before = measure(forearm, desired_hand, rest_hand, axis)
	var roll = clampf(float(before.twist), -MAX_FOREARM_ROLL, MAX_FOREARM_ROLL)
	var candidates: Array[float] = [roll]
	if preferred_forearm is Basis:
		var difference = Basis(preferred_forearm).orthonormalized() * forearm.orthonormalized().inverse()
		var preferred = float(_split(difference.get_rotation_quaternion(), axis).twist)
		candidates.push_front(clampf(preferred, -MAX_FOREARM_ROLL, MAX_FOREARM_ROLL))
		# The wrist has a cone, not a zero-twist equality. Use its remaining
		# natural range to keep the actual forearm roll on the continuous branch.
		for boundary in [-MAX_WRIST_TWIST + 0.0001, MAX_WRIST_TWIST - 0.0001]:
			candidates.append(clampf(float(before.twist) + boundary, -MAX_FOREARM_ROLL, MAX_FOREARM_ROLL))
	var best: Dictionary = {}
	var best_score = INF
	for candidate in candidates:
		var result = Basis(axis.normalized(), candidate) * forearm
		var after = measure(result, desired_hand, rest_hand, axis)
		var safe = float(after.swing) <= MAX_WRIST_SWING + 0.0001 and absf(float(after.twist)) <= MAX_WRIST_TWIST + 0.0001
		var score = Basis(preferred_forearm).get_rotation_quaternion().angle_to(result.get_rotation_quaternion()) if preferred_forearm is Basis else absf(candidate - roll)
		if (safe and (best.is_empty() or not best.safe or score < best_score)) or best.is_empty():
			best = {"basis": result, "roll": candidate, "swing": after.swing, "twist": after.twist, "safe": safe}
			best_score = score
	return best
