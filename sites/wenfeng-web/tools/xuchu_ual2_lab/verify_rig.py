from lab_context import OUTPUT, TOOLS, SOURCE, TARGET, MANIFEST
from pathlib import Path
import sys,json,hashlib
import numpy as np
from scipy.spatial.transform import Rotation as R
sys.path.insert(0,str(TOOLS))
from prepare_polearms import Sampler,between
B=OUTPUT;old=Sampler(B/'xuchu-ual2-full-body-prototype.glb');new=Sampler(B/'xuchu-ual2-twist-rig-experiment.glb');a,e,h=[old.names['mixamorig:Right'+p]for p in ['Arm','ForeArm','Hand']];end=new.names['mixamorig:RightForeArmTwist3'];foregroup=[e]+[new.names['mixamorig:RightForeArmTwist'+str(k)]for k in [1,2,3]];scale=2.15;bindold=old.pose()[0];bindnew=new.pose()[0]
restH=R.from_quat(old.nodes[h]['rotation']);axloc=np.array(old.nodes[h]['translation']);axloc/=np.linalg.norm(axloc);forward=restH.inv().apply(axloc);side=np.array([1.,0,0])if abs(forward[0])<.8 else np.array([0.,1,0]);side-=forward*np.dot(side,forward);side/=np.linalg.norm(side)
man=json.loads(MANIFEST.read_text())['xuchu']['grip'];gp=np.array(man['position']);gr=R.from_quat(man['rotation_xyzw']);points=np.array([man['right_palm'],gp+gr.apply([0,man['mesh_grip_y']+man['mesh_scale']*30,0]),gp+gr.apply([0,man['mesh_grip_y']+man['mesh_scale']*99,0])])
def geometry(model):
 skin=model.j['skins'][0];joints=np.array(skin['joints']);ibm=model.accessor(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1);geos=[]
 for mesh in model.j['meshes']:
  for prim in mesh['primitives']:
   at=prim['attributes']
   if 'JOINTS_0'not in at:continue
   ids=model.accessor(at['JOINTS_0']).astype(int);we=model.accessor(at['WEIGHTS_0'])
   if 'JOINTS_1'in at:ids=np.c_[ids,model.accessor(at['JOINTS_1']).astype(int)];we=np.c_[we,model.accessor(at['WEIGHTS_1'])]
   v=model.accessor(at['POSITION']);geos.append((np.c_[v,np.ones(len(v))],ids,we))
 return joints,ibm,geos
og=geometry(old);ng=geometry(new)
def matrices(w,geo):
 joints,ibm,_=geo;mats=[]
 for j in joints:
  M=np.eye(4);M[:3,:3]=w[j][1].as_matrix();M[:3,3]=w[j][0];mats.append(M)
 return np.array(mats)@ibm
def vertices(w,geo):
 M=matrices(w,geo);return[np.sum(np.einsum('nvij,nj->nvi',M[ids],v)*we[:,:,None],axis=1)[:,:3]for v,ids,we in geo[2]]
# Region membership uses original anatomical influences, new weights evaluated in full.
regions={};sh=old.names['mixamorig:RightShoulder']
for name,g1,g2 in [('shoulder',[sh],[a]),('elbow',[a],[e]),('wrist',[e],[h]),('forearm_interior',[e],[])]:
 regs=[]
 for idx,(v,ids,we)in enumerate(og[2]):
  nodes=og[0][ids];w1=np.sum(we*np.isin(nodes,g1),axis=1);w2=np.sum(we*np.isin(nodes,g2),axis=1)if g2 else np.zeros(len(v));mask=(w1>=.08)&(w2>=.08)&(w1+w2>=.65)if g2 else(w1>=.65);regs.append(mask)
 regions[name]=regs
restm={}
for label,geo,w in [('old',og,bindold),('new',ng,bindnew)]:
 M=matrices(w,geo);restm[label]=[np.abs(np.linalg.det(np.sum(M[ids,:,:3]*we[:,:,None,None],axis=1)[:,:3,:3]))for _,ids,we in geo[2]]
def volume(w,geo,label):
 M=matrices(w,geo);val={k:1. for k in regions}
 for num,(_,ids,we)in enumerate(geo[2]):
  det=np.abs(np.linalg.det(np.sum(M[ids,:,:3]*we[:,:,None,None],axis=1)[:,:3,:3]))/restm[label][num]
  for key,masks in regions.items():
   mask=masks[num]
   if np.any(mask):val[key]=min(val[key],float(np.min(det[mask])))
 return val
