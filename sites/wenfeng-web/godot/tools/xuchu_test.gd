extends SceneTree

# Exercise imported character/weapon scenes, real action clocks and the normal
# strike resolver. Defenders are stationary so knockback cannot hide extra hits.
const Roster = preload("res://scripts/roster.gd")
const WEAPONS = ["xuchu_saber", "saber", "sword"]
const EXCLUSIVE_WEAPONS = {
	"zhaoyun": "zhaoyun_spear", "machao": "machao_spear",
	"guanyu": "guandao", "zhangfei": "serpent_spear", "lubu": "halberd",
}
const GRIP_Y = 0.075 / 0.0058

var game: Node3D
var checks: Array = []
var failures: Array = []
var impacts: Array = []
var skill_identity: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, condition: bool, detail = "") -> void:
	checks.append({"name": label, "passed": condition, "detail": str(detail)})
	if not condition:
		failures.append(label)
	print(("PASS " if condition else "FAIL ") + label + (": " + str(detail) if str(detail) != "" else ""))

func frames(count: int) -> void:
	for _i in count:
		await physics_frame

func seconds(duration: float) -> void:
	var elapsed = 0.0
	while elapsed < duration - 0.00001:
		await physics_frame
		elapsed += game.player.get_physics_process_delta_time()

func until_action_time(moment: float) -> void:
	var ticks = 0
	while game.player.state in ["attack", "skill", "ultimate"] and game.player.action_time < moment and ticks < 2400:
		await physics_frame
		ticks += 1
	if ticks >= 2400:
		check("Xu action clock advances", false, moment)

func _observe_impact(_fighter, outcome: String, _at: Vector3) -> void:
	impacts.append(outcome)

func select_weapon(id: String) -> void:
	game.return_to_menu()
	game.select_character("xuchu")
	game.select_opponent("zhaoyun")
	game.select_weapon(id)
	await frames(3)
	if not game.enemy.impact_received.is_connected(_observe_impact):
		game.enemy.impact_received.connect(_observe_impact)
	check("Xu selects " + id, game.player.character_id == "xuchu" and game.player.weapon_id == id)

func reset(gap = 1.25, blocking = false) -> void:
	paused = false
	game.paused = false
	game.start_match()
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	game.phase = "fight"
	game.round_time = 90.0
	game.ai_enabled = false
	game.hit_stop_until = 0
	game.skill_fx.clear()
	impacts.clear()
	for fighter in [game.player, game.enemy]:
		fighter.reset_fighter()
		fighter.damage_dealt = 0.0
		fighter.parries = 0
		fighter.blocked_hits = 0
		fighter.dodged_hits = 0
	game.player.set_physics_process(true)
	game.player.enabled = true
	game.enemy.enabled = false
	game.enemy.set_physics_process(false)
	game.player.position = Vector3(0, 0.015, 0)
	game.player.rotation.y = 0.0
	game.enemy.position = Vector3(0, 0.015, gap)
	game.enemy.rotation.y = PI
	if blocking:
		game.enemy.state = "block"
		game.enemy.wants_block = true
		game.enemy.action_time = 0.5

func find_bone_ending(suffix: String) -> int:
	for index in game.player.skeleton.get_bone_count():
		if game.player.skeleton.get_bone_name(index).ends_with(suffix):
			return index
	return -1

func grip_checks(weapon: String) -> void:
	var fighter = game.player
	check(weapon + " uses a right-hand bone attachment", not fighter.is_two_handed() and fighter.grip.get_parent() is BoneAttachment3D and fighter.grip.get_parent().bone_name.ends_with("RightHand"))
	check(weapon + " imports its actual weapon scene", is_instance_valid(fighter.weapon_mesh) and fighter.weapon_mesh.scene_file_path == Roster.WEAPONS[weapon].path)
	var hand_index = find_bone_ending("RightHand")
	var knuckle_index = find_bone_ending("RightHandMiddle1")
	check(weapon + " has right-hand and knuckle bones", hand_index >= 0 and knuckle_index >= 0)
	if hand_index < 0 or knuckle_index < 0:
		return
	fighter.set_physics_process(false)
	for clip in ["Idle", "Attack1", "Attack2", "Attack3", "Heavy", "Block", "Walk", "Run", "Dodge", "TigerCleave", "BruteRoar", "BruteCharge", "BruteFinish"]:
		check(weapon + " has " + clip, fighter.animation_names.has(clip))
		if not fighter.animation_names.has(clip):
			continue
		fighter.play_clip(clip, 0.0)
		fighter.animation_player.advance(0)
		var animation: Animation = fighter.animation_player.get_animation(fighter.animation_names[clip])
		fighter.animation_player.seek(animation.length * 0.48, true)
		fighter.animation_player.pause()
		fighter.skeleton.force_update_all_bone_transforms()
		await frames(3)
		var hand: Transform3D = fighter.skeleton.global_transform * fighter.skeleton.get_bone_global_pose(hand_index)
		var knuckle: Transform3D = fighter.skeleton.global_transform * fighter.skeleton.get_bone_global_pose(knuckle_index)
		var palm: Vector3 = hand.origin.lerp(knuckle.origin, 0.85)
		var handle: Vector3 = fighter.weapon_mesh.to_global(Vector3(0, GRIP_Y, 0))
		check(weapon + " " + clip + " handle stays in right palm", handle.distance_to(palm) < 0.025, handle.distance_to(palm))
	fighter.set_physics_process(true)

