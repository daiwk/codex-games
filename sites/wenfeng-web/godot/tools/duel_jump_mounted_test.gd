extends "res://tools/duel_jump_test.gd"
# Focused final horse-bone callback regression; all thresholds inherited.
func run()->void:
	out="/private/tmp/wenfeng-jump-mounted-latest.json"
	Engine.physics_ticks_per_second=60;Engine.time_scale=1
	game=load("res://main.tscn").instantiate();root.add_child(game);game.testing=true;game.fx.muted=true;game.ai_enabled=false
	await frames(6)
	for role in ROLES:await basic(role,"mounted")
	write_report(true);game._reset_hit_feedback();quit(0 if failures.is_empty() else 1)
