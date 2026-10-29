extends CharacterBody3D
class_name DuelFighter
const RoleSkills = preload("res://scripts/skill_profiles.gd")
const Roster = preload("res://scripts/roster.gd")
const MountedCombat = preload("res://scripts/mounted_combat.gd")
const HorseVisual = preload("res://scripts/horse_visual.gd")
const RiderPose = preload("res://scripts/rider_pose.gd")
const ThrustContact = preload("res://scripts/thrust_contact.gd")
const CombatMotion = preload("res://scripts/combat_motion.gd")
const AttackTempo = preload("res://scripts/attack_tempo.gd")
const JumpMotion = preload("res://scripts/jump_motion.gd")
const JumpPose = preload("res://scripts/jump_pose.gd")

signal strike_requested(fighter, attack)
signal impact_received(fighter, outcome, position)
signal action_started(fighter, action)
signal skill_triggered(fighter, skill, stage)
signal jump_started(fighter)
signal jump_landed(fighter, position)

const ATTACKS = [
	{"clip": "Attack1", "duration": 0.80, "active": Vector2(0.13, 0.30), "damage": 15.0, "cost": 13.0, "reach": 2.12, "lunge": 1.9, "heavy": false},
	{"clip": "Attack2", "duration": 0.85, "active": Vector2(0.13, 0.32), "damage": 17.0, "cost": 15.0, "reach": 2.20, "lunge": 1.7, "heavy": false},
	{"clip": "Attack3", "duration": 1.05, "active": Vector2(0.27, 0.55), "damage": 23.0, "cost": 19.0, "reach": 2.30, "lunge": 2.0, "heavy": false},
]
const HEAVY = {"clip": "Heavy", "duration": 1.14, "active": Vector2(0.29, 0.53), "damage": 31.0, "cost": 29.0, "reach": 2.35, "lunge": 2.1, "heavy": true}
const LOOP_CLIPS = ["Idle", "Walk", "WalkBack", "StrafeLeft", "StrafeRight", "Run", "TurnLeft", "TurnRight"]
const GAIT_CLIPS = ["Walk", "WalkBack", "StrafeLeft", "StrafeRight", "Run", "TurnLeft", "TurnRight"]

var character_id = "zhaoyun"
var weapon_id = "sword"
var is_player = false
var opponent: DuelFighter
var hp = 120.0
var stamina = 100.0
var state = "idle"
var action_time = 0.0
var action_duration = 0.0
var attack: Dictionary = {}
var combo = 0
var combo_buffered = false
var hit_landed = false
var swing_announced = false
var enabled = false
var regen_delay = 0.0
var dodge_direction = Vector3.ZERO
var input_move = Vector3.ZERO
var wants_block = false
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var model: Node3D
var grip: Node3D
var weapon_mesh: Node3D
var previous_tip = Vector3.ZERO
var animation_names: Dictionary = {}
var current_clip = ""
var locomotion_rate = 1.0
var locomotion_phase = 0.0
var combat_motion: SkeletonModifier3D
var tempo_profile: Dictionary = {}
var _attack_tempo_library: AnimationLibrary
var attack_warmup_ms = 0.0
var blocked_hits = 0
var parries = 0
var dodged_hits = 0
var damage_dealt = 0.0
var footstep_clock = 0.0
var turn_speed = 0.0
var turning_in_place = false
var turn_direction = 1.0
var energy = 35.0
var cooldowns: Dictionary = {"rush": 0.0, "counter": 0.0}
var skill_id = ""
var skill_stage = ""
var skill_hit_index = -1
var skill_strike_announced = false
var skill_animation_index = -1
var skill_animation_started = false
var skill_counter_primed = false
var grip_config: Dictionary = {}
var clip_thrust_ready_seconds: Dictionary = {}
var right_hand_index = -1
var left_hand_index = -1
var grip_roll_ready = false
var mounted = false
var horse_color = "white"
var mount_speed = 0.0
var _mount_action_velocity = Vector3.ZERO
var mount_charge_time = 0.0
var mount_charge_cooldown = 0.0
var mount_turn_rate = 0.0
var horse: Node3D
var rider_pose: SkeletonModifier3D
var riding_height = 0.0
var rider_hip_height = 0.0
var thrust_contact: SkeletonModifier3D
var contact_latched = false
var contact_active = false
var contact_point = Vector3.ZERO
var contact_retraction = 0.0
var _thrust_segment_data: Dictionary = {}
var _contact_backstep_requested = false
# Zero retains the duel's foot/mounted arena; other modes may set a world limit.
var movement_radius = 0.0
var jump_motion = JumpMotion.new()
var jump_pose: SkeletonModifier3D
var _jump_floor_snap = 0.2

func _ready() -> void:
	collision_layer = 2
	collision_mask = 3
	var shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.62 if mounted else 0.32
	capsule.height = 3.05 if mounted else 1.80
	shape.shape = capsule
	shape.position.y = 1.53 if mounted else 0.91
	add_child(shape)
	floor_snap_length = 0.2
	_load_visuals()
	if is_player:
		prewarm_attack_animations()
	combat_motion = CombatMotion.new()
	combat_motion.setup(self, skeleton)
	if not mounted:
		jump_pose = JumpPose.new()
		jump_pose.setup(skeleton, Callable(self, "jump_status"))
	if mounted:
		horse = HorseVisual.new()
		horse.setup(character_id, horse_color)
		add_child(horse)
		rider_pose = RiderPose.new()
		rider_pose.setup(skeleton, model)
		rider_pose.set_activity_provider(Callable(combat_motion, "activity_weight"))
		rider_pose.set_jump_provider(Callable(self, "jump_status"))
		rider_pose.set_mount_width(horse.belly_width)
		rider_hip_height = rider_pose.rest_hip_height()
		riding_height = horse.saddle_height() - rider_hip_height
		model.position = Vector3(0.0, riding_height, horse.saddle_z())
	if is_two_handed():
		thrust_contact = ThrustContact.new()
		thrust_contact.setup(self, skeleton)
	if mounted:
		# A browser can run several physics ticks before its next render frame.
		# Align after either rig finishes, rather than leaving the rider at an
		# earlier render frame's saddle height during those extra horse strides.
		skeleton.skeleton_updated.connect(_post_animation_visual)
		var horse_skeleton = _find_node(horse, "Skeleton3D") as Skeleton3D
		if is_instance_valid(horse_skeleton):
			horse_skeleton.skeleton_updated.connect(_post_animation_visual)
		horse.bind_rider()
	reset_fighter()