func resource_checks(weapon: String) -> void:
	reset()
	check(weapon + " starts with normal round resources", game.player.hp == 120.0 and game.player.stamina == 100.0 and game.player.energy == 35.0)
	check(weapon + " retains Xu skill names and descriptions", game.player.skill_name("rush") == skill_identity.rush and game.player.skill_name("counter") == skill_identity.counter and game.player.ultimate_name() == skill_identity.ultimate and game.player.skill_description("rush") == skill_identity.rush_description)
	check(weapon + " retains Xu skill costs and cooldowns", game.player.skill_cost("rush") == 30.0 and game.player.skill_cost("counter") == 27.0 and game.player.skill_cooldown("rush") == 6.4 and game.player.skill_cooldown("counter") == 9.5)
	for data in [["rush", 29.9], ["counter", 26.9]]:
		game.player.stamina = data[1]
		check(weapon + " " + data[0] + " rejects insufficient stamina", not game.player.request_skill(data[0]))
	game.player.stamina = 31.9
	check(weapon + " heavy requires its full 32 stamina", not game.player.request_heavy())
	game.player.energy = 99.0
	check(weapon + " U requires full energy", not game.player.request_ultimate())
	game.player.enabled = false
	game.player.energy = 100.0
	game.player.stamina = 100.0
	check(weapon + " disabled fighter cannot start actions", not game.player.request_light() and not game.player.request_heavy() and not game.player.request_skill("rush") and not game.player.request_ultimate())

func basic_checks(weapon: String) -> void:
	reset()
	check(weapon + " light chain starts", game.player.request_light())
	check(weapon + " first light spends 16 stamina", is_equal_approx(game.player.stamina, 84.0))
	var first_window: Vector2 = game.player.attack.active
	await until_action_time(first_window.x - 0.03)
	check(weapon + " light cannot hit before its swing", game.enemy.hp == 120.0)
	var seen: Dictionary = {}
	var expected_damage = 0.0
	var minimum_stamina = 100.0
	for _tick in 480:
		if game.player.state == "attack":
			var index: int = game.player.combo
			if not seen.has(index):
				seen[index] = game.player.current_clip
				expected_damage += float(game.player.attack.damage)
			minimum_stamina = minf(minimum_stamina, game.player.stamina)
			game.player.request_light()
		elif seen.has(2):
			break
		await physics_frame
	check(weapon + " buffered chain reaches all three authored cuts", seen.size() == 3 and seen.get(0) == "Attack1" and seen.get(1) == "Attack2" and seen.get(2) == "Attack3", seen)
	check(weapon + " three cuts spend the unchanged 58 stamina", is_equal_approx(minimum_stamina, 42.0), minimum_stamina)
	check(weapon + " all three cuts land real damage once each", impacts.size() == 3 and is_equal_approx(game.enemy.hp, 120.0 - expected_damage) and expected_damage > 50.0, {"hits": impacts, "damage": game.player.damage_dealt, "expected": expected_damage})
	check(weapon + " chain recovers to idle", game.player.state == "idle")
	reset()
	game.player.stamina = 32.0
	check(weapon + " heavy starts at exact cost", game.player.request_heavy())
	check(weapon + " heavy spends 32 stamina", is_equal_approx(game.player.stamina, 0.0))
	var window: Vector2 = game.player.attack.active
	var damage: float = game.player.attack.damage
	var duration: float = game.player.action_duration
	await until_action_time(window.x - 0.03)
	check(weapon + " heavy telegraph cannot hit early", game.enemy.hp == 120.0)
	await until_action_time(window.y + 0.04)
	check(weapon + " heavy lands its weapon-adjusted damage", is_equal_approx(game.enemy.hp, 120.0 - damage) and impacts.size() == 1 and damage >= 31.0, game.player.damage_dealt)
	await seconds(duration - window.y + 0.10)
	check(weapon + " heavy recovers without repeated damage", game.player.state == "idle" and impacts.size() == 1)

