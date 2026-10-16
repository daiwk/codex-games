extends Node

var game: Node

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func picture(name: String) -> void:
	await game.capture("res://qa/" + name + ".png")
	print("CAPTURE " + name)

func pose(clip: String, time: float, filename: String) -> void:
	var p = game.player
	p.enabled = false
	p.position = Vector3(0, 0.015, 0)
	p.rotation.y = 0.0
	p.play_clip(clip, 0.0)
	p.animation_player.seek(time, true)
	p.animation_player.pause()
	await frames(3)
	await picture(filename)

func ready_fight() -> void:
	game.phase = "fight"
	game.round_time = 84.0
	for f in [game.player, game.enemy]:
		f.reset_fighter()
		f.enabled = true
	game.player.position = Vector3(0, 0.015, 1.12)
	game.enemy.position = Vector3(0, 0.015, -1.12)
	game.player.rotation.y = PI
	game.enemy.rotation.y = 0.0
	game._update_camera(1, true)

func run(target: Node) -> void:
	game = target
	game.testing = true
	game.ai_enabled = false
	game.fx.muted = true
	await frames(40)
	await picture("menu")
	game.select_character("machao")
	game.select_weapon("saber")
	await frames(20)
	await picture("selection-machao")
	game.select_character("zhaoyun")
	game.select_weapon("sword")
	ready_fight()
	await frames(28)
	await picture("duel")
	game.player.request_light()
	await frames(13)
	await picture("light-attack")
	await frames(50)
	ready_fight()
	game.player.wants_block = true
	await frames(25)
	game.enemy.request_heavy()
	await frames(24)
	await picture("guard")
	await frames(60)
	game.toggle_pause()
	await frames(3)
	await picture("pause")
	game.toggle_pause()
	game.phase = "match_end"
	game.scores = [2, 1]
	for f in [game.player, game.enemy]:
		f.enabled = false
	await frames(3)
	await picture("results")
	game.hud.visible = false
	game.enemy.visible = false
	game.phase = "fight"
	game.camera_override = true
	game.camera.position = Vector3(2.7, 1.95, 3.45)
	game.camera.fov = 38
	game.camera.look_at(Vector3(0, 0.97, 0))
	for sample in [["Idle", 0.4, "idle"], ["Attack1", 0.22, "slash-a"], ["Attack2", 0.27, "slash-b"], ["Attack3", 0.7, "slash-c"], ["Block", 0.44, "block"], ["Run", 0.25, "run"], ["WalkBack", 0.4, "backstep"], ["StrafeLeft", 0.35, "sidestep"], ["Dodge", 0.3, "dodge"], ["Heavy", 0.6, "heavy"], ["Death", 2.35, "death"]]:
		await pose(sample[0], sample[1], "zhaoyun-" + sample[2])
	game.return_to_menu()
	game.select_character("machao")
	game.select_weapon("saber")
	game.phase = "fight"
	game.enemy.visible = false
	for sample in [["Idle", 0.4, "idle"], ["Attack1", 0.22, "slash-a"], ["Attack2", 0.27, "slash-b"], ["Attack3", 0.7, "slash-c"], ["Block", 0.44, "block"], ["Run", 0.25, "run"], ["WalkBack", 0.4, "backstep"], ["StrafeLeft", 0.35, "sidestep"], ["Dodge", 0.3, "dodge"], ["Heavy", 0.6, "heavy"], ["Death", 2.35, "death"]]:
		await pose(sample[0], sample[1], "machao-" + sample[2])
	print("DUEL_SHOWCASE=PASS")
	get_tree().quit()
