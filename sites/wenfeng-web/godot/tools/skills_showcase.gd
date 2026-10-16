extends Node

var game: Node
var captures: Array = []
var snapshots: Array = []

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func picture(name: String) -> void:
	var path = "res://qa/" + name + ".png"
	await game.capture(path)
	captures.append(path)
	snapshots.append({"capture": path, "state": game.snapshot(),
		"skill_name": game.player.skill_name(game.player.skill_id) if game.player.skill_id != "" else "",
		"clip": game.player.current_clip})
	print("CAPTURE " + name)

func ready_fight(gap = 2.45) -> void:
	game.phase = "fight"
	game.round_time = 76.0
	game.ai_enabled = false
	game.skill_fx.clear()
	for fighter in [game.player, game.enemy]:
		fighter.reset_fighter()
		fighter.enabled = true
		fighter.energy = 100.0
	game.player.position = Vector3(0, 0.015, gap * 0.5)
	game.enemy.position = Vector3(0, 0.015, -gap * 0.5)
	game.player.rotation.y = PI
	game.enemy.rotation.y = 0.0
	game.camera_override = true
	game.camera.position = Vector3(5.9, 3.6, 6.5)
	game.camera.fov = 48.0
	game.camera.look_at(Vector3(0, 0.96, 0))
	game.enemy.enabled = false

func showcase_character(character: String, weapon: String) -> void:
	game.return_to_menu()
	game.select_character(character)
	game.select_weapon(weapon)
	await frames(8)
	await picture(character + "-role-menu")
	ready_fight()
	await frames(15)
	await picture(character + "-skills-ready")
	game.player.request_skill("rush")
	await frames(12 if character == "zhaoyun" else 23)
	await picture(character + "-skill-rush-windup")
	await frames(9 if character == "zhaoyun" else 10)
	await picture(character + "-skill-rush")
	await frames(65)
	ready_fight(2.15)
	if character == "zhaoyun":
		game.player.input_move = Vector3.RIGHT
	else:
		game.enemy.state = "block"
		game.enemy.action_time = 0.5
		game.enemy.play_clip("Block", 0.0)
	game.player.request_skill("counter")
	game.player.input_move = Vector3.ZERO
	await frames(11 if character == "zhaoyun" else 19)
	await picture(character + "-skill-e-start")
	# E is an active evasive cut / radial guard break. No simulated incoming
	# attack is needed to trigger either role's action.
	await frames(17 if character == "zhaoyun" else 10)
	await picture(character + "-skill-e-strike")
	await frames(65)
	ready_fight(2.45)
	await frames(8)
	game.player.request_ultimate()
	await frames(19 if character == "zhaoyun" else 43)
	await picture(character + "-ultimate-charge")
	await frames(23)
	await picture(character + "-ultimate-release")
	await frames(85 if character == "zhaoyun" else 16)
	await picture(character + "-ultimate-finisher")
	await frames(70)

func run(target: Node) -> void:
	game = target
	game.testing = true
	game.ai_enabled = false
	game.fx.muted = true
	Engine.time_scale = 1.0
	await RenderingServer.frame_post_draw
	await frames(40)
	await showcase_character("zhaoyun", "sword")
	await showcase_character("machao", "saber")
	var file = FileAccess.open("res://qa/skills-showcase.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": true, "captures": captures, "snapshots": snapshots}, "\t"))
	print("DUEL_SKILLS_SHOWCASE=PASS CAPTURES=" + str(captures.size()))
	get_tree().quit()
