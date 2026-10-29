extends RefCounted

# A contact-aware stop/gather step into the source preparation. Foot contacts
# are world-space constraints; locomotion is not held as a frozen local pose.
const SOURCE_START = 0.25
const SAMPLE_HZ = 120.0
var fighter
var prepared = false
var active = false
var duration = 0.0
var _source_pose: Array = []
var _prep_rows: Array = []
var _chest_id = -1
var _upper_ids: Array = []
var _run_rows: Array = []
var _run_length = 0.0
var _foot_vertices: Array = [[], []]
var _foot_ids: Array = []
var _leg_ids: Array = []
var _source_feet: Array = []
var _source_cloud: Array = []
var _run_min: Array = [INF, INF]
var _start = Vector3.ZERO
var _goal = Vector3.ZERO
var _start_velocity = Vector3.ZERO
var _stop_time = 0.0
var _brake_start = 0.0
var _plans: Array = []
var _entry_animation: Animation
var _library: AnimationLibrary
var _elapsed = 0.0
var _last_elapsed = 0.0
var _diagnostics: Dictionary = {}
var _root_clip = false
var _enabled = false
var _air_released = false
var _late_stop = false
var _first_side = 0
var _swing_speeds: Array = []

func _pose(rig: Skeleton3D) -> Array:
	var result: Array = []
	for i in rig.get_bone_count(): result.append({"p":rig.get_bone_pose_position(i),"q":rig.get_bone_pose_rotation(i),"s":rig.get_bone_pose_scale(i)})
	return result

func _put(rig: Skeleton3D, pose: Array) -> void:
	for i in pose.size():
		rig.set_bone_pose_position(i,pose[i].p)
		rig.set_bone_pose_rotation(i,pose[i].q)
		rig.set_bone_pose_scale(i,pose[i].s)
	rig.force_update_all_bone_transforms()

func _key(ap: AnimationPlayer, alias: String) -> String:
	for k in ap.get_animation_list():
		if String(k).get_slice("/",String(k).get_slice_count("/")-1)==alias:return k
	return ""

func _meshes(node: Node, found: Array) -> void:
	if node is MeshInstance3D and node.skin != null:found.append(node)
	for child in node.get_children():_meshes(child,found)

func _cache_foot_geometry(source: Node, rig: Skeleton3D) -> void:
	var meshes: Array=[]
	_meshes(source,meshes)
	for mesh in meshes:
		var skin: Skin=mesh.skin
		var binds: Array=[]
		for slot in skin.get_bind_count():
			var bone=skin.get_bind_bone(slot)
			if bone<0:bone=rig.find_bone(String(skin.get_bind_name(slot)))
			binds.append({"bone":bone,"pose":skin.get_bind_pose(slot)})
		for surface in mesh.mesh.get_surface_count():
			var arrays=mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
			var count=bones.size()/vertices.size()
			for vi in vertices.size():
				for side in 2:
					var prefix="mixamorig_Left" if side==0 else "mixamorig_Right"
					var foot_weight=0.0
					var parts: Array=[]
					for j in count:
						var weight=weights[vi*count+j]
						if weight<0.000001:continue
						var binding: Dictionary=binds[bones[vi*count+j]]
						var name=rig.get_bone_name(binding.bone)
						if name.begins_with(prefix+"Foot") or name.begins_with(prefix+"Toe"):
							foot_weight+=weight
						parts.append({"bone":binding.bone,"point":binding.pose*vertices[vi],"weight":weight})
					if foot_weight>0.5:_foot_vertices[side].append(parts)
	assert(_foot_vertices[0].size()>10 and _foot_vertices[1].size()>10,"Foot contacts need real shoe skin vertices")

func _cloud(rig: Skeleton3D, side: int) -> Array:
	var transforms: Dictionary={}
	var result: Array=[]
	for vertex in _foot_vertices[side]:
		var p=Vector3.ZERO
		for part in vertex:
			if not transforms.has(part.bone):transforms[part.bone]=rig.get_bone_global_pose(part.bone)
			p+=Transform3D(transforms[part.bone])*Vector3(part.point)*float(part.weight)
		result.append(p)
	return result

func _min_y(cloud: Array) -> float:
	var value=INF
	for p in cloud:value=minf(value,Vector3(p).y)
	return value

