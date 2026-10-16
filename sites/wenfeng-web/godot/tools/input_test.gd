extends Node

var game: Node
var results: Array = []

func frames(count: int) -> void:
	var simulated = 0.0
	while simulated < count / 60.0 - 0.00001:
		await get_tree().physics_frame
		simulated += get_physics_process_delta_time()

func key(code: int, down: bool) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: int) -> void:
	key(code, true)
	await frames(2)
	key(code, false)
	await frames(2)
	await get_tree().process_frame
	await get_tree().process_frame

func click(at: Vector2, button = MOUSE_BUTTON_LEFT) -> void:
	var motion = InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	for down in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = at
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame
		await get_tree().process_frame
	await frames(3)

func check(value: bool, title: String) -> void:
	results.append({"name": title, "passed": value})
	print(("PASS " if value else "FAIL ") + title)

func position_pair(gap = 1.30) -> void:
	for fighter in [game.player, game.enemy]:
		fighter.reset_fighter()
		fighter.enabled = true
	game.player.position = Vector3(0, 0.015, gap * 0.5)
	game.enemy.position = Vector3(0, 0.015, -gap * 0.5)
	game.player.rotation.y = PI
	game.enemy.rotation.y = 0
	game._update_camera(1.0, true)

func run(target: Node) -> void:
	game = target
	process_mode = Node.PROCESS_MODE_ALWAYS
	game.ai_enabled = false
	game.fx.muted = true
	await RenderingServer.frame_post_draw
	await frames(40)
	await click(Vector2(320, 345))
	check(game.character_id == "machao" and game.player.character_id == "machao", "menu mouse selects Ma Chao")
	await click(Vector2(320, 443))
	check(game.weapon_id == "saber" and game.player.weapon_id == "saber", "menu mouse selects saber")
	await click(Vector2(100, 532))
	check(game.difficulty == 0, "menu mouse selects difficulty")
	await click(Vector2(220, 632))
	check(game.phase == "countdown", "start button enters countdown")
	await frames(172)
	check(game.phase == "fight", "countdown starts playable fight")
	position_pair(4.5)
	await frames(4)
	var origin = game.player.position
	key(KEY_W, true)
	await frames(23)
	key(KEY_W, false)
	await frames(4)
	check(game.player.position.distance_to(origin) > 0.7, "physical W key moves fighter")
	position_pair()
	await tap(KEY_J)
	await frames(54)
	check(game.enemy.hp < 120, "physical J key animates and damages opponent")
	position_pair()
	await tap(KEY_K)
	await frames(74)
	check(game.enemy.hp < 95, "physical K key performs heavy attack")
	position_pair()
	await click(Vector2(1100, 600))
	await frames(54)
	check(game.enemy.hp < 120, "left mouse button performs light attack")
	position_pair()
	await click(Vector2(1100, 600), MOUSE_BUTTON_RIGHT)
	await frames(74)
	check(game.enemy.hp < 95, "right mouse button performs heavy attack")
	position_pair()
	origin = game.player.position
	await tap(KEY_SPACE)
	await frames(35)
	check(game.player.position.distance_to(origin) > 1.0 and game.player.stamina < 90, "physical Space key dodges and spends stamina")
	position_pair()
	key(KEY_L, true)
	await frames(24)
	check(game.player.state == "block", "holding physical L key raises guard")
	game.enemy.request_light()
	await frames(38)
	check(game.player.hp == 120.0 and game.player.stamina < 95, "keyboard guard blocks AI strike")
	key(KEY_L, false)
	await frames(10)
	check(game.player.state == "idle", "releasing L lowers guard")
	key(KEY_SHIFT, true)
	await frames(8)
	check(game.player.state == "block", "physical Shift also raises guard")
	key(KEY_SHIFT, false)
	await frames(5)
	position_pair(4.2)
	await tap(KEY_Q)
	check(game.player.skill_id == "rush" and game.player.cooldowns.rush > 5.0, "physical Q performs rush skill")
	await frames(65)
	position_pair()
	await tap(KEY_E)
	check(game.player.state == "skill" and game.player.skill_id == "counter" and game.player.cooldowns.counter > 7.5, "physical E performs selected role utility skill")
	await frames(60)
	position_pair(2.4)
	game.player.energy = 100.0
	await tap(KEY_U)
	check(game.player.state == "ultimate" and game.player.skill_stage == "windup" and game.player.energy == 0.0, "physical U spends energy and charges ultimate")
	await frames(180)
	await tap(KEY_M)
	check(not game.fx.muted, "physical M enables sound")
	await tap(KEY_M)
	check(game.fx.muted, "physical M mutes sound")
	await tap(KEY_ESCAPE)
	check(game.paused and game.hud.pause_panel.visible, "physical Esc opens pause panel")
	var clock = game.round_time
	await frames(8)
	check(game.round_time == clock, "pause stops round clock")
	await click(Vector2(640, 370))
	check(not game.paused and not get_tree().paused, "resume button restores play")
	await tap(KEY_ESCAPE)
	await click(Vector2(640, 506))
	check(game.phase == "menu" and not game.paused, "pause menu returns to character selection")
	await tap(KEY_ENTER)
	check(game.phase == "countdown", "physical Enter starts match")
	await tap(KEY_R)
	check(game.phase == "countdown" and game.scores == [0, 0], "physical R restarts match")
	if DisplayServer.get_name() != "headless":
		await tap(KEY_F)
		await frames(42)
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "physical F enables fullscreen")
		await game.capture("res://qa/fullscreen.png")
		await tap(KEY_F)
		await frames(36)
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "physical F restores window")
	var passed = true
	for result in results:
		passed = passed and result.passed
	var file = FileAccess.open("res://qa/input-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": passed, "checks": results.size(), "results": results,
		"render": {"fps": Performance.get_monitor(Performance.TIME_FPS),
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}}, "\t"))
	print("DUEL_INPUT=" + ("PASS" if passed else "FAIL") + " CHECKS=" + str(results.size()))
	get_tree().quit(0 if passed else 1)
