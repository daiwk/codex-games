extends SceneTree
var checks=[]
var summary={"mode":"HEADLESS ENGINE MIXER PROBE ONLY, NOT VISUAL ACCEPTANCE","max_helper_roll_after_blend":0.0,"max_legacy_position_error_rig":0.0,"unfixed_reference":{},"cases":[]}
func _initialize(): call_deferred("run")
func find_type(n:Node,type:String):
	if n.is_class(type):return n
	for c in n.get_children():
		var r=find_type(c,type)
		if r!=null:return r
	return null
func bone(rig:Skeleton3D,suffix:String):
	for i in rig.get_bone_count():
		if rig.get_bone_name(i).ends_with(suffix):return i
	return -1
func key(ap:AnimationPlayer,alias:String):
	for k in ap.get_animation_list():
		if k.get_slice("/",k.get_slice_count("/")-1)==alias:return k
	return ""
func helper_roll(rig:Skeleton3D):
	var angle=0.0
	for k in [1,2,3]:
		var q=rig.get_bone_pose_rotation(bone(rig,"RightForeArmTwist"+str(k))).normalized()
		angle=maxf(angle,2*atan2(Vector3(q.x,q.y,q.z).length(),absf(q.w)))
	return angle
func reset(ap:AnimationPlayer,rig:Skeleton3D):
	ap.stop()
	for i in rig.get_bone_count():rig.reset_bone_pose(i)
func setup(path:String):
	var model=load(path).instantiate()
	root.add_child(model)
	var ap:AnimationPlayer=find_type(model,"AnimationPlayer")
	ap.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return {"model":model,"ap":ap,"rig":find_type(model,"Skeleton3D")}
func run():
	var candidate=setup("res://compatible.glb")
	var original=setup("res://original.glb")
	var unfixed=setup("res://unfixed.glb")
	await process_frame
	var ap:AnimationPlayer=candidate.ap
	var rig:Skeleton3D=candidate.rig
	var oa:AnimationPlayer=original.ap
	var orig:Skeleton3D=original.rig
	# Negative-control reference: determine actual engine behavior without identity tracks.
	var ua:AnimationPlayer=unfixed.ap
	var ur:Skeleton3D=unfixed.rig
	ua.play(key(ua,"XuUAL2RegularTwistRig"),0)
	ua.seek(.2,true)
	ua.advance(0)
	var before=helper_roll(ur)
	ua.play(key(ua,"Idle"),.12)
	for step in 31:ua.advance(1.0/60)
	summary.unfixed_reference={"before_roll_deg":rad_to_deg(before),"after_Idle_0_516s_roll_deg":rad_to_deg(helper_roll(ur))}
	for target in ["Idle","Hit","Dodge","Block"]:
		for lead in [.2,.7666666667,1.5]:
			for blend in [0.0,.12,.25]:
				reset(ap,rig)
				ap.play(key(ap,"XuUAL2RegularTwistRig"),0)
				ap.seek(lead,true)
				ap.advance(0)
				var initial=helper_roll(rig)
				ap.play(key(ap,target),blend)
				ap.advance(0)
				var max_after=0.0
				var max_pos=0.0
				for frame in 46:
					if frame>0:ap.advance(1.0/60)
					if frame/60.0+1e-8>=blend:
						max_after=maxf(max_after,helper_roll(rig))
						oa.play(key(oa,target),0)
						oa.seek(ap.current_animation_position,true)
						oa.advance(0)
						rig.force_update_all_bone_transforms()
						orig.force_update_all_bone_transforms()
						for i in orig.get_bone_count():
							var j=rig.find_bone(orig.get_bone_name(i))
							max_pos=maxf(max_pos,orig.get_bone_global_pose(i).origin.distance_to(rig.get_bone_global_pose(j).origin))
				var ok=max_after<0.00002 and max_pos<0.00002
				checks.append(ok)
				summary.max_helper_roll_after_blend=maxf(summary.max_helper_roll_after_blend,max_after)
				summary.max_legacy_position_error_rig=maxf(summary.max_legacy_position_error_rig,max_pos)
				summary.cases.append({"target":target,"source_time":lead,"blend":blend,"initial_roll_deg":rad_to_deg(initial),"after_blend_max_roll_deg":rad_to_deg(max_after),"legacy_original_bone_position_error_rig":max_pos,"pass":ok})
	summary.completed_cases=checks.size()
	summary.all_pass=not checks.has(false)
	summary.sha256=FileAccess.get_sha256("res://compatible.glb")
	FileAccess.open("res://switch-results.json",FileAccess.WRITE).store_string(JSON.stringify(summary,"  "))
	print("SWITCH_PROBE ",JSON.stringify(summary))
	quit(0 if summary.all_pass else 1)
