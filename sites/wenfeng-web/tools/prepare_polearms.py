#!/usr/bin/env python3
"""Bake free KayKit two-handed clips onto the supplied Guan Yu / Zhang Fei / Lu Bu rigs.

Optional preparation dependencies: numpy, scipy, Pillow. Original GLBs are
read-only inputs. Runtime and local Web play need none of these dependencies.
"""
from copy import deepcopy
import hashlib
import io
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.spatial.transform import Rotation as R, Slerp

from gltf_tools import GLB, compact_buffers, write_glb

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT.parents[1] / "godot-games/3a-games"
GAME = ROOT / "godot"
KAY = ASSETS / "source/third_party/kaykit"


class Sampler(GLB):
    """Cache source interpolation; the same authored clips drive both rigs."""
    def __init__(self, path):
        super().__init__(path)
        self.samples = {}

    def pose(self, name=None, time=0.0):
        pose = {i: [np.array(n.get('translation', [0., 0., 0.])),
                    np.array(n.get('rotation', [0., 0., 0., 1.]))]
                for i, n in enumerate(self.nodes)}
        if name:
            if name not in self.samples:
                channels = []
                for channel in self.anims[name]['channels']:
                    path = channel['target']['path']
                    if path not in ('translation', 'rotation'):
                        continue
                    source = self.anims[name]['samplers'][channel['sampler']]
                    times = self.accessor(source['input'])[:, 0]
                    values = self.accessor(source['output'])
                    interpolation = Slerp(times, R.from_quat(values)) if path == 'rotation' and len(times) > 1 else None
                    channels.append((channel['target']['node'], path, times, values, interpolation))
                self.samples[name] = channels
            for node, path, times, values, interpolation in self.samples[name]:
                t = np.clip(time, times[0], times[-1])
                if len(times) == 1:
                    value = values[0]
                elif path == 'rotation':
                    value = interpolation(t).as_quat()
                else:
                    value = np.array([np.interp(t, times, values[:, axis]) for axis in range(3)])
                pose[node][path == 'rotation'] = value
        return self.world(pose), pose


def body_mapping():
    names = {'Hips': 'hips', 'Spine': 'spine', 'Spine1': 'chest',
             'Spine2': 'chest', 'Neck': 'chest', 'Head': 'head'}
    for side, suffix in [('Left', 'l'), ('Right', 'r')]:
        names.update({side + a: b + '.' + suffix for a, b in [
            ('Arm', 'upperarm'), ('ForeArm', 'lowerarm'), ('Hand', 'wrist'),
            ('UpLeg', 'upperleg'), ('Leg', 'lowerleg'), ('Foot', 'foot'),
            ('ToeBase', 'toes'), ('Toe_End', 'toes')]})
    return {'mixamorig:' + a: b for a, b in names.items()}


def clip_set(character):
    clips = {
        'Idle': ('melee', 'Melee_2H_Idle'),
        'Walk': ('basic', 'Walking_A'), 'WalkBack': ('advanced', 'Walking_Backwards'),
        'StrafeLeft': ('advanced', 'Running_Strafe_Left'),
        'StrafeRight': ('advanced', 'Running_Strafe_Right'),
        'Run': ('basic', 'Running_A'), 'TurnLeft': ('basic', 'Walking_A'),
        'TurnRight': ('basic', 'Walking_A'),
        'Attack1': ('melee', 'Melee_2H_Attack_Stab' if character == 'zhangfei' else 'Melee_2H_Attack_Slice'),
        'Attack2': ('melee', {'guanyu': 'Melee_2H_Attack_Chop', 'zhangfei': 'Melee_2H_Attack_Slice', 'lubu': 'Melee_2H_Attack_Stab'}[character]),
        'Attack3': ('melee', 'Melee_2H_Attack_Spin'),
        'Heavy': ('melee', 'Melee_2H_Attack_Chop'),
        'Block': ('melee', 'Melee_2H_Idle'), 'Dodge': ('advanced', 'Dodge_Backward'),
        'Hit': ('general', 'Hit_A'), 'GuardBreak': ('general', 'Hit_B'),
        'Death': ('general', 'Death_A'), 'Victory': ('melee', 'Melee_2H_Idle'),
    }
    if character == 'guanyu':
        clips.update(CrescentSweep=('melee', 'Melee_2H_Attack_Spin'),
                     CrescentStep=('advanced', 'Dodge_Backward'),
                     CrescentCounter=('melee', 'Melee_2H_Attack_Chop'),
                     CrescentCharge=('melee', 'Melee_2H_Idle'),
                     CrescentFinish=('melee', 'Melee_2H_Attack_Spinning'))
    elif character == 'zhangfei':
        clips.update(SerpentThrust=('melee', 'Melee_2H_Attack_Stab'),
                     SerpentBrace=('melee', 'Melee_2H_Idle'),
                     SerpentCharge=('melee', 'Melee_2H_Idle'),
                     SerpentCross=('melee', 'Melee_2H_Attack_Slice'))
    else:
        clips.update(HalberdSweep=('melee', 'Melee_2H_Attack_Spin'),
                     HalberdThrust=('melee', 'Melee_2H_Attack_Stab'),
                     HalberdCharge=('melee', 'Melee_2H_Idle'),
                     HalberdFinish=('melee', 'Melee_2H_Attack_Spinning'))
    return clips


