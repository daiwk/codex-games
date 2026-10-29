"""Build a frozen animation-only K library outside the repo; no game edits.

The accompanying patch is a separate, unaccepted runtime experiment.
"""
from pathlib import Path
import argparse,copy,hashlib,json,struct
import numpy as np

WEB=Path(__file__).resolve().parents[2]
REPO=WEB.parents[1]
BASE_SHA='89f369ccbfce8b5ecd4735ed5f4a18467d23ca4dfc9ec684f51b9c7c30dad43c'
DAO_SHA='9fbc41c922c1dd65f87e239da5fa4747eddfbb0c7dab4c06d11110d8efaed064'
FK_SHA='50ebed213d9f4d90e12935474d6b992ae75e9815774037a2b366134b78ff8a55'
VARIANTS={
    'raw':('e19e3cbbf4c78146c6a34980189c40ef2e0c5445673612ae7a14401078179106','XuUAL1SwordAttackRaw','9dacd7fce44e393637cb57be06e0f90939c25a3cbf2a3893754b9a41591b0ee7'),
    'support':('b3d35d9459e3f59820a4560e551fc7d8a6cfaa952d1a1632af72c7ebe4eef4e5','XuUAL1SwordAttackSupportTrial','71bb8fcb39c95685348a6a2932dd83de7b0b174d26455a9a66f5009c7210edcc'),
    'dao_trial':(DAO_SHA,'XuDaoKUpperTwistTrial','ef37f13b2f5a2c7fe8288a5a3f992686b338ccf4ce0e4083ae90be9cd7574963'),
    'fk_trial':(FK_SHA,'XuDaoKFKRecoveryTrial','16edc9f4b3a2e70e12040eaad2c0156078b097a373f8d6720b0ec338c3ddeb0d'),
}

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
    b=p.read_bytes();n=struct.unpack_from('<I',b,12)[0]
    return json.loads(b[20:20+n]),b[28+n:]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-glb',type=Path,required=True)
    parser.add_argument('--variant',choices=VARIANTS,required=True)
    parser.add_argument('--baseline',type=Path)
    parser.add_argument('--output-dir',type=Path,required=True)
    args=parser.parse_args()
    if args.variant in ['dao_trial','fk_trial']and args.baseline is None:parser.error('Arm trials require explicit --baseline pointing to the identical frozen source rig')
    src=args.source_glb.resolve();baseline=(args.baseline or WEB/'godot/assets/characters/xuchu.glb').resolve();dest=args.output_dir.resolve()
    if dest.is_relative_to(REPO)or any(p.is_relative_to(dest)for p in [src,baseline]):parser.error('Output must be outside repository and cannot contain an input')
    if dest.exists():parser.error('Output exists; choose a new directory')
    expected,alias,out_sha=VARIANTS[args.variant]
    baseline_sha={'dao_trial':DAO_SHA,'fk_trial':FK_SHA}.get(args.variant,BASE_SHA)
    if sha(src)!=expected or sha(baseline)!=baseline_sha:parser.error('Frozen input hash differs')
    d,buf=read(src);base,bb=read(baseline)
    if args.variant in ['dao_trial','fk_trial']:
        assert len(d['skins'][0]['joints'])==68
        assert 'JOINTS_1'in d['meshes'][0]['primitives'][0]['attributes']
    assert d['animations'][:len(base['animations'])]==base['animations']
    assert buf[:base['buffers'][0]['byteLength']]==bb[:base['buffers'][0]['byteLength']]
    def arr(ai):
        a=d['accessors'][ai];v=d['bufferViews'][a['bufferView']];off=v.get('byteOffset',0)+a.get('byteOffset',0);n={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']]
        return np.frombuffer(buf,dtype='<f4',count=a['count']*n,offset=off).reshape((-1,n)).copy()
    a=copy.deepcopy(next(x for x in d['animations']if x['name']==alias));a['name']='XuUAL1GameK'
    for c in a['channels']:
        if c['target']['path']=='translation'and d['nodes'][c['target']['node']].get('name','').endswith('Hips'):
            sam=copy.deepcopy(a['samplers'][c['sampler']]);times=arr(sam['input'])[:,0];values=arr(sam['output']);root=values-values[0];root[:,1]=0;flat=values.copy();flat[:,[0,2]]=values[0,[0,2]]
            buf+=b'\0'*(-len(buf)%4);vi=len(d['bufferViews']);d['bufferViews'].append({'buffer':0,'byteOffset':len(buf),'byteLength':flat.nbytes});buf+=flat.astype('<f4').tobytes()
            ai=len(d['accessors']);d['accessors'].append({'bufferView':vi,'componentType':5126,'count':len(flat),'type':'VEC3','min':flat.min(axis=0).tolist(),'max':flat.max(axis=0).tolist()});sam['output']=ai
            a['samplers'].append(sam);c['sampler']=len(a['samplers'])-1
            break
    else:raise AssertionError('Missing Hips track')
    d['animations'].append(a);d['buffers'][0]['byteLength']=len(buf)
    j=json.dumps(d,separators=(',',':'),ensure_ascii=False).encode();j+=b' '*(-len(j)%4);buf+=b'\0'*(-len(buf)%4)
    out=struct.pack('<4sII',b'glTF',2,28+len(j)+len(buf))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(buf),0x004e4942)+buf
    if hashlib.sha256(out).hexdigest()!=out_sha:raise RuntimeError('Library binary differs from frozen prototype')
    meta={'raw_sha256':sha(src),'baseline_sha256':baseline_sha,'clip':'XuUAL1GameK','raw_clip':alias,'idle_clip':'XuUAL1SwordIdleRaw','duration':float(times[-1]),'actor_scale':2.15,'times':times.tolist(),'root_delta_model':root.tolist()}
    if args.variant=='support':meta['source_note']='Root fixed-art 18-degree follow-through support trial; post-.40 blade direction intentionally differs; no runtime changes.'
    meta['method']='Only Hips XZ delta transferred to CharacterBody; source Y, all rotations, hands, time and old 27 animations unchanged. No synthetic root motion.'
    if args.variant=='dao_trial':
        meta['source_note']='Frozen 9fbc UpperTwist right-arm candidate, 68bone/8weights; main character and imported source clips use this identical rig. Original equipment frame0. No arm/source changes here.'
        meta['method']='Only Hips XZ delta transferred to CharacterBody; source Y, all rotations, hands and time unchanged from 9fbc; no source arm edits. No synthetic root motion.'
        # Match the frozen sidecar field order as well as its numeric values.
        method=meta.pop('method');note=meta.pop('source_note');meta['source_note']=note;meta['method']=method
    if args.variant=='fk_trial':
        meta.pop('method')
        meta['source_note']='Frozen 50eb FK-recovery right-arm candidate, 68bone/8weights; main character and imported source clips use this identical rig. Original equipment frame0. No arm/source changes here.'
        meta['method']='Only Hips XZ delta transferred to CharacterBody; source Y, all rotations, hands and time unchanged from 50eb; no source arm edits. No synthetic root motion.'
        if hashlib.sha256(json.dumps(meta,indent=2).encode()).hexdigest()!='06ce586f0e7fd713d07f7bc7c9ce83f999db4a699de15c601167adbef57ce1d8':raise RuntimeError('FK sidecar differs from frozen runtime')
    dest.mkdir(parents=True)
    (dest/'xuchu_ual1_k.glb').write_bytes(out)
    (dest/'xuchu_ual1_k.json').write_text(json.dumps(meta,indent=2))
    # Fixed intended path after manual copying into an isolated Godot project.
    immutable='false'if args.variant=='fk_trial'else'true'
    (dest/'xuchu_ual1_k.glb.import').write_text('[remap]\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n[deps]\nsource_file="res://assets/motion/xuchu_ual1_k.glb"\ndest_files=[]\n[params]\nanimation/import=true\nanimation/fps=120\nanimation/remove_immutable_tracks='+immutable+'\n_subresources={"nodes":{"PATH:AnimationPlayer":{"optimizer/enabled":false,"compression/enabled":false}}}\n')
    print(json.dumps({'variant':args.variant,'library_sha256':out_sha,'sidecar_sha256':sha(dest/'xuchu_ual1_k.json'),'output':str(dest)}))

if __name__=='__main__':main()
