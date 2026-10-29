"""One full FK candidate through approved true key poses. No end-effector solve."""
from pathlib import Path
import argparse
from copy import deepcopy
import sys,json,hashlib,numpy as np
from scipy.spatial.transform import Rotation as R,RotationSpline
sys.dont_write_bytecode=True
TOOLS=Path(__file__).resolve().parents[3]
WEB=TOOLS.parent
sys.path.insert(0,str(TOOLS))
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base-glb',type=Path,required=True)
parser.add_argument('--keys-glb',type=Path,required=True)
parser.add_argument('--output-dir',type=Path,required=True)
args=parser.parse_args()
B=args.output_dir.resolve()
if B.is_relative_to(WEB.parents[1]):parser.error('Output must be outside the repository')
if any((B/n).exists() for n in ['xuchu-dao-k-fk-recovery.glb','fk-recovery-metadata.json']):parser.error('Never overwrite experiment outputs')
from gltf_tools import GLB,write_glb
g=GLB(args.base_glb.resolve());keys=GLB(args.keys_glb.resolve());assert hashlib.sha256(g.path.read_bytes()).hexdigest()=='9fbc41c922c1dd65f87e239da5fa4747eddfbb0c7dab4c06d11110d8efaed064';assert hashlib.sha256(keys.path.read_bytes()).hexdigest()=='84a43012d9d670a5439d0df10aaba99bb92e2dedb9e0357f0b0ea8f20b2f59ab';old='XuDaoKUpperTwistTrial';alias='XuDaoKFKRecoveryTrial';parts=['RightArm','RightForeArm','RightHand']+['RightUpperArmTwist'+str(i)for i in [1,2,3]];bones=[g.names['mixamorig:'+p]for p in parts];kp={t:keys.pose(k,0)[1]for t,k in [(.65,'DaoFKPose065'),(.80,'DaoFKPose080'),(1.05,'DaoFKPose105')]};out=deepcopy(g.j);blob=bytearray(g.bin);ani=deepcopy(g.anims[old]);ani['name']=alias;rows=[];outputs={}
def append(v):
 ar=np.asarray(v,dtype='<f4');blob.extend(b'\0'*(-len(blob)%4));vi=len(out['bufferViews']);out['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':ar.nbytes});blob.extend(ar.tobytes());ai=len(out['accessors']);out['accessors'].append({'bufferView':vi,'componentType':5126,'count':len(ar),'type':'VEC4'});return ai
for c in ani['channels']:
 node=c['target']['node']
 if node not in bones or c['target']['path']!='rotation':continue
 sm=ani['samplers'][c['sampler']];ts=g.accessor(sm['input'])[:,0];original=g.accessor(sm['output']);frame=np.rint(ts*120).astype(int);keep=(frame<=66)|(frame>=156);controls=[(float(t),q)for t,q,k in zip(ts,original,keep)if k]+[(t,p[node][1])for t,p in kp.items()];controls.sort(key=lambda x:x[0]);ct=np.array([x[0]for x in controls]);cq=np.array([x[1]for x in controls]);spline=RotationSpline(ct,R.from_quat(cq));sample=spline(ts).as_quat().astype('<f4');sample[keep]=original[keep]
 # Preserve every pre-active/tail quaternion byte; choose continuous equivalent signs only in the new middle.
 for j in np.flatnonzero(~keep):
  if np.dot(sample[j-1],sample[j])<0:sample[j]*=-1
 assert sample[keep].tobytes()==original[keep].tobytes();outputs[node]=sample;ai=append(sample);newsm=deepcopy(sm);newsm['output']=ai;ani['samplers'].append(newsm);c['sampler']=len(ani['samplers'])-1
 rows.append({'bone':g.nodes[node]['name'],'time_accessor_reused':sm['input'],'old_output_accessor':sm['output'],'new_output_accessor':ai,'prefix_0_to_055_bytes_exact':sample[frame<=66].tobytes()==original[frame<=66].tobytes(),'tail_130_to_end_bytes_exact':sample[frame>=156].tobytes()==original[frame>=156].tobytes(),'key_angular_speed_rad_s':{str(t):float(np.linalg.norm(spline(t,1)))for t in kp},'interpolation':'Continuous SO(3) cubic, dense frozen source controls before.55/after1.30; internal keys have no imposed zero tangent.'})
assert len(rows)==6
assert all(np.array_equal(outputs[bones[3]],outputs[i])for i in bones[4:])
out['animations'].append(ani);assert out['animations'][:len(g.j['animations'])]==g.j['animations']and blob[:len(g.bin)]==g.bin;path=B/'xuchu-dao-k-fk-recovery.glb';write_glb(path,out,blob)
meta={'status':'ONE CONTINUOUS FK ART CANDIDATE / NOT ACCEPTED / NO RUNTIME','source9fbc_sha256':hashlib.sha256(g.path.read_bytes()).hexdigest(),'approved_static_keys_sha256':hashlib.sha256(keys.path.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'alias':alias,'duration':g.duration(old),'rig_equipment_grip_weights_body_timing_unchanged':True,'scope':'Only six right-arm/helper rotation output tracks append. Inputs/time accessors reused. 0–.55 and1.30–end original output samples byte-exact, hence original baked curves before the join are unchanged. Right arm cubic local rotation curves pass approved .65/.80/1.05 FK poses without key holds/forced zero tangents. Wrist/blade are fullFK outputs, no W/BladeFrame/targetIK or angle sweep. Same source body, feet, free left and finger local channels.','tracks':rows};(B/'fk-recovery-metadata.json').write_text(json.dumps(meta,indent=2));print(json.dumps(meta,indent=2))
