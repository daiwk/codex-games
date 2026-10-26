extends "res://tools/wrist_pose_test.gd"
const ROLES=["zhaoyun","machao","guanyu","zhangfei","lubu","xuchu"]
var result_cases:Array=[]
var trace:Array=[]
var events:Array=[]
var jump_starts=0
var jump_lands=0
var recording=false
var last_frame=-1
var seat={}
var boots={}
var baseline_leg:Quaternion
var leg_set=false
var max_leg_angle=0.0
var baseline_horse_leg:Quaternion
var horse_leg_set=false
var max_horse_leg_angle=0.0
var last_draw_stage=""
var out="/private/tmp/wenfeng-jump-independent-latest.json"
func observe()->void:
	if recording and last_frame!=Engine.get_physics_frames():
		last_frame=Engine.get_physics_frames()
		trace.append({"frame":last_frame,"y":game.player.position.y,"state":game.player.state,"clip":game.player.current_clip,"jump":game.player.jump_status().duplicate(true),"on_floor":game.player.is_on_floor(),"stamina":game.player.stamina,"energy":game.player.energy})
	super.observe()
	if not observing:return
	var actor=game.player
	var leg=actor.skeleton.get_bone_global_pose(bone(actor.skeleton,"LeftLeg")).basis.get_rotation_quaternion()
	if not leg_set and not actor.is_jumping():baseline_leg=leg;leg_set=true
	if leg_set and actor.is_jumping():max_leg_angle=maxf(max_leg_angle,baseline_leg.angle_to(leg))
	if actor.mounted:
		var hip=actor.skeleton.get_bone_global_pose(bone(actor.skeleton,"Hips"))
		seat.error=maxf(seat.error,absf(actor.skeleton.to_global(hip.origin).y-(actor.horse.global_position.y+actor.horse.saddle_height())))
		for i in 2:
			var side="Left" if i==0 else "Right"
			var foot=actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(bone(actor.skeleton,side+"Foot")).origin)
			var toe=actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(bone(actor.skeleton,side+"ToeBase")).origin)
			boots[i]=actor.model.to_local(foot.lerp(toe,.62)+Vector3.UP*.045)
func observe_horse()->void:
	if not recording or not observing:return
	var rig:Skeleton3D=game.player.horse._skeleton
	var index=rig.find_bone("FrontUpperLeg.L")
	if index<0:return
	var pose=rig.get_bone_global_pose(index).basis.get_rotation_quaternion()
	if not horse_leg_set and not game.player.is_jumping():baseline_horse_leg=pose;horse_leg_set=true
	if horse_leg_set and game.player.is_jumping():max_horse_leg_angle=maxf(max_horse_leg_angle,baseline_horse_leg.angle_to(pose))
func check_drawn_grip()->void:
	super.check_drawn_grip()
	if not observing or not game.player.mounted or boots.size()!=2:return
	for i in 2:
		seat.boot=maxf(seat.boot,game.player.model.to_global(boots[i]).distance_to(game.player.horse._stirrup_frames[i].global_position));seat.samples+=1
func started(_actor:Node)->void:
	if recording:jump_starts+=1
func landed(_actor:Node,_at:Vector3)->void:
	if recording:jump_lands+=1
func skill_event(actor:Node,id:String,stage:String)->void:
	if recording and actor==game.player:events.append({"id":id,"stage":stage,"y":actor.position.y,"airborne":actor.jump_status().airborne,"jump_phase":actor.jump_status().phase,"frame":Engine.get_physics_frames()})
func key(code:int,down:bool)->void:
	var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;Input.parse_input_event(e)
func prepare_case(role:String,mode:String,label:String)->void:
	recording=false;observing=false;key(KEY_V,false)
	await setup(role,mode,6.0)
	await frames(10)
	context=label;trace=[];events=[];jump_starts=0;jump_lands=0;last_frame=-1;seat={"error":0.0,"boot":0.0,"samples":0};boots.clear();leg_set=false;max_leg_angle=0;horse_leg_set=false;max_horse_leg_angle=0
	if game.player.mounted:game.player.horse._skeleton.skeleton_updated.connect(observe_horse)
	game.player.jump_started.connect(started);game.player.jump_landed.connect(landed);game.player.skill_triggered.connect(skill_event)
	recording=true