func _load_visuals() -> void:
	var scene = load("res://assets/characters/%s.glb" % character_id) as PackedScene
	model = scene.instantiate()
	model.name = "CharacterVisual"
	model.scale = Vector3.ONE * float(Roster.character(character_id).get("scale", 1.98))
	add_child(model)
	animation_player = _find_node(model, "AnimationPlayer") as AnimationPlayer
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	skeleton = _find_node(model, "Skeleton3D") as Skeleton3D
	assert(animation_player != null and skeleton != null, "Character must have a skeleton and baked CC0 clips")
	for key in animation_player.get_animation_list():
		var short_name = String(key).get_slice("/", String(key).get_slice_count("/") - 1)
		animation_names[short_name] = key
		if short_name in LOOP_CLIPS:
			animation_player.get_animation(key).loop_mode = Animation.LOOP_LINEAR
	# Each original Mixamo rig has different wrist roll. The metadata is derived
	# from its own T-pose correspondence, so both weapons share the same grip.
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/animation_manifest.json"))
	var config: Dictionary = manifest[character_id]["grip"]
	clip_thrust_ready_seconds.clear()
	for alias in manifest[character_id].get("clips", {}):
		clip_thrust_ready_seconds[alias] = float(manifest[character_id].clips[alias].get("grip_startup_blend_source_seconds", 0.25))
	grip_config = config
	weapon_id = resolve_equipped_weapon(weapon_id)
	if config.get("mode", "one_hand") == "two_hand":
		_load_two_handed_weapon()
		_tune_materials(model)
		return
	var attachment = BoneAttachment3D.new()
	for index in skeleton.get_bone_count():
		if skeleton.get_bone_name(index).ends_with("RightHand"):
			attachment.bone_name = skeleton.get_bone_name(index)
			break
	assert(attachment.bone_name != "", "Right-hand weapon socket is required")
	skeleton.add_child(attachment)
	grip = Node3D.new()
	grip.name = "CalibratedGrip"
	attachment.add_child(grip)
	var q: Array = config.rotation_xyzw
	grip.quaternion = Quaternion(q[0], q[1], q[2], q[3])
	var p: Array = config.position
	grip.position = Vector3(p[0], p[1], p[2])
	weapon_mesh = (load(Roster.WEAPONS[weapon_id].path) as PackedScene).instantiate()
	weapon_mesh.name = "OneHandWeapon"
	weapon_mesh.scale = Vector3.ONE * float(config.mesh_scale)
	weapon_mesh.position.y = float(config.mesh_grip_y)
	grip.add_child(weapon_mesh)
	# Many small armor surfaces use the originals' baked normal maps. Keep them
	# on the authored meshes; remove imported shadow lights/cameras if any.
	_tune_materials(model)

func is_two_handed() -> bool:
	return grip_config.get("mode", "one_hand") == "two_hand"

func resolve_equipped_weapon(selected: String) -> String:
	return Roster.resolve_weapon(character_id, selected)

func _load_two_handed_weapon() -> void:
	for index in skeleton.get_bone_count():
		if skeleton.get_bone_name(index).ends_with("RightHand"):
			right_hand_index = index
		elif skeleton.get_bone_name(index).ends_with("LeftHand"):
			left_hand_index = index
	assert(right_hand_index >= 0 and left_hand_index >= 0, "Both polearm hand sockets are required")
	grip = Node3D.new()
	grip.name = "TwoHandGrip"
	add_child(grip)
	weapon_mesh = (load(Roster.WEAPONS[weapon_id].path) as PackedScene).instantiate()
	weapon_mesh.name = "TwoHandPolearm"
	var length_m = float(grip_config.weapon_length)
	weapon_mesh.scale = Vector3.ONE * length_m
	weapon_mesh.position.y = -length_m * float(grip_config.grip_fraction)
	grip.add_child(weapon_mesh)
	if skeleton.has_signal("skeleton_updated"):
		skeleton.connect("skeleton_updated", _update_two_hand_grip)
	_update_two_hand_grip()
	_tune_materials(weapon_mesh)

func palm_position(left: bool) -> Vector3:
	if is_instance_valid(thrust_contact) and thrust_contact.pose_cached:
		return skeleton.to_global(thrust_contact.left_palm_local if left else thrust_contact.right_palm_local)
	var index = left_hand_index if left else right_hand_index
	var p: Array = grip_config.left_palm if left else grip_config.right_palm
	var local_palm = skeleton.get_bone_global_pose(index) * Vector3(p[0], p[1], p[2])
	return skeleton.to_global(local_palm)

func _update_two_hand_grip(delta = 0.0, instant = false) -> void:
	if not is_inside_tree() or not is_instance_valid(skeleton) or not skeleton.is_inside_tree() or not is_instance_valid(weapon_mesh) or left_hand_index < 0:
		return
	var right = palm_position(false)
	var left = palm_position(true)
	var axis = (right - left).normalized() * float(grip_config.get("axis_sign", 1.0))
	if right.distance_to(left) < 0.025:
		return
	var wrist_basis: Basis = thrust_contact.right_wrist_basis if is_instance_valid(thrust_contact) and thrust_contact.pose_cached else skeleton.get_bone_global_pose(right_hand_index).basis
	var wrist = skeleton.global_basis * wrist_basis
	var side = wrist.x - axis * wrist.x.dot(axis)
	if side.length() < 0.05:
		side = Vector3.UP.cross(axis) if absf(axis.y) < 0.9 else Vector3.RIGHT.cross(axis)
	side = side.normalized()
	if Roster.WEAPONS[weapon_id].get("edge_forward", false):
		# This GLB's convex cutting edge is local -X. Aim that edge along the
		# committed facing direction, rotating only around the two-hand shaft.
		var previous = grip.global_basis.x - axis * grip.global_basis.x.dot(axis)
		if previous.length_squared() > 0.001:
			previous = previous.normalized()
		else:
			previous = side
		var edge = forward() - axis * forward().dot(axis)
		var desired = -edge.normalized() if edge.length_squared() > 0.02 else previous
		if instant or not grip_roll_ready:
			side = desired
		else:
			var angle = previous.signed_angle_to(desired, axis)
			side = previous.rotated(axis, clampf(angle, -14.0 * delta, 14.0 * delta))
		grip_roll_ready = true
	grip.global_transform = Transform3D(Basis(side, axis, side.cross(axis)), right)

func _process(delta: float) -> void:
	if mounted and is_instance_valid(horse):
		horse.update_motion(delta, mount_speed if enabled else 0.0, mount_turn_rate, hp <= 0.0)
		rider_pose.update(delta, mount_speed / 8.2 if enabled else 0.0,
			mount_turn_rate if enabled else 0.0, horse.saddle_transform().basis,
			combat_motion.activity_weight())
		model.position = Vector3(0.0, horse.saddle_height() - rider_hip_height, horse.saddle_z())
	if is_two_handed():
		_update_two_hand_grip(delta)

func _post_animation_visual() -> void:
	if not is_inside_tree() or not mounted or not is_instance_valid(horse) or not is_instance_valid(model) or not horse.is_inside_tree():
		return
	var seat: Transform3D = horse.saddle_transform()
	model.position = Vector3(0.0, seat.origin.y - rider_hip_height, seat.origin.z)
	horse.sync_rider_contacts()
	# The polearm is a world-space attachment, unlike the skinned body. Moving
	# the model to the new seat must move the weapon with its final cached palms.
	if is_two_handed():
		_update_two_hand_grip()

func is_thrust_weapon() -> bool:
	return bool(Roster.WEAPONS[weapon_id].get("thrust_only", false))

func is_physical_thrust(data: Dictionary = {}) -> bool:
	if not is_two_handed() or state not in ["attack", "skill", "ultimate"]:
		return false
	var candidate = data
	if candidate.is_empty():
		candidate = _thrust_segment_data if state in ["skill", "ultimate"] and not _thrust_segment_data.is_empty() else attack
	return candidate.get("shape", "") == "line" and not candidate.get("radial", false)

func thrust_body_low() -> Vector3:
	return global_position + Vector3.UP * (1.7 if mounted else 0.42)

func thrust_body_high() -> Vector3:
	return global_position + Vector3.UP * (3.1 if mounted else 1.55)

func thrust_body_radius() -> float:
	return 0.36

func _reset_thrust_contact() -> void:
	contact_latched = false
	contact_active = false
	contact_point = Vector3.ZERO
	contact_retraction = 0.0
	_thrust_segment_data.clear()
	_contact_backstep_requested = false

