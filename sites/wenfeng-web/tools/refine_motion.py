#!/usr/bin/env python3
"""Refine derived CC0 retargets; user source GLBs are never written.

Close locomotion wrist/arm loops without changing combat trajectories.
All combat channels and clocks are preserved exactly. Filtering independent
arm rotations would change the shared palm axis and real weapon trajectories.
"""
from copy import deepcopy
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np
from scipy.spatial.transform import Rotation as R, Slerp
from gltf_tools import GLB, compact_buffers, write_glb

ROOT = Path(__file__).resolve().parents[1]
LOOPS = {'Idle','Walk','WalkBack','StrafeLeft','StrafeRight','Run','TurnLeft','TurnRight'}


def batch_between(a,b):
    q=np.c_[np.cross(a,b),1.+np.einsum('ij,ij->i',a,b)]
    return R.from_quat(q/np.maximum(np.linalg.norm(q,axis=1)[:,None],1e-8))


def align_grip_axes(original,curves,count,record):
    if record['grip'].get('mode')!='two_hand':return {}
    world={}
    for node in original.order:
        definition=original.nodes[node]
        rotation=R.from_quat(curves.get((node,'rotation'),np.broadcast_to(definition.get('rotation',[0.,0.,0.,1.]),(count,4))))
        position=curves.get((node,'translation'),np.broadcast_to(definition.get('translation',[0.,0.,0.]),(count,3)))
        if node in original.parents:
            parent_position,parent_rotation=world[original.parents[node]]
            world[node]=(parent_position+parent_rotation.apply(position),parent_rotation*rotation)
        else:world[node]=(position,rotation)
    fingers=GLB(ROOT/'source-assets/animations/ual1/UAL1_Standard.glb')
    finger_rest=fingers.pose('A_TPose')[0]
    weapon=finger_rest[fingers.names['hand_r']][1]*R.from_euler('x',90,degrees=True)
    bind=original.pose()[0];mirror=np.diag([-1.,1.,1.]);hands={};hand_rotations={};grip_axis={};palms={}
    for side in ['Right','Left']:
        hand=original.names['mixamorig:'+side+'Hand'];hands[side]=hand
        source=weapon if side=='Right' else R.from_matrix(mirror@weapon.as_matrix()@mirror)
        grip=bind[hand][1].inv()*source
        grip_axis[side]=grip.apply([0.,1.,0.]);hand_rotations[side]=world[hand][1]
        palms[side]=np.asarray(record['grip'][side.lower()+'_palm'])
    for iteration in range(8):
        points={side:world[hand][0]+hand_rotations[side].apply(palms[side]) for side,hand in hands.items()}
        axis=points['Right']-points['Left'];axis/=np.maximum(np.linalg.norm(axis,axis=1)[:,None],1e-8);axis*=record['grip']['axis_sign']
        for side in hands:
            hand_rotations[side]=batch_between(hand_rotations[side].apply(grip_axis[side]),axis)*hand_rotations[side]
    results={}
    for side,hand in hands.items():
        fore=original.parents[hand];upper=original.parents[fore]
        forearm=world[fore][1];desired=hand_rotations[side];rest=R.from_quat(original.nodes[hand]['rotation'])
        local_axis=np.asarray(original.nodes[hand]['translation']);local_axis/=np.linalg.norm(local_axis)
        axis=forearm.apply(local_axis)
        delta=(desired*(forearm*rest).inv()).as_quat()
        signed=2.*np.arctan2(np.einsum('ij,ij->i',delta[:,:3],axis),delta[:,3]);signed=(signed+np.pi)%(2.*np.pi)-np.pi
        roll=np.sign(signed)*np.maximum(abs(signed)-np.deg2rad(29.),0.)
        forearm=R.from_rotvec(axis*roll[:,None])*forearm
        curves[(fore,'rotation')]=(world[upper][1].inv()*forearm).as_quat()
        curves[(hand,'rotation')]=(forearm.inv()*desired).as_quat()
        points={part:world[index][0]+hand_rotations[part].apply(palms[part]) for part,index in hands.items()}
        shaft=points['Right']-points['Left'];shaft/=np.maximum(np.linalg.norm(shaft,axis=1)[:,None],1e-8);shaft*=record['grip']['axis_sign']
        results[side]=float(np.degrees(np.arccos(np.clip(np.einsum('ij,ij->i',desired.apply(grip_axis[side]),shaft),-1.,1.))).max())
    return results


