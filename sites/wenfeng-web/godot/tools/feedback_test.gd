extends SceneTree

## Presentation contracts plus real controller J/K contacts. Run only after
## import/integration; --rpg-test prevents loading/writing a real RPG save.
const Feedback = preload("res://scripts/impact_feedback.gd")
const CameraMotion = preload("res://scripts/combat_camera.gd")
var game: Node3D
var enemy: DuelFighter
var controller = ""
var last_impact: Dictionary = {}
var pending_transition = ""
var checks = 0
var failures: Array[String] = []
var rows: Array = []

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://qa"))
	if "--rpg-test" not in OS.get_cmdline_user_args():
		push_error("Use -- --rpg-test to isolate RPG save data")
		quit(2)
		return
	call_deferred("run")

func check(label: String, condition: bool, details: Variant = null) -> void:
	checks += 1
	rows.append({"label": label, "passed": condition, "details": details})
	print("PASS " if condition else "FAIL ", label, " ", details if details != null else "")
	if not condition:
		failures.append(label)

func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func wall_wait(milliseconds: int) -> void:
	var until = Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < until:
		await process_frame

func feedback_contract() -> void:
	var feedback = Feedback.new()
	feedback.reset()
	var heavy = feedback.request(68, 0.12)
	var first_start: int = feedback.started
	check("first contact schedules requested wall duration", heavy - first_start == 68 and Engine.time_scale == 0.12)
	var light = feedback.request(20, 0.30)
	check("overlapping light never shortens heavy or weakens slow scale", light >= heavy and Engine.time_scale == 0.12,
		{"heavy": heavy, "light": light, "scale": Engine.time_scale})
	var capped = feedback.request(500, 0.08)
	check("merged contacts cap at initial start plus90ms", capped == first_start + 90 and Engine.time_scale == 0.08,
		{"started": first_start, "deadline": capped})
	await wall_wait(maxi(0, capped - Time.get_ticks_msec() + 3))
	check("tick restores normal time by wall clock", feedback.tick() == 0 and Engine.time_scale == 1.0)
	check("expired freeze cannot immediately restart inside160ms", feedback.request(40, 0.12) == 0 and Engine.time_scale == 1.0)
	await wall_wait(maxi(0, feedback.cooldown_until - Time.get_ticks_msec() + 5))
	check("new contact can rearm after cooldown", feedback.request(40, 0.20) > Time.get_ticks_msec() and Engine.time_scale == 0.20)
	feedback.reset()
	check("reset clears deadline cooldown and global slow motion", feedback.deadline == 0 and feedback.cooldown_until == 0 and feedback.started == 0 and Engine.time_scale == 1.0)

func recoil_contract() -> void:
	var camera = CameraMotion.new()
	var peak = 0.0
	var finite = true
	for frame in 300:
		if frame < 80:
			camera.kick(Vector3(sin(float(frame)), 0.15, cos(float(frame))), true)
		var offset: Vector3 = camera.update([1.0 / 240.0, 1.0 / 60.0, 0.12][frame % 3])
		peak = maxf(peak, offset.length())
		finite = finite and offset.is_finite() and camera.velocity.is_finite()
	check("repeated kicks and120ms frames stay finite and within10cm", finite and peak > 0.01 and peak <= 0.10001, peak)
	camera.update(1.0)
	check("spring settles to zero without base drift", camera.recoil.length() < 0.0001 and camera.velocity.length() < 0.0001,
		{"recoil": camera.recoil, "velocity": camera.velocity})
	camera.kick(Vector3.RIGHT, true)
	camera.update(1.0 / 60.0)
	camera.reset()
	check("camera reset clears displacement and impulse", camera.recoil.is_zero_approx() and camera.velocity.is_zero_approx())