func register_thrust_contact(at: Vector3) -> void:
	# A parry may already have changed us to stagger during receive_strike.
	if not is_physical_thrust():
		return
	contact_latched = true
	contact_active = true
	contact_point = at
	if mounted:
		mount_charge_time = 0.0
	# Withdraw the authored hands towards their ready stance after resistance.
	# Action/recovery timers and combo buffering continue on the original clock.
	play_clip("Idle", 0.08)

func basic_reach() -> float:
	return float(Roster.WEAPONS[weapon_id].reach) + (0.30 if mounted else 0.0)

func preferred_distance() -> float:
	return float(Roster.character(character_id).distance) + (0.4 if mounted else 0.0)

func _light_attacks() -> Array:
	if character_id == "xuchu":
		return [
			{"clip": "Attack1", "duration": 0.94, "active": Vector2(0.15, 0.28), "damage": 18.0, "cost": 16.0, "reach": basic_reach(), "lunge": 1.6, "heavy": false, "min_dot": 0.08},
			{"clip": "Attack2", "duration": 1.04, "active": Vector2(0.37, 0.50), "damage": 21.0, "cost": 19.0, "reach": basic_reach() + 0.08, "lunge": 1.4, "heavy": false, "min_dot": 0.0},
			{"clip": "Attack3", "duration": 1.24, "active": Vector2(0.60, 0.80), "damage": 28.0, "cost": 23.0, "reach": basic_reach() + 0.15, "lunge": 1.2, "heavy": false, "min_dot": -0.12},
		]
	if not is_two_handed():
		return ATTACKS
	if is_thrust_weapon():
		return [
			{"clip": "Attack1", "duration": 0.90, "active": Vector2(0.19, 0.39), "damage": 18.0, "cost": 17.0, "reach": basic_reach(), "lunge": 1.7, "heavy": false, "shape": "line", "half_width": 0.54},
			{"clip": "Attack2", "duration": 1.00, "active": Vector2(0.21, 0.43), "damage": 21.0, "cost": 20.0, "reach": basic_reach(), "lunge": 1.4, "heavy": false, "shape": "line", "half_width": 0.56},
			{"clip": "Attack3", "duration": 1.14, "active": Vector2(0.24, 0.49), "damage": 28.0, "cost": 24.0, "reach": basic_reach() + 0.15, "lunge": 1.1, "heavy": false, "shape": "line", "half_width": 0.60},
		]
	return [
		{"clip": "Attack1", "duration": 0.98, "active": Vector2(0.32, 0.54), "damage": 18.0, "cost": 17.0, "reach": basic_reach(), "lunge": 1.7, "heavy": false, "shape": "sector", "min_dot": -0.12},
		{"clip": "Attack2", "duration": 1.10, "active": Vector2(0.35, 0.61), "damage": 21.0, "cost": 20.0, "reach": basic_reach(), "lunge": 1.4, "heavy": false, "min_dot": -0.16},
		{"clip": "Attack3", "duration": 1.34, "active": Vector2(0.42, 0.80), "damage": 28.0, "cost": 24.0, "reach": basic_reach() + 0.15, "lunge": 1.1, "heavy": false, "min_dot": -0.30},
	]

func _tune_materials(node: Node, category = "") -> void:
	var duel_presentation = has_method("duel_strike_forward")
	if category == "": category = "weapon" if node == weapon_mesh else "character"
	if node is MeshInstance3D:
		var surfaces = node.mesh.get_surface_count() if node.mesh != null else 0
		if not duel_presentation: surfaces = node.get_surface_override_material_count()
		for i in surfaces:
			var mat = node.get_active_material(i)
			if mat is StandardMaterial3D:
				if not duel_presentation:
					mat.roughness = maxf(mat.roughness, 0.52)
					continue
				# Private material copies preserve the imported RPG resources. The
				# character's metal/cloth separation already lives in its PBR map;
				# retain those authored factors rather than treating skin as steel.
				mat = mat.duplicate() as StandardMaterial3D
				if category == "weapon":
					if mat.roughness_texture != null:
						mat.roughness = clampf(mat.roughness * 0.86, 0.40, 1.0)
					elif mat.metallic > 0.45:
						mat.roughness = clampf(mat.roughness, 0.28, 0.46)
					else:
						mat.roughness = maxf(mat.roughness, 0.68)
				node.set_surface_override_material(i, mat)
	for child in node.get_children():
		_tune_materials(child, category)

func _find_node(node: Node, kind: String) -> Node:
	if node.is_class(kind):
		return node
	for child in node.get_children():
		var result = _find_node(child, kind)
		if result != null:
			return result
	return null

func reset_fighter() -> void:
	_reset_jump()
	_cancel_skill()
	hp = 120.0
	stamina = 100.0
	state = "idle"
	action_time = 0.0
	combo = 0
	combo_buffered = false
	hit_landed = false
	swing_announced = false
	attack = {}
	regen_delay = 0.0
	wants_block = false
	input_move = Vector3.ZERO
	velocity = Vector3.ZERO
	turn_speed = 0.0
	turning_in_place = false
	grip_roll_ready = false
	mount_speed = 0.0
	_mount_action_velocity = Vector3.ZERO
	mount_charge_time = 0.0
	mount_charge_cooldown = 0.0
	mount_turn_rate = 0.0
	locomotion_rate = 1.0
	locomotion_phase = 0.0
	if is_instance_valid(combat_motion):
		combat_motion.reset_motion()
	if is_instance_valid(thrust_contact):
		thrust_contact.reset_motion()
	if is_instance_valid(rider_pose):
		rider_pose.reset_motion()
	if mounted and is_instance_valid(horse):
		horse.reset_motion()
	energy = 35.0
	cooldowns = {"rush": 0.0, "counter": 0.0}
	current_clip = ""
	play_clip("Idle", 0.0)

func resolve_animation_clip(clip: String) -> String:
	return clip

func _can_jump() -> bool:
	return enabled and hp > 0.0 and not jump_motion.active and is_on_floor() and state not in ["hit", "stagger", "dead", "dodge"]

func request_jump() -> bool:
	if not _can_jump(): return false
	_jump_floor_snap = floor_snap_length
	jump_motion.begin(mounted, global_position.y)
	jump_started.emit(self)
	action_started.emit(self, "jump")
	return true

func is_jumping() -> bool:
	return jump_motion.active

func jump_status() -> Dictionary:
	var result = jump_motion.status(global_position.y if is_inside_tree() else 0.0, _can_jump())
	result.mounted = mounted
	return result

func _reset_jump() -> void:
	if jump_motion.active:
		floor_snap_length = _jump_floor_snap
	jump_motion.reset()

func _advance_jump(delta: float) -> void:
	var launched = jump_motion.advance(delta, hp <= 0.0)
	if launched:
		floor_snap_length = 0.0
	if jump_motion.airborne:
		# Combat knockback remains planar. Receiving a hit or starting a skill
		# must not erase a real jump's vertical momentum.
		velocity.y = jump_motion.vertical_speed

func _finish_jump() -> void:
	if not jump_motion.airborne:
		return
	jump_motion.vertical_speed = velocity.y
	if is_on_ceiling() and velocity.y > 0.0:
		jump_motion.vertical_speed = 0.0
	if jump_motion.flight_time > 0.035 and is_on_floor() and velocity.y <= 0.0:
		jump_motion.land(global_position.y)
		floor_snap_length = _jump_floor_snap
		jump_landed.emit(self, global_position)
		action_started.emit(self, "land")

