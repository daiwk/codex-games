from lab_context import OUTPUT, TOOLS, SOURCE, TARGET, MANIFEST
from pathlib import Path
from copy import deepcopy
import sys,json,hashlib
import numpy as np
sys.path.insert(0,str(TOOLS))
from prepare_polearms import Sampler
from gltf_tools import write_glb
B=OUTPUT;m=Sampler(B/'xuchu-ual2-twist-rig-experiment.glb');out=deepcopy(m.j);blob=bytearray(m.bin);helpers=[m.names['mixamorig:RightForeArmTwist'+str(i)]for i in [1,2,3]]
def append(vals,kind):
 ar=np.asarray(vals,dtype='<f4');blob.extend(b'\0'*(-len(blob)%4));v=len(out['bufferViews']);out['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':ar.nbytes});blob.extend(ar.tobytes());ac={'bufferView':v,'componentType':5126,'count':len(ar),'type':kind}
 if kind=='SCALAR':ac['min']=ar.min(axis=0).tolist();ac['max']=ar.max(axis=0).tolist()
 out['accessors'].append(ac);return len(out['accessors'])-1
rot=append([[0,0,0,1],[0,0,0,1]],'VEC4');count=0
for old,ani in zip(m.j['animations'],out['animations']):
 if ani['name']=='XuUAL2RegularTwistRig':assert ani==old;continue
 ta=append([[0],[m.duration(ani['name'])]],'SCALAR')
 for h in helpers:
  assert not any(c['target']['node']==h for c in old['channels']);ani['samplers'].append({'input':ta,'output':rot,'interpolation':'LINEAR'});ani['channels'].append({'sampler':len(ani['samplers'])-1,'target':{'node':h,'path':'rotation'}})
 assert ani['channels'][:len(old['channels'])]==old['channels'];assert ani['samplers'][:len(old['samplers'])]==old['samplers'];count+=1
assert blob[:len(m.bin)]==m.bin
path=B/'xuchu-ual2-twist-rig-compatible.glb';write_glb(path,out,blob);rep={'status':'TMP CONTROLLER COMPATIBILITY VARIANT / NOT VISUAL ACCEPTANCE','input':str(m.path),'output':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'method':'Only append three helper identity tracks to each legacy clip. All prior channels/samplers and binary prefix exact. Existing TwistRig experimental clip is unchanged. This explicitly owns helper tracks across switches; the tested current Godot default Mixer also resets the unfixed Idle case, so prior residual roll is not established. Runtime wrist/IK parent adaptation remains separate.','legacy_aliases_with_identity':count};(B/'twist-rig-compatible.json').write_text(json.dumps(rep,indent=2));print(json.dumps(rep),flush=True)
