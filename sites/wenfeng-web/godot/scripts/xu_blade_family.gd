extends RefCounted

class ReceivingHand extends SkeletonModifier3D:
	var family
	func _process_modification_with_delta(_delta: float) -> void:
		if family != null: family.apply_hand_pose()

# One coherent anatomical source clock. The weapon follows the existing palm
# socket; no wrist target, handle-axis roll search or independent arm retiming.
const ASSET = "res://assets/motion/xuchu_blade_family.glb"
const META = "res://assets/motion/xuchu_blade_family.json"
var fighter
var enabled = false
var action_active = false
var stance_ready = false
var mode = ""
var data: Dictionary = {}
var sequence: Array = []
var source_alias = ""
var source_time = 0.0
var elapsed = 0.0
var last_root = Vector3.ZERO
var pending_root = Vector3.ZERO
var start_basis = Basis.IDENTITY
var pending_strike: Dictionary = {}
var hand_open = 0.0
var catch_elapsed = -1.0
var returning = false
var has_released = false
var _cast_cancel_pending = false
var repeat_requested = false
var _open_fingers: Dictionary = {}
var _original_grip = Quaternion.IDENTITY
var _anatomical_grip = Quaternion.IDENTITY
var _grip_from = Quaternion.IDENTITY
var _grip_goal = Quaternion.IDENTITY
var _grip_clock = 1.0
var _grip_duration = 0.0

func setup(owner_fighter) -> void:
	fighter = owner_fighter
	enabled = not fighter.mounted and fighter.character_id == "xuchu" and not fighter.is_two_handed()
	if not enabled: return
	data = JSON.parse_string(FileAccess.get_file_as_string(META))
	_original_grip = fighter.grip.quaternion
	# Official UAL2 viewer's fixed sword attachment defines the blade plane.
	# This calibrates equipment about its round hilt; it never changes a wrist.
	_anatomical_grip = _original_grip * Quaternion(Vector3.UP, deg_to_rad(91.35219431993688))
	_grip_goal = _original_grip
	var scene = (load(ASSET) as PackedScene).instantiate()
	scene.visible = false
	fighter.add_child(scene)
	var player: AnimationPlayer = fighter._find_node(scene, "AnimationPlayer")
	var rig: Skeleton3D = fighter._find_node(scene, "Skeleton3D")
	var library = AnimationLibrary.new()
	for key in player.get_animation_list():
		var alias = String(key).get_slice("/", String(key).get_slice_count("/") - 1)
		if not alias.begins_with("XuBlade"): continue
		library.add_animation(alias, player.get_animation(key).duplicate(true))
		fighter.animation_names[alias] = "XuBlade/" + alias
	fighter.animation_player.add_animation_library("XuBlade", library)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for key in player.get_animation_list():
		if String(key).ends_with("XuBladeThrow"):
			player.play(key, 0.0)
			player.seek(0.5, true)
			player.advance(0.0)
			break
	for index in rig.get_bone_count():
		var label = String(rig.get_bone_name(index))
		if label.contains("RightHand") and label != "mixamorig_RightHand":
			var live = fighter.skeleton.find_bone(label)
			if live >= 0: _open_fingers[live] = rig.get_bone_pose_rotation(index)
	scene.free()
	var receiving_hand = ReceivingHand.new()
	receiving_hand.family = self
	fighter.skeleton.add_child(receiving_hand)
	stance_ready = true
	play_ready(0.18)
	use_anatomical_grip(0.0)

func reset() -> void:
	action_active = false
	stance_ready = enabled
	mode = ""
	sequence.clear()
	pending_root = Vector3.ZERO
	pending_strike.clear()
	hand_open = 0.0
	catch_elapsed = -1.0
	returning = false
	has_released = false
	_cast_cancel_pending = false
	repeat_requested = false

func owns_profile(profile: Dictionary) -> bool:
	return enabled and bool(profile.get("xu_blade_family", false))

func duration(alias: String) -> float:
	return float(data.clips[alias].duration)

func _part(alias: String, seconds = -1.0) -> Dictionary:
	return {"alias":alias, "duration":duration(alias) if seconds < 0.0 else seconds}

