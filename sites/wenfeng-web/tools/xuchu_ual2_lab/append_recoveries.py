from lab_context import OUTPUT, TOOLS, SOURCE, TARGET, MANIFEST
"""Optional isolated A/B recovery aliases, with ONE Regular-family calibration.
No controller/chain decisions. Never fit a new Foot reference or Y per clip.
"""
from pathlib import Path
from copy import deepcopy
import sys,json,hashlib,argparse
import numpy as np
from scipy.spatial.transform import Rotation as R
from scipy.optimize import lsq_linear
from scipy.sparse import eye,diags,vstack
sys.path.insert(0,str(TOOLS))
from prepare_polearms import Sampler,library_mapping,between
from gltf_tools import write_glb
from continuous_elbow import solve
p=argparse.ArgumentParser();p.add_argument('--recoveries',default='A,B');args=p.parse_args();selected=args.recoveries.split(',');assert all(c in ['A','B']for c in selected)
B=OUTPUT;basepath=B/'xuchu-ual2-twist-rig-compatible.glb';base=Sampler(basepath);cal=Sampler(B/'xuchu-ual2-full-body-prototype.glb');src=Sampler(SOURCE);out=deepcopy(base.j);blob=bytearray(base.bin);bind,rest=cal.pose();ref,_=src.pose('A_TPose');idle,_=cal.pose('Idle',0);footref,_=src.pose('Sword_Regular_Combo',0);hips=cal.names['mixamorig:Hips'];srcHip=src.names['pelvis'];ratio=bind[hips][0][1]/ref[srcHip][0][1];offset=json.loads((B/'xuchu-prototype.json').read_text())['clips']['XuUAL2RegularFull']['constant_body_y'];helpers=[base.names['mixamorig:RightForeArmTwist'+str(i)]for i in [1,2,3]];a,e,h=[base.names['mixamorig:Right'+s]for s in ['Arm','ForeArm','Hand']];parent=base.parents[a]
pairs={cal.names[a]:src.names[b]for a,b in library_mapping('ual2').items()if a in cal.names and b in src.names}
for side,suffix in [('Left','l'),('Right','r')]:
 for digit in ['Thumb','Index','Middle','Ring','Pinky']:
  for k in range(1,5):
   an=f'mixamorig:{side}Hand{digit}{k}';bn=digit.lower()+f'_{k:02d}'+('_leaf'if k==4 else'')+'_'+suffix
   if an in cal.names and bn in src.names:pairs[cal.names[an]]=src.names[bn]
correction={a:ref[b][1].inv()*bind[a][1]for a,b in pairs.items()}
for side,suffix in [('Left','l'),('Right','r')]:
 for part,bone in [('Foot','foot'),('ToeBase','ball'),('Toe_End','ball_leaf')]:
  i=cal.names.get('mixamorig:'+side+part);j=src.names.get(bone+'_'+suffix)
  if i is not None and j is not None:correction[i]=footref[j][1].inv()*idle[i][1]
def append(vals,kind):
 ar=np.asarray(vals,dtype='<f4');blob.extend(b'\0'*(-len(blob)%4));v=len(out['bufferViews']);out['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':ar.nbytes});blob.extend(ar.tobytes());ac={'bufferView':v,'componentType':5126,'count':len(ar),'type':kind}
 if kind=='SCALAR':ac['min']=ar.min(axis=0).tolist();ac['max']=ar.max(axis=0).tolist()
 out['accessors'].append(ac);return len(out['accessors'])-1

def raw_pose(clip,t):
 sw,_=src.pose(clip,float(t));desired={i:sw[j][1]*correction[i]for i,j in pairs.items()};p={};wr={}
 for i in cal.order:
  par=cal.parents.get(i);pr=wr[par]if par is not None else R.identity();r=desired.get(i,pr*R.from_quat(rest[i][1]));p[i]=[rest[i][0].copy(),(pr.inv()*r).as_quat()];wr[i]=r
 p[hips][0]+=(sw[srcHip][0]-ref[srcHip][0])*ratio;p[hips][0][1]+=offset
 return p
