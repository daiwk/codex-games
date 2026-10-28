extends "res://scripts/fighter.gd"

const DuelTempo = preload("res://scripts/duel_attack_tempo.gd")
const DuelSkills = preload("res://scripts/duel_skill_profiles.gd")
const Cavalry = preload("res://scripts/duel_mounted_combat.gd")
const CavalryPose = preload("res://scripts/duel_mounted_pose.gd")
const FootMotionPolish = preload("res://scripts/duel_motion_polish.gd")
signal duel_landed(at: Vector3)

const DUEL_COMBO_CLIPS = {
	"zhaoyun": {"Attack2": "DragonLow", "Attack3": "DragonHigh"},
	"machao": {"Attack2": "TigerCouch", "Attack3": "TigerDrive"},
	"zhangfei": {"Attack2": "SerpentRoot", "Attack3": "SerpentLong"},
	"guanyu": {"Attack3": "CrescentLow"},
	"lubu": {"Attack2": "HalberdRise", "Attack3": "HalberdDrop", "Heavy": "HalberdDrop"},
}
const DUEL_FOOT_NORMALS = {
	"zhaoyun": {"Attack1": "DuelDragonJab", "Attack2": "DuelDragonLow", "Attack3": "DuelDragonDrive", "Heavy": "DuelDragonHeavy"},
	"machao": {"Attack1": "DuelTigerProbe", "Attack2": "DuelTigerLow", "Attack3": "DuelTigerDrive", "Heavy": "DuelTigerHeavy"},
}

# Duel-only opt-in target navigation. Shared combat and RPG actors retain
# their own targeting policy; active weapon trajectories remain committed.
const LOCK_FORWARD_SPEED = 4.8
const LOCK_REVERSE_SPEED = 2.2
const LOCK_ORBIT_SPEED = 2.6
var lock_facing = false
var lock_forward_speed = 0.0
var _lock_move_velocity = Vector3.ZERO
var _lock_motion_active = false
var _duel_tempo_library: AnimationLibrary
var _duel_step_velocity = Vector3.ZERO
var _duel_step_basis = Basis.IDENTITY
var _duel_air_active = false
var _duel_air_elapsed = 0.0
var _duel_floor_snap = 0.2
var _duel_weapon_thrown = false
var _duel_push_velocity = Vector3.ZERO
var cavalry_body_yaw = 0.0
var _cavalry = Cavalry.new()
var _cavalry_input_explicit = false
var _cavalry_pending_side = 0
var _cavalry_selected_side = 0
var _cavalry_side_manual = false
var _cavalry_aim_committed = false
var _cavalry_attack_world_yaw = 0.0
var _cavalry_intended_speed = 0.0
var _cavalry_pose: SkeletonModifier3D
var _cavalry_edge_side = Vector3.ZERO
var _duel_actual_velocity = Vector3.ZERO
var _recorded_gaits = false
var _recorded_retreat_speed = 1.65
var _recorded_step_intervals: Dictionary = {}

func strike_source_position(attacker: DuelFighter, data: Dictionary) -> Vector3:
	if data.has("source_position") and String(data.get("special", "")) != "": return Vector3(data.source_position)
	return super.strike_source_position(attacker, data)

func guard_facing() -> Vector3:
	return duel_strike_forward() if mounted else super.guard_facing()

func skill_profile(id: String) -> Dictionary:
	var fallback = super.skill_profile(id)
	if mounted: fallback = Cavalry.profile(character_id, id, fallback)
	return DuelSkills.for_skill(character_id, id, fallback, mounted)

func _ready() -> void:
	super._ready()
	_setup_recorded_gaits()
	if not mounted and character_id in ["zhaoyun", "machao"] and is_thrust_weapon():
		# Keep the shared/RPG and mounted contact modifiers untouched.
		if is_instance_valid(thrust_contact):
			skeleton.remove_child(thrust_contact)
			thrust_contact.free()
		thrust_contact = FootMotionPolish.new()
		thrust_contact.setup(self, skeleton)
	if mounted:
		_cavalry_pose = CavalryPose.new()
		_cavalry_pose.setup(self, skeleton)
		if is_instance_valid(thrust_contact): skeleton.move_child(_cavalry_pose, thrust_contact.get_index())
	# Opponent normals must also be ready before their first visible attack.
	if not is_player: prewarm_attack_animations()

