extends RefCounted

# Isolated family reaction: source K/Ready remains the stance owner. The
# original imported Hit provides only its change from its first local pose.
const SAMPLE_HZ = 120.0
# _bake_arm.py starts the physical main-cut angle at .30s. The .35s
# gameplay active start is not the boundary of the source preparation.
const PREPARATION_END = 0.30
var fighter
var _hit_rows: Array = []
var _idle: Array = []
var _hit_length = 0.0
var _library: AnimationLibrary
var _serial = 0
var playing = false
var diagnostics: Dictionary = {}
var _right_weapon_branch: Dictionary = {}
var _preparation_rows: Array = []
var prefix_entry: Dictionary = {}

func _pose(rig: Skeleton3D) -> Array:
	var values: Array = []
	for index in rig.get_bone_count():
		values.append({"p": rig.get_bone_pose_position(index), "q": rig.get_bone_pose_rotation(index), "s": rig.get_bone_pose_scale(index)})
	return values

func _key(player: AnimationPlayer, alias: String) -> String:
	for candidate in player.get_animation_list():
		if String(candidate).get_slice("/", String(candidate).get_slice_count("/") - 1) == alias: return candidate
	return ""

func setup(owner_fighter, idle_alias: String, preparation_alias: String) -> void:
	fighter = owner_fighter
	var shoulder = fighter.skeleton.find_bone("mixamorig_RightShoulder")
	assert(shoulder >= 0, "Family Hit requires the right weapon branch")
	for index in fighter.skeleton.get_bone_count():
		var ancestor = index
		while ancestor >= 0:
			if ancestor == shoulder:
				_right_weapon_branch[index] = true
				break
			ancestor = fighter.skeleton.get_bone_parent(ancestor)
	# A temporary imported scene has no gameplay scripts or modifiers. Cache
	# the real Godot output before freeing it; no runtime sampling rig remains.
	var source = (load("res://assets/motion/xuchu_ual1_k.glb") as PackedScene).instantiate()
	source.visible = false
	fighter.add_child(source)
	var player: AnimationPlayer = fighter._find_node(source, "AnimationPlayer")
	var rig: Skeleton3D = fighter._find_node(source, "Skeleton3D")
	assert(rig.get_bone_count() == fighter.skeleton.get_bone_count(), "Family Hit must use the same source rig")
	for index in rig.get_bone_count(): assert(rig.get_bone_name(index) == fighter.skeleton.get_bone_name(index), "Family Hit source bone order differs")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var idle_key = _key(player, idle_alias)
	var hit_key = _key(player, "Hit")
	assert(not idle_key.is_empty() and not hit_key.is_empty(), "Family Hit requires imported Hit and SwordIdle")
	player.play(idle_key, 0.0, 1.0)
	player.seek(0.0, true)
	player.advance(0.0)
	_idle = _pose(rig)
	_hit_length = player.get_animation(hit_key).length
	player.stop()
	rig.reset_bone_poses()
	player.play(hit_key, 0.0, 1.0)
	var samples = ceili(_hit_length * SAMPLE_HZ)
	for index in samples + 1:
		player.seek(minf(float(index) / SAMPLE_HZ, _hit_length), true)
		player.advance(0.0)
		_hit_rows.append(_pose(rig))
	player.stop()
	rig.reset_bone_poses()
	var preparation_key = _key(player, preparation_alias)
	assert(not preparation_key.is_empty(), "Family Hit requires the actual GameK preparation")
	player.play(preparation_key, 0.0, 1.0)
	for index in int(round(PREPARATION_END * SAMPLE_HZ)) + 1:
		player.seek(float(index) / SAMPLE_HZ, true)
		player.advance(0.0)
		_preparation_rows.append(_pose(rig))
	source.free()
	_library = AnimationLibrary.new()
	fighter.animation_player.add_animation_library("XuFamilyHit", _library)

func reset() -> void:
	playing = false
	diagnostics.clear()

func finish() -> void:
	playing = false

func _hit_pose(fraction: float) -> Array:
	var position = clampf(fraction, 0.0, 1.0) * _hit_length * SAMPLE_HZ
	var i = mini(int(position), _hit_rows.size() - 1)
	var j = mini(i + 1, _hit_rows.size() - 1)
	var amount = clampf(position - i, 0.0, 1.0)
	var values: Array = []
	for index in _idle.size():
		var a: Dictionary = _hit_rows[i][index]
		var b: Dictionary = _hit_rows[j][index]
		values.append({"p": Vector3(a.p).lerp(b.p, amount), "q": Quaternion(a.q).slerp(b.q, amount), "s": Vector3(a.s).lerp(b.s, amount)})
	return values

func _preparation_pose(time: float) -> Array:
	var position = clampf(time, 0.0, PREPARATION_END) * SAMPLE_HZ
	var i = mini(int(position), _preparation_rows.size() - 1)
	var j = mini(i + 1, _preparation_rows.size() - 1)
	var amount = clampf(position - i, 0.0, 1.0)
	var values: Array = []
	for index in _idle.size():
		var a: Dictionary = _preparation_rows[i][index]
		var b: Dictionary = _preparation_rows[j][index]
		values.append({"p": Vector3(a.p).lerp(b.p, amount), "q": Quaternion(a.q).slerp(b.q, amount), "s": Vector3(a.s).lerp(b.s, amount)})
	return values

