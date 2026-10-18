extends Node

# Browser integration is separate from the original combat simulation.
var game: Node
var _callback: JavaScriptObject
var _clock = 0.0
const ACTIONS = ["move_left", "move_right", "move_up", "move_down", "light", "heavy", "guard", "dodge", "skill_rush", "skill_counter", "ultimate"]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		return
	_callback = JavaScriptBridge.create_callback(_command)
	JavaScriptBridge.get_interface("window").wenfengCommand = _callback
	_publish()
	JavaScriptBridge.eval("window.wenfengReady && window.wenfengReady()")

func _process(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	_clock += delta
	if _clock >= 0.10:
		_clock = 0.0
		_publish()

func _command(args: Array) -> void:
	if args.is_empty():
		return
	match str(args[0]):
		"pause":
			game.toggle_pause()
		"blur":
			_release_inputs()
			if game.phase in ["fight", "countdown"] and not game.paused:
				game.toggle_pause()
		"mute":
			game.fx.muted = not game.fx.muted
		"menu":
			_release_inputs()
			game.return_to_menu()
		"mode":
			if args.size() >= 2 and game.phase == "menu":
				_release_inputs()
				game.select_combat_mode(str(args[1]))
		"horse_color", "enemy_horse_color":
			if args.size() >= 2 and game.phase == "menu":
				_release_inputs()
				game.select_horse_color(str(args[1]), str(args[0]) == "enemy_horse_color")
		"input":
			if args.size() >= 3 and str(args[1]) in ACTIONS:
				if bool(args[2]):
					Input.action_press(str(args[1]))
				else:
					Input.action_release(str(args[1]))
	_publish()

func _publish() -> void:
	var data = game.snapshot()
	data["ready"] = true
	data["muted"] = game.fx.muted
	data["difficulty"] = game.difficulty
	data["round"] = game.round_number
	data["fps"] = Engine.get_frames_per_second()
	var window_size = get_window().size
	var logical_size = get_viewport().get_visible_rect().size
	data["rendering"] = {
		"pixels": [window_size.x, window_size.y],
		"logical_size": [logical_size.x, logical_size.y],
		"scale_3d": get_viewport().scaling_3d_scale,
		"msaa_3d": get_viewport().msaa_3d,
	}
	data["coordinates"] = "meters; Y up; X right; Z toward the near edge of the arena"
	JavaScriptBridge.eval("window.__wenfengState=" + JSON.stringify(data) + ";window.wenfengStateChanged && window.wenfengStateChanged();")

func _release_inputs() -> void:
	for action in ACTIONS:
		Input.action_release(action)

func close_game() -> void:
	_release_inputs()
	game.return_to_menu()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.wenfengClose && window.wenfengClose()")