func observe_contact(_defender: DuelFighter, outcome: String, _at: Vector3) -> void:
	# Production controller listeners were connected first. Observe their real
	# presentation response, then restore test/save isolation immediately.
	last_impact = {"outcome": outcome, "wall": Time.get_ticks_msec(), "scale": Engine.time_scale,
		"deadline": game.hit_stop_until, "helper_deadline": game.hit_feedback.deadline,
		"recoil": game.camera_motion.recoil, "velocity": game.camera_motion.velocity,
		"enemy_hp": enemy.hp, "actor_state": game.player.state}
	game.testing = true
	match pending_transition:
		"pause": game.toggle_pause()
		"menu": game.return_to_menu()
		"camp": game.return_to_camp()
		"map": game.command("toggle_map")
		"inventory": game.command("toggle_inventory")
		"free": game.queue_free()
	last_impact["after_transition_scale"] = Engine.time_scale
	last_impact["after_transition_deadline"] = game.hit_stop_until

func feedback_clean() -> bool:
	return (Engine.time_scale == 1.0 and game.hit_stop_until == 0 and game.hit_feedback.deadline == 0 and
		game.camera_motion.recoil.is_zero_approx() and game.camera_motion.velocity.is_zero_approx())

func setup_controller(id: String) -> void:
	controller = id
	game = load("res://rpg.tscn" if id == "rpg" else "res://main.tscn").instantiate()
	root.add_child(game)
	game.testing = true
	game.fx.muted = true
	game.set_physics_process(false)
	await frames(4)
	if id == "rpg":
		game.phase = "explore"
		game.dialogue.clear()
		game.minion_spawns.clear()
		for key in game.enemies.keys():
			game._despawn(key)
		await frames(3)
		game.player.position = Vector3(-52.0, 0.015, 70.0)
		game._spawn_enemy("raider_feedback", game.player.position + Vector3(0, 0, 2.1), 1, false)
		enemy = game.enemies.raider_feedback
		enemy.apply_stats(1000.0, 1.0, 0.0, true)
		game.player.apply_stats(1000.0, 1.0, 0.0, true)
	else:
		game.phase = "fight"
		game.ai_enabled = false
		enemy = game.enemy
	enemy.impact_received.connect(observe_contact)
	check(id + " controller owns shared wall-clock and camera helpers",
		game.hit_feedback.get_script().resource_path.ends_with("impact_feedback.gd") and
		game.camera_motion.get_script().resource_path.ends_with("combat_camera.gd"))

func reset_pair(gap = 2.1) -> void:
	paused = false
	game.paused = false
	game.testing = true
	game._reset_hit_feedback()
	if controller == "rpg":
		game.inventory_open = false
		game.map_open = false
		game.dead = false
		game.phase = "explore"
	else:
		game.phase = "fight"
		game.ai_enabled = false
	var at = Vector3(-52.0, 0.015, 70.0) if controller == "rpg" else Vector3(0, 0.015, 0)
	if controller == "rpg" and (not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.get_parent() == null):
		game._spawn_enemy("raider_feedback", at + Vector3(0, 0, gap), 1, false)
		enemy = game.enemies.raider_feedback
		enemy.apply_stats(1000.0, 1.0, 0.0, true)
		enemy.impact_received.connect(observe_contact)
	for fighter in [game.player, enemy]:
		fighter.reset_fighter()
		fighter.hp = 1000.0
		fighter.enabled = fighter == game.player
		fighter.set_physics_process(fighter == game.player)
		fighter.input_move = Vector3.ZERO
	game.player.position = at
	enemy.position = at + Vector3(0, 0, gap)
	game.player.rotation.y = 0.0
	enemy.rotation.y = PI
	game.player.opponent = enemy
	enemy.opponent = game.player
	await frames(4)
	last_impact = {}
	pending_transition = ""

func real_hit(heavy: bool, transition = "") -> Dictionary:
	await reset_pair()
	pending_transition = transition
	var before_hp: float = enemy.hp
	game.testing = false
	var accepted: bool = game.player.request_heavy() if heavy else game.player.request_light()
	var limit = Time.get_ticks_msec() + 2500
	while last_impact.is_empty() and Time.get_ticks_msec() < limit:
		await process_frame
	if is_instance_valid(game):
		game.testing = true
	var event = last_impact.duplicate()
	check(controller + " actual " + ("K" if heavy else "J") + " contact drives shared feedback",
		accepted and not event.is_empty() and float(event.get("enemy_hp", before_hp)) < before_hp and float(event.get("scale", 1.0)) < 1.0 and
		int(event.get("deadline", 0)) == int(event.get("helper_deadline", -1)), event)
	if not event.is_empty():
		check(controller + " actual contact impulse remains bounded", Vector3(event.velocity).length() > 0.0 and Vector3(event.recoil).length() <= 0.10001, event)
	return event

