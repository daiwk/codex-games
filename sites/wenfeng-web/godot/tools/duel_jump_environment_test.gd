extends "res://tools/duel_jump_test.gd"
const NativeBridge=preload("res://tools/duel_native_web_bridge_test.gd")
func ceiling(mode:String)->void:
	await prepare_case("zhaoyun",mode,mode+"/physical-ceiling")
	var actor=game.player
	var collider:CollisionShape3D
	for n in actor.get_children():
		if n is CollisionShape3D and n.shape is CapsuleShape3D:collider=n;break
	check(context+" real physics capsule exists",collider!=null,null)
	if collider==null:return
	var roof=StaticBody3D.new();roof.collision_layer=1
	var cs=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(6,.25,6);cs.shape=box;roof.add_child(cs)
	var face=collider.global_position.y+collider.shape.height*.5+.35
	roof.position=Vector3(actor.position.x,face+.125,actor.position.z);game.add_child(roof);await frames(2)
	var origin=actor.position.y;var peak=origin;var collided=false
	actor.request_jump()
	for i in 130:
		await frames(1);peak=maxf(peak,actor.position.y);collided=collided or actor.is_on_ceiling()
	check(context+" actual roof stops rise and body lands",collided and peak-origin<.5 and actor.is_on_floor() and not actor.is_jumping(),{"ceiling_collision":collided,"peak_delta":peak-origin,"status":actor.jump_status()})
	result_cases.append({"case":context,"trace":trace.duplicate(true)})
	roof.queue_free();await frames(2)
func mutual()->void:
	await prepare_case("zhaoyun","foot","foot/jump-vs-dodge")
	game.player.request_jump();await wait_air()
	for i in 70:
		if game.player.jump_status().phase=="falling":break
		await frames(1)
	var stamina=game.player.stamina;var vertical=game.player.velocity.y;var flight=game.player.jump_status().flight_time
	var dodge=game.player.request_dodge()
	check(context+" air dodge spends normal cost without a second launch",dodge and is_equal_approx(stamina-game.player.stamina,24.0) and is_equal_approx(game.player.velocity.y,vertical) and is_equal_approx(game.player.jump_status().flight_time,flight) and not game.player._duel_air_active,
		{"accepted":dodge,"stamina":[stamina,game.player.stamina],"vertical":[vertical,game.player.velocity.y],"flight":[flight,game.player.jump_status().flight_time],"old_hop_active":game.player._duel_air_active})
	await wait_land();await frames(35)
	check(context+" original jump still has single real landing",jump_starts==1 and jump_lands==1 and game.player.is_on_floor() and is_equal_approx(game.player.floor_snap_length,.2),{"starts":jump_starts,"lands":jump_lands,"snap":game.player.floor_snap_length})
	game.player.request_dodge();await frames(2)
	check(context+" old dodge hop cannot stack new jump",not game.player.request_jump(),game.player.jump_status())
func bridge_jump(mode:String)->void:
	await prepare_case("zhaoyun",mode,mode+"/native-bridge-jump")
	var bridge=NativeBridge.new();bridge.game=game;root.add_child(bridge)
	bridge._command(["input","jump",true]);await frames(2)
	bridge._command(["input","jump",false]);var accepted=game.player.is_jumping()
	await wait_land()
	check(context+" original bridge starts one jump and releases",accepted and jump_starts==1 and jump_lands==1 and not Input.is_action_pressed("jump"),{"starts":jump_starts,"lands":jump_lands,"pressed":Input.is_action_pressed("jump")})
	bridge.queue_free();await frames(1)
func resource_gate(mode:String)->void:
	await prepare_case("zhaoyun",mode,mode+"/air-low-resource")
	game.player.request_jump();await wait_air()
	game.player.stamina=0;game.player.energy=0 # Explicit native insufficient-resource fixture.
	var q=game.player.request_skill("rush");var u=game.player.request_ultimate()
	check(context+" air never bypasses skill resource gates",not q and not u and events.is_empty() and game.player.stamina==0 and game.player.energy==0,{"q":q,"u":u,"events":events})
	await wait_land()
func run()->void:
	out="/private/tmp/wenfeng-jump-environment-latest.json"
	Engine.physics_ticks_per_second=60;Engine.time_scale=1
	game=load("res://main.tscn").instantiate();root.add_child(game);game.testing=true;game.fx.muted=true;game.ai_enabled=false;await frames(6)
	for mode in ["foot","mounted"]:
		await ceiling(mode);await bridge_jump(mode);await resource_gate(mode)
	await mutual()
	write_report(true);game._reset_hit_feedback();print("JUMP BOUNDARY DONE ",checks," ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