func _setup_recorded_gaits() -> void:
	if mounted or character_id != "zhaoyun" or not is_thrust_weapon(): return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/animation_manifest.json"))
	var config: Dictionary = manifest[character_id].get("recorded_duel_gaits", {})
	if config.is_empty(): return
	var aliases = {"Run": "DuelMocapRun", "WalkBack": "DuelMocapWalkBack"}
	for alias in aliases.values():
		if not animation_names.has(alias): return
	for logical in aliases:
		var key: String = animation_names[aliases[logical]]
		animation_player.get_animation(key).loop_mode = Animation.LOOP_LINEAR
		animation_names[logical] = key
	_recorded_retreat_speed = float(config["retreat_speed"])
	_recorded_step_intervals = config.get("step_intervals", {})
	_recorded_gaits = true

func _update_locomotion(delta: float) -> void:
	super._update_locomotion(delta)
	if not _recorded_gaits or state != "move" or current_clip != "WalkBack" or is_jumping(): return
	# Match recorded retreat cadence. Keep the original acceleration while
	# braking from forward travel; limit only speed along the new input.
	var movement = input_move.limit_length()
	if movement.length_squared() < 0.0001: return
	var direction = movement.normalized()
	var flat = Vector3(velocity.x, 0.0, velocity.z)
	var excess = flat.dot(direction) - _recorded_retreat_speed * movement.length()
	if excess > 0.0:
		flat -= direction * excess
		velocity.x = flat.x
		velocity.z = flat.z

func locomotion_step_interval(clip: String) -> float:
	return float(_recorded_step_intervals.get(clip, super.locomotion_step_interval(clip)))

func set_cavalry_input(throttle: float, steering: float, brake = false) -> void:
	_cavalry_input_explicit = true
	_cavalry.set_input(throttle, steering, brake)
	if brake: mount_charge_time = 0.0

func set_cavalry_attack_side(side: int) -> void:
	_cavalry_pending_side = clampi(side, -1, 1)

func cavalry_status() -> Dictionary:
	var rate = absf(_cavalry.turn_rate)
	return {"signed_speed": _cavalry.speed, "target_speed": _cavalry.target_speed,
		"throttle": _cavalry.throttle, "steering": _cavalry.steering,
		"braking": _cavalry.braking, "attack_side": _cavalry_selected_side,
		"body_yaw": cavalry_body_yaw, "turn_rate": _cavalry.turn_rate,
		"turn_radius": absf(_cavalry.speed) / rate if rate > 0.01 else 0.0}

func duel_strike_forward() -> Vector3:
	return (global_basis * Basis(Vector3.UP, cavalry_body_yaw)).z.normalized() if mounted else forward()

func cavalry_impact_data(defender: Node3D, data: Dictionary) -> Dictionary:
	var result = data.duplicate(true)
	if not mounted or bool(data.get("external_only", false)): return result
	var actual = _duel_actual_velocity.slide(Vector3.UP)
	var other = Vector3.ZERO
	if defender.has_method("get_duel_actual_velocity"):
		other = Vector3(defender.call("get_duel_actual_velocity")).slide(Vector3.UP)
	elif defender is CharacterBody3D:
		other = defender.get_real_velocity().slide(Vector3.UP)
	var relative = (actual - other).length()
	var factor = 1.0 + clampf((relative - 2.0) / 12.0, 0.0, 1.0) * 0.65 if actual.length() > 1.4 else 1.0
	result["damage"] = float(result.damage) * factor
	result["guard_cost"] = float(result.get("guard_cost", 24.0)) * minf(factor, 1.25)
	result["cavalry_relative_speed"] = relative
	result["cavalry_multiplier"] = factor
	return result

func get_duel_actual_velocity() -> Vector3:
	return _duel_actual_velocity

