extends "res://tools/responsiveness_test.gd"

var checks: Array = []
var armor_failures: Array = []
var incoming: Array = []

func verify(label: String, passed: bool, detail: Variant) -> void:
	checks.append({"label": label, "passed": passed, "detail": detail})
	print("PASS " if passed else "FAIL ", label, " ", JSON.stringify(detail))
	if not passed: armor_failures.append(label)

func incoming_impact(_actor: Node, outcome: String, at: Vector3) -> void:
	incoming.append({"player_state": player.state, "player_action_time": player.action_time,
		"enemy_state": enemy.state, "enemy_action_time": enemy.action_time,
		"outcome": outcome, "position": point(at), "hp": player.hp})

func spawn_enemy(role: String) -> void:
	game.enemies.clear()
	enemy.queue_free()
	await frames(2)
	enemy = Actor.new()
	enemy.character_id = role
	enemy.weapon_id = "serpent_spear" if role == "bandit" else "machao_spear"
	enemy.mounted = true
	enemy.position = Vector3(0, 0.015, 4)
	enemy.set_meta("rpg_id", "raider_qa")
	game.add_child(enemy)
	enemy.apply_stats(1000, 1, 0, true)
	enemy.strike_requested.connect(game._resolve_strike)
	enemy.impact_received.connect(impact)
	game.enemies["raider_qa"] = enemy
	player.impact_received.connect(incoming_impact) if not player.impact_received.is_connected(incoming_impact) else null
	await frames(4)

func prepare_interrupt(gap = 1.6) -> void:
	observing = false
	game._release_inputs()
	player.reset_fighter()
	enemy.reset_fighter()
	enemy.apply_stats(1000, 1, 0, true)
	player.enabled = true
	enemy.enabled = true
	enemy.set_physics_process(true)
	player.position = Vector3(0, 0.015, 0)
	enemy.position = Vector3(0, 0.015, gap)
	player.rotation.y = 0.0
	enemy.rotation.y = PI
	player.velocity = Vector3.ZERO
	enemy.velocity = Vector3.ZERO
	player.opponent = enemy
	enemy.opponent = player
	game.locked_target_id = "raider_qa"
	await frames(12)
	incoming = []
	impacts = []
	start_events = []
	press_tick = ticks
	observing = true

func player_j() -> void:
	key(true)
	await frames(2)
	key(false)

func run() -> void:
	output_path = "/private/tmp/wenfeng-responsiveness-interrupt-cases.json"
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	game = Controller.new()
	root.add_child(game)
	var floor_body = StaticBody3D.new()
	var collider = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(2000, 0.3, 2000)
	collider.shape = box
	collider.position.y = -0.15
	floor_body.add_child(collider)
	game.add_child(floor_body)
	await pair("mounted", "serpent_spear")
	await spawn_enemy("bandit")
	for kind in ["light", "heavy"]:
		await prepare_interrupt()
		var health = player.hp
		var enemy_started = enemy.request_light() if kind == "light" else enemy.request_heavy()
		await frames(5 if kind == "light" else 12)
		await player_j()
		await frames(65)
		var protected_at_contact = not incoming.is_empty() and incoming[0].player_state == "attack"
		verify("actual bandit " + kind + " contact preserves only eligible normal", enemy_started and not incoming.is_empty() and (protected_at_contact if kind == "light" else not protected_at_contact),
			{"enemy_character": enemy.character_id, "enemy_data": enemy.attack, "incoming": incoming, "outgoing": impacts,
			"damage_taken": health - player.hp, "damage_dealt": 1000.0 - enemy.hp, "player_starts": start_events})
		if kind == "light":
			verify("protected jab still takes full real light damage and lands once", is_equal_approx(health - player.hp, 18.0) and is_equal_approx(1000.0 - enemy.hp, 18.0),
				{"taken": health - player.hp, "dealt": 1000.0 - enemy.hp})
	await spawn_enemy("machao")
	await prepare_interrupt()
	var boss_hp = player.hp
	var boss_started = enemy.request_light()
	await frames(5)
	await player_j()
	await frames(65)
	verify("actual boss light still interrupts the player jab", boss_started and not incoming.is_empty() and incoming[0].player_state != "attack" and player.hp < boss_hp,
		{"incoming": incoming, "enemy_character": enemy.character_id, "taken": boss_hp - player.hp, "dealt": 1000.0 - enemy.hp})
	await spawn_enemy("bandit")
	# Start outside reach, then let the real enemy approach during the player's
	# recovery. The timer/state remain the live normal-attack timer.
	await prepare_interrupt(4.0)
	await player_j()
	for i in 60:
		if player.action_time >= 0.30: break
		await frames(1)
	enemy.position = Vector3(0, 0.015, 1.6)
	enemy.request_light()
	await frames(50)
	verify("bandit light during normal recovery still interrupts", not incoming.is_empty() and incoming[0].player_state != "attack" and float(incoming[0].player_action_time) < 0.05,
		{"incoming": incoming, "normal_duration": 0.648})
	# One exact boundary check after the epsilon fix; full previous matrices stay
	# separate, including their original 3.4 floating cutoff misses.
	await exercise("mounted", "serpent_spear", 3.4)
	verify("3.4 horizontal boundary accepts at most 0.9m physical step", absf(player.position.z) <= 0.9001 and absf(player.position.z) > 0.01,
		{"travel_z": player.position.z, "case": results.back()})
	var out = FileAccess.open("/private/tmp/wenfeng-responsiveness-interrupt-regression.json", FileAccess.WRITE)
	out.store_string(JSON.stringify({"completed": true, "passed": armor_failures.is_empty(), "checks": checks.size(), "failures": armor_failures, "results": checks,
		"scope": "Actual imported bandit/machao actors, real enemy request_light/heavy and RPG strike resolver; player receives real J input. AI and world isolated; no synthetic armor flag."}, "\t"))
	print("INTERRUPT DONE ", checks.size(), " checks ", armor_failures.size(), " failures")
	quit(0 if armor_failures.is_empty() else 1)
