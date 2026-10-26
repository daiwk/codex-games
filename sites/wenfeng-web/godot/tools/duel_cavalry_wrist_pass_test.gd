extends "res://tools/wrist_pose_test.gd"
var result_cases:Array=[]
var rate_diagnostics:Array=[]
var boot_cache:Dictionary={}
var seat_metrics:Dictionary={}
var pass_samples:Array=[]
var target_is_on_right=1
var report_path="/private/tmp/wenfeng-cavalry-wrist-passes-latest.json"

func observe()->void:
	super.observe()
	if not observing:return
	var actor=game.player
	var hips=bone(actor.skeleton,"Hips")
	var hip=actor.skeleton.get_bone_global_pose(hips)
	var expected_y=actor.horse.global_position.y+actor.horse.saddle_height()
	seat_metrics.seat=maxf(seat_metrics.seat,absf(actor.skeleton.to_global(hip.origin).y-expected_y))
	seat_metrics.hip_drift=maxf(seat_metrics.hip_drift,hip.origin.distance_to(actor.skeleton.get_bone_global_rest(hips).origin))
	for i in 2:
		var side="Left" if i==0 else "Right"
		var foot=bone(actor.skeleton,side+"Foot");var toe=bone(actor.skeleton,side+"ToeBase")
		var a=actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(foot).origin)
		var b=actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(toe).origin)
		boot_cache[i]=actor.model.to_local(a.lerp(b,.62)+Vector3.UP*.045)
	pass_samples.append({"frame":Engine.get_physics_frames(),"state":actor.state,"time":actor.action_time,"clip":actor.current_clip,
		"player_position":[actor.position.x,actor.position.y,actor.position.z],"target_position":[game.enemy.position.x,game.enemy.position.y,game.enemy.position.z],
		"actual_speed":actor.get_real_velocity().slide(Vector3.UP).length(),"target_speed":game.enemy.get_real_velocity().slide(Vector3.UP).length(),
		"gait":actor.cavalry_status().duplicate(true),"strike_forward":[actor.duel_strike_forward().x,actor.duel_strike_forward().y,actor.duel_strike_forward().z],
		"contact_latched":actor.contact_latched,"retraction":actor.contact_retraction,"hp":game.enemy.hp})

func check_drawn_grip()->void:
	super.check_drawn_grip()
	if not observing or boot_cache.size()!=2:return
	for i in 2:
		var expected=game.player.model.to_global(boot_cache[i])
		seat_metrics.boot=maxf(seat_metrics.boot,expected.distance_to(game.player.horse._stirrup_frames[i].global_position))
		seat_metrics.boot_samples+=1