func _update_cavalry_aim(delta: float) -> void:
	var desired = 0.0
	if state == "attack" and not _duel_weapon_thrown:
		if _cavalry_aim_committed:
			desired = angle_difference(rotation.y, _cavalry_attack_world_yaw)
		else:
			desired = Cavalry.attack_yaw(_cavalry_selected_side, is_two_handed())
			if is_instance_valid(opponent) and not _cavalry_side_manual:
				# Aim the rider at the pass's contact phase, not where a moving
				# opponent stood at the beginning of a long swing. Explicit left/
				# right reins stay on that side; they never retarget across the horse.
				var lead = clampf(Cavalry.contact_time(attack, is_two_handed()) - action_time, 0.0, 0.30)
				var relative_velocity = opponent.get_real_velocity() - get_real_velocity()
				var predicted = opponent.global_position - global_position + relative_velocity.slide(Vector3.UP) * lead
				var local = global_basis.inverse() * predicted
				var angle = atan2(local.x, local.z)
				desired = angle
			if character_id == "guanyu" and combo == 1 and not bool(attack.get("heavy", false)): desired -= 0.22
			# The calibrated rear palm sits left of the chest axis. A small
			# right-side lead puts the physical spear line on the pass lane.
			if is_thrust_weapon() and _cavalry_selected_side > 0: desired += 0.10
			desired = clampf(desired, -deg_to_rad(70.0), deg_to_rad(70.0))
			if action_time >= float(attack.active.x) - 0.03:
				_cavalry_aim_committed = true
				_cavalry_attack_world_yaw = rotation.y + desired
	elif state == "block" and is_instance_valid(opponent):
		var local = global_basis.inverse() * (opponent.global_position - global_position)
		desired = atan2(local.x, local.z)
	cavalry_body_yaw = move_toward(cavalry_body_yaw, clampf(desired, -deg_to_rad(78.0), deg_to_rad(78.0)), delta * 8.0)

func _process(delta: float) -> void:
	super._process(delta)
	if mounted and is_instance_valid(horse) and _cavalry.speed < -0.08:
		var tree = horse.get("_animation_tree") as AnimationTree
		if is_instance_valid(tree): tree.set("parameters/Cadence/scale", -absf(float(tree.get("parameters/Cadence/scale"))))

func _update_two_hand_grip(delta = 0.0, instant = false) -> void:
	if not is_inside_tree() or not is_instance_valid(grip) or not grip.is_inside_tree() or not is_instance_valid(skeleton) or not skeleton.is_inside_tree(): return
	super._update_two_hand_grip(delta, instant)
	if not mounted or not is_instance_valid(grip) or not Roster.WEAPONS.get(weapon_id, {}).get("edge_forward", false): return
	var axis = grip.global_basis.y.normalized()
	var edge = duel_strike_forward().slide(axis)
	if edge.length_squared() < 0.001: return
	var desired = -edge.normalized()
	var previous = _cavalry_edge_side.slide(axis)
	if instant or previous.length_squared() < 0.01:
		_cavalry_edge_side = desired
	else:
		previous = previous.normalized()
		_cavalry_edge_side = previous.rotated(axis, clampf(previous.signed_angle_to(desired, axis), -14.0 * delta, 14.0 * delta))
	grip.global_basis = Basis(_cavalry_edge_side, axis, _cavalry_edge_side.cross(axis))

func resolve_animation_clip(clip: String) -> String:
	# Only the duel's foot spear normals select these newly baked whole-body
	# phrases. Mounted combat and the independent RPG retain their exact clips.
	if not mounted and is_thrust_weapon() and DUEL_FOOT_NORMALS.has(character_id):
		var authored = String(DUEL_FOOT_NORMALS[character_id].get(clip, ""))
		if authored != "" and animation_names.has(authored): return authored
	if mounted:
		var directional = Cavalry.normal_clip(character_id, clip, _cavalry_selected_side)
		if directional != clip: return directional
	if mounted and character_id == "zhaoyun" and clip == "Attack3":
		# The elevated foot stance crowds the mounted shaft into a different
		# close-contact elbow branch. Keep the rider's finisher on the safe line.
		return "Attack3"
	return String(DUEL_COMBO_CLIPS.get(character_id, {}).get(clip, clip))

func prewarm_attack_animations() -> void:
	var begin = Time.get_ticks_usec()
	var profiles = _light_attacks().duplicate(true)
	profiles.append(_heavy_attack_profile())
	var previous_side = _cavalry_selected_side
	for side in ([-1, 0, 1] if mounted else [0]):
		_cavalry_selected_side = side
		for original in profiles:
			var data = _weapon_adjusted_attack(original)
			var clip = resolve_animation_clip(String(data.clip))
			if animation_names.has(clip):
				DuelTempo.variant(animation_player.get_animation(animation_names[clip]), float(data.duration), data.active, bool(data.get("heavy", false)))
	_cavalry_selected_side = previous_side
	attack_warmup_ms = float(Time.get_ticks_usec() - begin) / 1000.0

