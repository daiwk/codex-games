extends CharacterBody3D
class_name DuelFighter
const RoleSkills = preload("res://scripts/skill_profiles.gd")
const Roster = preload("res://scripts/roster.gd")

signal strike_requested(fighter, attack)
signal impact_received(fighter, outcome, position)
signal action_started(fighter, action)
signal skill_triggered(fighter, skill, stage)

const ATTACKS = [
	{"clip": "Attack1", "duration": 0.80, "active": Vector2(0.13, 0.30), "damage": 15.0, "cost": 13.0, "reach": 2.12, "lunge": 1.9, "heavy": false},
	{"clip": "Attack2", "duration": 0.85, "active": Vector2(0.13, 0.32), "damage": 17.0, "cost": 15.0, "reach": 2.20, "lunge": 1.7, "heavy": false},
	{"clip": "Attack3", "duration": 1.05, "active": Vector2(0.27, 0.55), "damage": 23.0, "cost": 19.0, "reach": 2.30, "lunge": 2.0, "heavy": false},
]
const HEAVY = {"clip": "Heavy", "duration": 1.14, "active": Vector2(0.29, 0.53), "damage": 31.0, "cost": 29.0, "reach": 2.35, "lunge": 2.1, "heavy": true}
const LOOP_CLIPS = ["Idle", "Walk", "WalkBack", "StrafeLeft", "StrafeRight", "Run", "TurnLeft", "TurnRight"]

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
var grip_config: Dictionary = {}
var right_hand_index = -1
var left_hand_index = -1
var grip_roll_ready = false

func _ready() -> void:
	collision_layer = 2
	collision_mask = 3
	var shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.80
	shape.shape = capsule
	shape.position.y = 0.91
	add_child(shape)
	floor_snap_length = 0.2
	_load_visuals()
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
	grip_config = config
	weapon_id = Roster.resolve_weapon(character_id, weapon_id)
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
	weapon_mesh = (load("res://onehand_%s.glb" % weapon_id) as PackedScene).instantiate()
	weapon_mesh.name = "OneHandWeapon"
	weapon_mesh.scale = Vector3.ONE * float(config.mesh_scale)
	weapon_mesh.position.y = float(config.mesh_grip_y)
	grip.add_child(weapon_mesh)
	# Many small armor surfaces use the originals' baked normal maps. Keep them
	# on the authored meshes; remove imported shadow lights/cameras if any.
	_tune_materials(model)

func is_two_handed() -> bool:
	return character_id in ["guanyu", "zhangfei", "lubu"]

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
	var wrist = skeleton.global_basis * skeleton.get_bone_global_pose(right_hand_index).basis
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
	if is_two_handed():
		_update_two_hand_grip(delta)

func is_thrust_weapon() -> bool:
	return bool(Roster.WEAPONS[weapon_id].get("thrust_only", false))

func basic_reach() -> float:
	return float(Roster.WEAPONS[weapon_id].reach)

func preferred_distance() -> float:
	return float(Roster.character(character_id).distance)

func _light_attacks() -> Array:
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

func _tune_materials(node: Node) -> void:
	if node is MeshInstance3D:
		for i in node.get_surface_override_material_count():
			var mat = node.get_active_material(i)
			if mat is StandardMaterial3D:
				mat.roughness = maxf(mat.roughness, 0.52)
	for child in node.get_children():
		_tune_materials(child)

func _find_node(node: Node, kind: String) -> Node:
	if node.is_class(kind):
		return node
	for child in node.get_children():
		var result = _find_node(child, kind)
		if result != null:
			return result
	return null

func reset_fighter() -> void:
	_cancel_skill()
	hp = 120.0
	stamina = 100.0
	state = "idle"
	action_time = 0.0
	combo = 0
	combo_buffered = false
	hit_landed = false
	attack = {}
	regen_delay = 0.0
	wants_block = false
	input_move = Vector3.ZERO
	velocity = Vector3.ZERO
	turn_speed = 0.0
	turning_in_place = false
	grip_roll_ready = false
	energy = 35.0
	cooldowns = {"rush": 0.0, "counter": 0.0}
	current_clip = ""
	play_clip("Idle", 0.0)

func play_clip(clip: String, blend = 0.12, duration = 0.0) -> void:
	if not animation_names.has(clip):
		push_error("Missing required animation: " + clip)
		return
	var key = animation_names[clip]
	animation_player.speed_scale = 1.0
	var speed = 1.0
	if duration > 0.0:
		speed = animation_player.get_animation(key).length / duration
	animation_player.play(key, blend, speed)
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