func wait_land(limit=180)->bool:
	for i in limit:
		await frames(1)
		if not game.player.is_jumping() and game.player.is_on_floor():return true
	return false
func wait_air()->bool:
	var y=game.player.position.y
	for i in 35:
		await frames(1)
		if game.player.jump_status().airborne and not game.player.is_on_floor() and game.player.position.y>y+.04:return true
	return false
func basic(role:String,mode:String)->void:
	await prepare_case(role,mode,role+"/"+mode+"/jump-anatomy")
	reset_metrics();observing=true;await frames(2)
	var start_y=game.player.position.y;var stamina=game.player.stamina;var energy=game.player.energy
	var accepted=false
	if role=="zhaoyun":
		key(KEY_V,true);await frames(2);key(KEY_V,false);accepted=game.player.is_jumping()
	else:accepted=game.player.request_jump()
	var no_double=not game.player.request_jump()
	var unchanged=is_equal_approx(stamina,game.player.stamina) and is_equal_approx(energy,game.player.energy)
	var air=await wait_air();var completed=await wait_land();await frames(3);observing=false
	var peak=start_y
	for row in trace:peak=maxf(peak,float(row.y))
	check(context+" accepted with actual physical airborne body",accepted and air and peak-start_y>.9 and peak-start_y<1.6,{"peak_delta":peak-start_y,"starts":jump_starts})
	check(context+" no double jump and no resource cost",no_double and unchanged,{"double_refused":no_double,"unchanged":unchanged})
	check(context+" real floor landing event and cleared recovery",completed and jump_starts==1 and jump_lands==1 and game.player.jump_status().can_jump,{"starts":jump_starts,"lands":jump_lands,"status":game.player.jump_status()})
	check(context+(" actual final horse foreleg folds" if mode=="mounted" else " actual final rider leg folds"),(max_horse_leg_angle if mode=="mounted" else max_leg_angle)>.10,{"rider_degrees":rad_to_deg(max_leg_angle),"horse_degrees":rad_to_deg(max_horse_leg_angle)})
	for side in (["Left","Right"] if game.player.is_two_handed() else ["Right"]):
		check(context+" "+side+" wrist swing <=40",metrics[side+"_swing"]<=deg_to_rad(40)+.002,rad_to_deg(metrics[side+"_swing"]))
		check(context+" "+side+" wrist twist <=35",metrics[side+"_twist"]<=deg_to_rad(35)+.002,rad_to_deg(metrics[side+"_twist"]))
	check(context+" actual skin volume >=.65",metrics.skin_samples>0 and metrics.skin_volume>=.65,metrics.skin_volume)
	check(context+" bone lengths and drawn handle remain correct",metrics.length_error<.002 and metrics.grip_samples>0 and metrics.grip<.035,{"bone":metrics.length_error,"grip":metrics.grip,"samples":metrics.grip_samples})
	if mode=="mounted":check(context+" actual moving saddle and final boots stay <=3.5cm",seat.error<.035 and seat.boot<.035 and seat.samples>0,seat)
	result_cases.append({"case":context,"peak_delta":peak-start_y,"rider_leg_degrees":rad_to_deg(max_leg_angle),"horse_leg_degrees":rad_to_deg(max_horse_leg_angle),"metrics":metrics.duplicate(true),"seat":seat.duplicate(true),"trace":trace.duplicate(true)})
	write_report(false)
