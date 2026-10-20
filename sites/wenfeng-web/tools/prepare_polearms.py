#!/usr/bin/env python3
"""Bake free KayKit weapon clips onto the supplied warrior rigs.

Optional preparation dependencies: numpy, scipy, Pillow. Original GLBs are
read-only inputs. Runtime and local Web play need none of these dependencies.
"""
from copy import deepcopy
import argparse
import hashlib
import io
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.spatial.transform import Rotation as R, Slerp

from gltf_tools import GLB, compact_buffers, write_glb

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "source-assets"
GAME = ROOT / "godot"
KAY = ASSETS / "animations/kaykit"
CHARACTERS = {
    'zhaoyun': ('characters/zhaoyun.glb', 3.05),
    'machao': ('characters/machao.glb', 3.05),
    'guanyu': ('characters/关羽.glb', 2.85),
    'zhangfei': ('characters/张飞.glb', 3.05),
    'lubu': ('characters/吕布.glb', 3.15),
    'xuchu': ('characters/许褚.glb', 1.25),
}


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
        'Attack1': ('melee', 'Melee_2H_Attack_Slice'),
        'Attack2': ('melee', 'Melee_2H_Attack_Stab' if character == 'lubu' else 'Melee_2H_Attack_Chop'),
        'Attack3': ('melee', 'Melee_2H_Attack_Spin'),
        'Heavy': ('melee', 'Melee_2H_Attack_Chop'),
        'Block': ('melee', 'Melee_2H_Idle'), 'Dodge': ('advanced', 'Dodge_Backward'),
        'Hit': ('general', 'Hit_A'), 'GuardBreak': ('general', 'Hit_B'),
        'Death': ('general', 'Death_A'), 'Victory': ('melee', 'Melee_2H_Idle'),
    }
    if character == 'xuchu':
        # The free library has no named 1H idle. Its authored single-hand
        # blocking stance gives the sword arm a ready pose and guards the chest.
        clips.update(Idle=('melee', 'Melee_Blocking'),
                     Block=('melee', 'Melee_Blocking'),
                     Attack1=('melee', 'Melee_1H_Attack_Slice_Horizontal'),
                     Attack2=('melee', 'Melee_1H_Attack_Slice_Diagonal'),
                     Attack3=('melee', 'Melee_1H_Attack_Chop'),
                     Heavy=('melee', 'Melee_1H_Attack_Jump_Chop'),
                     Victory=('melee', 'Melee_Blocking'),
                     TigerCleave=('melee', 'Melee_1H_Attack_Slice_Horizontal'),
                     BruteRoar=('melee', 'Melee_Blocking'),
                     BruteCharge=('melee', 'Melee_Blocking'),
                     BruteFinish=('melee', 'Melee_1H_Attack_Chop'))
    elif character in ('zhaoyun', 'machao'):
        clips.update({alias: ('melee', 'Melee_2H_Attack_Stab') for alias in
                      ['Attack1', 'Attack2', 'Attack3', 'Heavy']})
        if character == 'zhaoyun':
            clips.update({alias: ('melee', 'Melee_2H_Attack_Stab') for alias in
                          ['DragonThrust', 'DragonCross', 'DragonBackCut']})
            clips.update(CloudStep=('advanced', 'Dodge_Backward'),
                         DragonCharge=('melee', 'Melee_2H_Idle'))
            # Optional RPG equipment uses this same rig and calibrated palms.
            # Keep every duel alias intact; these authored cuts are selected
            # only by RPGActor when wielding a guandao or halberd.
            clips.update(RPGSlash=('melee', 'Melee_2H_Attack_Slice'),
                         RPGChop=('melee', 'Melee_2H_Attack_Chop'),
                         RPGSpin=('melee', 'Melee_2H_Attack_Spin'),
                         RPGFinish=('melee', 'Melee_2H_Attack_Spinning'))
        else:
            clips.update({alias: ('melee', 'Melee_2H_Attack_Stab') for alias in
                          ['TigerThrust', 'TigerFinish', 'TigerSweep', 'TigerSlam']})
            clips.update(TigerRoar=('melee', 'Melee_2H_Idle'),
                         TigerCharge=('melee', 'Melee_2H_Idle'))
    elif character == 'guanyu':
        clips.update(CrescentSweep=('melee', 'Melee_2H_Attack_Spin'),
                     CrescentStep=('advanced', 'Dodge_Backward'),
                     CrescentCounter=('melee', 'Melee_2H_Attack_Chop'),
                     CrescentCharge=('melee', 'Melee_2H_Idle'),
                     CrescentFinish=('melee', 'Melee_2H_Attack_Spinning'))
    elif character == 'zhangfei':
        # Every serpent-spear strike uses the author's linear two-handed stab.
        # Runtime playback rates distinguish the combo and charged thrust;
        # neither an overhead chop nor a spinning/sweeping cut belongs here.
        clips.update({alias: ('melee', 'Melee_2H_Attack_Stab') for alias in
                      ['Attack1', 'Attack2', 'Attack3', 'Heavy', 'SerpentThrust', 'SerpentCross']})
        clips.update(SerpentBrace=('melee', 'Melee_2H_Idle'),
                     SerpentCharge=('melee', 'Melee_2H_Idle'))
    else:
        clips.update(HalberdSweep=('melee', 'Melee_2H_Attack_Spin'),
                     HalberdThrust=('melee', 'Melee_2H_Attack_Stab'),
                     HalberdCharge=('melee', 'Melee_2H_Idle'),
                     HalberdFinish=('melee', 'Melee_2H_Attack_Spinning'))
    return clips