func request_heavy() -> bool:
	var required_cost = 34.0 if is_two_handed() else float(HEAVY.cost)
	if not enabled or state not in ["idle", "move", "block"] or hp <= 0.0 or stamina < required_cost:
		return false
	combo = 0
	attack = HEAVY.duplicate()
	if is_two_handed():
		attack.merge({"duration": 1.48, "active": Vector2(0.48, 0.83), "damage": 38.0, "cost": 34.0, "reach": basic_reach() + 0.12, "lunge": 1.8}, true)
	if is_thrust_weapon():
		attack.merge({"duration": 1.40, "active": Vector2(0.29, 0.60), "shape": "line", "half_width": 0.62}, true)
	_apply_weapon_stats()
	_enter_attack()
	return true

func ultimate_name() -> String:
	return skill_name("ultimate")

func skill_profile(id: String) -> Dictionary:
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
	action_time = 0.0
	combo_buffered = false
	hit_landed = false
	turning_in_place = false
	state = "skill"
	attack = profile.duplicate(true)
	attack["skill"] = id
	action_duration = profile.duration
	if profile.kind == "evade":
		dodge_direction = input_move.normalized() if input_move.length() > 0.1 else -forward()
		dodge_direction.y = 0.0
	play_clip(profile.clip, 0.08, 0.40 if profile.kind == "evade" else action_duration)
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
	action_time = 0.0
	action_duration = float(skill_profile("ultimate").duration)
	combo_buffered = false
	hit_landed = false
	attack = {}
	turning_in_place = false
	velocity.x = 0.0
	velocity.z = 0.0
	play_clip(skill_profile("ultimate").charge_clip, 0.11, ultimate_windup())
	skill_triggered.emit(self, "ultimate", "start")
	return true

func _cancel_skill() -> void:
	if skill_id != "":
		skill_triggered.emit(self, skill_id, "cancel")
	skill_id = ""
	skill_stage = ""
	skill_hit_index = -1
	skill_strike_announced = false
	skill_animation_index = -1
	skill_animation_started = false

func _begin_attack(index: int) -> bool:
	var options = _light_attacks()
	if stamina < options[index].cost:
		return false
	combo = index
	attack = options[index].duplicate()
	_apply_weapon_stats()
	_enter_attack()
	return true

func _apply_weapon_stats() -> void:
	if is_two_handed():
		return
	# The saber trades a little reach for damage; the straight sword recovers
	# faster. The two use the same genuine single-hand animation set.
	if weapon_id == "saber":
		attack.damage *= 1.08
		attack.duration *= 1.04
		attack.reach -= 0.10
	else:
		attack.duration *= 0.96

func _enter_attack() -> void:
	stamina -= float(attack.cost)
	regen_delay = 0.75
	state = "attack"
	action_time = 0.0
	action_duration = attack.duration
	combo_buffered = false
	hit_landed = false
	play_clip(attack.clip, 0.075, action_duration)
	previous_tip = blade_tip()
	action_started.emit(self, "heavy" if attack.heavy else "light")

func request_dodge(direction = Vector3.ZERO) -> bool:
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
	return weapon_mesh.to_global(Vector3(0, 98, 0)) if is_instance_valid(weapon_mesh) else global_position + Vector3.UP

func blade_base() -> Vector3:
	if is_two_handed() and is_instance_valid(weapon_mesh):
		return weapon_mesh.to_global(Vector3(0, float(Roster.WEAPONS[weapon_id].blade_start), 0))
	return weapon_mesh.to_global(Vector3(0, 22, 0)) if is_instance_valid(weapon_mesh) else global_position + Vector3.UP

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
	if character_id != "machao":
		return false
	if state == "ultimate":
		return action_time >= 0.55
	return state == "skill" and attack.get("kind", "") == "sweep" and action_time >= 0.18 and action_time <= 0.70 and not data.heavy

func receive_strike(attacker: DuelFighter, data: Dictionary) -> String:
	if hp <= 0.0:
		return "dead"
	var impact = global_position + Vector3.UP * 1.05
	if is_invulnerable():
		dodged_hits += 1
		gain_energy(9.0)
		impact_received.emit(self, "evade", impact)
		return "evade"
	var toward_attacker = attacker.global_position - global_position
	toward_attacker.y = 0.0
	var front_guard = toward_attacker.normalized().dot(forward()) > 0.1
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
		return
	action_time += delta
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
			if action_time >= window.x and action_time <= window.y and not hit_landed:
				strike_requested.emit(self, attack)
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
	velocity.y -= 20.0 * delta
	if is_on_floor() and velocity.y < 0:
		velocity.y = -0.2
	move_and_slide()
	var flat = Vector2(position.x, position.z)
	if flat.length() > 7.6:
		flat = flat.normalized() * 7.6
		position.x = flat.x
		position.z = flat.y
	previous_tip = blade_tip()

