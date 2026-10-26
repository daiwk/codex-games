extends "res://tools/rpg_jump_test.gd"

# Focused regression for the one original58/59 failure; post-fix10/10.
# Persistence and autonomous AI isolation are inherited from the test helper.
func run():
	Engine.physics_ticks_per_second=60;Engine.time_scale=1.0
	game=load("res://tools/rpg_jump_controller.gd").new();root.add_child(game);current_scene=game;await frames(8);game.fx.muted=true
	while game.phase=="dialogue":game.command("continue_dialogue")
	bind_player();await frames(8)
	check("grounded status reports mounted and zero jump height",game.player.jump_status().mounted and is_zero_approx(game.player.jump_status().height),game.player.jump_status())
	check("real V starts old horse jump",await start_air(),game.player.jump_status());await frames(10)
	var old=game.player;var id=old.get_instance_id();var high=old.position.y
	game.command("horse_color","brown")
	var immediate=game.player.position
	check("old pending-free capsule immediately disables",is_instance_valid(old) and old.collision_layer==0 and old.collision_mask==0 and not old.is_physics_processing() and not old.enabled,{"layer":old.collision_layer,"mask":old.collision_mask,"enabled":old.enabled})
	check("new grounded spawn preserves collision mask",game.player.get_instance_id()!=id and is_equal_approx(immediate.y,.05) and game.player.collision_layer==2 and game.player.collision_mask==3,{"layer":game.player.collision_layer,"mask":game.player.collision_mask,"position":immediate,"prior_air_height":high})
	bind_player();await frames(18)
	check("no inherited body overlap lift or slow airborne drift",high>.3 and game.player.horse_color=="brown" and game.player.is_on_floor() and absf(game.player.position.y)<.1 and not game.player.is_jumping(),{"height":game.player.position.y,"jump":game.player.jump_status()})
	check("new inactive status is accurate",game.player.jump_status().mounted and is_zero_approx(game.player.jump_status().height) and game.player.jump_status().can_jump,game.player.jump_status())
	context="replacement-horse-air-Q";events=[];var f=game.player
	check("replacement actor can really jump again",await start_air(),f.jump_status());await press(KEY_Q)
	check("replacement controller Q accepts in real air",not events.is_empty() and events[0].stage=="start" and events[0].jump.airborne,events.duplicate(true))
	for i in 150:
		await frames(1)
		if not events.is_empty() and events[-1].stage=="complete" and not f.is_jumping():break
	var released=false;var completed=false
	for e in events:
		if e.stage=="release":released=true
		if e.stage=="complete":completed=true
	check("replacement Q releases and completes",released and completed,events.duplicate(true))
	check("replacement lands with new floor collision intact",f.is_on_floor() and not f.is_jumping() and f.collision_mask==3 and f.collision_layer==2,f.jump_status())
	game._reset_hit_feedback();paused=false
	FileAccess.open("/private/tmp/wenfeng-rpg-jump-horse-target-results.json",FileAccess.WRITE).store_string(JSON.stringify({"completed":true,"passed":failures.is_empty(),"checks":checks.size(),"failures":failures,"results":checks,"scope":"Focused post-fix actual RPG station horse_color replacement during a real V jump. Full controller/world/UI, only persistence/AI isolated as original59case. Verify immediate retirement of old collidable, new ground spawn and unchanged 2/3 collision, no inherited lift, then actual physical V and airborne Q through new actor. Original58/59 failure report retained untouched."},"\t"));print("RPG_JUMP_HORSE_TARGET ",checks.size()-failures.size(),"/",checks.size()," ",failures);quit(1 if failures.size() else 0)
