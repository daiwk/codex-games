"""Project-authored pose phrases layered over CC0 source animations.

These are deliberately new clips. Existing basic-attack / contact regression
clips are never changed. Retargeting and both-hand IK still run afterwards.
Angles are this project's art direction, not motion copied from another game.
"""
import numpy as np
from scipy.spatial.transform import Rotation as R


def phrase(source, keys, library='melee', crop=None, reverse=False):
    return dict(source=source, library=library, keys=keys, crop=crop, reverse=reverse)


# Keys: normalized time, torso pitch/yaw/roll (degrees), independent arm pitch,
# crouch blend, hip lateral shift. All rotations affect complete branches,
# including weapon sockets, before the existing calibrated two-palm solver.
SIGNATURES = {
    'zhaoyun': {
        'DragonNeedle': phrase('Melee_2H_Attack_Stab', [(0, -4, -13, 7, 0, .12, -.055), (.22, 0, -4, 2, 0, .04, -.025), (.42, 0, 0, 0, 0, 0, 0), (1, -3, 10, -3, 0, .05, .035)]),
        'DragonLow': phrase('Melee_2H_Attack_Stab', [(0, 13, 15, -5, -4, .42, .06), (.24, 5, 4, -2, -2, .18, .025), (.43, 0, 0, 0, 0, .06, 0), (1, 4, -12, 4, 0, .13, -.035)]),
        'DragonHigh': phrase('Melee_2H_Attack_Stab', [(0, -4, -13, 7, 0, .12, -.055), (.24, -3, -5, 1, 2, .04, -.02), (.43, 0, 0, 0, 0, 0, 0), (1, -5, 12, -4, 4, .05, .035)]),
        'DragonSlip': phrase('Dodge_Left', [(0, 0, 0, 0, 0, .05, 0), (.5, 7, -20, 12, -9, .30, -.06), (1, 2, -8, 3, 0, .1, 0)], 'advanced'),
        'DragonGather': phrase('Melee_2H_Idle', [(0, 0, 0, 0, 0, .03, 0), (.55, 8, -20, 8, -12, .35, -.055), (1, 2, -8, 3, -3, .16, -.025)]),
        # Guandao/halberd equipment remains available to the RPG player.
        'CrescentLow': phrase('Melee_2H_Attack_Slice', [(0, 15, -18, -9, -22, .45, -.04), (.45, 4, 0, 0, -8, .18, 0), (1, 5, 12, 4, -10, .1, .04)]),
        'CrescentDrag': phrase('Walking_Backwards', [(0, 0, 0, 0, 0, .04, 0), (.5, 14, -27, -12, -27, .22, -.04), (1, 10, -20, -8, -20, .18, -.03)], 'advanced'),
        'CrescentReturn': phrase('Melee_2H_Attack_Chop', [(0, 8, -20, -7, -8, .28, -.03), (.4, 0, 0, 0, 0, 0, 0), (1, 10, 18, 6, -10, .22, .03)]),
        'HalberdRise': phrase('Melee_2H_Attack_Chop', [(0, 14, -20, -8, -18, .42, -.04), (.5, -4, 0, 0, 8, .05, 0), (1, -8, 16, 6, 12, .02, .04)], reverse=True),
        'HalberdWheel': phrase('Melee_2H_Attack_Spinning', [(0, -6, 18, 12, 12, .12, .03), (.5, 0, 0, 0, 0, .06, 0), (1, 8, -15, -6, -10, .28, -.03)]),
        'HalberdDrop': phrase('Melee_2H_Attack_Chop', [(0, -12, 18, 8, 15, .08, .03), (.38, 0, 0, 0, 0, .05, 0), (1, 18, -12, -5, -16, .42, -.03)]),
    },
    'machao': {
        'TigerCouch': phrase('Melee_2H_Attack_Stab', [(0, 18, 17, -7, -15, .32, .035), (.24, 7, 7, -3, -4, .18, .015), (.45, 0, 0, 0, 0, .06, 0), (1, 12, 10, -5, -8, .25, .025)]),
        'TigerSet': phrase('Melee_2H_Idle', [(0, 3, 4, 0, -4, .08, 0), (.6, 18, 22, -10, -20, .5, .055), (1, 18, 22, -10, -20, .5, .055)]),
        'TigerDrive': phrase('Melee_2H_Attack_Stab', [(0, 20, 24, -10, -19, .5, .05), (.22, 9, 10, -4, -7, .25, .025), (.42, 0, 0, 0, 0, .05, 0), (1, 13, 12, -7, -12, .3, .03)]),
        'TigerCommit': phrase('Melee_2H_Attack_Stab', [(0, 24, 27, -11, -23, .58, .06), (.22, 9, 9, -4, -7, .24, .025), (.43, 0, 0, 0, 0, .02, 0), (.7, 13, -10, 4, -6, .3, -.025), (1, 7, -5, 2, -4, .15, 0)]),
    },
    'guanyu': {},
    'zhangfei': {
        'SerpentWard': phrase('Melee_2H_Idle', [(0, 0, 0, 0, 0, .05, 0), (.25, 11, -16, -6, -18, .62, -.045), (1, 11, -16, -6, -18, .62, -.045)]),
        'SerpentRoot': phrase('Melee_2H_Attack_Stab', [(0, 13, -20, -7, -18, .62, -.045), (.24, 5, -7, -2, -5, .35, -.02), (.42, 0, 0, 0, 0, .18, 0), (1, 10, -13, -5, -12, .48, -.025)]),
        'SerpentVoice': phrase('Melee_2H_Idle', [(0, 10, -15, -5, -14, .4, -.03), (.3, -13, -10, 4, 22, .62, -.02), (.58, -19, 6, -3, 28, .53, .015), (1, 6, 0, 0, 0, .25, 0)]),
        'SerpentLong': phrase('Melee_2H_Attack_Stab', [(0, 18, -26, -8, -20, .65, -.05), (.22, 8, -10, -3, -6, .35, -.025), (.43, 0, 0, 0, 0, .16, 0), (1, 16, -16, -5, -16, .55, -.04)]),
    },
    'lubu': {},
    'xuchu': {
        'BruteShoulder': phrase('Sword_Dash', [(0, 14, 24, -13, -6, 0, .045), (.35, 8, 15, -8, 0, 0, .025), (1, 10, -15, 5, -6, 0, -.02)], 'ual2'),
        'BruteGuard': phrase('Sword_Block', [(0, 4, 10, -4, 0, 0, .025), (.35, 10, 18, -9, -10, 0, .04), (1, 6, 13, -6, -5, 0, .025)], 'ual2'),
        'BruteRebuke': phrase('Melee_1H_Attack_Slice_Diagonal', [(0, 14, 23, -12, -8, .35, .04), (.4, 0, 0, 0, 0, .1, 0), (1, 16, -20, 8, -18, .4, -.04)]),
        'BruteGather': phrase('Melee_Blocking', [(0, 2, 0, 0, 0, .1, 0), (.5, 18, 25, -11, 30, .7, .045), (1, 20, 28, -12, 38, .75, .05)]),
        'BruteExecution': phrase('Melee_1H_Attack_Jump_Chop', [(0, 20, 28, -12, 28, .5, .05), (.25, -8, 12, -4, 18, .08, .02), (.5, 4, 0, 0, 0, .1, 0), (1, 25, -22, 8, -20, .7, -.04)]),
    },
}
# Keep the free dash's authored lower body; its sword arm is a deliberate
# close horizontal cut from KayKit, avoiding the source rig's wrist snap.
SIGNATURES['xuchu']['BruteShoulder']['upper_source'] = ['melee', 'Melee_1H_Attack_Slice_Horizontal']

