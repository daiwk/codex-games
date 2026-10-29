extends SceneTree

var camera_kind = "normal"
var seconds = 3.0
var clip = "XuUAL2RegularTwistRig"
var output = ""
var viewport: SubViewport
var rig: Skeleton3D
var player: AnimationPlayer
var model: Node3D
var grip: Node3D
var weapon: Node3D
var camera: Camera3D
var overlay: FrameOverlay
var rows: Array = []
var grip_config: Dictionary
var indices: Dictionary = {}
var wrist_max = {"Left_swing":0., "Left_twist":0., "Right_swing":0., "Right_twist":0.}
var length_error = 0.0

class FrameOverlay extends Control:
	var index = 0
	var caption = ""
	func _draw() -> void:
		draw_rect(Rect2(0,0,1280,42),Color(0.01,0.015,0.02,.96))
		for bit in 16:
			draw_rect(Rect2(8+bit*8,8,7,16),Color.WHITE if (index>>bit)&1 else Color.BLACK)
		draw_string(ThemeDB.fallback_font,Vector2(148,25),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
		draw_string(ThemeDB.fallback_font,Vector2(20,780),"TMP TWIST RIG / NOT ACCEPTED | Full source hips/legs/left; offline right-arm retarget | 1.0x",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color(.78,.85,.9))

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--camera="): camera_kind = arg.trim_prefix("--camera=")
		if arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		if arg.begins_with("--clip="): clip = arg.trim_prefix("--clip=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	call_deferred("run")

func find_type(node: Node, type: String):
	if node.is_class(type): return node
	for child in node.get_children():
		var found = find_type(child,type)
		if found != null: return found
	return null

func material(color: Color, roughness = 0.9) -> StandardMaterial3D:
	var m = StandardMaterial3D.new(); m.albedo_color = color; m.roughness = roughness
	return m

func box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var node = MeshInstance3D.new(); var mesh = BoxMesh.new();mesh.size=size;node.mesh=mesh;node.position=at;node.material_override=mat;parent.add_child(node)

func p(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func wrist(side: String) -> Dictionary:
	var fore = rig.get_bone_global_pose(indices[side+"ForeArm"])
	var hand = rig.get_bone_global_pose(indices[side+"Hand"])
	var rest = rig.get_bone_rest(indices[side+"Hand"])
	var axis = (hand.origin-fore.origin).normalized()
	var wrist_fore = rig.get_bone_global_pose(indices.RightForeArmTwist3) if side == "Right" else fore
	var neutral = wrist_fore.basis.orthonormalized()*rest.basis.orthonormalized()
	var delta = (hand.basis.orthonormalized()*neutral.inverse()).get_rotation_quaternion().normalized()
	if delta.w<0: delta=-delta
	var dot = Vector3(delta.x,delta.y,delta.z).dot(axis)
	var twist = Quaternion(axis.x*dot,axis.y*dot,axis.z*dot,delta.w)
	if dot*dot+delta.w*delta.w<1e-8: twist=Quaternion.IDENTITY
	else: twist=twist.normalized()
	if twist.w<0:twist=-twist
	var swing=(delta*twist.inverse()).normalized()
	var swing_angle=2*atan2(Vector3(swing.x,swing.y,swing.z).length(),absf(swing.w))
	var twist_angle=absf(2*atan2(Vector3(twist.x,twist.y,twist.z).dot(axis),twist.w))
	var rest_length = rig.get_bone_global_rest(indices[side+"Hand"]).origin.distance_to(rig.get_bone_global_rest(indices[side+"ForeArm"]).origin)
	length_error=maxf(length_error,absf(hand.origin.distance_to(fore.origin)-rest_length))
	wrist_max[side+"_swing"]=maxf(wrist_max[side+"_swing"],rad_to_deg(swing_angle))
	wrist_max[side+"_twist"]=maxf(wrist_max[side+"_twist"],rad_to_deg(twist_angle))
	return {"swing_deg":rad_to_deg(swing_angle),"twist_deg":rad_to_deg(twist_angle)}

func frame_row(index: int, t: float) -> Dictionary:
	var bones = {}
	for suffix in indices: bones[suffix]=p(rig.to_global(rig.get_bone_global_pose(indices[suffix]).origin))
	return {"index":index,"seconds":t,"bake_frame_1based":int(round(t*120))+1,"animation_time":player.current_animation_position,
		"bones":bones,"right_grip":p(grip.global_position),"blade_base":p(weapon.to_global(Vector3(0,30,0))),"blade_tip":p(weapon.to_global(Vector3(0,99,0))),
		"Left_wrist":wrist("Left"),"Right_wrist":wrist("Right"),"camera":p(camera.global_position)}

func run() -> void:
	if output.is_empty(): output = ProjectSettings.globalize_path("res://captures/"+camera_kind)
	Engine.physics_ticks_per_second=60
	root.size=Vector2i(640,400)
	viewport=SubViewport.new();viewport.size=Vector2i(1280,800);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.msaa_3d=Viewport.MSAA_2X;root.add_child(viewport)
	var stage=Node3D.new();viewport.add_child(stage)
	var world=WorldEnvironment.new();var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.095,.13,.18);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.65,.75,.9);env.ambient_light_energy=.6;env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;env.tonemap_exposure=.92;world.environment=env;stage.add_child(world)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-42,-28,0);sun.light_color=Color(1,.91,.79);sun.light_energy=1.3;sun.shadow_enabled=true;stage.add_child(sun)
	var fill=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-25,145,0);fill.light_color=Color(.67,.79,1);fill.light_energy=.35;stage.add_child(fill)
	box(stage,Vector3(12,.04,12),Vector3(0,-.02,0),material(Color(.23,.29,.34)))
	var line_material=material(Color(.30,.37,.42))
	for i in range(-12,13):
		box(stage,Vector3(12,.001,.004),Vector3(0,.001,i*.5),line_material)
		box(stage,Vector3(.004,.001,12),Vector3(i*.5,.001,0),line_material)
	model=(load("res://compatible.glb") as PackedScene).instantiate();model.scale=Vector3.ONE*2.15;stage.add_child(model)
	rig=find_type(model,"Skeleton3D");player=find_type(model,"AnimationPlayer")
	assert(rig!=null and player!=null)
	for i in rig.get_bone_count():
		for suffix in ["Hips","Spine","Spine1","Spine2","Head","LeftArm","RightArm","LeftForeArm","RightForeArm","LeftHand","RightHand","LeftLeg","RightLeg","LeftFoot","RightFoot","LeftToeBase","RightToeBase","RightForeArmTwist1","RightForeArmTwist2","RightForeArmTwist3"]:
			if rig.get_bone_name(i).ends_with(suffix):indices[suffix]=i
	grip_config=JSON.parse_string(FileAccess.get_file_as_string("res://grip.json"))
	var attachment=BoneAttachment3D.new();attachment.bone_name=rig.get_bone_name(indices.RightHand);rig.add_child(attachment)
	grip=Node3D.new();grip.position=Vector3(grip_config.position[0],grip_config.position[1],grip_config.position[2]);var q:Array=grip_config.rotation_xyzw;grip.quaternion=Quaternion(q[0],q[1],q[2],q[3]);attachment.add_child(grip)
	weapon=(load("res://xuchu_saber.glb") as PackedScene).instantiate();weapon.scale=Vector3.ONE*float(grip_config.mesh_scale);weapon.position.y=float(grip_config.mesh_grip_y);grip.add_child(weapon)
	camera=Camera3D.new();camera.fov=44;camera.position=Vector3(2.8,1.8,4.4) if camera_kind=="normal" else Vector3(-2.65,1.65,.35);stage.add_child(camera);camera.look_at(Vector3(0,1.02,0) if camera_kind=="normal" else Vector3(-.15,1.45,0),Vector3.UP);camera.current=true
	var layer=CanvasLayer.new();viewport.add_child(layer);overlay=FrameOverlay.new();layer.add_child(overlay)
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	assert(player.has_animation(clip),"Missing new source alias")
	player.get_animation(clip).loop_mode=Animation.LOOP_NONE;player.play(clip,0,1.0);player.seek(0,true);player.advance(0)
	for warm in 4:await process_frame
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	var sample_count=int(round(seconds*60))
	for index in sample_count:
		var t=minf(index/60.0,player.get_animation(clip).length)
		player.seek(t,true);player.advance(0)
		rig.force_update_all_bone_transforms()
		overlay.index=index;overlay.caption="F%04d  %.3fs  UAL2 -> XU / TWIST RIG TRIAL / %s / 1.0x"%[index,t,camera_kind];overlay.queue_redraw()
		await physics_frame
		await process_frame
		await create_timer(0.0,true,false).timeout
		RenderingServer.force_draw(false,1.0/60.0)
		var im=viewport.get_texture().get_image()
		var err=im.save_jpg(output.path_join("frames/%05d.jpg"%index),.96)
		assert(err==OK,"Cannot save source preview frame")
		rows.append(frame_row(index,t))
		if index%60==0:print("UAL2_NATIVE ",camera_kind," ",index,"/",sample_count)
	FileAccess.open(output.path_join("trace.json"),FileAccess.WRITE).store_string(JSON.stringify({"fps":60,"seconds":seconds,"clip":clip,"camera":camera_kind,"frame_count":rows.size(),"whole_body_source_rate":1.0,"mode":"Standalone retarget trial, not runtime acceptance. Offline right-arm elbow circle + distributed forearm twist; right palm and blade path preserved. Full source hips/legs/left and all timing unchanged; no runtime gameplay/IK/grounding.","model_sha256":FileAccess.get_sha256("res://compatible.glb"),"weapon_sha256":FileAccess.get_sha256("res://xuchu_saber.glb"),"wrist_max_degrees":wrist_max,"bone_length_error_model_max":length_error,"frames":rows},"\t"))
	print("UAL2_NATIVE_COMPLETE ",output)
	quit()
