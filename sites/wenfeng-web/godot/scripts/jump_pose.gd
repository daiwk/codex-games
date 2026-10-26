extends SkeletonModifier3D

## CC0 lower-body / horse jump overlay. The upper-body animation and complete
## arm branches remain authored; the later contact modifier retains authority.
const DATA_PATH = "res://assets/motion/jump_motion.json"
static var _data: Dictionary = {}
var rig: Skeleton3D
var provider = Callable()
var horse_mode = false
var _bones: Dictionary = {}
var _rests: Dictionary = {}
var _hips = -1
var _spine = -1
var _floor_y = 0.0
var _last_phase = "grounded"
var last_weight = 0.0
var last_source = ""
var _previous_targets: Dictionary = {}
var _landing_entry: Dictionary = {}

func setup(skeleton: Skeleton3D, status_provider: Callable, horse = false) -> void:
	rig = skeleton
	provider = status_provider
	horse_mode = horse
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var table: Dictionary = _data.horse.Gallop_Jump.rotations if horse_mode else _data.human.Jump_Start.rotations
	for index in rig.get_bone_count():
		var label = String(rig.get_bone_name(index))
		for suffix in table:
			if label == suffix or (not horse_mode and label.ends_with(suffix)):
				_bones[suffix] = index
				_rests[suffix] = rig.get_bone_global_rest(index)
				break
	if not horse_mode:
		_hips = int(_bones.get("Hips", -1))
		for index in rig.get_bone_count():
			if String(rig.get_bone_name(index)).ends_with("Spine"):
				_spine = index
		_floor_y = minf(Transform3D(_rests.LeftFoot).origin.y, Transform3D(_rests.RightFoot).origin.y)
	rig.add_child(self)
	rig.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	influence = 1.0

func _sample(clip: Dictionary, bone: String, time: float) -> Quaternion:
	var times: Array = clip.times
	var frames: Array = clip.rotations[bone]
	var frame = clampf(time / maxf(float(clip.duration), 0.001), 0.0, 1.0) * float(times.size() - 1)
	var lo = mini(floori(frame), frames.size() - 1)
	var hi = mini(lo + 1, frames.size() - 1)
	var a: Array = frames[lo]
	var b: Array = frames[hi]
	return Quaternion(a[0], a[1], a[2], a[3]).slerp(Quaternion(b[0], b[1], b[2], b[3]), frame - float(lo))

func _process_modification_with_delta(_delta: float) -> void:
	last_weight = 0.0
	if not provider.is_valid(): return
	var jump: Dictionary = provider.call()
	if not bool(jump.get("active", false)) or bool(jump.get("interrupted", false)):
		_last_phase = "grounded"
		_previous_targets.clear()
		_landing_entry.clear()
		return
	var phase = String(jump.phase)
	var t = float(jump.phase_time)
	var progress = float(jump.flight_progress)
	if phase == "landing" and _last_phase != "landing":
		_landing_entry = _previous_targets.duplicate()
	var weight = 1.0
	var source = "Gallop_Jump" if horse_mode else "Jump_Start"
	var clock = 0.0
	if phase == "anticipation":
		var p = clampf(t / float(jump.anticipation), 0.0, 1.0)
		weight = smoothstep(0.0, 0.65, p)
		clock = lerpf(0.12, 0.35, p) if horse_mode else p * 0.24
	elif bool(jump.airborne):
		if horse_mode:
			clock = lerpf(0.35, 1.13, progress)
		elif progress < 0.25:
			clock = lerpf(0.24, 0.60, progress / 0.25)
		elif progress < 0.65:
			source = "Jump_Idle"
			clock = lerpf(0.0, 0.40, (progress - 0.25) / 0.40)
		else:
			source = "Jump_Land"
			# Extend the feet before the real capsule touches down. The landing
			# phase then absorbs impact through bent knees instead of snapping a
			# permanently tucked airborne body down to the ground in one frame.
			clock = lerpf(0.0, 0.55, (progress - 0.65) / 0.35)
	elif phase == "landing":
		var p = clampf(t / float(jump.landing_duration), 0.0, 1.0)
		weight = 1.0 - smoothstep(0.55, 1.0, p)
		source = "Gallop_Jump" if horse_mode else "Jump_Land"
		clock = lerpf(1.13, 1.45833337, p) if horse_mode else lerpf(0.25, 0.66666669, p)
	var clip: Dictionary = _data.horse[source] if horse_mode else _data.human[source]
	var hip_input = rig.get_bone_global_pose(_hips) if _hips >= 0 else Transform3D.IDENTITY
	var spine_input = rig.get_bone_global_pose(_spine) if _spine >= 0 else Transform3D.IDENTITY
	# Set parent-to-child global rotations while leaving all local offsets and
	# thus every limb length untouched. Source root height is deliberately absent.
	for label in _bones:
		var index = int(_bones[label])
		var pose = rig.get_bone_global_pose(index)
		var desired = Basis(_sample(clip, label, clock)) * Transform3D(_rests[label]).basis
		if phase == "landing" and not horse_mode and _landing_entry.has(label):
			desired = Basis(Quaternion(_landing_entry[label]).slerp(desired.get_rotation_quaternion(), smoothstep(0.0, 0.075, t)))
		pose.basis = Basis(pose.basis.get_rotation_quaternion().slerp(desired.get_rotation_quaternion(), weight))
		_previous_targets[label] = pose.basis.get_rotation_quaternion()
		if label == "Hips":
			pose.origin = hip_input.origin.lerp(Transform3D(_rests.Hips).origin, weight)
		rig.set_bone_global_pose(index, pose)
	if _hips >= 0:
		var hip = rig.get_bone_global_pose(_hips)
		var grounding = 1.0 if phase in ["anticipation", "landing"] else 0.0
		var feet_y = minf(rig.get_bone_global_pose(int(_bones.LeftFoot)).origin.y,
			rig.get_bone_global_pose(int(_bones.RightFoot)).origin.y)
		hip.origin.y += (_floor_y - feet_y) * grounding * weight
		rig.set_bone_global_pose(_hips, hip)
		# Hip/leg articulation must not reorient the attacking shoulders/hands.
		spine_input.origin += hip.origin - hip_input.origin
		rig.set_bone_global_pose(_spine, spine_input)
	last_weight = weight
	last_source = source
	_last_phase = phase
