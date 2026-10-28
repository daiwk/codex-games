extends "res://tools/duel_wrist_focused_test.gd"

## Actual imported normals at touching spear range, including first contact
## and the return to idle. Unlike the older focused suite, visible forearm /
## palm angular speed is a hard condition here rather than a diagnostic.
var grounded_foot_heights: Dictionary = {}

func observe() -> void:
	super.observe()
	if not observing or not is_instance_valid(game.player): return
	var fighter = game.player
	var height = INF
	for suffix in ["LeftFoot", "RightFoot", "LeftToeBase", "RightToeBase"]:
		var index = bone(fighter.skeleton, suffix)
		if index >= 0:
			height = minf(height, fighter.skeleton.to_global(fighter.skeleton.get_bone_global_pose(index).origin).y - fighter.global_position.y)
	if not grounded_foot_heights.has(context): grounded_foot_heights[context] = {"minimum": INF, "maximum": -INF}
	grounded_foot_heights[context].minimum = minf(grounded_foot_heights[context].minimum, height)
	grounded_foot_heights[context].maximum = maxf(grounded_foot_heights[context].maximum, height)

func run() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.testing = true
	game.fx.muted = true
	game.ai_enabled = false
	await frames(5)
	for role in ["zhaoyun", "machao"]:
		for index in 4:
			await normal(role, "foot", index)
			for side in ["Left", "Right"]:
				for part in ["_world_forearm_rate", "_world_hand_rate"]:
					hard(context + " " + side + part + " <=900deg/s", float(metrics[side + part]) <= deg_to_rad(900.0),
						rad_to_deg(float(metrics[side + part])))
			var feet: Dictionary = grounded_foot_heights[context]
			hard(context + " grounded foot does not penetrate floor", float(feet.minimum) >= -0.02, feet)
			hard(context + " planted foot height remains within 6cm", float(feet.maximum) - float(feet.minimum) < 0.06, feet)
	var file = FileAccess.open("/private/tmp/wenfeng-duel-motion-polish-latest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"completed": true, "checks": checks, "failures": anatomical_failures,
		"speed_diagnostics": speed_diagnostics, "cases": case_metrics, "feet": grounded_foot_heights}, "\t"))
	game._reset_hit_feedback()
	print("DUEL_MOTION_POLISH_DONE ", case_metrics.size(), " cases ", checks, " checks ", anatomical_failures.size(), " failures")
	quit(0 if anatomical_failures.is_empty() else 1)
