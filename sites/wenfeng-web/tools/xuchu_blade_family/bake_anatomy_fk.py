"""Read-only-input art control: UAL2 full anatomical FK, no socket/arm/wrist IK.
Appends aliases to the supplied50eb rig; never installs it into a project.
"""
from pathlib import Path
from copy import deepcopy
import argparse,sys,json,hashlib,numpy as np
from scipy.spatial.transform import Rotation as R
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--target',type=Path,required=True);p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--tools-dir',type=Path,required=True);p.add_argument('--clips',nargs='+',required=True);p.add_argument('--alias-prefix',default='XuAnatomy_');p.add_argument('--hz',type=float,default=120);p.add_argument('--floor-reference',default='Sword_Regular_A');p.add_argument('--leg-frame-align',action='store_true');p.add_argument('--root-displacement-ratio',type=float,default=None);p.add_argument('--root-neutral-source',default='Sword_Regular_A');p.add_argument('--foot-ref-source',default=None);p.add_argument('--foot-ref-target',default='Idle');p.add_argument('--sole-align-target',default=None);p.add_argument('--body-y-model',type=float,default=None,help='Optional single shared family Y constant; never per clip');a=p.parse_args();sys.path.insert(0,str(a.tools_dir));from gltf_tools import GLB,write_glb
assert not a.output.exists();g=GLB(a.target);s=GLB(a.source);assert hashlib.sha256(a.target.read_bytes()).hexdigest()=='50ebed213d9f4d90e12935474d6b992ae75e9815774037a2b366134b78ff8a55'
for clip in a.clips:assert clip in s.anims,clip
mapping={'Hips':'pelvis','Spine':'spine_01','Spine1':'spine_02','Spine2':'spine_03','Neck':'neck_01','Head':'Head'}
for side,suffix in [('Left','l'),('Right','r')]:
 for part,source in [('Shoulder','clavicle'),('Arm','upperarm'),('ForeArm','lowerarm'),('Hand','hand'),('UpLeg','thigh'),('Leg','calf'),('Foot','foot'),('ToeBase','ball'),('Toe_End','ball_leaf')]:mapping[side+part]=source+'_'+suffix
 for digit in ['Thumb','Index','Middle','Ring','Pinky']:
  for k in [1,2,3,4]:mapping[side+'Hand'+digit+str(k)]=digit.lower()+f'_{k:02d}'+('_leaf'if k==4 else'')+'_'+suffix
pairs={g.names['mixamorig:'+n]:s.names[v]for n,v in mapping.items()if 'mixamorig:'+n in g.names and v in s.names};bind,rest=g.pose();ref,_=s.pose('A_TPose');corr={i:ref[j][1].inv()*bind[i][1]for i,j in pairs.items()};foot_correction_report={}
if a.foot_ref_source is not None:
 sw,_=s.pose(a.foot_ref_source,0);tw,_=g.pose(a.foot_ref_target,0)
 for side,suffix in [('Left','l'),('Right','r')]:
  for part,bone in [('Foot','foot'),('ToeBase','ball'),('Toe_End','ball_leaf')]:
   i=g.names.get('mixamorig:'+side+part);j=s.names.get(bone+'_'+suffix)
   if i is not None and j is not None:
    old=corr[i];corr[i]=sw[j][1].inv()*tw[i][1];foot_correction_report[g.nodes[i]['name']]=float(np.rad2deg((old.inv()*corr[i]).magnitude()))
