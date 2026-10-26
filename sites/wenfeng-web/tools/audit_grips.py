#!/usr/bin/env python3
"""Independently audit every exported key of the derived warrior grips.

Preparation-only numpy/scipy dependencies. The report checks the GLBs rather
than calling the production IK or trusting its angle/continuity results.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from scipy.spatial.transform import Rotation as R

from prepare_polearms import GAME, ROOT, Sampler, grasp_active_windows


def transport(a, b):
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
    axis = np.cross(a, b)
    length = np.linalg.norm(axis)
    dot = np.clip(a @ b, -1., 1.)
    if length < 1e-8:
        if dot > 0.: return R.identity()
        axis = np.cross(a, np.eye(3)[np.argmin(abs(a))])
        axis /= np.linalg.norm(axis)
        return R.from_rotvec(axis * np.pi)
    return R.from_rotvec(axis / length * np.arctan2(length, dot))


def audit(role, record, path, forearm_reference='upper_arm_local'):
    scene = Sampler(path)
    windows = grasp_active_windows(role, record['clips'])
    result = {'role': role, 'forearm_reference': forearm_reference, 'clips': [], 'failures': []}
    grip_frames = {}
    if record['grip'].get('mode') == 'two_hand':
        source = Sampler(ROOT/'source-assets/animations/ual1/UAL1_Standard.glb')
        reference = source.pose('A_TPose')[0]
        weapon = reference[source.names['hand_r']][1] * R.from_euler('x',90,degrees=True)
        bind = scene.pose()[0]; mirror = np.diag([-1.,1.,1.])
        for side in ['Right','Left']:
            hand = scene.names['mixamorig:'+side+'Hand']
            calibration = bind[hand][1].inv() * (weapon if side=='Right' else R.from_matrix(mirror@weapon.as_matrix()@mirror))
            grip_frames[side] = (hand,calibration,np.asarray(record['grip'][side.lower()+'_palm']))
    arms = []
    for side in (['Right'] if role == 'xuchu' else ['Right', 'Left']):
        h = scene.names['mixamorig:' + side + 'Hand']
        f = scene.parents[h]
        rest = R.from_quat(scene.nodes[h]['rotation'])
        axis = np.asarray(scene.nodes[h]['translation']); axis /= np.linalg.norm(axis)
        arms.append((side, f, h, rest, axis))
    for alias, animation in scene.anims.items():
        info = record['clips'][alias]
        held = info.get('continuous_grip_hold_source_times', [])
        active_held = [time for time in held if any(lo - 1e-6 <= time <= hi + 1e-6 for lo, hi in windows.get(alias, []))]
        rates = info.get('continuous_grip_limits_degrees_per_second', {})
        gameplay_rate = float(rates.get('maximum_gameplay_rate', 1.))
        if role == 'xuchu' and alias in ['Attack1','Attack2','Attack3','Heavy']:
            gameplay_rate /= .96  # fastest optional straight sword stat modifier
        row = {'clip': alias, 'maximum_gameplay_rate': gameplay_rate,
               'held_source_times': held, 'active_held_source_times': active_held,
               'active_source_windows': windows.get(alias, []),
               'wrist_swing_degrees': 0., 'wrist_twist_degrees': 0.,
               'forearm_roll_gameplay_degrees_per_second': 0.,
               'forearm_local_roll_gameplay_degrees_per_second': 0.,
               'forearm_world_roll_gameplay_degrees_per_second': 0.,
               'wrist_gameplay_degrees_per_second': 0., 'maximum_arm_local_key_delta': 0., 'grip_axis_error_degrees': 0.}
        for channel in animation['channels']:
            if channel['target']['path'] != 'rotation': continue
            name = scene.nodes[channel['target']['node']].get('name', '')
            if not name.endswith(('Arm', 'ForeArm', 'Hand')): continue
            sampler = animation['samplers'][channel['sampler']]
            rotations = R.from_quat(scene.accessor(sampler['output']))
            row['maximum_arm_local_key_delta'] = max(row['maximum_arm_local_key_delta'], float(np.degrees((rotations[:-1].inv() * rotations[1:]).magnitude()).max()))
        previous = {}
        for time in np.linspace(0., scene.duration(alias), info['samples']):
            world, pose = scene.pose(alias, time)
            if grip_frames:
                points={side:world[hand][0]+world[hand][1].apply(palm) for side,(hand,calibration,palm) in grip_frames.items()}
                shaft=points['Right']-points['Left'];shaft/=np.linalg.norm(shaft);shaft*=record['grip']['axis_sign']
                for side,(hand,calibration,palm) in grip_frames.items():
                    direction=(world[hand][1]*calibration).apply([0.,1.,0.])
                    row['grip_axis_error_degrees']=max(row['grip_axis_error_degrees'],float(np.degrees(np.arccos(np.clip(direction@shaft,-1.,1.)))))
            for side, f, h, rest, axis in arms:
                local = R.from_quat(pose[h][1])
                delta = local * rest.inv()
                q = delta.as_quat()
                projected = np.r_[axis * (q[:3] @ axis), q[3]]
                if np.linalg.norm(projected) < 1e-8: projected = np.array([0.,0.,0.,1.])
                twist = R.from_quat(projected / np.linalg.norm(projected))
                swing = delta * twist.inv()
                row['wrist_swing_degrees'] = max(row['wrist_swing_degrees'], float(np.degrees(swing.magnitude())))
                row['wrist_twist_degrees'] = max(row['wrist_twist_degrees'], float(np.degrees(twist.magnitude())))
                fore_local = R.from_quat(pose[f][1])
                fore_world = world[f][1]
                if side in previous:
                    old_local, old_world, old_wrist, old_time = previous[side]
                    dt = time - old_time
                    for label, old_fore, fore in [('local', old_local, fore_local), ('world', old_world, fore_world)]:
                        fore_axis = fore.apply(axis)
                        carried = transport(old_fore.apply(axis), fore_axis) * old_fore
                        q = (fore * carried.inv()).as_quat()
                        roll = (2. * np.arctan2(q[:3] @ fore_axis, q[3]) + np.pi) % (2. * np.pi) - np.pi
                        field = 'forearm_' + label + '_roll_gameplay_degrees_per_second'
                        row[field] = max(row[field], float(abs(np.degrees(roll)) / dt * gameplay_rate))
                    row['wrist_gameplay_degrees_per_second'] = max(row['wrist_gameplay_degrees_per_second'], float(np.degrees((old_wrist.inv() * local).magnitude()) / dt * gameplay_rate))
                previous[side] = (fore_local, fore_world, local, time)
        if alias in ['Idle','Walk','WalkBack','StrafeLeft','StrafeRight','Run','TurnLeft','TurnRight']:
            epsilon=gameplay_rate/480.;duration=scene.duration(alias)
            world_before,before=scene.pose(alias,duration-epsilon);world_after,after=scene.pose(alias,epsilon)
            for side,f,h,rest,axis in arms:
                for label, old, new in [('local',R.from_quat(before[f][1]),R.from_quat(after[f][1])),('world',world_before[f][1],world_after[f][1])]:
                    old_axis=old.apply(axis);new_axis=new.apply(axis)
                    carried=transport(old_axis,new_axis)*old
                    q=(new*carried.inv()).as_quat();roll=(2.*np.arctan2(q[:3]@new_axis,q[3])+np.pi)%(2.*np.pi)-np.pi
                    field='forearm_'+label+'_roll_gameplay_degrees_per_second'
                    row[field]=max(row[field],float(abs(np.degrees(roll))*240.))
                wrist=(R.from_quat(before[h][1]).inv()*R.from_quat(after[h][1])).magnitude()
                row['wrist_gameplay_degrees_per_second']=max(row['wrist_gameplay_degrees_per_second'],float(np.degrees(wrist)*240.))
            row['loop_seam_physics_rate']=240.
        row['forearm_roll_gameplay_degrees_per_second'] = row['forearm_world_roll_gameplay_degrees_per_second' if forearm_reference == 'world' else 'forearm_local_roll_gameplay_degrees_per_second']
        if active_held: result['failures'].append([alias, 'active grip held', active_held])
        for field, limit in [('wrist_swing_degrees',40.), ('wrist_twist_degrees',35.), ('forearm_roll_gameplay_degrees_per_second',900.), ('wrist_gameplay_degrees_per_second',900.)]:
            if row[field] > limit + .02: result['failures'].append([alias, field, row[field], limit])
        result['clips'].append(row)
    for key in ['wrist_swing_degrees', 'wrist_twist_degrees', 'forearm_roll_gameplay_degrees_per_second', 'forearm_local_roll_gameplay_degrees_per_second', 'forearm_world_roll_gameplay_degrees_per_second', 'wrist_gameplay_degrees_per_second', 'maximum_arm_local_key_delta', 'grip_axis_error_degrees']:
        result['maximum_' + key] = max(row[key] for row in result['clips'])
    result['held_frames'] = sum(len(row['held_source_times']) for row in result['clips'])
    result['active_held_frames'] = sum(len(row['active_held_source_times']) for row in result['clips'])
    result['passed'] = not result['failures']
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--characters', nargs='+', default=['zhaoyun','machao','guanyu','zhangfei','lubu','xuchu','bandit'])
    parser.add_argument('--output', type=Path, default=ROOT / 'qa/grip-continuity-2026-10-24.json')
    parser.add_argument('--forearm-reference', choices=['world','upper_arm_local'], default='world',
                        help='World continuity is the release guard; local counter-roll is always reported separately')
    args = parser.parse_args()
    manifest = json.loads((GAME / 'assets/characters/animation_manifest.json').read_text())
    report = {'roles': {}, 'passed': True}
    for role in args.characters:
        result = audit(role, manifest[role], GAME / ('assets/characters/' + role + '.glb'), args.forearm_reference)
        report['roles'][role] = result
        report['passed'] &= result['passed']
        print(role, {key:value for key,value in result.items() if key != 'clips'}, flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
