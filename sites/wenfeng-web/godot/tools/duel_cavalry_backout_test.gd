extends SceneTree
var game:Node3D
var results:Array=[]
var checks:Array=[]
var failures:Array=[]
var attacks:Array=[]
var clock=0.0
var recording=false
const OUT="/private/tmp/wenfeng-cavalry-backout-latest.json"
func _initialize()->void:call_deferred("run")
func frames(n:int)->void:
	for i in n:await physics_frame
func p(v:Vector3)->Array:return [v.x,v.y,v.z]
func check(label:String,passed:bool,detail:Variant=null)->void:
	checks.append({"label":label,"passed":passed,"detail":detail});if not passed:failures.append(label)
	print("PASS " if passed else "FAIL ",label," ",JSON.stringify(detail));write(false)
func action(actor:Node,kind:String)->void:
	if recording and actor==game.enemy and kind in ["light","heavy"]:
		attacks.append({"time":clock,"phase":game.cavalry_director.phase,"kind":kind,"gap":(game.enemy.position-game.player.position).slide(Vector3.UP).length()})
func setup(gap:float)->void:
	recording=false;game.return_to_menu();game.select_combat_mode("mounted");game.select_character("zhaoyun");game.select_opponent("machao")
	await frames(3);game.start_match();game.testing=true;game.phase="fight";game.ai_enabled=false;game.player.enabled=true;game.enemy.enabled=true
	game.player.position=Vector3(0,.015,-gap*.5);game.enemy.position=Vector3(0,.015,gap*.5);game.player.rotation.y=0;game.enemy.rotation.y=PI
	game.player.set_cavalry_input(0,0,false);game.enemy.set_cavalry_input(0,0,false)
	await frames(15);game.rng.seed=714;game.enemy.action_started.connect(action);game.ai_enabled=true
func exercise(label:String,gap:float,pressure:bool)->void:
	await setup(gap)
	game.player.set_cavalry_input(1 if pressure else 0,0,false)
	var samples:Array=[];var phases:Dictionary={};var first_back=-1.0;var first_open=-1.0;var first_clear=-1.0;var min_gap=INF;var max_step=0.0
	var previous=game.enemy.position;clock=0;attacks=[];recording=true
	for i in 900:
		await physics_frame
		clock+=game.enemy.get_physics_process_delta_time()
		var distance=(game.enemy.position-game.player.position).slide(Vector3.UP).length();min_gap=minf(min_gap,distance)
		var phase=String(game.cavalry_director.phase);phases[phase]=int(phases.get(phase,0))+1
		if phase=="back_out" and first_back<0:first_back=clock
		if first_back>=0 and first_open<0 and distance>1.8:first_open=clock
		if first_back>=0 and first_clear<0 and distance>2.6:first_clear=clock
		max_step=maxf(max_step,(game.enemy.position-previous).slide(Vector3.UP).length());previous=game.enemy.position
		samples.append({"time":clock,"frame":Engine.get_physics_frames(),"phase":phase,"gap":distance,"player":p(game.player.position),"enemy":p(game.enemy.position),
			"player_hp":game.player.hp,"enemy_hp":game.enemy.hp,"player_speed":game.player.mount_speed,"enemy_speed":game.enemy.mount_speed,"enemy_cavalry":game.enemy.cavalry_status().duplicate(true)})
		if game.phase!="fight":break
	recording=false
	var no_new_while_back=true;var reengaged=false
	for e in attacks:
		no_new_while_back=no_new_while_back and e.phase!="back_out"
		if first_clear>=0 and e.time>first_clear:reengaged=true
	results.append({"label":label,"initial_gap":gap,"player_forward_reins":pressure,"first_back_out":first_back,"first_open_1p8":first_open,"first_clear_2p6":first_clear,
		"min_gap":min_gap,"max_enemy_movement_per_tick":max_step,"phases":phases,"new_attacks":attacks.duplicate(true),"samples":samples,"final_player_hp":game.player.hp})
	if gap<1.8:
		check(label+" enters real blocked withdrawal",first_back>=.6 and first_back<4,{"first":first_back,"phases":phases})
		check(label+" actually opens body gap above1.8",first_open>=0 and first_open<6,first_open)
		check(label+" clears2.6 and reengages",first_clear>=0 and first_clear<8 and reengaged,{"clear":first_clear,"attacks":attacks})
	else:check(label+" normal approach still passes and attacks",phases.has("pass") and not attacks.is_empty(),{"phases":phases,"attacks":attacks})
	check(label+" back_out cannot launch new normal attacks",no_new_while_back,attacks)
	check(label+" real physics withdrawal never teleports",max_step<=8.3/60.0+.04,max_step)
	write(false)
func write(done:bool)->void:
	FileAccess.open(OUT,FileAccess.WRITE).store_string(JSON.stringify({"completed":done,"passed":done and failures.is_empty(),"checks":checks,"failures":failures,"cases":results,
		"scope":"Actual Main and final cavalry director, both CharacterBodies enabled. Only initial placement/reins set; no position or velocity rewrite during trial, no HP/invulnerability/weapon geometry change. Fixed60 native offline mechanics evidence. Near stationary and forward-pressure plus genuine approach; other skill/motion suites not repeated."},"\t"))
func run()->void:
	Engine.physics_ticks_per_second=60;Engine.time_scale=1
	game=load("res://main.tscn").instantiate();root.add_child(game);game.testing=true;game.fx.muted=true;game.ai_enabled=false
	await frames(8)
	await exercise("near-stationary-player",1.3,false)
	await exercise("near-forward-pressure",1.3,true)
	await exercise("normal-moving-approach",16,true)
	write(true);game._reset_hit_feedback();print("BACKOUT DONE ",checks.size()," ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
