extends SceneTree

const SKILLS = [
	["zhaoyun","ultimate","flying_blades",6.0,9],
	["machao","ultimate","cavalry",6.0,6],
	["guanyu","rush","shockwave",6.0,1],
	["zhangfei","counter","roar",3.0,1],
	["lubu","ultimate","air_slam",2.6,1],
	["xuchu","rush","returning_blade",6.0,1],
]
var requested_weapon = ""
var report_path = "/private/tmp/wenfeng-duel-integrated-specials-latest.json"
var game: Node3D
var checks: Array = []
var failures: Array = []
var cases: Array = []
var contacts: Array = []
var observing = false
var initial_hp = 120.0
var last_hp = 120.0
var peak_y = 0.0
var peak_entities = 0
var weapon_hidden = false
var landed_frames: Array = []
var camera_outside: Array = []
var current: Dictionary = {}
var last_sample_frame = -1

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	call_deferred("run")

func frames(count: int) -> void:
	for i in count:await physics_frame

func verify(label: String, value: bool, detail: Variant = null) -> void:
	var row={"label":label,"passed":value,"detail":detail}
	checks.append(row)
	print("PASS " if value else "FAIL ",label," ",JSON.stringify(detail))
	if not value:failures.append(label)
	write_report(false)

func point(v: Vector3) -> Array:return [v.x,v.y,v.z]

func contact(attacker: Node, defender: Node, data: Dictionary, at: Vector3) -> void:
	if not observing or attacker != game.player:return
	contacts.append({"type":data.get("special",""),"volley":data.get("volley_id",-1),"index":data.get("projectile_index",-1),
		"damage":last_hp-defender.hp,"hp":defender.hp,"point":point(at),"frame":Engine.get_physics_frames(),
		"player_y":attacker.position.y,"target_position":point(defender.position)})
	last_hp=defender.hp

func landed(_at: Vector3) -> void:
	if observing:landed_frames.append(Engine.get_physics_frames())

func sample() -> void:
	if not observing:return
	var frame=Engine.get_physics_frames()
	if frame==last_sample_frame:return
	last_sample_frame=frame
	peak_y=maxf(peak_y,game.player.position.y)
	peak_entities=maxi(peak_entities,game.specials.entity_count())
	weapon_hidden=weapon_hidden or not game.player.weapon_mesh.visible
	if game.lock_active() and camera_outside.size()<8:
		for actor in [game.player,game.enemy]:
			for h in [0.0,3.1 if actor.mounted else 1.8]:
				var p=actor.position+Vector3.UP*h
				var screen=game.camera.unproject_position(p)
				var size=game.get_viewport().get_visible_rect().size
				if game.camera.is_position_behind(p) or screen.x<0.0 or screen.x>size.x or screen.y<0.0 or screen.y>size.y:
					camera_outside.append({"frame":frame,"actor":"player" if actor==game.player else "enemy","height":h,"screen":[screen.x,screen.y],"world":point(p)})

func setup(role: String, mode: String, gap: float) -> void:
	observing=false
	game.return_to_menu()
	game.select_combat_mode(mode)
	game.select_character(role)
	if requested_weapon != "":game.select_weapon(requested_weapon)
	game.select_opponent("machao" if role=="zhaoyun" else "zhaoyun")
	await frames(3)
	game.start_match()
	game.testing=true
	game.phase="fight"
	game.ai_enabled=false
	game.player.enabled=true
	game.enemy.enabled=true
	game.player.position=Vector3(0,.015,-gap*.5)
	game.enemy.position=Vector3(0,.015,gap*.5)
	game.player.rotation.y=0.0
	game.enemy.rotation.y=PI
	game.enemy.input_move=Vector3.ZERO
	game.enemy.wants_block=false
	game.rng.seed=714
	await frames(15)
	game._update_camera(1.0,true)
	contacts=[]
	initial_hp=game.enemy.hp
	last_hp=initial_hp
	peak_y=game.player.position.y
	peak_entities=0
	weapon_hidden=false
	landed_frames=[]
	camera_outside=[]
	last_sample_frame=-1
	game.player.skeleton.skeleton_updated.connect(sample)
	game.player.duel_landed.connect(landed)
	observing=true

