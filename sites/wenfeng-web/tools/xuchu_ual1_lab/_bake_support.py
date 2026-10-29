"""Small follow-through art trial: change palm/blade orientation explicitly.

No source-body rewrite, elbow IK, foot change or timing edit. Not accepted.
"""
from pathlib import Path
from copy import deepcopy
import hashlib,json,sys
sys.dont_write_bytecode=True
import numpy as np
from scipy.spatial.transform import Rotation as R
import argparse
TOOLS=Path(__file__).resolve().parents[1]
WEB=TOOLS.parent
sys.path.insert(0,str(TOOLS))
parser=argparse.ArgumentParser(description="Private exact local art bake; use prepare.py.")
parser.add_argument("--raw-glb",type=Path,required=True)
parser.add_argument("--output-dir",type=Path,required=True)
args=parser.parse_args();B=args.output_dir.resolve()
if B.is_relative_to(WEB.parents[1]):parser.error("Output must be outside the repository")
if any((B/n).exists() for n in ["xuchu-ual1-support-art-trial.glb","metadata.json"]):parser.error("Never overwrite outputs")
from gltf_tools import GLB,write_glb

g=GLB(args.raw_glb.resolve())
assert hashlib.sha256(g.path.read_bytes()).hexdigest()=='e19e3cbbf4c78146c6a34980189c40ef2e0c5445673612ae7a14401078179106'
clip='XuUAL1SwordAttackRaw';alias='XuUAL1SwordAttackSupportTrial'
e,h=[g.names['mixamorig:Right'+p]for p in ['ForeArm','Hand']]
rest=R.from_quat(g.nodes[h]['rotation'])
ani=deepcopy(g.anims[clip]);ani['name']=alias
ch=next(c for c in ani['channels']if c['target']['node']==h and c['target']['path']=='rotation')
sm=ani['samplers'][ch['sampler']];ts=g.accessor(sm['input'])[:,0]

def smooth(a,b,x):
    u=np.clip((x-a)/(b-a),0,1)
    return u*u*u*(u*(u*6-15)+10)

qs=[];rows=[]
for t in ts:
    world,pose=g.pose(clip,float(t))
    axis=world[h][0]-world[e][0];axis/=np.linalg.norm(axis)
    neutral=world[e][1]*rest
    q=(world[h][1]*neutral.inv()).as_quat()
    if q[3]<0:q=-q
    proj=np.dot(q[:3],axis)
    tq=np.r_[axis*proj,q[3]]
    twist=R.identity()if np.linalg.norm(tq)<1e-10 else R.from_quat(tq/np.linalg.norm(tq))
    swing=R.from_quat(q)*twist.inv();rv=swing.as_rotvec();angle=np.linalg.norm(rv)
    envelope=smooth(.40,.48,float(t))*(1-smooth(.75,1.0,float(t)))
    remove=np.deg2rad(18)*smooth(np.deg2rad(40),np.deg2rad(68),angle)*envelope
    ns=R.from_rotvec(rv*(1-remove/angle))if angle>1e-10 else R.identity()
    nh=ns*twist*neutral
    local=(world[e][1].inv()*nh).as_quat()
    if qs and np.dot(qs[-1],local)<0:local=-local
    qs.append(local)
    rows.append({'time':float(t),'raw_wrist_swing_deg':float(np.rad2deg(angle)),'removed_flex_deg':float(np.rad2deg(remove)),'trial_wrist_swing_deg':float(np.rad2deg(angle-remove))})

out=deepcopy(g.j);blob=bytearray(g.bin)
q=np.asarray(qs,dtype='<f4');blob.extend(b'\0'*(-len(blob)%4))
vi=len(out['bufferViews']);out['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':q.nbytes});blob.extend(q.tobytes())
ai=len(out['accessors']);out['accessors'].append({'bufferView':vi,'componentType':5126,'count':len(q),'type':'VEC4'})
ani['samplers'][ch['sampler']]['output']=ai
out['animations'].append(ani)
assert blob[:len(g.bin)]==g.bin
path=B/'xuchu-ual1-support-art-trial.glb';write_glb(path,out,blob)
report={'status':'ART TRIAL / NOT ACCEPTED / source palm and knife orientation intentionally changed','input_sha256':hashlib.sha256(g.path.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'alias':alias,'method':'Smooth 18deg maximum reduction of deep right-wrist flexion in .40–1.0s follow-through; preserves source pronation. No arm/shoulder relocation, no leg/root/foot/timing changes. Finger local rotations remain authored and follow the edited palm. Original aliases and BIN prefix unchanged.','trace':rows}
(B/'metadata.json').write_text(json.dumps(report,indent=2))
print(report['output_sha256'],max(x['removed_flex_deg']for x in rows),max(x['trial_wrist_swing_deg']for x in rows))