func setup(owner_fighter, source_clip: String) -> void:
	fighter=owner_fighter
	for side in ["Left","Right"]:
		_foot_ids.append(fighter.skeleton.find_bone("mixamorig_"+side+"Foot"))
		_leg_ids.append([fighter.skeleton.find_bone("mixamorig_"+side+"UpLeg"),fighter.skeleton.find_bone("mixamorig_"+side+"Leg"),fighter.skeleton.find_bone("mixamorig_"+side+"Foot")])
	var source=(load("res://assets/motion/xuchu_ual1_k.glb") as PackedScene).instantiate()
	source.visible=false
	fighter.add_child(source)
	var rig: Skeleton3D=fighter._find_node(source,"Skeleton3D")
	var ap: AnimationPlayer=fighter._find_node(source,"AnimationPlayer")
	assert(rig.get_bone_count()==fighter.skeleton.get_bone_count())
	ap.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_cache_foot_geometry(source,rig)
	var run_key=_key(ap,"Run")
	assert(not run_key.is_empty())
	_run_length=ap.get_animation(run_key).length
	ap.get_animation(run_key).loop_mode=Animation.LOOP_LINEAR
	ap.play(run_key,0,1)
	for i in int(ceil(_run_length*SAMPLE_HZ)):
		ap.seek(i/SAMPLE_HZ,true);ap.advance(0);rig.force_update_all_bone_transforms()
		var clouds=[_cloud(rig,0),_cloud(rig,1)]
		_run_rows.append({"clouds":clouds,"min":[_min_y(clouds[0]),_min_y(clouds[1])]})
		for side in 2:_run_min[side]=minf(_run_min[side],_run_rows[-1].min[side])
	ap.stop();rig.reset_bone_poses()
	var key=_key(ap,source_clip)
	assert(not key.is_empty())
	ap.get_animation(key).loop_mode=Animation.LOOP_NONE
	_chest_id=rig.find_bone("mixamorig_Spine2")
	for bone in rig.get_bone_count():
		var ancestor=bone
		while ancestor>=0:
			if ancestor==_chest_id:_upper_ids.append(bone);break
			ancestor=rig.get_bone_parent(ancestor)
	ap.play(key,0,1)
	for sample in int(ceil(SOURCE_START*SAMPLE_HZ))+1:
		ap.seek(minf(sample/SAMPLE_HZ,SOURCE_START),true);ap.advance(0);rig.force_update_all_bone_transforms()
		_prep_rows.append({"pose":_pose(rig),"chest":rig.get_bone_global_pose(_chest_id).basis.orthonormalized().get_rotation_quaternion()})
	ap.seek(SOURCE_START,true);ap.advance(0);rig.force_update_all_bone_transforms()
	_source_pose=_pose(rig)
	for side in 2:
		_source_feet.append(rig.get_bone_global_pose(_foot_ids[side]))
		_source_cloud.append(_cloud(rig,side))
	source.free()
	_library=AnimationLibrary.new()
	fighter.animation_player.add_animation_library("XuRunEntry",_library)
	_enabled=true

func reset() -> void:
	prepared=false
	active=false
	duration=0.0
	_elapsed=0.0
	_last_elapsed=0.0
	_plans.clear()
	_air_released=false
	_late_stop=false
	_swing_speeds.clear()
	_diagnostics.clear()

func _run_cloud(time: float, side: int, vertex: int) -> Vector3:
	var f=fposmod(time,_run_length)*SAMPLE_HZ
	var i=int(f)%_run_rows.size()
	var j=(i+1)%_run_rows.size()
	return Vector3(_run_rows[i].clouds[side][vertex]).lerp(_run_rows[j].clouds[side][vertex],f-i)

func _run_swing_speed(side: int, vertex: int, rate: float, root_velocity: Vector3) -> float:
	var maximum=1.0
	for row in _run_rows.size():
		var time=float(row)/SAMPLE_HZ
		var v=(_run_cloud(time+1.0/SAMPLE_HZ,side,vertex)-_run_cloud(time-1.0/SAMPLE_HZ,side,vertex))*(SAMPLE_HZ*0.5*rate)
		var world=root_velocity+fighter.skeleton.global_basis*v
		maximum=maxf(maximum,Vector2(world.x,world.z).length())
	return maximum