func play_clip(clip: String, blend = 0.12, duration = 0.0) -> void:
	if state != "attack" or duration <= 0.0 or not attack.has("active"):
		super.play_clip(clip, blend, duration)
		return
	clip = resolve_animation_clip(clip)
	if not animation_names.has(clip):
		super.play_clip(clip, blend, duration)
		return
	var key: String = animation_names[clip]
	var entry = DuelTempo.variant(animation_player.get_animation(key), duration, attack.active, bool(attack.get("heavy", false)))
	tempo_profile = entry.profile
	if not tempo_profile.is_empty():
		if _duel_tempo_library == null:
			_duel_tempo_library = AnimationLibrary.new()
			animation_player.add_animation_library("DuelTempo", _duel_tempo_library)
		if not _duel_tempo_library.has_animation(entry.key):
			_duel_tempo_library.add_animation(entry.key, entry.animation)
		key = "DuelTempo/" + String(entry.key)
	animation_player.speed_scale = 1.0
	animation_player.play(key, blend, animation_player.get_animation(key).length / duration)
	current_clip = clip

func _enter_attack() -> void:
	if mounted:
		_cavalry_selected_side = _cavalry_pending_side
		_cavalry_side_manual = _cavalry_pending_side != 0
		if not _cavalry_side_manual and is_instance_valid(opponent):
			var local = global_basis.inverse() * (opponent.global_position - global_position)
			_cavalry_selected_side = signi(roundi(local.x * 1000.0)) if absf(atan2(local.x, local.z)) > deg_to_rad(15.0) else 0
		_cavalry_pending_side = 0
		_cavalry_aim_committed = false
	_duel_step_basis = global_basis
	_duel_step_velocity = Vector3(velocity.x, 0.0, velocity.z)
	super._enter_attack()

func register_thrust_contact(at: Vector3) -> void:
	if not is_physical_thrust(): return
	contact_latched = true
	contact_active = true
	contact_point = at
	if mounted: mount_charge_time = 0.0
	# Continue the authored hips, stepping and withdrawal. The existing contact
	# modifier remains responsible for resistance and preventing penetration.

func duel_can_cancel_normal_recovery() -> bool:
	return state == "attack" and action_time >= float(attack.active.y) + 0.04

func request_light() -> bool:
	if _duel_weapon_thrown: return false
	return super.request_light()

func request_heavy() -> bool:
	if _duel_weapon_thrown: return false
	if enabled and hp > 0.0 and duel_can_cancel_normal_recovery() and stamina >= float(_heavy_attack_profile().cost): _idle()
	return super.request_heavy()

func request_skill(id: String) -> bool:
	if _duel_weapon_thrown: return false
	if enabled and hp > 0.0 and id in cooldowns and cooldowns[id] <= 0.0 and stamina >= skill_cost(id) and duel_can_cancel_normal_recovery(): _idle()
	return super.request_skill(id)

func request_ultimate() -> bool:
	if _duel_weapon_thrown: return false
	if enabled and hp > 0.0 and energy >= 99.999 and duel_can_cancel_normal_recovery(): _idle()
	return super.request_ultimate()

func _duel_source_phase(time: float) -> float:
	if tempo_profile.is_empty(): return clampf(time / maxf(action_duration, 0.001), 0.0, 1.0)
	return DuelTempo.source_at_action_time(time, tempo_profile) / maxf(float(tempo_profile.length), 0.001)

func _duel_step_offset(time: float) -> Vector3:
	var phase = _duel_source_phase(time)
	var heavy = bool(attack.get("heavy", false))
	var distance = 0.30 if heavy else [0.18, 0.24, 0.30][mini(combo, 2)]
	var advance = distance * smoothstep(0.16, 0.42, phase)
	var gather = -0.025 * smoothstep(0.0, 0.15, phase)
	var settle = -0.06 * smoothstep(0.68, 0.98, phase)
	return _duel_step_basis.z * (advance + gather + settle)

