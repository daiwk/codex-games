"""Reproduce Zhao Yun's two recorded locomotion clips from archived CMU data.

Run with no arguments to install the GLB and update its animation manifest.
Use --output /private/tmp/name.glb to validate without changing runtime files.
Requires NumPy and SciPy. No runtime IK, foot planner, phase editing, or rig
changes: source rotations/pelvis curves, fixed anatomical correspondence,
uniform timing, and one measured whole-clip Y placement are the full pipeline.
"""
from pathlib import Path
from copy import deepcopy
import argparse
import hashlib
import json
import numpy as np
from scipy.spatial.transform import Rotation as R

from acclaim_motion import Acclaim, between
from gltf_tools import GLB, write_glb

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / 'source-assets/animations/cmu-locomotion'
BASELINE = ROOT / 'source-assets/animations/runtime-baselines/zhaoyun-before-recorded-gaits.glb'
RUNTIME = ROOT / 'godot/assets/characters/zhaoyun.glb'
MANIFEST = ROOT / 'godot/assets/characters/animation_manifest.json'
BASELINE_SHA256 = '707628b708ab34526ae16dac1c3c735530f962191af47e5219de6c7c5f08a2b8'
REFERENCE_OUTPUT_SHA256 = 'ae7a153643e3471aa7a6956f7c3c96b8ae0a8ae5ab5fce1119d9fe2eb13fab47'
ACTOR_SCALE = 1.98
FPS = 120
CONFIG = {
    'DuelMocapRun': {
        'subject': '09', 'trial': '01', 'frames_1based': [52, 142],
        'foot_reference_frames_1based': {'Left': 93, 'Right': 51},
        'game_speed_mps': 2.85, 'controller_rate': 1.38,
        'whole_clip_ground_y_model_units': 0.01959884161115798,
    },
    'DuelMocapWalkBack': {
        'subject': '136', 'trial': '25', 'frames_1based': [857, 1054],
        'foot_reference_frames_1based': {'Left': 1033, 'Right': 936},
        'source_playback_rate': 1.4, 'controller_rate': 1.65,
        'whole_clip_ground_y_model_units': 0.030480889218230386,
    },
}


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def append_array(scene, binary, values, kind):
    values = np.asarray(values, dtype='<f4')
    binary.extend(b'\0' * (-len(binary) % 4))
    view = len(scene['bufferViews'])
    scene['bufferViews'].append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': values.nbytes})
    binary.extend(values.tobytes())
    item = {'bufferView': view, 'componentType': 5126, 'count': len(values), 'type': kind}
    if kind == 'SCALAR':
        item.update(min=[float(values.min())], max=[float(values.max())])
    scene['accessors'].append(item)
    return len(scene['accessors']) - 1


