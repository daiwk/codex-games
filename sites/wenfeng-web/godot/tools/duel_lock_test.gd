extends SceneTree

# Controller/locomotion regression for optional duel locking. Inputs use the
# normal handler and InputMap; only the stationary opponent is a test fixture.
# Run: Godot --headless --path . --script res://tools/duel_lock_test.gd
class InputDriver extends Node:
	var controller: Node
	var active = true
	func _physics_process(_delta: float) -> void:
		if active and is_instance_valid(controller) and controller.phase == "fight" and not controller.paused:
			controller._player_input()

var game: Node3D
var driver: InputDriver
var checks = 0
var failures: Array[String] = []
var results: Array = []
const MOVE_ACTIONS = ["move_left", "move_right", "move_up", "move_down", "guard", "dodge"]

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	checks += 1
	results.append({"name": label, "passed": passed, "detail": detail})
	print("PASS " if passed else "FAIL ", label, " ", detail if detail != null else "")
	if not passed:
		failures.append(label)

func frames(count: int) -> void:
	for index in count:
		await physics_frame

func release_inputs() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)

func key(code: Key, echo = false) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	event.echo = echo
	game._input(event)
	game._unhandled_input(event)

func middle(pressed: bool) -> void:
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_MIDDLE
	event.pressed = pressed
	event.position = Vector2(640, 400)
	game._input(event)
	game._unhandled_input(event)

func lock_state() -> Dictionary:
	return game.snapshot().get("lock_on", {})

func lock_active() -> bool:
	return bool(lock_state().get("active", false))

func flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)

func setup(mode: String, gap = 7.0, at = Vector3.ZERO) -> void:
	release_inputs()
	paused = false
	game.paused = false
	game.return_to_menu()
	game.select_combat_mode(mode)
	game.select_character("zhaoyun")
	game.select_opponent("machao")
	await frames(3)
	game.start_match()
	game.phase = "fight"
	game.round_time = 90.0
	game.ai_enabled = false
	game.player.enabled = true
	game.enemy.enabled = false
	game.enemy.set_physics_process(false)
	game.player.position = at + Vector3(0, 0.015, 0)
	game.enemy.position = at + Vector3(0, 0.015, gap)
	game.player.rotation.y = 0.0
	game.enemy.rotation.y = PI
	await frames(3)
	game._update_camera(1.0, true)

func target_visible(actor: Node3D) -> bool:
	var point = actor.global_position + Vector3.UP * (2.3 if actor.mounted else 1.15)
	if game.camera.is_position_behind(point):
		return false
	return Rect2(Vector2.ZERO, game.get_viewport().get_visible_rect().size).has_point(game.camera.unproject_position(point))

func movement_case(mode: String, action: String) -> void:
	await setup(mode)
	key(KEY_TAB)
	await frames(5)
	for index in 60:
		game._update_camera(1.0 / 60.0)
	var start: Vector3 = game.player.position
	var initial_radius = flat(game.enemy.position - start).length()
	var initial_right = flat(game.camera.global_basis.x).normalized()
	Input.action_press(action)
	await frames(45)
	Input.action_release(action)
	var moved = flat(game.player.position - start)
	var radius = flat(game.enemy.position - game.player.position).length()
	var toward = flat(game.enemy.position - game.player.position).normalized()
	var facing: float = game.player.forward().dot(toward)
	var passed = lock_active() and facing > 0.94
	match action:
		"move_up": passed = passed and radius < initial_radius - 0.6
		"move_down": passed = passed and radius > initial_radius + 0.5
		"move_left": passed = passed and moved.dot(initial_right) < -0.45 and absf(radius - initial_radius) < 0.75
		"move_right": passed = passed and moved.dot(initial_right) > 0.45 and absf(radius - initial_radius) < 0.75
	check(mode + " real locked " + action + " keeps facing and target-relative travel", passed,
		{"movement": moved, "initial_radius": initial_radius, "radius": radius, "facing": facing, "lock": lock_state()})
	check(mode + " locked movement keeps both actors in the camera", target_visible(game.player) and target_visible(game.enemy))
	await frames(30)
	check(mode + " release brakes locked movement", flat(game.player.velocity).length() < 0.08, game.player.velocity)

