extends "res://tools/wrist_pose_test.gd"

var anatomical_failures: Array = []
var speed_diagnostics: Array = []
var case_metrics: Array = []

func write_report(completed: bool) -> void:
	var file=FileAccess.open("/private/tmp/wenfeng-duel-wrist-focused-latest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"completed":completed,"anatomy_passed":completed and anatomical_failures.is_empty(),
		"checks":checks,"anatomical_failures":anatomical_failures,"speed_diagnostics":speed_diagnostics,
		"results":rows,"cases":case_metrics,
		"scope":"Independent final skeleton wrist swing/twist, actual skinned seam determinant, bone length and drawn handle contact. Real new DuelActor J1/J2/J3/K plus recovery blend. Both arms on five two-handed characters, active right grip on one-handed Xu; free left hand is not certified. Model-space speed retained as diagnostic; relative compensating roll is separate. Does not change RPG or production solver."},"\t"))

func hard(label: String, passed: bool, detail: Variant) -> void:
	check(label,passed,detail)
	if not passed:anatomical_failures.append(label)

func normal(role: String, mode: String, index: int) -> void:
	var gap=1.5 if role=="xuchu" else (2.1 if mode=="mounted" else 2.3)
	await setup(role,mode,gap)
	context=role+"/"+mode+"/"+(["J1","J2","J3","K"][index])
	reset_metrics();loop_observing=false;observing=true
	var accepted=game.player.request_heavy() if index==3 else game.player._begin_attack(index)
	var clip=game.player.current_clip
	var completed=false
	for frame in 260:
		await physics_frame
		if game.player.state in ["idle","move","block"] and frame>2:
			completed=true;break
	if completed:await frames(12)
	observing=false
	hard(context+" actual full playback and recovery sampled",accepted and completed and metrics.samples>=6 and metrics.finite,{"samples":metrics.samples,"clip":clip})
	for side in (["Left","Right"] if game.player.is_two_handed() else ["Right"]):
		hard(context+" "+side+" wrist swing <=40deg",float(metrics[side+"_swing"])<=deg_to_rad(40.0)+.002,rad_to_deg(float(metrics[side+"_swing"])))
		hard(context+" "+side+" residual wrist twist <=35deg",float(metrics[side+"_twist"])<=deg_to_rad(35.0)+.002,rad_to_deg(float(metrics[side+"_twist"])))
		for suffix in ["_world_forearm_rate","_world_hand_rate"]:
			if float(metrics[side+suffix])>deg_to_rad(900.0):
				speed_diagnostics.append({"case":context,"side":side,"kind":suffix,"deg_per_second":rad_to_deg(float(metrics[side+suffix])),"worst":metrics.worst.get(side+suffix,{})})
	hard(context+" actual bone length preserved",metrics.length_error<.002,metrics.length_error)
	hard(context+" actual skin wrist blend volume >=.65",metrics.skin_samples>0 and metrics.skin_volume>=.65,{"volume":metrics.skin_volume,"vertex_frames":metrics.skin_samples})
	hard(context+" drawn palms stay on handle <=3.5cm",metrics.grip_samples>0 and metrics.grip<.035,{"distance":metrics.grip,"samples":metrics.grip_samples})
	hard(context+" real contact remains damaging",game.enemy.hp<120.0,120.0-game.enemy.hp)
	case_metrics.append({"case":context,"clip":clip,"damage":120.0-game.enemy.hp,"metrics":metrics.duplicate(true)})
	print("WRISTCASE ",context," ",JSON.stringify({"swingL":rad_to_deg(metrics.Left_swing),"swingR":rad_to_deg(metrics.Right_swing),"twistL":rad_to_deg(metrics.Left_twist),"twistR":rad_to_deg(metrics.Right_twist),"skin":metrics.skin_volume,"grip":metrics.grip,"anatomy_fails":anatomical_failures.size(),"rate_diagnostics":speed_diagnostics.size()}))
	game.player.skeleton.skeleton_updated.disconnect(observe)
	write_report(false)

func run() -> void:
	Engine.physics_ticks_per_second=60
	Engine.time_scale=1.0
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.testing=true;game.fx.muted=true;game.ai_enabled=false
	await frames(5)
	for mode in ["foot","mounted"]:
		for role in ["zhaoyun","machao","guanyu","zhangfei","lubu","xuchu"]:
			for index in 4:await normal(role,mode,index)
	write_report(true)
	game._reset_hit_feedback()
	print("DUEL WRIST FOCUSED DONE ",case_metrics.size()," cases ",anatomical_failures.size()," anatomical failures ",speed_diagnostics.size()," speed diagnostics")
	quit(0 if anatomical_failures.is_empty() else 1)