func start_skill(id: String) -> bool:
	if id=="ultimate":
		game.player.energy=100.0 # Explicit native gate fixture, never a browser write.
		return game.player.request_ultimate()
	return game.player.request_skill(id)

func spawn_wait(limit=230) -> bool:
	for i in limit:
		if not game.specials.groups.is_empty():return true
		await frames(1)
	return false

func complete_wait(limit=340) -> void:
	for i in limit:
		await frames(1)
		if game.specials.groups.is_empty() and game.player.state in ["idle","move","block"]:return

func make_wall() -> StaticBody3D:
	var body=StaticBody3D.new()
	var shape=CollisionShape3D.new()
	var box=BoxShape3D.new()
	box.size=Vector3(12,8,.35)
	shape.shape=box
	body.position=Vector3(0,4,0)
	body.add_child(shape)
	game.add_child(body)
	return body

func exercise(spec: Array, mode: String, scenario: String) -> void:
	var role:String=spec[0];var skill:String=spec[1];var type:String=spec[2]
	await setup(role,mode,float(spec[3]))
	current={"role":role,"mode":mode,"skill":skill,"type":type,"scenario":scenario}
	var label=role+"/"+mode+"/"+scenario
	var origin=game.enemy.position
	var wall:StaticBody3D=null
	if scenario=="wall":
		wall=make_wall()
		await frames(2)
	verify(label+" default target lock",game.lock_active())
	verify(label+" actual skill accepted",start_skill(skill))
	var spawned=await spawn_wait()
	verify(label+" full release or landing creates real group",spawned,{"specials":game.specials.debug_state(),"state":game.player.state,"stage":game.player.skill_stage,"y":game.player.position.y})
	if scenario=="miss" and spawned:
		# Controlled geometric miss: move the same target outside the released
		# lane/front. Entity trajectories and homing limits stay unmodified.
		game.enemy.position.x=5.7
		game.enemy.velocity=Vector3.ZERO
	await complete_wait()
	await frames(18)
	observing=false
	var damage=initial_hp-game.enemy.hp
	var displacement=(game.enemy.position-origin).slide(Vector3.UP).length()
	var row={"context":current.duplicate(true),"damage":damage,"contacts":contacts.duplicate(true),"peak_entities":peak_entities,"peak_actor_y":peak_y,
		"landings":landed_frames.duplicate(),"weapon_hidden":weapon_hidden,"weapon_visible_final":game.player.weapon_mesh.visible,
		"airborne_final":game.player.duel_is_airborne(),"player_position_final":point(game.player.position),"target_position_final":point(game.enemy.position),
		"target_displacement":displacement,"specials_final":game.specials.debug_state(),"camera_outside":camera_outside.duplicate()}
	cases.append(row)
	verify(label+" clears all transient groups",game.specials.groups.is_empty())
	verify(label+" returns weapon and lands",game.player.weapon_mesh.visible and not game.player.duel_is_airborne() and game.player.is_on_floor())
	if scenario=="hit":
		verify(label+" actual HP decreases",damage>0.0,{"damage":damage,"contacts":contacts.size(),"displacement":displacement})
		var unique:Dictionary={}
		var tracked=0.0
		for hit in contacts:
			unique[str(hit.volley)+":"+str(hit.index)]=true
			tracked+=float(hit.damage)
		verify(label+" no untracked or duplicate contact damage",is_equal_approx(tracked,damage) and unique.size()==contacts.size(),{"tracked":tracked,"damage":damage,"contacts":contacts.size(),"unique":unique.size()})
		verify(label+" bounded individual hit count",contacts.size()<=int(spec[4]),{"actual":contacts.size(),"max":spec[4]})
		verify(label+" real target displacement",displacement>0.015,{"metres":displacement})
		verify(label+" normal camera retains whole bodies",camera_outside.is_empty(),camera_outside)
		if role=="zhaoyun" or role=="machao":verify(label+" actual formation entity count",peak_entities==int(spec[4]),peak_entities)
		if role=="lubu" and mode=="foot":
			verify(label+" actual airborne arc and single landing",peak_y>2.0 and landed_frames.size()==1,{"peak_y":peak_y,"landings":landed_frames})
			verify(label+" only landing creates damage",not contacts.is_empty() and int(contacts[0].frame)>=int(landed_frames[0]),{"contacts":contacts,"landed":landed_frames})
		if role=="xuchu":verify(label+" actual held weapon disappears then returns",weapon_hidden and game.player.weapon_mesh.visible)
	else:
		verify(label+" no HP loss without route contact",is_zero_approx(damage) and contacts.is_empty(),{"damage":damage,"contacts":contacts})
	if wall!=null:wall.queue_free();await frames(2)
	write_report(false)