func _limit_thrust_motion() -> void:
	if not mounted and state == "attack":
		var delta = get_physics_process_delta_time()
		var desired = (_duel_step_offset(action_time) - _duel_step_offset(maxf(0.0, action_time - delta))) / maxf(delta, 0.001)
		_duel_step_velocity = _duel_step_velocity.move_toward(desired.limit_length(3.2), delta * 22.0)
		velocity.x = _duel_step_velocity.x
		velocity.z = _duel_step_velocity.z
	elif not mounted and state == "dodge":
		# Accelerate through the authored push-off, then land and settle, instead
		# of starting at maximum speed with planted feet.
		var phase = clampf(action_time / 0.40, 0.0, 1.0)
		var speed = 1.40 / 0.40 * 6.0 * phase * (1.0 - phase)
		velocity.x = dodge_direction.x * speed
		velocity.z = dodge_direction.z * speed
	super._limit_thrust_motion()
	if _duel_push_velocity.length_squared() > 0.0001:
		# Final planar velocity wins over attack, horse and ordinary hit motion.
		# CharacterBody still resolves walls, bodies and the arena via its one
		# normal move_and_slide call; this never corrects a position directly.
		velocity.x = _duel_push_velocity.x
		velocity.z = _duel_push_velocity.z
		_duel_push_velocity = _duel_push_velocity.move_toward(Vector3.ZERO, get_physics_process_delta_time() * 18.0)

func apply_duel_impulse(direction: Vector3, strength: float) -> void:
	var planar = direction.slide(Vector3.UP)
	if planar.length_squared() < 0.0001 or hp <= 0.0: return
	_duel_push_velocity = planar.normalized() * clampf(strength, 0.0, 9.0)

func begin_duel_aerial(launch_speed = 7.2) -> bool:
	if mounted or not enabled or hp <= 0.0 or _duel_air_active or is_jumping(): return false
	_duel_floor_snap = floor_snap_length
	floor_snap_length = 0.0
	_duel_air_active = true
	_duel_air_elapsed = 0.0
	velocity.y = maxf(velocity.y, float(launch_speed))
	return true

func duel_is_airborne() -> bool:
	return _duel_air_active or bool(jump_status().airborne)

func _can_jump() -> bool:
	return not _duel_air_active and super._can_jump()

func set_duel_weapon_thrown(thrown: bool) -> void:
	_duel_weapon_thrown = thrown
	if is_instance_valid(weapon_mesh): weapon_mesh.visible = not thrown

func duel_weapon_is_thrown() -> bool:
	return _duel_weapon_thrown

func _cancel_skill(completion = "cancel") -> void:
	if completion != "complete" and skill_id != "": set_duel_weapon_thrown(false)
	super._cancel_skill(completion)

func reset_fighter() -> void:
	set_duel_weapon_thrown(false)
	if _duel_air_active: floor_snap_length = _duel_floor_snap
	_duel_air_active = false
	_duel_air_elapsed = 0.0
	_duel_step_velocity = Vector3.ZERO
	_duel_push_velocity = Vector3.ZERO
	_cavalry.reset()
	_cavalry_input_explicit = false
	_cavalry_pending_side = 0
	_cavalry_selected_side = 0
	_cavalry_aim_committed = false
	cavalry_body_yaw = 0.0
	_cavalry_edge_side = Vector3.ZERO
	_duel_actual_velocity = Vector3.ZERO
	super.reset_fighter()
	_lock_move_velocity = Vector3.ZERO
	_lock_motion_active = false
	lock_forward_speed = 0.0

func _has_lock_target() -> bool:
	return mounted and lock_facing and hp > 0.0 and is_instance_valid(opponent) and opponent != self and opponent.hp > 0.0

func _physics_process(delta: float) -> void:
	if hp <= 0.0 and _duel_weapon_thrown: set_duel_weapon_thrown(false)
	if _duel_air_active: _duel_air_elapsed += delta
	if not enabled and _duel_air_active:
		# Round presentation can disable combat while a real jump is airborne.
		# Finish gravity/collision only; never freeze or teleport the actor.
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= 20.0 * delta
		var before_air_move = position
		move_and_slide()
		_duel_actual_velocity = (position - before_air_move) / maxf(delta, 0.001)
		if _duel_air_elapsed > 0.08 and is_on_floor() and velocity.y <= 0.0:
			_duel_air_active = false
			floor_snap_length = _duel_floor_snap
			duel_landed.emit(global_position)
		return
	if not _has_lock_target() and _lock_motion_active:
		# A released backward/orbit step must not become a forward gallop.
		mount_speed = maxf(0.0, velocity.dot(forward()))
		_lock_move_velocity = Vector3.ZERO
		_lock_motion_active = false
		lock_forward_speed = 0.0
	var before_move = position
	super._physics_process(delta)
	_duel_actual_velocity = (position - before_move) / maxf(delta, 0.001)
	if mounted and enabled and delta > 0.0:
		var actual = _duel_actual_velocity.dot(forward())
		_cavalry.reconcile(actual, _cavalry_intended_speed)
		mount_speed = Vector2(position.x - before_move.x, position.z - before_move.z).length() / delta
		lock_forward_speed = actual
	if _duel_air_active and _duel_air_elapsed > 0.08 and is_on_floor() and velocity.y <= 0.0:
		_duel_air_active = false
		floor_snap_length = _duel_floor_snap
		duel_landed.emit(global_position)
	if _lock_motion_active and enabled and delta > 0.0:
		var travelled = (position - before_move) / delta
		travelled.y = 0.0
		mount_speed = minf(_lock_move_velocity.length(), travelled.length())
		_lock_move_velocity = travelled.limit_length(_lock_move_velocity.length())
		lock_forward_speed = _lock_move_velocity.dot(forward())