# Reproduce established family Full at its original keys before appending Rec.
max_repro=0.
for t in np.linspace(0,3,91):
 pred=cal.world(raw_pose('Sword_Regular_Combo',t));actual=cal.pose('XuUAL2RegularFull',t)[0];max_repro=max(max_repro,max(np.linalg.norm(pred[i][0]-actual[i][0])for i in cal.order))
report={'status':'TMP RECOVERY OPTIONS / NOT CONTROLLER INTEGRATED / NOT VISUAL ACCEPTED','base_sha256':hashlib.sha256(basepath.read_bytes()).hexdigest(),'source_file':str(src.path),'family_calibration':{'foot_reference':'Sword_Regular_Combo t0 -> original target Idle t0, fixed per bone, shared all family clips','hip_scale_ratio':ratio,'constant_body_y_rig':offset,'root_reference':'source A_TPose pelvis -> frozen target bind hips, source full XYZ displacement retained','per_clip_foot_or_height_fit':False,'full_key_reproduction_error_rig':max_repro},'clips':{}}
raw_aliases=[]
for letter in selected:
 clip='Sword_Regular_'+letter+'_Rec';alias='XuUAL2Regular'+letter+'RecoveryRaw';dur=src.duration(clip);ts=np.linspace(0,dur,round(dur*30)+1);rots={i:[]for i in pairs};trans=[]
 for t in ts:
  pp=raw_pose(clip,t);trans.append(pp[hips][0])
  for i in rots:
   q=pp[i][1]
   if rots[i]and np.dot(q,rots[i][-1])<0:q=-q
   rots[i].append(q)
 ani={'name':alias,'samplers':[],'channels':[]};ta=append(ts[:,None],'SCALAR')
 for i,vals in rots.items():ani['samplers'].append({'input':ta,'output':append(vals,'VEC4'),'interpolation':'LINEAR'});ani['channels'].append({'sampler':len(ani['samplers'])-1,'target':{'node':i,'path':'rotation'}})
 ani['samplers'].append({'input':ta,'output':append(trans,'VEC3'),'interpolation':'LINEAR'});ani['channels'].append({'sampler':len(ani['samplers'])-1,'target':{'node':hips,'path':'translation'}})
 for i in helpers:ani['samplers'].append({'input':ta,'output':append([[0,0,0,1]]*len(ts),'VEC4'),'interpolation':'LINEAR'});ani['channels'].append({'sampler':len(ani['samplers'])-1,'target':{'node':i,'path':'rotation'}})
 out['animations'].append(ani);raw_aliases.append(alias);report['clips'][alias]={'source':clip,'duration':dur,'body_rate_hz':30,'shared_family_calibration':True}
rawpath=B/'xuchu-ual2-family-recoveries-raw.glb';write_glb(rawpath,out,blob);raw=Sampler(rawpath);restH=R.from_quat(cal.nodes[h]['rotation']);direction=np.array(cal.nodes[h]['translation']);axislocal=direction/np.linalg.norm(direction);forward=restH.inv().apply(axislocal);side=np.array([1.,0,0])if abs(forward[0])<.8 else np.array([0.,1,0]);side-=forward*np.dot(side,forward);side/=np.linalg.norm(side)
def wrist(F,H,ax):
 hf=H.apply(forward);sw=np.arccos(np.clip(np.dot(ax,hf),-1,1));al=between(ax,hf);ns=(F*restH).apply(side);cs=(al.inv()*H).apply(side);ns-=ax*np.dot(ns,ax);cs-=ax*np.dot(cs,ax);ns/=np.linalg.norm(ns);cs/=np.linalg.norm(cs);return sw,np.arctan2(np.dot(ax,np.cross(ns,cs)),np.dot(ns,cs))
