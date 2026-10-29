extends RefCounted

# Scoped extraction of the existing 60ms common weapon-frame experiment.
# Pose/clock/IK behavior and the contact modifier's existing flags are unchanged.
const SOURCE_HASH = "23ba8aabd2bafa6d06ff9332008b1828fa27d1d56d9f1def85ea0acc3dfafe29"
const SOURCE_PATH = "res://assets/motion/parry_frame_source.json"
var fighter
var enabled = false
var _object: Dictionary = {}
var _rows: Array = []
var _result: Dictionary = {}

func setup(owner_fighter) -> void:
	fighter = owner_fighter
	# Main configures identity/equipment before _ready. Do not require visuals
	# yet: super._ready() ends in reset_fighter -> the Actor's play_clip hook.
	if not fighter.is_player or fighter.mounted or fighter.character_id != "zhaoyun" or not fighter.is_thrust_weapon(): return
	if FileAccess.get_sha256("res://assets/characters/zhaoyun.glb") != SOURCE_HASH:
		push_error("Weapon transition source model does not match the frozen 23ba input")
		return
	var source = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	if not source is Dictionary or String(source.get("sha256", "")) != SOURCE_HASH:
		push_error("Weapon transition table does not match the frozen 23ba input")
		return
	_rows = source.get("rows", [])
	if _rows.is_empty():
		push_error("Weapon transition table has no source rows")
		return
	enabled = true

func on_clip(clip: String) -> void:
	if enabled and clip == "GuardBreak" and fighter.state == "stagger" and fighter.trial_contact_scope:
		_begin_object_parry()
	else:
		_object.clear()

func result() -> Dictionary:
	return _result

func _frame_v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func _frame_q(a: Array) -> Quaternion:
	return Quaternion(a[0], a[1], a[2], a[3]).normalized()

func _object_basis(axis: Vector3, right_hand: Basis) -> Basis:
	var side = right_hand.x - axis * right_hand.x.dot(axis)
	if side.length_squared() < 0.000001: side = Vector3.UP.cross(axis)
	side = side.normalized()
	return Basis(side, axis, side.cross(axis)).orthonormalized()

func _begin_object_parry() -> void:
	_object.clear()
	_result.clear()
	if not is_instance_valid(fighter.thrust_contact) or not fighter.thrust_contact.pose_cached: return
	var right: Vector3 = fighter.thrust_contact.right_palm_local
	var left: Vector3 = fighter.thrust_contact.left_palm_local
	var axis = (right-left).normalized() * float(fighter.grip_config.axis_sign)
	var rq: Quaternion = fighter.thrust_contact.right_wrist_basis.get_rotation_quaternion()
	var lq = Quaternion.IDENTITY
	for arm in fighter.thrust_contact._arms:
		if arm.left and fighter.thrust_contact._previous_arm_frames.has(arm.lower):
			lq = Basis(fighter.thrust_contact._previous_arm_frames[arm.lower].world_hand).get_rotation_quaternion()
	var basis = _object_basis(axis, Basis(rq))
	_object = {"mid": (right+left)*0.5, "span":right.distance_to(left),
		"q":basis.get_rotation_quaternion(), "rq":basis.get_rotation_quaternion().inverse()*rq,
		"lq":basis.get_rotation_quaternion().inverse()*lq}

func apply_object_parry(contact: Node, delta: float) -> bool:
	_result = {"active":false}
	if not enabled or _object.is_empty() or fighter.state != "stagger" or fighter.trial_contact_outcome != "parry": return false
	var raw_time = clampf(fighter.animation_player.current_animation_position, 0.0, float(_rows[-1].time))
	var f = raw_time * 120.0
	var i = mini(int(f),_rows.size()-1)
	var j = mini(i+1,_rows.size()-1)
	var mix = clampf(f-i,0.0,1.0)
	var a: Dictionary = _rows[i]
	var b: Dictionary = _rows[j]
	var right = _frame_v(a.right_palm).lerp(_frame_v(b.right_palm),mix)
	var left = _frame_v(a.left_palm).lerp(_frame_v(b.left_palm),mix)
	var rq = _frame_q(a.right_hand_q).slerp(_frame_q(b.right_hand_q),mix)
	var lq = _frame_q(a.left_hand_q).slerp(_frame_q(b.left_hand_q),mix)
	var axis = (right-left).normalized()*float(fighter.grip_config.axis_sign)
	var target = _object_basis(axis,Basis(rq)).get_rotation_quaternion()
	var amount = smoothstep(0.0,0.06,fighter.action_time)
	var q: Quaternion = Quaternion(_object.q).slerp(target,amount)
	var mid: Vector3 = Vector3(_object.mid).lerp((right+left)*0.5,amount)
	var span = lerpf(float(_object.span),right.distance_to(left),amount)
	axis = Basis(q).y
	right = mid+axis*span*0.5*float(fighter.grip_config.axis_sign)
	left = mid-axis*span*0.5*float(fighter.grip_config.axis_sign)
	var poses = {}
	for arm in contact._arms:
		for index in [arm.upper,arm.lower,arm.hand]: poses[index]=fighter.skeleton.get_bone_pose_rotation(index)
	var safe = true
	contact._modifier_delta=maxf(delta,0.0001)
	for arm in contact._arms:
		var target_rel: Quaternion = target.inverse()*(lq if arm.left else rq)
		var from_rel: Quaternion = _object.lq if arm.left else _object.rq
		var desired = Basis(q*from_rel.slerp(target_rel,amount))
		var hand: Transform3D = fighter.skeleton.get_bone_global_pose(arm.hand)
		hand.basis=desired
		fighter.skeleton.set_bone_global_pose(arm.hand,hand)
		safe = contact._arm_ik(arm,fighter.skeleton.to_global(left if arm.left else right)) and safe
	var right_error = contact._palm_local(false).distance_to(right)*fighter.model.scale.x
	var left_error = contact._palm_local(true).distance_to(left)*fighter.model.scale.x
	safe = safe and maxf(right_error,left_error)<0.002
	_result={"active":true,"safe":safe,"amount":amount,"raw_time":raw_time,"right_error_m":right_error,"left_error_m":left_error,"span_m":span*fighter.model.scale.x}
	if not safe:
		for index in poses:fighter.skeleton.set_bone_pose_rotation(index,poses[index])
		return false
	contact._was_constrained=false
	contact._roll_recovering=false
	contact._phrase_settling=false
	contact._cache_final_pose()
	return true
