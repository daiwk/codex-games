extends "res://tools/duel_cavalry_flow_test.gd"
var checks:Array=[]
var failures:Array=[]

func _initialize()->void:
	output="/private/tmp/wenfeng-cavalry-control-latest.json"
	call_deferred("run")

func check(label:String,passed:bool,detail:Variant=null)->void:
	checks.append({"label":label,"passed":passed,"detail":detail})
	if not passed:failures.append(label)
	print("PASS " if passed else "FAIL ",label," ",JSON.stringify(detail))
	write_report(false)

func clear_input()->void:
	super.clear_input()
	for a in ["cavalry_left","cavalry_right","cavalry_brake"]:Input.action_release(a)

func actor_row(actor:Node3D,label:String)->Dictionary:
	var row=super.actor_row(actor,label)
	row["cavalry"]=actor.cavalry_status()
	row["actual_velocity"]=point(actor.get_real_velocity())
	return row

func prep(label:String,role="zhaoyun")->void:
	await prepare(role,"mounted",28.0)
	game.testing=true;observing=false
	game.player.position=Vector3(0,.015,-14)
	game.enemy.position=Vector3(12,.015,14)
	game.player.rotation.y=0;game.enemy.rotation.y=PI
	game.player.set_cavalry_input(0,0,false)
	await frames(8)
	samples=[];events=[];last_physics=-1;observing=true;phase_label=label

func controls()->void:
	await prep("real-InputMap-gait-brake-reverse")
	game.testing=false
	check("mounted field starts with 28m diameter allowance",game.player.movement_radius>=27.9,game.player.movement_radius)
	Input.action_press("move_up");await frames(120);Input.action_release("move_up")
	var fast=game.player.cavalry_status().duplicate(true)
	check("W builds real speed gradually",fast.signed_speed>5.5 and fast.signed_speed<=8.21,fast)
	var start=game.player.position;await frames(60)
	var released=game.player.cavalry_status().duplicate(true)
	check("released W retains gait without artificial stop",released.signed_speed>fast.signed_speed-.1 and (game.player.position-start).length()>5.0,released)
	var oldyaw=game.player.rotation.y
	await tap(KEY_TAB);await frames(20)
	check("real Tab changes camera lock without steering horse",absf(angle_difference(oldyaw,game.player.rotation.y))<.001,{"before":oldyaw,"after":game.player.rotation.y,"lock":game.lock_active()})
	Input.action_press("cavalry_brake");await frames(70);Input.action_release("cavalry_brake")
	var braked=game.player.cavalry_status().duplicate(true)
	check("X brakes actual horse and retained gait",absf(braked.signed_speed)<.05 and absf(braked.target_speed)<.05,braked)
	Input.action_press("move_down");await frames(100);Input.action_release("move_down")
	var reverse=game.player.cavalry_status().duplicate(true)
	check("S gives bounded actual reverse after stopping",reverse.signed_speed<-.8 and reverse.signed_speed>=-2.01,reverse)
	var tree=game.player.horse.get("_animation_tree") as AnimationTree
	check("reverse has actual backward gait cadence",tree!=null and float(tree.get("parameters/Cadence/scale"))<0,float(tree.get("parameters/Cadence/scale")) if tree else 0)
	finish_case("real-InputMap-WSX-and-Tab")

func turning(high:bool)->float:
	await prep("high-speed-turn" if high else "slow-turn")
	game.testing=false
	Input.action_press("move_up");await frames(165 if high else 45);Input.action_release("move_up")
	Input.action_press("move_right");await frames(60);Input.action_release("move_right")
	var status=game.player.cavalry_status().duplicate(true)
	var lateral=absf(Vector3(game.player.velocity.x,0,game.player.velocity.z).dot(game.player.global_basis.x))
	check(("high" if high else "low")+" turn moves along actual horse heading",lateral<.03,{"side_velocity":lateral,"status":status})
	check(("high" if high else "low")+" turn does not exceed new speed cap",absf(status.signed_speed)<=8.21,status)
	finish_case("high-turn" if high else "low-turn")
	return absf(status.turn_rate)