def resize_images(scene, binary, maximum=1024, normal_maximum=None):
    images = {v['bufferView']: v for v in scene.get('images', [])}
    normal_views = set()
    if normal_maximum is not None:
        for material in scene.get('materials', []):
            normal = material.get('normalTexture')
            if normal is not None:
                source = scene['textures'][normal['index']].get('source')
                if source is not None:
                    normal_views.add(scene['images'][source]['bufferView'])
    packed = bytearray()
    for index, view in enumerate(scene['bufferViews']):
        start = view.get('byteOffset', 0)
        payload = binary[start:start + view['byteLength']]
        if index in images:
            image = Image.open(io.BytesIO(payload))
            limit = min(maximum, normal_maximum) if index in normal_views else maximum
            image.thumbnail((limit, limit), Image.Resampling.LANCZOS)
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
    one_hand = character == 'xuchu'
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
    for side, suffix in ([('Right', 'r')] if one_hand else [('Left', 'l'), ('Right', 'r')]):
        hand = target.names['mixamorig:' + side + 'Hand']
        source_weapon = finger_rest[source_hand][1] * R.from_euler('x', 90, degrees=True)
        if side == 'Left':
            source_weapon = R.from_matrix(mirror @ source_weapon.as_matrix() @ mirror)
        grip_rotations[side] = bind[hand][1].inv() * source_weapon
        for digit in ['Thumb', 'Index', 'Middle', 'Ring', 'Pinky']:
            for index in range(1, 5):
                name = 'mixamorig:' + side + 'Hand' + digit + str(index)
                finger_name = digit.lower() + '_%02d' % index + ('_leaf' if index == 4 else '') + '_r'
                if name not in target.names or finger_name not in finger_source.names:
                    continue
                t, s = target.names[name], finger_source.names[finger_name]
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
    hold_upper = {'Walk', 'WalkBack', 'StrafeLeft', 'StrafeRight', 'Run', 'TurnLeft', 'TurnRight',
                  'Dodge', 'CrescentStep', 'CloudStep'}
    for alias, (library, authored) in clip_set(character).items():
        src, pair = sources[library], pairs[library]
        duration = src.duration(authored)
        times = np.linspace(0, duration, max(2, round(duration * 30) + 1))
        rotations = {t: [] for t in set(pair) | set(finger_offsets)}
        translations = []
        for time in times:
            world, _ = src.pose(authored, time)
            if alias in hold_upper:
                idle_name = 'Melee_Blocking' if one_hand else 'Melee_2H_Idle'
                idle = sources['melee'].pose(idle_name, time % sources['melee'].duration(idle_name))[0]
                for name, node in src.names.items():
                    if name.startswith(('upperarm.', 'lowerarm.', 'wrist.', 'hand.', 'handslot.')) or name in ['chest', 'head']:
                        if name in sources['melee'].names:
                            world[node] = idle[sources['melee'].names[name]]
            desired = {t: world[s][1] * correction[library][t] for t, s in pair.items()}
            if one_hand:
                # KayKit animates mitten-hand nodes between wrist and weapon
                # socket. Carry that authored sword orientation into our wrist
                # rather than dropping those nodes during skeleton mapping.
                right_hand = target.names['mixamorig:RightHand']
                desired[right_hand] = world[src.names['handslot.r']][1] * grip_rotations['Right'].inv()
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
            if not one_hand:
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
    blob = resize_images(out, blob, normal_maximum=512 if character in ('zhaoyun', 'machao', 'xuchu') else None)
    out['asset']['generator'] = 'Wenfeng: CC0 KayKit T-pose world-space retarget, closed-finger grip'
    destination = GAME / ('assets/characters/' + character + '.glb')
    write_glb(destination, out, blob)
    grip = ({'mode': 'one_hand', 'rotation_xyzw': grip_rotations['Right'].as_quat().tolist(),
             'position': palms['right'], 'right_palm': palms['right'],
             'mesh_scale': 0.0058, 'mesh_grip_y': -0.075,
             'adaptation': 'Authored single-hand weapon socket, closed right-hand grip; no arm IK'} if one_hand else
            {'mode': 'two_hand', 'right_palm': palms['right'], 'left_palm': palms['left'],
             'weapon_length': CHARACTERS[character][1], 'grip_fraction': 0.35, 'axis_sign': -1.0,
             'adaptation': 'Authored weapon axis, offline two-bone arm IK, mirrored closed grip'})
    return {'source': {'file': source_name, 'sha256': hashlib.sha256(target.path.read_bytes()).hexdigest()},
            'clips': metrics, 'grip': grip}