def resize_images(scene, binary, maximum=1024):
    images = {v['bufferView']: v for v in scene.get('images', [])}
    packed = bytearray()
    for index, view in enumerate(scene['bufferViews']):
        start = view.get('byteOffset', 0)
        payload = binary[start:start + view['byteLength']]
        if index in images:
            image = Image.open(io.BytesIO(payload))
            image.thumbnail((maximum, maximum), Image.Resampling.LANCZOS)
            output = io.BytesIO()
            if images[index].get('mimeType') == 'image/jpeg':
                image.convert('RGB').save(output, format='JPEG', quality=86, optimize=True)
            else:
                image.save(output, format='PNG', optimize=True)
            payload = output.getvalue()
        packed += b'\0' * (-len(packed) % 4)
        view['byteOffset'], view['byteLength'] = len(packed), len(payload)
        packed += payload
    return packed


def between(a, b):
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
    cross = np.cross(a, b)
    sine = np.linalg.norm(cross)
    if sine < 1e-8:
        return R.identity()
    return R.from_rotvec(cross / sine * np.arctan2(sine, np.dot(a, b)))


def fit_polearm_hands(target, pose, axis, hand_rotations, palms):
    """Adapt the authored sword grip to one long shaft without stretching bones.

    KayKit's mitten hands have different proportions and attachment offsets.
    Keep its weapon direction, hand-centre motion and elbow bend; solve each
    two-bone arm for two reachable points on that shaft during the offline bake.
    """
    world = target.world(pose)
    arms = {}
    centre = np.zeros(3)
    half_spacing = .12
    for side, sign in [('Right', -1), ('Left', 1)]:
        a, e, h = [target.names['mixamorig:' + side + part] for part in ['Arm', 'ForeArm', 'Hand']]
        shoulder, elbow, wrist = [world[i][0] for i in [a, e, h]]
        offset = hand_rotations[side].apply(palms[side.lower()])
        centre += (wrist + world[h][1].apply(palms[side.lower()])) / 2
        arms[side] = (a, e, h, shoulder, elbow, offset, sign,
                      np.linalg.norm(elbow - shoulder), np.linalg.norm(wrist - elbow))
    # Project the common grip centre into both arms' reachable volumes.
    for _ in range(12):
        for side, (_, _, _, shoulder, _, offset, sign, l1, l2) in arms.items():
            anchor = shoulder + offset - axis * half_spacing * sign
            delta = centre - anchor
            maximum = (l1 + l2) * .97
            if np.linalg.norm(delta) > maximum:
                centre = anchor + delta / np.linalg.norm(delta) * maximum
    for side, (a, e, h, shoulder, elbow, offset, sign, l1, l2) in arms.items():
        wrist = centre + axis * half_spacing * sign - offset
        direction = wrist - shoulder
        distance = np.clip(np.linalg.norm(direction), abs(l1 - l2) + 1e-5, l1 + l2 - 1e-5)
        direction /= np.linalg.norm(direction)
        bend = elbow - shoulder
        bend -= direction * np.dot(bend, direction)
        if np.linalg.norm(bend) < 1e-5:
            bend = np.cross(direction, [0, 1, 0])
        bend /= np.linalg.norm(bend)
        along = (l1*l1 - l2*l2 + distance*distance) / (2*distance)
        new_elbow = shoulder + direction * along + bend * np.sqrt(max(0, l1*l1 - along*along))
        world = target.world(pose)
        arm_rotation = between(world[e][0] - shoulder, new_elbow - shoulder) * world[a][1]
        parent = target.parents[a]
        pose[a][1] = (world[parent][1].inv() * arm_rotation).as_quat()
        world = target.world(pose)
        fore_rotation = between(world[h][0] - world[e][0], wrist - world[e][0]) * world[e][1]
        pose[e][1] = (world[a][1].inv() * fore_rotation).as_quat()
        pose[h][1] = (fore_rotation.inv() * hand_rotations[side]).as_quat()


