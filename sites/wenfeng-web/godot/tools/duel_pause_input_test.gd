extends SceneTree

# Run with Godot --headless --path godot --script
# res://tools/duel_pause_input_test.gd --fixed-fps 60
# The real GUI consumes clicks; the real controller receives physical taps
# and production bridge commands. No combat/input implementation is replaced.
const NativeBridge = preload("res://tools/duel_native_web_bridge_test.gd")
var game: Node3D
var bridge: Node
var checks: Array = []
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for _i in count:
		await physics_frame
		await process_frame

func check(label: String, value: bool, evidence: Dictionary = {}) -> void:
	checks.append({"label": label, "passed": value, "evidence": evidence})
	if not value: failures.append(label)
	print("PASS " if value else "FAIL ", label, " ", evidence)

func key(code: int, down: bool) -> void:
	var event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func mouse(at: Vector2, button: int, down: bool) -> void:
	var event = InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func move_mouse(at: Vector2) -> void:
	var event = InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func evidence() -> Dictionary:
	return {"phase": game.phase, "paused": game.paused,
		"state": game.player.state, "combo": game.player.combo,
		"heavy": bool(game.player.attack.get("heavy", false)),
		"stamina": game.player.stamina, "pending": game.pending_input}

func prepare_fight() -> void:
	game.start_match()
	game.phase = "fight"
	game.testing = false
	game.ai_enabled = false
	game.player.enabled = true
	game.enemy.enabled = false
	game.enemy.set_physics_process(false)
	game.player.position = Vector3(0, 0.015, -2)
	game.enemy.position = Vector3(0, 0.015, 2)
	game.player.rotation.y = 0
	game.enemy.rotation.y = PI
	await frames(4)

func resume_click(held_frames: int) -> void:
	await prepare_fight()
	game.toggle_pause()
	await frames(3)
	var button: Button
	for child in game.hud.pause_panel.get_children():
		if child is Button and child.text == "继续决斗": button = child
	var at = button.get_global_rect().get_center()
	move_mouse(at)
	mouse(at, MOUSE_BUTTON_LEFT, true)
	await frames(held_frames)
	mouse(at, MOUSE_BUTTON_LEFT, false)
	await frames(2)
	check("resume click held %d ticks does not attack" % held_frames,
		not game.paused and game.player.state == "idle" and game.player.stamina == 100.0,
		evidence())

func expect_attack(label: String, heavy: bool) -> void:
	await frames(2)
	check(label, game.player.state == "attack" and game.player.combo == 0
		and bool(game.player.attack.get("heavy", false)) == heavy, evidence())

func run() -> void:
	Engine.physics_ticks_per_second = 60
	# Headless windows otherwise have a small GUI viewport unrelated to the
	# product's 1280x800 layout, so actual button hit testing would miss it.
	root.size = Vector2i(1280, 800)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await frames(4)
	game.fx.muted = true
	bridge = NativeBridge.new()
	bridge.game = game
	root.add_child(bridge)

	await resume_click(0)
	await resume_click(3)
	for button in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		await prepare_fight()
		var at = Vector2(1100, 600)
		move_mouse(at)
		mouse(at, button, true)
		mouse(at, button, false)
		await expect_attack("fight same-tick mouse tap %d attacks once" % button,
			button == MOUSE_BUTTON_RIGHT)
	for code in [KEY_J, KEY_K]:
		await prepare_fight()
		key(code, true)
		key(code, false)
		await expect_attack("fight same-tick keyboard tap %d attacks once" % code, code == KEY_K)

	await prepare_fight()
	Input.action_press("heavy")
	Input.action_release("heavy")
	await expect_attack("fight polling still accepts a complete action tap", true)
	await prepare_fight()
	bridge._command(["input", "light", true])
	bridge._command(["input", "light", false])
	await expect_attack("touch bridge same-tick tap attacks once", false)
	await prepare_fight()
	game.player.stagger(0.05)
	bridge._command(["input", "light", true])
	bridge._command(["input", "light", false])
	await frames(6)
	check("touch bridge tap buffers through short recovery", game.player.state == "attack"
		and game.player.combo == 0, evidence())

	await prepare_fight()
	game.player.stagger(0.10)
	bridge._command(["input", "light", true])
	bridge._command(["input", "light", false])
	game.toggle_pause()
	await frames(3)
	key(KEY_J, true)
	key(KEY_J, false)
	game.toggle_pause()
	await frames(12)
	check("pause clears queued and paused-frame combat input", game.player.state == "idle"
		and game.pending_input == "" and game.player.stamina == 100.0, evidence())

	await prepare_fight()
	game.player.stagger(0.10)
	bridge._command(["input", "heavy", true])
	bridge._command(["input", "heavy", false])
	game.return_to_menu()
	await frames(3)
	key(KEY_J, true)
	key(KEY_J, false)
	game.start_match()
	await frames(166)
	check("menu and countdown discard previous combat intent", game.phase == "fight"
		and game.player.state == "idle" and game.pending_input == "", evidence())

	var file = FileAccess.open("/private/tmp/wenfeng-duel-pause-input-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	print("DUEL_PAUSE_INPUT ", checks.size(), " checks; ", failures.size(), " failures")
	bridge.queue_free()
	game.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
