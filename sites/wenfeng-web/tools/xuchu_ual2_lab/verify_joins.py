from verify_rig import *
new=Sampler(OUTPUT/"xuchu-ual2-family-recoveries.glb")
report={'input_sha256':hashlib.sha256(new.path.read_bytes()).hexdigest(),'model_scale':2.15,'status':'EXACT JOIN PROBE ONLY; no blend','joins':{}}
for letter,t in [('A',13/30),('B',1.)]:
 fw,fp=new.pose('XuUAL2RegularTwistRig',t);rw,rp=new.pose('XuUAL2Regular'+letter+'RecoveryTwistRig',0);rawfw,_=new.pose('XuUAL2RegularFull',t);rawrw,_=new.pose('XuUAL2Regular'+letter+'RecoveryRaw',0);pv=[];av=[];local=[]
 for i in new.order:
  pv.append((np.linalg.norm(fw[i][0]-rw[i][0])*scale,i));av.append((np.rad2deg((fw[i][1]*rw[i][1].inv()).magnitude()),i));local.append((np.rad2deg((R.from_quat(fp[i][1])*R.from_quat(rp[i][1]).inv()).magnitude()),i))
 v1=vertices(fw,ng);v2=vertices(rw,ng);diff=[np.linalg.norm(x-y,axis=1)*scale for x,y in zip(v1,v2)];maxvertex=max((float(np.max(d)),p,int(np.argmax(d)))for p,d in enumerate(diff));p1=fw[h][0]+fw[h][1].apply(points);p2=rw[h][0]+rw[h][1].apply(points)
 report['joins'][letter]={'full_time':t,'source_body_raw_max_position_m':float(max(np.linalg.norm(rawfw[i][0]-rawrw[i][0])*scale for i in old.order)),'world_bone_position_peaks':[(float(v),new.nodes[i]['name'])for v,i in sorted(pv,reverse=True)[:8]],'world_bone_rotation_peaks_deg':[(float(v),new.nodes[i]['name'])for v,i in sorted(av,reverse=True)[:8]],'local_rotation_peaks_deg':[(float(v),new.nodes[i]['name'])for v,i in sorted(local,reverse=True)[:8]],'mesh_max_vertex_error_world_m':maxvertex,'palm_base_tip_errors_m':np.linalg.norm(p1-p2,axis=1).tolist(),'right_arm_details':{new.nodes[i]['name']:{'full_world_position':fw[i][0].tolist(),'rec_world_position':rw[i][0].tolist(),'full_local_rotation':fp[i][1].tolist(),'rec_local_rotation':rp[i][1].tolist()}for i in[a,e,h]+foregroup[1:]}}
print(json.dumps(report,indent=2));(B/'family-join-initial.json').write_text(json.dumps(report,indent=2))