func begin(kind: String) -> void:
	# The final delta of J1/J2 belongs to the tick that chains into the next
	# source phrase. Preserve that queued physical root motion across play().
	var carry = pending_root if action_active and mode == "light" and kind == "light" else Vector3.ZERO
	action_active = true
	stance_ready = false
	mode = kind
	use_anatomical_grip(0.075)
	if kind in ["throw", "volley"]: has_released = false
	repeat_requested = false
	pending_root = carry
	pending_strike.clear()
	start_basis = fighter.global_basis
	elapsed = 0.0
	last_root = Vector3.ZERO
	source_alias = ""
	match kind:
		"light":
			sequence = [_part(String(fighter.attack.clip))]
			if float(fighter.attack.get("family_entry", 0.0)) > 0.0:
				sequence.push_front(_part("XuBladeReady", float(fighter.attack.family_entry)))
		"throw": sequence = [_part("XuBladeThrow")]
		"volley": sequence = [_part("XuBladeThrowWindup", 0.55), _part("XuBladeThrowFollow")]
		"counter":
			var response = _part("XuBladeJ1")
			response["blend"] = 0.14
			sequence = [_part("XuBladeGuardEnter", 0.56), response]
	fighter.tempo_profile = {}
	fighter.combat_motion.influence = 0.0
	fighter.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var entry_blend = float(fighter.attack.get("family_entry", 0.0)) if kind == "light" else 0.0
	if entry_blend > 0.0: use_anatomical_grip(entry_blend)
	_sample(0.0, maxf(entry_blend, 0.075) if carry.is_zero_approx() else 0.0)

func _curve(alias: String, time: float) -> Vector3:
	var clip: Dictionary = data.clips[alias]
	var rows: Array = clip.root_delta_model
	var f = clampf(time / float(clip.duration), 0.0, 1.0) * (rows.size() - 1)
	var lo = mini(int(f), rows.size() - 1)
	var hi = mini(lo + 1, rows.size() - 1)
	var a: Array = rows[lo]
	var b: Array = rows[hi]
	return Vector3(a[0], 0.0, a[2]).lerp(Vector3(b[0], 0.0, b[2]), f - lo)

func _sample(time: float, blend = 0.0, delta = 0.0) -> void:
	var offset = 0.0
	var root = Vector3.ZERO
	for index in sequence.size():
		var part: Dictionary = sequence[index]
		var alias: String = part.alias
		var seconds = float(part.duration)
		if time <= offset + seconds + 0.000001 or index == sequence.size() - 1:
			source_time = clampf((time - offset) / seconds, 0.0, 1.0) * duration(alias)
			root += _curve(alias, source_time)
			if source_alias != alias:
				source_alias = alias
				var key: String = fighter.animation_names[alias]
				fighter.animation_player.get_animation(key).loop_mode = Animation.LOOP_NONE
				fighter.animation_player.play(key, float(part.get("blend", blend)), duration(alias) / seconds)
				fighter.current_clip = alias
			# Advance the complete pose by one source clock. seek() by itself
			# does not progress AnimationPlayer's blend clock.
			fighter.animation_player.advance(delta)
			fighter.animation_player.seek(source_time, true)
			fighter.animation_player.advance(0.0)
			break
		root += _curve(alias, duration(alias))
		offset += seconds
	pending_root += root - last_root
	last_root = root
	_sync_weapon()

func prepare_tick(delta: float) -> void:
	if not enabled: return
	if _cast_cancel_pending:
		_cast_cancel_pending = false
		fighter._cancel_skill("cancel")
		fighter._idle()
		return
	if _grip_clock < _grip_duration:
		_grip_clock += delta
		fighter.grip.quaternion = _grip_from.slerp(_grip_goal, smoothstep(0.0, _grip_duration, _grip_clock))
	if catch_elapsed >= 0.0:
		catch_elapsed += delta
		hand_open = 1.0 - smoothstep(0.0, 0.10, catch_elapsed)
		if catch_elapsed >= 0.10: catch_elapsed = -1.0
	if not action_active: return
	if fighter.state not in ["attack", "skill", "ultimate"]:
		legacy_clip()
		return
	elapsed = fighter.action_time
	if mode == "light" and fighter.combo_buffered and fighter.combo < 2:
		elapsed = minf(elapsed, float(fighter.attack.combo_at))
	_sample(elapsed, 0.0, delta)
	if mode in ["throw", "volley"] and not has_released:
		var release = 0.55 if mode == "volley" else 11.0 / 30.0
		hand_open = smoothstep(release - 0.08, release, elapsed)

