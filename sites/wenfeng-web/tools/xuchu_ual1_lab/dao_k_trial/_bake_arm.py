"""TMP art arm redesign. Original body/fingers/clips immutable. Not source arm preservation."""
from pathlib import Path
import argparse
from copy import deepcopy
import sys,json,hashlib
import numpy as np
from scipy.spatial.transform import Rotation as R,Slerp
sys.dont_write_bytecode=True
TOOLS=Path(__file__).resolve().parents[2]
WEB=TOOLS.parent
sys.path.insert(0,str(TOOLS))
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--support-glb',type=Path,required=True)
parser.add_argument('--manifest',type=Path,required=True)
parser.add_argument('--output-dir',type=Path,required=True)
args=parser.parse_args()
assert hashlib.sha256(args.manifest.resolve().read_bytes()).hexdigest()=='3182fe59c2175d820cacccfe70f97e6b0bb2bfbc170d0682011307d024eec6b0'
B=args.output_dir.resolve()
if B.is_relative_to(WEB.parents[1]):parser.error('Output must be outside the repository')
if any((B/n).exists() for n in ['xuchu-dao-k-arm-art.glb','arm-design-metadata.json']):parser.error('Never overwrite experiment outputs')
from gltf_tools import GLB,write_glb
from prepare_polearms import between
p=args.support_glb.resolve();g=GLB(p);assert hashlib.sha256(p.read_bytes()).hexdigest()=='b3d35d9459e3f59820a4560e551fc7d8a6cfaa952d1a1632af72c7ebe4eef4e5'
clip='XuUAL1SwordAttackSupportTrial';alias='XuDaoKArmArtTrial';a,e,h=[g.names['mixamorig:Right'+x]for x in ['Arm','ForeArm','Hand']];cfg=json.loads(args.manifest.resolve().read_text())['xuchu']['grip'];grip=R.from_quat(cfg['rotation_xyzw']);scale=2.15
axis=np.array(g.nodes[h]['translation']);l2=np.linalg.norm(axis);axis/=l2;ua=np.array(g.nodes[e]['translation']);ua/=np.linalg.norm(ua);fr=R.from_quat(g.nodes[e]['rotation']);foreRestAxis=fr.apply(axis);handrest=R.from_quat(g.nodes[h]['rotation'])
U=np.array([0.,1,0]);F=np.array([0.,0,1]);N=np.array([-1.,0,0]);prevAlpha=None

def smooth(a,b,t):
 z=np.clip((t-a)/(b-a),0,1);return z**3*(z*(z*6-15)+10)
def wrist(local):
 d=local*handrest.inv();q=d.as_quat();q=q if q[3]>=0 else-q;proj=np.dot(q[:3],axis);tq=np.r_[axis*proj,q[3]];tw=R.identity()if np.linalg.norm(tq)<1e-10 else R.from_quat(tq);sw=d*tw.inv();return float(np.rad2deg(sw.magnitude())),float(np.rad2deg(tw.magnitude()))
def solve(t):
 global prevAlpha
 w,ps=g.pose(clip,float(t));S,El,Wr=[w[i][0]for i in[a,e,h]];l1=np.linalg.norm(El-S);weight=float(np.clip(smooth(0,.30,t)*(1-smooth(.75,1.30,t)),0,1));phase=smooth(.30,.55,t);theta=np.deg2rad(110)*phase
 blade=R.from_matrix(np.column_stack((-U*np.sin(theta)+F*np.cos(theta),U*np.cos(theta)+F*np.sin(theta),N)));desired=blade*grip.inv();H=Slerp([0,1],R.from_quat([w[h][1].as_quat(),desired.as_quat()]))(weight)
 wanted=S+(F*.31+U*(.15-.27*phase))/scale;wanted=Wr*(1-weight)+wanted*weight
 # Keep source local wrist angle, move elbow/wrist on exact arm-length reachable sphere.
 localH=R.from_quat(ps[h][1]);fore=H*localH.inv();D=fore.apply(axis);anchor=S+D*l2;d=wanted-anchor;newW=anchor+d/np.linalg.norm(d)*l1;newE=newW-D*l2
 upper0=between(El-S,newE-S)*w[a][1]
 # Prefer no extra forearm axial roll at the elbow; absorb a continuous roll in upper arm.
 qb=(upper0.inv()*fore*fr.inv()).as_quat();A=np.dot(qb[:3],foreRestAxis);BB=np.dot(-qb[3]*ua-np.cross(ua,qb[:3]),foreRestAxis);alpha=2*np.arctan2(-A,BB);alpha=(alpha+np.pi)%(2*np.pi)-np.pi
 if prevAlpha is not None:alpha+=2*np.pi*round((prevAlpha-alpha)/(2*np.pi))
 prevAlpha=alpha;roll=alpha*weight;upper=R.from_rotvec((newE-S)/l1*roll)*upper0
 ps[a][1]=(w[g.parents[a]][1].inv()*upper).as_quat();ps[e][1]=(upper.inv()*fore).as_quat();ps[h][1]=localH.as_quat();nw=g.world(ps)
 sw,tw=wrist(localH);edelta=R.from_quat(ps[e][1])*fr.inv();eq=edelta.as_quat();etq=np.r_[foreRestAxis*np.dot(eq[:3],foreRestAxis),eq[3]];er=R.identity()if np.linalg.norm(etq)<1e-10 else R.from_quat(etq)
 return ps,{'time':float(t),'arm_weight':float(weight),'blade_theta_degrees':float(np.rad2deg(theta)),'target_projection_m':float(np.linalg.norm(newW-wanted)*scale),'wrist_world_m':(newW*scale).tolist(),'elbow_world_m':(newE*scale).tolist(),'upper_roll_art_degrees':float(np.rad2deg(roll)),'elbow_rest_axial_twist_degrees':float(np.rad2deg(er.magnitude())),'wrist_source_swing_deg':sw,'wrist_source_twist_deg':tw,'hand_world_target_error_deg':float(np.rad2deg((nw[h][1].inv()*H).magnitude())),'exact_wrist_target_error_m':float(np.linalg.norm(nw[h][0]-newW)*scale),'length_upper_m':float(np.linalg.norm(nw[e][0]-nw[a][0])*scale),'length_fore_m':float(np.linalg.norm(nw[h][0]-nw[e][0])*scale)}