def refine_polearm_head(scene, blade_root, transition_start, scale_xyz, shaft_band):
    """Shrink a blade at its root, then move the intact upper assembly forward.

    The head is scaled about its original blade root. Its short neck and tassel
    move together with the head; the length adjustment is spread along a bare
    shaft section below the ornaments, above the fixed two-hand grip. Two
    positive-Jacobian stages preserve the tip and avoid an elongated metal cone.
    """
    assert 0. < transition_start < blade_root < 1.
    scale_x, scale_y, scale_z = scale_xyz
    source_tip = max(float(scene.accessor(primitive['attributes']['POSITION'])[:, 1].max())
                     for mesh in scene.j['meshes'] for primitive in mesh['primitives'])
    shaft_start, shaft_end = shaft_band
    assert 0.35 < shaft_start < shaft_end < transition_start
    assembly_shift = 1. - (blade_root + scale_y * (source_tip - blade_root))
    blob = bytearray(scene.bin)
    transformed_accessors = set()
    for mesh in scene.j['meshes']:
        for primitive in mesh['primitives']:
            attributes = primitive['attributes']
            if attributes['POSITION'] in transformed_accessors:
                continue
            transformed_accessors.add(attributes['POSITION'])
            positions = scene.accessor(attributes['POSITION'])
            band = blade_root - transition_start
            t = np.clip((positions[:, 1] - transition_start) / band, 0., 1.)
            blend = t * t * (3. - 2. * t)
            derivative = 6. * t * (1. - t) / band
            sx, sz = 1. + (scale_x - 1.) * blend, 1. + (scale_z - 1.) * blend
            x, y, z = positions.T
            adjusted = positions.copy()
            adjusted[:, 0], adjusted[:, 2] = x * sx, z * sz
            # Stage A: shrink the metal blade at its root, retaining the short
            # collar. Stage B: translate the complete upper assembly; extend
            # only the bare shaft below it to keep the original tip at Y=1.
            stage_y = y + (scale_y - 1.) * blend * (y - blade_root)
            shaft_t = np.clip((stage_y - shaft_start) / (shaft_end - shaft_start), 0., 1.)
            shaft_blend = shaft_t * shaft_t * (3. - 2. * shaft_t)
            shaft_derivative = 6. * shaft_t * (1. - shaft_t) / (shaft_end - shaft_start)
            adjusted[:, 1] = stage_y + assembly_shift * shaft_blend
            jxy = (scale_x - 1.) * derivative * x
            jzy = (scale_z - 1.) * derivative * z
            stage_jyy = 1. + (scale_y - 1.) * (blend + derivative * (y - blade_root))
            jyy = stage_jyy * (1. + assembly_shift * shaft_derivative)
            assert np.all(jyy >= scale_y - 1e-6), 'Head transition must not fold over'
            active = t > 0
            shaft_active = shaft_t > 0
            active |= shaft_active
            normal_active = (t > 0) | ((shaft_t > 0) & (shaft_t < 1))
            adjusted[~active] = positions[~active]
            updates = [('POSITION', adjusted)]
            if 'NORMAL' in attributes:
                normals = scene.accessor(attributes['NORMAL'])
                transformed = normals.copy()
                transformed[:, 0], transformed[:, 2] = normals[:, 0] / sx, normals[:, 2] / sz
                transformed[:, 1] = (normals[:, 1] - jxy * transformed[:, 0] - jzy * transformed[:, 2]) / jyy
                transformed[normal_active] /= np.linalg.norm(transformed[normal_active], axis=1)[:, None]
                updates.append(('NORMAL', transformed))
            if 'TANGENT' in attributes:
                tangents = scene.accessor(attributes['TANGENT'])
                transformed = tangents.copy()
                transformed[:, 0] = sx * tangents[:, 0] + jxy * tangents[:, 1]
                transformed[:, 1] = jyy * tangents[:, 1]
                transformed[:, 2] = sz * tangents[:, 2] + jzy * tangents[:, 1]
                transformed[normal_active, :3] /= np.linalg.norm(transformed[normal_active, :3], axis=1)[:, None]
                updates.append(('TANGENT', transformed))
            for semantic, values in updates:
                accessor = scene.j['accessors'][attributes[semantic]]
                view = scene.j['bufferViews'][accessor['bufferView']]
                assert accessor['componentType'] == 5126
                offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
                target = np.ndarray(values.shape, dtype='<f4', buffer=blob,
                                    offset=offset, strides=(view.get('byteStride', values.shape[1] * 4), 4))
                target[:] = values
                if semantic == 'POSITION':
                    accessor['min'], accessor['max'] = values.min(0).tolist(), values.max(0).tolist()
    scene.bin = bytes(blob)
    scene.j['asset'].setdefault('extras', {})['wenfeng_spear_head'] = {
        'head_scale_xyz': list(scale_xyz), 'blend_y': [transition_start, blade_root],
        'source_blade_root_y': blade_root, 'source_tip_y': source_tip,
        'blade_root_y': 1. + scale_y * (blade_root - source_tip),
        'tip_y': 1., 'head_pivot_y': blade_root,
        'upper_assembly_shift_y': assembly_shift, 'shaft_extension_blend_y': list(shaft_band),
        'grip_shaft_unchanged_below_y': shaft_start, 'tassel_shape_preserved': True,
    }


