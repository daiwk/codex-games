extends SceneTree
var game
var driver
var active=false
var tick=0
var config:Dictionary={}
var rows:Array=[]
var events:Array=[]
var attempts:Array=[]
var cases:Array=[]
var output_path=""
var quick=false
class Driver extends Node:
	var callback:Callable
	func _physics_process(_dt):callback.call()
func _initialize():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output_path=arg.trim_prefix("--output=")
		if arg=="--quick":quick=true
	if not output_path.is_absolute_path():
		printerr("Pass --output=/absolute/writable/report.json");quit(2);return
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	call_deferred("run")
func frames(n:int):
	for i in n:
		await physics_frame
		await process_frame
func v(p:Vector3):return [p.x,p.y,p.z]
func stats(a):return {"state":a.state,"clip":a.current_clip,"action_time":a.action_time,"hp":a.hp,"stamina":a.stamina,"energy":a.energy,"position":v(a.position),"velocity":v(a.velocity),"wants_block":a.wants_block,"action_duration":a.action_duration}
func input_tick():
	if not active:return
	if tick in config.taps:
		game.queue_combat_input("light");events.append({"kind":"J_intent","tick":tick,"physics":Engine.get_physics_frames()})
	game.enemy.wants_block=(config.get("guard","")=="hold")
	if config.get("guard","")=="parry_lift":game.enemy.wants_block=tick>=70
	if config.get("guard","")=="parry_down":game.enemy.wants_block=tick<86 or tick>=94
	game._player_input()
	tick+=1
func source_event(row:Dictionary):
	if not active:return
	var r=row.duplicate(true);r["tick"]=tick;r["player"]=stats(game.player);r["enemy"]=stats(game.enemy);r["last_melee_hit"]=game.last_melee_hit.duplicate(true);events.append(r)
func impact(actor,result,at):
	if active:events.append({"kind":"impact","victim":"player" if actor==game.player else "enemy","outcome":result,"at":v(at),"tick":tick,"physics":Engine.get_physics_frames(),"source":game.player.source_combo_status(),"player":stats(game.player),"enemy":stats(game.enemy)})
func attempted(actor,profile):
	if not active:return
	var lo=game.enemy.thrust_body_low();var hi=game.enemy.thrust_body_high()
	var pair=Geometry3D.get_closest_points_between_segments(actor.blade_base(),actor.blade_tip(),lo,hi)
	var swept=Geometry3D.get_closest_points_between_segments(actor.previous_tip,actor.blade_tip(),lo,hi)
	attempts.append({"tick":tick,"physics":Engine.get_physics_frames(),"profile":profile.duplicate(true),"blade_base":v(actor.blade_base()),"blade_tip":v(actor.blade_tip()),"previous_tip":v(actor.previous_tip),"body_low":v(lo),"body_high":v(hi),"distance":minf(pair[0].distance_to(pair[1]),swept[0].distance_to(swept[1])),"player":stats(game.player),"enemy":stats(game.enemy),"registered_contact":actor.hit_landed,"last_melee_hit":game.last_melee_hit.duplicate(true)})
func one_case(c:Dictionary):
	active=false;game.return_to_menu();game.select_combat_mode("foot");game.select_character("xuchu");game.select_weapon("xuchu_saber");game.select_opponent("zhaoyun");await frames(4)
	game.start_match();game.phase="fight";game.testing=true;game.ai_enabled=false;game.player.enabled=true;game.enemy.enabled=true;game.enemy.set_physics_process(true)
	game.player.position=Vector3(0,.015,-float(c.gap)/2);game.enemy.position=Vector3(0,.015,float(c.gap)/2);game.player.rotation.y=0;game.enemy.rotation.y=PI
	game.player.energy=0;game.enemy.energy=0;game.player.source_combo_event.connect(source_event);game.player.strike_requested.connect(attempted);game.player.impact_received.connect(impact);game.enemy.impact_received.connect(impact)
	game.enemy.wants_block=c.get("guard","") in ["hold","parry_down"]
	await frames(20)
	config=c;rows=[];events=[];attempts=[];tick=0;active=true
	for i in int(float(c.seconds)*60):
		await physics_frame
		await process_frame
		rows.append({"tick":tick,"physics":Engine.get_physics_frames(),"source":game.player.source_combo_status(),"player":stats(game.player),"enemy":stats(game.enemy),"last_melee_hit":game.last_melee_hit.duplicate(true)})
	active=false
	var result={"fixture":c,"damage":120-game.enemy.hp,"source":game.player.source_combo_status(),"events":events.duplicate(true),"attempts":attempts.duplicate(true),"frames":rows.duplicate(true)};cases.append(result)
	FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify(cases));print("TWO_BEAT ",c.name," damage=",result.damage," player=",game.player.state," enemy=",game.enemy.state)
func run():
	Engine.physics_ticks_per_second=60;driver=Driver.new();driver.callback=input_tick;root.add_child(driver);game=load("res://main.tscn").instantiate();root.add_child(game);game.testing=true;game.ai_enabled=false;game.fx.muted=true;await frames(5)
	if quick:
		await one_case({"name":"JJJ_dynamic_1.7","gap":1.7,"taps":[6,18,44],"seconds":4.0})
	else:
		for gap in [1.15,1.7,2.0,2.3,6.0]:
			for n in [1,2,3]:await one_case({"name":"J".repeat(n)+"_dynamic_"+str(gap),"gap":gap,"taps":[6] if n==1 else ([6,18] if n==2 else [6,18,44]),"seconds":2.3 if n==1 else (2.8 if n==2 else 4.0)})
		for pattern in ["hold","parry_lift","parry_down"]:
			await one_case({"name":"JJJ_"+pattern,"gap":1.15,"taps":[6,18,44],"seconds":4.0,"guard":pattern})
	game._reset_hit_feedback();print("TWO_BEAT_COMPLETE");quit()
