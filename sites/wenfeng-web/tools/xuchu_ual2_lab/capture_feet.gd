extends SceneTree

# Native source/target foot close-up. No gait/pose/height correction.
var kind = "target"
var rows: Array = []
var output = ""

class FootFrameLabel extends Control:
	var frame = 0
	var caption = ""
	func _draw() -> void:
		draw_rect(Rect2(0,0,1280,42),Color(.01,.02,.03,.98))
		for bit in 16:
			draw_rect(Rect2(8+bit*8,8,7,16),Color.WHITE if (frame>>bit)&1 else Color.BLACK)
		draw_string(ThemeDB.fallback_font,Vector2(148,27),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color.WHITE)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--kind="):kind=arg.trim_prefix("--kind=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func find_type(node: Node, type: String):
	if node.is_class(type):return node
	for child in node.get_children():
		var found=find_type(child,type)
		if found!=null:return found
	return null

func box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var node=MeshInstance3D.new();var mesh=BoxMesh.new();mesh.size=size;node.mesh=mesh;node.position=at
	var mat=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.9;node.material_override=mat;parent.add_child(node)

func p(v:Vector3)->Array:return [v.x,v.y,v.z]

func run() -> void:
	assert(kind in ["source","target"])
	assert(output.is_absolute_path(), "Pass an absolute --output directory outside the game project")
	root.size=Vector2i(640,400)
	var viewport=SubViewport.new();viewport.size=Vector2i(1280,800);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.msaa_3d=Viewport.MSAA_2X;root.add_child(viewport)
	var stage=Node3D.new();viewport.add_child(stage)
	var world=WorldEnvironment.new();var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color(.10,.14,.19);env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color(.72,.8,.95);env.ambient_light_energy=.7;world.environment=env;stage.add_child(world)
	var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,-25,0);light.light_energy=1.5;light.shadow_enabled=true;stage.add_child(light)
	box(stage,Vector3(8,.04,8),Vector3(0,-.02,0),Color(.25,.30,.35))
	for i in range(-20,21):
		box(stage,Vector3(8,.001,.004),Vector3(0,.001,i*.1),Color(.38,.44,.48))
		box(stage,Vector3(.004,.001,8),Vector3(i*.1,.001,0),Color(.38,.44,.48))
	var model=(load("res://ual2.glb" if kind=="source" else "res://compatible.glb")as PackedScene).instantiate()
	model.scale=Vector3.ONE*(1.0942450747005428 if kind=="source" else 2.15);stage.add_child(model)
	var rig:Skeleton3D=find_type(model,"Skeleton3D");var player:AnimationPlayer=find_type(model,"AnimationPlayer")
	var clip="Sword_Regular_Combo" if kind=="source" else "XuUAL2RegularTwistRig"
	assert(player.has_animation(clip))
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;player.get_animation(clip).loop_mode=Animation.LOOP_NONE;player.play(clip,0,1.0)
	var camera=Camera3D.new();camera.fov=30;camera.position=Vector3(-2.3,.48,.40);stage.add_child(camera);camera.look_at(Vector3(0,.28,0),Vector3.UP);camera.current=true
	var layer=CanvasLayer.new();viewport.add_child(layer);var label=FootFrameLabel.new();layer.add_child(label)
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	for warm in 4:await process_frame
	for frame in 60:
		var t=frame/60.0;player.seek(t,true);player.advance(0);rig.force_update_all_bone_transforms()
		label.frame=frame;label.caption="%s F%03d t=%.3f / SOURCE 1x / 10cm FLOOR GRID"%[kind,frame,t];label.queue_redraw()
		await physics_frame;await process_frame;await create_timer(0.,true,false).timeout;RenderingServer.force_draw(false,1./60.)
		assert(viewport.get_texture().get_image().save_jpg(output.path_join("frames/%05d.jpg"%frame),.97)==OK)
		var bones={}
		for n in rig.get_bone_count():
			var name=String(rig.get_bone_name(n))
			if "foot"in name.to_lower()or"toe"in name.to_lower():bones[name]=p(rig.to_global(rig.get_bone_global_pose(n).origin))
		rows.append({"index":frame,"seconds":t,"bones":bones})
	FileAccess.open(output.path_join("trace.json"),FileAccess.WRITE).store_string(JSON.stringify({"kind":kind,"fps":60,"seconds":1,"clip":clip,"floor_y":0,"scale":model.scale.x,"model_sha256":FileAccess.get_sha256("res://ual2.glb" if kind=="source" else "res://compatible.glb"),"warning":"Joint positions are not soles. No per-frame height adjustment. Standalone source comparison, not gameplay acceptance.","frames":rows}))
	print("FOOT_CAPTURE_DONE ",kind," ",output);quit()