def center_weapon_shaft(scene, center):
    """Translate only X/Z so the authored handle sits on the game's grip axis."""
    blob = bytearray(scene.bin)
    for mesh in scene.j['meshes']:
        for primitive in mesh['primitives']:
            index = primitive['attributes']['POSITION']
            values = scene.accessor(index)
            values[:, 0] -= center[0]
            values[:, 2] -= center[1]
            accessor = scene.j['accessors'][index]
            view = scene.j['bufferViews'][accessor['bufferView']]
            offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
            target = np.ndarray(values.shape, dtype='<f4', buffer=blob,
                                offset=offset, strides=(view.get('byteStride', 12), 4))
            target[:] = values
            accessor['min'], accessor['max'] = values.min(0).tolist(), values.max(0).tolist()
    scene.bin = bytes(blob)
    scene.j['asset'].setdefault('extras', {})['wenfeng_grip_center_xz'] = list(center)


def normalize_horizontal_spear(scene, center):
    """Put an original -X-pointing spear on +Y, with its tail at zero.

    A rigid quarter-turn preserves the original spearhead, tassel and UVs.
    Divide by original length so the runtime's weapon_length is in metres.
    """
    positions = [scene.accessor(primitive['attributes']['POSITION'])
                 for mesh in scene.j['meshes'] for primitive in mesh['primitives']]
    tail = max(float(values[:, 0].max()) for values in positions)
    tip = min(float(values[:, 0].min()) for values in positions)
    length = tail - tip
    assert length > 0
    blob = bytearray(scene.bin)
    transformed_accessors = set()
    for mesh in scene.j['meshes']:
        for primitive in mesh['primitives']:
            for semantic in ('POSITION', 'NORMAL', 'TANGENT'):
                index = primitive['attributes'].get(semantic)
                if index is None or index in transformed_accessors:
                    continue
                transformed_accessors.add(index)
                values = scene.accessor(index)
                adjusted = values.copy()
                if semantic == 'POSITION':
                    adjusted[:, 0] = (values[:, 1] - center[0]) / length
                    adjusted[:, 1] = (tail - values[:, 0]) / length
                    adjusted[:, 2] = (values[:, 2] - center[1]) / length
                else:
                    adjusted[:, 0], adjusted[:, 1] = values[:, 1], -values[:, 0]
                accessor = scene.j['accessors'][index]
                view = scene.j['bufferViews'][accessor['bufferView']]
                assert accessor['componentType'] == 5126
                offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
                target = np.ndarray(adjusted.shape, dtype='<f4', buffer=blob, offset=offset,
                                    strides=(view.get('byteStride', adjusted.shape[1] * 4), 4))
                target[:] = adjusted
                if semantic == 'POSITION':
                    accessor['min'], accessor['max'] = adjusted.min(0).tolist(), adjusted.max(0).tolist()
    scene.bin = bytes(blob)
    scene.j['asset'].setdefault('extras', {})['wenfeng_spear_axis'] = {
        'source_axis': '-X', 'runtime_axis': '+Y', 'source_shaft_center_yz': list(center),
        'source_length': length, 'tail_y': 0., 'tip_y': 1.,
    }