func toggle_and_lifecycle(mode: String) -> void:
	await setup(mode)
	check(mode + " starts with optional lock disabled", not game.lock_on and not lock_active(), lock_state())
	key(KEY_TAB)
	await frames(3)
	var snapshot = lock_state()
	check(mode + " Tab enables live enemy lock", game.lock_on and lock_active() and game.player.lock_facing, snapshot)
	check(mode + " snapshot exposes target availability and position", snapshot.get("available", false) and not str(snapshot.get("target", "")).is_empty() and snapshot.get("position", []).size() == 3, snapshot)
	key(KEY_TAB, true)
	check(mode + " key repeat does not toggle lock", lock_active())
	key(KEY_TAB)
	await frames(2)
	check(mode + " Tab restores free mode", not game.lock_on and not lock_active() and not game.player.lock_facing)
	middle(true)
	middle(false)
	await frames(2)
	check(mode + " middle click toggles lock once", game.lock_on and lock_active())
	var before_pause = game.player.position
	game.toggle_pause()
	key(KEY_TAB)
	middle(true)
	middle(false)
	await create_timer(0.08, true, false, true).timeout
	check(mode + " pause retains lock and rejects switching", game.paused and game.lock_on and lock_active() and game.player.position.is_equal_approx(before_pause))
	game.toggle_pause()
	await frames(2)
	var toward = flat(game.enemy.position - game.player.position).normalized()
	var camera_offset = flat(game.camera.position - game.player.position)
	for index in 120:
		game._update_camera(1.0 / 60.0)
	camera_offset = flat(game.camera.position - game.player.position)
	check(mode + " locked camera sits behind the player and shows both actors", camera_offset.dot(toward) < -1.0 and target_visible(game.player) and target_visible(game.enemy),
		{"offset": camera_offset, "camera": game.camera.position})
	game._new_round()
	await frames(3)
	check(mode + " next round retains user lock preference", game.lock_on and lock_active() and game.phase == "countdown", lock_state())
	game.phase = "fight"
	game.player.enabled = true
	game.enemy.hp = 0.0
	await frames(3)
	check(mode + " actual enemy death releases active target immediately", not lock_active() and not game.player.lock_facing and game.phase == "round_end", lock_state())
	game.return_to_menu()
	await frames(2)
	check(mode + " selection menu clears lock preference and target", not game.lock_on and not lock_active(), lock_state())
	key(KEY_TAB)
	middle(true)
	middle(false)
	check(mode + " menu input cannot acquire a combat lock", not game.lock_on and not lock_active())

func committed_contact_case(mode: String) -> void:
	await setup(mode, 2.25)
	key(KEY_TAB)
	await frames(3)
	var hp_before = game.enemy.hp
	check(mode + " locked J starts its real attack", game.player.request_light())
	var contact = false
	for index in 90:
		await physics_frame
		contact = contact or game.player.contact_latched
		if game.player.state == "idle":
			break
	check(mode + " lock preserves physical thrust contact and real damage", contact and game.enemy.hp < hp_before,
		{"before": hp_before, "after": game.enemy.hp, "contact": contact})

func camera_crossing_case(mode: String) -> void:
	await setup(mode, 5.0)
	key(KEY_TAB)
	driver.active = false
	game.player.set_physics_process(false)
	game.set_process(false)
	game._update_camera(1.0, true)
	var max_yaw_step = 0.0
	var visible_samples = 0
	var total_samples = 0
	# Real camera controller with explicit enemy-position fixtures covers four
	# bearings, then a close pass through the 65 cm direction-retention zone.
	for index in 240:
		var angle = float(index) * TAU / 240.0
		game.enemy.position = game.player.position + Vector3(sin(angle), 0, cos(angle)) * 5.0
		var before: float = game.camera_axis_yaw
		game._update_camera(1.0 / 60.0)
		max_yaw_step = maxf(max_yaw_step, absf(angle_difference(before, game.camera_axis_yaw)))
		visible_samples += 1 if target_visible(game.player) and target_visible(game.enemy) else 0
		total_samples += 1
	var held_yaw: float = game.camera_axis_yaw
	for index in 61:
		game.enemy.position = game.player.position + Vector3(0.0, 0.0, 0.30 - float(index) * 0.01)
		game._update_camera(1.0 / 60.0)
	check(mode + " close body crossing retains the camera side", absf(angle_difference(held_yaw, game.camera_axis_yaw)) < 0.0001)
	check(mode + " locked camera has bounded turn rate over all bearings", max_yaw_step < 0.055, max_yaw_step)
	check(mode + " four-bearing camera keeps both fighters visible", visible_samples == total_samples, [visible_samples, total_samples])
	game.set_process(true)
	game.player.set_physics_process(true)
	driver.active = true

