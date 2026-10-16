extends Node

var game: Node
var captured: Array = []

func frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func picture(name: String) -> void:
	await game.capture("res://qa/" + name + ".png")
	captured.append(name)
	print("ASSET_CAPTURE " + name)

func head_index() -> int:
	for i in game.player.skeleton.get_bone_count():
		if String(game.player.skeleton.get_bone_name(i)).ends_with("Head"):
			return i
	return -1

func close_pose(clip: String, time: float) -> void:
	var p = game.player
	assert(head_index() >= 0, "Imported character needs a Head bone for close-up review")
	p.enabled = false
	p.position = Vector3(0, 0.015, 0)
	p.rotation.y = 0.0
	p.play_clip(clip, 0.0)
	p.animation_player.seek(time, true)
	p.animation_player.pause()
	await frames(3)
	var h: Vector3 = p.skeleton.to_global(p.skeleton.get_bone_global_pose(head_index()).origin)
	game.camera.position = h + Vector3(0.38, 0.12, 1.00)
	game.camera.fov = 38
	game.camera.look_at(h + Vector3.UP * 0.025)
	await frames(3)

func run(target: Node) -> void:
	game = target
	game.testing = true
	game.ai_enabled = false
	game.fx.muted = true
	game.camera_override = true
	game.hud.visible = false
	for character in ["zhaoyun", "machao"]:
		game.phase = "menu"
		game.select_character(character)
		game.select_weapon("sword" if character == "zhaoyun" else "saber")
		game.enemy.visible = false
		game.phase = "fight"
		for sample in [["Idle", 0.4, "ready"], ["Attack1", 0.2, "attack"], ["Heavy", 0.5, "raised-arm"], ["Block", 0.44, "guard"]]:
			await close_pose(sample[0], sample[1])
			await picture(character + "-head-" + sample[2])
		for sample in [[Vector3.UP, -0.70, "left"], [Vector3.UP, 0.70, "right"], [Vector3.RIGHT, 0.40, "nod"]]:
			await close_pose("Idle", 0.4)
			var skeleton: Skeleton3D = game.player.skeleton
			var index = head_index()
			var head_world = skeleton.global_transform * skeleton.get_bone_global_pose(index)
			var local_axis: Vector3 = head_world.basis.inverse() * sample[0]
			skeleton.set_bone_pose_rotation(index, skeleton.get_bone_pose_rotation(index) * Quaternion(local_axis.normalized(), sample[1]))
			await frames(4)
			await picture(character + "-head-" + sample[2])
		game.camera.position = Vector3(2.7, 1.95, 3.45)
		game.camera.fov = 38
		game.camera.look_at(Vector3(0, 0.97, 0))
		game.player.reset_fighter()
		game.player.rotation.y = 0.0
		game.enemy.position = Vector3(3.5, 0.015, -2)
		game.player.enabled = true
		for i in 5:
			await frames(12)
			await picture(character + "-pivot-" + str(i))
	var file = FileAccess.open("res://qa/asset-review-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures": captured, "count": captured.size()}, "\t"))
	print("DUEL_ASSET_REVIEW=PASS CAPTURES=" + str(captured.size()))
	get_tree().quit()