func wall()->void:
	await prep("real-wall-blocks-speed")
	game.player.position=Vector3(0,.015,-6)
	game.enemy.position=Vector3(12,.015,10)
	var body=StaticBody3D.new();body.collision_layer=1
	var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(12,6,.4);shape.shape=box
	body.position=Vector3(0,3,0);body.add_child(shape);game.add_child(body)
	game.player.set_cavalry_input(1,0,false);await frames(200)
	var status=game.player.cavalry_status().duplicate(true)
	check("solid wall stops actual movement and HUD speed",game.player.position.z<-.4 and absf(status.signed_speed)<.08 and game.player.mount_speed<.08,{"position":point(game.player.position),"status":status,"hud_speed":game.player.mount_speed})
	var data=game.player.cavalry_impact_data(game.enemy,{"damage":18.0})
	check("blocked horse has no phantom speed bonus",is_equal_approx(float(data.cavalry_multiplier),1.0),data)
	finish_case("solid-wall-stop")
	body.queue_free();await frames(3)

func ai_flow_new()->void:
	await prep("actual-mounted-director")
	game.player.position=Vector3(0,.015,-14);game.enemy.position=Vector3(0,.015,14)
	game.enemy.enabled=true;game.enemy.set_physics_process(true);game.ai_enabled=true
	game.player.set_cavalry_input(.8,0,false)
	var phases:Dictionary={};var saw_return=false
	for i in 1800:
		if game.phase!="fight":break
		var phase=game.cavalry_director.phase
		phases[phase]=int(phases.get(phase,0))+1
		# Stable genuine player reins through the same motion API. Turn left
		# before reaching the field edge, brake for a broad return then ride.
		var radius=Vector2(game.player.position.x,game.player.position.z).length()
		if radius>22:game.player.set_cavalry_input(-.5,1.0,game.player.mount_speed>6)
		elif i>250:game.player.set_cavalry_input(.35,.35,false)
		if i%110==0:game.player.request_light()
		await frames(1)
	check("actual cavalry AI performs approach and committed pass",phases.has("approach") and phases.has("pass"),phases)
	check("actual cavalry AI extends and turns for another pass",phases.has("extend") and phases.has("turn"),phases)
	finish_case("actual-director-30s-max")
	cases.back()["director_phases"]=phases

func lifecycle_new()->void:
	await prep("reset-cavalry-lifecycle")
	game.player.set_cavalry_input(1,.4,false);await frames(45)
	game.toggle_pause()
	var position=game.player.position;var status=game.player.cavalry_status().duplicate(true)
	await frames(30)
	check("pause freezes physical rider position and speed",game.player.position.distance_to(position)<.0001 and is_equal_approx(game.player.cavalry_status().signed_speed,status.signed_speed))
	game.toggle_pause();game._new_round();await frames(3)
	status=game.player.cavalry_status().duplicate(true)
	check("new round resets gait turn and pending attack side",absf(status.signed_speed)<.001 and absf(status.target_speed)<.001 and absf(status.turn_rate)<.001 and int(status.attack_side)==0,status)
	check("new round gives room for real approach",game.player.position.distance_to(game.enemy.position)>27.9,{"p":point(game.player.position),"e":point(game.enemy.position)})

func write_report(completed:bool)->void:
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"completed":completed,"passed":completed and failures.is_empty(),"checks":checks,"failures":failures,"cases":cases,
		"scope":"Native full Main/new real cavalry arena. Controls go through InputMap and actual Tab; passing uses public reins and side-input API, with both bodies moving and unmodified real strike resolver. Native fixed engine clock, not a Web/FPS claim. AI uses real director. No position rewrite occurs during a pass."},"\t"))

func run()->void:
	Engine.physics_ticks_per_second=60;Engine.time_scale=1
	game=load("res://main.tscn").instantiate();root.add_child(game);game.testing=true;game.fx.muted=true;game.ai_enabled=false
	await frames(8)
	await controls()
	var low=await turning(false);var high=await turning(true)
	check("high speed turn is wider than low speed turn",high<low and high<.8 and low>1.0,{"low":low,"high":high})
	await wall()
	await ai_flow_new();await lifecycle_new()
	write_report(true);clear_input();game._reset_hit_feedback();print("CAVALRY MAIN DONE ",checks.size()," ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
