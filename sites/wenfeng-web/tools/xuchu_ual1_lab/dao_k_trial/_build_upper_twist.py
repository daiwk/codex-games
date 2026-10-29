"""Final isolated upper-arm twist hypothesis; all old channels immutable."""
from pathlib import Path
import argparse
from copy import deepcopy
import sys,json,hashlib,numpy as np
from scipy.spatial.transform import Rotation as R
sys.dont_write_bytecode=True
TOOLS=Path(__file__).resolve().parents[2]
WEB=TOOLS.parent
sys.path.insert(0,str(TOOLS))
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--arm-glb',type=Path,required=True)
parser.add_argument('--support-glb',type=Path,required=True)
parser.add_argument('--output-dir',type=Path,required=True)
args=parser.parse_args()
assert hashlib.sha256(args.support_glb.resolve().read_bytes()).hexdigest()=='b3d35d9459e3f59820a4560e551fc7d8a6cfaa952d1a1632af72c7ebe4eef4e5'
B=args.output_dir.resolve()
if B.is_relative_to(WEB.parents[1]):parser.error('Output must be outside the repository')
if any((B/n).exists() for n in ['xuchu-dao-k-upper-twist.glb','upper-twist-metadata.json']):parser.error('Never overwrite experiment outputs')
from gltf_tools import GLB,write_glb
from prepare_polearms import between
basepath=args.arm_glb.resolve();sourcepath=args.support_glb.resolve();m=GLB(basepath);source=GLB(sourcepath);assert hashlib.sha256(basepath.read_bytes()).hexdigest()=='f233a6ddb05553bf188e998a0dc20960bf00b95948230134716db1e78b54d0c1';clip='XuDaoKArmArtTrial';alias='XuDaoKUpperTwistTrial';a,e,h=[m.names['mixamorig:Right'+s]for s in ['Arm','ForeArm','Hand']];out=deepcopy(m.j);blob=bytearray(m.bin);wr,pr=m.pose();direction=np.array(m.nodes[e]['translation']);axis=direction/np.linalg.norm(direction);helpers=[]
assert not any(c['target']['node']==e and c['target']['path']=='translation'for an in m.j['animations']for c in an['channels'])
for k in range(3):
 i=len(out['nodes']);helpers.append(i);out['nodes'].append({'name':f'mixamorig:RightUpperArmTwist{k+1}','translation':(direction/3).tolist(),'rotation':[0,0,0,1],'children':[]})
out['nodes'][a]['children']=[helpers[0]if c==e else c for c in out['nodes'][a]['children']]
for i,nxt in zip(helpers,helpers[1:]+[e]):out['nodes'][i]['children']=[nxt]
out['nodes'][e]['translation']=[0,0,0]
def append(vals,kind,component=5126):
 ar=np.asarray(vals,dtype='<f4'if component==5126 else'<u2');blob.extend(b'\0'*(-len(blob)%4));v=len(out['bufferViews']);out['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':ar.nbytes});blob.extend(ar.tobytes());ac={'bufferView':v,'componentType':component,'count':len(ar),'type':kind}
 if kind=='SCALAR':ac['min']=ar.min(axis=0).tolist();ac['max']=ar.max(axis=0).tolist()
 out['accessors'].append(ac);return len(out['accessors'])-1
skin=out['skins'][0];oldj=skin['joints'].copy();ibm=m.accessor(skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1);newibm=list(ibm);index=oldj.index(a)
for k,i in enumerate(helpers):
 mat=np.eye(4);mat[:3,:3]=wr[a][1].as_matrix();mat[:3,3]=wr[a][0]+wr[a][1].apply(direction*(k+1)/3);newibm.append(np.linalg.inv(mat))
skin['joints']=oldj+helpers;skin['inverseBindMatrices']=append(np.array(newibm).transpose(0,2,1).reshape(-1,16),'MAT4');jointids=[index]+list(range(len(oldj),len(oldj)+3));S=wr[a][0];E=wr[e][0];worldaxis=(E-S)/np.linalg.norm(E-S);length=np.linalg.norm(E-S);changed=0;maxinfluences=0
for meshidx,mesh in enumerate(out['meshes']):
 for pidx,prim in enumerate(mesh['primitives']):
  at=prim['attributes'];oldat=m.j['meshes'][meshidx]['primitives'][pidx]['attributes']
  if 'JOINTS_0'not in at:continue
  ji=m.accessor(oldat['JOINTS_0']).astype(int);we=m.accessor(oldat['WEIGHTS_0']);verts=m.accessor(oldat['POSITION'])
  if 'JOINTS_1'in oldat:ji=np.c_[ji,m.accessor(oldat['JOINTS_1']).astype(int)];we=np.c_[we,m.accessor(oldat['WEIGHTS_1'])]
  joints=[];weights=[]
  for v,j,w in zip(verts,ji,we):
   pairs=[]
   for bone,value in zip(j,w):
    if value<=0:continue
    if bone!=index:pairs.append((bone,value));continue
    coordinate=np.clip(np.dot(v-S,worldaxis)/length,0,1)*3;seg=min(int(coordinate),2);alpha=coordinate-seg;pairs.extend([(jointids[seg],value*(1-alpha)),(jointids[seg+1],value*alpha)]);changed+=1
   merged={}
   for bone,value in pairs:merged[bone]=merged.get(bone,0)+value
   pairs=[(bone,value)for bone,value in merged.items()if value>1e-12];pairs.sort(key=lambda p:-p[1]);maxinfluences=max(maxinfluences,len(pairs));assert len(pairs)<=8;assert abs(sum(z[1]for z in pairs)-sum(w))<1e-6;pairs+=[(0,0)]*(8-len(pairs));joints.append([z[0]for z in pairs]);weights.append([z[1]for z in pairs])
  joints=np.array(joints);weights=np.array(weights);at['JOINTS_0']=append(joints[:,:4],'VEC4',5123);at['WEIGHTS_0']=append(weights[:,:4],'VEC4');at['JOINTS_1']=append(joints[:,4:],'VEC4',5123);at['WEIGHTS_1']=append(weights[:,4:],'VEC4')
