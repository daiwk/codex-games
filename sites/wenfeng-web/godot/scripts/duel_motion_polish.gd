extends "res://scripts/thrust_contact.gd"

## Duel-only continuity on the two newly authored foot spear phrases. The
## complete existing capsule / round-handle / anatomical solver remains the
## feasibility test. Interpolating independent wrists after IK would lose the
## physical handle, so every intermediate pose is solved again before use.
var _phrase_settling = false
var continuity_samples = 0
var continuity_limited = 0
var continuity_fallbacks = 0
var _previous_body_rotations: Array[Quaternion] = []
var _previous_hip_position = Vector3.ZERO

func reset_motion() -> void:
	super.reset_motion()
	_phrase_settling = false
	continuity_samples = 0
	continuity_limited = 0
	continuity_fallbacks = 0
	_previous_body_rotations.clear()
	_previous_hip_position = Vector3.ZERO

func _body_rotations() -> Array[Quaternion]:
	var values: Array[Quaternion] = []
	for index in rig.get_bone_count(): values.append(rig.get_bone_pose_rotation(index))
	return values

func _continuous_fit(target_result: Dictionary, delta: float) -> Dictionary:
	if not is_instance_valid(fighter) or fighter.state not in ["attack", "idle", "move", "block"]:
		return super._continuous_fit(target_result, delta)
	var phrase = String(fighter.current_clip).begins_with("DuelDragon") or String(fighter.current_clip).begins_with("DuelTiger")
	if not _phrase_settling and not phrase:
		return super._continuous_fit(target_result, delta)
	if _previous_body_rotations.size() != rig.get_bone_count():
		return super._continuous_fit(target_result, delta)
	var hips = _bone("Hips")
	var target_body = _body_rotations()
	var target_position = rig.get_bone_pose_position(hips)
	var ratio = _arm_motion_ratio(delta)
	if bool(target_result.safe) and ratio <= 1.0: return target_result
	var fraction = minf(1.0, 1.0 / maxf(ratio, 0.0001))
	# A crouching thrust changes pelvis translation as well as rotations.
	# Smoothing only the arms against the already-risen pelvis can invalidate
	# the preceding feasible grasp and force an elbow branch jump. Advance the
	# complete pose together, then solve and validate its real shaft again.
	for attempt in 12:
		for index in rig.get_bone_count():
			rig.set_bone_pose_rotation(index, _previous_body_rotations[index].slerp(target_body[index], fraction).normalized())
		rig.set_bone_pose_position(hips, _previous_hip_position.lerp(target_position, fraction))
		var trial = _fit_current_pose()
		if trial.safe and _wrists_safe() and _arm_motion_ratio(delta) <= 1.001:
			trial["smoothed"] = true
			return trial
		fraction *= 0.5
	for index in rig.get_bone_count(): rig.set_bone_pose_rotation(index, target_body[index])
	rig.set_bone_pose_position(hips, target_position)
	return super._continuous_fit(target_result, delta)

func _process_modification_with_delta(delta: float) -> void:
	if is_instance_valid(fighter) and fighter.has_method("update_trial_contact_recovery"): fighter.call("update_trial_contact_recovery")
	if is_instance_valid(fighter) and fighter.has_method("flesh_source_trial_active") and bool(fighter.call("flesh_source_trial_active")):
		# No opponent-capsule retraction / sideguard / historical body rewind.
		# The exact current AnimationPlayer output remains authoritative.
		fighter._contact_backstep_requested = false
		fighter.contact_active = false
		fighter.contact_retraction = 0.0
		_was_constrained = false
		_roll_recovering = false
		_grip_contact_session = false
		_phrase_settling = false
		_previous_body_rotations.clear()
		_previous_hip_position = Vector3.ZERO
		if fighter.state in ["idle", "move"]: _ready_rotations = _rotations()
		_cache_final_pose()
		return
	var prior_rotations = _previous_rotations.duplicate()
	var prior_frames = _previous_arm_frames.duplicate(true)
	var prior_axis = _previous_shaft_axis
	super._process_modification_with_delta(delta)
	if not is_instance_valid(fighter) or not is_instance_valid(fighter.opponent) or fighter.mounted:
		return
	if fighter.state not in ["attack", "idle", "move", "block"]: _phrase_settling = false
	var phrase = String(fighter.current_clip).begins_with("DuelDragon") or String(fighter.current_clip).begins_with("DuelTiger")
	if phrase and fighter.state == "attack": _phrase_settling = true
	if not _phrase_settling or fighter.state not in ["attack", "idle", "move", "block"]:
		_previous_body_rotations = _body_rotations()
		_previous_hip_position = rig.get_bone_pose_position(_bone("Hips"))
		return
	if prior_rotations.is_empty() or prior_frames.is_empty():
		_previous_body_rotations = _body_rotations()
		_previous_hip_position = rig.get_bone_pose_position(_bone("Hips"))
		return
	# The superclass caches its final target at the end of every tick. Restore
	# the preceding *drawn* frame while walking toward that target, including
	# the first resistance frame and the later blend from withdrawal to idle.
	_previous_rotations = prior_rotations
	_previous_arm_frames = prior_frames
	_previous_shaft_axis = prior_axis
	continuity_samples += 1
	var ratio = _arm_motion_ratio(delta)
	var safe = _required_retraction(_shaft()) <= RESIDUAL_TOLERANCE and _wrists_safe()
	var result = _continuous_fit({"safe": safe, "retraction": fighter.contact_retraction}, delta)
	if bool(result.get("smoothed", false)): continuity_limited += 1
	elif ratio > 1.001: continuity_fallbacks += 1
	# Preserve the superclass' contact/braking decisions. This layer changes
	# only the feasible visible pose; real strikes still sample its actual tip.
	_cache_final_pose()
	_previous_body_rotations = _body_rotations()
	_previous_hip_position = rig.get_bone_pose_position(_bone("Hips"))
	if not phrase and ratio <= 1.0 and fighter.state in ["idle", "move"]:
		_phrase_settling = false
