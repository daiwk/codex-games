extends "res://tools/duel_specials_test.gd"
const ARMY = [
	["zhaoyun","spear_volley",7,10.0],
	["machao","cavalry",6,12.0],
	["guanyu","diagonal_cleave",3,24.0],
	["zhangfei","ground_pincer",5,14.0],
	["lubu","halberd_encircle",6,12.0],
	["xuchu","returning_fan",3,22.0]
]
var group_snapshots:Array=[]
var first_contact_age=-1.0
var baseline_y=0.0

func _initialize()->void:
	report_path="/private/tmp/wenfeng-army-main-latest.json"
	call_deferred("run")

func sample()->void:
	super.sample()
	if not observing:return
	if group_snapshots.size()<4 and not game.specials.groups.is_empty():
		group_snapshots.append(game.specials.debug_state())

func contact(attacker: Node, defender: Node, data: Dictionary, at: Vector3)->void:
	super.contact(attacker,defender,data,at)
	if observing and attacker==game.player and first_contact_age<0:
		for group in game.specials.groups.values():
			if group.owner==attacker.get_instance_id():first_contact_age=group.age;break

func army_case(spec:Array,mode:String,scenario:String)->void:
	var role:String=spec[0]
	await setup(role,mode,6.0)
	current={"role":role,"mode":mode,"scenario":scenario,"formation":spec[1]}
	group_snapshots=[];first_contact_age=-1;baseline_y=game.player.position.y
	var wall:StaticBody3D=null
	if scenario=="wall":wall=make_wall();await frames(2)
	var label=role+"/"+mode+"/"+scenario
	verify(label+" gate accepts real U",start_skill("ultimate"))
	verify(label+" real release creates formation",await spawn_wait())
	var snapshot=game.specials.debug_state()
	var own:Array=[]
	for group in snapshot.groups:
		if group.owner==game.player.get_instance_id():own.append(group)
	verify(label+" one owned formation",own.size()==1,snapshot)
	if not own.is_empty():
		var group:Dictionary=own[0]
		verify(label+" expected actual entity count",group.entities.size()==int(spec[2]),group.entities.size())
		verify(label+" expected mechanism",group.type==("cavalry" if role=="machao" else "weapon_array") and (role=="machao" or group.formation==String(spec[1])),group)
		if role!="machao":verify(label+" uses current real weapon asset",group.weapon_id==game.player.weapon_id,{"entity":group.weapon_id,"equipped":game.player.weapon_id})
		if role=="zhaoyun":verify(label+" seven spears not sword",group.weapon_id=="serpent_spear" and group.weapon_id!="sword",group.weapon_id)
	if scenario=="moving_escape":
		# Same actual CharacterBody moves through its ordinary locomotion. No
		# target teleport, invulnerability or target/energy rewrite after cast.
		game.enemy.input_move=Vector3.RIGHT
	await complete_wait(360)
	await frames(12)
	observing=false
	var damage=initial_hp-game.enemy.hp
	var unique:Dictionary={};var tracked=0.0
	for hit in contacts:unique[str(hit.volley)+":"+str(hit.index)]=true;tracked+=float(hit.damage)
	cases.append({"context":current.duplicate(true),"damage":damage,"contacts":contacts.duplicate(true),"first_contact_group_age":first_contact_age,
		"peak_actor_y":peak_y,"baseline_y":baseline_y,"peak_entities":peak_entities,"group_samples":group_snapshots.duplicate(true),
		"target_final":point(game.enemy.position),"weapon_hidden":weapon_hidden,"weapon_visible_final":game.player.weapon_mesh.visible,
		"final_groups":game.specials.debug_state(),"camera_outside":camera_outside.duplicate()})
	verify(label+" no invisible duplicate melee HP",is_equal_approx(tracked,damage) and unique.size()==contacts.size(),{"damage":damage,"tracked":tracked,"unique":unique.size(),"contacts":contacts.size()})
	verify(label+" each entity hits at most once",contacts.size()<=int(spec[2]),contacts.size())
	verify(label+" complete cleanup and weapon returned",game.specials.groups.is_empty() and game.player.weapon_mesh.visible and not game.player.duel_weapon_is_thrown(),game.specials.debug_state())
	if scenario=="hit":verify(label+" all actual entity contacts and damage",contacts.size()==int(spec[2]) and is_equal_approx(damage,float(spec[2])*float(spec[3])),{"damage":damage,"contacts":contacts.size(),"expected":float(spec[2])*float(spec[3])})
	else:verify(label+" actual blocked or evaded route has no HP loss",is_zero_approx(damage) and contacts.is_empty(),{"damage":damage,"contacts":contacts})
	if role=="lubu":
		verify(label+" remains grounded without old rigid launch",peak_y-baseline_y<0.08 and landed_frames.is_empty() and not game.player.duel_is_airborne(),{"peak":peak_y,"baseline":baseline_y,"landings":landed_frames})
		if scenario=="hit":verify(label+" real warning before contact",first_contact_age>=0.55,first_contact_age)
	if role=="xuchu":verify(label+" held weapon hides and truly returns",weapon_hidden and game.player.weapon_mesh.visible)
	if wall!=null:wall.queue_free();await frames(2)
	write_report(false)