func air_skill(role:String,mode:String,id:String)->void:
	await prepare_case(role,mode,role+"/"+mode+"/air-"+id)
	if id=="ultimate":game.player.energy=100 # Explicit native gate, never browser energy or claimed earned progression.
	var jumped=game.player.request_jump();var air=await wait_air()
	var before_s=game.player.stamina;var before_e=game.player.energy
	var cost=game.player.skill_cost(id) if id!="ultimate" else 0.0
	var accepted=game.player.request_ultimate() if id=="ultimate" else game.player.request_skill(id)
	var immediate_s=game.player.stamina;var immediate_e=game.player.energy
	var after_jump=game.player.is_jumping()
	for i in 300:
		await frames(1)
		if game.player.state in ["idle","move","block"] and not game.player.is_jumping() and game.specials.groups.is_empty():break
	var starts=0;var releases=0;var completes=0
	for e in events:
		if e.id!=id:continue
		if e.stage=="start":starts+=1
		if e.stage=="release":releases+=1
		if e.stage=="complete":completes+=1
	check(context+" accepts actual skill while body is off floor",jumped and air and accepted and after_jump,{"accepted":accepted,"first":events[0] if not events.is_empty() else {},"jump":game.player.jump_status()})
	check(context+" original resource gate spends exactly once",is_equal_approx(before_e-immediate_e,100.0) if id=="ultimate" else is_equal_approx(before_s-immediate_s,cost),{"stamina":[before_s,immediate_s],"energy":[before_e,immediate_e],"cost":cost})
	check(context+" actual full start-release-complete events",starts==1 and releases>=1 and completes==1,{"starts":starts,"releases":releases,"completes":completes,"events":events})
	check(context+" lands and cleans ownership",game.player.is_on_floor() and not game.player.is_jumping() and game.specials.groups.is_empty() and game.player.weapon_mesh.visible,game.specials.debug_state())
	result_cases.append({"case":context,"events":events.duplicate(true),"damage":120-game.enemy.hp,"stamina_before":before_s,"stamina_immediate":immediate_s,"energy_before":before_e,"energy_immediate":immediate_e,"trace":trace.duplicate(true)})
	write_report(false)
func lifecycle(mode:String,kind:String)->void:
	await prepare_case("zhaoyun",mode,mode+"/"+kind)
	var actor=game.player
	actor.request_jump();await wait_air();var before_y=actor.position.y;var before_xz=Vector2(actor.position.x,actor.position.z)
	if kind=="pause":
		game.toggle_pause();var before=actor.jump_status().duplicate(true);await frames(20)
		check(context+" freezes actual body and timer",is_equal_approx(actor.position.y,before_y) and is_equal_approx(actor.jump_status().flight_time,before.flight_time),actor.jump_status())
		game.toggle_pause();check(context+" resumes real fall and landing",await wait_land(),actor.jump_status())
	elif kind=="reset":
		actor.reset_fighter();check(context+" immediately clears jump and restores snap",not actor.is_jumping() and is_equal_approx(actor.floor_snap_length,.2),actor.jump_status())
		await frames(80);check(context+" reset body still obeys gravity",actor.is_on_floor(),actor.position.y)
	elif kind=="disabled":
		actor.enabled=false;var accepted=actor.request_skill("rush");await frames(100)
		check(context+" disabled keeps gravity but cannot attack or drift",not accepted and actor.is_on_floor() and not actor.is_jumping() and Vector2(actor.position.x,actor.position.z).distance_to(before_xz)<.01,{"position":actor.position,"jump":actor.jump_status()})
	elif kind=="death":
		actor.hp=1;actor.receive_strike(game.enemy,game.enemy._heavy_attack_profile());await frames(100)
		check(context+" lethal receiver still lands without reusable jump",actor.hp<=0 and actor.is_on_floor() and not actor.is_jumping() and not actor.request_jump(),{"hp":actor.hp,"status":actor.jump_status()})
	result_cases.append({"case":context,"trace":trace.duplicate(true)})
	write_report(false)
func write_report(done:bool)->void:
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({"completed":done,"passed":done and failures.is_empty(),"checks":checks,"failures":failures,"results":rows,"cases":result_cases,
		"scope":"Independent actual Main scene, all six heroes foot/mounted physical jump; actual final skeleton modifier callbacks for wrist/skin/length/grip and saddle/stirrups. Actual V proves Zhao foot/mounted input, API for other deterministic cases. 36 air Q/E/U resource/start/release/complete paths; native energy100 explicitly for U only, no guarantee ground targets must all be hit. Pause/reset/disabled/death actual physics. No source GLB/production modification."},"\t"))
func run()->void:
	Engine.physics_ticks_per_second=60;Engine.time_scale=1
	game=load("res://main.tscn").instantiate();root.add_child(game);game.testing=true;game.fx.muted=true;game.ai_enabled=false
	await frames(6)
	for mode in ["foot","mounted"]:
		for role in ROLES:await basic(role,mode)
	for mode in ["foot","mounted"]:
		for role in ROLES:
			for id in ["rush","counter","ultimate"]:await air_skill(role,mode,id)
	for mode in ["foot","mounted"]:
		for kind in ["pause","reset","disabled","death"]:await lifecycle(mode,kind)
	write_report(true);game._reset_hit_feedback();print("INDEPENDENT DUEL JUMP DONE ",checks," ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