ts=np.linspace(0,g.duration(clip),185);qs={i:[]for i in[a,e,h]};rows=[];poses=[]
for t in ts:
 ps,row=solve(float(t));poses.append(ps);rows.append(row)
 for i in qs:
  q=ps[i][1]
  if qs[i]and np.dot(q,qs[i][-1])<0:q=-q
  qs[i].append(q)
out=deepcopy(g.j);blob=bytearray(g.bin)
def append(vals,kind):
 z=np.asarray(vals,dtype='<f4');blob.extend(b'\0'*(-len(blob)%4));vi=len(out['bufferViews']);out['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':z.nbytes});blob.extend(z.tobytes());ai=len(out['accessors']);out['accessors'].append({'bufferView':vi,'componentType':5126,'count':len(z),'type':kind});return ai
ani=deepcopy(g.anims[clip]);ani['name']=alias;ta=append(ts[:,None],'SCALAR');out['accessors'][ta]['min']=[float(ts[0])];out['accessors'][ta]['max']=[float(ts[-1])]
for c in ani['channels']:
 i=c['target']['node']
 if c['target']['path']=='rotation'and i in qs:
  ani['samplers'].append({'input':ta,'output':append(qs[i],'VEC4'),'interpolation':'LINEAR'});c['sampler']=len(ani['samplers'])-1
out['animations'].append(ani);assert out['animations'][:len(g.j['animations'])]==g.j['animations']and blob[:len(g.bin)]==g.bin
path=B/'xuchu-dao-k-arm-art.glb';write_glb(path,out,blob)
meta={'status':'TMP ARM ART REDESIGN / NOT ACCEPTED / NO RUNTIME','source':str(p),'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'output':str(path),'output_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'alias':alias,'duration':g.duration(clip),'right_arm_bake_hz':120,'equipment_local_Q':[0,0,0,1],'fixed_grip':cfg,'method':'New global sagittal single-edge blade plane N=-X, S=Ucos(theta)+Fsin(theta), E=-Usin(theta)+Fcos(theta), theta quintic0→110 .30–.55. New shoulder-relative wrist .31m forward, .15m high→.12m low. Source Hand local wrist retained; exact-length upper-arm sphere projection permits new elbow/wrist points. Upper-arm continuous roll reduces forearm elbow axial twist. Prep0–.30 and recovery.75–1.30 quintic world-pose weight. Right Arm/ForeArm/Hand channels only; all source fingers/body/hips/legs/left/timing and every previous alias/BIN untouched. THIS CHANGES SOURCE ARM AND KNIFE PATH, and is not a preservation claim.','rows':rows,'original_animation_and_binary_prefix_unchanged':True,'max_projection_m':max(x['target_projection_m']for x in rows),'max_upper_roll_deg':max(abs(x['upper_roll_art_degrees'])for x in rows)}
(B/'arm-design-metadata.json').write_text(json.dumps(meta,indent=2));print(meta['output_sha256'],meta['max_projection_m'],meta['max_upper_roll_deg']);print(json.dumps([min(rows,key=lambda r:abs(r['time']-t))for t in [.3,.4,.55,.75,1.3]],indent=2))
