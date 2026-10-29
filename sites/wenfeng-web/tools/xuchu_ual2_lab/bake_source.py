from lab_context import OUTPUT, TOOLS, SOURCE, TARGET, MANIFEST
from pathlib import Path
from copy import deepcopy
import sys,json,hashlib
import numpy as np
from scipy.spatial.transform import Rotation as R
sys.path.insert(0,str(TOOLS))
from prepare_polearms import Sampler,library_mapping
from gltf_tools import write_glb
BASE=OUTPUT
source=Sampler(SOURCE)
target_path=TARGET;target=Sampler(target_path)
(BASE/'xuchu-base-frozen.glb').write_bytes(target_path.read_bytes())
bind,rest=target.pose();ref,_=source.pose('A_TPose');idle,_=target.pose('Idle',0);foot_ref,_=source.pose('Sword_Regular_Combo',0)
pairs={target.names[a]:source.names[b]for a,b in library_mapping('ual2').items()if a in target.names and b in source.names}
# Carry actual authored finger trajectories on BOTH hands. Only right is the
# wielding hand; left remains the independent authored balance/defense hand.
for side,suffix in [('Left','l'),('Right','r')]:
 for digit in ['Thumb','Index','Middle','Ring','Pinky']:
  for k in range(1,5):
   a=f'mixamorig:{side}Hand{digit}{k}';b=digit.lower()+f'_{k:02d}'+('_leaf'if k==4 else'')+'_'+suffix
   if a in target.names and b in source.names:pairs[target.names[a]]=source.names[b]
correction={a:ref[b][1].inv()*bind[a][1]for a,b in pairs.items()}
for side,suffix in [('Left','l'),('Right','r')]:
 for part,bone in [('Foot','foot'),('ToeBase','ball'),('Toe_End','ball_leaf')]:
  a=target.names.get('mixamorig:'+side+part);b=source.names.get(bone+'_'+suffix)
  if a is not None and b is not None:correction[a]=foot_ref[b][1].inv()*idle[a][1]
hips=target.names['mixamorig:Hips'];sourcehip=source.names['pelvis'];ratio=bind[hips][0][1]/ref[sourcehip][0][1]
skin=target.j['skins'][0];joints=skin['joints'];ibm=target.accessor(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
foot_joint_ids=[k for k,j in enumerate(joints)if any(a in target.nodes[j].get('name','')for a in ['Foot','Toe'])]
geometry=[]
for mesh in target.j['meshes']:
 for prim in mesh['primitives']:
  attrs=prim['attributes']
  if'JOINTS_0'not in attrs:continue
  v=target.accessor(attrs['POSITION']);ji=target.accessor(attrs['JOINTS_0']).astype(int);we=target.accessor(attrs['WEIGHTS_0']);mask=np.sum(we*np.isin(ji,foot_joint_ids),axis=1)>.35
  if np.any(mask):geometry.append((np.c_[v[mask],np.ones(mask.sum())],ji[mask],we[mask]))
assert geometry

def sole(world):
 mats=[]
 for j in joints:
  m=np.eye(4);m[:3,:3]=world[j][1].as_matrix();m[:3,3]=world[j][0];mats.append(m)
 skinm=np.array(mats)@ibm;lo=1e9
 for v,ji,we in geometry:
  current=np.sum(np.einsum('nvij,nj->nvi',skinm[ji],v)*we[:,:,None],axis=1);lo=min(lo,float(current[:,1].min()))
 return lo
baseline_sole=sole(idle)
out=deepcopy(target.j);blob=bytearray(target.bin)
def append(a,kind):
 a=np.asarray(a,dtype='<f4');blob.extend(b'\0'*(-len(blob)%4));view=len(out['bufferViews']);out['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':a.nbytes});blob.extend(a.tobytes());acc={'bufferView':view,'componentType':5126,'count':len(a),'type':kind}
 if kind=='SCALAR':acc['min']=a.min(axis=0).tolist();acc['max']=a.max(axis=0).tolist()
 out['accessors'].append(acc);return len(out['accessors'])-1