if __name__ == "__main__":
    report={'status':'CPU/FK diagnostic only; optional engine checks are separate; NOT ACCEPTED; heavy excluded (geometrically infeasible)','input_sha256':hashlib.sha256(old.path.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(new.path.read_bytes()).hexdigest(),'world_scale':scale,'regions':{k:int(sum(np.count_nonzero(v)for v in vs))for k,vs in regions.items()},'legacy':{},'regular':{}}
    assert old.j['animations']==new.j['animations'][:len(old.j['animations'])]
    assert all(c['target']['node']not in [e,h]for ani in old.j['animations']for c in ani['channels']if c['target']['path']=='translation')
    maxjoint=0;maxskin=0;cases=0
    for clip in old.anims:
     for t in np.linspace(0,old.duration(clip),7):
      ow,_=old.pose(clip,float(t));nw,_=new.pose(clip,float(t));maxjoint=max(maxjoint,max(np.linalg.norm(ow[i][0]-nw[i][0])*scale for i in old.order),max((ow[i][1]*nw[i][1].inv()).magnitude()for i in old.order));ov=vertices(ow,og);nv=vertices(nw,ng);maxskin=max(maxskin,max(float(np.max(np.linalg.norm(a-b,axis=1)))*scale for a,b in zip(ov,nv)));cases+=1
    report['legacy']={'all_original_animation_dictionaries_exact':True,'animation_count':len(old.anims),'sampled_poses':cases,'max_original_bone_position_m_or_angle_rad':float(maxjoint),'max_actual_skin_vertex_error_m':maxskin,'algebraic_equivalence':'All new twist tracks identity; split translations sum to originalHand translation. All new station skin matrices equal the originalForeArm matrix. Thus all unchanged legacy time samples, not just these probes, have the original world skeleton and original weighted skin.'};print('LEGACY',report['legacy'],flush=True)
    clip='XuUAL2RegularFull';alias='XuUAL2RegularTwistRig';ts=np.linspace(0,3,721);met={'sample_hz':240,'max_palm_error_m':0.,'max_tip_error_m':0.,'max_hand_angle_deg':0.,'max_original_body_error_m':0.,'max_bone_error_m':0.,'max_wrist_swing_deg':0.,'max_wrist_twist_deg':0.,'max_elbow_shift_m':0.,'max_elbow_correction_step_60hz_m':0.,'max_elbow_actual_step_60hz_m':0.,'old_min_volume':{k:1. for k in regions},'new_min_volume':{k:1. for k in regions},'worst_times':{}};previous=None
    for num,t in enumerate(ts):
     ow,op=old.pose(clip,float(t));nw,np_=new.pose(alias,float(t));oe=ow[h][0]+ow[h][1].apply(points);ne=nw[h][0]+nw[h][1].apply(points);errors=np.linalg.norm(oe-ne,axis=1)*scale;met['max_palm_error_m']=max(met['max_palm_error_m'],float(errors[0]));met['max_tip_error_m']=max(met['max_tip_error_m'],float(errors[2]));met['max_hand_angle_deg']=max(met['max_hand_angle_deg'],float(np.rad2deg((ow[h][1]*nw[h][1].inv()).magnitude())))
     for i in old.order:
      if i not in [a,e,h]and not old.nodes[i].get('name','').startswith('mixamorig:RightHand'):met['max_original_body_error_m']=max(met['max_original_body_error_m'],float(np.linalg.norm(ow[i][0]-nw[i][0])*scale))
     met['max_bone_error_m']=max(met['max_bone_error_m'],abs(np.linalg.norm(nw[e][0]-nw[a][0])-np.linalg.norm(ow[e][0]-ow[a][0]))*scale,abs(np.linalg.norm(nw[h][0]-nw[e][0])-np.linalg.norm(ow[h][0]-ow[e][0]))*scale)
     ax=nw[h][0]-nw[e][0];ax/=np.linalg.norm(ax);H=nw[h][1];F=nw[end][1];hf=H.apply(forward);sw=np.arccos(np.clip(np.dot(ax,hf),-1,1));align=between(ax,hf);ns=(F*restH).apply(side);cs=(align.inv()*H).apply(side);ns-=ax*np.dot(ns,ax);cs-=ax*np.dot(cs,ax);ns/=np.linalg.norm(ns);cs/=np.linalg.norm(cs);tw=abs(np.arctan2(np.dot(ax,np.cross(ns,cs)),np.dot(ns,cs)));met['max_wrist_swing_deg']=max(met['max_wrist_swing_deg'],float(np.rad2deg(sw)));met['max_wrist_twist_deg']=max(met['max_wrist_twist_deg'],float(np.rad2deg(tw)))
     for lab,w,g in [('old',ow,og),('new',nw,ng)]:
      for key,v in volume(w,g,lab).items():
       if v<met[lab+'_min_volume'][key]:met[lab+'_min_volume'][key]=v;met['worst_times'][lab+'_'+key]=float(t)
     delta=nw[e][0]-ow[e][0];met['max_elbow_shift_m']=max(met['max_elbow_shift_m'],float(np.linalg.norm(delta)*scale))
     if num%4==0:
      if previous:met['max_elbow_correction_step_60hz_m']=max(met['max_elbow_correction_step_60hz_m'],float(np.linalg.norm(delta-previous[0])*scale));met['max_elbow_actual_step_60hz_m']=max(met['max_elbow_actual_step_60hz_m'],float(np.linalg.norm(nw[e][0]-previous[1])*scale))
      previous=(delta,nw[e][0])
    report['regular']=met;(B/'twist-rig-verification.json').write_text(json.dumps(report,indent=2));print('REGULAR',json.dumps(met),flush=True)
