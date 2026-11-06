#!/usr/bin/env python3
"""Bake the duel-only Guan Yu polearm phrases on the existing Mixamo rig.

Run from any working directory with NumPy and SciPy installed. Base character
geometry, textures and existing animation data stay intact. The authored
coordinates are blade and stance poses in character space, in seconds.
"""
from concurrent.futures import ProcessPoolExecutor
from copy import deepcopy
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.interpolate import PchipInterpolator
from scipy.spatial.transform import Rotation as Rotation

from gltf_tools import GLB, compact_buffers, write_glb
from prepare_polearms import fit_polearm_hands

ROOT = Path(__file__).resolve().parents[1] / "godot"
HZ = 60
SCALE = 1.98
PREFIX = "GuanCrescent"
UP = np.array([0.0, 1.0, 0.0])
FORWARD = np.array([0.0, 0.0, 1.0])
SIDES = ("Left", "Right")


def normalize(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-9)


def between(start, end):
    a, b = np.broadcast_arrays(normalize(start), normalize(end))
    q = np.concatenate([np.cross(a, b), 1.0 + np.sum(a * b, axis=-1, keepdims=True)], axis=-1)
    if np.linalg.norm(q, axis=-1).min() < 1e-7:
        # Unreachable for ordinary swings; keep a defined fallback for a
        # potential straight antipode in a newly authored pose.
        fallback = np.cross(a, np.eye(3)[np.argmin(np.abs(a), axis=-1)])
        q[..., :3] = np.where((np.linalg.norm(q, axis=-1) < 1e-7)[..., None], fallback, q[..., :3])
    return Rotation.from_quat(normalize(q))


def yaw(angle):
    return Rotation.from_euler("y", angle, degrees=True)


def shaft_frame(heading, elevation):
    return yaw(heading) * Rotation.from_euler("x", -elevation, degrees=True)


def smoothstep(a):
    return a * a * (3.0 - 2.0 * a)


# Row: time, pelvis yaw, extra chest yaw, body pitch, hip height, local
# centre x/y/z in metres on the original rig, shaft yaw/elevation, edge roll.
# Blade roll = 0 for positive yaw cuts, -90 for down, 90 for up.
READY = (0, 0, 0, 0, .514, .003, .591, .185, 55.2, 22.0, -165.5)
# Continuation points are also the next attack's exact first pose.
J1_JOIN = (.60, -37, -18, 11, .489, -.035, .560, .191, -109, -14, -173)
J2_JOIN = (.65, 43, 19, -7, .521, .040, .661, .185, 133, 37, -298)
J3_JOIN = (.74, -47, -15, 19, .457, -.035, .475, .204, -120, -20, -176)
U_DRAW = (.76, 37, 18, -11, .504, .050, .758, .158, 60, 57, -114)

