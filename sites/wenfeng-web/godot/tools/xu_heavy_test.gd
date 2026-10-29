extends SceneTree

# Production Main, input dispatch and actors. These are state/cancellation
# regressions; shoe contact and animation quality require rendered review.
const NativeBridge = preload("res://tools/duel_native_web_bridge_test.gd")
var game
var bridge
var checks: Array = []
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for i in count:
		# Main.testing suppresses its automatic player-input polling.
		if is_instance_valid(game) and game.testing and game.phase == "fight" and not game.paused:
			game._player_input()
		await physics_frame
		await process_frame

func input(action: String, down: bool) -> void:
	bridge._command(["input", action, down])

func tap(action: String) -> void:
	input(action, true)
	input(action, false)

func check(label: String, passed: bool) -> void:
	var evidence: Dictionary = game.player.source_k_status()
	checks.append({"label": label, "passed": passed, "source_k": evidence,
		"state": game.player.state, "clip": game.player.current_clip})
	if not passed: failures.append(label)
	print("PASS " if passed else "FAIL ", label)

func prepare() -> void:
	game._clear_combat_input()
	for action in InputMap.get_actions(): Input.action_release(action)
	game.start_match()
	game.testing = true
	game.ai_enabled = false
	game.phase = "fight"
	game.paused = false
	game.player.enabled = true
	game.enemy.enabled = false
	game.enemy.set_physics_process(false)
	game.player.position = Vector3(0, 0.015, -3)
	game.enemy.position = Vector3(0, 0.015, 4)
	game.player.rotation.y = 0
	game.enemy.rotation.y = PI
	game.lock_on = true
	game.camera_axis_ready = false
	await frames(4)

func begin_running_k(ticks: int) -> void:
	input("move_up", true)
	await frames(ticks)
	tap("heavy")
	await frames(2)
	input("move_up", false)

func clear_source() -> bool:
	var source: Dictionary = game.player.source_k_status()
	return not source.active and not source.queued_strike and not source.run_entry.active and Vector3(source.pending_root).length_squared() < 0.000001

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.testing = true
	game.ai_enabled = false
	game.fx.muted = true
	game.select_character("xuchu")
	game.select_opponent("zhaoyun")
	for action in InputMap.get_actions():
		InputMap.action_erase_events(action)
		Input.action_release(action)
	bridge = NativeBridge.new()
	bridge.game = game
	root.add_child(bridge)
	for ticks in [18, 27, 36, 45]:
		await prepare()
		await begin_running_k(ticks)
		var source: Dictionary = game.player.source_k_status()
		var entered: bool = source.active and source.run_entry.active and source.run_entry.prepared
		await frames(150)
		check("Run phase %s enters and finishes without a stuck plant" % ticks,
			entered and clear_source() and game.player.state == "idle" and game.enemy.hp == 120.0)

	await prepare()
	game.player.stamina = 0.0
	await begin_running_k(18)
	check("Rejected K leaves no prepared plant", clear_source() and not game.player.source_k_status().run_entry.prepared)

	await prepare()
	tap("jump")
	await frames(12)
	tap("heavy")
	await frames(2)
	check("Airborne K keeps its aerial heavy", game.player.is_jumping() and game.player.state == "attack" and not bool(game.player.attack.get("xu_ual1_k", false)) and clear_source())

	await prepare()
	await begin_running_k(18)
	tap("jump")
	await frames(10)
	check("Jump during plant releases ground foot anchors", game.player.is_jumping() and bool(game.player.source_k_status().run_entry.get("air_released", false)))

	await prepare()
	await begin_running_k(18)
	await frames(8)
	# Explicit state-level incoming strike. Rendered acceptance uses real contact.
	game.player.receive_strike(game.enemy, {"damage": 18.0, "heavy": false, "hit_stun": 0.3})
	await frames(1)
	check("Incoming hit clears plant, root motion and queued damage", game.player.state == "hit" and clear_source())

	await prepare()
	await begin_running_k(18)
	game.start_match()
	await frames(2)
	check("New round clears the previous heavy", clear_source())

	var report = "/private/tmp/wenfeng-xu-heavy-results.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): report = arg.trim_prefix("--output=")
	FileAccess.open(report, FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	print("XU_HEAVY_DONE ", checks.size(), " checks; ", failures.size(), " failures")
	bridge.queue_free()
	game.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
