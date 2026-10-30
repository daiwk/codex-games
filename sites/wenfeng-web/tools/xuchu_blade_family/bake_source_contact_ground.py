"""Source-contact lower-body control: exact-length2bone legs, source poles and nearest feasible pelvisY.
Fixed upper-body locals/time/rootXZ; no goal clipping or ground pin.
"""
from pathlib import Path
from copy import deepcopy
import argparse,sys,json,hashlib,numpy as np
from scipy.spatial.transform import Rotation as R
ap=argparse.ArgumentParser();ap.add_argument('--target',type=Path,required=True);ap.add_argument('--source',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--tools-dir',type=Path,required=True);ap.add_argument('--clips',nargs='+',required=True);ap.add_argument('--ground-y-model',type=float,default=0.0);a=ap.parse_args();sys.path.insert(0,str(a.tools_dir));from gltf_tools import GLB,write_glb
assert not a.output.exists();G=GLB(a.target);S=GLB(a.source);assert hashlib.sha256(a.target.read_bytes()).hexdigest()=='5ee4e8e1d8292b53be6dd8eba7fbc16dbcff040ecbbfe8ee8ae71c582dc35c67';assert hashlib.sha256(a.source.read_bytes()).hexdigest()=='8cee20ab1bc55130092447e810e26df22dd2803eccc54f52137a7d54d7ab88a8';ratio=.45443943577095475;scale=2.15;hip=G.names['mixamorig:Hips'];tol_model=1e-5/scale
# Cache interpolation, without importing any QA/capture module.
class Cache:
 def __init__(self,g):self.g=g;self.c={}
 def pose(self,clip,t):
  from scipy.spatial.transform import Slerp
  p={i:[np.array(n.get('translation',[0.,0,0])),np.array(n.get('rotation',[0.,0,0,1]))]for i,n in enumerate(self.g.nodes)}
  if clip not in self.c:
   z=[]
   for c in self.g.anims[clip]['channels']:
    k=c['target']['path']
    if k not in ['rotation','translation']:continue
    sm=self.g.anims[clip]['samplers'][c['sampler']];ts=self.g.accessor(sm['input'])[:,0];v=self.g.accessor(sm['output']);z.append((c['target']['node'],k,ts,v,Slerp(ts,R.from_quat(v))if k=='rotation'and len(ts)>1 else None))
   self.c[clip]=z
  for i,k,ts,v,ip in self.c[clip]:
   x=np.clip(t,ts[0],ts[-1]);p[i][k=='rotation']=v[0].copy()if len(ts)==1 else(ip(x).as_quat()if k=='rotation'else np.array([np.interp(x,ts,v[:,j])for j in range(3)]))
  return p
GC,SC=Cache(G),Cache(S)
def worldm(g,p):
 w={}
 for i in g.order:
  m=np.eye(4);m[:3,:3]=R.from_quat(p[i][1]).as_matrix()@np.diag(g.nodes[i].get('scale',[1,1,1]));m[:3,3]=p[i][0];w[i]=w[g.parents[i]]@m if i in g.parents else m
 return w
def swing(u,v):
 u=u/np.linalg.norm(u);v=v/np.linalg.norm(v);axis=np.cross(u,v);n=np.linalg.norm(axis);dot=float(np.dot(u,v))
 if n<1e-12:
  if dot>0:return R.identity()
  basis=np.eye(3)[np.argmin(np.abs(u))];axis=np.cross(u,basis);return R.from_rotvec(axis/np.linalg.norm(axis)*np.pi)
 return R.from_rotvec(axis/n*np.arctan2(n,dot))
class ShoeGeometry:
 def __init__(self,g,source=False):
  self.g=g;skin=g.j['skins'][0];self.joints=skin['joints'];self.ib=g.accessor(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1);self.geo=[];self.counts={'Left':0,'Right':0}
  for mesh in g.j['meshes']:
   for pr in mesh['primitives']:
    at=pr['attributes']
    if 'JOINTS_0'not in at:continue
    v=g.accessor(at['POSITION']);j=g.accessor(at['JOINTS_0']).astype(int);w=g.accessor(at['WEIGHTS_0'])
    if 'JOINTS_1'in at:j=np.c_[j,g.accessor(at['JOINTS_1']).astype(int)];w=np.c_[w,g.accessor(at['WEIGHTS_1'])]
    masks={}
    for side,suf in [('Left','l'),('Right','r')]:
     names=[x+'_'+suf for x in ['foot','ball','ball_leaf']]if source else[side+x for x in ['Foot','ToeBase','Toe_End']];ids=[i for i,n in enumerate(self.joints)if any(g.nodes[n]['name'].endswith(q)for q in names)];masks[side]=(w*np.isin(j,ids)).sum(1)>.5;self.counts[side]+=int(masks[side].sum())
    keep=masks['Left']|masks['Right'];self.geo.append((np.c_[v[keep],np.ones(keep.sum())],j[keep],w[keep],{s:m[keep]for s,m in masks.items()}))
 def minima(self,wm):
  mats=np.array([wm[i]for i in self.joints])@self.ib;ret={s:float('inf')for s in ['Left','Right']}
  for v,j,w,masks in self.geo:
   xyz=(np.einsum('nvij,nj->nvi',mats[j],v)*w[:,:,None]).sum(1)[:,:3]
   for side,mask in masks.items():
    if mask.any():ret[side]=min(ret[side],float(xyz[mask,1].min()))
  return ret
TG,SG=ShoeGeometry(G),ShoeGeometry(S,True);bt=worldm(G,GC.pose('XuAnatomy_Sword_Regular_A',0));bs=worldm(S,SC.pose('Sword_Regular_A',0));baseTS=TG.minima(bt);baseSS=SG.minima(bs);legids={};srcids={}
for side,suf in [('Left','l'),('Right','r')]:legids[side]=[G.names['mixamorig:'+side+x]for x in ['UpLeg','Leg','Foot']];srcids[side]=[S.names[x+'_'+suf]for x in ['thigh','calf','foot']]
parentHip=G.parents[hip];parentM=worldm(G,GC.pose('XuAnatomy_Sword_Regular_A',0))[parentHip];assert np.linalg.norm(parentM[[0,2],1])<1e-10;hipYgain=parentM[1,1]
def target_pelvis_interval(baseW,goals,lengths):
 lo,hi=-float('inf'),float('inf');each={}
 for side in ['Left','Right']:
  sh=baseW[legids[side][0]][:3,3];goal=goals[side];L1,L2=lengths[side];rho2=float(np.sum((goal[[0,2]]-sh[[0,2]])**2));r=L1+L2
  if rho2>r*r+1e-12:raise RuntimeError('Source XZ goal unreachable: '+str((side,rho2,r*r)))
  v=np.sqrt(max(0,r*r-rho2));dl=goal[1]-sh[1]-v;dh=goal[1]-sh[1]+v;lo=max(lo,dl);hi=min(hi,dh);each[side]=[float(dl),float(dh)]
 if lo>hi+1e-10:raise RuntimeError('Both source-contact pelvisY intervals do not intersect: '+str(each))
 delta=min(max(0.,lo),hi)
 return float(delta),[float(lo),float(hi)],each

def solve_legs(basep,baseR,baseW,sw,goals,lengths,delta,previous_poles):
 p=deepcopy(basep);p[hip][0][1]+=delta/hipYgain;wm=worldm(G,p);poles={};debug={}
 for side in ['Left','Right']:
  up,knee,foot=legids[side];su,sk,sf=srcids[side];sh=wm[up][:3,3];goal=goals[side];v=goal-sh;dist=np.linalg.norm(v);L1,L2=lengths[side]
  if dist>L1+L2+1e-7 or dist<abs(L1-L2)-1e-7:raise RuntimeError('Exact original-bone-length IK bound violated: '+str((side,dist,L1,L2)))
  axis=v/max(dist,1e-12);sv=sw[sf][:3,3]-sw[su][:3,3];sa=sv/np.linalg.norm(sv);svk=sw[sk][:3,3]-sw[su][:3,3];pole=svk-sa*np.dot(svk,sa)
  if np.linalg.norm(pole)<1e-9:
   if side in previous_poles:pole=swing(previous_poles[side]['axis'],axis).apply(previous_poles[side]['pole'])
   else:
    seed=np.eye(3)[np.argmin(np.abs(axis))];pole=seed-axis*np.dot(seed,axis)
  else:pole=swing(sa,axis).apply(pole)
  pole-=axis*np.dot(pole,axis);pole/=np.linalg.norm(pole);x=(dist*dist+L1*L1-L2*L2)/(2*max(dist,1e-12));height=np.sqrt(max(0,L1*L1-x*x));newK=sh+axis*x+pole*height
  oldU=baseW[knee][:3,3]-baseW[up][:3,3];oldV=baseW[foot][:3,3]-baseW[knee][:3,3];newU=newK-sh;newV=goal-newK;ru=swing(oldU,newU)*baseR[up][1];rl=swing(oldV,newV)*baseR[knee][1];p[up][1]=(baseR[G.parents[up]][1].inv()*ru).as_quat();p[knee][1]=(ru.inv()*rl).as_quat();p[foot][1]=(rl.inv()*baseR[foot][1]).as_quat();poles[side]={'axis':axis,'pole':pole};step=0.
  if side in previous_poles:
   transported=swing(previous_poles[side]['axis'],axis).apply(previous_poles[side]['pole']);step=float(np.rad2deg(np.arccos(np.clip(np.dot(transported,pole),-1,1))))
  debug[side]={'knee_bend_plane_source_pole_step_deg':step,'target_knee_flex_deg':float(np.rad2deg(np.pi-np.arccos(np.clip(np.dot(-newU,newV)/L1/L2,-1,1)))),'straight_knee':bool(height<1e-7),'knee_goal_model':newK.tolist(),'ankle_goal_model':goal.tolist()}
 return p,poles,debug
out=deepcopy(G.j);blob=bytearray(G.bin);report={'input_sha256':hashlib.sha256(a.target.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256(a.source.read_bytes()).hexdigest(),'ratio':ratio,'target_shoe_vertices':TG.counts,'source_shoe_vertices':SG.counts,'ground_plane_model_y':a.ground_y_model,'ground_rule':'desired actual soleY = max(mapped source animated soleY, ground plane). Positive source lifts unchanged; source XZ/poles/Foot orientation retained.','scope':'Only selected new aliases UpLeg/Leg IK, Foot local counterrotation and HipsY nearest shared reachable interval projection; original lengths, source knee pole transport, Foot/Toe global source-reference rotations, all upper local rotation tracks, all time and rootXZ remain copied unchanged. Source lifts are preserved, negative actual sole goals receive only standard ground nonpenetration max(sourceY,groundY). No goal projection or trajectory smoothing.','clips':{}}
def append(vals):
 arr=np.asarray(vals,dtype='<f4');blob.extend(b'\0'*(-len(blob)%4));vi=len(out['bufferViews']);out['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':arr.nbytes});blob.extend(arr.tobytes());out['accessors'].append({'bufferView':vi,'componentType':5126,'count':len(arr),'type':'VEC3'if arr.shape[1]==3 else'VEC4'});return len(out['accessors'])-1
for clip in a.clips:
 alias='XuAnatomy_'+clip;ani=deepcopy(G.anims[alias]);ts=G.accessor(ani['samplers'][ani['channels'][0]['sampler']]['input'])[:,0];poses=[];rows=[];previous_poles={}
 for t in ts:
  basep=GC.pose(alias,float(t));baseR=G.world(basep);baseW=worldm(G,basep);sw=worldm(S,SC.pose(clip,float(t)));targetSoles=TG.minima(baseW);sourceSoles=SG.minima(sw);goals={};desired={};raw_desired={};lengths={}
  for side in ['Left','Right']:
   up,kn,ft=legids[side];sf=srcids[side][2];goals[side]=bt[ft][:3,3]+ratio*(sw[sf][:3,3]-bs[sf][:3,3]);raw_desired[side]=baseTS[side]+ratio*(sourceSoles[side]-baseSS[side]);desired[side]=max(raw_desired[side],a.ground_y_model);goals[side][1]=desired[side]-(targetSoles[side]-baseW[ft][1,3]);lengths[side]=[np.linalg.norm(baseW[kn][:3,3]-baseW[up][:3,3]),np.linalg.norm(baseW[ft][:3,3]-baseW[kn][:3,3])]
  for iteration in range(24):
   delta,interval,each=target_pelvis_interval(baseW,goals,lengths);p,poles,dbg=solve_legs(basep,baseR,baseW,sw,goals,lengths,delta,previous_poles);actualW=worldm(G,p);actual=TG.minima(actualW);errors={s:desired[s]-actual[s]for s in ['Left','Right']}
   if max(abs(x)for x in errors.values())<=tol_model:break
   for side in ['Left','Right']:goals[side][1]+=errors[side]
  else:raise RuntimeError('Actual shoe contour fixed point did not converge: '+str((clip,float(t),errors)))
  previous_poles=poles;poses.append(p);ankleerr=max(np.linalg.norm(actualW[legids[s][2]][:3,3]-goals[s])*scale for s in ['Left','Right']);rows.append({'time':float(t),'pelvis_y_delta_runtime_m':delta*scale,'pelvis_y_feasible_interval_runtime_m':[x*scale for x in interval],'original_pelvis_in_interval':bool(interval[0]<=0<=interval[1]),'iterations':iteration+1,'actual_sole_max_error_runtime_m':max(abs(x)for x in errors.values())*scale,'actual_ankle_goal_error_runtime_m':float(ankleerr),'source_animated_sole_model_y':raw_desired,'desired_sole_model_y':desired,'actual_sole_model_y':actual,'sides':dbg})
 for ch in ani['channels']:
  node=ch['target']['node'];path=ch['target']['path']
  if path=='rotation'and node in sum(legids.values(),[]):
   vals=[]
   for p in poses:
    q=p[node][1];q=-q if vals and np.dot(q,vals[-1])<0 else q;vals.append(q)
  elif path=='translation'and node==hip:vals=[p[hip][0]for p in poses]
  else:continue
  sm=deepcopy(ani['samplers'][ch['sampler']]);sm['output']=append(vals);ani['samplers'].append(sm);ch['sampler']=len(ani['samplers'])-1
 index=next(i for i,x in enumerate(out['animations'])if x['name']==alias);out['animations'][index]=ani;summary={'duration':float(ts[-1]),'frames':len(ts),'pelvis_y_minmax_runtime_m':[min(x['pelvis_y_delta_runtime_m']for x in rows),max(x['pelvis_y_delta_runtime_m']for x in rows)],'pelvis_changed_frames':sum(abs(x['pelvis_y_delta_runtime_m'])>1e-6 for x in rows),'maximum_sole_error_runtime_m':max(x['actual_sole_max_error_runtime_m']for x in rows),'maximum_ankle_error_runtime_m':max(x['actual_ankle_goal_error_runtime_m']for x in rows),'max_iterations':max(x['iterations']for x in rows),'ground_corrected_frames':{s:sum(x['source_animated_sole_model_y'][s]<a.ground_y_model for x in rows)for s in ['Left','Right']},'max_source_pole_direction_step_deg':max(v['knee_bend_plane_source_pole_step_deg']for x in rows for v in x['sides'].values()),'straight_knee_frames':{s:sum(x['sides'][s]['straight_knee']for x in rows)for s in ['Left','Right']}};report['clips'][clip]={'summary':summary,'rows':rows};print(clip,summary,flush=True)
assert blob[:len(G.bin)]==G.bin;a.output.parent.mkdir(parents=True,exist_ok=True);write_glb(a.output,out,blob);report['output_sha256']=hashlib.sha256(a.output.read_bytes()).hexdigest();a.output.with_suffix('.json').write_text(json.dumps(report,indent=2));print('OUTPUT',report['output_sha256'],flush=True)
