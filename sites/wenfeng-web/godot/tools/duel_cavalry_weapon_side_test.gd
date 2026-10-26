extends "res://tools/duel_cavalry_direction_test.gd"
func _initialize()->void:
	report_path="/private/tmp/wenfeng-weapon-side-latest.json"
	super._initialize()
func side_case(channel:String,direction:int)->void:
	await prepare(0,true,"stationary")
	var actor=game.player
	var forward=actor.forward().normalized();var rider_right=forward.cross(Vector3.UP).normalized()
	var action="cavalry_left" if direction<0 else "cavalry_right"
	var code=KEY_Z if direction<0 else KEY_C
	if channel=="bridge":bridge._command(["input",action,true])
	else:key(code,true)
	await frames(2)
	if channel=="bridge":bridge._command(["input",action,false])
	else:key(code,false)
	await frames(12)
	var aim=actor.duel_strike_forward().normalized()
	var physical=(actor.blade_tip()-actor.blade_base()).normalized()
	var anchor=actor.position+Vector3.UP*2
	game.camera.force_update_transform()
	var aim_dx=game.camera.unproject_position(anchor+aim*2).x-game.camera.unproject_position(anchor+forward*2).x
	var physical_dx=game.camera.unproject_position(anchor+physical*2).x-game.camera.unproject_position(anchor+forward*2).x
	var row={"channel":channel,"action":action,"key":"Z" if direction<0 else "C","expected_rider_side":direction,"accepted":actor.state=="attack","clip":actor.current_clip,"time":actor.action_time,
		"cavalry":actor.cavalry_status().duplicate(true),"rider_right":v(rider_right),"aim":v(aim),"physical_blade_direction":v(physical),
		"aim_right_component":aim.dot(rider_right),"physical_blade_right_component":physical.dot(rider_right),"actual_camera_aim_dx":aim_dx,"actual_camera_blade_dx":physical_dx}
	cases.append(row)
	var label=channel+"/"+row.key
	check(label+" actual controller accepts normal attack",actor.state=="attack",row)
	check(label+" rider upper aim points to label side",aim.dot(rider_right)*direction>.3,row.aim_right_component)
	check(label+" actual weapon points to label side",physical.dot(rider_right)*direction>.1,row.physical_blade_right_component)
	check(label+" live camera projects aim and weapon on label side",aim_dx*direction>1 and physical_dx*direction>1,{"aim":aim_dx,"weapon":physical_dx})
	check(label+" release clears source action",not Input.is_action_pressed(action),Input.is_action_pressed(action))
	write(false)
func write(done:bool)->void:
	FileAccess.open(report_path,FileAccess.WRITE).store_string(JSON.stringify({"completed":done,"passed":done and failures.is_empty(),"checks":checks,"failures":failures,"cases":cases,
		"scope":"Four actual Main normal attacks from real Z/C key events and unchanged native WebBridge._command path (browser publication disabled only). Anatomical rider right is forward cross UP, independent actual drawn blade segment and real Camera screen projections. No AI/contact target interference or production modifications. Does not certify browser pointer clicks or all animation anatomy."},"\t"))
func run()->void:
	Engine.physics_ticks_per_second=60;Engine.time_scale=1
	game=load("res://main.tscn").instantiate();root.add_child(game);game.fx.muted=true;game.ai_enabled=false
	bridge=NativeBridge.new();bridge.game=game;root.add_child(bridge);await frames(6)
	for channel in ["keyboard","bridge"]:
		for direction in [-1,1]:await side_case(channel,direction)
	release_inputs();game._reset_hit_feedback();write(true);print("WEAPON SIDE SIGN DONE ",cases.size()," cases ",checks.size()," checks ",failures.size()," failures");quit(0 if failures.is_empty() else 1)