func pass_case(role:String,side:int,wrong=false)->void:
	await setup(role,"mounted",34.0)
	game.player.rotation.y=0;game.enemy.rotation.y=PI
	game.player.position=Vector3(0,.015,-17)
	# side is anatomical rider side, never the geometric yaw API sign.
	var rider_right=game.player.forward().cross(Vector3.UP).normalized()
	game.enemy.position=game.player.position+game.player.forward()*34.0+rider_right*float(side)*1.65
	game.enemy.enabled=true;game.enemy.set_physics_process(true)
	game.player.set_cavalry_input(1,0,false);game.enemy.set_cavalry_input(1,0,false)
	await frames(5)
	var start_yaw=game.player.rotation.y
	var attack=game.player._weapon_adjusted_attack(game.player._light_attacks()[0])
	var window:Vector2=attack.active
	var launched=false;var accepted=false;var launch_info:Dictionary={}
	context=role+"/moving-pass/"+("rider-left" if side<0 else "rider-right")+("-wrong" if wrong else "")
	reset_metrics();loop_observing=false;boot_cache.clear();pass_samples=[]
	seat_metrics={"seat":0.0,"hip_drift":0.0,"boot":0.0,"boot_samples":0}
	for tick in 500:
		var longitudinal=game.enemy.position.z-game.player.position.z
		var closing=(game.player.get_real_velocity()-game.enemy.get_real_velocity()).dot(Vector3(0,0,1))
		var contact_time=(window.x+window.y)*.5 if game.player.is_two_handed() else window.x+.02
		var launch=1.1+maxf(0.0,closing)*contact_time
		if not launched and longitudinal<=launch and longitudinal>0:
			game.player.set_cavalry_attack_side(side if wrong else -side)
			observing=true;accepted=game.player.request_light();launched=true
			launch_info={"longitudinal":longitudinal,"closing":closing,"window":[window.x,window.y],"player_speed":game.player.get_real_velocity().length(),"target_speed":game.enemy.get_real_velocity().length(),"clip":game.player.current_clip}
		await physics_frame
		if launched and game.player.state in ["idle","move","block"]:
			await frames(12);break
	observing=false
	var damage=120.0-game.enemy.hp
	var last=game.last_melee_hit.duplicate(true)
	check(context+" real attack and recovery sampled",accepted and metrics.samples>8 and metrics.finite,{"samples":metrics.samples,"launch":launch_info})
	for arm in (["Left","Right"] if game.player.is_two_handed() else ["Right"]):
		check(context+" "+arm+" wrist swing <=40",metrics[arm+"_swing"]<=deg_to_rad(40)+.002,rad_to_deg(metrics[arm+"_swing"]))
		check(context+" "+arm+" wrist twist <=35",metrics[arm+"_twist"]<=deg_to_rad(35)+.002,rad_to_deg(metrics[arm+"_twist"]))
		for suffix in ["_world_forearm_rate","_world_hand_rate"]:
			if metrics[arm+suffix]>deg_to_rad(900):rate_diagnostics.append({"case":context,"side":arm,"kind":suffix,"degrees_per_second":rad_to_deg(metrics[arm+suffix]),"worst":metrics.worst.get(arm+suffix,{})})
	check(context+" actual skin volume >=.65",metrics.skin_samples>0 and metrics.skin_volume>=.65,{"volume":metrics.skin_volume,"samples":metrics.skin_samples})
	check(context+" actual bones preserve length",metrics.length_error<.002,metrics.length_error)
	check(context+" actual drawn palm-to-handle <=3.5cm",metrics.grip_samples>0 and metrics.grip<.035,{"grip":metrics.grip,"samples":metrics.grip_samples})
	check(context+" pelvis follows true moving saddle",seat_metrics.seat<.035 and seat_metrics.hip_drift<.001,seat_metrics)
	check(context+" final boot points stay in real stirrups",seat_metrics.boot_samples>0 and seat_metrics.boot<.035,seat_metrics)
	check(context+" horse heading not forced by side attack",absf(angle_difference(start_yaw,game.player.rotation.y))<.01,game.player.rotation.y)
	check(context+(" wrong side physically misses" if wrong else " real blade contact damages moving target"),is_zero_approx(damage) if wrong else damage>0,{"damage":damage,"last_hit":last})
	if not wrong and damage>0:
		var data:Dictionary=last.get("data",{})
		check(context+" actual relative-speed bonus bounded and not stacked",float(data.get("cavalry_multiplier",0))>=1 and float(data.get("cavalry_multiplier",2))<=1.65001 and is_equal_approx(float(last.damage),float(data.damage)),last)
	check(context+" real paths cross rather than stopping at target",game.player.position.z>game.enemy.position.z+1,{"p":game.player.position.z,"e":game.enemy.position.z})
	result_cases.append({"case":context,"expected_rider_side":side,"geometric_yaw_side":side if wrong else -side,"damage":damage,"last_melee_hit":last,"launch":launch_info,"metrics":metrics.duplicate(true),"seat":seat_metrics.duplicate(true),"samples":pass_samples.duplicate(true)})
	game.player.skeleton.skeleton_updated.disconnect(observe)
	write_report(false)

func write_report(completed:bool)->void:
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify({"completed":completed,"passed":completed and failures.is_empty(),"checks":checks,"failures":failures,"results":rows,"cases":result_cases,"rate_diagnostics":rate_diagnostics,
		"scope":"Full Main actual cavalry arena. Both real riders accelerate with public reins from +/-17m to a full-speed pass, 1.65m lanes constructed from forward cross UP, geometric API receives minus anatomical side. Same physical two-sided cases as the earlier integer-side test; old reports retain their original labels. J predicts the actual active-window centre at current closing speed. No velocity injection or body relocation during a pass. Independent final wrist/skin/bone/grip and real saddle/stirrup sampling includes recovery. >900 degrees/s is separately retained as diagnostics, not a claim that all motion is perfectly smooth. Both hands on 2H; Xu gripping right hand only."},"\t"))

func run()->void:
	Engine.physics_ticks_per_second=60;Engine.time_scale=1
	game=load("res://main.tscn").instantiate();root.add_child(game);game.testing=true;game.fx.muted=true;game.ai_enabled=false
	await frames(8)
	for role in ["zhaoyun","machao","guanyu","zhangfei","lubu","xuchu"]:
		for side in [-1,1]:await pass_case(role,side)
	for role in ["zhaoyun","guanyu"]:await pass_case(role,-1,true)
	write_report(true);game._reset_hit_feedback();print("CAVALRY WRIST PASS DONE ",checks," ",failures.size()," failures ",rate_diagnostics.size()," rate diagnostics");quit(0 if failures.is_empty() else 1)
