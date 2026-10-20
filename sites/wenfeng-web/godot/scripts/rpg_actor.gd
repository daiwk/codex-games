extends "res://scripts/fighter.gd"
class_name RPGActor

# The open world shares the duel's animation, grip, cavalry and contact logic.
# Only navigation, equipment and persistent RPG stats differ here.
const RPG_WEAPONS = ["serpent_spear", "guandao", "halberd"]
const RPG_LENGTHS = {"serpent_spear": 3.05, "guandao": 2.85, "halberd": 3.15}
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
	super._physics_process(delta)

func _update_facing(delta: float) -> void:
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

func _aim_attack() -> void:
	if mounted or state not in ["idle", "move", "block"] or not is_instance_valid(opponent) or opponent.hp <= 0.0:
		return
	var direction = opponent.global_position - global_position
	if Vector2(direction.x, direction.z).length_squared() > 0.01:
		rotation.y = atan2(direction.x, direction.z)

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
