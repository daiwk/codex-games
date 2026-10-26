extends "res://tools/responsiveness_test.gd"

var assertions: Array = []
var life_failures: Array = []

func verify(label: String, passed: bool, detail: Variant = null) -> void:
	assertions.append({"label": label, "passed": passed, "detail": detail})
	print("PASS " if passed else "FAIL ", label, " ", JSON.stringify(detail))
	if not passed:
		life_failures.append(label)

func send_key(code: int, pressed: bool) -> void:
	var e = InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)

func reset_probe(gap = 2.1) -> void:
	observing = false
	game.get_tree().paused = false
	game.paused = false
	game.inventory_open = false
	game.map_open = false
	game._release_inputs()
	player.reset_fighter()
	enemy.reset_fighter()
	enemy.apply_stats(1000, 1, 0, true)
	player.enabled = true
	enemy.enabled = false
	enemy.set_physics_process(false)
	player.position = Vector3(0, 0.015, 0)
	enemy.position = Vector3(0, 0.015, gap)
	player.rotation.y = 0.0
	enemy.rotation.y = PI
	game.locked_target_id = "raider_qa"
	game.phase = "explore"
	await frames(12)
	start_events = []
	impacts = []
	samples = []
	first_active = -1.0
	press_tick = ticks
	observing = true

func short_press(code: int) -> void:
	send_key(code, true)
	await create_timer(0.002, true, false, true).timeout
	send_key(code, false)
	await frames(2)

func run() -> void:
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
	for weapon in ["serpent_spear", "guandao", "halberd"]:
		await pair("mounted", weapon)
		await reset_probe()
		await short_press(KEY_J)
		await frames(55)
		verify(weapon + " 2ms physical J starts exactly one real attack", start_events.size() == 1 and enemy.hp < 1000.0,
			{"starts": start_events, "damage": 1000.0 - enemy.hp, "impacts": impacts})
	# All remaining checks exercise shared input lifecycle on the actual RPG
	# controller with a mounted spear player, with no AI or persistent save.
	await pair("mounted", "serpent_spear")
	for boundary in ["pause", "inventory", "blur", "disable"]:
		await reset_probe()
		player.state = "hit"
		player.action_duration = 0.8
		player.action_time = 0.3
		await short_press(KEY_J)
		var queued = game.pending_combat_input == "light"
		if boundary == "pause":
			game.toggle_pause()
		elif boundary == "inventory":
			send_key(KEY_I, true)
			send_key(KEY_I, false)
		elif boundary == "blur":
			game._web_command(["blur"])
		else:
			game._set_enabled(false)
		await frames(2)
		var cleared = game.pending_combat_input == ""
		await frames(2)
		if boundary == "inventory":
			send_key(KEY_I, true)
			send_key(KEY_I, false)
		elif boundary in ["pause", "blur"]:
			game.toggle_pause()
		else:
			game._set_enabled(true)
		await frames(55)
		verify(boundary + " clears queued J and does not replay it on resume", queued and cleared and start_events.is_empty(),
			{"was_queued": queued, "cleared": cleared, "starts": start_events, "paused_after": game.paused})
	await reset_probe()
	player.state = "hit"
	player.action_duration = 0.8
	player.action_time = 0.3
	await short_press(KEY_J)
	await frames(55)
	verify("queued input expires before a long hit recovery", start_events.is_empty() and game.pending_combat_input == "",
		{"starts": start_events, "pending": game.pending_combat_input})
	for code in [KEY_K, KEY_Q, KEY_E, KEY_U, KEY_SPACE]:
		await reset_probe()
		if code == KEY_U:
			player.energy = 100.0 # Explicit native state fixture to test cancel gate.
		await short_press(KEY_J)
		for i in 6:
			if player.state == "attack" and not player.attack.is_empty(): break
			await frames(1)
		verify("pre-cancel J begins for " + OS.get_keycode_string(code), player.state == "attack" and not player.attack.is_empty(), {"state": player.state, "pending": game.pending_combat_input})
		if player.state != "attack" or player.attack.is_empty(): continue
		for i in 80:
			if player.action_time >= float(player.attack.active.y) + 0.085:
				break
			await frames(1)
		var old_time = player.action_time
		var old_duration = player.action_duration
		await short_press(code)
		await frames(2)
		var switched = (player.state == "attack" and bool(player.attack.get("heavy", false))) if code == KEY_K else (player.state == "skill" if code in [KEY_Q, KEY_E] else (player.state == "ultimate" if code == KEY_U else player.mount_charge_time > 0.0))
		verify("normal recovery can chain " + OS.get_keycode_string(code), switched and old_time < old_duration,
			{"request_time": old_time, "full_normal_duration": old_duration, "after_state": player.state,
			"after_clip": player.current_clip, "stamina": player.stamina, "energy": player.energy, "mount_charge": player.mount_charge_time})
	await reset_probe()
	await short_press(KEY_J)
	for i in 6:
		if player.state == "attack" and not player.attack.is_empty(): break
		await frames(1)
	for i in 80:
		if player.action_time >= float(player.attack.active.y) + 0.085:
			break
		await frames(1)
	var before_stamina = player.stamina
	Input.action_press("move_down")
	await short_press(KEY_SPACE)
	await frames(2)
	Input.action_release("move_down")
	verify("reverse Space is refused without cancelling normal or spending stamina", player.state == "attack" and player.mount_charge_time == 0.0 and is_equal_approx(player.stamina, before_stamina),
		{"state": player.state, "stamina_before": before_stamina, "stamina_after": player.stamina, "charge": player.mount_charge_time})
	# Solid wall blocks ordinary move_and_slide; also measure whether the real
	# resolver can incorrectly hit the body through it.
	var wall = StaticBody3D.new()
	var wc = CollisionShape3D.new()
	var ws = BoxShape3D.new()
	ws.size = Vector3(8, 5, 0.35)
	wc.shape = ws
	wall.position = Vector3(0, 2.5, 1.45)
	wall.add_child(wc)
	game.add_child(wall)
	for weapon in ["serpent_spear", "guandao", "halberd"]:
		await pair("mounted", weapon)
		await reset_probe(3.2)
		await short_press(KEY_J)
		var furthest = player.position.z
		for i in 70:
			await frames(1)
			furthest = maxf(furthest, player.position.z)
		verify(weapon + " auto step respects solid wall collision", furthest < 0.67,
			{"furthest_position_z": furthest, "wall_near_face": 1.275, "body_radius": 0.62})
		verify(weapon + " cannot deal damage through solid wall", enemy.hp == 1000.0,
			{"damage": 1000.0 - enemy.hp, "impacts": impacts})
	var report = {"completed": true, "checks": assertions.size(), "failures": life_failures,
		"passed": life_failures.is_empty(), "results": assertions,
		"fixture": "Real physical input events on inherited RPG controller and real imported actors, stationary unguarded native target; world/AI/HUD/persistence isolated. Energy100 only for explicit native U gate fixture."}
	var out = FileAccess.open("/private/tmp/wenfeng-responsiveness-lifecycle-regression.json", FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "\t"))
	print("LIFECYCLE DONE ", assertions.size(), " checks ", life_failures.size(), " failures")
	quit(0 if life_failures.is_empty() else 1)