func _prep(time: float) -> Dictionary:
	var f=clampf(time,0,SOURCE_START)*SAMPLE_HZ
	var i=mini(int(f),_prep_rows.size()-1)
	var j=mini(i+1,_prep_rows.size()-1)
	var pose: Array=[]
	for bone in _source_pose.size():
		var a: Dictionary=_prep_rows[i].pose[bone]
		var b: Dictionary=_prep_rows[j].pose[bone]
		pose.append({"p":Vector3(a.p).lerp(b.p,f-i),"q":Quaternion(a.q).slerp(b.q,f-i),"s":Vector3(a.s).lerp(b.s,f-i)})
	return {"pose":pose,"chest":Quaternion(_prep_rows[i].chest).slerp(_prep_rows[j].chest,f-i)}

func _next_contact(phase: float, side: int, rate: float) -> float:
	var threshold=_min_y(_source_cloud[side])+0.02/float(fighter.model.scale.x)
	var initial_id=int(fposmod(phase,_run_length)*SAMPLE_HZ)%_run_rows.size()
	var seen_air=float(_run_rows[initial_id].min[side])>threshold
	for step in int(ceil(_run_length*SAMPLE_HZ))+1:
		var time=phase+step/SAMPLE_HZ
		var id=int(fposmod(time,_run_length)*SAMPLE_HZ)%_run_rows.size()
		if float(_run_rows[id].min[side])>threshold:seen_air=true
		elif seen_air:return maxf(0.035,step/SAMPLE_HZ/maxf(rate,0.1))
	return _run_length/maxf(rate,0.1)

func _hermite(a: Vector3, velocity: Vector3, b: Vector3, time: float, length: float) -> Vector3:
	var s=clampf(time/maxf(length,0.0001),0,1)
	return a*(2*s*s*s-3*s*s+1)+velocity*length*(s*s*s-2*s*s+s)+b*(-2*s*s*s+3*s*s)

func _root_at(time: float) -> Vector3:
	if _late_stop:return _goal
	var axis=_start_velocity.normalized()
	var displacement=_goal-_start
	var distance=maxf(0,displacement.dot(axis))
	var speed=_start_velocity.length()
	var t=clampf(time,0,_stop_time)
	var traveled=speed*t
	if t>_brake_start:
		var braking=maxf(_stop_time-_brake_start,0.0001)
		var b=t-_brake_start
		traveled=speed*_brake_start+speed*b-speed*b*b/(2*braking)
	var lateral=displacement-axis*distance
	return _start+axis*minf(traveled,distance)+lateral*smoothstep(0,_stop_time,t)

