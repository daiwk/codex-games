extends "res://scripts/fighter.gd"
class_name RPGActor

# The open world shares the duel's animation, grip, cavalry and contact logic.
# Only navigation, equipment and persistent RPG stats differ here.
const RPG_WEAPONS = ["serpent_spear", "guandao", "halberd"]
const RPG_LENGTHS = {"serpent_spear": 3.05, "guandao": 2.85, "halberd": 3.15}
const LOCK_FORWARD_SPEED = 4.8
const LOCK_REVERSE_SPEED = 2.2
const LOCK_ORBIT_SPEED = 2.6
const CUT_CLIPS = {
	"Attack1": "RPGSlash", "Attack2": "RPGChop", "Attack3": "RPGSpin", "Heavy": "RPGChop",
	"CrescentSweep": "RPGSpin", "CrescentStep": "CloudStep", "CrescentCounter": "RPGChop",
	"CrescentCharge": "Idle", "CrescentFinish": "RPGFinish",
	"HalberdSweep": "RPGSpin", "HalberdThrust": "DragonThrust",
	"HalberdCharge": "Idle", "HalberdFinish": "RPGFinish",
}

var max_hp: float = 160.0
var attack_multiplier: float = 1.0
var defense: float = 0.0
# The RPG controller supplies a world-space radial/tangent input and explicitly
# owns opponent selection. The duel and free riding never enable this flag.
var lock_facing = false
var lock_forward_speed = 0.0
var _lock_move_velocity = Vector3.ZERO
var _lock_motion_active = false

func _init() -> void:
	movement_radius = 155.0
	hp = max_hp

func apply_stats(health: float, damage_scale: float, armor: float, heal: bool = false) -> void:
	max_hp = maxf(1.0, health)
	attack_multiplier = maxf(0.0, damage_scale)
	defense = maxf(0.0, armor)
	hp = max_hp if heal else clampf(hp, 0.0, max_hp)

func reset_fighter() -> void:
	super.reset_fighter()
	hp = max_hp
	_lock_move_velocity = Vector3.ZERO
	_lock_motion_active = false
	lock_forward_speed = 0.0

func resolve_equipped_weapon(selected: String) -> String:
	if character_id == "zhaoyun" and selected in RPG_WEAPONS:
		return selected
	return super.resolve_equipped_weapon(selected)

func _load_two_handed_weapon() -> void:
	_update_equipment_length()
	super._load_two_handed_weapon()

func _update_equipment_length() -> void:
	if character_id == "zhaoyun":
		grip_config = grip_config.duplicate(true)
		grip_config["weapon_length"] = float(RPG_LENGTHS.get(weapon_id, 3.05))

# Returns false without changes for unsupported gear or a busy/dead actor.
# Before entering the tree, selecting a weapon is enough; visuals load in ready.
func equip_weapon(id: String) -> bool:
	if not Roster.WEAPONS.has(id) or resolve_equipped_weapon(id) != id:
		return false
	if not is_node_ready():
		weapon_id = id
		return true
	if id == weapon_id:
		return true
	if not is_two_handed() or hp <= 0.0 or state not in ["idle", "move", "block"]:
		return false
	var scene = load(Roster.WEAPONS[id].path) as PackedScene
	if scene == null:
		return false
	var replacement = scene.instantiate() as Node3D
	var previous_weapon = weapon_mesh
	weapon_id = id
	_update_equipment_length()
	weapon_mesh = replacement
	weapon_mesh.name = "TwoHandPolearm"
	var length_m = float(grip_config.weapon_length)
	weapon_mesh.scale = Vector3.ONE * length_m
	weapon_mesh.position.y = -length_m * float(grip_config.grip_fraction)
	grip.add_child(weapon_mesh)
	grip.remove_child(previous_weapon)
	previous_weapon.queue_free()
	_tune_materials(weapon_mesh)
	grip_roll_ready = false
	if is_instance_valid(thrust_contact):
		thrust_contact.pose_cached = false
	_idle()
	_update_two_hand_grip(0.0, true)
	previous_tip = blade_tip()
	return true

