extends SkeletonModifier3D
class_name RiderPose

## Add as a direct child of the character's Skeleton3D. SkeletonModifier3D runs
## after AnimationPlayer and before skinning, so walking clips cannot overwrite
## the seat. The original GLB and its animation resources remain untouched.
##
##   var rider = preload("res://scripts/rider_pose.gd").new()
##   rider.setup(fighter.skeleton, fighter.model)
##   rider.active = mounted
##   fighter.model.position.y = saddle_height - rider.rest_hip_height()
##   rider.update(delta, mounted_speed_ratio)
##
## The fighter owns model height, horse motion and clip remapping. This modifier
## anchors the pelvis, preserves the animated upper body's pose relative to the
## seat, and replaces only the legs with a spread, bent-knee riding posture.

var _rig: Skeleton3D
var _model: Node3D
var _hips = -1
var _spine = -1
var _chest = -1
var _head = -1
var _hip_rest = Transform3D.IDENTITY
var _legs: Array[Dictionary] = []
var _speed_ratio = 0.0
var _configured = false
var _mount_width_m = 0.68
var _lean = Vector3.ZERO
var _lean_velocity = Vector3.ZERO
var _activity_weight = 1.0
var _activity_provider = Callable()
var last_secondary = Vector3.ZERO
var _speed_ready = false
var _jump_provider = Callable()
var last_jump_tuck = 0.0

func setup(rig: Skeleton3D, character_model: Node3D) -> bool:
	_rig = rig
	_model = character_model
	_hips = _find_bone("Hips")
	_spine = _find_bone("Spine")
	_chest = _find_bone("Spine2")
	_head = _find_bone("Head")
	if _hips < 0 or _spine < 0:
		push_error("RiderPose requires the supplied Mixamo pelvis and spine")
		return false
	_hip_rest = _rig.get_bone_global_rest(_hips)
	_legs.clear()
	for side in ["Left", "Right"]:
		var upper = _find_bone(side + "UpLeg")
		var lower = _find_bone(side + "Leg")
		var foot = _find_bone(side + "Foot")
		var toe = _find_bone(side + "ToeBase")
		var end = _find_bone(side + "Toe_End")
		if upper < 0 or lower < 0 or foot < 0 or toe < 0:
			push_error("RiderPose requires a complete " + side + " leg")
			return false
		var upper_rest = _rig.get_bone_global_rest(upper)
		var lower_rest = _rig.get_bone_global_rest(lower)
		var foot_rest = _rig.get_bone_global_rest(foot)
		var toe_rest = _rig.get_bone_global_rest(toe)
		_legs.append({"upper": upper, "lower": lower, "foot": foot, "toe": toe, "end": end,
			"sign": 1.0 if side == "Left" else -1.0,
			"upper_rest": upper_rest, "lower_rest": lower_rest, "foot_rest": foot_rest,
			"toe_rest": toe_rest,
			"end_rest": _rig.get_bone_global_rest(end) if end >= 0 else Transform3D.IDENTITY,
			"thigh_direction": lower_rest.origin - upper_rest.origin,
			"shin_direction": foot_rest.origin - lower_rest.origin,
			"foot_direction": toe_rest.origin - foot_rest.origin})
	if get_parent() != _rig:
		if get_parent() != null:
			reparent(_rig)
		else:
			_rig.add_child(self)
	# Match the existing AnimationPlayer's physics callback. The modifier stack
	# remains the final authority after animation has supplied the attack pose.
	_rig.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	influence = 1.0
	_configured = true
	return true

func update(delta: float, speed_ratio = 0.0, turn_rate = 0.0,
		saddle_basis = Basis.IDENTITY, activity = 1.0) -> void:
	# A rider absorbs the actual saddle's pitch and roll through the waist.
	# Acceleration/braking and turns settle on a damped spring; the hips and
	# stirrups still remain anchored instead of bobbing through the horse.
	var dt = clampf(delta, 0.0, 0.05)
	var next_speed = clampf(speed_ratio, 0.0, 1.0)
	var acceleration = (next_speed - _speed_ratio) / maxf(dt, 0.001) if _speed_ready and dt > 0.0 else 0.0
	_speed_ready = true
	_speed_ratio = next_speed
	_activity_weight = clampf(activity, 0.0, 1.0)
	var saddle_angles: Vector3 = saddle_basis.get_euler()
	var target = Vector3(
		clampf(next_speed * 0.033 - acceleration * 0.024 + saddle_angles.x * 0.20, -0.065, 0.065),
		clampf(-turn_rate * 0.010, -0.028, 0.028),
		clampf(-turn_rate * 0.022 + saddle_angles.z * 0.18, -0.060, 0.060))
	var steps = maxi(1, ceili(dt / 0.0084))
	var step = dt / float(steps)
	for index in steps:
		_lean_velocity += ((target - _lean) * 112.0 - _lean_velocity * 21.2) * step
		_lean += _lean_velocity * step

func reset_motion() -> void:
	_speed_ratio = 0.0
	_lean = Vector3.ZERO
	_lean_velocity = Vector3.ZERO
	_activity_weight = 1.0
	last_secondary = Vector3.ZERO
	_speed_ready = false
	last_jump_tuck = 0.0

func set_activity_provider(provider: Callable) -> void:
	_activity_provider = provider

func set_jump_provider(provider: Callable) -> void:
	_jump_provider = provider

