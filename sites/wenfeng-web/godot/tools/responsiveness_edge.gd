extends "res://tools/responsiveness_test.gd"

func run() -> void:
	output_path = "/private/tmp/wenfeng-response-final-edge.json"
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
		for gap in [3.4, 4.0]:
			await exercise("mounted", weapon, gap)
	write_report(true)
	print("FINAL BOUNDS DONE ", results.size())
	quit(0)
