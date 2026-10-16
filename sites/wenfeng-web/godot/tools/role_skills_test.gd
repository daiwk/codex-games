extends Node

# Exercise the real action clocks and strike resolver. Stationary defenders are
# intentional: knockback cannot hide a repeated hit or move later hits out of range.
var game: Node
var checks: Array = []
var failures: Array = []
var impacts: Array = []
var stages: Array = []
var polling_skill_input = false
var move_behind_on_finish = false
var rush_distances: Dictionary = {}

func _physics_process(_delta: float) -> void:
	if polling_skill_input:
		game._player_input()

func check(condition: bool, title: String, detail = "") -> void:
	checks.append({"name": title, "passed": condition, "detail": str(detail)})
	print(("PASS " if condition else "FAIL ") + title + (": " + str(detail) if str(detail) != "" else ""))
	if not condition:
		failures.append(title)

func frames(count: int) -> void:
	var simulated = 0.0
	while simulated < count / 60.0 - 0.00001:
		await get_tree().physics_frame
		simulated += get_physics_process_delta_time()

func seconds(duration: float) -> void:
	await frames(int(ceil(duration * 60.0)))

func select_role(id: String) -> void:
	game.return_to_menu()
	game.select_character(id)
	game.select_weapon("sword")
	if not game.enemy.impact_received.is_connected(_observe_impact):
		game.enemy.impact_received.connect(_observe_impact)
	if not game.player.skill_triggered.is_connected(_observe_stage):
		game.player.skill_triggered.connect(_observe_stage)
	await frames(2)

func _observe_impact(_fighter, outcome: String, _at: Vector3) -> void:
	impacts.append(outcome)

func _observe_stage(fighter, id: String, stage: String) -> void:
	stages.append({"skill": id, "stage": stage, "time": fighter.action_time, "clip": fighter.current_clip})
	# Emitted after commitment and before resolving damage. Moving behind here
	# distinguishes an actual radial slam from a targeted thrust's last hit.
	if move_behind_on_finish and id == "ultimate" and stage == "finish":
		game.enemy.position = fighter.position - fighter.forward() * 2.0

func reset(gap = 1.8) -> void:
	get_tree().paused = false
	game.paused = false
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	game.phase = "fight"
	game.round_time = 90.0
	game.ai_enabled = false
	game.scores = [0, 0]
	game.hit_stop_until = 0
	game.skill_fx.clear()
	move_behind_on_finish = false
	impacts.clear()
	stages.clear()
	for fighter in [game.player, game.enemy]:
		fighter.reset_fighter()
		fighter.enabled = true
		fighter.damage_dealt = 0.0
		fighter.parries = 0
		fighter.blocked_hits = 0
		fighter.dodged_hits = 0
	game.player.position = Vector3(0, 0.015, gap * 0.5)
	game.enemy.position = Vector3(0, 0.015, -gap * 0.5)
	game.player.rotation.y = PI
	game.enemy.rotation.y = 0.0

func freeze_defender(blocking = false) -> void:
	game.enemy.enabled = false
	if blocking:
		game.enemy.state = "block"
		game.enemy.wants_block = true
		game.enemy.action_time = 0.5

func offset_defender(side: float, forward_distance: float) -> void:
	var right: Vector3 = game.player.global_basis.x.normalized()
	game.enemy.position = game.player.position + right * side + game.player.forward() * forward_distance

func skill_key(code: int) -> void:
	polling_skill_input = true
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await frames(3)
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await frames(2)
	polling_skill_input = false