def bake(target, scene, binary, alias, config):
    subject, trial = config['subject'], config['trial']
    asf = SOURCES / (subject + '.asf')
    amc = SOURCES / (subject + '_' + trial + '.amc')
    source = Acclaim(asf)
    frames = source.read(amc)
    worlds = [source.evaluate(frame) for frame in frames]
    first, last = config['frames_1based']
    a, b = first - 1, last - 1
    assert 0 <= a < b < len(frames)
    bind, _ = target.pose()
    ready_world, ready = target.pose('Idle', 0.)
    hips = target.names['mixamorig:Hips']
    mapping, children = {}, {}
    for side, prefix in [('Left', 'l'), ('Right', 'r')]:
        for part, bone, child in [('UpLeg', 'femur', 'Leg'), ('Leg', 'tibia', 'Foot'),
                                   ('Foot', 'foot', 'ToeBase'), ('ToeBase', 'toes', 'Toe_End')]:
            node = target.names['mixamorig:' + side + part]
            children[node] = target.names.get('mixamorig:' + side + child,
                                               target.nodes[node].get('children', [node])[0])
            mapping[node] = prefix + bone
    for part, bone, child in [('Spine', 'lowerback', 'Spine1'), ('Spine1', 'upperback', 'Spine2'),
                               ('Spine2', 'thorax', 'Neck'), ('Neck', 'lowerneck', 'Head'),
                               ('Head', 'head', 'HeadTop_End')]:
        node = target.names['mixamorig:' + part]
        children[node] = target.names['mixamorig:' + child]
        mapping[node] = bone
    corrections = {node: between(bind[children[node]][0] - bind[node][0], source.bones[bone]['direction']) * bind[node][1]
                   for node, bone in mapping.items()}
    target_legs = sum(np.linalg.norm(bind[children[n]][0] - bind[n][0])
                      for n, bone in mapping.items() if bone.endswith(('femur', 'tibia')))
    source_legs = sum(source.bones[bone]['length'] for bone in ['lfemur', 'ltibia', 'rfemur', 'rtibia'])
    ratio = target_legs / source_legs
    roots = np.array([frames[i]['root'][:3] for i in range(a, b + 1)])
    net = roots[-1] - roots[0]
    direction = net.copy() * (1. if alias.endswith('Run') else -1.)
    # H removes capture placement. It is not a coordinate-basis conjugation.
    heading = R.from_euler('y', -np.arctan2(direction[0], direction[2]))
    references = {}
    for side, prefix in [('Left', 'l'), ('Right', 'r')]:
        reference = config['foot_reference_frames_1based'][side]
        assert 1 <= reference <= len(frames)
        references[side] = {'source_frame_1based': reference, 'rotation_mapping': {}}
        for part, bone in [('Foot', 'foot'), ('ToeBase', 'toes')]:
            node = target.names['mixamorig:' + side + part]
            ref = worlds[reference - 1][2][prefix + bone]
            # Dref -> actual Idle foot/sole frame supplies all three axes.
            # H*D(t)*K preserves the complete source temporal world rotation.
            corrections[node] = ref.inv() * heading.inv() * ready_world[node][1]
            references[side]['rotation_mapping'][part] = {
                'source_reference_world_delta_xyzw': ref.as_quat().tolist(),
                'target_idle_world_rotation_xyzw': ready_world[node][1].as_quat().tolist(),
                'fixed_right_calibration_xyzw': corrections[node].as_quat().tolist(),
            }
    source_duration = (b - a) / float(FPS)
    distance = float(np.linalg.norm(net[[0, 2]]) * ratio * ACTOR_SCALE)
    retarget_speed = distance / source_duration
    game_speed = config.get('game_speed_mps')
    if 'source_playback_rate' in config:
        game_speed = retarget_speed * config['source_playback_rate']
    controller_rate = config['controller_rate']
    clip_duration = distance / game_speed * controller_rate
    source_roots = heading.apply(roots)
    line = np.linspace(source_roots[0], source_roots[-1], len(roots))
    poses = []
    for sample, i in enumerate(range(a, b + 1)):
        rotations = worlds[i][2]
        desired = {hips: heading * rotations['root'] * bind[hips][1]}
        desired.update({node: heading * rotations[bone] * corrections[node] for node, bone in mapping.items()})
        pose, world_rot = {}, {}
        for node in target.order:
            parent = target.parents.get(node)
            pr = world_rot[parent] if parent is not None else R.identity()
            wr = desired.get(node, pr * R.from_quat(ready[node][1]))
            pose[node] = [ready[node][0].copy(), (pr.inv() * wr).as_quat()]
            world_rot[node] = wr
        hip = ready_world[hips][0].copy()
        hip[[0, 2]] += (source_roots[sample] - line[sample])[[0, 2]] * ratio
        hip[1] = source_roots[sample, 1] * ratio
        parent = target.parents.get(hips)
        pp, pq = ready_world[parent] if parent is not None else (np.zeros(3), R.identity())
        pose[hips][0] = pq.inv().apply(hip - pp)
        poses.append(pose)
    for pose in poses:
        pose[hips][0][1] += config['whole_clip_ground_y_model_units']
    times = np.linspace(0., clip_duration, len(poses))
    animation = {'name': alias, 'samplers': [], 'channels': []}
    time_id = append_array(scene, binary, times[:, None], 'SCALAR')
    for node in target.order:
        values = []
        for pose in poses:
            q = pose[node][1]
            if values and np.dot(values[-1], q) < 0.:
                q = -q
            values.append(q)
        animation['samplers'].append({'input': time_id, 'output': append_array(scene, binary, values, 'VEC4'), 'interpolation': 'LINEAR'})
        animation['channels'].append({'sampler': len(animation['samplers']) - 1, 'target': {'node': node, 'path': 'rotation'}})
    animation['samplers'].append({'input': time_id, 'output': append_array(scene, binary, [p[hips][0] for p in poses], 'VEC3'), 'interpolation': 'LINEAR'})
    animation['channels'].append({'sampler': len(animation['samplers']) - 1, 'target': {'node': hips, 'path': 'translation'}})
    scene['animations'].append(animation)
    return {
        'source': 'CMU ' + subject + '_' + trial, 'library': 'CMU Graphics Lab Motion Capture Database',
        'source_frames_1based': [first, last], 'fps': FPS, 'samples': len(poses),
        'source_seconds': source_duration, 'seconds': clip_duration,
        'source_asf_sha256': sha256(asf), 'source_amc_sha256': sha256(amc),
        'source_url': 'https://mocap.cs.cmu.edu/subjects/' + subject + '/' + subject + '_' + trial + '.amc',
        'retarget_root_cycle_distance_m': distance, 'retarget_native_speed_mps': retarget_speed,
        'game_speed_mps': game_speed, 'required_source_playback_rate': game_speed / retarget_speed,
        'existing_controller_speed_scale': controller_rate, 'actual_runtime_cycle_seconds': clip_duration / controller_rate,
        'uniform_ground_placement_model_units': config['whole_clip_ground_y_model_units'],
        'ground_reference': 'One fixed whole-clip Y chosen from actual CPU-skinned shoe support medians; mean sole +9mm compensates actor root about -9mm. Remaining left/right difference is preserved.',
        'foot_static_reference': references,
        'processing': 'Source hip/pelvis and complete spine/neck/head/leg rotations; original bone lengths and mesh. Arms/hands retain Idle relative to source chest. Fixed Foot/Toe anatomical reference, unchanged source temporal rotation. One shared heading/scale, linear rootXZ path removal, original pelvis Y curve, one constant whole-clip ground placement, uniform playback timing. No foot planner, runtime/offline IK, per-frame grounding, stride warp, or loop pose editing.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=RUNTIME)
    parser.add_argument('--manifest-output', type=Path)
    args = parser.parse_args()
    assert sha256(BASELINE) == BASELINE_SHA256, 'Recorded-gait baseline changed'
    source_manifest = json.loads((SOURCES / 'SOURCE.json').read_text())
    for config in CONFIG.values():
        for name in [config['subject'] + '.asf', config['subject'] + '_' + config['trial'] + '.amc']:
            assert sha256(SOURCES / name) == source_manifest['files'][name]['sha256'], name
    model = GLB(BASELINE)
    assert len(model.j['animations']) == 46
    scene, binary = deepcopy(model.j), bytearray(model.bin)
    assert not any(a['name'] in CONFIG for a in scene['animations'])
    clips = {alias: bake(model, scene, binary, alias, config) for alias, config in CONFIG.items()}
    for field in ['nodes', 'meshes', 'skins', 'materials', 'textures', 'images']:
        assert scene.get(field) == model.j.get(field), field
    assert bytes(binary[:len(model.bin)]) == model.bin
    for original in model.j['animations']:
        assert next(a for a in scene['animations'] if a['name'] == original['name']) == original
    args.output.parent.mkdir(parents=True, exist_ok=True)
    staged = args.output.with_name(args.output.name + '.preparing')
    try:
        write_glb(staged, scene, binary)
        runtime_sha = sha256(staged)
        assert runtime_sha == REFERENCE_OUTPUT_SHA256, 'Output differs from the reviewed recorded-gait GLB'
        staged.replace(args.output)
    finally:
        staged.unlink(missing_ok=True)
    manifest_path = args.manifest_output or (MANIFEST if args.output.resolve() == RUNTIME.resolve() else args.output.with_suffix('.manifest.json'))
    manifest = json.loads(MANIFEST.read_text())
    manifest['zhaoyun']['clips'].update(clips)
    manifest['zhaoyun']['runtime_sha256'] = runtime_sha
    manifest['zhaoyun']['recorded_duel_gaits'] = {
        'retreat_speed': clips['DuelMocapWalkBack']['game_speed_mps'],
        'step_intervals': {logical: clips[alias]['actual_runtime_cycle_seconds'] / 2.
                           for logical, alias in [('Run', 'DuelMocapRun'), ('WalkBack', 'DuelMocapWalkBack')]},
        'source': 'CMU 09_01 + 136_25; see source-assets/animations/cmu-locomotion/SOURCE.json',
        'processing': 'Fixed anatomical/foot reference retarget; original source rotation curves; uniform time scale and one constant whole-body height per clip.',
    }
    manifest['zhaoyun']['recorded_locomotion'] = {
        'baker': 'tools/prepare_recorded_locomotion.py', 'baker_sha256': sha256(__file__),
        'baseline': str(BASELINE.relative_to(ROOT)), 'baseline_sha256': BASELINE_SHA256,
        'runtime_sha256': runtime_sha, 'existing_animation_count': 46,
        'existing_binary_bytes_retained': len(model.bin), 'mode': 'append_only',
        'actor_scale': ACTOR_SCALE, 'configuration': CONFIG,
        'duel_foot_aliases': {'Run': 'DuelMocapRun', 'WalkBack': 'DuelMocapWalkBack'},
        'license_archive': 'source-assets/animations/cmu-locomotion/SOURCE.json',
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({'output': str(args.output), 'sha256': runtime_sha, 'manifest': str(manifest_path),
                      'clips': {name: {k: clip[k] for k in ['game_speed_mps', 'seconds', 'actual_runtime_cycle_seconds']} for name, clip in clips.items()}}, indent=2))


if __name__ == '__main__':
    main()
