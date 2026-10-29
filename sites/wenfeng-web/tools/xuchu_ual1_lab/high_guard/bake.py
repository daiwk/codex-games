"""Isolated K high guard / FK exit candidate. Locked main model remains unchanged."""
from pathlib import Path
from copy import deepcopy
import sys,json,hashlib,argparse,numpy as np
from scipy.spatial.transform import Rotation as R,Slerp
ap=argparse.ArgumentParser();ap.add_argument('--source',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--tools-dir',type=Path,required=True);args=ap.parse_args();sys.path.insert(0,str(args.tools_dir));from gltf_tools import GLB,write_glb
assert not args.output.exists();g=GLB(args.source);assert hashlib.sha256(args.source.read_bytes()).hexdigest()=='50ebed213d9f4d90e12935474d6b992ae75e9815774037a2b366134b78ff8a55'
OLD='XuDaoKFKRecoveryTrial';ALIAS='XuDaoKHighGuard';SCALE=2.15;DELTA=.25
a,e,h,c=[g.names['mixamorig:'+x]for x in ['RightArm','RightForeArm','RightHand','Spine2']];active=[a,e,h]+[g.names['mixamorig:RightUpperArmTwist'+str(i)]for i in [1,2,3]]
def sm(a,b,t):
 x=np.clip((t-a)/(b-a),0,1);return float(x**3*(10-15*x+6*x*x))
def between(u,v):
 ax=np.cross(u,v);l=np.linalg.norm(ax);th=np.arccos(np.clip(np.dot(u,v)/np.linalg.norm(u)/np.linalg.norm(v),-1,1));return R.identity()if l<1e-12 else R.from_rotvec(ax/l*th)
def highguard(t):
 w,p=g.pose(OLD,float(t));s,el,wr=[w[i][0]for i in[a,e,h]];d=-w[c][1].apply([0,0,1])+[0,1,0];d/=np.linalg.norm(d);u=el-s+d*DELTA/SCALE*sm(.075,.15,t);el2=s+u/np.linalg.norm(u)*np.linalg.norm(el-s);q=between(el-s,el2-s);p[a][1]=(w[g.parents[a]][1].inv()*q*w[a][1]).as_quat();nw=g.world(p);p[e][1]=(nw[g.parents[e]][1].inv()*w[e][1]).as_quat();return p
p0=highguard(.30);_,pend=g.pose(OLD,.40)
handrest=R.from_quat(g.nodes[h]['rotation']);axis=np.array(g.nodes[h]['translation']);axis/=np.linalg.norm(axis)
def wrist(q):
 d=R.from_quat(q)*handrest.inv();q=d.as_quat();q=q if q[3]>=0 else-q;tq=np.r_[axis*np.dot(q[:3],axis),q[3]];tw=R.identity()if np.linalg.norm(tq)<1e-12 else R.from_quat(tq);return np.rad2deg((d*tw.inv()).magnitude()),np.rad2deg(tw.magnitude())
def pose(t):
 w,p=g.pose(OLD,float(t));source_local={k:[v[0].copy(),v[1].copy()]for k,v in p.items()};ex=0
 if t<.30:p=highguard(t)
 elif t<.425:
  alpha=sm(.30,.40,t)
  if t<.40:
   for k in active:p[k][1]=Slerp([0,1],R.from_quat([p0[k][1],pend[k][1]]))(alpha).as_quat()
  if t>.35:
   rejoin=sm(.35,.375,t)
   for k in active:p[k][1]=Slerp([0,1],R.from_quat([p[k][1],source_local[k][1]]))(rejoin).as_quat()
  nw=g.world(p);u=nw[e][0]-nw[a][0];v=nw[h][0]-nw[e][0];ax=-np.cross(u,v);ax/=np.linalg.norm(ax);oldH=nw[h][1];ex=40*sm(.305,1/3,t)*(1-sm(.35,.425,t));p[e][1]=(nw[g.parents[e]][1].inv()*R.from_rotvec(ax*np.deg2rad(ex))*nw[e][1]).as_quat();oldH=R.from_rotvec(ax*np.deg2rad(ex*.50))*oldH;nw=g.world(p);p[h][1]=(nw[g.parents[h]][1].inv()*oldH).as_quat()
 nw=g.world(p);sw,tw=wrist(p[h][1]);return p,{'time':float(t),'elbow_extension_deg':ex,'wrist_swing_deg':sw,'wrist_twist_deg':tw,'hand_shift_m':((nw[h][0]-w[h][0])*SCALE).tolist(),'hand_orientation_difference_deg':np.rad2deg((nw[h][1].inv()*w[h][1]).magnitude())}
out=deepcopy(g.j);blob=bytearray(g.bin);an=deepcopy(g.anims[OLD]);an['name']=ALIAS;records=[]
for ch in an['channels']:
 node=ch['target']['node']
 if node not in active or ch['target']['path']!='rotation':continue
 sa=an['samplers'][ch['sampler']];ts=g.accessor(sa['input'])[:,0];orig=g.accessor(sa['output']);vals=orig.copy();frames=np.rint(ts*120).astype(int);mask=(frames>9)&(frames<51)
 for j in np.flatnonzero(mask):
  p,row=pose(float(ts[j]));vals[j]=p[node][1]
  if np.dot(vals[j-1],vals[j])<0:vals[j]*=-1
  if node==a:records.append(row)
 assert vals[~mask].tobytes()==orig[~mask].tobytes();buf=np.asarray(vals,dtype='<f4');blob.extend(b'\0'*(-len(blob)%4));vi=len(out['bufferViews']);out['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':buf.nbytes});blob.extend(buf.tobytes());ai=len(out['accessors']);out['accessors'].append({'bufferView':vi,'componentType':5126,'count':len(buf),'type':'VEC4'});ns=deepcopy(sa);ns['output']=ai;an['samplers'].append(ns);ch['sampler']=len(an['samplers'])-1
out['animations'].append(an);args.output.parent.mkdir(parents=True,exist_ok=True);write_glb(args.output,out,blob);meta={'source_sha256':hashlib.sha256(args.source.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(args.output.read_bytes()).hexdigest(),'alias':ALIAS,'scope':'RightArm/ForeArm/Hand and upper3twist rotation tracks .075-.425 only; all fingers/body/freeleft/leg/root/mesh/grip untouched; main character unchanged. .075-.3 high guard preserving old global hand/fore; .3-.4 whole FK right chain preparation-to-original-cut .4 quaternion blend, locally rejoining current source FK over.35-.375 so the cutting hand approaches along the original slice rather than returning laterally at contact; elbow extension40deg peak is split equally between wrist compensation and coherent whole-hand turn, envelope through.425. All >=.425 original tracks byte-exact.','max_wrist_swing_deg':max(x['wrist_swing_deg']for x in records),'max_wrist_twist_deg':max(x['wrist_twist_deg']for x in records),'records':records};args.output.with_suffix('.json').write_text(json.dumps(meta,indent=2));print(json.dumps({k:v for k,v in meta.items()if k!='records'}))