leg_frame_report={}
if a.leg_frame_align:
 def min_swing(u,v):
  u=u/np.linalg.norm(u);v=v/np.linalg.norm(v);axis=np.cross(u,v);n=np.linalg.norm(axis);assert n>1e-8 or np.dot(u,v)>0
  return R.identity()if n<1e-12 else R.from_rotvec(axis/n*np.arctan2(n,np.dot(u,v)))
 for side,suf in [('Left','l'),('Right','r')]:
  for part,child,sourcepart,sourcechild in [('UpLeg','Leg','thigh','calf'),('Leg','Foot','calf','foot')]:
   i=g.names['mixamorig:'+side+part];ci=g.names['mixamorig:'+side+child];j=s.names[sourcepart+'_'+suf];cj=s.names[sourcechild+'_'+suf];td=bind[ci][0]-bind[i][0];sd=ref[cj][0]-ref[j][0];turn=min_swing(td,sd);corr[i]=ref[j][1].inv()*turn*bind[i][1];leg_frame_report[g.nodes[i]['name']]={'target_bind_child_vector_model':td.tolist(),'source_ref_child_vector_model':sd.tolist(),'minimum_swing_deg':float(np.rad2deg(turn.magnitude())),'new_target_ref_global_basis_xyzw':(turn*bind[i][1]).as_quat().tolist()}
hip=g.names['mixamorig:Hips'];ship=s.names['pelvis'];hip_ratio=bind[hip][0][1]/ref[ship][0][1];ratio=hip_ratio if a.root_displacement_ratio is None else float(a.root_displacement_ratio);root_source_anchor=s.pose(a.root_neutral_source,0)[0][ship][0];root_target_anchor=rest[hip][0]+(root_source_anchor-ref[ship][0])*hip_ratio;feet=[g.names['mixamorig:'+side+part]for side in ['Left','Right']for part in ['Foot','ToeBase']]
def pose(clip,t,body_y=0.):
 w,_=s.pose(clip,float(t));desired={i:w[j][1]*corr[i]for i,j in pairs.items()};out={};rots={}
 for i in g.order:
  parent=g.parents.get(i);pr=rots[parent]if parent is not None else R.identity();q=desired.get(i,pr*R.from_quat(rest[i][1]));out[i]=[rest[i][0].copy(),(pr.inv()*q).as_quat()];rots[i]=q
 out[hip][0]=(rest[hip][0]+(w[ship][0]-ref[ship][0])*ratio)if a.root_displacement_ratio is None else(root_target_anchor+(w[ship][0]-root_source_anchor)*ratio);out[hip][0][1]+=body_y
 return out
p0=pose(a.floor_reference,0);w0=g.world(p0);body_y=min(bind[i][0][1]for i in feet)-min(w0[i][0][1]for i in feet)
sole_calibration_report=None
if a.sole_align_target is not None:
 skin=g.j['skins'][0];jointids=skin['joints'];ib=g.accessor(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1);footj=[i for i,j in enumerate(jointids)if any(g.nodes[j]['name'].endswith(side+part)for side in ['Left','Right']for part in ['Foot','ToeBase','Toe_End'])];geo=[]
 for mesh in g.j['meshes']:
  for prim in mesh['primitives']:
   at=prim['attributes']
   if 'JOINTS_0'not in at:continue
   v=g.accessor(at['POSITION']);ji=g.accessor(at['JOINTS_0']).astype(int);we=g.accessor(at['WEIGHTS_0'])
   if 'JOINTS_1'in at:ji=np.c_[ji,g.accessor(at['JOINTS_1']).astype(int)];we=np.c_[we,g.accessor(at['WEIGHTS_1'])]
   mask=(we*np.isin(ji,footj)).sum(1)>.5;geo.append((np.c_[v[mask],np.ones(mask.sum())],ji[mask],we[mask]))
 def actual_sole(ps):
  wm={}
  for i in g.order:
   mat=np.eye(4);mat[:3,:3]=R.from_quat(ps[i][1]).as_matrix()@np.diag(g.nodes[i].get('scale',[1,1,1]));mat[:3,3]=ps[i][0];wm[i]=wm[g.parents[i]]@mat if i in g.parents else mat
  mats=np.array([wm[i]for i in jointids])@ib
  return min(float((np.einsum('nvij,nj->nvi',mats[ji],v)*we[:,:,None]).sum(1)[:,1].min())for v,ji,we in geo)
 target_sole=actual_sole(g.pose(a.sole_align_target,0)[1]);source_sole=actual_sole(pose(a.foot_ref_source or a.floor_reference,0,0));body_y=target_sole-source_sole;sole_calibration_report={'target':a.sole_align_target+'@0','source':(a.foot_ref_source or a.floor_reference)+'@0','target_actual_sole_model':target_sole,'source_actual_sole_at_zero_body_y_model':source_sole,'shoe_vertices':sum(len(v)for v,_,_ in geo),'one_shared_body_y_model':body_y}