func plan() -> bool:
	var plan_started_usec=Time.get_ticks_usec()
	reset()
	if not _enabled or fighter.state!="move" or fighter.current_clip!="Run" or fighter.is_jumping() or not fighter.is_on_floor():return false
	var velocity=Vector3(fighter.velocity.x,0,fighter.velocity.z)
	if velocity.length()<1.0:return false
	var rig: Skeleton3D=fighter.skeleton
	rig.force_update_all_bone_transforms()
	var incoming=_pose(rig)
	_start=fighter.global_position
	_start_velocity=velocity
	var scale: float=fighter.model.scale.x
	var phase: float=fighter.animation_player.current_animation_position
	var rate: float=fighter.animation_player.speed_scale
	var clouds=[_cloud(rig,0),_cloud(rig,1)]
	var indices=[0,0]
	var start_points: Array=[]
	var velocities: Array=[]
	var contacts: Array=[]
	for side in 2:
		for i in clouds[side].size():
			if Vector3(clouds[side][i]).y<Vector3(clouds[side][indices[side]]).y:indices[side]=i
		var p: Vector3=clouds[side][indices[side]]
		start_points.append(rig.to_global(p))
		var local_v=(_run_cloud(phase+1.0/SAMPLE_HZ,side,indices[side])-_run_cloud(phase-1.0/SAMPLE_HZ,side,indices[side]))*(SAMPLE_HZ*0.5*rate)
		velocities.append(velocity+rig.global_basis*local_v)
		contacts.append(_next_contact(phase,side,rate))
	var forward: Vector3=fighter.forward()
	var first=0 if Vector3(start_points[0]-_start).dot(forward)>Vector3(start_points[1]-_start).dot(forward) else 1
	_first_side=first
	var second=1-first
	for side in 2:_swing_speeds.append(_run_swing_speed(side,indices[side],rate,velocity))
	var first_grounded=_min_y(clouds[first])*scale<=_min_y(_source_cloud[first])*scale+0.025 and Vector3(velocities[first]).y<0.5
	if first_grounded:contacts[first]=0.0
	var landing: Vector3=start_points[first]+forward*maxf(0,Vector3(velocities[first]).dot(forward))*float(contacts[first])/3.0
	var target_anchor: Vector3=_source_cloud[first][indices[first]]
	var root_offset=landing-_start-rig.global_basis*target_anchor
	root_offset.y=0
	var distance=maxf(root_offset.dot(forward),0.03) if first_grounded else maxf(root_offset.dot(forward),velocity.length_squared()/36.0)
	var min_time=maxf(float(contacts[second])+0.06,float(contacts[first])+0.18)
	if not first_grounded:distance=maxf(distance,velocity.length()*min_time/3.0)
	root_offset+=forward*(distance-root_offset.dot(forward))
	var collision=KinematicCollision3D.new()
	_root_clip=fighter.test_move(fighter.global_transform,root_offset,collision,0.001)
	if _root_clip:root_offset=collision.get_travel();root_offset.y=0
	_goal=_start+root_offset
	_stop_time=maxf(0.04,2.0*maxf(0.01,root_offset.dot(forward))/velocity.length())
	duration=maxf(_stop_time,min_time)
	var desired: Array=[]
	for side in 2:desired.append(_goal+rig.global_basis*Vector3(_source_cloud[side][indices[side]]))
	# A wider gathering step may need longer than the next running touchdown.
	# Do not accelerate its sole beyond the existing run's swing speed merely
	# to hit a fixed transition duration.
	var swing_distance=Vector2(Vector3(desired[second]-start_points[second]).x,Vector3(desired[second]-start_points[second]).z).length()
	var swing_speed=float(_swing_speeds[second])
	contacts[second]=maxf(float(contacts[second]),1.5*swing_distance/maxf(swing_speed,1.0))
	# Carry the centre of mass toward the next support before braking. A
	# constant brake from the first frame keeps a long stance held in the air.
	var carry_distance=maxf(0,root_offset.dot(velocity.normalized()))
	_brake_start=minf(float(contacts[second])*0.70,carry_distance/velocity.length()*0.80)
	_stop_time=maxf(0.04,2.0*carry_distance/velocity.length()-_brake_start)
	duration=maxf(maxf(_stop_time,float(contacts[second])+0.06),maxf(float(contacts[first])+0.18,SOURCE_START))
	landing=_goal+rig.global_basis*target_anchor if not _root_clip else landing
	var third=_root_clip and Vector2(landing.x-desired[first].x,landing.z-desired[first].z).length()>0.03
	if third:duration=maxf(duration,float(contacts[second])+0.24)
	for side in 2:
		var foot: Transform3D=rig.get_bone_global_pose(_foot_ids[side])
		var target: Transform3D=_source_feet[side]
		var local_start=foot.affine_inverse()*Vector3(clouds[side][indices[side]])
		var plan={"index":indices[side],"start":start_points[side],"velocity":velocities[side],"q0":foot.basis.orthonormalized().get_rotation_quaternion(),"q1":target.basis.orthonormalized().get_rotation_quaternion(),"ground":_start.y+_min_y(_source_cloud[side])*scale,"initial_min":_start.y+_min_y(clouds[side])*scale,"land":float(contacts[side]),"target":desired[side],"initial_anchor":local_start}
		if side==first:
			plan["first_landing"]=landing
			plan["reposition"]=third
			plan["reposition_start"]=float(contacts[second])+0.04
		else:
			plan["first_landing"]=desired[side]
			plan["reposition"]=false
			plan["lift"]=0.0 if plan.initial_min>plan.ground+0.04 else minf(0.08,float(contacts[first]))
		_plans.append(plan)
	# This is a body preparation with separately solved foot contacts, not a
	# long crossfade used as a substitute for a landing.
	_entry_animation=Animation.new();_entry_animation.length=duration;_entry_animation.loop_mode=Animation.LOOP_NONE
	var root=fighter.animation_player.get_node(fighter.animation_player.root_node)
	var path: NodePath=root.get_path_to(rig)
	var count=maxi(2,ceili(duration*60))
	var samples: Array=[]
	var incoming_chest: Quaternion=rig.get_bone_global_pose(_chest_id).basis.orthonormalized().get_rotation_quaternion()
	var chest_offset=incoming_chest*Quaternion(_prep_rows[0].chest).inverse()
	for sample in count+1:
		var t=duration*sample/count
		var amount=smoothstep(0,duration,t)
		var offset_amount=smoothstep(0,0.10,t)
		var row=_prep(t)
		var pose: Array=[]
		for bone in rig.get_bone_count():
			pose.append({"p":Vector3(incoming[bone].p).lerp(_source_pose[bone].p,amount),"q":Quaternion(incoming[bone].q).slerp(_source_pose[bone].q,amount),"s":Vector3(incoming[bone].s).lerp(_source_pose[bone].s,amount)})
		for bone in _upper_ids:
			var source: Dictionary=row.pose[bone]
			var zero: Dictionary=_prep_rows[0].pose[bone]
			var q_offset=Quaternion(zero.q).inverse()*Quaternion(incoming[bone].q)
			pose[bone]={"p":Vector3(source.p)+(Vector3(incoming[bone].p)-Vector3(zero.p))*(1-offset_amount),"q":Quaternion(source.q)*q_offset.slerp(Quaternion.IDENTITY,offset_amount),"s":Vector3(source.s)+(Vector3(incoming[bone].s)-Vector3(zero.s))*(1-offset_amount)}
		_put(rig,pose)
		var chest: Transform3D=rig.get_bone_global_pose(_chest_id)
		chest.basis=Basis(chest_offset.slerp(Quaternion.IDENTITY,offset_amount)*Quaternion(row.chest))
		rig.set_bone_global_pose(_chest_id,chest)
		samples.append(_pose(rig))
	_put(rig,incoming)
	for bone in rig.get_bone_count():
		for type in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]:
			var track=_entry_animation.add_track(type);_entry_animation.track_set_path(track,NodePath(String(path)+":"+rig.get_bone_name(bone)))
			for sample in count+1:
				var t=duration*sample/count
				if type==Animation.TYPE_POSITION_3D:_entry_animation.position_track_insert_key(track,t,samples[sample][bone].p)
				elif type==Animation.TYPE_ROTATION_3D:_entry_animation.rotation_track_insert_key(track,t,samples[sample][bone].q)
				else:_entry_animation.scale_track_insert_key(track,t,samples[sample][bone].s)
	if _library.has_animation("Plant"):_library.remove_animation("Plant")
	_library.add_animation("Plant",_entry_animation)
	prepared=true
	_diagnostics={"plan_ms":(Time.get_ticks_usec()-plan_started_usec)/1000.0,"planned":true,"duration":duration,"source_start":SOURCE_START,"first_side":"left" if first==0 else "right","phase":phase,"run_min":_run_min,"initial_sole":[_min_y(clouds[0])*scale,_min_y(clouds[1])*scale],"contacts":contacts,"root_forward_m":root_offset.dot(forward),"root_offset":root_offset,"first_grounded":first_grounded,"collision_clipped":_root_clip,"third_step":third,"foot_vertices":[_foot_vertices[0].size(),_foot_vertices[1].size()],"max_target_error_m":0.0}
	return true