func prewarm_attack_animations() -> void:
	# Do expensive immutable clip construction while the actor is loading,
	# before the first input. Never play a clip or touch combat/stamina state.
	var start = Time.get_ticks_usec()
	var profiles = _light_attacks().duplicate(true)
	profiles.append(_heavy_attack_profile())
	for original in profiles:
		var data = _weapon_adjusted_attack(original)
		var clip = resolve_animation_clip(String(data.clip))
		if animation_names.has(clip):
			AttackTempo.variant(animation_player.get_animation(animation_names[clip]),
				float(data.duration), data.active, bool(data.get("heavy", false)))
	attack_warmup_ms = float(Time.get_ticks_usec() - start) / 1000.0

func play_clip(clip: String, blend = 0.12, duration = 0.0) -> void:
	clip = resolve_animation_clip(clip)
	if mounted and clip in ["Walk", "WalkBack", "StrafeLeft", "StrafeRight", "Run", "TurnLeft", "TurnRight", "Dodge"]:
		clip = "Idle"
	if mounted and clip == "Death":
		clip = "Hit"
	if not animation_names.has(clip):
		push_error("Missing required animation: " + clip)
		return
	var key: String = animation_names[clip]
	tempo_profile = {}
	if state == "attack" and duration > 0.0 and attack.has("active"):
		# Rephrase only the pose before/after contact. Gameplay, skill clips,
		# action duration and the authored active interval keep their old timing.
		var weighted = AttackTempo.variant(animation_player.get_animation(key), duration, attack.active, bool(attack.get("heavy", false)))
		if not Dictionary(weighted.profile).is_empty():
			if _attack_tempo_library == null:
				_attack_tempo_library = AnimationLibrary.new()
				animation_player.add_animation_library("AttackTempo", _attack_tempo_library)
			if not _attack_tempo_library.has_animation(weighted.key):
				_attack_tempo_library.add_animation(weighted.key, weighted.animation)
			key = "AttackTempo/" + String(weighted.key)
			tempo_profile = weighted.profile
	# Directional clips use the same planted-foot phase. Restarting every new
	# direction at frame zero caused a visible hitch when circling an opponent.
	var preserve_phase = current_clip in GAIT_CLIPS and clip in GAIT_CLIPS and animation_player.current_animation_length > 0.0
	var phase = fposmod(animation_player.current_animation_position / animation_player.current_animation_length, 1.0) if preserve_phase else 0.0
	animation_player.speed_scale = 1.0
	var speed = 1.0
	if duration > 0.0:
		speed = animation_player.get_animation(key).length / duration
	animation_player.play(key, blend, speed)
	if preserve_phase:
		animation_player.seek(phase * animation_player.get_animation(key).length, true)
		locomotion_phase = phase
	current_clip = clip

func request_light() -> bool:
	if not enabled or hp <= 0.0:
		return false
	if state == "attack" and not attack.get("heavy", false) and combo < 2:
		combo_buffered = true
		return true
	if state not in ["idle", "move", "block"]:
		return false
	return _begin_attack(0)

func _heavy_attack_profile() -> Dictionary:
	var profile = HEAVY.duplicate()
	if is_two_handed():
		profile.merge({"duration": 1.48, "active": Vector2(0.48, 0.83), "damage": 38.0, "cost": 34.0, "reach": basic_reach() + 0.12, "lunge": 1.8}, true)
	elif character_id == "xuchu":
		profile.merge({"duration": 1.40, "active": Vector2(0.72, 0.88), "damage": 36.0, "cost": 32.0, "reach": basic_reach() + 0.15, "lunge": 2.0}, true)
	if is_thrust_weapon():
		profile.merge({"duration": 1.40, "active": Vector2(0.29, 0.60), "shape": "line", "half_width": 0.62}, true)
	if mounted and weapon_id == "guandao":
		# A short horse step carries the descending blade into contact. Mounted
		# locomotion owns velocity, so the foot attack's lunge cannot supply it.
		profile["mount_advance"] = {"start": 0.22, "end": 0.68, "speed": 0.85}
	return profile

func request_heavy() -> bool:
	var profile = _heavy_attack_profile()
	if not enabled or state not in ["idle", "move", "block"] or hp <= 0.0 or stamina < float(profile.cost):
		return false
	combo = 0
	attack = profile
	_apply_weapon_stats()
	_enter_attack()
	return true

func ultimate_name() -> String:
	return skill_name("ultimate")

func skill_profile(id: String) -> Dictionary:
	if character_id not in ["zhaoyun", "machao", "guanyu", "zhangfei", "lubu", "xuchu"]:
		return MountedCombat.profile(id, is_thrust_weapon(), basic_reach())
	if mounted:
		return MountedCombat.profile(id, is_thrust_weapon(), basic_reach(), character_id)
	return RoleSkills.for_character(character_id).get(id, {})

func skill_name(id: String) -> String:
	return String(skill_profile(id).get("name", ""))

func skill_description(id: String) -> String:
	return String(skill_profile(id).get("description", ""))

func skill_cost(id: String) -> float:
	return float(skill_profile(id).get("cost", 0.0))

func skill_cooldown(id: String) -> float:
	return float(skill_profile(id).get("cooldown", 0.0))

func ultimate_windup() -> float:
	return float(skill_profile("ultimate").windup)

func ultimate_radius() -> float:
	return float(skill_profile("ultimate").radius)

func gain_energy(amount: float) -> void:
	var before = energy
	energy = clampf(energy + amount, 0.0, 100.0)
	if before < 100.0 and energy >= 100.0:
		action_started.emit(self, "ultimate_ready")

func skill_ready(id: String) -> bool:
	if not enabled or hp <= 0.0 or state not in ["idle", "move", "block"]:
		return false
	if id == "ultimate":
		return energy >= 99.999
	return cooldowns.has(id) and cooldowns[id] <= 0.0 and stamina >= skill_cost(id)

func request_skill(id: String) -> bool:
	if id not in ["rush", "counter"] or not skill_ready(id):
		return false
	var profile = skill_profile(id)
	cooldowns[id] = skill_cooldown(id)
	stamina -= skill_cost(id)
	regen_delay = 0.9
	skill_id = id
	skill_stage = "windup"
	skill_hit_index = -1
	skill_strike_announced = false
	skill_animation_started = false
	skill_animation_index = -1
	skill_counter_primed = false
	action_time = 0.0
	combo_buffered = false
	hit_landed = false
	turning_in_place = false
	state = "skill"
	_mount_action_velocity = Vector3(velocity.x, 0.0, velocity.z)
	attack = profile.duplicate(true)
	attack["skill"] = id
	_reset_thrust_contact()
	action_duration = profile.duration
	if profile.kind == "evade":
		dodge_direction = input_move.normalized() if input_move.length() > 0.1 else (global_basis.x * float(profile.get("dodge_side", 0.0)) if profile.has("dodge_side") else -forward())
		dodge_direction.y = 0.0
	var initial_duration = float(profile.stages[0].duration) if profile.has("stages") else (0.40 if profile.kind == "evade" else action_duration)
	play_clip(profile.clip, 0.08, initial_duration)
	if profile.has("stages"):
		skill_animation_index = 0
	skill_triggered.emit(self, id, "start")
	return true

func request_ultimate() -> bool:
	if not skill_ready("ultimate"):
		return false
	energy = 0.0
	regen_delay = 1.0
	skill_id = "ultimate"
	skill_stage = "windup"
	skill_hit_index = -1
	skill_strike_announced = false
	skill_animation_index = -1
	state = "ultimate"
	_mount_action_velocity = Vector3(velocity.x, 0.0, velocity.z)
	action_time = 0.0
	action_duration = float(skill_profile("ultimate").duration)
	combo_buffered = false
	hit_landed = false
	attack = {}
	_reset_thrust_contact()
	turning_in_place = false
	velocity.x = 0.0
	velocity.z = 0.0
	play_clip(skill_profile("ultimate").charge_clip, 0.11, ultimate_windup())
	skill_triggered.emit(self, "ultimate", "start")
	return true