def normalize_xuchu_saber(scene):
    """Rigidly fit the diagonal supplied saber to the shared one-hand socket.

    Its original handle is diagonal. Keep its full shape, rotate the measured
    handle axis to +Y and place the palm centre at the same 12.93 cm grip used
    by the preserved sword/saber, so all three are interchangeable on one rig.
    """
    center = np.array([0.330000013, 0.607033253, -0.057281181])
    rotation = np.array([[0.642242193, -0.715890765, 0.273907542],
                         [-0.764054060, -0.626455724, 0.154190257],
                         [0.061207581, -0.308307648, -0.949315548]])
    grip_y = 0.075 / 0.0058
    # The tip stays at Y=100, matching old weapon-tip sampling. A little pommel
    # below Y=0 is retained rather than shortening the supplied handle.
    scale = (100. - grip_y) / 1.039460421
    blob = bytearray(scene.bin)
    transformed = set()
    for mesh in scene.j['meshes']:
        for primitive in mesh['primitives']:
            for semantic in ('POSITION', 'NORMAL', 'TANGENT'):
                index = primitive['attributes'].get(semantic)
                if index is None or index in transformed:
                    continue
                transformed.add(index)
                values = scene.accessor(index)
                adjusted = values.copy()
                adjusted[:, :3] = (values[:, :3] - center) @ rotation.T * scale if semantic == 'POSITION' else values[:, :3] @ rotation.T
                if semantic == 'POSITION':
                    adjusted[:, 1] += grip_y
                accessor = scene.j['accessors'][index]
                view = scene.j['bufferViews'][accessor['bufferView']]
                assert accessor['componentType'] == 5126
                offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
                target = np.ndarray(adjusted.shape, dtype='<f4', buffer=blob, offset=offset,
                                    strides=(view.get('byteStride', adjusted.shape[1] * 4), 4))
                target[:] = adjusted
                if semantic == 'POSITION':
                    accessor['min'], accessor['max'] = adjusted.min(0).tolist(), adjusted.max(0).tolist()
    scene.bin = bytes(blob)
    scene.j['asset'].setdefault('extras', {})['wenfeng_one_hand_grip'] = {
        'source_handle_center': center.tolist(), 'source_to_runtime_rotation': rotation.tolist(),
        'scale': scale, 'handle_center': [0., grip_y, 0.], 'tip_y': 100.,
    }