PHRASES = {
    "J1": [
        READY, (.15, 16, 14, 7, .496, .027, .602, .165, 105, 18, -177),
        (.25, 12, 5, 10, .492, .014, .612, .203, 75, 17, -173),
        (.33, -5, -5, 9, .489, -.107, .607, .199, 4, 10, -170),
        (.42, -25, -14, 12, .482, -.060, .570, .209, -68, -8, -170),
        J1_JOIN, (.92, *READY[1:]),
    ],
    "J2": [
        (0, *J1_JOIN[1:]), (.16, -32, -20, 9, .479, -.045, .546, .190, -112, -23, -280),
        (.29, -15, -15, 7, .483, -.025, .554, .211, -70, -17, -305),
        (.37, 7, -2, 0, .504, .114, .679, .187, -6, 13, -316),
        (.47, 30, 12, -8, .516, .030, .744, .185, 85, 30, -310),
        J2_JOIN, (.94, 0, 0, 0, .514, .003, .591, .185, 55.2, 22, -165.5),
    ],
    "J3": [
        (0, *J2_JOIN[1:]), (.18, 45, 17, 14, .464, .042, .478, .182, 128, -19, -235),
        (.35, 21, 13, 16, .454, .028, .492, .210, 72, -15, -200),
        (.445, -8, -3, 19, .446, -.095, .489, .190, 6, -18, -179),
        (.58, -36, -16, 20, .451, -.037, .474, .215, -83, -20, -177),
        J3_JOIN, (1.05, *READY[1:]),
    ],
    "J4": [
        (0, *J3_JOIN[1:]), (.20, -34, -15, -1, .492, -.052, .680, .185, -104, 33, -119),
        (.38, -15, -8, -10, .518, -.065, .808, .160, -42, 72, -70),
        (.49, -9, 5, 5, .506, -.044, .765, .208, -13, 42, -78),
        (.565, 1, 8, 16, .468, -.104, .654, .206, 7, -7, -82),
        (.645, 10, 8, 24, .449, -.080, .533, .221, 12, -38, -90),
        (.82, 9, 2, 14, .468, .043, .526, .219, 32, -23, -102),
        (1.25, *READY[1:]),
    ],
    "K": [
        READY, (.23, 20, 15, -9, .501, .059, .720, .163, 66, 47, -113),
        (.48, 27, 12, -12, .514, .065, .824, .148, 55, 70, -84),
        (.61, 11, 9, 3, .498, .033, .807, .211, 20, 54, -88),
        (.71, 3, -2, 18, .462, .114, .693, .207, -8, 9, -95),
        (.815, -9, -6, 25, .443, .093, .537, .206, -13, -36, -107),
        (.96, -13, -8, 15, .464, -.042, .523, .218, -18, -26, -118),
        (1.45, *READY[1:]),
    ],
    "Q": [
        # Sit into the rear boot, unwind the hips, and let the loaded blade
        # catch up to the torso. The rising back of the turn redirects its
        # momentum into a lower second cut after the cross-step plants.
        READY, (.16, -20, -16, 10, .490, -.034, .560, .164, -68, -7, -269),
        (.245, -31, -15, 15, .465, -.035, .551, .165, -99, -10, -326),
        (.38, -2, -25, 14, .464, -.030, .561, .201, -67, -7, -352),
        (.515, 23, -16, 10, .467, .099, .564, .199, -9, -3, -355),
        (.585, 42, -11, 8, .478, .064, .556, .200, 57, 1, -354),
        (.69, 99, -26, 8, .496, .034, .624, .185, 145, 22, -350),
        (.82, 172, -23, 12, .489, .023, .618, .190, 231, 18, -348),
        (.95, 250, -23, 18, .467, .015, .519, .195, 285, -12, -352),
        (1.09, 320, -24, 18, .453, .021, .499, .204, 337, -16, -346),
        (1.18, 358, -19, 18, .461, .111, .552, .190, 358, -8, -342),
        (1.29, 393, -9, 4, .477, .020, .623, .201, 425, 16, -379),
        (1.46, 380, 2, 5, .488, .031, .604, .182, 438, 25, -456),
        (1.78, 360, *READY[2:8], 415.2, 22, -525.5),
    ],
    "E": [
        READY, (.18, 16, 10, 13, .475, .032, .534, .160, 104, -11, -172),
        (.36, 36, 17, 20, .451, .041, .459, .166, 134, -26, -162),
        (.54, 34, 12, 17, .457, .045, .490, .170, 119, -20, -187),
        (.67, 18, 8, 9, .475, .021, .561, .217, 68, 8, -205),
        (.775, 0, -1, 9, .471, -.090, .593, .196, 6, 10, -198),
        (.885, -23, -12, 15, .453, -.038, .501, .226, -72, -19, -187),
        (1.01, -25, -13, 16, .461, -.047, .509, .190, -93, -19, -185),
        (1.31, *READY[1:]),
    ],
    "UCharge": [
        READY, (.17, 15, 12, 16, .467, .025, .497, .172, 107, -16, -143),
        (.30, 30, 16, 19, .456, .039, .466, .177, 135, -24, -131),
        (.43, 44, 12, 9, .482, .038, .564, .193, 118, 17, -124),
        (.60, 43, 14, -8, .510, .053, .724, .177, 79, 50, -116),
        U_DRAW,
    ],
    "U": [
        (0, *U_DRAW[1:]), (.18, 40, 17, -16, .517, .058, .817, .146, 48, 72, -104),
        (.29, 33, 22, -14, .512, .060, .834, .156, 37, 76, -98),
        (.39, 17, 21, -6, .503, .051, .828, .181, 28, 74, -96),
        (.46, 6, 17, 5, .479, .045, .801, .207, 17, 61, -93),
        # Hold the blade high until the lead boot is down. Then brake the
        # downward cut through a deep knee bend before lifting the weapon.
        (.53, -2, 11, 18, .449, .102, .749, .214, 1, 37, -94),
        (.57, -9, 4, 25, .419, .110, .632, .180, -8, 1, -96),
        (.63, -14, 1, 29, .346, .086, .526, .146, -9, -39, -99),
        (.665, -16, 0, 42, .316, .082, .510, .158, -10, -38, -102),
        (.735, -17, 0, 48, .320, .081, .508, .170, -11, -32, -103),
        (.86, -12, -2, 34, .384, .074, .526, .208, -9, -24, -107),
        (1.04, -5, -4, 14, .461, -.012, .552, .193, 13, -8, -119),
        (1.35, *READY[1:]),
    ],
}