func resource_checks(role: String) -> void:
	var q_cost = 22.0 if role == "zhaoyun" else 28.0
	var e_cost = 20.0 if role == "zhaoyun" else 26.0
	var q_cd = 4.5 if role == "zhaoyun" else 6.0
	var e_cd = 6.5 if role == "zhaoyun" else 9.0
	var aliases = ["DragonCharge", "DragonThrust", "DragonCross", "DragonBackCut", "CloudStep"] if role == "zhaoyun" else ["TigerSweep", "TigerRoar", "TigerCharge", "TigerSlam"]
	var complete = true
	for clip in aliases:
		complete = complete and game.player.animation_names.has(clip)
	check(complete, role + " has its own authored skill clips", aliases)
	check(game.player.skill_name("rush") != game.enemy.skill_name("rush") and game.player.skill_name("counter") != game.enemy.skill_name("counter"), role + " exposes distinct Q and E names")
	check(game.player.skill_description("rush") != game.enemy.skill_description("rush") and game.player.skill_description("counter") != game.enemy.skill_description("counter"), role + " describes distinct Q and E rules")
	check(is_equal_approx(game.player.skill_cost("rush"), q_cost) and is_equal_approx(game.player.skill_cost("counter"), e_cost), role + " UI costs match role rules")
	check(is_equal_approx(game.player.skill_cooldown("rush"), q_cd) and is_equal_approx(game.player.skill_cooldown("counter"), e_cd), role + " UI cooldowns match role rules")
	reset()
	check(game.player.energy == 35.0, role + " fresh round begins with 35 energy")
	check(not game.player.request_skill("unknown"), role + " rejects unknown skills")
	game.player.stamina = q_cost - 0.1
	check(not game.player.request_skill("rush"), role + " Q requires its actual stamina cost")
	game.player.stamina = e_cost - 0.1
	check(not game.player.request_skill("counter"), role + " E requires its actual stamina cost")
	game.player.energy = 99.0
	check(not game.player.request_ultimate(), role + " U requires full energy")
	game.player.enabled = false
	game.player.energy = 100.0
	game.player.stamina = 100.0
	check(not game.player.request_skill("rush") and not game.player.request_ultimate(), role + " disabled fighter cannot spend skills")
	for id in ["rush", "counter"]:
		reset(8.0)
		check(game.player.request_skill(id), role + " " + id + " can activate")
		var cost = q_cost if id == "rush" else e_cost
		var cooldown = q_cd if id == "rush" else e_cd
		check(is_equal_approx(game.player.stamina, 100.0 - cost) and is_equal_approx(game.player.cooldowns[id], cooldown), role + " " + id + " spends its own cost and starts cooldown")
		check(game.player.state == "skill", role + " " + id + " is an active action, not the shared counter stance")
		check(not game.player.request_skill("rush") and not game.player.request_ultimate(), role + " " + id + " recovery cannot be cancelled into another skill")
		await seconds(1.2)
		check(not game.player.request_skill(id), role + " " + id + " rejects repeat during cooldown")
		await seconds(cooldown)
		game.player.stamina = 100.0
		check(game.player.cooldowns[id] == 0.0 and game.player.request_skill(id), role + " " + id + " becomes ready after its cooldown")

func rush_checks(role: String) -> void:
	var damage = 20.0 if role == "zhaoyun" else 30.0
	reset()
	freeze_defender()
	game.player.request_skill("rush")
	await seconds(0.27 if role == "zhaoyun" else 0.43)
	check(game.enemy.hp == 120.0, role + " Q telegraph cannot damage early")
	await seconds(0.46)
	check(is_equal_approx(game.enemy.hp, 120.0 - damage), role + " Q deals its distinct damage once", game.enemy.hp)
	await seconds(0.6)
	check(is_equal_approx(game.enemy.hp, 120.0 - damage) and game.player.state == "idle", role + " Q recovery ends without repeated damage")
	reset(5.0)
	freeze_defender()
	var origin: Vector3 = game.player.position
	game.player.request_skill("rush")
	await seconds(0.7)
	rush_distances[role] = game.player.position.distance_to(origin)
	check(float(rush_distances[role]) > (0.8 if role == "zhaoyun" else 0.1), role + " Q advances through actual movement", rush_distances[role])
	reset(8.0)
	freeze_defender()
	game.player.request_skill("rush")
	await seconds(0.22)
	offset_defender(1.4, 1.2)
	await seconds(0.7)
	check(game.enemy.hp == (120.0 if role == "zhaoyun" else 90.0), role + " Q " + ("misses outside narrow thrust corridor" if role == "zhaoyun" else "catches a lateral target in broad sweep"), game.enemy.hp)
	reset(8.0)
	freeze_defender()
	game.player.request_skill("rush")
	await seconds(0.22)
	offset_defender(0.0, -1.7)
	await seconds(1.0)
	check(game.enemy.hp == 120.0, role + " Q cannot hit behind committed facing")
	reset(8.0)
	freeze_defender()
	game.player.request_skill("rush")
	await seconds(1.2)
	check(game.enemy.hp == 120.0, role + " Q has finite range")
	reset()
	freeze_defender()
	game.player.request_skill("rush")
	await seconds(0.30)
	var outcome: String = game.player.receive_strike(game.enemy, DuelFighter.ATTACKS[0])
	check(outcome == "hit" and game.player.hp == 105.0 and (game.player.state == "skill") == (role == "machao"), role + " Q " + ("remains interruptible by light attacks" if role == "zhaoyun" else "has light-hit armor but still loses HP"))
	reset()
	freeze_defender()
	game.player.request_skill("rush")
	await seconds(0.30)
	outcome = game.player.receive_strike(game.enemy, DuelFighter.HEAVY)
	check(outcome == "hit" and game.player.hp == 89.0 and game.player.state == "hit", role + " Q can be interrupted by a heavy")