def prepare_weapons(characters=None):
    selected = set(CHARACTERS if characters is None else characters)
    if selected.intersection({'zhaoyun', 'machao'}):
        selected.add('zhangfei')
    weapons = GAME / 'assets/weapons'
    weapons.mkdir(exist_ok=True)
    for character, name, file, center in [
            ('guanyu', 'guandao', '青龙刀.glb', (-0.02490234375, 0.0029296875)),
            ('zhangfei', 'serpent_spear', '丈八蛇矛.glb', (-0.034423828125, -0.019287109375)),
            ('lubu', 'halberd', '方天画戟.glb', (0., -0.00390625))]:
        if character not in selected:
            continue
        scene = GLB(ASSETS / 'weapons' / file)
        center_weapon_shaft(scene, center)
        if name == 'serpent_spear':
            refine_polearm_head(scene, 0.713, 0.705, (0.70, 0.70, 0.48), (0.36, 0.395))
        write_glb(weapons / (name + '.glb'), scene.j, resize_images(scene.j, scene.bin, 1024))
    for character, center in [('zhaoyun', (0.0751953125, 0.)),
                              ('machao', (0.1162109375, 0.0146484375))]:
        if character not in selected:
            continue
        name = character + '_spear'
        scene = GLB(ASSETS / 'weapons' / (name + '.glb'))
        normalize_horizontal_spear(scene, center)
        refine_polearm_head(scene, 0.82 if character == 'zhaoyun' else 0.775,
                           0.78 if character == 'zhaoyun' else 0.774, (0.65, 0.65, 0.65), (0.42, 0.60))
        write_glb(weapons / (name + '.glb'), scene.j, resize_images(scene.j, scene.bin, 1024))
    if 'xuchu' in selected:
        scene = GLB(ASSETS / 'weapons/刀-许褚.glb')
        normalize_xuchu_saber(scene)
        write_glb(weapons / 'xuchu_saber.glb', scene.j,
                  resize_images(scene.j, scene.bin, 1024, normal_maximum=512))
    if characters is None:
        saber = GLB(ASSETS / 'weapons/onehand_saber.glb')
        center_weapon_shaft(saber, (-5.7, 0.))
        write_glb(GAME / 'onehand_saber.glb', saber.j, resize_images(saber.j, saber.bin, 512))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--weapons-only', action='store_true', help='Prepare weapon geometry/textures without rebaking character animations')
    parser.add_argument('--characters', nargs='+', choices=CHARACTERS,
                        help='Rebake only selected characters and their corresponding weapons')
    args = parser.parse_args()
    if args.weapons_only:
        prepare_weapons(args.characters)
        return
    sources = {key: Sampler(KAY / ('Rig_Medium_' + name + '.glb')) for key, name in [
        ('melee', 'CombatMelee'), ('general', 'General'), ('basic', 'MovementBasic'), ('advanced', 'MovementAdvanced')]}
    fingers = Sampler(ASSETS / 'animations/ual1/UAL1_Standard.glb')
    manifest_path = GAME / 'assets/characters/animation_manifest.json'
    manifest = json.loads(manifest_path.read_text())
    for character in args.characters or CHARACTERS:
        file, _ = CHARACTERS[character]
        manifest[character] = bake(character, file, sources, fingers)
    prepare_weapons(args.characters)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
