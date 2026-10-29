from pathlib import Path
from copy import deepcopy
import sys,json,hashlib
sys.dont_write_bytecode=True
import numpy as np
from scipy.spatial.transform import Rotation as R
import argparse
TOOLS=Path(__file__).resolve().parents[1]
WEB=TOOLS.parent
sys.path.insert(0,str(TOOLS))
parser=argparse.ArgumentParser(description="Private exact raw UAL1 bake; use prepare.py for checked inputs and new output directories.")
parser.add_argument("--source",type=Path,required=True)
parser.add_argument("--baseline",type=Path,required=True)
parser.add_argument("--output-dir",type=Path,required=True)
args=parser.parse_args();B=args.output_dir.resolve()
if B.is_relative_to(WEB.parents[1]):parser.error("Output must be outside the repository")
if any((B/n).exists() for n in ["xuchu-ual1-sword-raw.glb","raw-metadata.json"]):parser.error("Never overwrite outputs")
from prepare_polearms import Sampler,library_mapping
from gltf_tools import write_glb
source=Sampler(args.source.resolve());target=Sampler(args.baseline.resolve());assert hashlib.sha256(source.path.read_bytes()).hexdigest()=='69591853d817488edaa8fd9bf8fc1d821eaeaf789f8627b3cd23b41c4ed67997';assert hashlib.sha256(target.path.read_bytes()).hexdigest()=='89f369ccbfce8b5ecd4735ed5f4a18467d23ca4dfc9ec684f51b9c7c30dad43c'
bind,rest=target.pose();ref,_=source.pose('A_TPose');idle,_=target.pose('Idle',0);footref,_=source.pose('Sword_Idle',0);pairs={target.names[a]:source.names[b]for a,b in library_mapping('ual2').items()if a in target.names and b in source.names}
for side,suffix in [('Left','l'),('Right','r')]:
 for digit in ['Thumb','Index','Middle','Ring','Pinky']:
  for k in range(1,5):
   a=f'mixamorig:{side}Hand{digit}{k}';b=digit.lower()+f'_{k:02d}'+('_leaf'if k==4 else'')+'_'+suffix
   if a in target.names and b in source.names:pairs[target.names[a]]=source.names[b]
correction={a:ref[b][1].inv()*bind[a][1]for a,b in pairs.items()}
for side,suffix in [('Left','l'),('Right','r')]:
 for part,bone in [('Foot','foot'),('ToeBase','ball'),('Toe_End','ball_leaf')]:
  a=target.names.get('mixamorig:'+side+part);b=source.names.get(bone+'_'+suffix)
  if a is not None and b is not None:correction[a]=footref[b][1].inv()*idle[a][1]
hips=target.names['mixamorig:Hips'];sourcehip=source.names['pelvis'];ratio=bind[hips][0][1]/ref[sourcehip][0][1]
skin=target.j['skins'][0];joints=skin['joints'];ibm=target.accessor(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1);footids=[k for k,j in enumerate(joints)if any(a in target.nodes[j].get('name','')for a in ['Foot','Toe'])];geometry=[]
for mesh in target.j['meshes']:
 for prim in mesh['primitives']:
  at=prim['attributes'];v=target.accessor(at['POSITION']);ji=target.accessor(at['JOINTS_0']).astype(int);we=target.accessor(at['WEIGHTS_0']);mask=np.sum(we*np.isin(ji,footids),axis=1)>.35
  if np.any(mask):geometry.append((np.c_[v[mask],np.ones(mask.sum())],ji[mask],we[mask]))
def sole(w):
 mats=[]
 for j in joints:
  M=np.eye(4);M[:3,:3]=w[j][1].as_matrix();M[:3,3]=w[j][0];mats.append(M)
 M=np.array(mats)@ibm
 return min(float(np.min(np.sum(np.einsum('nvij,nj->nvi',M[ji],v)*we[:,:,None],axis=1)[:,1]))for v,ji,we in geometry)
def pose(clip,t):
 w,_=source.pose(clip,float(t));desired={a:w[b][1]*correction[a]for a,b in pairs.items()};p={};globalr={}
 for a in target.order:
  parent=target.parents.get(a);pr=globalr[parent]if parent is not None else R.identity();wr=desired.get(a,pr*R.from_quat(rest[a][1]));p[a]=[rest[a][0].copy(),(pr.inv()*wr).as_quat()];globalr[a]=wr
 p[hips][0]+=(w[sourcehip][0]-ref[sourcehip][0])*ratio
 return p
family_y=sole(idle)-sole(target.world(pose('Sword_Idle',0)));out=deepcopy(target.j);blob=bytearray(target.bin)
def append(a,kind):
 a=np.asarray(a,dtype='<f4');blob.extend(b'\0'*(-len(blob)%4));view=len(out['bufferViews']);out['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':a.nbytes});blob.extend(a.tobytes());acc={'bufferView':view,'componentType':5126,'count':len(a),'type':kind}
 if kind=='SCALAR':acc['min']=a.min(axis=0).tolist();acc['max']=a.max(axis=0).tolist()
 out['accessors'].append(acc);return len(out['accessors'])-1
report={'status':'TMP RAW RETARGET ONLY / NOT ACCEPTED / NO RUNTIME INTEGRATION','source_file':str(source.path),'source_sha256':hashlib.sha256(source.path.read_bytes()).hexdigest(),'source_license':'Official UAL1 Standard CC0; original snapshots in repository source-assets/animations/ual1','target_baseline_sha256':hashlib.sha256(target.path.read_bytes()).hexdigest(),'method':'Full source body/world rotations and fingers; full scaled Hips XYZ. No IK, no wrist edits, no limb/foot/pelvis clamps, no ready blending, no timewarp. One fixed Foot/Toe calibration from source Sword_Idle0 to target original Idle0. One shared bodyY from that same static calibration frame, never per-clip/per-frame.','hip_scale_ratio':ratio,'family_constant_body_y_rig':family_y,'clips':{}}
for alias,clip in [('XuUAL1SwordAttackRaw','Sword_Attack'),('XuUAL1SwordIdleRaw','Sword_Idle')]:
 dur=source.duration(clip);ts=np.linspace(0,dur,round(dur*120)+1);rots={i:[]for i in pairs};trans=[]
 for t in ts:
  p=pose(clip,t);p[hips][0][1]+=family_y;trans.append(p[hips][0])
  for i in rots:
   q=p[i][1]
   if rots[i]and np.dot(q,rots[i][-1])<0:q=-q
   rots[i].append(q)
 ani={'name':alias,'samplers':[],'channels':[]};ta=append(ts[:,None],'SCALAR')
 for i,v in rots.items():ani['samplers'].append({'input':ta,'output':append(v,'VEC4'),'interpolation':'LINEAR'});ani['channels'].append({'sampler':len(ani['samplers'])-1,'target':{'node':i,'path':'rotation'}})
 ani['samplers'].append({'input':ta,'output':append(trans,'VEC3'),'interpolation':'LINEAR'});ani['channels'].append({'sampler':len(ani['samplers'])-1,'target':{'node':hips,'path':'translation'}});out['animations'].append(ani);report['clips'][alias]={'source':clip,'duration':dur,'frames':len(ts),'shared_y':family_y,'shared_footref':'Sword_Idle0'}
assert out['animations'][:len(target.j['animations'])]==target.j['animations'];assert blob[:len(target.bin)]==target.bin
path=B/'xuchu-ual1-sword-raw.glb';write_glb(path,out,blob);report['output']=str(path);report['sha256']=hashlib.sha256(path.read_bytes()).hexdigest();(B/'raw-metadata.json').write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True)
