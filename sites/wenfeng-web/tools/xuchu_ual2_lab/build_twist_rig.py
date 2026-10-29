from lab_context import OUTPUT, TOOLS, SOURCE, TARGET, MANIFEST
"""Temporary, isolated forearm twist rig. No canonical/runtime file writes."""
from pathlib import Path
from copy import deepcopy
import sys,json,hashlib
import numpy as np
from scipy.spatial.transform import Rotation as R
sys.path.insert(0,str(TOOLS))
from prepare_polearms import Sampler,between
from gltf_tools import write_glb
from continuous_elbow import solve
B=OUTPUT;m=Sampler(B/'xuchu-ual2-full-body-prototype.glb');out=deepcopy(m.j);blob=bytearray(m.bin);a,e,h=[m.names['mixamorig:Right'+s]for s in ['Arm','ForeArm','Hand']];par=m.parents[a];wrest,prest=m.pose();direction=np.array(m.nodes[h]['translation']);axislocal=direction/np.linalg.norm(direction);restH=R.from_quat(m.nodes[h]['rotation']);forward=restH.inv().apply(axislocal);side=np.array([1.,0,0])if abs(forward[0])<.8 else np.array([0.,1,0]);side-=forward*np.dot(side,forward);side/=np.linalg.norm(side)
ids=[]
for k in range(3):
 i=len(out['nodes']);ids.append(i);out['nodes'].append({'name':f'mixamorig:RightForeArmTwist{k+1}','translation':(direction/3).tolist(),'rotation':[0,0,0,1],'children':[]})
out['nodes'][e]['children']=[ids[0]if c==h else c for c in out['nodes'][e]['children']]
for i,nxt in zip(ids,ids[1:]+[h]):out['nodes'][i]['children']=[nxt]
out['nodes'][h]['translation']=[0,0,0]
def append(vals,kind,component=5126):
 ar=np.asarray(vals,dtype='<f4'if component==5126 else'<u2');blob.extend(b'\0'*(-len(blob)%4));v=len(out['bufferViews']);out['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':ar.nbytes});blob.extend(ar.tobytes());ac={'bufferView':v,'componentType':component,'count':len(ar),'type':kind}
 if kind=='SCALAR':ac['min']=ar.min(axis=0).tolist();ac['max']=ar.max(axis=0).tolist()
 out['accessors'].append(ac);return len(out['accessors'])-1
skin=out['skins'][0];oldj=skin['joints'].copy();oldibm=m.accessor(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1);findex=oldj.index(e);newibm=list(oldibm)
for k,i in enumerate(ids):
 mat=np.eye(4);mat[:3,:3]=wrest[e][1].as_matrix();mat[:3,3]=wrest[e][0]+wrest[e][1].apply(direction*(k+1)/3);newibm.append(np.linalg.inv(mat))
skin['joints']=oldj+ids;skin['inverseBindMatrices']=append(np.array(newibm).transpose(0,2,1).reshape(-1,16),'MAT4');newjointids=[findex]+list(range(len(oldj),len(oldj)+3));S=wrest[e][0];W=wrest[h][0];axis=(W-S)/np.linalg.norm(W-S);length=np.linalg.norm(W-S);vertices_changed=0
for mesh_idx,mesh in enumerate(out['meshes']):
 for pidx,prim in enumerate(mesh['primitives']):
  attrs=prim['attributes']
  if 'JOINTS_0'not in attrs:continue
  oldprim=m.j['meshes'][mesh_idx]['primitives'][pidx]['attributes'];ji=m.accessor(oldprim['JOINTS_0']).astype(int);we=m.accessor(oldprim['WEIGHTS_0']);verts=m.accessor(oldprim['POSITION']);nj=[];nw=[]
  for v,j,w in zip(verts,ji,we):
   pairs=[]
   for joint,weight in zip(j,w):
    if weight<=0:continue
    if joint!=findex:pairs.append((joint,weight));continue
    q=np.clip(np.dot(v-S,axis)/length,0,1)*3;k=min(int(q),2);alpha=q-k;pairs.extend([(newjointids[k],weight*(1-alpha)),(newjointids[k+1],weight*alpha)]);vertices_changed+=1
   merged={}
   for joint,weight in pairs:merged[joint]=merged.get(joint,0)+weight
   pairs=sorted(merged.items(),key=lambda p:-p[1]);assert len(pairs)<=8;pairs+= [(0,0)]*(8-len(pairs));nj.append([x[0]for x in pairs]);nw.append([x[1]for x in pairs])
  nj=np.array(nj);nw=np.array(nw);attrs['JOINTS_0']=append(nj[:,:4],'VEC4',5123);attrs['WEIGHTS_0']=append(nw[:,:4],'VEC4');attrs['JOINTS_1']=append(nj[:,4:],'VEC4',5123);attrs['WEIGHTS_1']=append(nw[:,4:],'VEC4')
