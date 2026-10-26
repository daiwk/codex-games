extends SceneTree
const NativeBridge=preload("res://tools/duel_native_web_bridge_test.gd")
var game:Node3D
var bridge:Node
var cases:Array=[]
var checks:Array=[]
var failures:Array=[]
var report_path="/private/tmp/wenfeng-steering-sign-latest.json"
var baseline=false
func _initialize()->void:
	baseline="--baseline" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):report_path=arg.trim_prefix("--report=")
	call_deferred("run")
func frames(n:int)->void:
	for i in n:await physics_frame
func v(p:Vector3)->Array:return [p.x,p.y,p.z]
func key(code:int,down:bool)->void:
	var e=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=down;Input.parse_input_event(e)
func release_inputs()->void:
	for code in [KEY_W,KEY_S,KEY_A,KEY_D,KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN]:key(code,false)
	for action in ["move_up","move_down","move_left","move_right","cavalry_brake"]:Input.action_release(action)
func bone(rig:Skeleton3D,suffix:String)->int:
	for i in rig.get_bone_count():
		if rig.get_bone_name(i).ends_with(suffix):return i
	return -1
func check(label:String,passed:bool,detail:Variant)->void:
	checks.append({"label":label,"passed":passed,"detail":detail})
	if not passed:failures.append(label)
	print("PASS " if passed else "FAIL ",label," ",JSON.stringify(detail))
func prepare(yaw:float,locked:bool,gait:String)->void:
	release_inputs();game.return_to_menu();game.select_combat_mode("mounted");game.select_character("zhaoyun");game.select_opponent("machao")
	await frames(2);game.start_match();game.phase="fight";game.testing=false;game.ai_enabled=false;game.player.enabled=true;game.enemy.enabled=false;game.enemy.set_physics_process(false)
	game.player.position=Vector3(0,.015,-8);game.enemy.position=Vector3(14,.015,14);game.player.rotation.y=yaw
	game.lock_on=locked;game._sync_lock();await frames(6)
	if gait!="stationary":
		var code=KEY_W if gait=="forward" else KEY_S
		key(code,true);await frames(100);key(code,false);await frames(3)
	game._update_camera(1,true);game.camera.force_update_transform();await frames(2)