# Actor-local root Z in metres. Plants below are world-in-clip anchors, so
# translating the actor by this curve does not pull the supporting boot.
TRAVEL = {
    "J1": [(0, 0), (.15, -.03), (.40, .26), (.60, .32), (.92, .32)],
    "J2": [(0, 0), (.20, .01), (.45, .29), (.65, .33), (.94, .33)],
    "J3": [(0, 0), (.19, -.02), (.46, .23), (.74, .27), (1.05, .27)],
    "J4": [(0, 0), (.30, -.04), (.57, .40), (.82, .44), (1.25, .44)],
    "K": [(0, 0), (.43, -.08), (.74, .45), (.96, .52), (1.45, .52)],
    "Q": [(0, 0), (.23, -.035), (.44, .10), (.61, .19), (.88, .32),
          (1.10, .44), (1.23, .56), (1.46, .60), (1.78, .60)],
    "E": [(0, 0), (.14, -.06), (.42, -.64), (.53, -.68), (.79, -.21), (1.31, -.19)],
    "UCharge": [(0, 0), (.26, .07), (.52, .36), (.76, .47)],
    "U": [(0, 0), (.24, .015), (.36, .12), (.46, .31), (.55, .53), (.64, .62), (.80, .64), (1.35, .64)],
}

# Left/right boot swing intervals and maximum ankle lift in rig metres.
# Between intervals the ankle anchor stays fixed, including through turns.
STEPS = {
    "J1": {"Left": [(.64, .80, .045)], "Right": [(.18, .37, .054), (.74, .92, .026)]},
    "J2": {"Left": [(.20, .40, .052), (.76, .94, .025)], "Right": [(.67, .82, .043)]},
    "J3": {"Left": [(.76, .88, .037)], "Right": [(.20, .41, .052), (.85, 1.05, .021)]},
    "J4": {"Left": [(.34, .55, .064), (.97, 1.25, .031)], "Right": [(.73, .98, .045)]},
    "K": {"Left": [(.56, .69, .057), (1.19, 1.45, .024)], "Right": [(.82, 1.11, .042)]},
    "Q": {"Left": [(.21, .40, .044), (.675, .815, .059), (.997, 1.130, .054), (1.46, 1.61, .030)],
          "Right": [(.51, .665, .053), (.831, .987, .056), (1.15, 1.31, .049), (1.625, 1.78, .026)]},
    "E": {"Left": [(.10, .31, .055), (.57, .76, .056), (1.07, 1.31, .026)],
          "Right": [(.30, .48, .049), (.83, 1.03, .043)]},
    "UCharge": {"Left": [(.33, .56, .045)], "Right": [(.09, .28, .044), (.56, .76, .034)]},
    "U": {"Left": [(.27, .46, .064), (1.10, 1.35, .034)], "Right": [(.84, 1.06, .048)]},
}

# The cleave shifts over its rear boot before the front boot takes the cut.
# Each row is (time, lateral pelvis offset in rig metres, torso roll in degrees).
CLEAVE_WEIGHT = {
    "UCharge": [(0, 0, 0), (.17, -.035, 7), (.31, -.060, 11),
                (.48, -.035, 6), (.60, .026, -4), (.76, -.019, 3)],
    "U": [(0, -.019, 3), (.23, -.065, 11), (.35, -.053, 10), (.46, .011, 1),
          (.55, .048, -6), (.64, .069, -9), (.75, .071, -10), (.84, .051, -7),
          (1.00, .022, -2), (1.35, 0, 0)],
}