# Append identity tracks to every old clip; old channels/samplers and original BIN remain prefix-exact.
identity=append([[0,0,0,1],[0,0,0,1]],'VEC4')
for old,an in zip(m.j['animations'],out['animations']):
 ta=append([[0],[m.duration(an['name'])]],'SCALAR')
 for i in helpers:an['samplers'].append({'input':ta,'output':identity,'interpolation':'LINEAR'});an['channels'].append({'sampler':len(an['samplers'])-1,'target':{'node':i,'path':'rotation'}})
 assert an['channels'][:len(old['channels'])]==old['channels']and an['samplers'][:len(old['samplers'])]==old['samplers']
# Only the new hypothesis clip replaces upper-arm full twist with source-aligned proximal swing.
ts=np.linspace(0,m.duration(clip),185);qs={i:[]for i in[a]+helpers};rows=[];previous=None
for t in ts:
 w,p=m.pose(clip,float(t));s,sp=source.pose('XuUAL1SwordAttackSupportTrial',float(t));prox=between(s[e][0]-s[a][0],w[e][0]-w[a][0])*s[a][1];full=w[a][1];delta=prox.inv()*full;rv=delta.as_rotvec();raw=float(rv@axis);raw+=2*np.pi*round((previous-raw)/(2*np.pi))if previous is not None else 0;previous=raw;pure=R.from_rotvec(axis*raw);residual=float(np.rad2deg((pure.inv()*delta).magnitude()));assert residual<1e-4
 rots={a:w[m.parents[a]][1].inv()*prox};rots.update({i:R.from_rotvec(axis*raw/3)for i in helpers})
 for i in qs:
  q=rots[i].as_quat()
  if qs[i]and np.dot(q,qs[i][-1])<0:q=-q
  qs[i].append(q)
 rows.append({'time':float(t),'humerus_roll_deg':float(np.rad2deg(raw)),'per_station_roll_deg':float(np.rad2deg(raw/3)),'pure_axial_residual_deg':residual})
an=deepcopy(m.anims[clip]);an['name']=alias;ta=append(ts[:,None],'SCALAR')
for c in an['channels']:
 if c['target']['node']==a and c['target']['path']=='rotation':an['samplers'].append({'input':ta,'output':append(qs[a],'VEC4'),'interpolation':'LINEAR'});c['sampler']=len(an['samplers'])-1
for i in helpers:an['samplers'].append({'input':ta,'output':append(qs[i],'VEC4'),'interpolation':'LINEAR'});an['channels'].append({'sampler':len(an['samplers'])-1,'target':{'node':i,'path':'rotation'}})
out['animations'].append(an);assert blob[:len(m.bin)]==m.bin;path=B/'xuchu-dao-k-upper-twist.glb';write_glb(path,out,blob)
report={'status':'TMP UPPER-ARM TWIST RIG HYPOTHESIS / NOT ACCEPTED','source_arm_trial':str(basepath),'source_sha256':hashlib.sha256(basepath.read_bytes()).hexdigest(),'source_body':str(sourcepath),'output':str(path),'output_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'added_alias':alias,'legacy_aliases_with_identity':len(m.anims),'helper_node_ids':helpers,'old_right_forearm_translation':direction.tolist(),'weighting':'Original RightArm influence split linearly by rest shoulder→elbow axial coordinate over proximal,1/3,2/3,elbow stations. Up to8 weights; no discarded original influences. Helpers identity gives original world bones and original skin. ForeArm parent final station; local translation0, original local rotation unchanged.','maximum_influences':maxinfluences,'vertices_with_upper_arm_influence':changed,'equipment_local_Q':[0,0,0,1],'new_K':'Proximal Arm world uses minimum source→f233 humerus direction swing. The full remaining axial roll is divided1/3 over helpers, reaching exact f233 Arm orientation at elbow. f233 ForeArm/Hand/Fingers local tracks and body timing unchanged. This redistributes skin, not a claim that total shoulder roll or physical pose is natural.','trace':rows};(B/'upper-twist-metadata.json').write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items()if k!='trace'},indent=2))