func zhao_step_checks() -> void:
	reset(2.0)
	freeze_defender()
	var origin: Vector3 = game.player.position
	game.player.input_move = Vector3.RIGHT
	game.player.request_skill("counter")
	game.player.input_move = Vector3.ZERO
	await seconds(0.18)
	var outcome: String = game.player.receive_strike(game.enemy, DuelFighter.ATTACKS[0])
	check(outcome == "evade" and game.player.hp == 120.0 and game.player.state == "skill", "Zhao E evades a real hit during its step")
	check(game.player.position.x - origin.x > 0.4, "Zhao E follows chosen lateral movement", game.player.position - origin)
	check(game.enemy.state == "idle" and game.player.parries == 0, "Zhao E does not intercept or stagger the attacker")
	offset_defender(0.0, 1.8)
	await seconds(0.50)
	check(game.enemy.hp == 104.0, "Zhao E returns a 16 damage cut without needing an incoming attack", game.enemy.hp)
	await seconds(0.4)
	check(game.player.state == "idle" and game.enemy.hp == 104.0, "Zhao E cuts once then recovers")
	reset(4.0)
	freeze_defender()
	origin = game.player.position
	game.player.request_skill("counter")
	await seconds(0.25)
	check((game.player.position - origin).dot(game.player.forward()) < -0.4, "Zhao E defaults to a backstep without directional input")
	reset()
	freeze_defender()
	game.player.request_skill("counter")
	await seconds(0.35)
	outcome = game.player.receive_strike(game.enemy, DuelFighter.ATTACKS[0])
	check(outcome == "hit" and game.player.hp == 105.0 and game.player.state == "hit", "Zhao E is vulnerable after its short evasion window")
	await seconds(0.7)
	check(game.enemy.hp == 120.0, "interrupting Zhao E prevents its later cut")

func ma_roar_checks() -> void:
	reset()
	freeze_defender(true)
	game.player.request_skill("counter")
	await seconds(0.50)
	check(game.enemy.hp == 120.0 and is_equal_approx(game.enemy.stamina, 60.0), "Ma E drains 40 guard without HP chip", {"hp": game.enemy.hp, "stamina": game.enemy.stamina})
	check(game.enemy.state == "stagger" and is_equal_approx(game.enemy.action_duration, 0.70), "Ma E forces a guard break even against full stamina")
	check(game.enemy.blocked_hits == 1 and game.enemy.parries == 0, "Ma E cannot be parried and breaks guard only once")
	reset()
	freeze_defender()
	game.player.request_skill("counter")
	await seconds(0.60)
	check(game.enemy.hp == 112.0 and is_equal_approx(game.enemy.action_duration, 0.70), "Ma E deals 8 damage and long hitstun to unguarded targets")
	check(Vector2(game.enemy.velocity.x, game.enemy.velocity.z).length() > 2.0, "Ma E knocks an unguarded target away")
	reset(8.0)
	freeze_defender()
	game.player.request_skill("counter")
	await seconds(0.22)
	offset_defender(0.0, -1.8)
	await seconds(0.50)
	check(game.enemy.hp == 112.0, "Ma E is a radial roar that also catches rear targets")
	reset()
	freeze_defender()
	game.player.request_skill("counter")
	await seconds(0.15)
	var outcome: String = game.player.receive_strike(game.enemy, DuelFighter.ATTACKS[0])
	check(outcome == "hit" and game.player.hp == 105.0 and game.player.state == "hit", "Ma E has no Zhao-style evasion or counter interception")