func _sync_weapon() -> void:
	fighter.skeleton.force_update_all_bone_transforms()
	var socket = fighter.grip.get_parent()
	if socket is BoneAttachment3D:
		var hand = fighter.skeleton.find_bone(socket.bone_name)
		if hand >= 0: socket.transform = fighter.skeleton.get_bone_global_pose(hand)

func apply_motion(delta: float) -> void:
	var world = start_basis * pending_root * fighter.model.scale.x
	fighter.velocity.x = world.x / maxf(delta, 0.00001)
	fighter.velocity.z = world.z / maxf(delta, 0.00001)
	pending_root = Vector3.ZERO

func queue_strike(profile: Dictionary) -> void:
	pending_strike = profile.duplicate(true)
	pending_strike["source_sample_time"] = source_time
	pending_strike["source_sample_tick"] = Engine.get_physics_frames()

func post_move() -> void:
	if pending_strike.is_empty(): return
	_sync_weapon()
	var profile = pending_strike.duplicate(true)
	pending_strike.clear()
	if action_active and fighter.state in ["attack", "skill"] and not fighter.hit_landed:
		fighter.strike_requested.emit(fighter, profile)

func finish() -> void:
	if mode == "light" and repeat_requested and fighter.state == "attack":
		if fighter._begin_attack(0): return
	action_active = false
	stance_ready = true
	pending_strike.clear()
	fighter._idle()

func play_ready(blend = 0.10) -> void:
	use_anatomical_grip(blend)
	action_active = false
	stance_ready = true
	fighter.combat_motion.influence = 1.0
	fighter.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	var key: String = fighter.animation_names.XuBladeReady
	fighter.animation_player.get_animation(key).loop_mode = Animation.LOOP_LINEAR
	fighter.animation_player.play(key, blend, 1.0)
	fighter.current_clip = "Idle"

func _set_grip(goal: Quaternion, seconds: float) -> void:
	if _grip_goal.is_equal_approx(goal) and fighter.grip.quaternion.is_equal_approx(goal): return
	_grip_from = fighter.grip.quaternion
	_grip_goal = goal
	_grip_clock = 0.0
	_grip_duration = seconds
	if seconds <= 0.0: fighter.grip.quaternion = goal

func use_original_grip(seconds = 0.075) -> void:
	if enabled: _set_grip(_original_grip, seconds)

func use_anatomical_grip(seconds = 0.075) -> void:
	_set_grip(_anatomical_grip, seconds)

func legacy_clip() -> void:
	use_original_grip()
	action_active = false
	stance_ready = false
	mode = ""
	pending_root = Vector3.ZERO
	pending_strike.clear()
	fighter.combat_motion.influence = 1.0
	fighter.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS

func on_release(_context: Dictionary) -> void:
	has_released = true
	hand_open = 1.0
	catch_elapsed = -1.0

func on_return(_context: Dictionary) -> void:
	returning = true

func on_catch(context: Dictionary) -> void:
	if not bool(context.get("last", true)): return
	returning = false
	catch_elapsed = 0.0

func on_cast_cancelled(_context: Dictionary) -> void:
	# The final-pose publisher is currently committing the cast. Defer body
	# state to the next physics tick instead of changing its sampled skeleton.
	_cast_cancel_pending = true

func reception_ready() -> bool:
	if not action_active: return fighter.state in ["idle", "move", "block"]
	if mode == "throw": return source_time >= 1.15
	if mode == "volley": return source_alias == "XuBladeThrowFollow" and source_time >= 1.15 - 11.0/30.0
	return false

func apply_hand_pose() -> void:
	if hand_open <= 0.0 or not enabled or fighter.hp <= 0.0: return
	for index in _open_fingers:
		var incoming = fighter.skeleton.get_bone_pose_rotation(index)
		fighter.skeleton.set_bone_pose_rotation(index, incoming.slerp(_open_fingers[index], hand_open))

func status() -> Dictionary:
	return {"enabled":enabled,"active":action_active,"ready":stance_ready,"mode":mode,"clip":source_alias,"source_time":source_time,"elapsed":elapsed,"hand_open":hand_open,"returning":returning}
