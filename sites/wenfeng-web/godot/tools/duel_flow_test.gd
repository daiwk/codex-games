extends SceneTree

# Read-only production baseline: normal arena/controller, actual input events,
# real AI and final skeleton poses. No gameplay profiles are replaced.
var game: Node3D
var samples: Array = []
var events: Array = []
var cases: Array = []
var current: Dictionary = {}
var observing = false
var phase_label = ""
var bone_ids: Dictionary = {}
var previous: Dictionary = {}
var last_physics = -1
var request_metrics: Array = []
var capture_mode = false
var capture_count = 0
var output = "/private/tmp/wenfeng-duel-flow-latest.json"

func _initialize() -> void:
	capture_mode = "--capture" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func frames(count: int) -> void:
	for i in count: await physics_frame

func point(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func bone(rig: Skeleton3D, suffix: String) -> int:
	for i in rig.get_bone_count():
		if rig.get_bone_name(i).ends_with(suffix): return i
	return -1

func event(actor: Node, action: String) -> void:
	if observing:
		events.append({"frame":Engine.get_physics_frames(),"role":"player" if actor==game.player else "enemy",
			"event":action,"state":actor.state,"clip":actor.current_clip,"action_time":actor.action_time,
			"hp":actor.hp,"position":point(actor.position)})

func skill_event(actor: Node, id: String, stage: String) -> void:
	event(actor,id+":"+stage)

func impact(actor: Node, outcome: String, _at: Vector3) -> void:
	event(actor,"impact:"+outcome)

func actor_row(actor: Node3D, label: String) -> Dictionary:
	var row={"state":actor.state,"clip":actor.current_clip,"combo":actor.combo,"action_time":actor.action_time,
		"action_duration":actor.action_duration,"position":point(actor.position),"facing":actor.rotation.y,
		"speed":Vector2(actor.velocity.x,actor.velocity.z).length(),"input":point(actor.input_move),"hp":actor.hp,
		"contact_latched":actor.contact_latched,"contact_active":actor.contact_active,"stamina":actor.stamina,
		"tip":point(actor.blade_tip()),"palm":point(actor.palm_position(false)),"animation_time":actor.animation_player.current_animation_position}
	if not actor.mounted:
		for side in ["Left","Right"]:
			var index=int(bone_ids.get(label+side,-1))
			if index>=0: row[side+"Toe"] = point(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(index).origin))
	return row

func sample() -> void:
	if not observing or not is_instance_valid(game.player): return
	var frame=Engine.get_physics_frames()
	if frame==last_physics:return
	last_physics=frame
	var row={"frame":frame,"stage":phase_label,"phase":game.phase,"delta":game.player.get_physics_process_delta_time(),
		"gap":game.player.position.distance_to(game.enemy.position),"player":actor_row(game.player,"p"),"enemy":actor_row(game.enemy,"e"),
		"fps":Engine.get_frames_per_second(),"time_scale":Engine.time_scale,"camera_position":point(game.camera.position),"fov":game.camera.fov,
		"wall_usec":Time.get_ticks_usec()}
	samples.append(row)
	if capture_mode and capture_count<64 and samples.size()%6==0 and phase_label=="controlled":
		capture_count+=1
		call_deferred("save_capture",capture_count)

func save_capture(index: int) -> void:
	if DisplayServer.get_name()=="headless": return
	RenderingServer.force_draw()
	var img=root.get_texture().get_image()
	if img:img.save_png("/private/tmp/wenfeng-duel-flow-capture/%03d.png"%index)

func key(code: int, down: bool) -> void:
	var e=InputEventKey.new()
	e.physical_keycode=code
	e.keycode=code
	e.pressed=down
	Input.parse_input_event(e)

func tap(code: int) -> void:
	key(code,true)
	await frames(2)
	key(code,false)

func clear_input() -> void:
	for a in ["move_left","move_right","move_up","move_down","light","heavy","dodge","guard","skill_rush","skill_counter","ultimate"]:Input.action_release(a)

func prepare(role: String, mode: String, gap: float) -> void:
	observing=false
	clear_input()
	game.return_to_menu()
	game.select_combat_mode(mode)
	game.select_character(role)
	game.select_opponent("machao" if role=="zhaoyun" else "zhaoyun")
	await frames(3)
	game.start_match()
	game.phase="fight"
	game.player.enabled=true
	game.enemy.enabled=false
	game.enemy.set_physics_process(false)
	game.ai_enabled=false
	game.player.position=Vector3(0,.015,0)
	game.enemy.position=Vector3(0,.015,gap)
	game.player.rotation.y=0
	game.enemy.rotation.y=PI
	game.lock_on=true
	game.rng.seed=714
	await frames(15)
	bone_ids.clear()
	for side in ["Left","Right"]:
		bone_ids["p"+side]=bone(game.player.skeleton,side+"ToeBase")
		bone_ids["e"+side]=bone(game.enemy.skeleton,side+"ToeBase")
	game.player.skeleton.skeleton_updated.connect(sample)
	for actor in [game.player,game.enemy]:
		actor.action_started.connect(event)
		actor.skill_triggered.connect(skill_event)
		actor.impact_received.connect(impact)
	samples=[]
	events=[]
	last_physics=-1
	observing=true
	current={"role":role,"mode":mode,"gap":gap,"warmup_ms":game.player.attack_warmup_ms}