# Selected planting targets receive a local X/Z extension in gameplay metres.
# The rear boot stays at its end-of-charge anchor until the blade settles.
CLEAVE_PLANTS = {
    ("UCharge", "Left", .56): (-.050, .13),
    ("UCharge", "Right", .76): (.062, -.06),
    ("U", "Left", .46): (-.104, .48),
    ("U", "Right", 1.06): (.035, -.04),
}

JOINS = {"J2": ("J1", .60), "J3": ("J2", .65), "J4": ("J3", .74), "U": ("UCharge", .76)}

# The support boot turns around its toe while the other foot moves. Each
# entry is start, end, world yaw in the clip, and maximum heel rock in degrees.
Q_PIVOTS = {
    "Left": [(.435, .595, 50, 11), (.836, .973, 206, 14), (1.159, 1.272, 355, 10)],
    "Right": [(.237, .382, -20, 9), (.689, .795, 151, 14), (1.014, 1.118, 330, 12),
              (1.478, 1.588, 365, 8)],
}

# Left-foot weight share, torso bank, and head lead through the two sweeps.
Q_WEIGHT = np.array([
    (0, .50, 0, 0), (.22, .17, -5, 3), (.38, .20, -8, 6),
    (.49, .81, 5, 10), (.64, .82, 8, 14), (.72, .19, -7, 18),
    (.81, .23, -5, 21), (.87, .79, 7, 18), (.98, .78, 9, 21),
    (1.04, .19, -6, 18), (1.13, .35, -7, 9), (1.20, .80, 6, 7),
    (1.35, .67, 5, -10), (1.50, .32, -3, -10),
    (1.64, .68, 3, -5), (1.78, .50, 0, 0),
])
Q_WEIGHT_CURVE = PchipInterpolator(Q_WEIGHT[:, 0], Q_WEIGHT[:, 1:], axis=0)


class Rig:
    def __init__(self, target, grip):
        self.glb = target
        self.world, self.rest = target.pose("Idle", 0.0)
        self.hip = self.id("Hips")
        self.rest_hip, self.rest_hip_rotation = self.world[self.hip]
        self.palms = {side.lower(): np.array(grip[side.lower() + "_palm"]) for side in SIDES}
        self.arms = {side: tuple(self.id(side + part) for part in ("Arm", "ForeArm", "Hand")) for side in SIDES}
        self.legs = {side: tuple(self.id(side + part) for part in ("UpLeg", "Leg", "Foot")) for side in SIDES}
        self.neutral_axis = normalize(self.palm(self.world, "Left") - self.palm(self.world, "Right"))
        self.neutral_shaft = shaft_frame(np.rad2deg(np.arctan2(self.neutral_axis[0], self.neutral_axis[2])),
                                         np.rad2deg(np.arcsin(self.neutral_axis[1])))
        self.rest_bones = target.pose()[1]

    def id(self, name):
        return self.glb.names["mixamorig:" + name]

    def set_world_rotation(self, pose, i, rotation):
        parent = self.glb.world(pose)[self.glb.parents[i]][1]
        pose[i][1] = (parent.inv() * rotation).as_quat()

    def palm(self, world, side):
        p, r = world[self.arms[side][-1]]
        return p + r.apply(self.palms[side.lower()])

    def solve_leg(self, pose, side, ankle, foot_rot, body):
        world = self.glb.world(pose)
        upper, knee, foot = self.legs[side]
        hip = world[upper][0]
        thigh_axis, shin_axis = self.rest[knee][0], self.rest[foot][0]
        l1, l2 = np.linalg.norm(thigh_axis), np.linalg.norm(shin_axis)
        move = ankle - hip
        distance = np.linalg.norm(move)
        aim = move / distance
        reach = np.clip(distance, abs(l1 - l2) + .001, l1 + l2 - .001)
        length = (l1 * l1 - l2 * l2 + reach * reach) / (2 * reach)
        height = np.sqrt(max(0.0, l1 * l1 - length * length))
        guide = body.apply(np.array([.35 if side == "Left" else -.35, 0.0, 1.0]))
        knee_pos = hip + aim * length + normalize(guide - aim * np.dot(aim, guide)) * height
        upper_ref = body * self.world[upper][1]
        knee_ref = body * self.world[knee][1]
        upper_rot = between(upper_ref.apply(thigh_axis), knee_pos - hip) * upper_ref
        knee_rot = between(knee_ref.apply(shin_axis), hip + reach * aim - knee_pos) * knee_ref
        pose[upper][1] = (world[self.glb.parents[upper]][1].inv() * upper_rot).as_quat()
        pose[knee][1] = (upper_rot.inv() * knee_rot).as_quat()
        pose[foot][1] = (knee_rot.inv() * foot_rot).as_quat()
        return distance - reach