func play_clip(clip: String, blend = 0.12, duration = 0.0) -> void:
	if character_id == "zhaoyun" and weapon_id in ["guandao", "halberd"]:
		clip = String(CUT_CLIPS.get(clip, clip))
	super.play_clip(clip, blend, duration)

func skill_profile(id: String) -> Dictionary:
	if not mounted and character_id == "zhaoyun" and weapon_id in ["guandao", "halberd"]:
		var owner_id = "guanyu" if weapon_id == "guandao" else "lubu"
		return RoleSkills.for_character(owner_id).get(id, {})
	return super.skill_profile(id)

func receive_strike(attacker: DuelFighter, data: Dictionary) -> String:
	# Resolve stats once, at the receiver, for normals, skills and guard chip.
	# World hit resolution should still add its physical cavalry bonus first.
	var resolved = data.duplicate(true)
	var damage_scale = attacker.attack_multiplier if attacker is RPGActor else 1.0
	var mitigation = 100.0 / (100.0 + defense)
	resolved["damage"] = maxf(0.0, float(data.get("damage", 0.0))) * damage_scale * mitigation
	if data.has("guard_chip"):
		resolved["guard_chip"] = maxf(0.0, float(data.guard_chip)) * damage_scale * mitigation
	return super.receive_strike(attacker, resolved)

func _physics_process(delta: float) -> void:
	if is_instance_valid(opponent) and opponent.hp <= 0.0:
		opponent = null
	if not is_instance_valid(opponent) and is_instance_valid(thrust_contact):
		# The duel always has a target; exploration may have none. Discard the
		# previous target's transient palm cache so the free gait keeps animating.
		thrust_contact.pose_cached = false
	if not _has_lock_target() and _lock_motion_active:
		# A backwards/sideways locked step must not turn into a forward surge
		# when the controller releases its target.
		mount_speed = maxf(0.0, velocity.dot(forward()))
		_lock_move_velocity = Vector3.ZERO
		_lock_motion_active = false
		lock_forward_speed = 0.0
	var before_move = position
	super._physics_process(delta)
	if _lock_motion_active and enabled and delta > 0.0:
		# DuelFighter measures only forward travel to stop a blocked horse. In
		# lock mode sideways/reverse travel is deliberate, so use actual planar
		# displacement for gait while keeping collision stops authoritative.
		var travelled = (position - before_move) / delta
		travelled.y = 0.0
		mount_speed = minf(_lock_move_velocity.length(), travelled.length())
		_lock_move_velocity = travelled.limit_length(_lock_move_velocity.length())
		lock_forward_speed = _lock_move_velocity.dot(forward())

func _has_lock_target() -> bool:
	return mounted and lock_facing and hp > 0.0 and is_instance_valid(opponent) and opponent != self and opponent.hp > 0.0

func _update_facing(delta: float) -> void:
	if _has_lock_target() and state in ["idle", "move", "block"]:
		turning_in_place = false
		turn_speed = 0.0
		_update_mount_facing(delta)
		return
	if contact_latched or state in ["attack", "skill", "ultimate"]:
		super._update_facing(delta)
		return
	turning_in_place = false
	turn_speed = 0.0
	mount_turn_rate = 0.0
	if hp <= 0.0 or state in ["dodge", "hit", "stagger", "dead"] or input_move.length_squared() <= 0.01:
		return
	if mounted:
		_update_mount_facing(delta)
		return
	var error = angle_difference(rotation.y, atan2(input_move.x, input_move.z))
	rotation.y += clampf(error, -7.0 * delta, 7.0 * delta)

