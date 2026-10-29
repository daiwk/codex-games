extends SceneTree
var OUTPUT = ""
const MODEL="res://assets/characters/zhaoyun.glb"
const MANIFEST="res://assets/characters/animation_manifest.json"
func _initialize():
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--output="):OUTPUT=arg.trim_prefix("--output=").simplify_path()
 var project=ProjectSettings.globalize_path("res://").simplify_path()
 if not OUTPUT.is_absolute_path() or OUTPUT.begins_with(project) or FileAccess.file_exists(OUTPUT) or not DirAccess.dir_exists_absolute(OUTPUT.get_base_dir()):
  printerr("Pass a new absolute --output outside the project, with an existing parent.")
  quit(2)
  return
 call_deferred("run")
func find_type(n:Node,t:String):
 if n.is_class(t):return n
 for c in n.get_children():
  var x=find_type(c,t)
  if x!=null:return x
 return null
func bone(rig:Skeleton3D,suffix:String):
 for i in rig.get_bone_count():
  if rig.get_bone_name(i).ends_with(suffix):return i
 return -1
func vec(v:Vector3):return [v.x,v.y,v.z]
func quat(q:Quaternion):return [q.x,q.y,q.z,q.w]
func run():
 var hash=FileAccess.get_sha256(MODEL)
 assert(hash=="23ba8aabd2bafa6d06ff9332008b1828fa27d1d56d9f1def85ea0acc3dfafe29")
 var model=(load(MODEL)as PackedScene).instantiate();root.add_child(model)
 assert(find_type(model,"SkeletonModifier3D")==null,"GLB model must have no modifiers")
 var rig:Skeleton3D=find_type(model,"Skeleton3D");var ap:AnimationPlayer=find_type(model,"AnimationPlayer")
 ap.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 var alias=""
 for k in ap.get_animation_list():
  if k.get_slice("/",k.get_slice_count("/")-1)=="GuardBreak":alias=k
 assert(not alias.is_empty())
 var duration=ap.get_animation(alias).length;ap.get_animation(alias).loop_mode=Animation.LOOP_NONE
 var ids={"left":bone(rig,"LeftHand"),"right":bone(rig,"RightHand")};assert(ids.left>=0 and ids.right>=0)
 var cfg:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST)).zhaoyun.grip
 ap.play(alias,0,1.0)
 var rows=[];var count=int(round(duration*120))+1
 for i in count:
  var t=duration if i==count-1 else i/120.0
  ap.seek(t,true);ap.advance(0);rig.force_update_all_bone_transforms()
  var r={"time":t}
  for side in ["left","right"]:
   var pose=rig.get_bone_global_pose(ids[side]);var off:Array=cfg[side+"_palm"]
   r[side+"_palm"]=vec(pose*Vector3(off[0],off[1],off[2]));r[side+"_hand_q"]=quat(pose.basis.orthonormalized().get_rotation_quaternion().normalized())
  rows.append(r)
 var doc={"sha256":hash,"alias":alias,"duration":duration,"sample_hz":120,"space":"Skeleton3D local space: get_bone_global_pose hand transform * original palm offset; hand quaternion from orthonormalized Skeleton-global basis. No model.scale1.98, actor yaw/translation, modifiers, runtime IK or animation crossfade. PackedScene real imported resource; AnimationPlayer manual play(alias,0), seek(t,true)+advance(0).","bone_names":{"left":rig.get_bone_name(ids.left),"right":rig.get_bone_name(ids.right)},"grip_offsets":{"left":cfg.left_palm,"right":cfg.right_palm},"model_scale":vec(model.scale),"skeleton_node_transform":{"origin":vec(rig.transform.origin),"basis_x":vec(rig.transform.basis.x),"basis_y":vec(rig.transform.basis.y),"basis_z":vec(rig.transform.basis.z)},"rows":rows}
 var f=FileAccess.open(OUTPUT,FileAccess.WRITE);assert(f!=null);f.store_string(JSON.stringify(doc,"  "));f.close();print("GUARDBREAK_SOURCE_ROWS ",rows.size()," ",OUTPUT);quit()