func measure_request(label: String) -> bool:
	var at=Time.get_ticks_usec()
	var accepted=game.player.request_light()
	request_metrics.append({"case":label,"accepted":accepted,"synchronous_ms":float(Time.get_ticks_usec()-at)/1000.0,
		"warmup_ms":game.player.attack_warmup_ms})
	return accepted

func finish_case(label: String) -> void:
	observing=false
	var attack_t=0.0
	var idle_attack_t=0.0
	var stationary_attack_t=0.0
	var ai_busy_t=0.0
	var ai_stationary_t=0.0
	var ai_fight_t=0.0
	var close_t=0.0
	var low_foot_distance=0.0
	var low_foot_time=0.0
	var max_gap=0.0
	var min_gap=INF
	var last_row:Dictionary={}
	for s in samples:
		var dt=float(s.delta)
		if s.phase=="fight":
			ai_fight_t+=dt
			if s.enemy.state in ["attack","hit","stagger","skill","ultimate"]:ai_busy_t+=dt
			if float(s.enemy.speed)<.1:ai_stationary_t+=dt
			if float(s.gap)<2.4:close_t+=dt
			max_gap=maxf(max_gap,s.gap);min_gap=minf(min_gap,s.gap)
		if s.player.state=="attack":
			attack_t+=dt
			if s.player.clip=="Idle":idle_attack_t+=dt
			if float(s.player.speed)<.1:stationary_attack_t+=dt
		if not last_row.is_empty() and s.player.state=="attack" and s.player.has("LeftToe"):
			for side in ["Left","Right"]:
				var a:Array=last_row.player[side+"Toe"]
				var b:Array=s.player[side+"Toe"]
				var delta=Vector3(b[0]-a[0],b[1]-a[1],b[2]-a[2])
				if float(b[1])<.18 and absf(delta.y)/maxf(dt,.001)<.18:
					low_foot_distance+=Vector2(delta.x,delta.z).length()
					low_foot_time+=dt
		last_row=s
	cases.append({"context":current.duplicate(true),"label":label,"samples":samples.duplicate(true),"events":events.duplicate(true),
		"metrics":{"attack_seconds":attack_t,"attack_uses_idle_seconds":idle_attack_t,"stationary_attack_seconds":stationary_attack_t,
			"ai_fight_seconds":ai_fight_t,"ai_busy_seconds":ai_busy_t,"ai_stationary_seconds":ai_stationary_t,"close_under_2p4_seconds":close_t,
			"min_gap":min_gap if is_finite(min_gap) else 0,"max_gap":max_gap,
			"low_foot_tangent_travel_m":low_foot_distance,"low_foot_candidate_seconds":low_foot_time}})
	print("FLOW ",label," ",JSON.stringify(cases.back().metrics))
	write_report(false)

func write_report(completed: bool) -> void:
	var file=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"completed":completed,"cases":cases,"request_cost":request_metrics,
		"scope":"Native actual arena and controller. Controlled cases disable only AI/target physics; actual attacks and hit resolver unchanged. AI cases run original AI. First-request cost is native CPU only; no Web/GPU cold-frame claim. Low-foot tangent metric is a candidate requiring visual confirmation, not an automatic sliding verdict."},"\t"))

func controlled(role: String, mode: String) -> void:
	await prepare(role,mode,2.1)
	phase_label="controlled"
	await frames(15)
	measure_request(role+mode+"first")
	await frames(20)
	await tap(KEY_J) # Existing light combo buffer through real controller.
	await frames(34)
	var before=game.player.state
	await tap(KEY_SPACE)
	events.append({"event":"probe:Space_mid_recovery","before":before,"after":game.player.state,"time":game.player.action_time})
	await frames(75)
	await tap(KEY_SPACE)
	await frames(34)
	measure_request(role+mode+"warm")
	await frames(85)
	finish_case(role+"/"+mode+"/contact-combo-dodge-repeat")

func ai_flow(role: String, mode: String) -> void:
	await prepare(role,mode,3.4 if mode=="foot" else 5.5)
	phase_label="ai"
	game.enemy.enabled=true
	game.enemy.set_physics_process(true)
	game.ai_enabled=true
	var started=Engine.get_physics_frames()
	var held=false
	for tick in 900:
		if game.phase=="fight" and game.player.hp>0:
			var toward=(game.enemy.position-game.player.position).slide(Vector3.UP)
			# Scripted player intent, delivered through normal InputMap/controller.
			if toward.length()>2.5:Input.action_press("move_up")
			else:Input.action_release("move_up")
			if tick%47==0:
				key(KEY_J,true);held=true
			if held and tick%47==2:
				key(KEY_J,false);held=false
			if tick%240==150: key(KEY_SPACE,true)
			if tick%240==152: key(KEY_SPACE,false)
		await frames(1)
	clear_input()
	finish_case(role+"/"+mode+"/15s-original-AI")

func run() -> void:
	Engine.physics_ticks_per_second=60
	Engine.time_scale=1
	if capture_mode:DirAccess.make_dir_recursive_absolute("/private/tmp/wenfeng-duel-flow-capture")
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.testing=false
	game.fx.muted=true
	await frames(10)
	for mode in ["foot","mounted"]:
		for role in ["zhaoyun","guanyu"]:await controlled(role,mode)
		await ai_flow("zhaoyun",mode)
	write_report(true)
	clear_input()
	game._reset_hit_feedback()
	print("DUEL FLOW BASELINE DONE ",cases.size())
	quit(0)