func case_run(yaw:float,locked:bool,gait:String,channel:String,direction:int,arrow=false)->void:
	await prepare(yaw,locked,gait)
	var actor=game.player
	var start_forward=actor.forward().normalized()
	# Model uses +Z facing. Anatomical right and the actual rear-view camera
	# right are -basis.x; do not reuse that same mistaken assumption as oracle.
	var rider_right=start_forward.cross(Vector3.UP).normalized()
	var right_arm=bone(actor.skeleton,"RightArm");var left_arm=bone(actor.skeleton,"LeftArm")
	var anatomical=(actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(right_arm).origin)-actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(left_arm).origin)).slide(Vector3.UP).normalized()
	var start_position=actor.position;var start_yaw=actor.rotation.y
	var starting_status=actor.cavalry_status().duplicate(true)
	var action="move_left" if direction<0 else "move_right"
	var code=(KEY_LEFT if direction<0 else KEY_RIGHT) if arrow else (KEY_A if direction<0 else KEY_D)
	if channel=="bridge":bridge._command(["input",action,true])
	else:key(code,true)
	await frames(24)
	var end_forward=actor.forward().normalized()
	var displacement=(actor.position-start_position).slide(Vector3.UP)
	var right_component=(end_forward-start_forward).dot(rider_right)
	var screen_anchor=actor.position+Vector3.UP*1.9
	# Both points use the very same actual live camera transform and same
	# current anchor. Camera-follow translation/yaw cannot fake the sign.
	game.camera.force_update_transform()
	var before_screen=game.camera.unproject_position(screen_anchor+start_forward*2)
	var after_screen=game.camera.unproject_position(screen_anchor+end_forward*2)
	var screen_x=after_screen.x-before_screen.x
	var camera_right_projection=(end_forward-start_forward).dot(game.camera.global_basis.x.normalized())
	var row={"yaw_degrees":rad_to_deg(yaw),"locked":locked,"gait":gait,"channel":channel,"key":("Left" if direction<0 else "Right") if arrow else ("A" if direction<0 else "D"),"expected_side":direction,"action":action,
		"start_yaw":start_yaw,"end_yaw":actor.rotation.y,"yaw_delta_degrees":rad_to_deg(angle_difference(start_yaw,actor.rotation.y)),"start_forward":v(start_forward),"end_forward":v(end_forward),"rider_right":v(rider_right),"anatomical_right":v(anatomical),"anatomical_agreement":anatomical.dot(rider_right),
		"rightward_heading_change":right_component,"live_camera_screen_dx":screen_x,"live_camera_right_projection":camera_right_projection,"displacement":v(displacement),"rightward_displacement":displacement.dot(rider_right),"status_before":starting_status,"status_during":actor.cavalry_status().duplicate(true),"input_axis":v(Vector3(Input.get_vector("move_left","move_right","move_up","move_down").x,0,0))}
	cases.append(row)
	var label=str(cases.size())+"/"+str(int(rad_to_deg(yaw)))+"/"+str(locked)+"/"+gait+"/"+channel+"/"+row.key
	check(label+" rider right agrees with actual shoulder anatomy",anatomical.dot(rider_right)>.65,row.anatomical_agreement)
	check(label+" horse head turns toward intended rider side",right_component*float(direction)>.01,{"right_component":right_component,"yaw_delta":row.yaw_delta_degrees})
	check(label+" actual live camera projects intended screen side",screen_x*float(direction)>.25 and camera_right_projection*float(direction)>.005,{"screen_dx":screen_x,"camera_right_dot":camera_right_projection})
	if gait!="stationary":
		var expected_motion=direction*(1 if gait=="forward" else -1)
		check(label+" physical curved path sign matches signed travel",displacement.dot(rider_right)*float(expected_motion)>.005,{"right_displacement":row.rightward_displacement,"expected":expected_motion})
	if channel=="bridge":bridge._command(["input",action,false])
	else:key(code,false)
	await frames(2)
	check(label+" releasing source clears directional action",not Input.is_action_pressed(action),Input.is_action_pressed(action))
	write(false)
func write(done:bool)->void:
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify({"completed":done,"passed":done and failures.is_empty(),"baseline":baseline,"checks":checks,"failures":failures,"cases":cases,
		"scope":"Real mounted Main and physical Input.parse_input_event keyboard mapping; native subclass calls unchanged WebBridge._command input code while disabling only browser JS publication. Four horse headings, lock both states, stationary/forward/reverse. Anatomical RightArm-LeftArm cross-check; actual live Camera projection of same-anchor new/old heading vectors, not merely abs(yaw). Reverse keeps A/D head direction but curved travel lateral sign reverses. No AI, actor rotation/velocity injection during steering, production edits, Git or RPG operations. Native bridge call does not certify an actual browser pointer click."},"\t"))
func run()->void:
	Engine.physics_ticks_per_second=60;Engine.time_scale=1
	game=load("res://main.tscn").instantiate();root.add_child(game);game.fx.muted=true;game.ai_enabled=false
	bridge=NativeBridge.new();bridge.game=game;root.add_child(bridge)
	await frames(6)
	if baseline:
		for channel in ["keyboard","bridge"]:
			for direction in [-1,1]:await case_run(0,false,"stationary",channel,direction)
	else:
		for yaw in [0.0,PI*.5,PI,-PI*.5]:
			for locked in [false,true]:
				for gait in ["stationary","forward","reverse"]:
					for direction in [-1,1]:await case_run(yaw,locked,gait,"keyboard",direction)
		for yaw in [0.0,PI*.5]:
			for locked in [false,true]:
				for direction in [-1,1]:await case_run(yaw,locked,"stationary","keyboard",direction,true)
		for locked in [false,true]:
			for gait in ["stationary","forward","reverse"]:
				for direction in [-1,1]:await case_run(0,locked,gait,"bridge",direction)
	release_inputs();game._reset_hit_feedback();write(true)
	print("STEERING SIGN DONE ",cases.size()," cases ",checks.size()," checks ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
