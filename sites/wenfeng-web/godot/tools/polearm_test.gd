extends SceneTree
const Roster = preload("res://scripts/roster.gd")
const POLEARM_IDS = ["guanyu", "zhangfei", "lubu"]

var game: Node3D
var checks: Array = []
var failures: Array = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, condition: bool) -> void:
	checks.append(label)
	if not condition:
		failures.append(label)
	print("PASS " if condition else "FAIL ", label)

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func setup_fight(id: String, distance_m: float) -> void:
	game.return_to_menu()
	game.select_character(id)
	game.select_opponent("zhaoyun")
	await frames(3)
	game.start_match()
	game.phase = "fight"
	game.ai_enabled = false
	game.player.enabled = true
	game.enemy.enabled = false
	game.player.position = Vector3(0, 0.015, 0)
	game.player.rotation.y = 0
	game.enemy.position = Vector3(0, 0.015, distance_m)
	game.enemy.rotation.y = PI
	game.enemy.set_physics_process(false)
	await frames(3)

func _capture_demos() -> void:
	root.size = Vector2i(1280, 800)
	for id in POLEARM_IDS:
		game.return_to_menu()
		game.opponent_id = ""
		game.select_character(id)
		await frames(12)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://qa/%s-menu.png" % id)
		game.hud.visible = false
		game.enemy.visible = false
		game.camera_override = true
		game.player.position = Vector3.ZERO
		game.player.rotation.y = 0.0
		game.player.set_physics_process(false)
		game.camera.position = Vector3(4.2, 2.7, 5.3)
		game.camera.fov = 43.0
		game.camera.look_at(Vector3(0, 1.35, 0))
		for clip in ["Idle", "Attack1", "Attack2", "Heavy", "Block"]:
			game.player.play_clip(clip, 0.0)
			game.player.animation_player.advance(0)
			var animation: Animation = game.player.animation_player.get_animation(game.player.animation_names[clip])
			game.player.animation_player.seek(animation.length * 0.48, true)
			game.player.animation_player.pause()
			game.player.skeleton.force_update_all_bone_transforms()
			game.player._update_two_hand_grip()
			await frames(3)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://qa/%s-%s.png" % [id, clip.to_lower()])
		game.hud.visible = true
		game.camera_override = false
		game.player.set_physics_process(true)
	# Match the user's rear view to confirm both plume-tip fans are gone.
	game.hud.visible = false
	game.enemy.visible = false
	game.camera_override = true
	game.player.set_physics_process(false)
	game.player.animation_player.stop()
	game.player.skeleton.reset_bone_poses()
	game.player.weapon_mesh.visible = false
	game.camera.position = Vector3(3.5, 2.4, -4.8)
	game.camera.fov = 37
	game.camera.look_at(Vector3(0, 1.2, 0))
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/lubu-repaired-back.png")

func _run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames(5)
	game.testing = true
	game.ai_enabled = false
	if "--visual-only" in OS.get_cmdline_user_args():
		await _capture_demos()
		game.queue_free()
		game = null
		await frames(3)
		quit()
		return
	for id in Roster.IDS:
		game.return_to_menu()
		game.select_character(id)
		await frames(4)
		check(id + " selectable", game.player.character_id == id)
		check(id + " imported animations", game.player.animation_names.size() >= 18)
		if id in POLEARM_IDS:
			check(id + " paired polearm", game.player.weapon_id == Roster.resolve_weapon(id, ""))
			game.player.set_physics_process(false)
			for clip in ["Idle", "Attack1", "Attack2", "Attack3", "Heavy", "Block"]:
				game.player.play_clip(clip, 0.0)
				game.player.animation_player.advance(0)
				game.player.animation_player.seek(0.25, true)
				game.player.animation_player.pause()
				game.player.skeleton.force_update_all_bone_transforms()
				game.player._update_two_hand_grip()
				var a: Vector3 = game.player.weapon_mesh.to_global(Vector3.ZERO)
				var b: Vector3 = game.player.weapon_mesh.to_global(Vector3.UP)
				var left: Vector3 = game.player.palm_position(true)
				var right: Vector3 = game.player.palm_position(false)
				check(id + " " + clip + " both palms on shaft", left.distance_to(Geometry3D.get_closest_point_to_segment(left, a, b)) < 0.035 and right.distance_to(Geometry3D.get_closest_point_to_segment(right, a, b)) < 0.035)
			game.player.set_physics_process(true)
	for id in Roster.IDS:
		for opponent in Roster.IDS:
			game.return_to_menu()
			game.select_character(id)
			game.select_opponent(opponent)
			await frames(2)
			check(id + " vs " + opponent, game.player.character_id == id and game.enemy.character_id == opponent and game.enemy.weapon_id in Roster.weapon_choices(opponent))
	for id in POLEARM_IDS:
		await setup_fight(id, 2.35)
		check(id + " light starts", game.player.request_light())
		await frames(100)
		check(id + " light deals damage at polearm distance", game.enemy.hp < 120)
		await setup_fight(id, 2.20)
		check(id + " heavy starts", game.player.request_heavy())
		await frames(120)
		check(id + " heavy deals damage", game.enemy.hp < 120)
		await setup_fight(id, 2.2)
		game.player.request_light()
		var highest_combo = 0
		for i in 180:
			if game.player.state == "attack":
				highest_combo = maxi(highest_combo, game.player.combo)
				game.player.request_light()
			await frames(1)
		check(id + " buffered light chain reaches third strike", highest_combo == 2)
		check(id + " light chain lands multiple hits", game.enemy.hp < 90)
		for skill in ["rush", "counter", "ultimate"]:
			await setup_fight(id, 1.65 if skill == "counter" else 2.6)
			if skill == "ultimate":
				game.player.energy = 100
				check(id + " U starts", game.player.request_ultimate())
			else:
				check(id + " " + skill + " starts", game.player.request_skill(skill))
			await frames(185 if skill == "ultimate" else 95)
			check(id + " " + skill + " deals real damage", game.enemy.hp < 120)
		await setup_fight(id, 3)
		game.player.stamina = 33
		check(id + " heavy respects polearm stamina cost", not game.player.request_heavy())
		game.player.energy = 99
		check(id + " ultimate energy gate", not game.player.request_ultimate())
	for id in POLEARM_IDS:
		game.return_to_menu()
		game.select_character("zhaoyun")
		game.select_opponent(id)
		await frames(3)
		game.start_match()
		game.phase = "fight"
		game.ai_enabled = true
		game.player.enabled = false
		game.enemy.enabled = true
		game.player.position = Vector3(0, .015, 0)
		game.enemy.position = Vector3(0, .015, 4.5)
		for i in 480:
			await frames(1)
			if game.player.hp < 120:
				break
		check(id + " AI approaches and lands an attack", game.player.hp < 120)
	if "--visual" in OS.get_cmdline_user_args():
		await _capture_demos()
	var output = FileAccess.open("res://qa/polearm-results.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}, "\t"))
	print("POLEARM QA ", checks.size(), " checks, ", failures.size(), " failures")
	game.queue_free()
	game = null
	await frames(3)
	quit(0 if failures.is_empty() else 1)