def bake(character, source_name, sources, finger_source):
    target = GLB(ASSETS / source_name)
    bind, rest = target.pose()
    skin = target.j['skins'][0]
    matrices = target.accessor(skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
    assert np.isfinite(matrices).all() and np.abs(matrices).max() < 100, 'Invalid supplied bind matrices'
    out, blob = deepcopy(target.j), bytearray(target.bin)
    out['animations'] = []
    pairs = {key: {target.names[a]: src.names[b] for a, b in body_mapping().items()
                   if a in target.names and b in src.names} for key, src in sources.items()}
    refs = {key: src.pose('T-Pose')[0] for key, src in sources.items()}
    correction = {key: {t: refs[key][s][1].inv() * bind[t][1] for t, s in pair.items()}
                  for key, pair in pairs.items()}
    finger_rest = finger_source.pose('A_TPose')[0]
    finger_hold = finger_source.pose('Sword_Idle')[0]
    finger_offsets = {}
    palms = {}
    grip_rotations = {}
    source_hand = finger_source.names['hand_r']
    mirror = np.diag([-1., 1., 1.])
    for side, suffix in [('Left', 'l'), ('Right', 'r')]:
        hand = target.names['mixamorig:' + side + 'Hand']
        source_weapon = finger_rest[source_hand][1] * R.from_euler('x', 90, degrees=True)
        if side == 'Left':
            source_weapon = R.from_matrix(mirror @ source_weapon.as_matrix() @ mirror)
        grip_rotations[side] = bind[hand][1].inv() * source_weapon
        for digit in ['Thumb', 'Index', 'Middle', 'Ring', 'Pinky']:
            for index in range(1, 5):
                name = 'mixamorig:' + side + 'Hand' + digit + str(index)
                source_name = digit.lower() + '_%02d' % index + ('_leaf' if index == 4 else '') + '_r'
                if name not in target.names or source_name not in finger_source.names:
                    continue
                t, s = target.names[name], finger_source.names[source_name]
                neutral = finger_rest[source_hand][1].inv() * finger_rest[s][1]
                closed = finger_hold[source_hand][1].inv() * finger_hold[s][1]
                delta = closed * neutral.inv()
                delta = finger_rest[source_hand][1] * delta * finger_rest[source_hand][1].inv()
                if side == 'Left':
                    delta = R.from_matrix(mirror @ delta.as_matrix() @ mirror)
                relative = bind[hand][1].inv() * bind[t][1]
                finger_offsets[t] = (hand, bind[hand][1].inv() * delta * bind[hand][1] * relative)
        knuckle = target.names['mixamorig:' + side + 'HandMiddle1']
        palms[side.lower()] = (bind[hand][1].inv().apply(bind[knuckle][0] - bind[hand][0]) * 0.85).tolist()

    hips = target.names['mixamorig:Hips']
    feet = [target.names['mixamorig:' + side + part] for side in ['Left', 'Right'] for part in ['Foot', 'ToeBase']]
    floor = min(bind[t][0][1] for t in feet)

    def append(values, kind):
        values = np.asarray(values, dtype='<f4')
        blob.extend(b'\0' * (-len(blob) % 4))
        view = len(out['bufferViews'])
        out['bufferViews'].append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': values.nbytes})
        blob.extend(values.tobytes())
        accessor = {'bufferView': view, 'componentType': 5126, 'count': len(values), 'type': kind}
        if kind == 'SCALAR':
            accessor.update(min=values.min(axis=0).tolist(), max=values.max(axis=0).tolist())
        out['accessors'].append(accessor)
        return len(out['accessors']) - 1

    metrics = {}
    hold_upper = {'Walk', 'WalkBack', 'StrafeLeft', 'StrafeRight', 'Run', 'TurnLeft', 'TurnRight', 'Dodge', 'CrescentStep'}
    for alias, (library, authored) in clip_set(character).items():
        src, pair = sources[library], pairs[library]
        duration = src.duration(authored)
        times = np.linspace(0, duration, max(2, round(duration * 30) + 1))
        rotations = {t: [] for t in set(pair) | set(finger_offsets)}
        translations = []
        for time in times:
            world, _ = src.pose(authored, time)
            if alias in hold_upper:
                idle = sources['melee'].pose('Melee_2H_Idle', time % sources['melee'].duration('Melee_2H_Idle'))[0]
                for name, node in src.names.items():
                    if name.startswith(('upperarm.', 'lowerarm.', 'wrist.', 'hand.', 'handslot.')) or name in ['chest', 'head']:
                        if name in sources['melee'].names:
                            world[node] = idle[sources['melee'].names[name]]
            desired = {t: world[s][1] * correction[library][t] for t, s in pair.items()}
            for t, (hand, relative) in finger_offsets.items():
                desired[t] = desired[hand] * relative
            pose, global_rotations = {}, {}
            for t in target.order:
                parent = target.parents.get(t)
                pr = global_rotations[parent] if parent is not None else R.identity()
                wr = desired.get(t, pr * R.from_quat(rest[t][1]))
                pose[t] = [rest[t][0].copy(), (pr.inv() * wr).as_quat()]
                global_rotations[t] = wr
            src_hip = src.names['hips']
            ratio = bind[hips][0][1] / refs[library][src_hip][0][1]
            delta = (world[src_hip][0] - refs[library][src_hip][0]) * ratio
            pose[hips][0] += delta
            if alias != 'Death':
                pose[hips][0][[0, 2]] = rest[hips][0][[0, 2]] + np.clip(delta[[0, 2]], -0.10, 0.10)
                grounded = target.world(pose)
                pose[hips][0][1] += floor - min(grounded[t][0][1] for t in feet)
            weapon_rotation = world[src.names['handslot.r']][1]
            axis = weapon_rotation.apply([0., 1., 0.])
            hand_rotations = {side: weapon_rotation * grip_rotations[side].inv() for side in ['Left', 'Right']}
            fit_polearm_hands(target, pose, axis, hand_rotations, palms)
            for t, values in rotations.items():
                q = pose[t][1]
                if values and np.dot(values[-1], q) < 0:
                    q = -q
                values.append(q)
            translations.append(pose[hips][0])
        animation = {'name': alias, 'samplers': [], 'channels': []}
        time_accessor = append(times.reshape(-1, 1), 'SCALAR')
        for t, values in rotations.items():
            animation['samplers'].append({'input': time_accessor, 'output': append(values, 'VEC4'), 'interpolation': 'LINEAR'})
            animation['channels'].append({'sampler': len(animation['samplers']) - 1, 'target': {'node': t, 'path': 'rotation'}})
        animation['samplers'].append({'input': time_accessor, 'output': append(translations, 'VEC3'), 'interpolation': 'LINEAR'})
        animation['channels'].append({'sampler': len(animation['samplers']) - 1, 'target': {'node': hips, 'path': 'translation'}})
        out['animations'].append(animation)
        metrics[alias] = {'source': authored, 'library': 'KayKit Free 1.1', 'seconds': float(duration), 'samples': len(times)}
        print(character, alias, authored, flush=True)
    blob = compact_buffers(out, blob)
    blob = resize_images(out, blob)
    out['asset']['generator'] = 'Wenfeng: CC0 KayKit T-pose world-space retarget, closed-finger grip'
    destination = GAME / ('assets/characters/' + character + '.glb')
    write_glb(destination, out, blob)
    return {'source': {'file': target.path.name, 'sha256': hashlib.sha256(target.path.read_bytes()).hexdigest()},
            'clips': metrics, 'grip': {'mode': 'two_hand', 'right_palm': palms['right'], 'left_palm': palms['left'],
                                    'weapon_length': {'guanyu': 2.85, 'zhangfei': 3.05, 'lubu': 3.15}[character],
                                    'grip_fraction': 0.35, 'axis_sign': -1.0,
                                    'adaptation': 'Authored weapon axis, offline two-bone arm IK, mirrored closed grip'}}


def main():
    sources = {key: Sampler(KAY / ('Rig_Medium_' + name + '.glb')) for key, name in [
        ('melee', 'CombatMelee'), ('general', 'General'), ('basic', 'MovementBasic'), ('advanced', 'MovementAdvanced')]}
    fingers = Sampler(ASSETS / 'source/third_party/ual1/UAL1_Standard.glb')
    manifest_path = GAME / 'assets/characters/animation_manifest.json'
    manifest = json.loads(manifest_path.read_text())
    for character, file in [('guanyu', '关羽.glb'), ('zhangfei', '张飞.glb'), ('lubu', '吕布.glb')]:
        manifest[character] = bake(character, file, sources, fingers)
    weapons = GAME / 'assets/weapons'
    weapons.mkdir(exist_ok=True)
    for name, file in [('guandao', '青龙刀.glb'), ('serpent_spear', '丈八蛇矛.glb'), ('halberd', '方天画戟.glb')]:
        scene = GLB(ASSETS / file)
        write_glb(weapons / (name + '.glb'), scene.j, resize_images(scene.j, scene.bin, 1024))
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