func current_activity_weight() -> float:
	# State/contact windows advance in physics, which can run several times
	# before render calls update(). Read a live provider at the point of use.
	if _activity_provider.is_valid():
		return clampf(float(_activity_provider.call()), 0.0, 1.0)
	return _activity_weight

func set_mount_width(width_m: float) -> void:
	_mount_width_m = clampf(width_m, 0.20, 1.10)

func rest_hip_height() -> float:
	if not _configured:
		return 0.0
	return (_rig.to_global(_hip_rest.origin) - _model.global_position).y

func rest_hip_position_in_model() -> Vector3:
	if not _configured:
		return Vector3.ZERO
	return _model.to_local(_rig.to_global(_hip_rest.origin))

func _find_bone(suffix: String) -> int:
	for index in _rig.get_bone_count():
		# Godot sanitizes the GLB's mixamorig: prefix during import.
		if _rig.get_bone_name(index).ends_with(suffix):
			return index
	return -1

func _set_global_basis(index: int, basis: Basis) -> void:
	var pose = _rig.get_bone_global_pose(index)
	pose.basis = basis
	_rig.set_bone_global_pose(index, pose)

func _process_modification_with_delta(_delta: float) -> void:
	if not _configured:
		return
	var hip_pose = _rig.get_bone_global_pose(_hips)
	var spine_pose = _rig.get_bone_global_pose(_spine)
	# Remove the ground clip's pelvis walking/root motion, including flips from
	# dodge/death clips. Compensating the spine preserves every upper-body bone's
	# authored world orientation and relative position, shifted onto the saddle.
	spine_pose.origin += _hip_rest.origin - hip_pose.origin
	_rig.set_bone_global_pose(_hips, _hip_rest)
	_rig.set_bone_global_pose(_spine, spine_pose)
	# Preserve the attack's upper-body pose at contact. During travel, distribute
	# the saddle response through waist/chest and stabilize the gaze softly.
	var tuck = 0.0
	var jump_lean = 0.0
	if _jump_provider.is_valid():
		var jump: Dictionary = _jump_provider.call()
		if bool(jump.get("active", false)) and not bool(jump.get("interrupted", false)):
			if bool(jump.airborne):
				tuck = sin(float(jump.flight_progress) * PI)
				jump_lean = 0.075 * tuck
			elif jump.phase == "anticipation":
				tuck = smoothstep(0.0, float(jump.anticipation), float(jump.phase_time)) * 0.3
			elif jump.phase == "landing":
				tuck = (1.0 - smoothstep(0.0, float(jump.landing_duration), float(jump.phase_time))) * 0.4
	last_jump_tuck = tuck
	var secondary = (_lean + Vector3(jump_lean, 0.0, 0.0)) * current_activity_weight()
	last_secondary = secondary
	for data in [[_spine, 0.65], [_chest, 0.35], [_head, -0.35]]:
		if int(data[0]) >= 0:
			var pose = _rig.get_bone_global_pose(int(data[0]))
			pose.basis = Basis.from_euler(secondary * float(data[1])) * pose.basis
			_rig.set_bone_global_pose(int(data[0]), pose)
	for leg in _legs:
		var sign_value = float(leg.sign)
		var forward_bias = 0.65 + 0.035 * _speed_ratio + 0.10 * tuck
		var upper_direction = Vector3(sign_value * 0.55, -0.40, forward_bias).normalized()
		# Resolve the required spread in metres for each supplied rig instead of
		# assuming the six characters have equal thigh lengths or hip spacing.
		# The knee clears the measured horse belly by at least 2.5 cm; the ankle
		# then hangs slightly farther out. Existing wider poses remain unchanged.
		var scale_x = maxf(_rig.global_basis.x.length(), 0.001)
		var target_half_width = (_mount_width_m * 0.5 + 0.025) / scale_x
		var upper_rest: Transform3D = leg.upper_rest
		var thigh_length = Vector3(leg.thigh_direction).length()
		var required_x = (target_half_width - sign_value * upper_rest.origin.x) / maxf(thigh_length, 0.001)
		var outward = clampf(maxf(absf(upper_direction.x), required_x), 0.0, 0.90)
		var vertical_forward = Vector2(-0.40, forward_bias).normalized() * sqrt(maxf(0.0, 1.0 - outward * outward))
		upper_direction = Vector3(sign_value * outward, vertical_forward.x, vertical_forward.y)
		var lower_direction = Vector3(sign_value * 0.05, -0.98, -0.20 - 0.10 * tuck).normalized()
		var foot_direction = Vector3(sign_value * 0.10, 0.08, 1.0).normalized()
		var thigh_turn = Basis(Quaternion(Vector3(leg.thigh_direction).normalized(), upper_direction))
		var shin_turn = Basis(Quaternion(Vector3(leg.shin_direction).normalized(), lower_direction))
		var foot_turn = Basis(Quaternion(Vector3(leg.foot_direction).normalized(), foot_direction))
		_set_global_basis(int(leg.upper), thigh_turn * Transform3D(leg.upper_rest).basis)
		_set_global_basis(int(leg.lower), shin_turn * Transform3D(leg.lower_rest).basis)
		_set_global_basis(int(leg.foot), foot_turn * Transform3D(leg.foot_rest).basis)
		_set_global_basis(int(leg.toe), foot_turn * Transform3D(leg.toe_rest).basis)
		if int(leg.end) >= 0:
			_set_global_basis(int(leg.end), foot_turn * Transform3D(leg.end_rest).basis)