func _cancel_skill(completion = "cancel") -> void:
	_reset_thrust_contact()
	if skill_id != "":
		skill_triggered.emit(self, skill_id, completion)
	skill_id = ""
	skill_stage = ""
	skill_hit_index = -1
	skill_strike_announced = false
	skill_animation_index = -1
	skill_animation_started = false
	skill_counter_primed = false

func _begin_attack(index: int) -> bool:
	var options = _light_attacks()
	if stamina < options[index].cost:
		return false
	combo = index
	attack = options[index].duplicate()
	_apply_weapon_stats()
	_enter_attack()
	return true

func _weapon_adjusted_attack(profile: Dictionary) -> Dictionary:
	var data = profile.duplicate(true)
	if is_two_handed():
		return data
	# The saber trades a little reach for damage; the straight sword recovers
	# faster. The two use the same genuine single-hand animation set.
	if weapon_id == "saber":
		data.damage *= 1.08
		data.duration *= 1.04
		data.active *= 1.04
		data.reach -= 0.10
	elif weapon_id == "xuchu_saber":
		data.damage *= 1.12
		data.duration *= 1.10
		data.active *= 1.10
	else:
		data.duration *= 0.96
		data.active *= 0.96
	return data

func _apply_weapon_stats() -> void:
	attack = _weapon_adjusted_attack(attack)

func _enter_attack() -> void:
	_reset_thrust_contact()
	stamina -= float(attack.cost)
	regen_delay = 0.75
	state = "attack"
	action_time = 0.0
	action_duration = attack.duration
	combo_buffered = false
	hit_landed = false
	swing_announced = false
	play_clip(attack.clip, 0.075, action_duration)
	previous_tip = blade_tip()
	action_started.emit(self, "heavy" if attack.heavy else "light")

func request_dodge(direction = Vector3.ZERO) -> bool:
	if mounted:
		if not enabled or hp <= 0.0 or stamina < 24.0 or mount_charge_cooldown > 0.0 or state not in ["idle", "move", "block"]:
			return false
		stamina -= 24.0
		regen_delay = 0.8
		mount_charge_time = 1.15
		mount_charge_cooldown = 3.6
		if state == "block":
			_idle()
		action_started.emit(self, "charge")
		return true
	if not enabled or hp <= 0.0 or stamina < 24.0 or state not in ["idle", "move", "block"]:
		return false
	stamina -= 24.0
	regen_delay = 0.80
	state = "dodge"
	action_time = 0.0
	action_duration = 0.54
	dodge_direction = direction.normalized() if direction.length() > 0.1 else -forward()
	dodge_direction.y = 0.0
	play_clip("Dodge", 0.06, action_duration)
	action_started.emit(self, "dodge")
	return true

func forward() -> Vector3:
	return global_basis.z.normalized()

func blade_tip() -> Vector3:
	if is_two_handed() and is_instance_valid(weapon_mesh):
		return weapon_mesh.to_global(Vector3(0, 0.99, 0))
	return weapon_mesh.to_global(Vector3(0, float(Roster.WEAPONS[weapon_id].get("blade_tip", 98.0)), 0)) if is_instance_valid(weapon_mesh) else global_position + Vector3.UP

func blade_base() -> Vector3:
	if is_two_handed() and is_instance_valid(weapon_mesh):
		return weapon_mesh.to_global(Vector3(0, float(Roster.WEAPONS[weapon_id].blade_start), 0))
	return weapon_mesh.to_global(Vector3(0, float(Roster.WEAPONS[weapon_id].get("blade_base", 22.0)), 0)) if is_instance_valid(weapon_mesh) else global_position + Vector3.UP

func is_invulnerable() -> bool:
	if state == "dodge" and action_time >= 0.035 and action_time <= 0.36:
		return true
	if character_id in ["zhaoyun", "guanyu"]:
		if state == "skill" and attack.get("kind", "") == "evade":
			return action_time >= 0.05 and action_time <= 0.31
		if state == "ultimate":
			for hit in skill_profile("ultimate").hits:
				if action_time >= hit.active.x - 0.10 and action_time <= hit.active.x + 0.015:
					return true
	return false

func _has_skill_armor(data: Dictionary) -> bool:
	if character_id not in ["machao", "xuchu"]:
		return false
	if state == "ultimate":
		return action_time >= float(skill_profile("ultimate").get("armor_from", 0.55))
	var window: Vector2 = attack.get("armor_window", Vector2(0.18, 0.70))
	return state == "skill" and bool(attack.get("light_armor", false)) and action_time >= window.x and action_time <= window.y and not data.heavy

func strike_source_position(attacker: DuelFighter, _data: Dictionary) -> Vector3:
	# Existing combat keeps its caster-based guard. Duel projectiles may
	# override this without changing the shared RPG's behavior.
	return attacker.global_position

func guard_facing() -> Vector3:
	return forward()

func receive_strike(attacker: DuelFighter, data: Dictionary) -> String:
	if hp <= 0.0:
		return "dead"
	var impact: Vector3 = data.get("contact_point", global_position + Vector3.UP * (2.1 if mounted else 1.05))
	if is_invulnerable():
		dodged_hits += 1
		gain_energy(9.0)
		impact_received.emit(self, "evade", impact)
		return "evade"
	var toward_attacker = strike_source_position(attacker, data) - global_position
	toward_attacker.y = 0.0
	var front_guard = toward_attacker.normalized().dot(guard_facing()) > 0.1
	var guard_window: Vector2 = attack.get("guard_window", Vector2(-1.0, -1.0))
	var skill_guard = state == "skill" and action_time >= guard_window.x and action_time <= guard_window.y
	if skill_guard and front_guard and not bool(data.get("unparryable", false)):
		# Zhang Fei roots his spear; Xu Chu braces his blade. A successful
		# interception strengthens their already scheduled physical retaliation.
		stamina = maxf(0.0, stamina - float(data.get("guard_cost", 24.0)) * 0.55)
		if stamina <= 0.0 or bool(data.get("force_guardbreak", false)):
			stagger(float(data.get("break_stun", 0.8)))
			impact_received.emit(self, "break", impact)
			return "break"
		skill_counter_primed = true
		blocked_hits += 1
		gain_energy(10.0)
		regen_delay = 1.0
		if not bool(data.heavy):
			attacker.stagger(0.36)
		impact_received.emit(self, "block", impact)
		return "block"
	if state == "block" and front_guard:
		if action_time <= 0.18 and not data.heavy and not data.get("unparryable", false):
			parries += 1
			stamina = minf(100.0, stamina + 13.0)
			gain_energy(18.0)
			attacker.stagger(0.70)
			impact_received.emit(self, "parry", impact)
			return "parry"
		stamina = maxf(0.0, stamina - float(data.get("guard_cost", 47.0 if data.heavy else 24.0)))
		gain_energy(6.0)
		if data.get("skill", "") != "ultimate":
			attacker.gain_energy(3.0)
		regen_delay = 1.0
		blocked_hits += 1
		var chip = minf(hp, float(data.get("guard_chip", 0.0)))
		if chip > 0.0:
			hp -= chip
			attacker.damage_dealt += chip
			gain_energy(chip * 0.40)
			if hp <= 0.0:
				_cancel_skill()
				state = "dead"
				action_time = 0.0
				play_clip("Death", 0.06)
				impact_received.emit(self, "heavy_hit", impact)
				return "hit"
		if stamina <= 0.0 or data.get("force_guardbreak", false):
			stagger(float(data.get("break_stun", 1.10)))
			impact_received.emit(self, "break", impact)
			return "break"
		velocity = -toward_attacker.normalized() * (2.2 if data.heavy else 0.8)
		impact_received.emit(self, "block", impact)
		return "block"
	var taken = minf(hp, float(data.damage))
	var armored = _has_skill_armor(data)
	var interrupted_charge = state == "ultimate" and skill_stage == "windup" and not armored
	hp = maxf(0.0, hp - taken)
	attacker.damage_dealt += taken
	gain_energy(taken * 0.40)
	if data.get("skill", "") != "ultimate":
		attacker.gain_energy(taken * 0.80)
	combo_buffered = false
	regen_delay = 0.9
	if not armored:
		velocity = -toward_attacker.normalized() * float(data.get("knockback", 3.8 if data.heavy else 1.6))
	if hp <= 0.0:
		_cancel_skill()
		state = "dead"
		action_time = 0.0
		play_clip("Death", 0.06)
	elif not armored:
		_cancel_skill()
		if interrupted_charge:
			gain_energy(35.0)
		state = "hit"
		action_time = 0.0
		action_duration = float(data.get("hit_stun", 0.50 if data.heavy else 0.30))
		play_clip("Hit", 0.055, action_duration)
	impact_received.emit(self, "heavy_hit" if data.heavy else "hit", impact)
	return "hit"