if a.body_y_model is not None:body_y=float(a.body_y_model)
out=deepcopy(g.j);blob=bytearray(g.bin)
def append(vals,kind):
 v=np.asarray(vals,dtype='<f4');blob.extend(b'\0'*(-len(blob)%4));vi=len(out['bufferViews']);out['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':v.nbytes});blob.extend(v.tobytes());ac={'bufferView':vi,'componentType':5126,'count':len(v),'type':kind}
 if kind=='SCALAR':ac['min']=v.min(0).tolist();ac['max']=v.max(0).tolist()
 out['accessors'].append(ac);return len(out['accessors'])-1
metadata={'target_sha256':hashlib.sha256(a.target.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256(a.source.read_bytes()).hexdigest(),'reference':'UAL2 A_TPose world correspondence; fixed original target bone translations/scales; all body+hand+finger rotations retain source FK. No weapon socket target, no wrist/forearm override, no IK or angle/roll limit, no timewarp. Existing target aliases and BIN prefix preserved. Grip/equipment config is not touched.','helper_policy':'Original 50eb 3upper twist helper locals identity; no source counterpart or new skin weights.','root_scale_ratio':ratio,'body_y_rig_constant':body_y,'body_y_reference':('explicit single shared --body-y-model constant; no per-clip/per-frame adjustment'if a.body_y_model is not None else('actual rendered shoe sole: '+str(a.foot_ref_source or a.floor_reference)+'@0 to '+str(a.sole_align_target)+'@0; one shared scalar'if a.sole_align_target is not None else a.floor_reference+'@0 (one constant for all controls; no per-frame floor/foot IK)')),'static_leg_frame_alignment':leg_frame_report,'original_hip_ratio':hip_ratio,'root_neutral_source':a.root_neutral_source,'source_Hips_neutral_model':root_source_anchor.tolist(),'target_Hips_neutral_before_bodyY_model':root_target_anchor.tolist(),'static_foot_reference':{'source':a.foot_ref_source,'target':a.foot_ref_target,'correction_change_degrees':foot_correction_report},'actual_sole_shared_calibration':sole_calibration_report,'clips':{}}
bones=g.j['skins'][0]['joints']
for clip in a.clips:
 duration=s.duration(clip);ts=np.linspace(0,duration,max(2,round(duration*a.hz)+1));poses=[pose(clip,t,body_y)for t in ts];an={'name':a.alias_prefix+clip,'channels':[],'samplers':[]};ta=append(ts[:,None],'SCALAR')
 for i in bones:
  qs=[]
  for ps in poses:
   q=ps[i][1];q=-q if qs and np.dot(q,qs[-1])<0 else q;qs.append(q)
  an['samplers'].append({'input':ta,'output':append(qs,'VEC4'),'interpolation':'LINEAR'});an['channels'].append({'target':{'node':i,'path':'rotation'},'sampler':len(an['samplers'])-1})
 an['samplers'].append({'input':ta,'output':append([ps[hip][0]for ps in poses],'VEC3'),'interpolation':'LINEAR'});an['channels'].append({'target':{'node':hip,'path':'translation'},'sampler':len(an['samplers'])-1});out['animations'].append(an);metadata['clips'][clip]={'alias':an['name'],'seconds':duration,'samples':len(ts)}
assert blob[:len(g.bin)]==g.bin;a.output.parent.mkdir(parents=True,exist_ok=True);write_glb(a.output,out,blob);metadata['output_sha256']=hashlib.sha256(a.output.read_bytes()).hexdigest();a.output.with_suffix('.json').write_text(json.dumps(metadata,indent=2));print(json.dumps(metadata,indent=2))