func begin() -> void:
	active=true
	_elapsed=0
	_last_elapsed=0
	_air_released=false
	fighter.animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	fighter.animation_player.speed_scale=1
	fighter.animation_player.play("XuRunEntry/Plant",0,1)
	fighter.animation_player.seek(0,true);fighter.animation_player.advance(0)
	fighter.current_clip="XuKRunPlant"

func advance(time: float) -> void:
	_elapsed=clampf(time,0,duration)
	fighter.animation_player.seek(minf(_elapsed,_entry_animation.length),true);fighter.animation_player.advance(0)
	if _elapsed>=0.10:
		# Once the initial Run offset is gone, the source owns the upper pose.
		# Read its original 120Hz cache directly. A second 60Hz animation
		# interpolation can differ by degrees and wrongly fail strict Hit entry.
		var row=_prep(_elapsed)
		var rig: Skeleton3D=fighter.skeleton
		for bone in _upper_ids:
			var pose: Dictionary=row.pose[bone]
			rig.set_bone_pose_position(bone,pose.p)
			rig.set_bone_pose_rotation(bone,pose.q)
			rig.set_bone_pose_scale(bone,pose.s)
		rig.force_update_all_bone_transforms()
		var chest: Transform3D=rig.get_bone_global_pose(_chest_id)
		chest.basis=Basis(Quaternion(row.chest))
		rig.set_bone_global_pose(_chest_id,chest)