func lifecycle() -> void:
	await setup("xuchu","foot",6.0)
	start_skill("rush")
	verify("returning blade exists before lifecycle",await spawn_wait())
	await frames(2)
	var ages:Dictionary={}
	for id in game.specials.groups:ages[id]=game.specials.groups[id].age
	var hp=game.enemy.hp
	game.toggle_pause()
	await frames(15)
	var same=true
	for id in ages:same=same and game.specials.groups.has(id) and is_equal_approx(ages[id],game.specials.groups[id].age)
	verify("pause freezes actual blade route and HP",same and is_equal_approx(game.enemy.hp,hp),{"ages":ages,"hp":game.enemy.hp})
	game.toggle_pause()
	game.player._idle() # Real shared cancellation path invokes owner cancellation callbacks.
	await frames(3)
	verify("cancel removes owner effects and returns held weapon",game.specials.groups.is_empty() and game.player.weapon_mesh.visible)
	await setup("xuchu","foot",6.0)
	start_skill("rush");await spawn_wait()
	game.player.hp=1.0 # Explicit initial lethal-test condition.
	game.player.receive_strike(game.enemy,game.enemy._heavy_attack_profile())
	await frames(3)
	verify("real lethal strike clears blade and returns weapon",game.player.hp<=0.0 and game.specials.groups.is_empty() and game.player.weapon_mesh.visible)
	await setup("lubu","foot",2.6)
	start_skill("ultimate")
	for i in 90:
		await frames(1)
		if game.player.duel_is_airborne():break
	verify("real ultimate launches before round reset",game.player.duel_is_airborne())
	game._new_round()
	await frames(3)
	verify("round reset clears airborne state weapon and entities",not game.player.duel_is_airborne() and game.player.weapon_mesh.visible and game.specials.groups.is_empty() and is_equal_approx(game.player.floor_snap_length,.2))
	await setup("zhaoyun","foot",2.1)
	game.testing=false
	game.player.state="hit";game.player.action_duration=.6;game.player.action_time=.48
	var e=InputEventKey.new();e.physical_keycode=KEY_J;e.keycode=KEY_J;e.pressed=true;Input.parse_input_event(e)
	await frames(2)
	e=e.duplicate();e.pressed=false;Input.parse_input_event(e)
	await frames(15)
	verify("260ms real input survives short hit recovery",game.player.state=="attack",{"state":game.player.state,"pending":game.pending_input})
	game.testing=true

func write_report(completed: bool) -> void:
	var f=FileAccess.open(report_path,FileAccess.WRITE)
	f.store_string(JSON.stringify({"completed":completed,"passed":completed and failures.is_empty(),"checks":checks.size(),"failures":failures,"results":checks,"cases":cases,
		"scope":"Actual Main scene and full real skill release/landing callbacks; original collision and receiver. AI disabled except separate flow fixture; explicit native energy100/HP1 conditions only. Execution source SHA separately saved. Target relocation in miss cases is a labelled geometric fixture, not a player dodge claim."},"\t"))

func run() -> void:
	Engine.physics_ticks_per_second=60
	Engine.time_scale=1.0
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.testing=true;game.fx.muted=true;game.ai_enabled=false
	game.specials.hit_requested.connect(contact)
	await frames(8)
	for spec in SKILLS:await exercise(spec,"foot","hit")
	for spec in SKILLS:await exercise(spec,"foot","miss")
	for spec in SKILLS:await exercise(spec,"foot","wall")
	for spec in SKILLS:await exercise(spec,"mounted","hit")
	await lifecycle()
	write_report(true)
	game._reset_hit_feedback()
	print("INTEGRATED SPECIALS DONE ",checks.size()," checks ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