func _update_facing(delta: float) -> void:
	if mounted:
		_update_mount_facing(delta)
		_update_cavalry_aim(delta)
		return
	if state == "attack" and not contact_latched and action_time < float(attack.active.x) - 0.03 and is_instance_valid(opponent):
		var direction = (opponent.global_position - global_position).slide(Vector3.UP)
		if direction.length_squared() > 0.01:
			# The diagonal second cut travels to the right of the chest axis.
			# Lead with the shoulder during anticipation so the actual blade,
			# rather than only the character's chest, crosses the target line.
			var blade_lead = -0.22 if character_id == "guanyu" and combo == 1 and not bool(attack.get("heavy", false)) else 0.0
			var error = angle_difference(rotation.y, atan2(direction.x, direction.z) + blade_lead)
			rotation.y += clampf(error, -3.5 * delta, 3.5 * delta)
			_duel_step_basis = global_basis
		return
	if _has_lock_target() and state in ["idle", "move", "block"] and not contact_latched:
		turning_in_place = false
		turn_speed = 0.0
		_update_mount_facing(delta)
		return
	super._update_facing(delta)

func _update_mount_facing(delta: float) -> void:
	if not _cavalry_input_explicit:
		var movement = input_move.slide(Vector3.UP)
		var angle = angle_difference(rotation.y, atan2(movement.x, movement.z)) if movement.length_squared() > 0.01 else 0.0
		_cavalry.set_input(1.0 if movement.dot(forward()) > 0.1 else (-1.0 if movement.dot(forward()) < -0.4 else 0.0), clampf(angle, -1.0, 1.0), false)
	mount_turn_rate = _cavalry.steer(delta, state in ["hit", "stagger", "dead"])
	rotation.y += mount_turn_rate * delta

func _update_mount_motion(delta: float) -> void:
	_lock_motion_active = false
	var action_target = INF
	if state in ["skill", "ultimate"]:
		var profile = attack if state == "skill" else skill_profile("ultimate")
		if bool(profile.get("rooted", false)):
			action_target = 0.0
		elif profile.has("motion") or profile.get("kind", "") in ["thrust", "sweep", "evade", "chase"]:
			action_target = skill_motion_velocity(profile).dot(forward())
	elif state == "block":
		action_target = clampf(_cavalry.target_speed, -1.0, 1.6)
	elif state == "attack" and attack.has("mount_advance") and absf(_cavalry.speed) < 1.2:
		var advance: Dictionary = attack.mount_advance
		if action_time >= float(advance.start) and action_time <= float(advance.end): action_target = maxf(_cavalry.target_speed, float(advance.speed))
	_cavalry_intended_speed = _cavalry.advance(delta, mount_charge_time > 0.0, state in ["hit", "stagger", "dead"], action_target)
	velocity.x = forward().x * _cavalry_intended_speed
	velocity.z = forward().z * _cavalry_intended_speed
	mount_speed = absf(_cavalry_intended_speed)
	footstep_clock += delta * mount_speed
	if mount_speed > 0.4 and footstep_clock > 1.25:
		footstep_clock = 0.0
		action_started.emit(self, "hoof")

func request_dodge(direction = Vector3.ZERO) -> bool:
	if duel_can_cancel_normal_recovery() and stamina >= 24.0 and (not mounted or mount_charge_cooldown <= 0.0):
		_idle()
	var accepted = super.request_dodge(direction)
	if accepted and not mounted: begin_duel_aerial(2.3)
	return accepted
