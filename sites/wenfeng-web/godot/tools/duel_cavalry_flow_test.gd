extends "res://tools/duel_flow_test.gd"

func _initialize() -> void:
	output="/private/tmp/wenfeng-cavalry-flow-latest.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func actor_row(actor: Node3D, label: String) -> Dictionary:
	var row={"state":actor.state,"clip":actor.current_clip,"combo":actor.combo,"action_time":actor.action_time,
		"action_duration":actor.action_duration,"position":point(actor.position),"facing":actor.rotation.y,
		"speed":Vector2(actor.velocity.x,actor.velocity.z).length(),"input":point(actor.input_move),"hp":actor.hp,
		"contact_latched":actor.contact_latched,"contact_active":actor.contact_active,"stamina":actor.stamina,
		"tip":point(actor.blade_tip()),"animation_time":actor.animation_player.current_animation_position}
	var hand=bone(actor.skeleton,"RightHand")
	if hand>=0:row["right_hand_bone_origin"]=point(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(hand).origin))
	row["mount_speed"]=actor.mount_speed
	row["mount_turn_rate"]=actor.mount_turn_rate
	row["lock_facing"]=actor.lock_facing
	row["charge_time"]=actor.mount_charge_time
	row["forward"]=point(actor.forward())
	var planar=Vector3(actor.velocity.x,0,actor.velocity.z)
	row["forward_velocity"]=planar.dot(actor.forward())
	row["side_velocity"]=absf(planar.dot(actor.global_basis.x))
	row["blade_base"]=point(actor.blade_base())
	row["active"]=actor.state=="attack" and actor.action_time>=float(actor.attack.get("active",Vector2.ZERO).x) and actor.action_time<=float(actor.attack.get("active",Vector2.ZERO).y)
	var near=Geometry3D.get_closest_points_between_segments(actor.blade_base(),actor.blade_tip(),actor.opponent.thrust_body_low(),actor.opponent.thrust_body_high())
	row["blade_capsule_distance"]=near[0].distance_to(near[1])
	row["body_radius"]=actor.opponent.thrust_body_radius()
	return row

func impact(actor: Node, outcome: String, at: Vector3) -> void:
	super.impact(actor,outcome,at)
	if not observing or events.is_empty():return
	var attacker=actor.opponent
	var toward=(actor.global_position-attacker.global_position).slide(Vector3.UP).normalized()
	var attacker_velocity=Vector3(attacker.velocity.x,0.0,attacker.velocity.z)
	var defender_velocity=Vector3(actor.velocity.x,0.0,actor.velocity.z)
	events.back().merge({"attacker_speed_at_impact":attacker_velocity.length(),"attacker_mount_speed_at_impact":attacker.mount_speed,
		"defender_speed_at_impact":defender_velocity.length(),"closing_speed_at_impact":(attacker_velocity-defender_velocity).dot(toward)})

func finish_case(label: String) -> void:
	super.finish_case(label)
	var result:Dictionary=cases.back()
	var peak_side=0.0
	var peak_turn=0.0
	var peak_speed=0.0
	var input_off_travel=0.0
	var peak_frame_heading=0.0
	var before:Dictionary={}
	var closest=INF
	var min_capsule=INF
	for row in result.samples:
		peak_side=maxf(peak_side,float(row.player.side_velocity))
		peak_speed=maxf(peak_speed,float(row.player.speed))
		peak_turn=maxf(peak_turn,absf(float(row.player.mount_turn_rate)))
		var base=Vector3(row.player.blade_base[0],row.player.blade_base[1],row.player.blade_base[2])
		var tip=Vector3(row.player.tip[0],row.player.tip[1],row.player.tip[2])
		var epos=Vector3(row.enemy.position[0],row.enemy.position[1],row.enemy.position[2])
		closest=minf(closest,minf(base.distance_to(epos),tip.distance_to(epos)))
		if bool(row.player.active):min_capsule=minf(min_capsule,float(row.player.blade_capsule_distance))
		if not before.is_empty():
			var a=Vector3(before.player.position[0],before.player.position[1],before.player.position[2])
			var b=Vector3(row.player.position[0],row.player.position[1],row.player.position[2])
			if Vector3(row.player.input[0],row.player.input[1],row.player.input[2]).length_squared()<.001:input_off_travel+=a.distance_to(b)
			peak_frame_heading=maxf(peak_frame_heading,absf(angle_difference(before.player.facing,row.player.facing)))
		before=row
	result.metrics.merge({"min_active_blade_capsule_distance":min_capsule if is_finite(min_capsule) else -1.0,"peak_speed":peak_speed,"peak_side_velocity":peak_side,"peak_turn_rad_per_s":peak_turn,"peak_heading_degrees_per_tick":rad_to_deg(peak_frame_heading),"release_coast_meters":input_off_travel,"final_player_hp":game.player.hp,"final_enemy_hp":game.enemy.hp,"final_player_position":point(game.player.position),"final_enemy_position":point(game.enemy.position)})
	write_report(false)
	print("CAVALRY ",label," ",JSON.stringify(result.metrics))