func motion(delta: float) -> void:
	var desired=_root_at(_elapsed)
	var d=desired-fighter.global_position
	fighter.velocity.x=d.x/maxf(delta,0.0001);fighter.velocity.z=d.z/maxf(delta,0.0001)

func _point(plan: Dictionary, time: float) -> Dictionary:
	if plan.has("segments"):return _segment_point(plan.segments,time)
	var start: Vector3=plan.start
	var target: Vector3=plan.first_landing
	var land: float=plan.land
	var lift: float=plan.get("lift",0.0)
	var air=true
	var t=time
	var length=land
	var velocity: Vector3=plan.velocity
	if time<lift:return {"p":start,"air":false,"fraction":0.0,"min":plan.ground}
	if lift>0: t-=lift;length-=lift;velocity=Vector3.ZERO
	if time>=land:
		if plan.reposition and time>float(plan.reposition_start):
			start=plan.first_landing;target=plan.target;t=time-float(plan.reposition_start);length=duration-float(plan.reposition_start);velocity=Vector3.ZERO
			air=time<duration
		else:return {"p":plan.first_landing,"air":false,"fraction":1.0,"min":plan.ground}
	var f=clampf(t/maxf(length,0.001),0,1)
	var point=_hermite(start,velocity,target,t,length)
	var initial: float=plan.initial_min if time<land else plan.ground
	var h: float
	if time<land and initial>float(plan.ground)+0.04:
		# A running shoe already in flight keeps its true vertical approach.
		# Adding a new clearance arc here makes a descending foot bounce up
		# immediately before touchdown. A new arc belongs to a new ground step.
		h=maxf(float(plan.ground),_hermite(Vector3(0,initial,0),Vector3(0,velocity.y,0),Vector3(0,float(plan.ground),0),t,length).y)
	else:
		h=lerpf(initial,float(plan.ground),smoothstep(0,1,f))+0.12*pow(sin(PI*f),2)
	return {"p":point,"air":air,"fraction":f,"min":h}

func _segment_point(segments: Array, time: float) -> Dictionary:
	for segment in segments:
		if time<float(segment.begin):return {"p":segment.start,"air":false,"fraction":0.0,"min":segment.min0}
		if time<=float(segment.end):
			var length: float=segment.end-segment.begin
			var t=time-float(segment.begin)
			var f=clampf(t/maxf(length,0.001),0,1)
			var point=_hermite(segment.start,segment.velocity,segment.target,t,length)
			var h: float
			if segment.arc:
				h=lerpf(float(segment.min0),float(segment.min1),smoothstep(0,1,f))+0.12*pow(sin(PI*f),2)
			else:
				h=maxf(float(segment.min1),_hermite(Vector3(0,segment.min0,0),Vector3(0,Vector3(segment.velocity).y,0),Vector3(0,segment.min1,0),t,length).y)
			return {"p":point,"air":f<1,"fraction":f,"min":h}
	var last: Dictionary=segments[-1]
	return {"p":last.target,"air":false,"fraction":1.0,"min":last.min1}

func _segment(start: Vector3, target: Vector3, begin: float, end: float, velocity: Vector3, min0: float, min1: float, arc: bool) -> Dictionary:
	return {"start":start,"target":target,"begin":begin,"end":end,"velocity":velocity,"min0":min0,"min1":min1,"arc":arc}