func skill_checks(weapon: String) -> void:
	for id in ["rush", "counter", "ultimate"]:
		reset(1.6)
		var profile: Dictionary = game.player.skill_profile(id)
		var expected_damage: float = {"rush": 29.0, "counter": 8.0, "ultimate": 60.0}[id]
		var window: Vector2 = profile.hits[0].active if id == "ultimate" else profile.active
		if id == "ultimate":
			game.player.energy = 100.0
			check(weapon + " U starts", game.player.request_ultimate())
			check(weapon + " U spends all energy", game.player.energy == 0.0)
		else:
			check(weapon + " " + id + " starts", game.player.request_skill(id))
			check(weapon + " " + id + " spends fixed role cost and starts cooldown", game.player.stamina == 100.0 - profile.cost and game.player.cooldowns[id] == profile.cooldown)
		await until_action_time(window.x - 0.03)
		check(weapon + " " + id + " cannot damage before its active window", game.enemy.hp == 120.0)
		await until_action_time(window.y + 0.04)
		check(weapon + " " + id + " deals fixed Xu damage", is_equal_approx(game.enemy.hp, 120.0 - expected_damage) and impacts.size() == 1, {"hp": game.enemy.hp, "contacts": impacts})
		await seconds(profile.duration - window.y + 0.10)
		check(weapon + " " + id + " recovers without repeat contact", game.player.state == "idle" and impacts.size() == 1)
		if id != "ultimate":
			check(weapon + " " + id + " cannot repeat while cooling down", not game.player.request_skill(id))
		else:
			check(weapon + " U damage does not refill its energy", game.player.energy == 0.0)
	for id in ["counter", "ultimate"]:
		reset(1.6, true)
		var profile: Dictionary = game.player.skill_profile(id)
		var window: Vector2 = profile.hits[0].active if id == "ultimate" else profile.active
		if id == "ultimate":
			game.player.energy = 100.0
			game.player.request_ultimate()
		else:
			game.player.request_skill(id)
		await until_action_time(window.y + 0.04)
		check(weapon + " " + id + " breaks guard with role-specific damage", game.enemy.state == "stagger" and game.enemy.parries == 0 and game.enemy.blocked_hits == 1 and is_equal_approx(game.enemy.hp, 108.0 if id == "ultimate" else 120.0) and is_equal_approx(game.enemy.stamina, 0.0 if id == "ultimate" else 58.0), {"hp": game.enemy.hp, "guard": game.enemy.stamina})
	reset(1.6)
	game.player.energy = 100.0
	var duration: float = game.player.skill_profile("ultimate").duration
	game.player.request_ultimate()
	await until_action_time(0.20)
	var outcome: String = game.player.receive_strike(game.enemy, DuelFighter.HEAVY)
	check(weapon + " heavy interrupts U startup", outcome == "hit" and game.player.state == "hit" and game.player.skill_id == "" and game.player.hp == 89.0)
	await seconds(duration + 0.10)
	check(weapon + " interrupted U produces no later damage", game.enemy.hp == 120.0 and impacts.is_empty())

func ai_check() -> void:
	game.return_to_menu()
	game.select_character("zhaoyun")
	game.select_opponent("xuchu")
	await frames(3)
	game.start_match()
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	game.phase = "fight"
	game.ai_enabled = true
	game.ai_think = 0.0
	game.ai_cooldown = 0.0
	game.player.enabled = false
	game.player.set_physics_process(false)
	game.enemy.enabled = true
	game.enemy.set_physics_process(true)
	game.player.position = Vector3(0, 0.015, 0)
	game.player.rotation.y = 0.0
	game.enemy.position = Vector3(0, 0.015, 4.5)
	game.enemy.rotation.y = PI
	var minimum_gap = 4.5
	for _tick in 600:
		await physics_frame
		minimum_gap = minf(minimum_gap, game.player.position.distance_to(game.enemy.position))
		if game.player.hp < 120.0:
			break
	check("Xu AI equips its own saber", game.enemy.character_id == "xuchu" and game.enemy.weapon_id == "xuchu_saber")
	check("Xu AI approaches and lands a real attack", minimum_gap < 3.0 and game.player.hp < 120.0, {"minimum_gap": minimum_gap, "hp": game.player.hp})

func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(5)
	game.testing = true
	game.ai_enabled = false
	game.fx.muted = true
	check("Xu is in the six-character roster", Roster.IDS.size() == 6 and "xuchu" in Roster.IDS)
	if not "xuchu" in Roster.IDS:
		quit(1)
		return
	check("Xu offers its own saber plus the preserved saber and sword", Roster.weapon_choices("xuchu") == WEAPONS)
	for id in EXCLUSIVE_WEAPONS:
		game.return_to_menu()
		game.select_character(id)
		game.select_weapon("sword")
		await frames(2)
		check(id + " retains its exclusive weapon", Roster.weapon_choices(id) == [EXCLUSIVE_WEAPONS[id]] and game.player.weapon_id == EXCLUSIVE_WEAPONS[id])
	game.return_to_menu()
	game.select_character("xuchu")
	await frames(3)
	check("Xu defaults to the supplied saber", game.player.weapon_id == "xuchu_saber")
	skill_identity = {"rush": game.player.skill_name("rush"), "counter": game.player.skill_name("counter"), "ultimate": game.player.ultimate_name(), "rush_description": game.player.skill_description("rush")}
	for weapon in WEAPONS:
		await select_weapon(weapon)
		await grip_checks(weapon)
		resource_checks(weapon)
		await basic_checks(weapon)
		await skill_checks(weapon)
	await ai_check()
	var output = FileAccess.open("res://qa/xuchu-results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed": failures.is_empty(), "checks": checks.size(), "failures": failures, "results": checks}, "\t"))
	print("XUCHU QA ", checks.size(), " checks, ", failures.size(), " failures")
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	game.queue_free()
	game = null
	await frames(3)
	quit(0 if failures.is_empty() else 1)
