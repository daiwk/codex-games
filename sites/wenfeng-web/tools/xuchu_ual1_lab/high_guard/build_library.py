from pathlib import Path
import struct,json,hashlib,copy,numpy as np,argparse
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--baseline-sidecar',type=Path,required=True);p.add_argument('--output-dir',type=Path,required=True);a=p.parse_args()
assert hashlib.sha256(a.source.read_bytes()).hexdigest()=='9234dffff40403eeb23ee4cb61d7508b11725818ca3cc00a3cce84901751dc41'
assert hashlib.sha256(a.baseline_sidecar.read_bytes()).hexdigest()=='06ce586f0e7fd713d07f7bc7c9ce83f999db4a699de15c601167adbef57ce1d8'
a.output_dir.mkdir(exist_ok=False,parents=True)
b=a.source.read_bytes();n=struct.unpack_from('<I',b,12)[0];d=json.loads(b[20:20+n]);buf=b[28+n:]
def arr(ai):
 x=d['accessors'][ai];v=d['bufferViews'][x['bufferView']];o=v.get('byteOffset',0)+x.get('byteOffset',0);k={'SCALAR':1,'VEC3':3,'VEC4':4}[x['type']];return np.frombuffer(buf,dtype='<f4',count=x['count']*k,offset=o).reshape(-1,k).copy()
raw='XuDaoKHighGuard';ani=copy.deepcopy(next(x for x in d['animations']if x['name']==raw));ani['name']='XuUAL1GameK'
for c in ani['channels']:
 if c['target']['path']=='translation'and d['nodes'][c['target']['node']].get('name','').endswith('Hips'):
  sm=copy.deepcopy(ani['samplers'][c['sampler']]);times=arr(sm['input'])[:,0];v=arr(sm['output']);root=v-v[0];root[:,1]=0;v[:,[0,2]]=v[0,[0,2]];buf+=b'\0'*(-len(buf)%4);vi=len(d['bufferViews']);d['bufferViews'].append({'buffer':0,'byteOffset':len(buf),'byteLength':v.nbytes});buf+=v.astype('<f4').tobytes();ai=len(d['accessors']);d['accessors'].append({'bufferView':vi,'componentType':5126,'count':len(v),'type':'VEC3','min':v.min(0).tolist(),'max':v.max(0).tolist()});sm['output']=ai;ani['samplers'].append(sm);c['sampler']=len(ani['samplers'])-1;break
else:raise RuntimeError('No Hips')
d['animations'].append(ani);d['buffers'][0]['byteLength']=len(buf);j=json.dumps(d,separators=(',',':'),ensure_ascii=False).encode();j+=b' '*(-len(j)%4);buf+=b'\0'*(-len(buf)%4);out=struct.pack('<4sII',b'glTF',2,28+len(j)+len(buf))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(buf),0x004e4942)+buf;(a.output_dir/'xuchu_ual1_k.glb').write_bytes(out)
assert hashlib.sha256(out).hexdigest()=='750a9b6d402537a1162a0ba6a7c36786539cca6ddbc5c12541a2494e8c0fe5de'
old=json.loads(a.baseline_sidecar.read_text())
assert times.tolist()==old['times'] and root.tolist()==old['root_delta_model']
old['raw_sha256']=hashlib.sha256(b).hexdigest()
old['raw_clip']=raw
old['source_note']='Xu saber high guard and shoulder-clear cutting entry; main character remains the 50eb 68-bone/8-weight rig. Archived UAL1 CC0 motion with explicitly authored right-arm corrections.'
old['method']='Hips XZ delta is transferred to CharacterBody. Authored RightArm/ForeArm/Hand and three upper-arm twist rotation tracks change only in .075-.425s. Body, legs, free arm, finger locals, root curve, grip and weapon are unchanged. From .425s the FK-recovery source tracks are byte-identical. Run entry separately plans actual shoe contacts before the source cut.'
old['preparation_fit']={'changed_interval_seconds':[0.075,0.425],'high_guard':'Exact upper-arm sphere; global forearm/hand direction preserved through .30s','cut_entry':'Whole right-arm FK transition, .35-.375 source rejoin, shared elbow extension and wrist counter-rotation; no independent weapon rotation','bake':'tools/xuchu_ual1_lab/high_guard/bake.py'}
(a.output_dir/'xuchu_ual1_k.json').write_text(json.dumps(old,indent=2))
print('library',hashlib.sha256(out).hexdigest(),'sidecar',hashlib.sha256((a.output_dir/'xuchu_ual1_k.json').read_bytes()).hexdigest())