func _stop_for_late_collision() -> void:
	if _late_stop or _air_released or fighter.is_jumping():return
	var residual=_root_at(_elapsed)-fighter.global_position
	residual.y=0
	if residual.length()<0.02:return
	var blocked=false
	for i in fighter.get_slide_collision_count():
		var collision=fighter.get_slide_collision(i)
		if absf(collision.get_normal().y)<0.5 and residual.dot(collision.get_normal())<0:blocked=true
	if not blocked:return
	# An opponent can enter the stopping lane after the initial test_move.
	# Stop at the actual body, retain the current shoe's approach/contact,
	# then gather each foot under this new centre in an explicit support order.
	var current: Array=[]
	var current_velocity: Array=[]
	var orientations: Array=[]
	for side in 2:
		current.append(_point(_plans[side],_elapsed))
		var before=_point(_plans[side],maxf(0,_elapsed-1.0/120.0))
		var after=_point(_plans[side],_elapsed+1.0/120.0)
		var v=(Vector3(after.p)-Vector3(before.p))*60.0
		v.y=(float(after.min)-float(before.min))*60.0
		current_velocity.append(v)
		orientations.append(Quaternion(_plans[side].q0).slerp(_plans[side].q1,smoothstep(0,duration,_elapsed)))
	_goal=fighter.global_position
	_late_stop=true
	_root_clip=true
	var landing_side=1-_first_side
	if bool(current[_first_side].air):landing_side=_first_side
	var stepping_side=1-landing_side
	var segments: Array=[[],[]]
	var positions: Array=[current[0].p,current[1].p]
	var ready_time=_elapsed
	if bool(current[landing_side].air):
		var old: Dictionary=_plans[landing_side]
		var old_land=float(old.land)
		var landing: Vector3=old.first_landing
		if old.reposition and _elapsed>float(old.reposition_start):old_land=duration;landing=old.target
		ready_time=maxf(old_land,_elapsed+0.02)
		segments[landing_side].append(_segment(positions[landing_side],landing,_elapsed,ready_time,current_velocity[landing_side],float(current[landing_side].min),float(old.ground),false))
		positions[landing_side]=landing
	var desired: Array=[]
	for side in 2:desired.append(_goal+fighter.skeleton.global_basis*Vector3(_source_cloud[side][int(_plans[side].index)]))
	for side in [stepping_side,landing_side]:
		var distance=Vector2(Vector3(desired[side]-positions[side]).x,Vector3(desired[side]-positions[side]).z).length()
		var begin=ready_time+0.03
		var length=maxf(0.12,1.5*distance/maxf(1.0,float(_swing_speeds[side]))) if distance>0.025 else 0.02
		segments[side].append(_segment(positions[side],desired[side],begin,begin+length,Vector3.ZERO,float(_plans[side].ground),float(_plans[side].ground),distance>0.025))
		positions[side]=desired[side]
		ready_time=begin+length
	var previous_duration=duration
	duration=maxf(duration,ready_time+0.06)
	var extra=duration-previous_duration
	fighter.action_duration+=extra
	fighter.attack["duration"]=float(fighter.attack.duration)+extra
	fighter.attack["active"]=Vector2(fighter.attack.active)+Vector2.ONE*extra
	for side in 2:
		_plans[side]["segments"]=segments[side]
		_plans[side]["q0"]=orientations[side]
		_plans[side]["q_start"]=_elapsed
		_plans[side]["q_length"]=duration-_elapsed
	_diagnostics["collision_clipped"]=true
	_diagnostics["late_steps"]=segments.duplicate(true)
	_diagnostics["late_collision"]=true
	_diagnostics["late_collision_at"]=_elapsed
	_diagnostics["late_collision_error_m"]=residual.length()
	_diagnostics["late_collision_root"]=_goal
	_diagnostics["late_collision_extended_s"]=extra
	_diagnostics["duration"]=duration

func _solve_leg(ids: Array, target: Vector3, basis: Basis) -> float:
	var rig: Skeleton3D=fighter.skeleton
	var upper: Transform3D=rig.get_bone_global_pose(ids[0]);var lower: Transform3D=rig.get_bone_global_pose(ids[1]);var foot: Transform3D=rig.get_bone_global_pose(ids[2])
	var l1=upper.origin.distance_to(lower.origin);var l2=lower.origin.distance_to(foot.origin)
	var d=target-upper.origin;var length=clampf(d.length(),absf(l1-l2)+0.00001,(l1+l2)*0.997)
	var direction=d.normalized();var along=(l1*l1-l2*l2+length*length)/(2*length)
	var center=upper.origin+direction*along
	var bend=lower.origin-center;bend-=direction*bend.dot(direction)
	if bend.length_squared()<0.000001:bend=Vector3.FORWARD.cross(direction)
	bend=bend.normalized()
	var knee=center+bend*sqrt(maxf(0,l1*l1-along*along))
	upper.basis=Basis(Quaternion((lower.origin-upper.origin).normalized(),(knee-upper.origin).normalized()))*upper.basis
	rig.set_bone_global_pose(ids[0],upper)
	lower=rig.get_bone_global_pose(ids[1]);foot=rig.get_bone_global_pose(ids[2])
	lower.basis=Basis(Quaternion((foot.origin-lower.origin).normalized(),(target-lower.origin).normalized()))*lower.basis
	rig.set_bone_global_pose(ids[1],lower)
	foot=rig.get_bone_global_pose(ids[2]);foot.basis=basis;rig.set_bone_global_pose(ids[2],foot)
	return foot.origin.distance_to(target)*float(fighter.model.scale.x)