func horse_color_case() -> void:
	for color in ["white", "brown"]:
		await setup("mounted", 2.25)
		game.return_to_menu()
		game.select_horse_color(color)
		game.select_horse_color("brown" if color == "white" else "white", true)
		await frames(3)
		game.start_match()
		game.phase = "fight"
		game.ai_enabled = false
		game.player.enabled = true
		game.enemy.enabled = false
		game.enemy.set_physics_process(false)
		game.player.position = Vector3(0, 0.015, 0)
		game.enemy.position = Vector3(0, 0.015, 2.25)
		game.player.rotation.y = 0.0
		game.enemy.rotation.y = PI
		key(KEY_TAB)
		await frames(3)
		var hp_before: float = game.enemy.hp
		game.player.request_light()
		await frames(80)
		check(color + " locked horse retains correct model and real contact damage", game.player.horse_color == color and game.player.horse != null and game.enemy.hp < hp_before,
			{"horse": game.player.horse_color, "hp": game.enemy.hp})

func mounted_charge_case() -> void:
	await setup("mounted", 10.0)
	key(KEY_TAB)
	await frames(4)
	# Reverse and tangent requests are real InputMap state. Rejected charge
	# must not spend resources or begin a cooldown.
	for action in ["move_down", "move_left", "move_right"]:
		Input.action_press(action)
		game._player_input()
		var before_stamina: float = game.player.stamina
		var rejected: bool = not game.player.request_dodge(game.player.input_move)
		check("locked " + action + " rejects Space without resource loss", rejected and game.player.stamina == before_stamina and game.player.mount_charge_cooldown == 0.0)
		Input.action_release(action)
	game._player_input()
	var start = game.player.position
	var stamina = game.player.stamina
	check("locked Space from standstill starts cavalry charge", game.player.request_dodge(Vector3.ZERO))
	await frames(30)
	check("locked standstill charge spends stamina and advances toward enemy", game.player.stamina <= stamina - 20.0 and game.player.position.z > start.z + 0.8 and game.player.mount_speed > 4.5,
		{"position": game.player.position, "speed": game.player.mount_speed, "stamina": game.player.stamina})
	Input.action_press("move_left")
	await frames(6)
	Input.action_release("move_left")
	check("locked orbit input cancels fast charge instead of sideways gallop", game.player.mount_charge_time <= 0.0, game.player.mount_charge_time)
	await frames(30)
	key(KEY_TAB)
	await frames(20)
	check("unlock after orbit does not create a forward surge", not lock_active() and game.player.mount_speed < 0.1 and flat(game.player.velocity).length() < 0.1, game.player.velocity)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.testing = true
	game.ai_enabled = false
	game.fx.muted = true
	driver = InputDriver.new()
	driver.controller = game
	root.add_child(driver)
	await frames(4)
	if not game.has_method("toggle_lock") or not game.has_method("_locked_movement"):
		check("duel lock controller API exists", false)
	else:
		for mode in ["foot", "mounted"]:
			await toggle_and_lifecycle(mode)
			for action in ["move_up", "move_down", "move_left", "move_right"]:
				await movement_case(mode, action)
			await committed_contact_case(mode)
			await camera_crossing_case(mode)
		await horse_color_case()
		await mounted_charge_case()
	release_inputs()
	paused = false
	game.paused = false
	game._reset_hit_feedback()
	DirAccess.make_dir_recursive_absolute("res://qa/duel-lock")
	var output = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "results": results}
	var file = FileAccess.open("res://qa/duel-lock/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	print("DUEL_LOCK_QA=", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
