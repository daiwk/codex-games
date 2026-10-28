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
import re
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.spatial.transform import Rotation as R, Slerp
from scipy.ndimage import gaussian_filter1d

from gltf_tools import GLB, compact_buffers, write_glb
from signature_motion import SIGNATURES, DUEL_NORMALS, sample_signature

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


def library_mapping(library):
    if library != 'ual2':
        return body_mapping()
    names = {'Hips': 'pelvis', 'Spine': 'spine_01', 'Spine1': 'spine_02',
             'Spine2': 'spine_03', 'Neck': 'neck_01', 'Head': 'Head'}
    for side, suffix in [('Left', 'l'), ('Right', 'r')]:
        names.update({side + part: bone + '_' + suffix for part, bone in [
            ('Shoulder', 'clavicle'), ('Arm', 'upperarm'), ('ForeArm', 'lowerarm'),
            ('Hand', 'hand'), ('UpLeg', 'thigh'), ('Leg', 'calf'), ('Foot', 'foot'),
            ('ToeBase', 'ball'), ('Toe_End', 'ball_leaf')]})
    return {'mixamorig:' + name: bone for name, bone in names.items()}


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
        'Attack3': ('melee', 'Melee_2H_Attack_Spinning'),
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
                         RPGSpin=('melee', 'Melee_2H_Attack_Spinning'),
                         RPGFinish=('melee', 'Melee_2H_Attack_Spinning'))
        else:
            clips.update({alias: ('melee', 'Melee_2H_Attack_Stab') for alias in
                          ['TigerThrust', 'TigerFinish', 'TigerSweep', 'TigerSlam']})
            clips.update(TigerRoar=('melee', 'Melee_2H_Idle'),
                         TigerCharge=('melee', 'Melee_2H_Idle'))
    elif character == 'guanyu':
        clips.update(CrescentSweep=('melee', 'Melee_2H_Attack_Spinning'),
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
        clips.update(HalberdSweep=('melee', 'Melee_2H_Attack_Spinning'),
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
        if np.dot(a, b) > 0:
            return R.identity()
        basis = np.eye(3)[np.argmin(np.abs(a))]
        pole = np.cross(a, basis)
        pole /= np.linalg.norm(pole)
        return R.from_rotvec(pole * np.pi)
    return R.from_rotvec(cross / sine * np.arctan2(sine, np.dot(a, b)))


def projected_twist(rotation, axis):
    """Swing/twist decomposition in the same coordinate frame as axis."""
    q = rotation.as_quat()
    projected = axis * np.dot(q[:3], axis)
    value = np.r_[projected, q[3]]
    if np.linalg.norm(value) < 1e-8:
        return R.identity()
    value /= np.linalg.norm(value)
    if value[3] < 0:
        value = -value
    return R.from_quat(value)


def fit_polearm_hands(target, pose, axis, hand_rotations, palms, history=None, _reach=.90, sides=None, _centre=None):
    """Jointly solve the grasp with natural wrists and continuous arm frames.

    Cylinder roll and a bounded rest-relative wrist cone leave each forearm
    orientation free. Its elbow is C + shaft_offset - palm_offset - forearm.
    The upper-arm length puts C on a sphere; two hands share its intersection
    circle. Evaluate authored and previous physical centres without changing
    bone lengths or accepting an elbow/axial-roll branch jump.
    """
    sides = sides or ['Right', 'Left']
    world = target.world(pose)
    spacing = .09 if len(sides) == 2 else 0.0
    wanted = sum(world[target.names['mixamorig:' + side + 'Hand']][0] +
                 world[target.names['mixamorig:' + side + 'Hand']][1].apply(palms[side.lower()])
                 for side in sides) / len(sides)
    if history and '_centre' in history:
        wanted = wanted * .85 + history['_centre'] * .15
    arms = {}
    for side in sides:
        a, e, h = [target.names['mixamorig:' + side + part] for part in ['Arm', 'ForeArm', 'Hand']]
        shoulder, elbow, wrist = [world[node][0] for node in [a, e, h]]
        rest = R.from_quat(target.nodes[h].get('rotation', [0., 0., 0., 1.]))
        bone_axis = np.asarray(target.nodes[h]['translation']); bone_axis /= np.linalg.norm(bone_axis)
        arms[side] = dict(a=a, e=e, h=h, shoulder=shoulder, elbow=elbow, rest=rest,
                          axis=bone_axis, l1=np.linalg.norm(elbow - shoulder),
                          l2=np.linalg.norm(wrist - elbow), sign=-1 if side == 'Right' else 1)

    def batch_between(origin, destination):
        origin = np.broadcast_to(origin, destination.shape).copy()
        origin /= np.linalg.norm(origin, axis=1)[:, None]
        destination = destination / np.linalg.norm(destination, axis=1)[:, None]
        dot = np.einsum('ij,ij->i', origin, destination)
        q = np.c_[np.cross(origin, destination), 1. + dot]
        bad = np.linalg.norm(q, axis=1) < 1e-7
        if bad.any():
            for i in np.flatnonzero(bad):
                basis = np.eye(3)[np.argmin(np.abs(origin[i]))]
                pole = np.cross(origin[i], basis); pole /= np.linalg.norm(pole)
                q[i] = np.r_[pole, 0.]
        q /= np.linalg.norm(q, axis=1)[:, None]
        return R.from_quat(q)

    def safe_wrist(local, arm):
        delta = local * arm['rest'].inv()
        q = delta.as_quat(); projection = q[:, :3] @ arm['axis']
        twist_q = np.c_[projection[:, None] * arm['axis'], q[:, 3]]
        n = np.linalg.norm(twist_q, axis=1)
        twist_q[n < 1e-8] = [0., 0., 0., 1.]; n[n < 1e-8] = 1.
        twist = R.from_quat(twist_q / n[:, None])
        swing = delta * twist.inv()
        rv = swing.as_rotvec(); angle = np.linalg.norm(rv, axis=1)
        rv *= np.minimum(1., np.deg2rad(34.) / np.maximum(angle, 1e-8))[:, None]
        tq = twist.as_quat(); signed = 2. * np.arctan2(tq[:, :3] @ arm['axis'], tq[:, 3])
        signed = (signed + np.pi) % (2. * np.pi) - np.pi
        return R.from_rotvec(rv) * R.from_rotvec(arm['axis'][None, :] * np.clip(signed, -np.deg2rad(29.), np.deg2rad(29.))[:, None]) * arm['rest']

    def candidates(degrees, relaxed=False):
        count = len(next(iter(degrees.values()))) if isinstance(degrees, dict) else len(degrees)
        data = {}
        for side, arm in arms.items():
            side_degrees = degrees[side] if isinstance(degrees, dict) else degrees
            roll = R.from_rotvec(axis[None, :] * np.deg2rad(side_degrees)[:, None])
            hand = roll * hand_rotations[side]
            wrist = R.from_quat(np.broadcast_to(arm['rest'].as_quat(), (count, 4)))
            wrists = [wrist]
            if relaxed and history and side + '_fore_world' in history:
                old_wrist = history[side + '_hand']
                old = R.from_quat(np.broadcast_to(old_wrist.as_quat(), (count, 4)))
                wanted_wrist = safe_wrist(history[side + '_fore_world'].inv() * hand, arm)
                delta = old.inv() * wanted_wrist
                step = np.minimum(1., np.deg2rad(float(history.get('_roll_rate', 195.)) * .98 * float(history.get('_step_seconds', 1. / 30.))) / np.maximum(delta.magnitude(), 1e-8))
                wrists.extend([old, old * R.from_rotvec(delta.as_rotvec() * step[:, None]), old * R.from_rotvec(delta.as_rotvec() * step[:, None] * .5)])
            hand = R.from_quat(np.repeat(hand.as_quat(), len(wrists), axis=0))
            wrist = R.from_quat(np.stack([w.as_quat() for w in wrists], axis=1).reshape(-1, 4))
            fore = hand * wrist.inv()
            forward = fore.apply(arm['axis'])
            offset = hand.apply(palms[side.lower()])
            anchor = arm['shoulder'] - axis * spacing * arm['sign'] + offset + forward * arm['l2']
            data[side] = dict(hand=hand, wrist=wrist, fore=fore, forward=forward, offset=offset, anchor=anchor)
        count = len(data[sides[0]]['forward'])
        if len(sides) == 1:
            side = sides[0]; arm = arms[side]
            anchor = data[side]['anchor']; toward = wanted - anchor
            norms = np.linalg.norm(toward, axis=1)
            toward[norms < 1e-7] = np.array([0., 0., 1.]); norms[norms < 1e-7] = 1.
            directions = toward / norms[:, None]
            centres = anchor + directions * arm['l1']
            indices = {side: np.arange(count)}
            valid = np.ones(count, dtype=bool)
            if history and side + '_upper_world' in history:
                previous = history[side + '_upper_world'].apply(np.asarray(target.nodes[arm['e']]['translation']))
                previous /= np.linalg.norm(previous)
                points = [centres]
                for amount in [0., .25, .5, .75]:
                    direction = previous[None, :] * (1. - amount) + directions * amount
                    direction /= np.maximum(np.linalg.norm(direction, axis=1)[:, None], 1e-8)
                    points.append(anchor + direction * arm['l1'])
                centres = np.concatenate(points)
                indices = {side: np.tile(np.arange(count), len(points))}
                valid = np.ones(len(centres), dtype=bool)
        else:
            right, left = 'Right', 'Left'
            ir = np.repeat(np.arange(count), count); il = np.tile(np.arange(count), count)
            indices = {right: ir, left: il}
            ar = data[right]['anchor'][ir]; al = data[left]['anchor'][il]
            delta = al - ar; distance = np.linalg.norm(delta, axis=1)
            l1r, l1l = arms[right]['l1'], arms[left]['l1']
            valid = (distance > abs(l1r - l1l) + 1e-6) & (distance < l1r + l1l - 1e-6)
            direction = delta / np.maximum(distance[:, None], 1e-7)
            along = (l1r*l1r - l1l*l1l + distance*distance) / np.maximum(2. * distance, 1e-7)
            circle = ar + direction * along[:, None]
            radius = np.sqrt(np.maximum(0., l1r*l1r - along*along))
            toward = wanted - circle
            toward -= direction * np.einsum('ij,ij->i', toward, direction)[:, None]
            norms = np.linalg.norm(toward, axis=1)
            for i in np.flatnonzero(norms < 1e-7):
                basis = np.eye(3)[np.argmin(np.abs(direction[i]))]
                toward[i] = np.cross(direction[i], basis); norms[i] = np.linalg.norm(toward[i])
            centres = circle + toward / norms[:, None] * radius[:, None]
            if history and '_centre' in history:
                previous = history['_centre'] - circle
                previous -= direction * np.einsum('ij,ij->i', previous, direction)[:, None]
                norms = np.linalg.norm(previous, axis=1)
                previous[norms < 1e-8] = toward[norms < 1e-8]
                norms = np.linalg.norm(previous, axis=1)
                previous /= np.maximum(norms[:, None], 1e-8)
                tangent = np.cross(direction, previous)
                points = [centres]
                for angle in [-16., -8., 0., 8., 16.]:
                    theta = np.deg2rad(angle)
                    points.append(circle + radius[:, None] * (previous * np.cos(theta) + tangent * np.sin(theta)))
                centres = np.concatenate(points)
                valid = np.tile(valid, len(points))
                indices = {side: np.tile(idx, len(points)) for side, idx in indices.items()}
        scores = np.sum((centres - wanted)**2, axis=1) * 150.
        debug = [('intersection', int(valid.sum()))]
        solved = {}
        for side, arm in arms.items():
            idx = indices[side]; d = data[side]
            hand = d['hand'][idx]; fore = d['fore'][idx]
            wrist = centres + axis * spacing * arm['sign'] - d['offset'][idx]
            elbow = wrist - d['forward'][idx] * arm['l2']
            previous_upper = history.get(side + '_upper_world') if history else None
            previous_fore = history.get(side + '_fore_world') if history else None
            upper_before = previous_upper if previous_upper is not None else world[arm['a']][1]
            upper_axis = np.asarray(target.nodes[arm['e']]['translation'])
            upper = batch_between(upper_before.apply(upper_axis), elbow - arm['shoulder']) * upper_before
            local_upper = world[target.parents[arm['a']]][1].inv() * upper
            local_fore = upper.inv() * fore
            scores += np.sum((elbow - arm['elbow'])**2, axis=1) * 2.
            if history:
                for part, local in [('upper', local_upper), ('fore', local_fore), ('hand', d['wrist'][idx])]:
                    previous = history.get(side + '_' + part)
                    if previous is not None:
                        change = (previous.inv() * local).magnitude()
                        if history.get('_enforce_continuity', True):
                            budget = np.deg2rad((float(history.get('_roll_rate', 195.)) if part == 'hand' else 1200.) * float(history.get('_step_seconds', 1. / 30.)))
                            minimum = np.rad2deg(change[valid].min()) if valid.any() else -1.
                            valid &= change <= budget
                            debug.append((side+part, int(valid.sum()), float(minimum)))
                        scores += change**2 * .08
                        if history.get('_enforce_continuity', True): scores += (change / max(budget, 1e-8))**4 * .15
                if previous_fore is not None:
                    old_axis = previous_fore.apply(arm['axis'])
                    current_axis = d['forward'][idx]
                    transported = batch_between(old_axis, current_axis) * previous_fore
                    delta_rot = fore * transported.inv()
                    q = delta_rot.as_quat()
                    signed = 2. * np.arctan2(np.einsum('ij,ij->i', q[:, :3], current_axis), q[:, 3])
                    signed = (signed + np.pi) % (2. * np.pi) - np.pi
                    if history.get('_enforce_continuity', True):
                        minimum = np.rad2deg(np.abs(signed)[valid].min()) if valid.any() else -1.
                        valid &= np.abs(signed) <= np.deg2rad(float(history.get('_roll_rate', 195.)) * float(history.get('_step_seconds', 1. / 30.)))
                        debug.append((side+'roll', int(valid.sum()), float(minimum)))
                    scores += signed**2 * .3
                    roll_budget = np.deg2rad(float(history.get('_roll_rate', 195.)) * float(history.get('_step_seconds', 1. / 30.)))
                    scores += (signed / max(roll_budget, 1e-8))**4 * .3
            solved[side] = (local_upper, local_fore, upper, fore, hand, elbow, d['wrist'][idx])
        scores[~valid] = np.inf
        best = int(np.argmin(scores))
        if not np.isfinite(scores[best]):
            if history is not None: history['_last_debug'] = debug
            return None
        return scores[best], best, centres, solved

    selected = None
    if history and all(side + '_fore_world' in history for side in sides):
        nearby = {}
        for side, arm in arms.items():
            previous_hand = history[side + '_fore_world'] * history[side + '_hand']
            roll_delta = projected_twist(previous_hand * hand_rotations[side].inv(), axis)
            centre_roll = np.rad2deg(np.dot(roll_delta.as_rotvec(), axis))
            nearby[side] = centre_roll + np.arange(-10., 10.1, 2.)
        selected = candidates(nearby, relaxed=True)
    if selected is None:
        selected = candidates(np.arange(-180., 180., 8.), relaxed=True)
    if selected is None and history and '_centre' in history:
        # Stay near the preceding *physical centre*, while still solving the
        # current authored rod axis and exact arm spheres. This is a new
        # continuous IK pose, rather than freezing the previous local arms.
        wanted = history['_centre'] * .85 + wanted * .15
        selected = candidates(np.arange(-180., 180., 8.), relaxed=True)
    if selected is None:
        return False
    _, index, centres, solved = selected
    for side, arm in arms.items():
        local_upper, local_fore, upper, fore, hand, elbow, wrist = solved[side]
        pose[arm['a']][1] = local_upper[index].as_quat()
        pose[arm['e']][1] = local_fore[index].as_quat()
        pose[arm['h']][1] = wrist[index].as_quat()
        if history is not None:
            history[side + '_upper'] = local_upper[index]
            history[side + '_fore'] = local_fore[index]
            history[side + '_hand'] = wrist[index]
            history[side + '_upper_world'] = upper[index]
            history[side + '_fore_world'] = fore[index]
            history[side + '_elbow'] = elbow[index]
    if history is not None: history['_centre'] = centres[index].copy()
    return True


def read_skill_profiles():
    text = (ROOT / 'godot/scripts/skill_profiles.gd').read_text()
    result = {}
    for name, body in re.findall(r'const (\w+) = (\{.*?\})\n\n', text, re.S):
        result[name.lower()] = json.loads(re.sub(r'Vector2\(([^)]+)\)', r'[\1]', body))
    return result


def grasp_active_windows(character, metrics):
    result = {}
    def add(alias, start, duration, active):
        if alias not in metrics: return
        scale = metrics[alias]['seconds'] / duration
        result.setdefault(alias, []).append(((active[0] - start) * scale, (active[1] - start) * scale))
    profiles = read_skill_profiles()
    owners = [character] + (['guanyu', 'lubu'] if character == 'zhaoyun' else [])
    for owner in owners:
        for kind, data in profiles.get(owner, {}).items():
            if data.get('hits'):
                for hit in data['hits']: add(hit['clip'], hit['start'], hit['clip_duration'], hit['active'])
            elif data['kind'] == 'evade': add(data['strike_clip'], data['strike_start'], .5, data['active'])
            elif data.get('stages'):
                stage = max((stage for stage in data['stages'] if stage['start'] <= data['active'][0]), key=lambda stage: stage['start'])
                add(stage['clip'], stage['start'], stage['duration'], data['active'])
            else: add(data['clip'], 0., data['duration'], data['active'])
    normal = [(.94, [.15,.28]), (1.04,[.37,.50]), (1.24,[.60,.80]), (1.4,[.72,.88])] if character == 'xuchu' else \
             [(.90,[.19,.39]), (1.,[.21,.43]), (1.14,[.24,.49]), (1.4,[.29,.60])] if character in ['zhaoyun','machao','zhangfei'] else \
             [(.98,[.32,.54]), (1.10,[.35,.61]), (1.34,[.42,.80]), (1.48,[.48,.83])]
    for alias, (duration, active) in zip(['Attack1','Attack2','Attack3','Heavy'], normal): add(alias,0.,duration,active)
    for alias, (duration, active) in zip(DUEL_NORMALS.get(character, {}), normal): add(alias, 0., duration, active)
    for alias,duration,active in [('RPGSlash',.98,[.32,.54]),('RPGChop',1.10,[.35,.61]),('RPGSpin',1.34,[.42,.80]),('RPGChop',1.48,[.48,.83])]: add(alias,0.,duration,active)
    return result


def grasp_playback_rates(character, clips, sources, signatures):
    """Use the real shared profile clocks, so a source-second limit is honest.

    The final forearm-roll budget is 870 degrees per game second, leaving
    margin beneath the independent 900 degree/sec check. Ordinary attack
    tempo has a bounded 2.35/1.90 maximum clock derivative.
    """
    profiles = read_skill_profiles()
    rates = {alias: 0. for alias in clips}
    def add(alias, seconds, factor=1.):
        if alias not in clips or seconds <= 0.: return
        library, source = clips[alias]
        spec = signatures.get(alias)
        length = spec['crop'][1] - spec['crop'][0] if spec and spec['crop'] else sources[library].duration(source)
        rates[alias] = max(rates.get(alias, 0.), length / seconds * factor)
    owners = [character] + (['guanyu', 'lubu'] if character == 'zhaoyun' else [])
    for owner in owners:
        for kind, skill in profiles.get(owner, {}).items():
            if skill.get('stages'):
                for stage in skill['stages']: add(stage['clip'], stage['duration'])
            elif kind != 'ultimate': add(skill['clip'], .4 if skill['kind'] == 'evade' else skill['duration'])
            for hit in skill.get('hits', []): add(hit['clip'], hit['clip_duration'])
            if skill.get('strike_clip'): add(skill['strike_clip'], .5)
            if skill.get('charge_clip'): add(skill['charge_clip'], skill['windup'])
    normal = [(.94, 1.9), (1.04, 1.9), (1.24, 1.9), (1.4, 2.35)] if character == 'xuchu' else \
             [(.90, 1.9), (1., 1.9), (1.14, 1.9), (1.4, 2.35)] if character in ['zhaoyun', 'machao', 'zhangfei'] else \
             [(.98, 1.9), (1.10, 1.9), (1.34, 1.9), (1.48, 2.35)]
    for alias, (seconds, factor) in zip(['Attack1', 'Attack2', 'Attack3', 'Heavy'], normal): add(alias, seconds, factor)
    for alias, (seconds, factor) in zip(DUEL_NORMALS.get(character, {}), normal): add(alias, seconds, factor)
    for alias, seconds, factor in [('RPGSlash', .98, 1.9), ('RPGChop', 1.1, 2.35), ('RPGSpin', 1.34, 1.9), ('RPGFinish', .65, 1.)]: add(alias, seconds, factor)
    return {alias: max(rate, .001) if rate > 0. else 1.5 for alias, rate in rates.items()}


def bake(character, source_name, sources, finger_source, only_aliases=None, destination=None):
    one_hand = character == 'xuchu'
    target = GLB(ASSETS / source_name)
    bind, rest = target.pose()
    skin = target.j['skins'][0]
    matrices = target.accessor(skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
    assert np.isfinite(matrices).all() and np.abs(matrices).max() < 100, 'Invalid supplied bind matrices'
    out, blob = deepcopy(target.j), bytearray(target.bin)
    out['animations'] = []
    pairs = {key: {target.names[a]: src.names[b] for a, b in library_mapping(key).items()
                   if a in target.names and b in src.names} for key, src in sources.items()}
    refs = {key: src.pose('A_TPose' if key == 'ual2' else 'T-Pose')[0] for key, src in sources.items()}
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
    ready_grip_history = {}
    baked_cache = {}
    hold_upper = {'Walk', 'WalkBack', 'StrafeLeft', 'StrafeRight', 'Run', 'TurnLeft', 'TurnRight',
                  'Dodge', 'CrescentStep', 'CloudStep'}
    gait_clips = {'Walk', 'WalkBack', 'StrafeLeft', 'StrafeRight', 'Run', 'TurnLeft', 'TurnRight'}
    clips = clip_set(character)
    signatures = SIGNATURES.get(character, {})
    clips.update({alias: (spec['library'], spec['source']) for alias, spec in signatures.items()})
    if only_aliases is not None:
        clips = {alias: clip for alias, clip in clips.items() if alias == 'Idle' or alias in only_aliases}
    playback_rates = grasp_playback_rates(character, clips, sources, signatures)
    shared_rates = {}
    for alias, (library, authored) in clips.items():
        key = (library, authored, json.dumps(signatures.get(alias), sort_keys=True), alias in hold_upper, alias in gait_clips)
        shared_rates[key] = max(shared_rates.get(key, 0.), playback_rates[alias])
    for alias, (library, authored) in clips.items():
        key = (library, authored, json.dumps(signatures.get(alias), sort_keys=True), alias in hold_upper, alias in gait_clips)
        playback_rates[alias] = shared_rates[key]
    for alias, (library, authored) in clips.items():
        src, pair = sources[library], pairs[library]
        signature = signatures.get(alias)
        cache_key = (library, authored, json.dumps(signature, sort_keys=True),
                     alias in hold_upper, alias in gait_clips, round(playback_rates[alias], 6))
        if cache_key in baked_cache:
            cached_animation, cached_metrics = baked_cache[cache_key]
            animation = deepcopy(cached_animation)
            animation['name'] = alias
            out['animations'].append(animation)
            metrics[alias] = deepcopy(cached_metrics)
            print(character, alias, authored, '(shared immutable pose accessors)', flush=True)
            continue
        duration = (signature['crop'][1] - signature['crop'][0]) if signature and signature['crop'] else src.duration(authored)
        times = np.linspace(0, duration, max(2, round(duration * 30) + 1))
        rotations = {t: [] for t in set(pair) | set(finger_offsets)}
        translations = []
        grip_history = dict(ready_grip_history)
        grip_history['_step_seconds'] = duration / max(1, len(times) - 1)
        grip_history['_roll_rate'] = 870. / playback_rates[alias]
        held_grip_times = []
        source_worlds = [sample_signature(signature, sources, time, duration) if signature else src.pose(authored, time)[0] for time in times]
        upper_worlds = None
        if signature and signature.get('upper_source'):
            upper_spec = dict(signature)
            upper_library, upper_clip = signature['upper_source']
            upper_spec.update(library=upper_library, source=upper_clip, crop=None)
            upper_worlds = [sample_signature(upper_spec, sources, time, duration) for time in times]
        cut_motion = ('Attack' in authored and authored != 'Melee_2H_Attack_Stab') or authored == 'Sword_Dash'
        smoothed_weapon = None
        prospective = {name: {'seconds': (spec['crop'][1] - spec['crop'][0]) if spec and spec['crop'] else sources[lib].duration(source)} for name, (lib, source) in clips.items() for spec in [signatures.get(name)]}
        current_windows = grasp_active_windows(character, prospective).get(alias, [])
        if cut_motion:
            # CC0 sword clips contain near-instant socket turns (up to 57
            # degrees in one 30 Hz key). Spread that whip over 80 ms of real
            # action time; preserve its direction/arc and never hold a pose.
            values = []
            for index, frame in enumerate(source_worlds):
                rotation = frame[src.names['hand_r']][1] * R.from_euler('x', 90, degrees=True) if library == 'ual2' else frame[src.names['handslot.r']][1]
                if upper_worlds is not None: rotation = upper_worlds[index][sources[upper_library].names['handslot.r']][1]
                q = rotation.as_quat()
                if values and np.dot(values[-1], q) < 0.: q = -q
                values.append(q)
            sigma = min(14., max(1., .080 * playback_rates[alias] / grip_history['_step_seconds']))
            smooth = gaussian_filter1d(np.asarray(values), sigma, axis=0, mode='nearest')
            smooth /= np.linalg.norm(smooth, axis=1)[:, None]
            smoothed_weapon = R.from_quat(smooth)
        for frame_index, time in enumerate(times):
            grip_history['_enforce_continuity'] = bool(time > 1e-8)
            world = source_worlds[frame_index]
            if authored == 'Melee_2H_Attack_Stab' and time < .25:
                # The source's first two sword-stance keys turn the socket
                # sharply across the body. Join the supplied ready elbow
                # branch during anticipation, before every physical hit band.
                # At source time .25 and throughout contact this is identity.
                ready = sources['melee'].pose('Melee_2H_Idle', 0.0)[0]
                progress = np.clip(time / .25, 0., 1.)
                amount = progress * progress * (3. - 2. * progress)
                for name, node in src.names.items():
                    if name.startswith(('upperarm.', 'lowerarm.', 'wrist.', 'hand.', 'handslot.')) or name in ['spine', 'chest', 'head']:
                        rn = sources['melee'].names.get(name)
                        if rn is not None:
                            neutral = ready[rn][1]
                            delta_rotation = neutral.inv() * world[node][1]
                            world[node] = (world[node][0], neutral * R.from_rotvec(delta_rotation.as_rotvec() * amount))
            if alias in hold_upper:
                idle_name = 'Melee_Blocking' if one_hand else 'Melee_2H_Idle'
                idle = sources['melee'].pose(idle_name, time % sources['melee'].duration(idle_name))[0]
                # Preserve the ready weapon posture, but let some of the
                # author's shoulder/chest counter-swing survive the stride.
                # Previously every upper-body joint was frozen in idle world
                # space, making a moving warrior look rigid from the waist up.
                # The weapon socket uses the identical blend before the arm IK,
                # so both palms and the long shaft stay in the same pose.
                upper_gait_weight = 0.16 if alias in gait_clips else 0.0
                for name, node in src.names.items():
                    if name.startswith(('upperarm.', 'lowerarm.', 'wrist.', 'hand.', 'handslot.')) or name in ['chest', 'head']:
                        if name in sources['melee'].names:
                            idle_position, idle_rotation = idle[sources['melee'].names[name]]
                            gait_position, gait_rotation = world[node]
                            delta_rotation = idle_rotation.inv() * gait_rotation
                            world[node] = (
                                idle_position * (1. - upper_gait_weight) + gait_position * upper_gait_weight,
                                idle_rotation * R.from_rotvec(delta_rotation.as_rotvec() * upper_gait_weight))
            desired = {t: world[s][1] * correction[library][t] for t, s in pair.items()}
            if upper_worlds is not None:
                for node, source_node in pairs[upper_library].items():
                    name = target.nodes[node].get('name', '')
                    if any(part in name for part in ['Spine','Neck','Head','Arm','Hand']):
                        desired[node] = upper_worlds[frame_index][source_node][1] * correction[upper_library][node]
                for side in ['Left','Right']:
                    desired.pop(target.names.get('mixamorig:' + side + 'Shoulder'), None)
            if one_hand:
                # KayKit animates mitten-hand nodes between wrist and weapon
                # socket. Carry that authored sword orientation into our wrist
                # rather than dropping those nodes during skeleton mapping.
                right_hand = target.names['mixamorig:RightHand']
                weapon_rotation = (smoothed_weapon[frame_index] if smoothed_weapon is not None else
                                   world[src.names['hand_r']][1] * R.from_euler('x', 90, degrees=True)
                                   if library == 'ual2' else world[src.names['handslot.r']][1])
                desired[right_hand] = weapon_rotation * grip_rotations['Right'].inv()
            for t, (hand, relative) in finger_offsets.items():
                desired[t] = desired[hand] * relative
            pose, global_rotations = {}, {}
            for t in target.order:
                parent = target.parents.get(t)
                pr = global_rotations[parent] if parent is not None else R.identity()
                wr = desired.get(t, pr * R.from_quat(rest[t][1]))
                pose[t] = [rest[t][0].copy(), (pr.inv() * wr).as_quat()]
                global_rotations[t] = wr
            src_hip = src.names['pelvis' if library == 'ual2' else 'hips']
            ratio = bind[hips][0][1] / refs[library][src_hip][0][1]
            delta = (world[src_hip][0] - refs[library][src_hip][0]) * ratio
            pose[hips][0] += delta
            if alias != 'Death':
                pose[hips][0][[0, 2]] = rest[hips][0][[0, 2]] + np.clip(delta[[0, 2]], -0.10, 0.10)
                grounded = target.world(pose)
                pose[hips][0][1] += floor - min(grounded[t][0][1] for t in feet)
            if one_hand:
                axis = weapon_rotation.apply([0., 1., 0.])
                grip_ok = fit_polearm_hands(target, pose, axis, {'Right': desired[right_hand]}, palms, grip_history, sides=['Right'])
            else:
                weapon_rotation = smoothed_weapon[frame_index] if smoothed_weapon is not None else world[src.names['handslot.r']][1]
                axis = weapon_rotation.apply([0., 1., 0.])
                hand_rotations = {side: weapon_rotation * grip_rotations[side].inv() for side in ['Left', 'Right']}
                grip_ok = fit_polearm_hands(target, pose, axis, hand_rotations, palms, grip_history)
            if not grip_ok:
                # A physical grip cannot cross to the other elbow-circle
                # branch in one key. Brief non-contact bracing preserves
                # the preceding physical forearm/palm world orientations,
                # without inheriting the chest's axial turn. Damage still tests
                # the resulting real blade, never the requested source pose.
                assert grip_history, 'No anatomical initial grip: ' + character + '/' + alias
                assert not any(lo - 1e-6 <= time <= hi + 1e-6 for lo, hi in current_windows), 'Refusing active frozen grip: ' + character + '/' + alias + ' at ' + str(float(time)) + ' ' + str(grip_history.get('_last_debug'))
                held_grip_times.append(float(time))
                parents_world = target.world(pose)
                for side in (['Right'] if one_hand else ['Left', 'Right']):
                    a, e, h = [target.names['mixamorig:' + side + part] for part in ['Arm','ForeArm','Hand']]
                    upper = grip_history[side + '_upper_world']
                    fore = grip_history[side + '_fore_world']
                    hand = fore * grip_history[side + '_hand']
                    pose[a][1] = (parents_world[target.parents[a]][1].inv() * upper).as_quat()
                    pose[e][1] = (upper.inv() * fore).as_quat()
                    pose[h][1] = (fore.inv() * hand).as_quat()
                carried = target.world(pose)
                centres = []
                for side in (['Right'] if one_hand else ['Left', 'Right']):
                    a, e, h = [target.names['mixamorig:' + side + part] for part in ['Arm', 'ForeArm', 'Hand']]
                    grip_history[side + '_upper'] = R.from_quat(pose[a][1])
                    grip_history[side + '_fore'] = R.from_quat(pose[e][1])
                    grip_history[side + '_upper_world'] = carried[a][1]
                    grip_history[side + '_fore_world'] = carried[e][1]
                    grip_history[side + '_elbow'] = carried[e][0]
                    centres.append(carried[h][0] + carried[h][1].apply(palms[side.lower()]))
                grip_history['_centre'] = sum(centres) / len(centres)
            for t, values in rotations.items():
                q = pose[t][1]
                if values and np.dot(values[-1], q) < 0:
                    q = -q
                values.append(q)
            translations.append(pose[hips][0])
        if alias == 'Idle': ready_grip_history = dict(grip_history)
        animation = {'name': alias, 'samplers': [], 'channels': []}
        time_accessor = append(times.reshape(-1, 1), 'SCALAR')
        for t, values in rotations.items():
            animation['samplers'].append({'input': time_accessor, 'output': append(values, 'VEC4'), 'interpolation': 'LINEAR'})
            animation['channels'].append({'sampler': len(animation['samplers']) - 1, 'target': {'node': t, 'path': 'rotation'}})
        animation['samplers'].append({'input': time_accessor, 'output': append(translations, 'VEC3'), 'interpolation': 'LINEAR'})
        animation['channels'].append({'sampler': len(animation['samplers']) - 1, 'target': {'node': hips, 'path': 'translation'}})
        out['animations'].append(animation)
        metrics[alias] = {'source': authored, 'library': 'Quaternius UAL2 Standard CC0' if library == 'ual2' else 'KayKit Free 1.1', 'seconds': float(duration), 'samples': len(times)}
        if signature:
            metrics[alias]['signature'] = {'author': 'Wenfeng project', 'pose_keys': signature['keys'],
                                         'reverse': signature['reverse'], 'crop': signature['crop'],
                                         'method': 'Torso/whole-arm branch rotations, authored crouch blend and lateral weight shift; calibrated hand IK afterwards'}
            if signature.get('upper_source'): metrics[alias]['signature']['upper_source'] = signature['upper_source']
            if signature.get('stance'):
                metrics[alias]['signature'].update(stance_keys=signature['stance'],
                    weapon_axis_fixed=True, distributed_torso=True, scope='duel_foot_only',
                    method='Authored shoulder/hip counter-rotation, independent leg rotations and weight transfer; unchanged thrust axis; calibrated two-palm IK, original bone lengths')
        if authored == 'Melee_2H_Attack_Stab':
            metrics[alias]['grip_startup_blend_source_seconds'] = .25
        if cut_motion: metrics[alias]['weapon_socket_smoothing_gameplay_seconds'] = .080
        metrics[alias]['continuous_grip_hold_source_times'] = held_grip_times
        metrics[alias]['continuous_grip_limits_degrees_per_second'] = {'wrist_source': grip_history['_roll_rate'], 'arm_source': 1200., 'forearm_incremental_roll_source': grip_history['_roll_rate'], 'maximum_gameplay_rate': playback_rates[alias], 'forearm_incremental_roll_gameplay': 870.}
        if alias in gait_clips:
            metrics[alias]['authored_upper_body_weight'] = 0.16
        baked_cache[cache_key] = (animation, metrics[alias])
        print(character, alias, authored, flush=True)
    active_windows = grasp_active_windows(character, metrics)
    for alias, record in metrics.items():
        record['physical_active_source_windows'] = active_windows.get(alias, [])
        bad = [time for time in record['continuous_grip_hold_source_times'] if any(lo - 1e-6 <= time <= hi + 1e-6 for lo, hi in active_windows.get(alias, []))]
        assert not bad, 'Refusing active frozen grip: ' + character + '/' + alias + ' ' + str(bad)
    blob = compact_buffers(out, blob)
    blob = resize_images(out, blob, normal_maximum=512 if character in ('zhaoyun', 'machao', 'xuchu') else None)
    out['asset']['generator'] = 'Wenfeng: CC0 KayKit T-pose world-space retarget, closed-finger grip'
    destination = destination or GAME / ('assets/characters/' + character + '.glb')
    write_glb(destination, out, blob)
    grip = ({'mode': 'one_hand', 'rotation_xyzw': grip_rotations['Right'].as_quat().tolist(),
             'position': palms['right'], 'right_palm': palms['right'],
             'mesh_scale': 0.0058, 'mesh_grip_y': -0.075,
             'adaptation': 'Authored blade axis; bounded anatomical wrist, exact upper-arm sphere grasp and continuous forearm frame; exact bone lengths'} if one_hand else
            {'mode': 'two_hand', 'right_palm': palms['right'], 'left_palm': palms['left'],
             'weapon_length': CHARACTERS[character][1], 'grip_fraction': 0.35, 'axis_sign': -1.0,
             'adaptation': 'Authored weapon axis; bounded anatomical wrists, exact shared centre on two upper-arm spheres, continuous forearm frames; exact bone lengths'})
    record = {'source': {'file': source_name, 'sha256': hashlib.sha256(target.path.read_bytes()).hexdigest()},
              'clips': metrics, 'grip': grip}
    # Close only locomotion seams. Combat channels must retain the exact shared
    # palm/weapon path solved above; independently filtering arm bones changes it.
    if only_aliases is None:
        from refine_motion import refine_animations
        closed_scene, closed_binary, _ = refine_animations(GLB(destination), record)
        write_glb(destination, closed_scene, closed_binary)
    record['runtime_sha256'] = hashlib.sha256(destination.read_bytes()).hexdigest()
    return record


def append_duel_normals(character, source_name, sources, fingers, output_path=None):
    """Append only new animation buffers, preserving every old runtime byte.

    Shared/RPG clips, geometry, textures and binding remain unchanged even if
    an old preparation recipe has since evolved. Re-running replaces only the
    Duel aliases. A full bake remains available separately.
    """
    import tempfile
    aliases = DUEL_NORMALS.get(character, {})
    assert aliases, 'Duel foot polish is only authored for Zhao Yun and Ma Chao'
    destination = GAME / ('assets/characters/' + character + '.glb')
    baseline = GLB(destination)
    with tempfile.TemporaryDirectory(prefix='wenfeng-duel-motion-') as folder:
        generated_path = Path(folder) / (character + '.glb')
        record = bake(character, source_name, sources, fingers, set(aliases), generated_path)
        generated = GLB(generated_path)
        out = deepcopy(baseline.j)
        out['animations'] = [a for a in out['animations'] if a['name'] not in aliases]
        blob = bytearray(baseline.bin)
        copied = {}
        def copy_accessor(index):
            if index in copied: return copied[index]
            values = generated.accessor(index)
            blob.extend(b'\0' * (-len(blob) % 4))
            view = len(out['bufferViews'])
            out['bufferViews'].append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': values.nbytes})
            blob.extend(values.tobytes())
            accessor = deepcopy(generated.j['accessors'][index])
            accessor.update(bufferView=view, byteOffset=0)
            copied[index] = len(out['accessors'])
            out['accessors'].append(accessor)
            return copied[index]
        for alias in aliases:
            animation = deepcopy(generated.anims[alias])
            for sampler in animation['samplers']:
                sampler['input'] = copy_accessor(sampler['input'])
                sampler['output'] = copy_accessor(sampler['output'])
            out['animations'].append(animation)
        assert bytes(blob[:len(baseline.bin)]) == baseline.bin
        for alias, animation in baseline.anims.items():
            if alias not in aliases:
                assert next(a for a in out['animations'] if a['name'] == alias) == animation
        write_glb(output_path or destination, out, blob)
    record['preservation'] = {'existing_animation_count': len(baseline.anims) - len(set(baseline.anims) & set(aliases)),
                              'existing_binary_bytes_retained': len(baseline.bin), 'mode': 'append_only'}
    return record


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
    parser.add_argument('--duel-polish-only', action='store_true',
                        help='Append Duel-only foot attack clips; preserve every shared/RPG clip and all geometry/materials')
    args = parser.parse_args()
    selected = args.characters or (list(DUEL_NORMALS) if args.duel_polish_only else list(CHARACTERS))
    if args.duel_polish_only:
        if args.weapons_only:
            parser.error('--duel-polish-only and --weapons-only are separate preparation modes')
        unsupported = set(selected) - set(DUEL_NORMALS)
        if unsupported:
            parser.error('--duel-polish-only only supports: ' + ', '.join(DUEL_NORMALS))
    if args.weapons_only:
        prepare_weapons(args.characters)
        return
    sources = {key: Sampler(KAY / ('Rig_Medium_' + name + '.glb')) for key, name in [
        ('melee', 'CombatMelee'), ('general', 'General'), ('basic', 'MovementBasic'), ('advanced', 'MovementAdvanced')]}
    sources['ual2'] = Sampler(ASSETS / 'animations/ual2/UAL2_Standard.glb')
    fingers = Sampler(ASSETS / 'animations/ual1/UAL1_Standard.glb')
    manifest_path = GAME / 'assets/characters/animation_manifest.json'
    manifest = json.loads(manifest_path.read_text())
    if args.duel_polish_only:
        # Stage the entire requested set before publishing any runtime file.
        # A failed second rig cannot leave the first rig ahead of its manifest.
        import tempfile
        import os
        with tempfile.TemporaryDirectory(prefix='wenfeng-duel-stage-') as folder:
            pending = []
            for character in selected:
                file, _ = CHARACTERS[character]
                staged = Path(folder) / (character + '.glb')
                record = append_duel_normals(character, file, sources, fingers, staged)
                for alias in DUEL_NORMALS[character]:
                    manifest[character]['clips'][alias] = record['clips'][alias]
                manifest[character]['duel_foot_polish'] = record['preservation']
                manifest[character]['runtime_sha256'] = hashlib.sha256(staged.read_bytes()).hexdigest()
                pending.append((staged, GAME / ('assets/characters/' + character + '.glb')))
            staged_manifest = Path(folder) / 'animation_manifest.json'
            staged_manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
            for staged, destination in pending:
                os.replace(staged, destination)
            os.replace(staged_manifest, manifest_path)
        return
    for character in selected:
        file, _ = CHARACTERS[character]
        manifest[character] = bake(character, file, sources, fingers)
    prepare_weapons(args.characters)
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