def q_boot_anchor(rig, side, t, curve, travel, start):
    foot, toe = rig.legs[side][-1], rig.id(side + "ToeBase")
    base = rig.world[foot][0]
    toe_offset = rig.world[toe][0] - base
    toe_forward = normalize(toe_offset - UP * np.dot(toe_offset, UP))
    heel_axis = np.cross(UP, toe_forward)
    old, old_yaw = start
    steps = STEPS["Q"][side]
    events = [(begin, end, None, lift) for begin, end, lift in steps] + Q_PIVOTS[side]
    for begin, end, heading, amount in sorted(events):
        if t < begin:
            break
        u = np.clip((t - begin) / (end - begin), 0.0, 1.0)
        weight = smoothstep(u)
        swing = heading is None
        if swing:
            heading = 360. if end == steps[-1][1] else float(curve(min(end + .047, 1.78))[0])
        heading_now = old_yaw + weight * ((heading - old_yaw + 180) % 360 - 180)
        rotate = yaw(heading_now)
        if swing:
            target = rig.rest_hip + yaw(heading).apply(base - rig.rest_hip) + FORWARD * float(travel(end)) / SCALE
            outward = rotate.apply([.028 if side == "Left" else -.028, 0.0, 0.0])
            ankle = old * (1. - weight) + target * weight + (UP * amount + outward) * np.sin(np.pi * u) ** 2
            heel = Rotation.identity()
        else:
            # Anchor the actual ToeBase and rock the heel off the floor
            # during the pivot. The opposite boot can pass the support leg.
            heel = Rotation.from_rotvec(heel_axis * np.deg2rad(amount) * np.sin(np.pi * u) ** 2)
            toe_world = old + yaw(old_yaw).apply(toe_offset)
            ankle = toe_world - rotate.apply(heel.apply(toe_offset))
        if t < end:
            return ankle, rotate * heel
        old, old_yaw = ankle, heading
    return old, yaw(old_yaw)

def boot_anchors(rig, alias, side, t, curve, travel, start):
    i = rig.legs[side][-1]
    base, base_rot = rig.world[i]
    old, old_yaw = start
    for begin, end, lift in STEPS[alias][side]:
        heading = float(curve(end)[0])
        if end == STEPS[alias][side][-1][1] and alias != "UCharge":
            heading = float(curve(PHRASES[alias][-1][0])[0])
        target = rig.rest_hip + yaw(heading).apply(base - rig.rest_hip) + FORWARD * float(travel(end)) / SCALE
        extension = CLEAVE_PLANTS.get((alias, side, end))
        if extension is not None:
            target += np.array([extension[0], 0.0, extension[1]]) / SCALE
        if t < begin:
            break
        if t < end:
            u = (t - begin) / (end - begin)
            p = smoothstep(u)
            ankle = old * (1 - p) + target * p + UP * (lift * np.sin(np.pi * u) ** 2)
            return ankle, old_yaw + p * ((heading - old_yaw + 180) % 360 - 180)
        old, old_yaw = target, heading
    return old, old_yaw


def start_anchors(rig, previous):
    if previous is None:
        return {side: (rig.world[rig.legs[side][-1]][0], 0) for side in SIDES}
    return previous["anchors"]