func anticipation_contract() -> void:
	var actor = game.player
	actor.reset_fighter()
	actor.enabled = true
	actor.set_physics_process(false)
	for action in ["light", "heavy", "rush", "counter", "ultimate"]:
		actor.reset_fighter()
		actor.energy = 100.0
		var accepted = false
		if action == "light": accepted = actor.request_light()
		elif action == "heavy": accepted = actor.request_heavy()
		elif action == "ultimate": accepted = actor.request_ultimate()
		else: accepted = actor.request_skill(action)
		var windup: float = actor.ultimate_windup() if action == "ultimate" else actor.attack.active.x
		var cap = 2.6 if action == "ultimate" else (0.35 if action == "light" else 1.1)
		var values: Array = []
		var unchanged = true
		var actual_state: String = actor.state
		var actual_hp: float = actor.hp
		for part in [0.0, 0.25, 0.50, 0.75, 0.99, 1.0, 1.20]:
			# Explicit offline timing samples; only the pure presentation getter
			# runs here. Real contacts above advance the production physics clock.
			actor.action_time = windup * part
			values.append(CameraMotion.anticipation(actor))
			unchanged = unchanged and actor.state == actual_state and actor.hp == actual_hp
		var bounded = true
		for value in values: bounded = bounded and float(value) >= 0.0 and float(value) <= cap + 0.00001
		check(controller + " " + action + " anticipation rises smoothly inside role timing and releases to0",
			accepted and windup > 0.0 and bounded and values[0] == 0.0 and values[1] < values[2] and
			values[2] < values[3] and values[3] < values[4] and values[5] == 0.0 and values[6] == 0.0 and unchanged, values)
	actor.reset_fighter()
	actor.set_physics_process(true)

func controller_contract(id: String) -> void:
	await setup_controller(id)
	await anticipation_contract()
	await reset_pair(10.0)
	game.testing = false
	game.player.request_light()
	await wall_wait(1200)
	game.testing = true
	check(id + " actual missed J has no hit stop or recoil", last_impact.is_empty() and feedback_clean())
	for heavy in [false, true]:
		var contact = await real_hit(heavy)
		if not contact.is_empty():
			check(id + " contact wall stop stays within90ms", int(contact.deadline) > int(contact.wall) and int(contact.deadline) - int(contact.wall) <= 90, contact)
		await wall_wait(160)
		check(id + " controller tick restores normal time", Engine.time_scale == 1.0 and game.hit_stop_until == 0)
	await real_hit(true, "pause")
	var paused_position: Vector3 = game.player.position
	await wall_wait(100)
	check(id + " pause clears active feedback and freezes actor", game.paused and paused and feedback_clean() and game.player.position.distance_to(paused_position) < 0.001)
	game.toggle_pause()
	check(id + " resume retains clean normal time", not paused and not game.paused and feedback_clean())
	if id == "rpg":
		for transition in ["map", "inventory", "camp"]:
			await real_hit(true, transition)
			check(id + " " + transition + " transition clears feedback", feedback_clean())
	else:
		await real_hit(true, "menu")
		check("duel return to menu clears feedback", game.phase == "menu" and feedback_clean())
	await real_hit(true, "free")
	await process_frame
	await process_frame
	check(id + " freeing controller cannot leave global slow motion", Engine.time_scale == 1.0)
	paused = false
	Engine.time_scale = 1.0
	await frames(3)

func run() -> void:
	Engine.time_scale = 1.0
	await feedback_contract()
	recoil_contract()
	for id in ["duel", "rpg"]:
		await controller_contract(id)
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "rows": rows,
		"fixture": "Real controller J/K contacts and normal lifecycle APIs. HP/positions are offline fixtures; only pure anticipation tests sample action_time directly. --rpg-test suppresses campaign save I/O."}
	FileAccess.open("res://qa/feedback-results.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SHARED_FEEDBACK_QA ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
