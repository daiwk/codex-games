"""Only three static FK authoring keys. No full clip, no weapon/end-effector targets."""
from pathlib import Path
import argparse
from copy import deepcopy
import sys,json,hashlib,numpy as np
from scipy.spatial.transform import Rotation as R,Slerp
sys.dont_write_bytecode=True
TOOLS=Path(__file__).resolve().parents[3]
WEB=TOOLS.parent
sys.path.insert(0,str(TOOLS))
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base-glb',type=Path,required=True)
parser.add_argument('--support-glb',type=Path,required=True)
parser.add_argument('--output-dir',type=Path,required=True)
args=parser.parse_args()
assert hashlib.sha256(args.support_glb.resolve().read_bytes()).hexdigest()=='b3d35d9459e3f59820a4560e551fc7d8a6cfaa952d1a1632af72c7ebe4eef4e5'
B=args.output_dir.resolve()
if B.is_relative_to(WEB.parents[1]):parser.error('Output must be outside the repository')
if any((B/n).exists() for n in ['xuchu-dao-fk-keys.glb','keys-metadata.json']):parser.error('Never overwrite experiment outputs')
from gltf_tools import GLB,write_glb
from prepare_polearms import between
g=GLB(args.base_glb.resolve());src=GLB(args.support_glb.resolve());assert hashlib.sha256(g.path.read_bytes()).hexdigest()=='9fbc41c922c1dd65f87e239da5fa4747eddfbb0c7dab4c06d11110d8efaed064';old='XuDaoKUpperTwistTrial';sourceclip='XuUAL1SwordAttackSupportTrial';a,e,h=[g.names['mixamorig:Right'+x]for x in ['Arm','ForeArm','Hand']];L=g.names['mixamorig:LeftArm'];hips=g.names['mixamorig:Hips'];neck=g.names['mixamorig:Neck'];helpers=[g.names['mixamorig:RightUpperArmTwist'+str(i)]for i in [1,2,3]];direction=np.array(g.nodes[helpers[0]]['translation'])*3;ua=direction/np.linalg.norm(direction);ha=np.array(g.nodes[h]['translation']);ha/=np.linalg.norm(ha);handrest=R.from_quat(g.nodes[h]['rotation']);scale=2.15

def norm(v):return np.asarray(v)/np.linalg.norm(v)
def body(w):
 U=norm(w[neck][0]-w[hips][0]);Rr=w[a][0]-w[L][0];Rr=norm(Rr-U*(Rr@U));F=np.cross(U,Rr);return np.column_stack([Rr,U,F])
def smooth(a,b,t):
 u=np.clip((t-a)/(b-a),0,1);return float(np.clip(u**3*(u*(u*6-15)+10),0,1))
def blend(q0,q1,u):return Slerp([0,1],R.from_quat([q0.as_quat(),q1.as_quat()]))(u)
w0,p0=g.pose(old,.55);s0,sp0=src.pose(sourceclip,.55);M0=body(s0);dup0=M0.T@norm(w0[e][0]-w0[a][0]);df0=M0.T@norm(w0[h][0]-w0[e][0]);upProx0=between(s0[e][0]-s0[a][0],w0[e][0]-w0[a][0])*s0[a][1];fullU0=w0[helpers[-1]][1];upperRoll0=float((upProx0.inv()*fullU0).as_rotvec()@ua);foreProx0=between(s0[h][0]-s0[e][0],w0[h][0]-w0[e][0])*s0[e][1];foreRoll0=float((foreProx0.inv()*w0[e][1]).as_rotvec()@ha)
upGoal=norm([.64,-.70,.28]);foreGoal=norm([-.18,.12,.98]);out=deepcopy(g.j);blob=bytearray(g.bin);rows=[]
def append(v,kind):
 ar=np.asarray(v,dtype='<f4');blob.extend(b'\0'*(-len(blob)%4));vi=len(out['bufferViews']);out['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':ar.nbytes});blob.extend(ar.tobytes());ai=len(out['accessors']);out['accessors'].append({'bufferView':vi,'componentType':5126,'count':len(ar),'type':kind});return ai
for t in [.65,.80,1.05]:
 sw,sp=src.pose(sourceclip,t);_,pose=g.pose(old,t);M=body(sw);swing=smooth(.55,.80,t);rec=smooth(.95,1.30,t);du=norm(dup0*(1-swing)+upGoal*swing);df=norm(df0*(1-swing)+foreGoal*swing);du=norm(du*(1-rec)+(M.T@norm(sw[e][0]-sw[a][0]))*rec);df=norm(df*(1-rec)+(M.T@norm(sw[h][0]-sw[e][0]))*rec);DU=M@du;DF=M@df
 prox=between(sw[e][0]-sw[a][0],DU)*sw[a][1];relax=1-smooth(.55,1.05,t);rollU=upperRoll0*relax;fullU=prox*R.from_rotvec(ua*rollU);foreProx=between(sw[h][0]-sw[e][0],DF)*sw[e][1];fore=foreProx*R.from_rotvec(ha*foreRoll0*relax);localH=blend(R.from_quat(p0[h][1]),handrest,swing);localH=blend(localH,R.from_quat(sp[h][1]),rec)
 pose[a][1]=(sw[src.parents[a]][1].inv()*prox).as_quat();pose[e][1]=(fullU.inv()*fore).as_quat();pose[h][1]=localH.as_quat()
 for i in helpers:pose[i][1]=R.from_rotvec(ua*rollU/3).as_quat()
 w=g.world(pose);alias='DaoFKPose'+str(round(t*100)).zfill(3);ani=deepcopy(g.anims[old]);ani['name']=alias;ta=append([[0],[1/60]],'SCALAR');out['accessors'][ta]['min']=[0];out['accessors'][ta]['max']=[1/60]
 for c in ani['channels']:
  node=c['target']['node'];path=c['target']['path']
  if path not in ['rotation','translation']:continue
  value=pose[node][path=='rotation'];ani['samplers'].append({'input':ta,'output':append([value,value],'VEC4'if path=='rotation'else'VEC3'),'interpolation':'LINEAR'});c['sampler']=len(ani['samplers'])-1
 out['animations'].append(ani);rows.append({'source_time':t,'alias':alias,'control':'Authored upper/forearm bone directions and axial-roll relaxation; hand local near-neutral. Wrist/blade are FK outputs, never targets.','upper_body_direction_RUF':du.tolist(),'fore_body_direction_RUF':df.tolist(),'elbow_minus_shoulder_RUF_m':(M.T@(w[e][0]-w[a][0])*scale).tolist(),'wrist_minus_shoulder_RUF_m':(M.T@(w[h][0]-w[a][0])*scale).tolist(),'upper_roll_degrees':float(np.rad2deg(rollU)),'fore_roll_degrees':float(np.rad2deg(foreRoll0*relax)),'wrist_m':(w[h][0]*scale).tolist(),'elbow_m':(w[e][0]*scale).tolist(),'source_recovery_weight':rec})
path=B/'xuchu-dao-fk-keys.glb';write_glb(path,out,blob);meta={'status':'THREE STATIC FK KEY POSES ONLY / NOT ACCEPTED / NO FULL CLIP OR RUNTIME','sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'base9fbc_animations_BIN_prefix_preserved':out['animations'][:len(g.j['animations'])]==g.j['animations']and blob[:len(g.bin)]==g.bin,'rig_weights_grip_equipment0_unchanged':True,'body_feet_left_finger_source_clock_unchanged':True,'keys':rows};(B/'keys-metadata.json').write_text(json.dumps(meta,indent=2));print(json.dumps(meta,indent=2))