func stagger(duration: float) -> void:
	if hp <= 0.0:
		return
	_cancel_skill()
	state = "stagger"
	action_time = 0.0
	action_duration = duration
	combo_buffered = false
	play_clip("GuardBreak", 0.06, duration)

func _physics_process(delta: float) -> void:
	if not enabled:
		if jump_motion.airborne:
			# Ending a round stops attacks, not gravity. A disabled airborne rider
			# still lands through the same capsule and move_and_slide collision.
			_advance_jump(delta)
			velocity.x = 0.0
			velocity.z = 0.0
			move_and_slide()
			_finish_jump()
		elif jump_motion.active:
			_reset_jump()
		return
	_advance_jump(delta)
	action_time += delta
	_advance_attack_animation(delta)
	if mounted:
		mount_charge_time = maxf(0.0, mount_charge_time - delta)
		mount_charge_cooldown = maxf(0.0, mount_charge_cooldown - delta)
	for id in cooldowns:
		cooldowns[id] = maxf(0.0, cooldowns[id] - delta)
	regen_delay = maxf(0.0, regen_delay - delta)
	if regen_delay <= 0.0 and state not in ["attack", "dodge", "stagger", "dead", "skill", "ultimate"]:
		stamina = minf(100.0, stamina + delta * (9.0 if state == "block" else 23.0))
	_update_facing(delta)
	match state:
		"skill":
			_update_skill(delta)
		"ultimate":
			_update_ultimate()
		"attack":
			var window: Vector2 = attack.active
			# Keep light/heavy as start notifications for input/recording. The
			# audible air cut belongs to the physical release, after anticipation.
			if not swing_announced and action_time >= maxf(0.0, window.x - 0.055) and action_time <= window.y:
				swing_announced = true
				action_started.emit(self, "swing_heavy" if bool(attack.get("heavy", false)) else "swing_light")
			if action_time >= window.x and action_time <= window.y and not hit_landed:
				_emit_attack_strike(attack)
			# A synchronous parry/counter can change our state during the signal.
			if state == "attack":
				var thrust = float(attack.lunge) if action_time < window.y and action_time > 0.06 else 0.0
				velocity.x = forward().x * thrust
				velocity.z = forward().z * thrust
				if combo_buffered and combo < 2 and action_time >= maxf(window.y + 0.10, action_duration * 0.58):
					if not _begin_attack(combo + 1):
						combo_buffered = false
				elif action_time >= action_duration:
					_idle()
		"dodge":
			var speed = 7.4 * pow(maxf(0.0, 1.0 - action_time / 0.46), 0.6)
			velocity.x = dodge_direction.x * speed
			velocity.z = dodge_direction.z * speed
			if action_time >= action_duration:
				_idle()
		"hit", "stagger":
			velocity.x = move_toward(velocity.x, 0.0, delta * 12.0)
			velocity.z = move_toward(velocity.z, 0.0, delta * 12.0)
			if action_time >= action_duration:
				_idle()
		"dead":
			velocity.x = move_toward(velocity.x, 0.0, delta * 10.0)
			velocity.z = move_toward(velocity.z, 0.0, delta * 10.0)
		_:
			_update_locomotion(delta)
	if mounted:
		_update_mount_motion(delta)
	_limit_thrust_motion()
	if not jump_motion.airborne:
		velocity.y -= 20.0 * delta
	if is_on_floor() and velocity.y < 0:
		velocity.y = -0.2
	var before_move = position
	move_and_slide()
	_finish_jump()
	var flat = Vector2(position.x, position.z)
	var arena_radius = movement_radius if movement_radius > 0.0 else (11.4 if mounted else 7.6)
	if flat.length() > arena_radius:
		flat = flat.normalized() * arena_radius
		position.x = flat.x
		position.z = flat.y
		if mounted:
			mount_speed = minf(mount_speed, 1.2)
	if mounted and delta > 0.0:
		# Colliding with a horse or the arena edge must also stop the gait,
		# HUD speed and cavalry damage bonus, not just the physics body.
		var travelled_speed = Vector2(position.x - before_move.x, position.z - before_move.z).length() / delta if state in ["skill", "ultimate"] else maxf(0.0, (position - before_move).dot(forward()) / delta)
		mount_speed = minf(mount_speed, travelled_speed)
	_after_attack_move()
	previous_tip = blade_tip()

func _update_facing(delta: float) -> void:
	if contact_latched:
		# Once the point meets armour, movement may turn away rather than
		# continuing the automatic chase through the other fighter.
		mount_turn_rate = 0.0
		if input_move.length_squared() > 0.01:
			var error = angle_difference(rotation.y, atan2(input_move.x, input_move.z))
			var step = clampf(error, -2.2 * delta, 2.2 * delta)
			rotation.y += step
			if mounted:
				mount_turn_rate = step / maxf(delta, 0.001)
		return
	if mounted:
		_update_mount_facing(delta)
		return
	var agile_step = state == "skill" and attack.get("kind", "") == "evade"
	var chasing = state == "ultimate" and bool(skill_profile("ultimate").get("chase", skill_profile("ultimate").kind == "chase"))
	var committed = (state in ["attack", "skill"] and action_time >= (float(attack.active.x) - 0.025 if agile_step else 0.10))
	if state == "ultimate":
		committed = action_time >= 0.45
		if chasing:
			committed = false
			for hit in skill_profile("ultimate").hits:
				# Re-aim through the lunge, then commit the narrow blade at contact.
				if action_time >= hit.active.x - 0.015 and action_time <= hit.active.y:
					committed = true
	if not is_instance_valid(opponent) or hp <= 0.0 or state in ["dodge", "hit", "stagger"] or committed:
		turn_speed = 0.0
		turning_in_place = false
		return
	var direction = opponent.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.04:
		return
	var error = angle_difference(rotation.y, atan2(direction.x, direction.z))
	var moving = input_move.length() > 0.1
	if state in ["idle", "move"] and not moving:
		# Hysteresis prevents tiny target movements from rotating planted feet.
		# Larger changes use a short stepping gait and bounded angular speed.
		if not turning_in_place and absf(error) > deg_to_rad(10.0):
			turning_in_place = true
			turn_direction = signf(error)
		elif turning_in_place and absf(error) < deg_to_rad(3.0):
			turning_in_place = false
		if not turning_in_place:
			turn_speed = 0.0
			return
	else:
		turning_in_place = false
	var limit = 7.2 if chasing or agile_step else (3.6 if moving else 2.8)
	var wanted = clampf(error * (14.0 if chasing or agile_step else 7.0), -limit, limit)
	turn_speed = move_toward(turn_speed, wanted, delta * (60.0 if chasing or agile_step else 14.0))
	var step = clampf(turn_speed * delta, -absf(error), absf(error))
	rotation.y += step

