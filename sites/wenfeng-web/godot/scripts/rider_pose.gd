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
var _hip_rest = Transform3D.IDENTITY
var _legs: Array[Dictionary] = []
var _speed_ratio = 0.0
var _configured = false
var _mount_width_m = 0.68

func setup(rig: Skeleton3D, character_model: Node3D) -> bool:
	_rig = rig
	_model = character_model
	_hips = _find_bone("Hips")
	_spine = _find_bone("Spine")
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

func update(_delta: float, speed_ratio = 0.0) -> void:
	# At speed, the thighs lean forward a little. There is deliberately no gait
	# phase: the rider never takes alternating walking steps on the horse.
	_speed_ratio = clampf(speed_ratio, 0.0, 1.0)

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
	for leg in _legs:
		var sign_value = float(leg.sign)
		var forward_bias = 0.65 + 0.035 * _speed_ratio
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
		var lower_direction = Vector3(sign_value * 0.05, -0.98, -0.20).normalized()
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