func array_lifecycle()->void:
	await setup("xuchu","mounted",6.0)
	start_skill("ultimate");verify("Xu U lifecycle group exists",await spawn_wait())
	await frames(2)
	var ages:Dictionary={}
	for id in game.specials.groups:ages[id]=game.specials.groups[id].age
	var hp=game.enemy.hp
	game.toggle_pause();await frames(20)
	var same=true
	for id in ages:same=same and game.specials.groups.has(id) and is_equal_approx(ages[id],game.specials.groups[id].age)
	verify("pause freezes formation route HP and hide state",same and is_equal_approx(hp,game.enemy.hp) and not game.player.weapon_mesh.visible)
	game.toggle_pause();game.player._idle();await frames(2)
	verify("actual cancel returns Xu weapon and removes owner groups",game.specials.groups.is_empty() and game.player.weapon_mesh.visible and not game.player.duel_weapon_is_thrown())
	await setup("zhaoyun","foot",6.0)
	start_skill("ultimate");await spawn_wait();game.player.hp=1.0
	game.player.receive_strike(game.enemy,game.enemy._heavy_attack_profile());await frames(3)
	verify("real lethal receiver cancels owned array",game.player.hp<=0 and game.specials.groups.is_empty())
	await setup("lubu","mounted",6.0)
	start_skill("ultimate");await spawn_wait();game._new_round();await frames(4)
	verify("round reset clears arrays and riders",game.specials.groups.is_empty() and game.player.weapon_mesh.visible and not game.player.duel_is_airborne())
	game.return_to_menu();game.select_combat_mode("foot");await frames(3)
	verify("mode switch rebuilds proper foot arena",not game.player.mounted and String(game.arena.get_script().resource_path).ends_with("arena.gd") and not String(game.arena.get_script().resource_path).ends_with("cavalry_arena.gd"),game.arena.get_script().resource_path)
	game.select_combat_mode("mounted");await frames(3)
	verify("mode switch uses new real cavalry arena",game.player.mounted and String(game.arena.get_script().resource_path).ends_with("duel_cavalry_arena.gd"),game.arena.get_script().resource_path)

func write_report(completed:bool)->void:
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify({"completed":completed,"passed":completed and failures.is_empty(),"checks":checks.size(),"failures":failures,"results":checks,"cases":cases,
		"scope":"Actual Main, real request_ultimate/release/receiver, six heroes foot and mounted. Native energy100 gate fixture only. Evasion uses the same CharacterBody ordinary movement, never teleport or invulnerability. AI disabled for deterministic geometry. Fixed engine clock is offline mechanics evidence, not real-time performance."},"\t"))

func run()->void:
	Engine.physics_ticks_per_second=60;Engine.time_scale=1
	game=load("res://main.tscn").instantiate();root.add_child(game);game.testing=true;game.fx.muted=true;game.ai_enabled=false
	game.specials.hit_requested.connect(contact)
	await frames(8)
	for mode in ["foot","mounted"]:
		for spec in ARMY:await army_case(spec,mode,"hit")
	await array_lifecycle()
	write_report(true);game._reset_hit_feedback();print("ARMY MAIN DONE ",checks.size()," checks ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
