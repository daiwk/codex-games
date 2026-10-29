from verify_rig import *
new=Sampler(OUTPUT/"xuchu-ual2-family-recoveries.glb")
report={'status':'TMP RECOVERY OPTIONS / NOT VISUAL ACCEPTANCE / no chain join claimed','sha256':hashlib.sha256(new.path.read_bytes()).hexdigest(),'shared_calibration':json.loads((B/'family-recoveries.json').read_text())['family_calibration'],'clips':{}}
footmasks=[]
for v,ids,we in og[2]:
 names=np.array([old.nodes[i].get('name','')for i in og[0]]);foot=np.array([('Foot'in n or'Toe'in n)for n in names]);footmasks.append(np.sum(we*foot[ids],axis=1)>.35)
for letter in ['A','B']:
 rawalias='XuUAL2Regular'+letter+'RecoveryRaw';alias='XuUAL2Regular'+letter+'RecoveryTwistRig';duration=new.duration(rawalias);ts=np.linspace(0,duration,round(duration*240)+1);met={'duration':duration,'samples':len(ts),'max_palm_error_world_m':0.,'max_blade_tip_error_world_m':0.,'max_hand_angle_deg':0.,'max_body_world_error_m':0.,'max_bone_error_m':0.,'max_wrist_swing_deg':0.,'max_wrist_twist_deg':0.,'max_elbow_shift_world_m':0.,'max_elbow_correction_step_60hz_m':0.,'source_min_volumes':{k:1. for k in regions},'candidate_min_volumes':{k:1. for k in regions},'actual_skinned_foot_lower_world_y_range':[1e9,-1e9],'endpoints':{}};previous=None
 for num,t in enumerate(ts):
  ow,op=new.pose(rawalias,float(t));nw,np_=new.pose(alias,float(t));oe=ow[h][0]+ow[h][1].apply(points);ne=nw[h][0]+nw[h][1].apply(points);err=np.linalg.norm(oe-ne,axis=1)*scale;met['max_palm_error_world_m']=max(met['max_palm_error_world_m'],float(err[0]));met['max_blade_tip_error_world_m']=max(met['max_blade_tip_error_world_m'],float(err[2]));met['max_hand_angle_deg']=max(met['max_hand_angle_deg'],float(np.rad2deg((ow[h][1]*nw[h][1].inv()).magnitude())))
  for i in old.order:
   if i not in[a,e,h]and not old.nodes[i].get('name','').startswith('mixamorig:RightHand'):met['max_body_world_error_m']=max(met['max_body_world_error_m'],float(np.linalg.norm(ow[i][0]-nw[i][0])*scale))
  met['max_bone_error_m']=max(met['max_bone_error_m'],abs(np.linalg.norm(nw[e][0]-nw[a][0])-np.linalg.norm(ow[e][0]-ow[a][0]))*scale,abs(np.linalg.norm(nw[h][0]-nw[e][0])-np.linalg.norm(ow[h][0]-ow[e][0]))*scale)
  ax=nw[h][0]-nw[e][0];ax/=np.linalg.norm(ax);H=nw[h][1];F=nw[end][1];hf=H.apply(forward);sw=np.arccos(np.clip(np.dot(ax,hf),-1,1));al=between(ax,hf);ns=(F*restH).apply(side);cs=(al.inv()*H).apply(side);ns-=ax*np.dot(ns,ax);cs-=ax*np.dot(cs,ax);ns/=np.linalg.norm(ns);cs/=np.linalg.norm(cs);tw=abs(np.arctan2(np.dot(ax,np.cross(ns,cs)),np.dot(ns,cs)));met['max_wrist_swing_deg']=max(met['max_wrist_swing_deg'],float(np.rad2deg(sw)));met['max_wrist_twist_deg']=max(met['max_wrist_twist_deg'],float(np.rad2deg(tw)))
  for lab,w,g,key in [('old',ow,og,'source_min_volumes'),('new',nw,ng,'candidate_min_volumes')]:
   for name,v in volume(w,g,lab).items():met[key][name]=min(met[key][name],v)
  verts=vertices(ow,og);lower=min(float(v[mask,1].min())*scale for v,mask in zip(verts,footmasks)if np.any(mask));met['actual_skinned_foot_lower_world_y_range'][0]=min(met['actual_skinned_foot_lower_world_y_range'][0],lower);met['actual_skinned_foot_lower_world_y_range'][1]=max(met['actual_skinned_foot_lower_world_y_range'][1],lower)
  delta=nw[e][0]-ow[e][0];met['max_elbow_shift_world_m']=max(met['max_elbow_shift_world_m'],float(np.linalg.norm(delta)*scale))
  if num%4==0:
   if previous is not None:met['max_elbow_correction_step_60hz_m']=max(met['max_elbow_correction_step_60hz_m'],float(np.linalg.norm(delta-previous)*scale))
   previous=delta
  if num in[0,len(ts)-1]:
   met['endpoints']['start'if num==0 else'end']={old.nodes[i]['name']:{'world_rig_position':nw[i][0].tolist(),'world_rotation_xyzw':nw[i][1].as_quat().tolist()}for i in old.order if old.nodes[i].get('name','').endswith(('Hips','LeftFoot','RightFoot','LeftHand','RightHand','RightForeArm','RightArm'))}
 report['clips'][alias]=met;print(alias,{k:v for k,v in met.items()if k!='endpoints'},flush=True)
(B/'family-recoveries-verification.json').write_text(json.dumps(report,indent=2))