def bake(rig, alias, previous):
    rows = np.array(PHRASES[alias])
    curve = PchipInterpolator(rows[:, 0], rows[:, 1:], axis=0)
    curve_travel = np.array(TRAVEL[alias])
    travel = PchipInterpolator(curve_travel[:, 0], curve_travel[:, 1])
    duration = rows[-1, 0]
    ticks = np.linspace(0.0, duration, round(duration * HZ) + 1)
    samples, edges, report = [], [], []
    stance = start_anchors(rig, previous)
    cleave_weight = None
    if alias in CLEAVE_WEIGHT:
        weights = np.asarray(CLEAVE_WEIGHT[alias])
        cleave_weight = PchipInterpolator(weights[:, 0], weights[:, 1:], axis=0)
    target = rig.glb
    last = previous["pose"] if previous is not None else rig.rest
    last_world = target.world(last)
    history = {"_step_seconds": 1. / HZ, "_roll_rate": 600., "_enforce_continuity": True,
               "_centre": sum(rig.palm(last_world, s) for s in SIDES) / 2.}
    history["_fore_guides"] = {side: Rotation.from_quat(rig.rest[arm[1]][1]) for side, arm in rig.arms.items()}
    for side, (upper, elbow, hand) in rig.arms.items():
        for name, i in (("upper", upper), ("fore", elbow), ("hand", hand)):
            history[side + "_" + name] = Rotation.from_quat(last[i][1])
            if name != "hand":
                history[side + "_" + name + "_world"] = last_world[i][1]
    is_rotary = alias == "Q"
    neutral_foot_center = sum(rig.world[rig.legs[side][-1]][0] for side in SIDES) / 2.
    for time in ticks:
        pelvis, chest, lean, height, cx, cy, cz, blade_yaw, elevation, edge_roll = curve(time)
        weight, bank, gaze = Q_WEIGHT_CURVE(time) if is_rotary else (.50, 0., 0.)
        hip_turn, body = yaw(pelvis), yaw(pelvis + chest)
        pose = deepcopy(rig.rest)
        pose[rig.hip][0][1] = height
        torso_tilt = Rotation.from_euler("x", lean, degrees=True)
        if cleave_weight is not None:
            lateral, roll = cleave_weight(time)
            pose[rig.hip][0][0] += lateral
            torso_tilt = Rotation.from_euler("z", roll, degrees=True) * torso_tilt
        pose[rig.hip][1] = (hip_turn * rig.rest_hip_rotation).as_quat()
        torso = yaw(pelvis + chest) * torso_tilt * yaw(-pelvis)
        if is_rotary:
            torso = yaw(pelvis + chest) * Rotation.from_euler("xz", [lean, bank], degrees=True) * yaw(-pelvis)
        for name, amount in (("Spine", .24), ("Spine1", .33), ("Spine2", .43)):
            bone = rig.id(name)
            world = target.world(pose)
            rig.set_world_rotation(pose, bone, Rotation.from_rotvec(torso.as_rotvec() * amount) * world[bone][1])
        # Face the opponent through the windup, then let the gaze lead the
        # planted turn and return to the blade line before the second pass.
        head = rig.id("Head")
        head_adjust = -np.clip(chest * .45, -13, 13) + gaze
        rig.set_world_rotation(pose, head, yaw(head_adjust) * target.world(pose)[head][1])
        offset = FORWARD * float(travel(time)) / SCALE
        if is_rotary:
            anchor_states = {side: q_boot_anchor(rig, side, time, curve, travel, stance[side]) for side in SIDES}
            left, right = [anchor_states[side][0] for side in SIDES]
            load = left * weight + right * (1. - weight) - offset - neutral_foot_center
            pose[rig.hip][0][[0, 2]] += load[[0, 2]] * .60
        else:
            anchor_states = {side: boot_anchors(rig, alias, side, time, curve, travel, stance[side]) for side in SIDES}
        hip_y = pose[rig.hip][0][1]
        world = target.world(pose)
        for side, (ankle, _) in anchor_states.items():
            upper, knee, foot = rig.legs[side]
            hip_point = world[upper][0]
            radius = np.linalg.norm(pose[knee][0]) + np.linalg.norm(pose[foot][0]) - .012
            reach = ankle - offset - hip_point
            vertical = np.sqrt(max(0.0, radius * radius - reach[0] ** 2 - reach[2] ** 2))
            hip_y = min(hip_y, ankle[1] + vertical - (hip_point[1] - height))
        pose[rig.hip][0][1] = hip_y
        # K's short two-foot transition adds a real silhouette break at
        # the top of the load, then puts the lead boot down into the cut.
        hop = .045 * np.sin(np.pi * np.clip((time - .53) / .18, 0, 1)) ** 2 if alias == "K" else 0
        pose[rig.hip][0][1] += hop
        errors = []
        for side, (ankle, heading) in anchor_states.items():
            foot = rig.legs[side][-1]
            foot_turn = heading if is_rotary else yaw(heading)
            errors.append(rig.solve_leg(pose, side, ankle - offset + UP * hop,
                                        foot_turn * rig.world[foot][1], hip_turn))
        frame = shaft_frame(blade_yaw, elevation)
        axis = frame.apply(FORWARD)
        edge = frame.apply([np.cos(np.deg2rad(edge_roll)), np.sin(np.deg2rad(edge_roll)), 0.0])
        center = body.apply([cx, 0.0, cz]) + np.array([0.0, cy + hip_y - height + hop, 0.0])
        if is_rotary:
            center[[0, 2]] += load[[0, 2]] * .60
        body_pose = target.world(pose)
        history["_upper_guides"] = {side: body_pose[arm[0]][1] for side, arm in rig.arms.items()}
        hand_rotations = {side: frame * rig.neutral_shaft.inv() * rig.world[arm[-1]][1] for side, arm in rig.arms.items()}
        # Narrow the grip during a cross-body cut, still leaving the length
        # of two clenched gloves between the two palm centres.
        cross_body = max(0.0, -np.sin(np.deg2rad(blade_yaw - pelvis - chest)))
        front_cross = max(0.0, np.cos(np.deg2rad(blade_yaw - pelvis - chest))) ** 5
        spacing = .09 - .035 * cross_body - .016 * front_cross
        # Penalize the whole pole piercing the armored torso, not merely
        # the two contact centres. Each obstacle includes the shaft radius.
        spine_clearance = [("Hips", .104), ("Spine", .104), ("Spine1", .109), ("Spine2", .118),
                           ("Neck", .089), ("Head", .090), ("LeftArm", .080), ("RightArm", .080)]
        obstacles = [(body_pose[rig.id(name)][0] + (UP * .073 if name == "Head" else 0), radius)
                     for name, radius in spine_clearance]
        history["_shaft_clearance"] = ((2.85 * .35 / SCALE, 2.85 * .65 / SCALE), obstacles)
        # Pose validation expects both palm centres on the same line and
        # rejects fallback poses that would let the haft jump in one glove.
        if time < 1e-7:
            pose = deepcopy(last)
            edge = previous["edge"] if previous is not None else normalize(FORWARD - rig.neutral_axis * np.dot(FORWARD, rig.neutral_axis))
            spacing = np.linalg.norm(rig.palm(last_world, "Left") - rig.palm(last_world, "Right")) * .5
        else:
            solved = fit_polearm_hands(target, pose, axis, hand_rotations, rig.palms, history,
                                      _centre=center, _spacing=spacing)
            if not solved:
                # Fall back to the soft temporal penalty, not to a frozen
                # old pose. Both arms still meet the authored shaft exactly.
                history["_enforce_continuity"] = False
                solved = fit_polearm_hands(target, pose, axis, hand_rotations, rig.palms, history,
                                          _centre=center, _spacing=spacing)
                history["_enforce_continuity"] = True
            if not solved:
                raise ValueError(f"No two-hand solution for {alias} at {time:.3f}")
        wrists = [np.rad2deg((Rotation.from_quat(pose[h][1]) * Rotation.from_quat(rig.rest_bones[h][1]).inv()).magnitude())
                  for _, _, h in rig.arms.values()]
        world = target.world(pose)
        a, b = [rig.palm(world, side) for side in SIDES]
        model_tip = b + normalize(a - b) * (2.85 * .65 / SCALE)
        model_tail = b - normalize(a - b) * (2.85 * .35 / SCALE)
        report.append([time, float(model_tip[1]), float(model_tail[1]), max(wrists),
                       float(abs(np.linalg.norm(a - b) - spacing * 2)), float(max(errors))])
        samples.append({"pose": pose, "anchors": {s: (p - FORWARD * float(travel(time)) / SCALE, h) for s, (p, h) in anchor_states.items()}, "edge": edge})
        edges.append(edge.tolist())
        last = pose
    return ticks, samples, edges, report, travel


