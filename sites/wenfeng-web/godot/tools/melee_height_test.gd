extends SceneTree

## Actual Main/actors/animations and real jump clocks. No strike geometry or
## profiles are mocked. Contact traces distinguish a miss from a generous
## horizontal slash and protect that existing close-range allowance.
var game: Node3D
var rows: Array = []
var failures: Array[String] = []
var impacts: Array = []
var active_trace: Array = []
var observing = false
var report = "/private/tmp/wenfeng-melee-height-latest.json"

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for index in count: await physics_frame

func geometry() -> Dictionary:
	var attacker = game.player
	var defender = game.enemy
	var low = defender.thrust_body_low()
	var high = defender.thrust_body_high()
	var blade = Geometry3D.get_closest_points_between_segments(attacker.blade_base(), attacker.blade_tip(), low, high)
	var sweep = Geometry3D.get_closest_points_between_segments(attacker.previous_tip, attacker.blade_tip(), low, high)
	return {"action_time": attacker.action_time, "player_y": attacker.position.y, "enemy_y": defender.position.y,
		"airborne": attacker.jump_status().airborne,
		"surface_clearance": minf(blade[0].distance_to(blade[1]), sweep[0].distance_to(sweep[1])) - defender.thrust_body_radius()}

func impact(_fighter: Node, outcome: String, _at: Vector3) -> void:
	if not observing: return
	var row = geometry()
	row["outcome"] = outcome
	impacts.append(row)

func check(label: String, passed: bool, detail: Dictionary) -> void:
	rows.append({"case": label, "passed": passed, "detail": detail})
	print("PASS " if passed else "FAIL ", label, " ", JSON.stringify(detail))
	if not passed: failures.append(label)

func setup(role: String, gap: float) -> void:
	observing = false
	game.return_to_menu()
	game.select_combat_mode("foot")
	game.select_character(role)
	game.select_opponent("zhaoyun")
	await frames(3)
	game.start_match()
	game.phase = "fight"
	game.ai_enabled = false
	game.player.enabled = true
	game.enemy.enabled = false
	game.enemy.set_physics_process(false)
	game.player.position = Vector3(0, 0.015, 0)
	game.enemy.position = Vector3(0, 0.015, gap)
	game.player.rotation.y = 0.0
	game.enemy.rotation.y = PI
	await frames(8)
	impacts.clear()
	active_trace.clear()
	game.enemy.impact_received.connect(impact)
	observing = true

func play_action(defense = "none", limit = 115) -> void:
	var guard_started = false
	for index in limit:
		await frames(1)
		if defense == "parry" and not guard_started and game.player.action_time >= 0.10:
			guard_started = true
			game.enemy.enabled = true
			game.enemy.set_physics_process(true)
			game.enemy.wants_block = true
		if game.player.state == "attack" and game.player.action_time >= game.player.attack.active.x and game.player.action_time <= game.player.attack.active.y:
			active_trace.append(geometry())
	observing = false

func details() -> Dictionary:
	return {"damage": 120.0 - game.enemy.hp, "parries": game.enemy.parries,
		"blocks": game.enemy.blocked_hits, "impacts": impacts.duplicate(true),
		"active_trace": active_trace.duplicate(true), "final_state": game.player.state}

func ground_normal(role: String, heavy: bool, gap: float) -> void:
	await setup(role, gap)
	var started = game.player.request_heavy() if heavy else game.player.request_light()
	await play_action()
	check(role + (" K" if heavy else " J") + " ground normal still damages", started and game.enemy.hp < 120.0, details())

func ground_defense(defense: String) -> void:
	await setup("xuchu", 1.1)
	if defense == "guard":
		game.enemy.enabled = true
		game.enemy.set_physics_process(true)
		game.enemy.wants_block = true
		await frames(25)
	var started = game.player.request_light()
	await play_action(defense)
	var defended = game.enemy.parries == 1 if defense == "parry" else game.enemy.blocked_hits == 1
	check("real ground " + defense + " remains effective", started and defended and game.enemy.hp == 120.0, details())

func airborne(defense: String, both_airborne = false) -> void:
	await setup("xuchu", 1.1)
	if defense == "guard" or both_airborne:
		game.enemy.enabled = true
		game.enemy.set_physics_process(true)
		game.enemy.wants_block = defense == "guard"
		await frames(25 if defense == "guard" else 4)
	var jumped = game.player.request_jump()
	var defender_jumped = game.enemy.request_jump() if both_airborne else true
	for index in 50:
		await frames(1)
		if game.player.jump_motion.airborne and game.player.jump_motion.flight_time >= 0.18: break
	var started = game.player.request_light()
	await play_action(defense)
	var detail = details()
	if both_airborne:
		var actual_contact = false
		for row in impacts:
			actual_contact = actual_contact or (bool(row.airborne) and float(row.surface_clearance) <= 0.07)
		check("actual same-height airborne blade contact still damages", jumped and defender_jumped and started and actual_contact and game.enemy.hp < 120.0, detail)
	else:
		if defense == "none":
			var minimum = INF
			for row in active_trace: minimum = minf(minimum, float(row.surface_clearance))
			detail["entire_active_minimum_surface_clearance"] = minimum
			check("separated airborne slash remains clear through whole active window", jumped and started and active_trace.size() >= 6 and minimum > 0.45, detail)
		check("separated airborne slash produces no " + defense + " damage/block/parry", jumped and started and game.enemy.hp == 120.0 and game.enemy.parries == 0 and game.enemy.blocked_hits == 0, detail)

func skill_case(role: String, id: String, category: String) -> void:
	await setup(role, 2.3)
	var started = game.player.request_skill(id)
	await play_action("none", 180)
	check(category + " skill keeps its existing damage path", started and game.enemy.hp < 120.0, details())

func run() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): report = arg.trim_prefix("--output=")
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.testing = true
	game.fx.muted = true
	game.ai_enabled = false
	await frames(5)
	for role in ["zhaoyun", "machao", "guanyu", "zhangfei", "lubu", "xuchu"]:
		for heavy in [false, true]:
			await ground_normal(role, heavy, 1.5 if role == "xuchu" else 2.3)
	# Preserve the original generous horizontal slash at touching range.
	await ground_normal("guanyu", false, 1.1)
	await ground_defense("guard")
	await ground_defense("parry")
	await airborne("none")
	await airborne("guard")
	await airborne("parry")
	await airborne("none", true)
	await skill_case("zhaoyun", "rush", "physical line")
	await skill_case("guanyu", "counter", "wave")
	await skill_case("zhangfei", "counter", "external radial")
	FileAccess.open(report, FileAccess.WRITE).store_string(JSON.stringify({"checks": rows.size(), "failures": failures, "cases": rows}, "\t"))
	game._reset_hit_feedback()
	print("MELEE_HEIGHT_DONE ", rows.size(), " checks ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