func _angle_degrees(a: Quaternion, b: Quaternion) -> float:
	var delta = (a.normalized().inverse() * b.normalized()).normalized()
	return rad_to_deg(2.0 * atan2(Vector3(delta.x,delta.y,delta.z).length(),absf(delta.w)))

func prefix_matches_incoming(time: float) -> bool:
	var current = _pose(fighter.skeleton)
	var source = _preparation_pose(time)
	var max_position = 0.0
	var max_rotation = 0.0
	for index in _right_weapon_branch:
		max_position = maxf(max_position, Vector3(current[index].p).distance_to(source[index].p) * float(data_scale()))
		max_rotation = maxf(max_rotation, _angle_degrees(current[index].q, source[index].q))
	# A still-blended or externally modified entry must retain legacy handling.
	prefix_entry = {"time":time,"position_error_m":max_position,"rotation_error_deg":max_rotation,"matched":max_position<0.00001 and max_rotation<0.001}
	return bool(prefix_entry.matched)

func data_scale() -> float:
	return fighter.model.scale.x

func play(duration: float, source_time: float, from_active: bool) -> void:
	var rig: Skeleton3D = fighter.skeleton
	rig.force_update_all_bone_transforms()
	var incoming = _pose(rig)
	var incoming_clip: String = fighter.current_clip
	var animation = Animation.new()
	animation.length = duration
	animation.loop_mode = Animation.LOOP_NONE
	var root = fighter.animation_player.get_node(fighter.animation_player.root_node)
	var skeleton_path: NodePath = root.get_path_to(rig)
	var tracks: Array = []
	for index in rig.get_bone_count():
		var path = NodePath(String(skeleton_path) + ":" + rig.get_bone_name(index))
		var row = []
		for type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			var track = animation.add_track(type)
			animation.track_set_path(track, path)
			animation.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
			row.append(track)
		tracks.append(row)
	var count = maxi(1, ceili(duration * SAMPLE_HZ))
	var max_end_delta = 0.0
	var hips_end_delta = Vector3.ZERO
	for sample in count + 1:
		var fraction = float(sample) / count
		var amount = smoothstep(0.0, 1.0, fraction)
		var hit = _hit_pose(fraction)
		var preparation = _preparation_pose(source_time * (1.0 - amount))
		var time = fraction * duration
		for index in rig.get_bone_count():
			var from: Dictionary = incoming[index]
			var to: Dictionary = _idle[index]
			if _right_weapon_branch.has(index):
				# Reuse the complete authored FK prefix backwards. Do not reverse
				# the released cut or invent a local-quaternion route to Ready.
				to = preparation[index]
				from = incoming[index] if sample == 0 else to
			var first: Dictionary = _hit_rows[0][index]
			var reaction: Dictionary = hit[index]
			var position = Vector3(from.p).lerp(to.p, amount)
			if rig.get_bone_name(index).ends_with("Hips"):
				position += Vector3(reaction.p) - Vector3(first.p)
				if sample == count: hips_end_delta = Vector3(reaction.p) - Vector3(first.p)
			var delta_q = Quaternion(first.q).inverse() * Quaternion(reaction.q)
			# The old upright Hit weapon-arm delta is incompatible with a high K.
			# Keep its incoming-to-SwordIdle arm; inherit the original torso recoil.
			if _right_weapon_branch.has(index): delta_q = Quaternion.IDENTITY
			var rotation = (Quaternion(from.q).slerp(to.q, amount) * delta_q).normalized()
			if sample == count: max_end_delta = maxf(max_end_delta, Quaternion.IDENTITY.angle_to(delta_q))
			animation.position_track_insert_key(tracks[index][0], time, position)
			animation.rotation_track_insert_key(tracks[index][1], time, rotation)
			animation.scale_track_insert_key(tracks[index][2], time, Vector3(from.s).lerp(to.s, amount))
	_serial += 1
	var key = "Reaction" + str(_serial % 2)
	if _library.has_animation(key): _library.remove_animation(key)
	_library.add_animation(key, animation)
	fighter.combat_motion.influence = 0.0
	fighter.tempo_profile = {}
	fighter.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	fighter.animation_player.speed_scale = 1.0
	# The generated first pose equals incoming. A second body crossfade would
	# mix this compatible reaction with the old K and reintroduce foot errors.
	fighter.animation_player.play("XuFamilyHit/" + key, 0.0, 1.0)
	fighter.animation_player.advance(0.0)
	fighter.current_clip = "Hit"
	playing = true
	var max_entry_position = 0.0
	var max_entry_rotation = 0.0
	for index in rig.get_bone_count():
		max_entry_position = maxf(max_entry_position, rig.get_bone_pose_position(index).distance_to(incoming[index].p))
		max_entry_rotation = maxf(max_entry_rotation, rig.get_bone_pose_rotation(index).angle_to(incoming[index].q))
	diagnostics = {"serial":_serial,"duration":duration,"incoming_clip":incoming_clip,"incoming_source_time":source_time,"interrupted_active_k":from_active,
		"entry_position_error_rig":max_entry_position,"entry_rotation_error_deg":rad_to_deg(max_entry_rotation),
		"original_hit_end_delta_max_deg":rad_to_deg(max_end_delta),"original_hit_end_hips_delta_rig":hips_end_delta,
		"physics_frame":Engine.get_physics_frames(),"source_hit_length":_hit_length,"samples":count+1,"prefix_entry":prefix_entry.duplicate(true),"preparation_stop_time":PREPARATION_END}

func status() -> Dictionary:
	var value = diagnostics.duplicate(true)
	value["playing"] = playing
	return value