func _update_mount_facing(delta: float) -> void:
	if not _has_lock_target():
		super._update_mount_facing(delta)
		return
	mount_turn_rate = 0.0
	if state in ["hit", "stagger", "dead", "dodge"]:
		return
	# Keep the existing physical thrust's committed contact window. Outside
	# that window the target, rather than an orbit tangent, determines heading.
	if state == "attack" and action_time >= float(attack.active.x) - 0.08 and action_time <= float(attack.active.y):
		return
	var toward = opponent.global_position - global_position
	toward.y = 0.0
	if toward.length_squared() < 0.01:
		return
	var error = angle_difference(rotation.y, atan2(toward.x, toward.z))
	var step = clampf(error * 9.0 * delta, -4.0 * delta, 4.0 * delta)
	rotation.y += step
	mount_turn_rate = step / maxf(delta, 0.001)

func _update_mount_motion(delta: float) -> void:
	if not _has_lock_target() or state not in ["idle", "move", "block"]:
		_lock_motion_active = false
		lock_forward_speed = 0.0
		super._update_mount_motion(delta)
		return
	if not _lock_motion_active:
		_lock_move_velocity = Vector3(velocity.x, 0.0, velocity.z)
	_lock_motion_active = true
	var toward = opponent.global_position - global_position
	toward.y = 0.0
	toward = toward.normalized() if toward.length_squared() > 0.01 else forward()
	var tangent = Vector3(toward.z, 0.0, -toward.x)
	var movement = input_move.slide(Vector3.UP).limit_length()
	var radial = movement.dot(toward)
	var orbit = movement.dot(tangent)
	# Space from a standstill chooses the locked target as its forward route.
	# Releasing W during that charge keeps it moving; steering away still brakes.
	if mount_charge_time > 0.0 and movement.length_squared() <= 0.01:
		radial = 1.0
	# A charging horse may accelerate into the target; reverse and side steps
	# use a measured walk instead of sliding an 8 m/s gallop around its body.
	if mount_charge_time > 0.0 and (radial < 0.45 or absf(orbit) > 0.45):
		mount_charge_time = 0.0
	var forward_speed = 8.2 if mount_charge_time > 0.0 else LOCK_FORWARD_SPEED
	var desired = toward * radial * (forward_speed if radial >= 0.0 else LOCK_REVERSE_SPEED) + tangent * orbit * LOCK_ORBIT_SPEED
	if state == "block":
		desired = desired.limit_length(1.2)
	var acceleration = 11.0 if mount_charge_time > 0.0 else (6.0 if desired.length() > _lock_move_velocity.length() else 10.0)
	_lock_move_velocity = _lock_move_velocity.move_toward(desired, delta * acceleration)
	velocity.x = _lock_move_velocity.x
	velocity.z = _lock_move_velocity.z
	mount_speed = _lock_move_velocity.length()
	footstep_clock += delta * mount_speed
	if mount_speed > 0.4 and footstep_clock > 1.25:
		footstep_clock = 0.0
		action_started.emit(self, "hoof")

func _aim_attack() -> void:
	if (mounted and not _has_lock_target()) or state not in ["idle", "move", "block"] or not is_instance_valid(opponent) or opponent.hp <= 0.0:
		return
	var direction = opponent.global_position - global_position
	if Vector2(direction.x, direction.z).length_squared() > 0.01:
		rotation.y = atan2(direction.x, direction.z)

func request_dodge(direction = Vector3.ZERO) -> bool:
	if _has_lock_target():
		var movement = input_move.slide(Vector3.UP).limit_length()
		if movement.length_squared() > 0.01:
			var toward = (opponent.global_position - global_position).slide(Vector3.UP).normalized()
			var tangent = Vector3(toward.z, 0.0, -toward.x)
			# Reject before the shared method spends stamina or starts cooldown.
			if movement.dot(toward) < 0.45 or absf(movement.dot(tangent)) > 0.45:
				return false
	return super.request_dodge(direction)

func request_light() -> bool:
	_aim_attack()
	return super.request_light()

func request_heavy() -> bool:
	_aim_attack()
	return super.request_heavy()

func request_skill(id: String) -> bool:
	_aim_attack()
	return super.request_skill(id)

func request_ultimate() -> bool:
	_aim_attack()
	return super.request_ultimate()