func locomotion_step_interval(clip: String) -> float:
	return 0.34 if clip == "Run" else 0.40

func _update_locomotion(delta: float) -> void:
	if mounted:
		var guarding = wants_block and stamina > 1.0 and mount_charge_time <= 0.0
		var next_state = "block" if guarding else ("move" if input_move.length() > 0.1 else "idle")
		if state != next_state:
			state = next_state
			action_time = 0.0
			play_clip("Block" if state == "block" else "Idle", 0.16)
		if state == "block" and action_time > 0.38:
			animation_player.seek(0.44, true)
			animation_player.pause()
		return
	if wants_block and stamina > 1.0:
		if state != "block":
			state = "block"
			action_time = 0.0
			play_clip("Block", 0.10)
		if action_time > 0.38:
			animation_player.seek(0.44, true)
			animation_player.pause()
		velocity.x = move_toward(velocity.x, 0.0, delta * 22.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 22.0)
		return
	if state == "block":
		_idle()
	var movement = input_move.limit_length()
	var speed = 2.85
	var gait_rate = 1.0
	var clip = "Idle"
	if movement.length() > 0.1:
		state = "move"
		var local = global_basis.inverse() * movement
		# Keep the controller's original forward/side/reverse speeds. Hysteresis
		# below selects visuals only; it must not alter navigation or spacing.
		speed = 2.85 if local.z > 0.65 else 1.65
		# Small hysteresis keeps the same authored gait around diagonal input,
		# instead of restarting the run/strafe crossfade every other frame.
		var forward_threshold = 0.53 if current_clip == "Run" else 0.68
		var backward_threshold = -0.53 if current_clip == "WalkBack" else -0.68
		if local.z > forward_threshold:
			clip = "Run"
			gait_rate = 1.38 * speed / 2.85
		elif local.z < backward_threshold:
			clip = "WalkBack"
			gait_rate = 1.65
		else:
			clip = "StrafeLeft" if local.x > 0 else "StrafeRight"
			gait_rate = 1.65 * speed / 1.65
		footstep_clock += delta * movement.length()
		if footstep_clock > locomotion_step_interval(clip):
			footstep_clock = 0.0
			action_started.emit(self, "step")
	else:
		state = "idle"
		if turning_in_place:
			clip = "TurnLeft" if turn_direction > 0.0 else "TurnRight"
			gait_rate = clampf(absf(turn_speed) / 1.6, 0.65, 1.65)
			footstep_clock += delta * gait_rate
			if footstep_clock > 0.67:
				footstep_clock = 0.0
				action_started.emit(self, "step")
	velocity.x = move_toward(velocity.x, movement.x * speed, delta * 18.0)
	velocity.z = move_toward(velocity.z, movement.z * speed, delta * 18.0)
	if current_clip != clip:
		play_clip(clip, 0.20)
	var target_rate = gait_rate if turning_in_place else (gait_rate * movement.length() if clip != "Idle" else 1.0)
	locomotion_rate = lerpf(locomotion_rate, target_rate, 1.0 - exp(-delta * 11.0))
	animation_player.speed_scale = locomotion_rate
	if clip in GAIT_CLIPS and animation_player.current_animation_length > 0.0:
		locomotion_phase = fposmod(animation_player.current_animation_position / animation_player.current_animation_length, 1.0)

func _update_mount_facing(delta: float) -> void:
	mount_turn_rate = 0.0
	if hp <= 0.0 or state in ["hit", "stagger"]:
		return
	var direction = input_move
	if state in ["skill", "ultimate"]:
		direction = opponent.global_position - global_position if is_instance_valid(opponent) else forward()
	if direction.length_squared() < 0.01:
		if mount_speed > 0.5 or not is_instance_valid(opponent):
			return
		direction = opponent.global_position - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return
	# Commit the weapon through its contact frame, with a much wider turning
	# circle at a gallop. The horse never strafes or reverses instantly.
	if action_facing_committed():
		return
	var error = angle_difference(rotation.y, atan2(direction.x, direction.z))
	var limit = 1.1 if mount_charge_time > 0.0 else lerpf(2.5, 1.65, clampf(mount_speed / 5.0, 0.0, 1.0))
	var step = clampf(error, -limit * delta, limit * delta)
	rotation.y += step
	mount_turn_rate = step / maxf(delta, 0.001)

func _update_mount_motion(delta: float) -> void:
	var desired = 0.0
	var action_motion = Vector3.ZERO
	var phased_action = state in ["skill", "ultimate"]
	if input_move.length() > 0.1:
		var alignment = maxf(0.0, forward().dot(input_move.normalized()))
		desired = 4.8 * input_move.limit_length().length() * lerpf(0.12, 1.0, alignment)
	if mount_charge_time > 0.0:
		desired = 8.2
	if state == "attack" and attack.has("mount_advance"):
		var advance: Dictionary = attack.mount_advance
		if action_time >= float(advance.start) and action_time <= float(advance.end):
			desired = maxf(desired, float(advance.speed))
	if phased_action:
		var profile = attack if state == "skill" else skill_profile("ultimate")
		# Skill movement owns the route. Held orbit/reverse keys cannot turn a
		# rooted guard into a gallop or steer a committed lance hit sideways.
		action_motion = skill_motion_velocity(profile)
		desired = action_motion.length()
		if bool(profile.get("rooted", false)):
			desired = 0.0
	if state == "block":
		desired = minf(desired, 1.2)
	elif state in ["hit", "stagger", "dead"]:
		desired = 0.0
		mount_charge_time = 0.0
	var acceleration = 11.0 if mount_charge_time > 0.0 else (4.6 if desired > mount_speed else 8.5)
	if phased_action:
		# A measured backward/sideways horse step preserves the evade's route.
		# Vector acceleration also prevents a lateral escape snapping instantly
		# into the returning forward thrust.
		_mount_action_velocity = _mount_action_velocity.move_toward(action_motion, delta * 8.5)
		velocity.x = _mount_action_velocity.x
		velocity.z = _mount_action_velocity.z
		mount_speed = _mount_action_velocity.length()
	else:
		mount_speed = move_toward(mount_speed, desired, delta * acceleration)
		velocity.x = forward().x * mount_speed
		velocity.z = forward().z * mount_speed
		_mount_action_velocity = Vector3(velocity.x, 0.0, velocity.z)
	footstep_clock += delta * mount_speed
	if mount_speed > 0.4 and footstep_clock > 1.25:
		footstep_clock = 0.0
		action_started.emit(self, "hoof")