func ultimate_checks(role: String) -> void:
	var expected_damage = 52.0 if role == "zhaoyun" else 58.0
	reset(2.0)
	freeze_defender()
	game.player.energy = 100.0
	check(game.player.request_ultimate(), role + " full energy activates U")
	check(game.player.energy == 0.0 and game.player.state == "ultimate" and game.player.skill_stage == "windup", role + " U consumes energy and has readable startup")
	await seconds(0.60 if role == "zhaoyun" else 1.20)
	check(game.enemy.hp == 120.0, role + " U cannot damage before its first active window")
	await seconds(2.4)
	var damage_events = 0
	for outcome in impacts:
		if outcome in ["hit", "heavy_hit"]:
			damage_events += 1
	check(game.enemy.hp == 120.0 - expected_damage and game.player.damage_dealt == expected_damage, role + " U deals its actual total damage", {"hp": game.enemy.hp, "damage": game.player.damage_dealt})
	check(damage_events == (5 if role == "zhaoyun" else 1), role + " U has " + ("five distinct targeted hits" if role == "zhaoyun" else "one committed slam"), damage_events)
	check(game.player.state == "idle" and game.player.energy == 0.0 and game.enemy.energy > 35.0, role + " U recovers and cannot refill itself from its own damage")
	reset(14.0)
	freeze_defender()
	move_behind_on_finish = true
	game.player.energy = 100.0
	game.player.request_ultimate()
	await seconds(2.8)
	check(game.enemy.hp == (120.0 if role == "zhaoyun" else 62.0), role + " U final " + ("targeted cut misses behind" if role == "zhaoyun" else "radial slam hits behind"), game.enemy.hp)
	reset(14.0)
	freeze_defender()
	game.player.energy = 100.0
	game.player.request_ultimate()
	await seconds(2.8)
	check(game.enemy.hp == 120.0, role + " U cannot hit an opponent outside its range")
	reset()
	freeze_defender()
	game.player.energy = 100.0
	game.player.request_ultimate()
	await seconds(0.20)
	var outcome: String = game.player.receive_strike(game.enemy, DuelFighter.HEAVY)
	check(outcome == "hit" and game.player.state == "hit" and is_equal_approx(game.player.energy, 47.4), role + " early heavy interrupts U and refunds 35 plus received-hit energy", game.player.energy)
	await seconds(2.8)
	check(game.enemy.hp == 120.0, role + " interrupted U emits no later damage")
	reset(1.3)
	game.player.energy = 100.0
	game.player.request_ultimate()
	await seconds(0.58 if role == "zhaoyun" else 1.21)
	game.enemy.request_dodge(Vector3.ZERO)
	await seconds(0.23)
	check(game.enemy.hp == 120.0 and game.enemy.dodged_hits > 0, role + " actual first U strike can be dodged", game.enemy.dodged_hits)

func zhao_ultimate_checks() -> void:
	reset(2.0)
	freeze_defender()
	game.player.energy = 100.0
	game.player.request_ultimate()
	await seconds(0.82)
	check(game.enemy.hp == 112.0, "Zhao U first chase hit deals 8 damage")
	offset_defender(1.0, 1.73)
	await seconds(0.32)
	check(game.enemy.hp == 104.0, "Zhao U reacquires a target between strikes", {"hp": game.enemy.hp, "facing": game.player.forward()})
	reset()
	freeze_defender()
	game.player.energy = 100.0
	game.player.request_ultimate()
	await seconds(0.60)
	var outcome: String = game.player.receive_strike(game.enemy, DuelFighter.HEAVY)
	check(outcome == "evade" and game.player.hp == 120.0 and game.player.state == "ultimate", "Zhao U grants brief invulnerability during a chase lunge")
	for data in [DuelFighter.ATTACKS[0], DuelFighter.HEAVY]:
		reset()
		freeze_defender()
		game.player.energy = 100.0
		game.player.request_ultimate()
		await seconds(0.82)
		outcome = game.player.receive_strike(game.enemy, data)
		check(outcome == "hit" and game.player.state == "hit", "Zhao U can be interrupted between lunges by " + ("heavy" if data.heavy else "light"))
	reset()
	freeze_defender()
	game.player.energy = 100.0
	game.player.request_ultimate()
	await seconds(0.20)
	outcome = game.player.receive_strike(game.enemy, DuelFighter.ATTACKS[0])
	check(outcome == "hit" and game.player.state == "hit", "Zhao U startup is vulnerable to a light attack")