report={'status':'TMP ONLY / NOT ACCEPTED / no controller integration','source':'Quaternius UAL2 Standard CC0','source_file':str(source.path),'base_xuchu_bin_sha256':hashlib.sha256(target.bin).hexdigest(),'base_runtime_sha256':hashlib.sha256(target_path.read_bytes()).hexdigest(),'method':'Full source whole-body world rotations calibrated from source T pose, full scaled source Hips XYZ; fixed foot/toe reference; one constant per-clip actual target skin sole placement. No IK, no pelvis clamp, no XZ clipping, no curve smoothing, no left-hand weapon constraint. Right hand is wielding; left keeps source animation.','hip_scale_ratio':ratio,'baseline_idle_actual_sole':baseline_sole,'clips':{}}
for alias,clip in [('XuUAL2RegularFull','Sword_Regular_Combo'),('XuUAL2HeavyFull','Sword_Heavy_Combo'),('XuUAL2RegularC','Sword_Regular_C')]:
 duration=source.duration(clip);times=np.linspace(0,duration,round(duration*30)+1);poses=[];lowest=[];source_low=[];rotations={a:[]for a in pairs};translations=[]
 for t in times:
  w,_=source.pose(clip,float(t));desired={a:w[b][1]*correction[a]for a,b in pairs.items()};p={};globalr={}
  for a in target.order:
   parent=target.parents.get(a);pr=globalr[parent]if parent is not None else R.identity();wr=desired.get(a,pr*R.from_quat(rest[a][1]));p[a]=[rest[a][0].copy(),(pr.inv()*wr).as_quat()];globalr[a]=wr
  p[hips][0]+=(w[sourcehip][0]-ref[sourcehip][0])*ratio
  poses.append(p);lowest.append(sole(target.world(p)));source_low.append(min(w[source.names[b]][0][1]for b in ['foot_l','foot_r','ball_l','ball_r']))
 # Choose a single constant from original source low-foot contact candidates.
 source_low=np.array(source_low);mask=source_low<=np.percentile(source_low,20)+.012;offset=baseline_sole-float(np.median(np.array(lowest)[mask]))
 for p in poses:
  p[hips][0][1]+=offset;translations.append(p[hips][0].copy())
  for a in pairs:
   q=p[a][1].copy()
   if rotations[a]and np.dot(rotations[a][-1],q)<0:q=-q
   rotations[a].append(q)
 ani={'name':alias,'samplers':[],'channels':[]};ta=append(times[:,None],'SCALAR')
 for a,vals in rotations.items():ani['samplers'].append({'input':ta,'output':append(vals,'VEC4'),'interpolation':'LINEAR'});ani['channels'].append({'sampler':len(ani['samplers'])-1,'target':{'node':a,'path':'rotation'}})
 ani['samplers'].append({'input':ta,'output':append(translations,'VEC3'),'interpolation':'LINEAR'});ani['channels'].append({'sampler':len(ani['samplers'])-1,'target':{'node':hips,'path':'translation'}});out['animations'].append(ani)
 report['clips'][alias]={'source':clip,'duration':duration,'frames':len(times),'constant_body_y':offset,'source_hips_span':np.ptp([source.pose(clip,float(t))[0][sourcehip][0]for t in times],axis=0).tolist(),'target_hips_span':np.ptp(translations,axis=0).tolist(),'contact_candidates':int(mask.sum())}
assert out['animations'][:len(target.j['animations'])]==target.j['animations'];assert blob[:len(target.bin)]==target.bin
path=BASE/'xuchu-ual2-full-body-prototype.glb';write_glb(path,out,blob);report['output']=str(path);report['sha256']=hashlib.sha256(path.read_bytes()).hexdigest();(BASE/'xuchu-prototype.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