func _update_facing(delta: float) -> void:
	var agile_step = state == "skill" and attack.get("kind", "") == "evade"
	var chasing = state == "ultimate" and skill_profile("ultimate").kind == "chase"
	var committed = (state in ["attack", "skill"] and action_time >= (0.32 if agile_step else 0.10))
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
	var limit = 7.2 if chasing else (5.5 if agile_step else (3.6 if moving else 2.8))
	var wanted = clampf(error * (14.0 if chasing else 7.0), -limit, limit)
	turn_speed = move_toward(turn_speed, wanted, delta * (60.0 if chasing else 24.0 if agile_step else 14.0))
	var step = clampf(turn_speed * delta, -absf(error), absf(error))
	rotation.y += step

func _update_locomotion(delta: float) -> void:
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
		if local.z > 0.65:
			clip = "Run"
			gait_rate = 1.38
		elif local.z < -0.65:
			clip = "WalkBack"
			speed = 1.65
			gait_rate = 1.65
		else:
			clip = "StrafeLeft" if local.x > 0 else "StrafeRight"
			speed = 1.65
			gait_rate = 1.65
		footstep_clock += delta * movement.length()
		if footstep_clock > (0.34 if clip == "Run" else 0.40):
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
		play_clip(clip, 0.16)
	animation_player.speed_scale = gait_rate if turning_in_place else (gait_rate * movement.length() if clip != "Idle" else 1.0)

func _idle() -> void:
	_cancel_skill()
	state = "idle"
	action_time = 0.0
	combo_buffered = false
	combo = 0
	play_clip("Idle", 0.13)

func _update_skill(delta: float) -> void:
	var window: Vector2 = attack.active
	var kind: String = attack.kind
	if kind == "evade" and action_time >= float(attack.strike_start) and not skill_animation_started:
		skill_animation_started = true
		play_clip(attack.strike_clip, 0.07, 0.45)
	if action_time >= window.x and not skill_strike_announced:
		skill_strike_announced = true
		skill_stage = "active"
		skill_triggered.emit(self, skill_id, "release")
	if action_time >= window.x and action_time <= window.y and not hit_landed:
		strike_requested.emit(self, attack)
		if state != "skill":
			return
	var speed = 0.0
	var direction = forward()
	if kind == "thrust" and action_time > float(attack.dash_from) and action_time < float(attack.dash_to):
		speed = float(attack.lunge)
	elif kind == "sweep" and action_time > 0.16 and action_time < window.y:
		speed = float(attack.lunge)
	elif kind == "evade" and action_time > 0.04 and action_time < 0.27:
		speed = 6.0
		direction = dodge_direction
	if kind != "evade" and is_instance_valid(opponent) and global_position.distance_to(opponent.global_position) < 1.12:
		speed = 0.0
	velocity.x = move_toward(velocity.x, direction.x * speed, delta * 75.0)
	velocity.z = move_toward(velocity.z, direction.z * speed, delta * 75.0)
	if action_time > window.y:
		skill_stage = "recovery"
	if action_time >= action_duration:
		_idle()

func _update_ultimate() -> void:
	var profile = skill_profile("ultimate")
	var hits: Array = profile.hits
	var chase = profile.kind == "chase"
	if action_time >= float(profile.windup) and skill_stage == "windup":
		skill_stage = "active"
		if not chase:
			play_clip(profile.release_clip, 0.055, float(profile.release_duration))
		skill_triggered.emit(self, "ultimate", "release")
	var lunging = false
	for index in hits.size():
		var data: Dictionary = hits[index]
		var window: Vector2 = data.active
		if chase and action_time >= float(data.start) and skill_animation_index < index:
			skill_animation_index = index
			play_clip(data.clip, 0.045, float(data.clip_duration))
		if chase and action_time >= window.x - 0.10 and action_time <= window.x + 0.025:
			lunging = true
		if action_time >= window.x and action_time <= window.y:
			if skill_hit_index != index:
				skill_hit_index = index
				hit_landed = false
				attack = data.duplicate()
				attack.merge({"heavy": true, "unparryable": true, "skill": "ultimate", "wave": true})
				if chase:
					attack.merge({"shape": "line", "half_width": float(profile.get("half_width", 0.55)), "reach": float(profile.get("reach", 3.1)), "guard_cost": float(profile.get("guard_cost", 16.0)), "knockback": 0.35, "hit_stun": 0.20})
				skill_triggered.emit(self, "ultimate", "finish" if index == hits.size() - 1 else "strike")
			if not hit_landed:
				strike_requested.emit(self, attack)
				if state != "ultimate":
					return
	var speed = 6.0 if lunging else 0.0
	if is_instance_valid(opponent) and global_position.distance_to(opponent.global_position) < 1.18:
		speed = 0.0
	velocity.x = forward().x * speed
	velocity.z = forward().z * speed
	if action_time > hits[-1].active.y:
		skill_stage = "recovery"
	if action_time >= action_duration:
		_idle()