func ma_ultimate_checks() -> void:
	reset(2.0)
	freeze_defender(true)
	game.player.energy = 100.0
	game.player.request_ultimate()
	await seconds(1.65)
	check(game.enemy.hp == 108.0 and game.enemy.stamina == 0.0, "Ma U breaks full guard and deals exactly 12 chip damage", {"hp": game.enemy.hp, "stamina": game.enemy.stamina})
	check(game.enemy.state == "stagger" and is_equal_approx(game.enemy.action_duration, 1.15) and game.enemy.parries == 0, "Ma U applies its long forced guard break without being parried")
	reset()
	freeze_defender()
	game.player.energy = 100.0
	game.player.request_ultimate()
	await seconds(0.20)
	var outcome: String = game.player.receive_strike(game.enemy, DuelFighter.ATTACKS[0])
	check(outcome == "hit" and game.player.hp == 105.0 and game.player.state == "hit", "Ma U remains vulnerable before its armor commitment")
	reset()
	freeze_defender()
	game.player.energy = 100.0
	game.player.request_ultimate()
	await seconds(0.70)
	outcome = game.player.receive_strike(game.enemy, DuelFighter.HEAVY)
	check(outcome == "hit" and game.player.hp == 89.0 and game.player.state == "ultimate", "Ma U armor after commitment takes full heavy damage without interruption")
	game.player.hp = 1.0
	outcome = game.player.receive_strike(game.enemy, DuelFighter.HEAVY)
	check(game.player.hp == 0.0 and game.player.state == "dead" and game.player.skill_id == "", "lethal damage stops Ma U despite armor")
	await seconds(2.0)
	check(game.enemy.hp == 120.0, "dead Ma U cannot produce its pending slam")

func input_and_lifecycle_checks(role: String) -> void:
	reset(5.0)
	await skill_key(KEY_Q)
	check(game.player.skill_id == "rush" and game.player.cooldowns.rush > game.player.skill_cooldown("rush") - 0.2, role + " physical Q routes to its own active skill")
	reset(5.0)
	await skill_key(KEY_E)
	check(game.player.state == "skill" and game.player.skill_id == "counter" and game.player.cooldowns.counter > game.player.skill_cooldown("counter") - 0.2, role + " physical E routes to its own active skill")
	reset(5.0)
	game.player.energy = 100.0
	await skill_key(KEY_U)
	check(game.player.state == "ultimate" and game.player.energy == 0.0, role + " physical U routes to its own ultimate")
	reset(5.0)
	game.player.energy = 100.0
	game.player.request_ultimate()
	await seconds(0.20)
	var paused_time: float = game.player.action_time
	var paused_fx: int = game.skill_fx.active_effect_count()
	game.toggle_pause()
	await get_tree().create_timer(0.05, true, false, true).timeout
	check(get_tree().paused and is_equal_approx(game.player.action_time, paused_time) and game.skill_fx.active_effect_count() == paused_fx, role + " pause freezes U and its effects")
	game.toggle_pause()
	game.player.cooldowns.rush = 4.0
	game.player.cooldowns.counter = 7.0
	game.player.reset_fighter()
	check(game.player.state == "idle" and game.player.skill_id == "" and game.player.energy == 35.0 and game.player.cooldowns.rush == 0.0 and game.player.cooldowns.counter == 0.0, role + " reset clears all role action state and cooldowns")
	game.return_to_menu()
	await frames(3)
	check(game.skill_fx.active_effect_count() == 0, role + " returning to selection clears skill effects")

func run(target: Node) -> void:
	game = target
	process_mode = Node.PROCESS_MODE_ALWAYS
	game.testing = true
	game.ai_enabled = false
	game.fx.muted = true
	await frames(4)
	for role in ["zhaoyun", "machao"]:
		await select_role(role)
		await resource_checks(role)
		await rush_checks(role)
		if role == "zhaoyun":
			await zhao_step_checks()
		else:
			await ma_roar_checks()
		await ultimate_checks(role)
		if role == "zhaoyun":
			await zhao_ultimate_checks()
		else:
			await ma_ultimate_checks()
		await input_and_lifecycle_checks(role)
	check(float(rush_distances.zhaoyun) > float(rush_distances.machao) + 0.4, "Zhao Q closes farther than Ma Q's deliberate sweeping step", rush_distances)
	var report = {"passed": failures.is_empty(), "checks": checks.size(), "failures": failures, "results": checks, "final_state": game.snapshot()}
	for path in ["res://qa/role-skills-results.json", "res://qa/skills-results.json"]:
		var file = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	print("DUEL_ROLE_SKILLS=" + ("PASS" if failures.is_empty() else "FAIL") + " CHECKS=" + str(checks.size()))
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	get_tree().quit(0 if failures.is_empty() else 1)
