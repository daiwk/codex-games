extends "res://tools/responsiveness_test.gd"

var wall_checks: Array = []
var wall_failures: Array = []

func verify(label: String, pass_value: bool, detail: Variant) -> void:
	wall_checks.append({"label":label,"passed":pass_value,"detail":detail})
	print("PASS " if pass_value else "FAIL ",label," ",JSON.stringify(detail))
	if not pass_value:wall_failures.append(label)

func obstacle(at: Vector3, size: Vector3) -> StaticBody3D:
	var body = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = at
	body.add_child(shape)
	game.add_child(body)
	return body

func run() -> void:
	output_path = "/private/tmp/wenfeng-response-wall-final-cases.json"
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
		await exercise("mounted", weapon, 3.2)
		verify(weapon + " clear 3.2m single J retains actual hit", results.back().damage == 18.0, {"damage":results.back().damage,"travel":results.back().travel,"mincontact":results.back().min_active_blade_capsule_axis_distance})
		var wall = obstacle(Vector3(0, 2.5, 1.45), Vector3(8, 5, 0.35))
		await frames(2)
		await exercise("mounted", weapon, 3.2)
		verify(weapon + " full static wall stops melee damage", results.back().damage == 0.0 and player.position.z < 0.67, {"damage":results.back().damage,"position":point(player.position),"mincontact":results.back().min_active_blade_capsule_axis_distance})
		wall.queue_free()
		await frames(2)
	await pair("mounted", "guandao")
	var low = obstacle(Vector3(0, 0.35, 1.45), Vector3(8, 0.7, 0.35))
	await frames(2)
	await exercise("mounted", "guandao", 3.2)
	verify("blade can strike above low barrier without wall-ray false block", results.back().damage == 18.0, {"damage":results.back().damage,"mincontact":results.back().min_active_blade_capsule_axis_distance,"barrier_height":0.7,"position":point(player.position)})
	low.queue_free()
	await frames(2)
	var side = obstacle(Vector3(2.5, 2.5, 1.45), Vector3(0.35, 5, 0.35))
	await frames(2)
	await exercise("mounted", "guandao", 3.2)
	verify("off-route side obstacle does not block a clear blade contact", results.back().damage == 18.0, {"damage":results.back().damage,"mincontact":results.back().min_active_blade_capsule_axis_distance,"obstacle_position":point(side.position)})
	var out = FileAccess.open("/private/tmp/wenfeng-response-wall-final.json", FileAccess.WRITE)
	out.store_string(JSON.stringify({"completed":true,"passed":wall_failures.is_empty(),"checks":wall_checks.size(),"failures":wall_failures,"results":wall_checks,"raw_cases":"/private/tmp/wenfeng-response-wall-final-cases.json","scope":"Focused post-fix static-wall occlusion, three clear and three full-wall actual key-J scenes, plus one low obstacle and one off-route side obstacle. This does not retest all earlier lifecycle cases."}, "\t"))
	print("WALL FINAL DONE ",wall_checks.size()," checks ",wall_failures.size()," failures")
	quit(0 if wall_failures.is_empty() else 1)
