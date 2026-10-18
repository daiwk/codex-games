#!/usr/bin/env python3
"""Rebuild the two user horse rigs without changing their original files.

The Tripo exports have invalid inverse-bind bytes, zero-length rest skeletons,
no animation, and almost all vertices attached to Root.  We discard that rig,
fit the CC0 Quaternius horse's anatomical skeleton, transfer weights separately
for the four limbs/body/tail, and retarget its authored three locomotion clips.
Original positions are only rotated and uniformly scaled; UVs/triangles remain.
Preparation dependency: numpy, scipy, Pillow. Runtime has no Python dependency.
"""
from pathlib import Path
from copy import deepcopy
from io import BytesIO
import argparse
import hashlib
import json
import numpy as np
from PIL import Image
from scipy.interpolate import RBFInterpolator
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree
from scipy.spatial.transform import Rotation as R, Slerp
from gltf_tools import GLB, compact_buffers, write_glb

ROOT = Path(__file__).resolve().parents[3]
RAW = ROOT / 'godot-games/3a-games'
REFERENCE = RAW / 'source/third_party/horse/Horse.glb'
CALIBRATION = RAW / 'source/third_party/horse/mount_calibration.json'
OUT = Path(__file__).resolve().parents[1] / 'godot/assets/mounts'
SCALE = .46
IDENTITY = np.array([0., 0., 0., 1.])
COLORS = {'brown': ('马_棕色.glb', 2.67), 'white': ('马_白色.glb', 2.33)}
LEGS = ['front_left', 'front_right', 'rear_left', 'rear_right']


def matrix(t, q, s=(1., 1., 1.)):
    m = np.eye(4)
    m[:3, :3] = R.from_quat(q).as_matrix() @ np.diag(s)
    m[:3, 3] = t
    return m