restpath=B/'xuchu-ual2-twist-rig-rest.glb';write_glb(restpath,out,blob);rig=Sampler(restpath)
# Unchanged legacy aliases and keys stay in place. Add one experimental clip.
clip='XuUAL2RegularFull';alias='XuUAL2RegularTwistRig';dur=m.duration(clip);ts=np.linspace(0,dur,361);frames=[];circles=[]
for t in ts:
 w,p=m.pose(clip,float(t));Sh,El,Wr=[w[i][0]for i in [a,e,h]];l1=np.linalg.norm(El-Sh);l2=np.linalg.norm(Wr-El);d=np.linalg.norm(Wr-Sh);n=(Wr-Sh)/d;b=(l1*l1-l2*l2+d*d)/(2*d);C=Sh+b*n;r=np.sqrt(max(0,l1*l1-b*b));u=(El-C)/max(r,1e-12);v=np.cross(n,u);f=w[h][1].apply(forward);circles.append((C,r,u,v,El,Wr,l2,f));frames.append((w,p,Sh,El,Wr))
theta,solver=solve(circles,np.deg2rad(38.8));inter=[];roll=[]
def measure(F,H,ax):
 hf=H.apply(forward);sw=np.arccos(np.clip(np.dot(ax,hf),-1,1));align=between(ax,hf);ns=(F*restH).apply(side);cs=(align.inv()*H).apply(side);ns-=ax*np.dot(ns,ax);cs-=ax*np.dot(cs,ax);ns/=np.linalg.norm(ns);cs/=np.linalg.norm(cs);return sw,np.arctan2(np.dot(ax,np.cross(ns,cs)),np.dot(ns,cs))
for t,angle,fr,circle in zip(ts,theta,frames,circles):
 w,p,Sh,El,Wr=fr;C,r,u,v,*_=circle;En=C+r*(u*np.cos(angle)+v*np.sin(angle));oldax=(Wr-El)/np.linalg.norm(Wr-El);ax=(Wr-En)/np.linalg.norm(Wr-En);F=between(oldax,ax)*w[e][1];U=between(El-Sh,En-Sh)*w[a][1];sw,tw=measure(F,w[h][1],ax);roll.append(tw);inter.append((w,p,ax,F,U,En))
# Continuous minimal forearm pronation; leave the wrist's natural 32deg range.
from scipy.optimize import lsq_linear
from scipy.sparse import eye,diags,vstack
roll=np.unwrap(roll);lo=roll-np.deg2rad(32);hi=roll+np.deg2rad(32);n=len(roll);A=vstack([eye(n),diags([-np.ones(n-1),np.ones(n-1)],[0,1],shape=(n-1,n)),2*diags([np.ones(n-2),-2*np.ones(n-2),np.ones(n-2)],[0,1,2],shape=(n-2,n))]).tocsr();phi=lsq_linear(A,np.zeros(A.shape[0]),bounds=(lo,hi),tol=1e-10,lsmr_tol=1e-10).x
qs={i:[]for i in[a,e,h]+ids};trace=[]
for t,ang,ph,fr in zip(ts,theta,phi,inter):
 w,p,ax,F,U,En=fr;H=w[h][1];Fend=R.from_rotvec(ax*ph)*F;rot={a:(w[par][1].inv()*U),e:U.inv()*F,h:Fend.inv()*H};rot.update({i:R.from_rotvec(axislocal*ph/3)for i in ids})
 for i in qs:
  q=rot[i].as_quat()
  if qs[i]and np.dot(q,qs[i][-1])<0:q=-q
  qs[i].append(q)
 trace.append({'time':float(t),'elbow_angle_deg':float(np.rad2deg(ang)),'total_forearm_roll_deg':float(np.rad2deg(ph)),'elbow_correction':(En-w[e][0]).tolist()})
ani=deepcopy(m.anims[clip]);ani['name']=alias;ta=append(ts[:,None],'SCALAR')
for c in ani['channels']:
 i=c['target']['node']
 if c['target']['path']=='rotation'and i in qs:ani['samplers'][c['sampler']]={'input':ta,'output':append(qs[i],'VEC4'),'interpolation':'LINEAR'}
for i in ids:ani['samplers'].append({'input':ta,'output':append(qs[i],'VEC4'),'interpolation':'LINEAR'});ani['channels'].append({'sampler':len(ani['samplers'])-1,'target':{'node':i,'path':'rotation'}})
out['animations'].append(ani);path=B/'xuchu-ual2-twist-rig-experiment.glb';write_glb(path,out,blob)
report={'status':'TMP RIG EXPERIMENT / NOT ACCEPTED','input_sha256':hashlib.sha256(m.path.read_bytes()).hexdigest(),'output':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'legacy_animation_count':len(m.j['animations']),'added_alias':alias,'twist_joint_node_indices':ids,'skin_weight_method':'Original forearm influence split linearly by rest-mesh axial coordinate over elbow/1-3/2-3/wrist stations. 8-influence glTF attributes avoid discarding old influences. At identity all stations have the original forearm skin matrix.','vertices_with_forearm_influence':vertices_changed,'source_timing_body_left_unchanged':True,'solver':solver,'trace':trace};(B/'twist-rig-experiment.json').write_text(json.dumps(report,indent=2));print(path,report['sha256'],solver,flush=True)
