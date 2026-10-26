# Native isolated RPG regression. Run with --headless --path <godot> --script res://tools/responsiveness_test.gd.
# Real key events, real authored skeletons, real RPG hit resolver; no AI/world/save.
extends SceneTree

const Actor = preload("res://scripts/rpg_actor.gd")
const Controller = preload("res://tools/responsiveness_controller.gd")
var game: Node3D
var enemy: RPGActor
var player: RPGActor
var samples: Array = []
var results: Array = []
var start_events: Array = []
var impacts: Array = []
var first_active = -1.0
var observing = false
var ticks = 0
var press_tick = 0
var origin = Vector3.ZERO
var current: Dictionary = {}
var output_path = "/private/tmp/wenfeng-responsiveness-regression.json"

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i in count:
		await physics_frame
		ticks += 1

func point(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func start(_actor: Node, action: String) -> void:
	if observing and action in ["light", "heavy"]:
		start_events.append({"tick": ticks - press_tick, "combo": player.combo, "action": action,
			"duration": player.action_duration, "active": [player.attack.active.x, player.attack.active.y], "clip": player.current_clip})

func impact(_actor: Node, outcome: String, at: Vector3) -> void:
	if observing:
		impacts.append({"tick": ticks - press_tick, "seconds": float(ticks - press_tick) / 60.0,
			"action_time": player.action_time, "outcome": outcome, "position": point(at), "combo": player.combo})

func attempt(_actor: Node, data: Dictionary) -> void:
	if not observing:
		return
	if first_active < 0.0:
		first_active = float(ticks - press_tick) / 60.0
	var blade = Geometry3D.get_closest_points_between_segments(player.blade_base(), player.blade_tip(), enemy.thrust_body_low(), enemy.thrust_body_high())
	var sweep = Geometry3D.get_closest_points_between_segments(player.previous_tip, player.blade_tip(), enemy.thrust_body_low(), enemy.thrust_body_high())
	var offset = (enemy.position - player.position).slide(Vector3.UP)
	samples.append({"tick": ticks - press_tick, "action_time": player.action_time, "clip": player.current_clip,
		"animation_time": player.animation_player.current_animation_position,
		"gap": offset.length(), "facing_dot": offset.normalized().dot(player.forward()),
		"blade_body_distance": blade[0].distance_to(blade[1]), "sweep_body_distance": sweep[0].distance_to(sweep[1]),
		"base": point(player.blade_base()), "tip": point(player.blade_tip()), "position": point(player.position),
		"body_low": point(enemy.thrust_body_low()), "body_high": point(enemy.thrust_body_high()),
		"contact_active": player.contact_active, "latched": player.contact_latched,
		"retraction": player.contact_retraction, "shape": data.get("shape", "")})

func key(pressed: bool) -> void:
	var e = InputEventKey.new()
	e.physical_keycode = KEY_J
	e.keycode = KEY_J
	e.pressed = pressed
	Input.parse_input_event(e)

func pair(mode: String, weapon: String) -> void:
	if is_instance_valid(player):
		game.enemies.clear()
		player.queue_free()
		enemy.queue_free()
		await frames(2)
	player = Actor.new()
	player.character_id = "zhaoyun"
	player.weapon_id = weapon
	player.mounted = mode == "mounted"
	player.is_player = true
	player.position = Vector3(0, 0.03, -4)
	game.add_child(player)
	enemy = Actor.new()
	enemy.character_id = "zhaoyun"
	enemy.weapon_id = "serpent_spear"
	enemy.mounted = mode == "mounted"
	enemy.set_meta("rpg_id", "raider_qa")
	enemy.position = Vector3(0, 0.03, 4)
	game.add_child(enemy)
	enemy.apply_stats(1000.0, 1.0, 0.0, true)
	enemy.enabled = false
	enemy.set_physics_process(false)
	game.player = player
	game.enemies["raider_qa"] = enemy
	game.locked_target_id = "raider_qa"
	player.strike_requested.connect(attempt)
	player.strike_requested.connect(game._resolve_strike)
	player.action_started.connect(start)
	enemy.impact_received.connect(impact)
	await frames(5)

func exercise(mode: String, weapon: String, gap: float, angle = 0.0, busy = "", busy_remaining = 0.1) -> void:
	observing = false
	key(false)
	player.reset_fighter()
	enemy.reset_fighter()
	enemy.apply_stats(1000.0, 1.0, 0.0, true)
	player.enabled = true
	enemy.enabled = false
	enemy.set_physics_process(false)
	player.position = Vector3(0, 0.015, 0)
	enemy.position = Vector3(0, 0.015, gap)
	player.rotation.y = angle
	enemy.rotation.y = PI
	player.input_move = Vector3.ZERO
	player.velocity = Vector3.ZERO
	game.locked_target_id = "raider_qa"
	game.paused = false
	game.phase = "explore"
	await frames(12)
	# A native fixture may select initial actor state; J itself always travels
	# through a physical-key input event and the original controller callback.
	if busy != "":
		player.state = busy
		player.action_duration = 0.6
		player.action_time = player.action_duration - busy_remaining
	observing = true
	samples = []
	start_events = []
	impacts = []
	first_active = -1.0
	press_tick = ticks
	origin = player.position
	var actual_start = {"position": point(player.position), "target_position": point(enemy.position), "gap": player.position.distance_to(enemy.position), "on_floor": player.is_on_floor(), "velocity": point(player.velocity)}
	var before_hp = enemy.hp
	key(true)
	await frames(2)
	key(false)
	var recovered = -1.0
	for i in 105:
		await frames(1)
		if recovered < 0.0 and not start_events.is_empty() and player.state == "idle":
			recovered = float(ticks - press_tick) / 60.0
	observing = false
	var minimum = INF
	for sample in samples:
		minimum = minf(minimum, minf(sample.blade_body_distance, sample.sweep_body_distance))
	var row = {"mode": mode, "weapon": weapon, "initial_gap": gap, "initial_angle_deg": rad_to_deg(angle),
		"initial_state": "idle" if busy == "" else busy, "busy_remaining": busy_remaining if busy != "" else 0.0,
		"actual_start": actual_start, "fixture_valid": bool(actual_start.on_floor) and absf(float(actual_start.position[1])) < 0.04 and Vector3(actual_start.position[0], 0, actual_start.position[2]).length() < 0.05,
		"single_real_j": true, "accepted": not start_events.is_empty(), "starts": start_events,
		"damage": before_hp - enemy.hp, "impacts": impacts, "first_active_seconds": first_active,
		"recovered_seconds": recovered, "travel": point(player.position - origin),
		"min_active_blade_capsule_axis_distance": minimum if is_finite(minimum) else null,
		"samples": samples}
	results.append(row)
	print("CASE ", JSON.stringify({"mode": mode,"weapon":weapon,"gap":gap,"angle":rad_to_deg(angle),"busy":busy,"accepted":row.accepted,"damage":row.damage,"active":first_active,"contact":row.min_active_blade_capsule_axis_distance,"travel":row.travel}))
	write_report(false)

func write_report(completed: bool) -> void:
	var file = FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"completed": completed,
		"scope": "Real RPG input controller, real skeleton and RPG resolver; isolated stationary unguarded enemy, no AI, real InputEventKey J, normal 60Hz clock. Distances are centre-to-centre metres. Busy initial state is explicitly a test fixture.",
		"physics_ticks_per_second": Engine.physics_ticks_per_second, "time_scale": Engine.time_scale,
		"cases": results}, "\t"))

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
	for mode in ["mounted", "foot"]:
		for weapon in ["serpent_spear", "guandao", "halberd"]:
			await pair(mode, weapon)
			for gap in [1.24, 1.6, 2.1, 2.6, 3.2]:
				await exercise(mode, weapon, gap)
			await exercise(mode, weapon, 2.1, PI * 0.5)
			await exercise(mode, weapon, 2.1, 0.0, "hit", 0.08)
	write_report(true)
	var rejected: Array = []
	for row in results:
		if not row.get("fixture_valid", false) or not row.accepted or not is_equal_approx(float(row.damage), 18.0):
			rejected.append({"mode":row.mode,"weapon":row.weapon,"gap":row.initial_gap,"state":row.initial_state,"accepted":row.accepted,"damage":row.damage,"fixture_valid":row.get("fixture_valid", false)})
	var report = JSON.parse_string(FileAccess.get_file_as_string(output_path))
	report["matrix_validation"] = {"passed":results.size()==42 and rejected.is_empty(),"expected_cases":42,"actual_cases":results.size(),"failures":rejected}
	var file = FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("RESPONSIVENESS MATRIX DONE ", results.size(), " ", rejected.size(), " failures")
	quit(0 if results.size()==42 and rejected.is_empty() else 1)