class Reference:
    def __init__(self):
        self.g = GLB(REFERENCE)
        self.rest = self.world()
        self.ids = list(range(2, 67))
        self.map = {old: new + 1 for new, old in enumerate(self.ids)}
        self.names = self.g.names
        self.inverse = self.g.accessor(self.g.j['skins'][0]['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
        self.joints = self.g.j['skins'][0]['joints']
        self.channels = {}
        for clip in ['Idle', 'Walk', 'Gallop']:
            self.channels[clip] = []
            a = self.g.anims[clip]
            for c in a['channels']:
                sa = a['samplers'][c['sampler']]
                ts, vs = self.g.accessor(sa['input'])[:, 0], self.g.accessor(sa['output'])
                interp = Slerp(ts, R.from_quat(vs)) if c['target']['path'] == 'rotation' and len(ts) > 1 else None
                self.channels[clip].append((c['target']['node'], c['target']['path'], ts, vs, interp))
        self.vertices, self.weights, self.labels = self.skin_reference()

    def world(self, name=None, time=0.):
        trs = {i: [np.array(n.get('translation', [0., 0., 0.])), np.array(n.get('rotation', IDENTITY)), np.array(n.get('scale', [1., 1., 1.]))] for i, n in enumerate(self.g.nodes)}
        if name:
            for ni, path, ts, vs, interp in self.channels[name]:
                t = np.clip(time, ts[0], ts[-1])
                if len(ts) == 1:
                    value = vs[0]
                elif interp is not None:
                    value = interp(t).as_quat()
                else:
                    value = np.array([np.interp(t, ts, vs[:, i]) for i in range(vs.shape[1])])
                trs[ni][{'translation': 0, 'rotation': 1, 'scale': 2}[path]] = value
        w = {}
        for i in self.g.order:
            m = matrix(*trs[i])
            w[i] = w[self.g.parents[i]] @ m if i in self.g.parents else m
        return w

    def skin_reference(self):
        transforms = np.stack([self.rest[j] @ inv for j, inv in zip(self.joints, self.inverse)])
        vertices, weights, labels = [], [], []
        for p in self.g.j['meshes'][0]['primitives']:
            v = self.g.accessor(p['attributes']['POSITION'])
            ji, we = self.g.accessor(p['attributes']['JOINTS_0']), self.g.accessor(p['attributes']['WEIGHTS_0'])
            mats = (transforms[ji] * we[:, :, None, None]).sum(1)
            vertices.append(np.einsum('nij,nj->ni', mats, np.c_[v, np.ones(len(v))])[:, :3] * SCALE)
            dense = np.zeros((len(v), 65))
            for col in range(4):
                for j, old in enumerate(self.joints):
                    dense[:, self.map[old] - 1] += np.where(ji[:, col] == j, we[:, col], 0.)
            weights.append(dense)
            dom = dense.argmax(1)
            labels.extend([region(self.g.nodes[self.ids[i]]['name']) for i in dom])
        return np.vstack(vertices), np.vstack(weights), np.array(labels)


def region(name):
    if name.startswith('Tail'):
        return 'tail'
    suffix = 'left' if name.endswith('.L') else 'right'
    if name.startswith(('Front', 'IKFront', 'FF.')):
        return 'front_' + suffix
    if name.startswith(('BackShoulder', 'BackLeg', 'BackUpper', 'BackLower', 'IKBack', 'FFB')):
        return 'rear_' + suffix
    return 'body'


def ray_top(v, tri, x, z):
    t = v[tri]
    origin, direction = np.array([x, 10., z]), np.array([0., -1., 0.])
    e1, e2 = t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]
    h = np.cross(direction, e2)
    a = np.einsum('ij,ij->i', e1, h)
    f = np.zeros(len(a)); valid = abs(a) > 1e-10; f[valid] = 1. / a[valid]
    s = origin - t[:, 0]
    u = f * np.einsum('ij,ij->i', s, h)
    q = np.cross(s, e1)
    vv = f * (q @ direction)
    tt = f * np.einsum('ij,ij->i', e2, q)
    valid &= (u >= 0) & (vv >= 0) & (u + vv <= 1) & (tt > 0)
    return float(10. - tt[valid].min()) if valid.any() else 1.6


def fit(ref, meta, v, scale, orient, center, color):
    def normalized(raw):
        return (np.array(raw) - center) @ orient.T * scale
    def slice_at(leg, height):
        if height == 0:
            xz = meta['hoof_xz'][leg]
            return normalized([xz[0], .025, xz[1]])
        return normalized(meta['leg_slices'][str(height)][leg])
    source, target = [], []
    def add(name, point):
        source.append(ref.rest[ref.names[name]][:3, 3] * SCALE)
        target.append(np.array(point))
    for leg in LEGS:
        side = '.L' if leg.endswith('left') else '.R'
        front = leg.startswith('front')
        levels = [('FrontUpperLeg', .42), ('FrontLowerLeg', .2), ('IKFrontLeg', .08), ('FF', 0)] if front else [('BackLeg', .5), ('BackUpperLeg', .35), ('BackLowerLeg', .2), ('IKBackLeg', .08), ('FFB', 0)]
        for name, height in levels:
            add(name + side, slice_at(leg, height))
        ankle = slice_at(leg, .08)
        add(('FrontLowerLeg' if front else 'BackLowerLeg') + side + '_end', ankle)
        toe = slice_at(leg, 0); toe[1] = .003; toe[2] += .035
        add(('FF' if front else 'FFB') + side + '_end', toe)
    back_z = float(np.mean([slice_at(l, .5)[2] for l in LEGS if l.startswith('rear')]))
    front_z = float(np.mean([slice_at(l, .42)[2] for l in LEGS if l.startswith('front')]))
    # Spine sits inside the body; a separate MountSaddle socket is measured
    # against the real dorsal mesh surface rather than these interior joints.
    add('Body', [0, .45, 0])
    add('Back', [0, 1.40, back_z + .03])
    add('Torso', [0, 1.33, -.32])
    add('Torso2', [0, 1.30, -.05])
    add('Torso3', [0, 1.30, front_z - .08])
    head_x = .0 if color == 'brown' else .14
    head_z = 1.075 if color == 'brown' else .91
    head_y = 1.95 if color == 'brown' else 2.015
    add('Neck1', [0, 1.53, front_z + .04])
    add('Neck2', [head_x * .3, 1.69, head_z - .22])
    add('Neck3', [head_x * .7, 1.86, head_z - .10])
    add('Head', [head_x, head_y, head_z])
    for side, sign in [('.L', 1), ('.R', -1)]:
        add('Ear1' + side, [head_x + sign * .075, head_y + .035, head_z - .025])
        add('Ear4' + side + '_end', [head_x + sign * .105, float(v[:, 1].max()) - .025, head_z + .025])
    tail = v[(v[:, 2] < back_z - .17) & (abs(v[:, 0]) < .20)]
    tail_min = float(np.percentile(tail[:, 1], 4)) if len(tail) else .3
    tail_z = float(np.median(tail[tail[:, 1] < .7, 2])) if np.any(tail[:, 1] < .7) else -1.1
    add('Tail2', [0, 1.49, back_z - .12])
    add('Tail4', [0, 1.1, tail_z])
    add('Tail7_end', [0, tail_min, tail_z])
    source, target = np.array(source), np.array(target)
    # TPS has a single-valued deformation field. Merge coincident anatomical
    # controls (the source ankle endpoint and independent IK root coincide).
    keys = np.round(source, 4)
    _, unique = np.unique(keys, axis=0, return_index=True)
    warp = RBFInterpolator(source[unique], target[unique], kernel='thin_plate_spline', smoothing=.0002)
    return warp, {leg: [slice_at(leg, h).tolist() for h in [0, .08, .2, .35, .42, .5]] for leg in LEGS}, np.array([head_x, head_y, head_z])


def transfer_weights(ref, warp, v, leg_paths, triangles):
    labels = np.full(len(v), 'body', dtype='<U12')
    distances = []
    for leg in LEGS:
        p = np.array(leg_paths[leg])
        x = np.interp(v[:, 1], p[:, 1], p[:, 0])
        z = np.interp(v[:, 1], p[:, 1], p[:, 2])
        distances.append(np.hypot(v[:, 0] - x, v[:, 2] - z))
    distances = np.array(distances).T
    nearest = distances.argmin(1)
    # Anatomical assignment prevents opposite legs from sharing weights.
    for i, leg in enumerate(LEGS):
        ceiling = .98 if leg.startswith('front') else 1.15
        pick = (nearest == i) & (v[:, 1] < ceiling) & (distances[:, i] < .26)
        labels[pick] = leg
    # Tail hair is authored as disconnected surface components. Weld only for
    # this connectivity query (never alter runtime vertices or UV seams), then
    # select complete posterior hair components. A plane through individual
    # points would split a continuous strand between tail and body weights.
    welded, inverse = np.unique(np.round(v, 5), axis=0, return_inverse=True)
    tri_welded = inverse[triangles]
    edge = np.vstack([tri_welded[:, [0, 1]], tri_welded[:, [1, 2]], tri_welded[:, [2, 0]]])
    graph = coo_matrix((np.ones(len(edge)), (edge[:, 0], edge[:, 1])), shape=(len(welded), len(welded))).tocsr()
    count, components = connected_components(graph, directed=False)
    for component in range(count):
        points = welded[components == component]
        if points[:, 2].min() < -.9 and points[:, 1].max() < 1.7:
            labels[components[inverse] == component] = 'tail'
    fitted = warp(ref.vertices)
    dense = np.zeros((len(v), 65))
    for group in ['body', 'tail'] + LEGS:
        src = np.flatnonzero(ref.labels == group)
        dst = np.flatnonzero(labels == group)
        if not len(dst):
            continue
        distance, indices = cKDTree(fitted[src]).query(v[dst], k=min(6, len(src)))
        factor = 1. / np.maximum(distance, .015) ** 2
        factor /= factor.sum(1, keepdims=True)
        dense[dst] = (ref.weights[src[indices]] * factor[:, :, None]).sum(1)
    # Feather only the top of each limb into the adjacent trunk, never to
    # another leg. It keeps the shoulder/haunch crease smooth at full stride.
    body_src = np.flatnonzero(ref.labels == 'body')
    body_tree = cKDTree(fitted[body_src])
    for leg in LEGS:
        ceiling = .98 if leg.startswith('front') else 1.15
        dst = np.flatnonzero((labels == leg) & (v[:, 1] > ceiling - .22))
        if not len(dst):
            continue
        _, idx = body_tree.query(v[dst], k=3)
        body = ref.weights[body_src[idx]].mean(1)
        mix = np.clip((v[dst, 1] - (ceiling - .22)) / .22, 0, .75)
        dense[dst] = dense[dst] * (1. - mix[:, None]) + body * mix[:, None]
    joints = np.argsort(dense, axis=1)[:, -4:][:, ::-1]
    weights = np.take_along_axis(dense, joints, axis=1)
    weights /= weights.sum(1, keepdims=True)
    assert np.isfinite(weights).all()
    return joints.astype('<u2'), weights.astype('<f4'), labels


def build(color, ref, max_texture=2048):
    filename, scale = COLORS[color]
    original = RAW / filename
    g = GLB(original)
    meta = json.loads(CALIBRATION.read_text())[filename]
    forward = np.array([meta['forward_xz'][0], 0, meta['forward_xz'][1]])
    orient = np.array([np.cross([0, 1, 0], forward), [0, 1, 0], forward])
    center = np.array([meta['body_center_xz'][0], 0, meta['body_center_xz'][1]])
    p = g.j['meshes'][0]['primitives'][0]
    vertices = (g.accessor(p['attributes']['POSITION']) - center) @ orient.T * scale
    normals = g.accessor(p['attributes']['NORMAL']) @ orient.T
    triangles = g.accessor(p['indices'])[:, 0].reshape(-1, 3)
    warp, leg_paths, head = fit(ref, meta, vertices, scale, orient, center, color)
    joints, weights, labels = transfer_weights(ref, warp, vertices, leg_paths, triangles)
    hoof_vertices = np.isin(labels, LEGS) & (vertices[:, 1] < .25)
    scene, blob = deepcopy(g.j), bytearray(g.bin)
    def append_array(values, kind, component=5126):
        dtype = {5126: '<f4', 5123: '<u2'}[component]
        data = np.asarray(values, dtype=dtype)
        blob.extend(b'\0' * (-len(blob) % 4))
        vi = len(scene['bufferViews'])
        scene['bufferViews'].append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': data.nbytes})
        blob.extend(data.tobytes())
        a = {'bufferView': vi, 'componentType': component, 'count': len(data), 'type': kind}
        if kind in ['SCALAR', 'VEC3']:
            a['min'], a['max'] = data.min(0).tolist(), data.max(0).tolist()
        scene['accessors'].append(a)
        return len(scene['accessors']) - 1
    mesh = scene['meshes'][0]['primitives'][0]
    mesh['attributes']['POSITION'] = append_array(vertices, 'VEC3')
    mesh['attributes']['NORMAL'] = append_array(normals, 'VEC3')
    mesh['attributes']['JOINTS_0'] = append_array(joints, 'VEC4', 5123)
    mesh['attributes']['WEIGHTS_0'] = append_array(weights, 'VEC4')
    # A tangent imported from the old coordinate system is invalid. Godot
    # derives matching tangents from the preserved normals/UVs at import.
    mesh['attributes'].pop('TANGENT', None)
    rest_pos = np.array([ref.rest[i][:3, 3] * SCALE for i in ref.ids])
    bind_pos = warp(rest_pos)
    bind_rot = R.from_matrix(np.array([ref.rest[i][:3, :3] / np.linalg.norm(ref.rest[i][:3, :3], axis=0) for i in ref.ids]))
    # Align each segment's bind axis to the fitted anatomical segment.
    align = []
    for k, old in enumerate(ref.ids):
        children = [c for c in ref.g.nodes[old].get('children', []) if c in ref.map]
        if children:
            c = ref.ids.index(children[0]); a = rest_pos[c] - rest_pos[k]; b = bind_pos[c] - bind_pos[k]
            if np.linalg.norm(a) > .0001 and np.linalg.norm(b) > .0001:
                a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
                cross = np.cross(a, b); sine = np.linalg.norm(cross)
                q = R.from_rotvec(cross / max(sine, 1e-10) * np.arctan2(sine, np.dot(a, b)))
            else:
                q = R.identity()
        else:
            q = R.identity()
        align.append(q.as_quat())
    bind_rot = R.from_quat(align) * bind_rot
    nodes = [{'name': 'HorseRig', 'children': []}]
    bind_world = []
    for k, old in enumerate(ref.ids):
        parent_old = ref.g.parents.get(old)
        parent_new = ref.map.get(parent_old, 0)
        w = matrix(bind_pos[k], bind_rot[k].as_quat())
        bind_world.append(w)
        parent_w = bind_world[parent_new - 1] if parent_new else np.eye(4)
        local = np.linalg.inv(parent_w) @ w
        nodes.append({'name': ref.g.nodes[old]['name'], 'translation': local[:3, 3].tolist(), 'rotation': R.from_matrix(local[:3, :3]).as_quat().tolist(), 'children': []})
        nodes[parent_new]['children'].append(k + 1)
    saddle_z = -.18
    saddle_x = float(np.median(vertices[(abs(vertices[:, 2] - saddle_z) < .08) & (vertices[:, 1] > 1.25), 0]))
    saddle = np.array([saddle_x, ray_top(vertices, triangles, saddle_x, saddle_z), saddle_z])
    torso = ref.map[ref.names['Torso2']]
    local_saddle = np.linalg.inv(bind_world[torso - 1]) @ np.r_[saddle, 1.]
    socket = len(nodes)
    nodes.append({'name': 'MountSaddle', 'translation': local_saddle[:3].tolist()})
    nodes[torso]['children'].append(socket)
    # Include a neutral socket in the skin joint list so Godot imports it as
    # an actual bone, even though no horse vertices are attached to it.
    saddle_world = bind_world[torso - 1] @ matrix(local_saddle[:3], IDENTITY)
    inverse = np.linalg.inv(np.array(bind_world + [saddle_world])).transpose(0, 2, 1).reshape(-1, 16)
    skin = {'name': 'RebuiltHorseSkin', 'skeleton': 0, 'joints': list(range(1, 66)) + [socket], 'inverseBindMatrices': append_array(inverse, 'MAT4')}
    nodes[0]['children'].append(len(nodes))
    nodes.append({'name': 'Horse_' + color, 'mesh': 0, 'skin': 0})
    scene['nodes'], scene['skins'], scene['scenes'], scene['scene'] = nodes, [skin], [{'nodes': [0]}], 0
    scene['animations'] = []
    frame_reports = {}
    bind_inv = np.linalg.inv(np.array(bind_world))
    source_rest_rotation = R.from_matrix(np.array([ref.rest[i][:3, :3] / np.linalg.norm(ref.rest[i][:3, :3], axis=0) for i in ref.ids]))
    for clip in ['Idle', 'Walk', 'Gallop']:
        duration = ref.g.duration(clip)
        times = np.linspace(0, duration, int(round(duration * 30)) + 1)
        out_t = np.zeros((len(times), 65, 3)); out_q = np.zeros((len(times), 65, 4)); floors = []
        for fi, time in enumerate(times):
            src_world = ref.world(clip, time)
            src_rotation = R.from_matrix(np.array([src_world[i][:3, :3] / np.linalg.norm(src_world[i][:3, :3], axis=0) for i in ref.ids]))
            rotations = src_rotation * source_rest_rotation.inv() * bind_rot
            worlds = np.zeros((65, 4, 4))
            # A fitted rest pose is static anatomy. Warping all animated world
            # positions would make the true femur/shin lengths change during
            # each stride. Retarget rotations, then FK the fixed bind offsets.
            for k, old in enumerate(ref.ids):
                name = ref.g.nodes[old]['name']
                po = ref.g.parents.get(old)
                parent = ref.map.get(po, 0)
                if name == 'Body':
                    position = warp((src_world[old][:3, 3] * SCALE)[None])[0]
                elif name.startswith(('IKFrontLeg', 'IKBackLeg')):
                    end_name = ('FrontLowerLeg' if name.startswith('IKFront') else 'BackLowerLeg') + name[-2:] + '_end'
                    end = ref.map[ref.names[end_name]] - 1
                    offset = bind_rot[end].inv().apply(bind_pos[k] - bind_pos[end])
                    position = worlds[end][:3, 3] + R.from_matrix(worlds[end][:3, :3]).apply(offset)
                elif parent:
                    position = (worlds[parent - 1] @ np.r_[nodes[k + 1]['translation'], 1.])[:3]
                else:
                    position = bind_pos[k]
                worlds[k] = matrix(position, rotations[k].as_quat())
            # Long layered hair follows the rump rigidly. The supplied ears
            # likewise retain their original shape relative to the head;
            # independent reference ear motions otherwise shear tiny edges
            # where the fitted left/right ear weights meet.
            back = ref.map[ref.names['Back']] - 1
            rump_delta = worlds[back] @ bind_inv[back]
            if clip == 'Gallop':
                # Raise the long hair as one rigid bundle while galloping.
                # Positive X rotation carries a backward/downward tail up and
                # farther behind the horse. Gait blending fades this naturally.
                pivot = bind_pos[ref.map[ref.names['Tail2']] - 1]
                lift_rotation = R.from_euler('x', 25., degrees=True)
                tail_lift = matrix(pivot - lift_rotation.apply(pivot), lift_rotation.as_quat())
                rump_delta = rump_delta @ tail_lift
            head_index = ref.map[ref.names['Head']] - 1
            head_delta = worlds[head_index] @ bind_inv[head_index]
            for k, old in enumerate(ref.ids):
                name = ref.g.nodes[old]['name']
                if name.startswith('Tail'):
                    worlds[k] = rump_delta @ bind_world[k]
                elif name.startswith('Ear'):
                    worlds[k] = head_delta @ bind_world[k]
            mats = worlds @ bind_inv
            skin_mats = (mats[joints] * weights[:, :, None, None]).sum(1)
            posed = np.einsum('nij,nj->ni', skin_mats, np.c_[vertices, np.ones(len(vertices))])[:, :3]
            # Ground the four hooves, not the hanging tail. The source's
            # animated toe ends preserve its brief airborne gallop phases;
            # walk/idle keep the lowest hoof planted at ground level.
            target_floor = 0.
            if clip == 'Gallop':
                toe_names = ['FF.L_end', 'FF.R_end', 'FFB.L_end', 'FFB.R_end']
                target_floor = max(0., min(src_world[ref.names[n]][1, 3] for n in toe_names) * SCALE - .001)
            foot_floor = float(posed[hoof_vertices, 1].min())
            lift = target_floor - foot_floor
            worlds[:, 1, 3] += lift
            floors.append(foot_floor + lift)
            for k, old in enumerate(ref.ids):
                parent_new = ref.map.get(ref.g.parents.get(old), 0)
                local = np.linalg.inv(worlds[parent_new - 1]) @ worlds[k] if parent_new else worlds[k]
                out_t[fi, k] = local[:3, 3]
                out_q[fi, k] = R.from_matrix(local[:3, :3]).as_quat()
        animation = {'name': clip, 'samplers': [], 'channels': []}
        input_index = append_array(times[:, None], 'SCALAR')
        for k in range(65):
            # Continuous signs avoid long-way quaternion interpolation.
            for fi in range(1, len(times)):
                if np.dot(out_q[fi - 1, k], out_q[fi, k]) < 0:
                    out_q[fi, k] *= -1
            for path, data, typ in [('translation', out_t[:, k], 'VEC3'), ('rotation', out_q[:, k], 'VEC4')]:
                si = len(animation['samplers'])
                animation['samplers'].append({'input': input_index, 'output': append_array(data, typ), 'interpolation': 'LINEAR'})
                animation['channels'].append({'sampler': si, 'target': {'node': k + 1, 'path': path}})
        scene['animations'].append(animation)
        frame_reports[clip] = {'frames': len(times), 'duration': duration, 'minimum_floor': min(floors), 'maximum_floor': max(floors)}
    for im in scene['images']:
        view = scene['bufferViews'][im['bufferView']]
        image = Image.open(BytesIO(blob[view.get('byteOffset', 0):view.get('byteOffset', 0) + view['byteLength']]))
        image.thumbnail((max_texture, max_texture), Image.Resampling.LANCZOS)
        stream = BytesIO()
        if im.get('mimeType') == 'image/jpeg':
            image.convert('RGB').save(stream, format='JPEG', quality=91, optimize=True)
        else:
            image.save(stream, format='PNG', optimize=True)
        blob.extend(b'\0' * (-len(blob) % 4)); im['bufferView'] = len(scene['bufferViews'])
        data = stream.getvalue()
        scene['bufferViews'].append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data)})
        blob.extend(data)
    scene.setdefault('asset', {})['generator'] = 'Wenfeng prepare_mounts.py: user Tripo geometry, fitted rig and CC0 Quaternius locomotion'
    scene['extras'] = {'source_geometry': filename, 'animation_license': 'CC0-1.0', 'front_axis': '+Z', 'units': 'metres', 'rebuilt_corrupt_skin': True}
    blob = compact_buffers(scene, blob)
    output = OUT / ('horse_' + color + '.glb')
    write_glb(output, scene, blob)
    body = vertices[(abs(vertices[:, 2] + .1) < .2) & (vertices[:, 1] > .95) & (vertices[:, 1] < 1.5)]
    result = {'file': output.name, 'source': filename, 'source_sha256': hashlib.sha256(original.read_bytes()).hexdigest(), 'source_uniform_scale': scale, 'source_yaw_degrees': meta['yaw_y_degrees_to_plus_z'], 'model_scale': 1., 'bounds_min': vertices.min(0).tolist(), 'bounds_max': vertices.max(0).tolist(), 'saddle_surface': saddle.tolist(), 'seat_offset_y': .05, 'head_anchor': head.tolist(), 'belly_width': float(np.ptp(body[:, 0])), 'vertices': len(vertices), 'triangles': len(triangles), 'weighted_bones': int(len(np.unique(joints[weights > .01]))), 'max_texture': max_texture, 'clips': frame_reports, 'regions': {label: int((labels == label).sum()) for label in np.unique(labels)}}
    print(json.dumps({color: result}, ensure_ascii=False, indent=2))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--color', choices=['brown', 'white', 'all'], default='all')
    parser.add_argument('--max-texture', type=int, default=2048)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / 'manifest.json'
    manifest = json.loads(path.read_text()) if path.exists() else {}
    ref = Reference()
    for color in COLORS if args.color == 'all' else [args.color]:
        manifest[color] = build(color, ref, args.max_texture)
    manifest['provenance'] = {'geometry': 'User-supplied Tripo models; original exports are retained unchanged.', 'motion': 'Quaternius Animated Farm Animals, CC0-1.0; see assets/licenses/Horse-CC0.txt.', 'preparation': 'tools/prepare_mounts.py', 'reference_sha256': hashlib.sha256(REFERENCE.read_bytes()).hexdigest()}
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
