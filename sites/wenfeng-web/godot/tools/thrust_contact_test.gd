extends SceneTree

## Real skeleton/weapon regression: no mocked combat or weapon transforms.
var game: Node3D
var failures: Array[String] = []
var checks = 0
var metrics: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks += 1
	print("PASS " if passed else "FAIL ", label)
	if not passed:
		failures.append(label)

func frames(count: int) -> void:
	for index in count:
		await physics_frame

func setup(id: String, mode: String, distance_m: float) -> void:
	game.return_to_menu()
	game.select_combat_mode(mode)
	game.select_character(id)
	game.select_opponent("zhaoyun")
	await frames(3)
	game.start_match()
	game.phase = "fight"
	game.ai_enabled = false
	game.player.enabled = true
	game.enemy.enabled = false
	game.enemy.set_physics_process(false)
	game.player.position = Vector3(0, 0.015, 0)
	game.player.rotation.y = 0.0
	game.enemy.position = Vector3(0, 0.015, distance_m)
	game.enemy.rotation.y = PI
	await frames(3)
	metrics = {"depth": 0.0, "grip": 0.0, "latched": false, "hits": 0, "hp": 120.0}
	game.player.skeleton.skeleton_updated.connect(sample)
	game.enemy.impact_received.connect(observe_impact)

func sample() -> void:
	if not is_instance_valid(game):
		return
	var fighter = game.player
	if not fighter.is_physical_thrust() or fighter.state not in ["attack", "skill", "ultimate"]:
		return
	var base: Vector3 = fighter.palm_position(false)
	var tip: Vector3 = fighter.blade_tip()
	var axis = (tip - base).normalized()
	var low: Vector3 = game.enemy.thrust_body_low()
	var high: Vector3 = game.enemy.thrust_body_high()
	var radius: float = game.enemy.thrust_body_radius()
	var pair = Geometry3D.get_closest_points_between_segments(base - axis * 5, tip + axis * 5, low, high)
	var sideways = pair[0].distance_to(pair[1])
	if sideways < radius:
		var entry = (pair[0] - base).dot(axis) - sqrt(maxf(0.0, radius * radius - sideways * sideways))
		if entry >= 0.0:
			metrics.depth = maxf(metrics.depth, (tip - base).dot(axis) - entry)
	var tail: Vector3 = fighter.weapon_mesh.to_global(Vector3.ZERO)
	var end: Vector3 = fighter.weapon_mesh.to_global(Vector3.UP)
	for left in [false, true]:
		var palm: Vector3 = fighter.palm_position(left)
		metrics.grip = maxf(metrics.grip, palm.distance_to(Geometry3D.get_closest_point_to_segment(palm, tail, end)))
	metrics.latched = metrics.latched or fighter.contact_latched

func observe_impact(_fighter: Node, outcome: String, _point: Vector3) -> void:
	# Mixed U now has a real radial first beat followed by a physical thrust.
	# Count at contact, not on a later physical frame that merely sees lower HP.
	if outcome in ["hit", "heavy_hit"] and game.player.is_physical_thrust():
		metrics.hits += 1
	metrics.hp = game.enemy.hp

func exercise(id: String, mode: String, distance_m: float, action: String) -> void:
	await setup(id, mode, distance_m)
	var title = "%s %s %.2fm %s" % [id, mode, distance_m, action]
	var accepted = false
	if action == "light":
		accepted = game.player.request_light()
	elif action == "heavy":
		accepted = game.player.request_heavy()
	elif action == "ultimate":
		game.player.energy = 100
		accepted = game.player.request_ultimate()
	else:
		accepted = game.player.request_skill(action)
	check(title + " starts", accepted)
	await frames(185 if action == "ultimate" else 100)
	print("METRICS ", title, " ", JSON.stringify(metrics))
	check(title + " no deep penetration", metrics.depth < 0.04)
	check(title + " hands remain on shaft", metrics.grip < 0.035)
	check(title + " recovers", game.player.state == "idle" and not game.player.contact_latched)
	if distance_m >= 1.5 and distance_m <= 2.3:
		check(title + " real contact and damage", metrics.latched and game.enemy.hp < 120.0)
	if action == "ultimate" or (action == "rush" and game.player.skill_profile("rush").has("hits")):
		var expected_thrusts = 0
		for hit in game.player.skill_profile(action).hits:
			if hit.get("shape", "line") == "line":
				expected_thrusts += 1
		check(title + " separate physical contacts for every line strike", metrics.hits == expected_thrusts)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.testing = true
	game.fx.muted = true
	game.ai_enabled = false
	await frames(4)
	for mode in ["foot", "mounted"]:
		for id in ["zhaoyun", "machao", "zhangfei"]:
			var normal_distance = 2.1 if mode == "mounted" else 2.3
			for distance_m in [1.24, normal_distance]:
				await exercise(id, mode, distance_m, "light")
			await exercise(id, mode, normal_distance, "heavy")
			await exercise(id, mode, 2.3, "rush")
			await exercise(id, mode, 2.3, "ultimate")
	await exercise("zhaoyun", "foot", 1.65, "counter")
	# A weapon's broad reach alone must never create a ranged normal-attack hit.
	await setup("zhaoyun", "foot", 3.6)
	game.player.request_light()
	await frames(100)
	check("far normal thrust misses outside real blade travel", game.enemy.hp == 120.0 and not metrics.latched)
	# Guard/parry/evade take the same physical path but retain their outcomes.
	for defense in ["guard", "parry", "evade"]:
		await setup("zhaoyun", "foot", 1.8)
		game.enemy.state = "dodge" if defense == "evade" else "block"
		game.enemy.action_time = 0.12 if defense in ["parry", "evade"] else 0.5
		game.player.request_light()
		await frames(100)
		check(defense + " does not take normal damage", game.enemy.hp == 120.0)
		if defense == "guard":
			check("guard produces contact", game.enemy.blocked_hits == 1 and metrics.latched)
		elif defense == "parry":
			check("parry produces one counter and releases latch", game.enemy.parries == 1 and game.player.state == "idle" and not game.player.contact_latched)
		else:
			check("evade has no contact latch", game.enemy.dodged_hits == 1 and not metrics.latched)
	print("THRUST CONTACT QA ", checks, " checks, ", failures.size(), " failures")
	game.queue_free()
	game = null
	await frames(3)
	quit(0 if failures.is_empty() else 1)