for character in ['guanyu']:
    for alias in ['CrescentLow', 'CrescentDrag', 'CrescentReturn']:
        SIGNATURES[character][alias] = SIGNATURES['zhaoyun'][alias]
    SIGNATURES[character].update({
        'CrescentGather': phrase('Melee_2H_Attack_Slice', [(0, 12, -22, -8, -25, .35, -.04), (1, 15, -27, -12, -30, .5, -.05)], crop=(0., .25)),
        'CrescentSplit': phrase('Melee_2H_Attack_Chop', [(0, -5, -22, -10, 8, .2, -.03), (.4, 0, 0, 0, 0, .05, 0), (1, 14, 24, 10, -18, .35, .04)]),
        'CrescentOrbit': phrase('Melee_2H_Attack_Spinning', [(0, 10, -25, -9, -15, .35, -.04), (.4, 0, 0, 0, 0, .1, 0), (1, 12, 18, 6, -10, .3, .03)]),
    })
for alias in ['HalberdRise', 'HalberdWheel', 'HalberdDrop']:
    SIGNATURES['lubu'][alias] = SIGNATURES['zhaoyun'][alias]
SIGNATURES['lubu']['HalberdGather'] = phrase('Melee_2H_Attack_Chop', [(0, 3, 0, 0, 0, .1, 0), (1, -16, 24, 12, 24, .28, .04)], crop=(0., .35))