func write_report(completed: bool) -> void:
	var file=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"completed":completed,"cases":cases,"request_cost":request_metrics,
		"scope":"Mounted-only native Main/actual arena/unaltered profiles and resolver. Locked control uses real InputMap; free steering and passing use explicit world intent with player input polling disabled. Passing has both CharacterBodies moving via real physics and single real request_light. AI trials use original AI and real InputMap player intent with fixed RNG seed. Fixed engine-clock runs are offline behavior evidence, not real-time FPS/latency. No role skill or ultimate assertion is implied."},"\t"))

func locked_controls() -> void:
	await prepare("zhaoyun","mounted",16.0)
	observing=false
	game.player.position=Vector3(0,.015,-6)
	game.enemy.position=Vector3(0,.015,10)
	game.player.rotation.y=0
	game.testing=false
	await frames(4)
	samples=[];events=[];last_physics=-1;observing=true
	phase_label="locked-controller-W-release-D-S"
	Input.action_press("move_up")
	await frames(60)
	Input.action_release("move_up")
	await frames(36)
	Input.action_press("move_right")
	await frames(60)
	Input.action_release("move_right")
	await frames(36)
	Input.action_press("move_down")
	await frames(36)
	Input.action_release("move_down")
	await frames(36)
	finish_case("locked-real-InputMap-W-release-D-S")

func free_controls() -> void:
	await prepare("zhaoyun","mounted",16.0)
	observing=false
	game.player.position=Vector3(0,.015,-6)
	game.enemy.position=Vector3(0,.015,10)
	game.player.rotation.y=0
	game.testing=true
	game.lock_on=false;game._sync_lock()
	await frames(4)
	samples=[];events=[];last_physics=-1;observing=true
	phase_label="free-native-intent-straight-turn-release"
	game.player.input_move=Vector3.FORWARD * -1
	await frames(60)
	game.player.input_move=Vector3.RIGHT
	await frames(45)
	game.player.input_move=Vector3.ZERO
	await frames(45)
	finish_case("unlocked-actor-world-intent-straight-turn-release")

func passing(role:String,lateral:float) -> void:
	await prepare(role,"mounted",10.0)
	observing=false
	game.testing=true
	game.lock_on=false;game._sync_lock()
	game.player.position=Vector3(-lateral*.5,.015,-5)
	game.enemy.position=Vector3(lateral*.5,.015,5)
	game.player.rotation.y=0;game.enemy.rotation.y=PI
	game.enemy.set_physics_process(true);game.enemy.enabled=true
	await frames(8)
	samples=[];events=[];last_physics=-1;observing=true
	phase_label="both-real-moving-pass"
	game.player.input_move=Vector3(0,0,1)
	game.enemy.input_move=Vector3(0,0,-1)
	var requested=false
	var accepted=false
	for i in 210:
		if not requested and game.player.position.distance_to(game.enemy.position)<4.0:
			requested=true;accepted=game.player.request_light()
			events.append({"event":"passing-first-J","accepted":accepted,"frame":Engine.get_physics_frames(),"gap":game.player.position.distance_to(game.enemy.position),"speed":game.player.mount_speed})
		await frames(1)
	finish_case(role+"/moving-headon/lateral-"+str(lateral))

func ai_trial(role:String) -> void:
	await prepare(role,"mounted",7.0)
	game.testing=false
	phase_label="real-AI-and-player-InputMap"
	game.enemy.enabled=true;game.enemy.set_physics_process(true);game.ai_enabled=true
	var held=false
	for tick in 900:
		if game.phase!="fight" or game.player.hp<=0:break
		var gap=game.player.position.distance_to(game.enemy.position)
		if gap>3.0:Input.action_press("move_up")
		else:Input.action_release("move_up")
		if tick%71==0:key(KEY_J,true);held=true
		if held and tick%71==2:key(KEY_J,false);held=false
		if tick%240==180:key(KEY_SPACE,true)
		if tick%240==182:key(KEY_SPACE,false)
		await frames(1)
	clear_input()
	finish_case(role+"/mounted/actual-AI-15s-max")

func run()->void:
	Engine.physics_ticks_per_second=60;Engine.time_scale=1
	game=load("res://main.tscn").instantiate();root.add_child(game);game.fx.muted=true
	await frames(10)
	await locked_controls()
	await free_controls()
	for role in ["zhaoyun","guanyu","xuchu"]:
		for lateral in [0.0,1.2,-1.2]:await passing(role,lateral)
	for role in ["zhaoyun","guanyu"]:await ai_trial(role)
	write_report(true);clear_input();game._reset_hit_feedback()
	print("CAVALRY BASELINE DONE ",cases.size());quit(0)
