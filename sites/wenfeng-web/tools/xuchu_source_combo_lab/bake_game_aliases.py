from pathlib import Path
from copy import deepcopy
import json,hashlib
import numpy as np
from scipy.spatial.transform import Rotation as R,Slerp
import argparse,sys
TOOLS=Path(__file__).resolve().parents[1]
WEB=TOOLS.parent
sys.path.insert(0,str(TOOLS))
from gltf_tools import GLB,write_glb
parser=argparse.ArgumentParser(description="Add the frozen source-family game aliases in an isolated project; no import/render/deploy.")
parser.add_argument("--rig-glb",type=Path,required=True)
parser.add_argument("--project",type=Path,required=True)
parser.add_argument("--metadata",type=Path,required=True)
args=parser.parse_args()
BASE=args.rig_glb.resolve();DEST=args.project.resolve();METADATA=args.metadata.resolve()
if DEST.is_relative_to(WEB.parents[1]) or METADATA.is_relative_to(WEB.parents[1]):parser.error("Generated project/metadata must be outside the repository")
if METADATA==BASE or DEST/"assets/characters/xuchu.glb"==BASE:parser.error("Never overwrite the source rig")
g=GLB(BASE);scene=deepcopy(g.j);blob=bytearray(g.bin);hips=g.names['mixamorig:Hips'];full='XuUAL2RegularTwistRig';full0=g.pose(full,0)[1][hips][0].copy()
assert hashlib.sha256(BASE.read_bytes()).hexdigest()=='d940035cc72829f37b277dfdefef60e5a6c5d90513fa38ab39028e306d4b7e76'

def append(ar,kind):
 ar=np.asarray(ar,dtype='<f4');blob.extend(b'\0'*(-len(blob)%4));vi=len(scene['bufferViews']);scene['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':ar.nbytes});blob.extend(ar.tobytes());acc={'bufferView':vi,'componentType':5126,'count':len(ar),'type':kind}
 if kind=='SCALAR':acc.update(min=[float(ar.min())],max=[float(ar.max())])
 scene['accessors'].append(acc);return len(scene['accessors'])-1

def value(channel,t):
 samp=g.anims[current_source]['samplers'][channel['sampler']];ts=g.accessor(samp['input'])[:,0];vs=g.accessor(samp['output']);t=np.clip(t,ts[0],ts[-1])
 if len(ts)==1:return vs[0]
 if channel['target']['path']=='rotation':return Slerp(ts,R.from_quat(vs))(t).as_quat()
 return np.array([np.interp(t,ts,vs[:,j]) for j in range(vs.shape[1])])

config={
 'XuGameJ1':(full,0.,13/30),
 'XuGameJ2':(full,13/30,1.),
 'XuGameJ3':(full,1.,3.),
 'XuGameRecover1':('XuUAL2RegularARecoveryTwistRig',0.,g.duration('XuUAL2RegularARecoveryTwistRig')),
 'XuGameRecover2':('XuUAL2RegularBRecoveryTwistRig',0.,g.duration('XuUAL2RegularBRecoveryTwistRig')),
 'XuGameReady':(full,0.,0.),
 'XuGameReadyAfter1':('XuUAL2RegularARecoveryTwistRig',g.duration('XuUAL2RegularARecoveryTwistRig'),g.duration('XuUAL2RegularARecoveryTwistRig')),
 'XuGameReadyAfter2':('XuUAL2RegularBRecoveryTwistRig',g.duration('XuUAL2RegularBRecoveryTwistRig'),g.duration('XuUAL2RegularBRecoveryTwistRig')),
 'XuGameReadyAfter3':(full,3.,3.),
}
motion={'schema':1,'status':'ISOLATED GAMEPLAY PROTOTYPE / NOT ARTISTIC ACCEPTANCE','base_sha256':hashlib.sha256(BASE.read_bytes()).hexdigest(),'actor_scale':2.15,'root_owner':'CharacterBody via source XZ deltas and move_and_slide; new game aliases keep only constant Full0 Hips XZ and original animated Y. No old lunge/AttackTempo.','facing':'One initial actor basis for the entire Full chain/recovery; original internal Hips/source yaw retained.','late_input':'During natural A/B recovery or final C stage, J records a 260ms source-clock intention to start a NEW J1 only after complete recovery. Earlier intentions expire; K/dodge/skill/ultimate requests supersede them; hit/legacy interruption and reset clear them. J2/J3 continuation buffers remain distinct and obey original source segment boundaries.','clips':{},'profiles':[{'clip':'XuGameJ1','duration':13/30,'active':[.10,.40],'damage':18.,'cost':16.,'reach':2.45},{'clip':'XuGameJ2','duration':1-13/30,'active':[.08,.50],'damage':21.,'cost':19.,'reach':2.53},{'clip':'XuGameJ3','duration':2.,'active':[.12,.90],'damage':28.,'cost':23.,'reach':2.60}]}