def refine_animations(original, record):
    scene = deepcopy(original.j)
    binary = bytearray(original.bin)
    changed = []
    def append(values, kind):
        values = np.asarray(values, dtype='<f4')
        binary.extend(b'\0' * (-len(binary) % 4))
        scene['bufferViews'].append({'buffer':0,'byteOffset':len(binary),'byteLength':values.nbytes})
        binary.extend(values.tobytes())
        accessor = {'bufferView':len(scene['bufferViews'])-1,'componentType':5126,'count':len(values),'type':kind}
        if kind == 'SCALAR': accessor.update(min=values.min(axis=0).tolist(),max=values.max(axis=0).tolist())
        scene['accessors'].append(accessor)
        return len(scene['accessors'])-1
    for animation in scene['animations']:
        alias = animation['name']; info = record['clips'][alias]
        if info.get('motion_refinement_version') == 1: continue
        loop = alias in LOOPS
        if not loop: continue
        raw_duration = float(info['seconds'])
        lo, hi = 0., raw_duration
        assert hi > lo
        times = np.linspace(lo, hi, max(2, round((hi-lo)*60)+1))
        output_times = times-lo
        time_accessor = append(output_times[:,None], 'SCALAR')
        curves={}
        for channel in animation['channels']:
            sampler = animation['samplers'][channel['sampler']]
            old_times = original.accessor(sampler['input'])[:,0]
            values = original.accessor(sampler['output'])
            kind = channel['target']['path']
            if kind == 'rotation':
                values = Slerp(old_times, R.from_quat(values))(np.clip(times,old_times[0],old_times[-1]))
                bone = scene['nodes'][channel['target']['node']].get('name','')
                if loop and bone.endswith(('Arm','ForeArm','Hand')):
                    first, last = values[0],values[-1]
                    shared = first * R.from_rotvec((first.inv()*last).as_rotvec()*.5)
                    relative = (shared.inv()*values).as_rotvec()
                    edge = np.minimum(times-lo, hi-times)
                    amount = np.clip(edge/min(.20,(hi-lo)*.25),0.,1.)
                    amount = amount*amount*(3.-2.*amount)
                    values = shared * R.from_rotvec(relative*amount[:,None])
                values = values.as_quat()
                for i in range(1,len(values)):
                    if values[i-1]@values[i] < 0.: values[i] *= -1.
            else:
                values = np.stack([np.interp(times,old_times,values[:,axis]) for axis in range(values.shape[1])],axis=1)
            curves[(channel['target']['node'],kind)]=values
        info['grip_axis_alignment_max_degrees']=align_grip_axes(original,curves,len(times),record)
        for channel in animation['channels']:
            sampler=animation['samplers'][channel['sampler']]
            kind=channel['target']['path'];values=curves[(channel['target']['node'],kind)]
            sampler['input']=time_accessor
            sampler['output']=append(values,'VEC4' if kind=='rotation' else 'VEC3')
        info['motion_refinement_version'] = 1
        info['seconds'] = float(hi-lo); info['samples'] = len(times)
        info['periodic_arm_wrist_closure_source_seconds']=min(.20,(hi-lo)*.25)
        changed.append(alias)
    binary = compact_buffers(scene,binary)
    return scene,binary,changed


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--characters',nargs='+',default=['zhaoyun'])
    parser.add_argument('--output-dir',type=Path,required=True)
    parser.add_argument('--input-dir',type=Path)
    args=parser.parse_args()
    base=args.input_dir or ROOT/'godot/assets/characters'
    manifest=json.loads((base/'animation_manifest.json').read_text())
    args.output_dir.mkdir(parents=True,exist_ok=True)
    for role in args.characters:
        record=deepcopy(manifest[role])
        scene,binary,changed=refine_animations(GLB(base/(role+'.glb')),record)
        write_glb(args.output_dir/(role+'.glb'),scene,binary)
        record['runtime_sha256']=hashlib.sha256((args.output_dir/(role+'.glb')).read_bytes()).hexdigest()
        (args.output_dir/(role+'.json')).write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
        print(role,changed,flush=True)

if __name__=='__main__':main()