for ralias in raw_aliases:
 dur=raw.duration(ralias);ts=np.linspace(0,dur,round(dur*120)+1);frames=[];circles=[];impossible=[];rawsw=[];rawtw=[]
 for t in ts:
  w,p=raw.pose(ralias,float(t));Sh,El,Wr=[w[i][0]for i in[a,e,h]];l1=np.linalg.norm(El-Sh);l2=np.linalg.norm(Wr-El);d=np.linalg.norm(Wr-Sh);n=(Wr-Sh)/d;b=(l1*l1-l2*l2+d*d)/(2*d);C=Sh+b*n;r=np.sqrt(max(0,l1*l1-b*b));u=(El-C)/max(r,1e-12);v=np.cross(n,u);f=w[h][1].apply(forward);A=np.dot((Wr-C)/l2,f);BB=-r/l2*np.dot(u,f);DD=-r/l2*np.dot(v,f);minimum=np.arccos(np.clip(A+np.hypot(BB,DD),-1,1));circles.append((C,r,u,v,El,Wr,l2,f));frames.append((w,p,Sh,El,Wr));sw,tw=wrist(w[e][1],w[h][1],(Wr-El)/l2);rawsw.append(sw);rawtw.append(abs(tw))
  if minimum>np.deg2rad(40):impossible.append({'time':float(t),'minimum_swing_deg':float(np.rad2deg(minimum))})
 report['clips'][ralias].update({'raw_wrist_swing_max_deg':float(np.rad2deg(max(rawsw))),'raw_wrist_twist_max_deg':float(np.rad2deg(max(rawtw))),'infeasible_exact_palm_40deg_frames':impossible})
 if impossible:print('REC_INFEASIBLE',ralias,len(impossible),max(x['minimum_swing_deg']for x in impossible),flush=True);continue
 theta,sol=solve(circles,np.deg2rad(38.8));inter=[];twists=[]
 for angle,fr,circle in zip(theta,frames,circles):
  w,p,Sh,El,Wr=fr;C,r,u,v,*_=circle;En=C+r*(u*np.cos(angle)+v*np.sin(angle));oldax=(Wr-El)/np.linalg.norm(Wr-El);ax=(Wr-En)/np.linalg.norm(Wr-En);F=between(oldax,ax)*w[e][1];U=between(El-Sh,En-Sh)*w[a][1];sw,tw=wrist(F,w[h][1],ax);inter.append((w,p,ax,F,U,En));twists.append(tw)
 twists=np.unwrap(twists);n=len(twists);A=vstack([eye(n),diags([-np.ones(n-1),np.ones(n-1)],[0,1],shape=(n-1,n)),2*diags([np.ones(n-2),-2*np.ones(n-2),np.ones(n-2)],[0,1,2],shape=(n-2,n))]).tocsr();phi=lsq_linear(A,np.zeros(A.shape[0]),bounds=(twists-np.deg2rad(32),twists+np.deg2rad(32)),tol=1e-10,lsmr_tol=1e-10).x;qs={i:[]for i in[a,e,h]+helpers};trace=[]
 for t,angle,ph,fr in zip(ts,theta,phi,inter):
  w,p,ax,F,U,En=fr;Fend=R.from_rotvec(ax*ph)*F;rot={a:w[parent][1].inv()*U,e:U.inv()*F,h:Fend.inv()*w[h][1]};rot.update({i:R.from_rotvec(axislocal*ph/3)for i in helpers})
  for i in qs:
   q=rot[i].as_quat()
   if qs[i]and np.dot(q,qs[i][-1])<0:q=-q
   qs[i].append(q)
  trace.append({'time':float(t),'elbow_correction_rig':(En-w[e][0]).tolist(),'total_forearm_roll_deg':float(np.rad2deg(ph))})
 alias=ralias.replace('Raw','TwistRig');ani=deepcopy(raw.anims[ralias]);ani['name']=alias;ta=append(ts[:,None],'SCALAR')
 for c in ani['channels']:
  i=c['target']['node']
  if c['target']['path']=='rotation'and i in qs:ani['samplers'][c['sampler']]={'input':ta,'output':append(qs[i],'VEC4'),'interpolation':'LINEAR'}
 out['animations'].append(ani);report['clips'][alias]={'raw_alias':ralias,'duration':dur,'shared_family_calibration':True,'right_arm_rate_hz':120,'solver':sol,'trace':trace};print('REC_TWIST',alias,dur,sol,flush=True)
assert out['animations'][:len(base.j['animations'])]==base.j['animations'];assert blob[:len(base.bin)]==base.bin
path=B/'xuchu-ual2-family-recoveries.glb';write_glb(path,out,blob);report['output']=str(path);report['sha256']=hashlib.sha256(path.read_bytes()).hexdigest();(B/'family-recoveries.json').write_text(json.dumps(report,indent=2));print(report['sha256'],'sharedY',offset,'repro',max_repro,flush=True)