def bake_group(inputs):
    path, grip, names = inputs
    rig = Rig(GLB(path), grip)
    result = {}
    joins = {}
    for name in names:
        times, frames, edges, stats, travel = bake(rig, name, joins.get(name))
        result[name] = (times, frames, edges, stats, travel(times))
        for child, (parent, time) in JOINS.items():
            if parent == name:
                joins[child] = frames[np.argmin(np.abs(times - time))]
    return result


def main():
    path = ROOT / "assets/characters/guanyu.glb"
    manifest_path = path.parent / "animation_manifest.json"
    manifest = json.loads(manifest_path.read_text())
    glb = GLB(path)
    hip = glb.names["mixamorig:Hips"]
    groups = [("J1", "J2", "J3", "J4"), ("K",), ("Q",), ("E",), ("UCharge", "U")]
    inputs = [(path, manifest["guanyu"]["grip"], group) for group in groups]
    baked = {}
    with ProcessPoolExecutor(max_workers=len(groups)) as workers:
        for group in workers.map(bake_group, inputs):
            baked.update(group)
    scene = deepcopy(glb.j)
    scene["animations"] = [a for a in scene["animations"] if not a["name"].startswith(PREFIX)]
    binary = compact_buffers(scene, glb.bin)
    result = {"clips": {}}

    def track(values, kind):
        data = np.asarray(values, dtype="<f4")
        binary.extend(b"\0" * (-len(binary) % 4))
        view = len(scene["bufferViews"])
        scene["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": data.nbytes})
        binary.extend(data.tobytes())
        accessor = {"bufferView": view, "componentType": 5126, "count": len(data), "type": kind}
        if kind == "SCALAR":
            accessor.update(min=[float(data.min())], max=[float(data.max())])
        scene["accessors"].append(accessor)
        return len(scene["accessors"]) - 1

    for name in PHRASES:
        times, frames, edges, stats, root_positions = baked[name]
        alias = PREFIX + name
        duration = float(times[-1])
        root = [[0.0, 0.0, round(float(z), 6)] for z in root_positions]
        result["clips"][alias] = {"duration": duration, "root": root,
                                  "edge": [[round(float(v), 6) for v in edge] for edge in edges]}
        time_index = track(times, "SCALAR")
        animation = {"name": alias, "samplers": [], "channels": []}

        def channel(node, mode, values, kind):
            animation["channels"].append({"sampler": len(animation["samplers"]),
                                           "target": {"node": node, "path": mode}})
            animation["samplers"].append({"input": time_index, "output": track(values, kind),
                                           "interpolation": "LINEAR"})

        for i in glb.j["skins"][0]["joints"]:
            keys = [frame["pose"][i][1] for frame in frames]
            for k in range(1, len(keys)):
                if np.dot(keys[k], keys[k - 1]) < 0:
                    keys[k] = -keys[k]
            channel(i, "rotation", keys, "VEC4")
        channel(hip, "translation", [f["pose"][hip][0] for f in frames], "VEC3")
        scene["animations"].append(animation)
        stats = np.array(stats)
        check = {"tip_min_m": float(stats[:, 1].min() * SCALE), "tail_min_m": float(stats[:, 2].min() * SCALE),
                 "wrist_max_deg": float(stats[:, 3].max()), "grasp_spacing_error_max_m": float(stats[:, 4].max() * SCALE),
                 "ankle_unreachable_max_m": float(stats[:, 5].max() * SCALE)}
        if check["wrist_max_deg"] > 45.0 or check["grasp_spacing_error_max_m"] > .003 or check["ankle_unreachable_max_m"] > .005:
            raise ValueError(f"Anatomical bounds exceeded for {alias}: {check}")
        if min(check["tip_min_m"], check["tail_min_m"]) < -.03:
            raise ValueError(f"Blade goes below the ground in {alias}: {check}")
        print(alias, check, flush=True)
    binary = compact_buffers(scene, binary)
    write_glb(path, scene, binary)
    record = manifest["guanyu"]
    record["runtime_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    record["duel_crescent"] = {
        "author": "Wenfeng project",
        "scope": "foot duel",
        "sample_hz": HZ,
        "clips": {alias: data["duration"] for alias, data in result["clips"].items()},
        "reference": "Public Phantom Blade Zero Crescent Blade demonstrations, used as choreography reference",
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    meta = ROOT / "assets/motion/guanyu_crescent.json"
    meta.write_text(json.dumps(result, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