func _limit_thrust_motion() -> void:
	# A standing fighter can brace as the point meets resistance. A horse
	# retains its real impact speed until the strike resolves, then brakes.
	var resisted = contact_latched or (contact_active and not mounted) or _contact_backstep_requested
	if not is_physical_thrust() or not resisted or not is_instance_valid(opponent):
		return
	var toward = opponent.global_position - global_position
	toward.y = 0.0
	if toward.length_squared() < 0.0001:
		return
	toward = toward.normalized()
	if contact_latched and input_move.length_squared() > 0.01 and not mounted:
		var escape = input_move.limit_length() * 2.8
		velocity.x = escape.x
		velocity.z = escape.z
	var advance = maxf(0.0, Vector3(velocity.x, 0, velocity.z).dot(toward))
	velocity -= toward * advance
	if _contact_backstep_requested:
		# A rare fully enclosed guard withdraws through normal physics, never a
		# position correction; collision and arena limits remain authoritative.
		velocity.x -= toward.x * 1.6
		velocity.z -= toward.z * 1.6
	if mounted:
		mount_charge_time = 0.0

func _idle() -> void:
	_cancel_skill()
	state = "idle"
	action_time = 0.0
	combo_buffered = false
	combo = 0
	play_clip("Idle", 0.13)

func action_facing_committed() -> bool:
	if state == "attack":
		return action_time >= float(attack.active.x) - 0.08 and action_time <= float(attack.active.y)
	if state not in ["skill", "ultimate"]:
		return false
	var profile = attack if state == "skill" else skill_profile("ultimate")
	for data in profile.get("hits", [profile]):
		var window: Vector2 = data.get("active", Vector2.ZERO)
		if action_time >= window.x - 0.08 and action_time <= window.y:
			return true
	return false

func skill_motion_velocity(profile: Dictionary) -> Vector3:
	if bool(profile.get("rooted", false)):
		return Vector3.ZERO
	if profile.has("motion"):
		for segment in profile.motion:
			if action_time > float(segment.start) and action_time < float(segment.end):
				var direction = forward()
				if not mounted:
					if segment.get("direction", "") == "side": direction = global_basis.x
					elif segment.get("direction", "") == "back": direction = -forward()
				return direction * float(segment.speed)
		return Vector3.ZERO
	var kind: String = profile.kind
	var speed = 0.0
	var direction = forward()
	if state == "ultimate" and bool(profile.get("chase", kind == "chase")):
		for data in profile.hits:
			var ready_time = float(data.start)
			if is_thrust_weapon() and data.has("clip") and animation_names.has(data.clip):
				var source_length = animation_player.get_animation(animation_names[data.clip]).length
				ready_time += float(clip_thrust_ready_seconds.get(data.clip, 0.25)) * float(data.clip_duration) / maxf(source_length, 0.001)
			if action_time >= maxf(float(data.active.x) - 0.10, ready_time) and action_time <= data.active.x + 0.025:
				speed = float(profile.get("chase_speed", 6.0))
	elif kind == "thrust" and action_time > float(profile.get("dash_from", 0.0)) and action_time < float(profile.get("dash_to", 0.0)):
		speed = float(profile.lunge)
	elif kind == "sweep" and action_time > 0.16 and action_time < float(profile.active.y):
		speed = float(profile.lunge)
	elif kind == "evade":
		if action_time >= float(profile.strike_start) and action_time < float(profile.active.y):
			speed = float(profile.get("return_lunge", 0.0))
		elif action_time > 0.04 and action_time < 0.27:
			speed = 2.0 if mounted else 6.0
			direction = dodge_direction
	return direction * speed

func _update_skill(delta: float) -> void:
	var kind: String = attack.kind
	for index in attack.get("stages", []).size():
		var stage: Dictionary = attack.stages[index]
		if action_time >= float(stage.start) and skill_animation_index < index:
			skill_animation_index = index
			_reset_thrust_contact()
			play_clip(stage.clip, 0.065, float(stage.duration))
	if kind == "evade" and action_time >= float(attack.strike_start) and not skill_animation_started:
		skill_animation_started = true
		_reset_thrust_contact()
		play_clip(attack.strike_clip, 0.07, 0.50)
	var hits: Array = attack.get("hits", [attack])
	for index in hits.size():
		var data: Dictionary = hits[index]
		var window: Vector2 = data.active
		if action_time < window.x or action_time > window.y:
			continue
		if skill_hit_index != index:
			skill_hit_index = index
			hit_landed = false
			skill_stage = "active"
			if not skill_strike_announced:
				skill_strike_announced = true
				skill_triggered.emit(self, skill_id, "release")
			elif hits.size() > 1:
				skill_triggered.emit(self, skill_id, "finish" if index == hits.size() - 1 else "strike")
		var payload = attack.duplicate(true)
		payload.merge(data, true)
		payload.erase("hits")
		payload.erase("stages")
		if skill_counter_primed:
			payload.damage = float(payload.damage) * float(attack.get("counter_bonus", 1.0))
			payload["guard_cost"] = float(payload.get("guard_cost", 36.0)) * 1.25
			payload["counter_confirmed"] = true
		_thrust_segment_data = payload
		if not hit_landed:
			strike_requested.emit(self, payload)
			if state != "skill": return
	var motion = skill_motion_velocity(attack)
	if kind != "evade" and is_instance_valid(opponent) and global_position.distance_to(opponent.global_position) < 1.12:
		motion = Vector3.ZERO
	velocity.x = move_toward(velocity.x, motion.x, delta * 75.0)
	velocity.z = move_toward(velocity.z, motion.z, delta * 75.0)
	if action_time > float(hits[-1].active.y):
		skill_stage = "recovery"
	if action_time >= action_duration:
		_cancel_skill("complete")
		_idle()

func _update_ultimate() -> void:
	var profile = skill_profile("ultimate")
	var hits: Array = profile.hits
	if action_time >= float(profile.windup) and skill_stage == "windup":
		skill_stage = "active"
		skill_triggered.emit(self, "ultimate", "release")
	for index in hits.size():
		var data: Dictionary = hits[index]
		var window: Vector2 = data.active
		if action_time >= float(data.start) and skill_animation_index < index:
			skill_animation_index = index
			_reset_thrust_contact()
			_thrust_segment_data = data.duplicate(true)
			play_clip(String(data.get("clip", profile.get("release_clip", "Idle"))), 0.055,
				float(data.get("clip_duration", profile.get("release_duration", 0.75))))
		if action_time >= window.x and action_time <= window.y:
			if skill_hit_index != index:
				skill_hit_index = index
				hit_landed = false
				attack = data.duplicate(true)
				attack.merge({"heavy": true, "unparryable": true, "skill": "ultimate", "wave": true})
				# Per-hit geometry wins: a planted spear's opening roar cannot
				# turn its following real thrust into a circular damage volume.
				for field in ["half_width", "reach", "guard_cost"]:
					if not attack.has(field): attack[field] = profile.get(field, 0.55 if field == "half_width" else 3.8 if field == "reach" else 32.0)
				if not attack.has("shape"): attack["shape"] = "line"
				if not attack.has("knockback"): attack["knockback"] = 0.35
				if not attack.has("hit_stun"): attack["hit_stun"] = 0.20
				_thrust_segment_data = attack.duplicate(true)
				skill_triggered.emit(self, "ultimate", "finish" if index == hits.size() - 1 else "strike")
			if not hit_landed:
				strike_requested.emit(self, attack)
				if state != "ultimate": return
	var motion = skill_motion_velocity(profile)
	if is_instance_valid(opponent) and global_position.distance_to(opponent.global_position) < 1.18:
		motion = Vector3.ZERO
	velocity.x = motion.x
	velocity.z = motion.z
	if action_time > hits[-1].active.y:
		skill_stage = "recovery"
	if action_time >= action_duration:
		_cancel_skill("complete")
		_idle()

func _advance_attack_animation(_delta: float) -> void:
	pass

func _emit_attack_strike(profile: Dictionary) -> void:
	strike_requested.emit(self, profile)

func _after_attack_move() -> void:
	pass
