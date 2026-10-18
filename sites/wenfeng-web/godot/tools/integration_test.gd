extends Node

var game: Node
var checks: Array = []
var failures: Array = []

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

func reset(gap = 1.30) -> void:
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	game.get_tree().paused = false
	game.paused = false
	game.phase = "fight"
	game.round_time = 90.0
	game.ai_enabled = false
	game.scores = [0, 0]
	for fighter in [game.player, game.enemy]:
		fighter.reset_fighter()
		fighter.enabled = true
		fighter.damage_dealt = 0.0
	game.player.position = Vector3(0, 0.015, gap * 0.5)
	game.enemy.position = Vector3(0, 0.015, -gap * 0.5)
	game.player.rotation.y = PI
	game.enemy.rotation.y = 0.0

func run(target: Node) -> void:
	game = target
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 240
	game.fx.muted = true
	await frames(4)
	for fighter in [game.player, game.enemy]:
		var required = ["Idle", "Walk", "WalkBack", "StrafeLeft", "StrafeRight", "Run", "TurnLeft", "TurnRight", "Attack1", "Attack2", "Attack3", "Heavy", "Block", "Dodge", "Hit", "GuardBreak", "Death"]
		var complete = true
		for clip in required:
			complete = complete and fighter.animation_names.has(clip)
		check(complete, fighter.character_id + " has every replacement clip")
		var head_length = (.99 - float(fighter.Roster.WEAPONS[fighter.weapon_id].blade_start)) * float(fighter.grip_config.weapon_length)
		check(is_equal_approx(fighter.blade_tip().distance_to(fighter.blade_base()), head_length), fighter.character_id + " spear scale", fighter.blade_tip().distance_to(fighter.blade_base()))
		check(fighter.is_two_handed() and fighter.grip.global_position.distance_to(fighter.palm_position(false)) < 0.035, fighter.character_id + " weapon follows two-hand grip")
	check(ResourceLoader.exists("res://onehand_sword.glb") and ResourceLoader.exists("res://onehand_saber.glb"), "sword and saber remain available for future warriors")

	reset(5.0)
	await frames(2)
	var origin = game.player.position
	Input.action_press("move_right")
	game._player_input()
	await frames(45)
	Input.action_release("move_right")
	game._player_input()
	check(game.player.position.distance_to(origin) > 0.7, "camera-relative movement accepts mapped input")
	game.player.input_move = Vector3.RIGHT
	await frames(240)
	check(Vector2(game.player.position.x, game.player.position.z).length() <= 7.601, "courtyard boundary contains fighter")
	game.player.input_move = Vector3.ZERO
	game.enemy.position = Vector3(-2, 0.015, -1)
	await frames(100)
	var direction = (game.enemy.position - game.player.position).normalized()
	check(game.player.forward().dot(direction) > 0.98, "fighter turns smoothly toward locked opponent", {"dot": game.player.forward().dot(direction), "yaw": game.player.rotation.y, "direction": direction, "step": game.player.turning_in_place, "clip": game.player.current_clip})

	reset(5.0)
	game.player.rotation.y = 0.0
	await frames(4)
	check(game.player.turning_in_place and game.player.current_clip in ["TurnLeft", "TurnRight"], "large facing change uses stepping animation")
	check(absf(game.player.rotation.y) < deg_to_rad(15.0), "turn accelerates without snapping through 180 degrees", game.player.rotation.y)
	await frames(115)
	direction = (game.enemy.position - game.player.position).normalized()
	check(game.player.forward().dot(direction) > 0.995 and not game.player.turning_in_place, "pivot finishes facing opponent and returns to ready stance")
	reset(5.0)
	var resting_yaw = game.player.rotation.y
	game.enemy.position.x = 0.20
	await frames(35)
	check(absf(angle_difference(resting_yaw, game.player.rotation.y)) < 0.001 and game.player.current_clip == "Idle", "small target motion does not spin planted feet", {"before": resting_yaw, "after": game.player.rotation.y, "clip": game.player.current_clip})

	reset()
	game.player.request_light()
	await frames(35)
	var after_hit = game.enemy.hp
	check(after_hit < 120.0 and after_hit > 90.0, "light attack lands during authored swing", after_hit)
	await frames(25)
	check(is_equal_approx(game.enemy.hp, after_hit), "one swing damages once")
	check(game.player.state == "idle", "attack recovery returns to idle", game.player.state)

	reset(5.0)
	game.player.request_heavy()
	await frames(75)
	check(game.enemy.hp == 120.0, "out-of-range attack misses")
	reset(4.0)
	game.player.request_light()
	await frames(9)
	game.enemy.position = game.player.position + Vector3(0, 0, 1.2)
	await frames(35)
	check(game.enemy.hp == 120.0, "attack cannot hit behind its locked facing")

	reset()
	var seen: Array = []
	var recorder = func(fighter, action):
		if fighter == game.player and action == "light":
			seen.append(fighter.attack.clip)
	game.player.action_started.connect(recorder)
	game.player.request_light()
	await frames(12)
	game.player.request_light()
	await frames(24)
	game.player.request_light()
	await frames(90)
	game.player.action_started.disconnect(recorder)
	check(seen == ["Attack1", "Attack2", "Attack3"], "buffered light inputs chain all three authored attacks", seen)
	check(game.enemy.hp < 100.0, "combo applies real damage", game.enemy.hp)

	reset()
	game.enemy.wants_block = true
	await frames(20)
	game.player.request_light()
	await frames(30)
	check(game.enemy.hp == 120.0 and game.enemy.stamina < 90.0 and game.enemy.blocked_hits > 0, "held guard absorbs strike and spends stamina", game.enemy.stamina)

	reset()
	var parries_before = game.enemy.parries
	game.player.request_light()
	await frames(5)
	game.enemy.wants_block = true
	await frames(19)
	check(game.enemy.parries > parries_before and game.player.state == "stagger", "timed parry staggers attacker", game.player.state)

	reset()
	game.enemy.stamina = 30.0
	game.enemy.wants_block = true
	await frames(20)
	game.player.request_heavy()
	await frames(37)
	check(game.enemy.state == "stagger" and game.enemy.stamina == 0.0, "heavy pressure breaks exhausted guard", game.enemy.state)

	reset()
	game.enemy.request_dodge(Vector3.RIGHT)
	await frames(5)
	var hp_before = game.enemy.hp
	var dodge_origin = game.enemy.position
	var outcome = game.enemy.receive_strike(game.player, DuelFighter.ATTACKS[0])
	check(outcome == "evade" and game.enemy.hp == hp_before, "dodge invulnerability prevents damage")
	await frames(35)
	check(game.enemy.position.distance_to(dodge_origin) > 0.7 and game.enemy.state == "idle", "dodge moves and recovers")
	reset()
	game.player.stamina = 10.0
	check(not game.player.request_heavy() and not game.player.request_light() and not game.player.request_dodge(), "insufficient stamina rejects actions")
	await frames(90)
	check(game.player.stamina > 40.0, "stamina regenerates while recovering")

	reset()
	game.toggle_pause()
	var hp_paused = game.player.hp
	await get_tree().create_timer(0.05, true, false, true).timeout
	check(get_tree().paused and game.player.hp == hp_paused, "pause freezes match")
	game.toggle_pause()
	check(not get_tree().paused, "pause resumes match")

	reset()
	game.enemy.hp = 1.0
	game.player.request_light()
	await frames(30)
	check(game.enemy.state == "dead" and game.phase == "round_end" and game.scores[0] == 1, "lethal attack plays death and awards round")
	game.phase_clock = 0.01
	await frames(4)
	check(game.phase == "countdown" and game.player.hp == 120.0 and game.enemy.hp == 120.0, "new round resets both fighters")
	game.phase_clock = 0.01
	await frames(4)
	game.player.position = Vector3(0, 0.015, 0.65)
	game.enemy.position = Vector3(0, 0.015, -0.65)
	game.enemy.hp = 1.0
	game.player.request_light()
	await frames(30)
	game.phase_clock = 0.01
	await frames(4)
	check(game.phase == "match_end" and game.scores[0] == 2, "best of three produces player victory", [game.phase, game.scores])

	reset()
	game.player.hp = 1.0
	game.enemy.request_light()
	await frames(30)
	check(game.player.state == "dead" and game.scores[1] == 1, "opponent can win a round")
	game.scores[1] = 2
	game.phase_clock = 0.01
	await frames(4)
	check(game.phase == "match_end", "defeat reaches result screen")
	game.start_match()
	check(game.phase == "countdown" and game.scores == [0, 0] and game.player.hp == 120.0, "rematch clears match result")
	Engine.time_scale = 4.0

	reset()
	game.player.hp = 80
	game.enemy.hp = 40
	game.round_time = 0.001
	await frames(3)
	check(game.phase == "round_end" and game.scores[0] == 1, "timeout awards healthier fighter")
	reset()
	game.round_time = 0.001
	await frames(3)
	check(game.overtime and game.player.hp == 1.0 and game.enemy.hp == 1.0, "tied timeout enters sudden death")

	game.return_to_menu()
	game.select_character("machao")
	game.select_weapon("saber")
	await frames(3)
	check(game.player.character_id == "machao" and game.player.weapon_id == "machao_spear" and game.enemy.character_id == "zhaoyun" and game.enemy.weapon_id == "zhaoyun_spear", "selection equips paired spears and rejects reserved saber")
	reset(4.5)
	Engine.time_scale = 4.0
	game.ai_enabled = true
	game.ai_think = 0.0
	game.ai_cooldown = 0.15
	await frames(620)
	check(game.enemy.damage_dealt > 0.0, "AI approaches and executes real attacks", game.enemy.damage_dealt)
	check(game.player.position.y > -0.1 and game.enemy.position.y > -0.1, "fighters remain on courtyard floor")

	var report = {"passed": failures.is_empty(), "checks": checks.size(), "failures": failures, "results": checks, "final_state": game.snapshot()}
	var file = FileAccess.open("res://qa/integration-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("DUEL_INTEGRATION=" + ("PASS" if failures.is_empty() else "FAIL") + " CHECKS=" + str(checks.size()))
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	get_tree().quit(0 if failures.is_empty() else 1)