# The RPG player's three equipment paths use the same supplied Zhao Yun rig.
# Bake every required cut signature there too; never fall back to a spear alias.
for owner in ['guanyu', 'lubu']:
    SIGNATURES['zhaoyun'].update(SIGNATURES[owner])


def interpolate(keys, progress):
    for a, b in zip(keys, keys[1:]):
        if progress <= b[0]:
            t = np.clip((progress - a[0]) / max(1e-7, b[0] - a[0]), 0., 1.)
            t = t * t * (3. - 2. * t)
            return np.asarray(a[1:]) * (1. - t) + np.asarray(b[1:]) * t
    return np.asarray(keys[-1][1:])


def sample_signature(spec, sources, time, duration):
    src = sources[spec['library']]
    p = np.clip(time / max(duration, 1e-7), 0., 1.)
    lo, hi = spec['crop'] or (0., src.duration(spec['source']))
    clock = hi - p * (hi - lo) if spec['reverse'] else lo + p * (hi - lo)
    world = src.pose(spec['source'], clock)[0]
    pitch, yaw, roll, arm_pitch, crouch, side = interpolate(spec['keys'], p)
    upper = R.from_euler('xyz', [pitch, yaw, roll], degrees=True)
    arms = R.from_euler('x', arm_pitch, degrees=True)
    is_ual = spec['library'] == 'ual2'
    for name, node in src.names.items():
        upper_name = name.startswith(('upperarm', 'lowerarm', 'wrist.', 'hand', 'handslot', 'clavicle')) or name in ['chest', 'head', 'Head', 'spine', 'spine_01', 'spine_02', 'spine_03', 'neck_01']
        arm_name = name.startswith(('upperarm', 'lowerarm', 'wrist.', 'hand', 'handslot', 'clavicle'))
        pos, rot = world[node]
        if upper_name:
            rot = upper * rot
            if arm_name:
                rot = arms * rot
            world[node] = (pos, rot)
    if not is_ual and crouch > 0.:
        low = sources['advanced'].pose('Crouching', 0.5)[0]
        for name in ['hips', 'upperleg.l', 'upperleg.r', 'lowerleg.l', 'lowerleg.r', 'foot.l', 'foot.r', 'toes.l', 'toes.r']:
            if name not in src.names or name not in sources['advanced'].names:
                continue
            node = src.names[name]
            pos, rot = world[node]
            low_pos, low_rot = low[sources['advanced'].names[name]]
            delta = rot.inv() * low_rot
            world[node] = (pos * (1. - crouch) + low_pos * crouch,
                           rot * R.from_rotvec(delta.as_rotvec() * crouch))
    hip = src.names['pelvis' if is_ual else 'hips']
    pos, rot = world[hip]
    pos = pos.copy()
    pos[0] += side
    world[hip] = (pos, rot)
    return world