# Independent source-authored J3 release beats; body/root/timing remain unchanged.
motion['profiles'][2]['beats']=[{'id': 'lift', 'active': [0.15, 0.31], 'damage_base': 12.0, 'guard_cost': 10.0, 'hit_stun': 0.1, 'knockback': 0.5, 'block_knockback': 0.3, 'block_defender_energy': 2.571428571428571, 'block_attacker_energy': 1.2857142857142856, 'evade_energy': 3.8571428571428568, 'source_full_window': [1.15, 1.31]}, {'id': 'downcut', 'active': [0.54, 0.68], 'damage_base': 16.0, 'guard_cost': 14.0, 'hit_stun': 0.2, 'knockback': 1.1, 'block_knockback': 0.5, 'block_defender_energy': 3.4285714285714284, 'block_attacker_energy': 1.7142857142857142, 'evade_energy': 5.142857142857142, 'source_full_window': [1.54, 1.6800000000000002]}]
motion['two_beat_budget']={'status': 'SOURCE-FAMILY PROTOTYPE / NOT A HIT GUARANTEE', 'total_base_damage': 28, 'weapon_damage_multiplier': 1.12, 'guard_cost_upper_bound': 24, 'hit_stun_nominal_sum': 0.3, 'hit_knockback_speed_nominal_sum': 1.6, 'block_knockback_speed_nominal_sum': 0.8, 'block_defender_energy_sum': 6, 'block_attacker_energy_sum': 3, 'evade_defender_energy_sum': 9, 'parry': 'Each beat remains nonheavy/parryable; successful parry interrupts the whole chain, preserving original once-only +18 energy/+13 stamina/.70s attacker stagger.', 'skill_guard': 'Successful skill guard interrupts the chain and retains its complete +10 energy counter reward.', 'warning': 'Stun durations and assigned knockback speeds are nominal budgets; actual controlled time and displacement must be measured. Missed beats grant nothing. No collision widening or target tracking.'}

for alias,(current_source,a,b) in config.items():
 ani={'name':alias,'samplers':[],'channels':[]};duration=b-a
 for channel in g.anims[current_source]['channels']:
  sample=g.anims[current_source]['samplers'][channel['sampler']];alltimes=g.accessor(sample['input'])[:,0]
  if duration==0:ts=np.array([a,a+1.]);values=np.array([value(channel,a),value(channel,a)])
  else:
   ts=np.unique(np.r_[a,alltimes[(alltimes>a+1e-7)&(alltimes<b-1e-7)],b]);values=np.array([value(channel,t) for t in ts])
  if channel['target']['node']==hips and channel['target']['path']=='translation':values[:,0]=full0[0];values[:,2]=full0[2]
  if channel['target']['path']=='rotation':
   for i in range(1,len(values)):
    if np.dot(values[i-1],values[i])<0:values[i]*=-1
  ta=append((ts-a)[:,None],'SCALAR');va=append(values,{'translation':'VEC3','rotation':'VEC4','scale':'VEC3'}[channel['target']['path']]);ani['samplers'].append({'input':ta,'output':va,'interpolation':'LINEAR'});ani['channels'].append({'sampler':len(ani['samplers'])-1,'target':deepcopy(channel['target'])})
 scene['animations'].append(ani)
 dur=duration if duration else 1.;tt=np.linspace(0,duration,round(duration*120)+1) if duration else np.array([0.,1.]);roots=[]
 for t in tt:
  p=g.pose(current_source,a+float(t) if duration else a)[1][hips][0];roots.append(p.copy())
 roots=np.array(roots);roots=roots-roots[0];roots[:,1]=0
 motion['clips'][alias]={'source_clip':current_source,'source_start':a,'source_end':b,'duration':dur,'times':tt.tolist(),'root_delta_model':roots.tolist(),'root_end_world':(roots[-1]*2.15).tolist()}
assert scene['nodes']==g.j['nodes'] and scene['meshes']==g.j['meshes'] and scene['skins']==g.j['skins'];assert blob[:len(g.bin)]==g.bin
out=DEST/'assets/characters/xuchu.glb';write_glb(out,scene,blob);motion['runtime_sha256']=hashlib.sha256(out.read_bytes()).hexdigest();(DEST/'assets/motion').mkdir(exist_ok=True);(DEST/'assets/motion/xuchu_source_combo.json').write_text(json.dumps(motion,indent=2));METADATA.write_text(json.dumps(motion,indent=2));print(motion['runtime_sha256'])
# Explicit import parameters retain the high-rate twist chain and all eight
# skin influences. Creating this file is not an engine/import invocation.
params=(Path(__file__).resolve().parent/"xuchu_import.params").read_text()
header='[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n[deps]\nsource_file="res://assets/characters/xuchu.glb"\ndest_files=[]\n[params]\n'
out.with_suffix('.glb.import').write_text(header+params)
