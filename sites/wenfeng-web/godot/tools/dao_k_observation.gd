extends RefCounted
const EDGE_POINT = Vector3(6.4614506,63.640232,-1.0068892)
const TIP_VERTEX = Vector3(-4.470485,100.0,-1.7452493)
static func sample(transform:Transform3D) -> Dictionary:
	return {"edge_direction":v(transform.basis.x.normalized()),"blade_normal":v(transform.basis.z.normalized()),"edge_vertex":v(transform*EDGE_POINT),"actual_tip_vertex":v(transform*TIP_VERTEX)}
static func v(p:Vector3) -> Array:return [p.x,p.y,p.z]
static func visit(node:Node, rows:Array) -> void:
	if node is MeshInstance3D:
		for s in node.mesh.get_surface_count():
			var a=node.mesh.surface_get_arrays(s)
			if a[Mesh.ARRAY_WEIGHTS]!=null and a[Mesh.ARRAY_WEIGHTS].size()>0:
				rows.append({"name":node.name,"surface":s,"vertices":a[Mesh.ARRAY_VERTEX].size(),"weights_per_vertex":float(a[Mesh.ARRAY_WEIGHTS].size())/a[Mesh.ARRAY_VERTEX].size(),"bones_per_vertex":float(a[Mesh.ARRAY_BONES].size())/a[Mesh.ARRAY_VERTEX].size(),"skin_bind_count":node.skin.get_bind_count() if node.skin!=null else 0,"visible":node.visible})
	for child in node.get_children():visit(child,rows)
static func identity(actor) -> Dictionary:
	var rows:Array=[];visit(actor.model,rows)
	var twists:Array=[]
	for i in actor.skeleton.get_bone_count():
		if "UpperArmTwist" in String(actor.skeleton.get_bone_name(i)):twists.append(String(actor.skeleton.get_bone_name(i)))
	var tracks:Array=[]
	if actor.animation_names.has("XuUAL1GameK"):
		var clip=actor.animation_player.get_animation(actor.animation_names.XuUAL1GameK)
		for i in clip.get_track_count():
			if "UpperArmTwist" in String(clip.track_get_path(i)):tracks.append(String(clip.track_get_path(i)))
	return {"character_id":actor.character_id,"model_sha256":FileAccess.get_sha256("res://assets/characters/%s.glb"%actor.character_id),"source_library_sha256":FileAccess.get_sha256("res://assets/motion/xuchu_ual1_k.glb"),"skeleton_bones":actor.skeleton.get_bone_count(),"twist_bones":twists,"source_twist_tracks":tracks,"render_meshes":rows,"grip_quaternion":str(actor.grip.quaternion),"mesh_quaternion":str(actor.weapon_mesh.quaternion)}