func solve_after_move() -> void:
	if not active:return
	if fighter.is_jumping():_air_released=true
	if _air_released:
		_diagnostics["air_released"]=true
		return
	_stop_for_late_collision()
	var rig: Skeleton3D=fighter.skeleton
	rig.force_update_all_bone_transforms()
	var max_error=0.0
	var actual_min: Array=[]
	var targets: Array=[]
	var lower=0.0
	for side in 2:
		var plan: Dictionary=_plans[side]
		var desired=_point(plan,_elapsed)
		var q: Quaternion=Quaternion(plan.q0).slerp(plan.q1,smoothstep(0,float(plan.get("q_length",duration)),_elapsed-float(plan.get("q_start",0.0))))
		var basis=Basis(q)
		var foot: Transform3D=rig.get_bone_global_pose(_foot_ids[side])
		var cloud=_cloud(rig,side)
		var local_cloud: Array=[]
		for p in cloud:local_cloud.append(foot.affine_inverse()*Vector3(p))
		var anchor: Vector3=local_cloud[int(plan.index)]
		var target=rig.to_local(Vector3(desired.p))-basis*anchor
		var min_y=INF
		for p in local_cloud:min_y=minf(min_y,(basis*Vector3(p)).y)
		var sole_height: float=desired.min
		if not desired.air and float(plan.initial_min)<=float(plan.ground)+0.04:
			sole_height=lerpf(float(plan.initial_min),float(plan.ground),smoothstep(0,minf(0.10,duration),_elapsed))
		target.y=(sole_height-rig.global_position.y)/float(fighter.model.scale.x)-min_y
		var ids: Array=_leg_ids[side]
		var up: Vector3=rig.get_bone_global_pose(ids[0]).origin
		var knee: Vector3=rig.get_bone_global_pose(ids[1]).origin
		var ankle: Vector3=rig.get_bone_global_pose(ids[2]).origin
		var length=(up.distance_to(knee)+knee.distance_to(ankle))*0.995
		var horizontal=Vector2(target.x-up.x,target.z-up.z).length()
		if horizontal<length:
			lower=maxf(lower,up.y-target.y-sqrt(length*length-horizontal*horizontal))
		else:lower=maxf(lower,0.14/float(fighter.model.scale.x))
		targets.append({"p":target,"b":basis,"sole":sole_height})
	lower=clampf(lower,0,0.14/float(fighter.model.scale.x))
	if lower>0:
		var hip=rig.find_bone("mixamorig_Hips")
		var h: Transform3D=rig.get_bone_global_pose(hip);h.origin.y-=lower;rig.set_bone_global_pose(hip,h)
	for side in 2:
		var row: Dictionary=targets[side]
		var error=0.0
		for iteration in 3:
			error=_solve_leg(_leg_ids[side],row.p,row.b)
			var actual=rig.global_position.y+_min_y(_cloud(rig,side))*float(fighter.model.scale.x)
			if absf(actual-float(row.sole))<0.0005:break
			row.p.y+=(float(row.sole)-actual)/float(fighter.model.scale.x)
		max_error=maxf(max_error,error)
		actual_min.append(rig.global_position.y+_min_y(_cloud(rig,side))*float(fighter.model.scale.x))
	_diagnostics["max_target_error_m"]=max_error
	_diagnostics["pelvis_lower_m"]=lower*float(fighter.model.scale.x)
	_diagnostics["actual_sole_min_y"]=actual_min
	_diagnostics["root_error_m"]=Vector2((_root_at(_elapsed)-fighter.global_position).x,(_root_at(_elapsed)-fighter.global_position).z).length()
	_diagnostics["elapsed"]=_elapsed

func reaction_source_time() -> float:
	# Only this explicit grounded stop/preparation may transfer to the K
	# family reaction. The early Run offset and a jump release are different
	# pose owners even if an isolated arm happens to resemble the prefix.
	if not active or not prepared or _air_released or _elapsed<0.10:return -1.0
	return minf(_elapsed,SOURCE_START)

func finish() -> void:
	active=false

func status() -> Dictionary:
	var d=_diagnostics.duplicate(true);d["active"]=active;d["prepared"]=prepared;return d
