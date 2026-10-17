"""Small glTF binary helpers for the reproducible, offline animation bake.

Geometry and bind data are copied from user assets; original files are never
modified. Requires NumPy and SciPy only when preparing new animated models.
"""
from pathlib import Path
from copy import deepcopy
import json
import struct
import numpy as np
from scipy.spatial.transform import Rotation as R, Slerp
IDENTITY = np.array([0., 0., 0., 1.])

class GLB:
    def __init__(self, path):
        self.path = Path(path)
        raw = Path(path).read_bytes()
        size, kind = struct.unpack_from('<II', raw, 12)
        self.j = json.loads(raw[20:20 + size])
        offset = 20 + size
        n, kind = struct.unpack_from('<II', raw, offset)
        self.bin = raw[offset + 8:offset + 8 + n]
        self.nodes = self.j['nodes']
        self.parents = {c: i for i, n in enumerate(self.nodes) for c in n.get('children', [])}
        self.names = {n.get('name', ''): i for i, n in enumerate(self.nodes)}
        self.anims = {a['name']: a for a in self.j.get('animations', [])}
        self.order = []

        def visit(i):
            self.order.append(i)
            for c in self.nodes[i].get('children', []):
                visit(c)

        for i in range(len(self.nodes)):
            if i not in self.parents:
                visit(i)

    def accessor(self, i):
        a = self.j['accessors'][i]
        b = self.j['bufferViews'][a['bufferView']]
        types = {5126: '<f4', 5125: '<u4', 5123: '<u2', 5121: 'u1'}
        widths = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
        dtype = np.dtype(types[a['componentType']])
        w = widths[a['type']]
        start = b.get('byteOffset', 0) + a.get('byteOffset', 0)
        return np.ndarray((a['count'], w), dtype=dtype, buffer=self.bin, offset=start,
                          strides=(b.get('byteStride', dtype.itemsize * w), dtype.itemsize)).copy()

    def duration(self, name):
        return max(float(self.accessor(s['input'])[-1, 0]) for s in self.anims[name]['samplers'])

    def pose(self, name=None, time=0.):
        poses = {}
        for i, n in enumerate(self.nodes):
            poses[i] = [np.array(n.get('translation', [0., 0., 0.])),
                        np.array(n.get('rotation', IDENTITY))]
        if name:
            a = self.anims[name]
            for c in a['channels']:
                target = c['target']
                if target['path'] not in ('rotation', 'translation'):
                    continue
                s = a['samplers'][c['sampler']]
                times = self.accessor(s['input'])[:, 0]
                values = self.accessor(s['output'])
                t = np.clip(time, times[0], times[-1])
                if len(times) == 1:
                    value = values[0]
                elif target['path'] == 'rotation':
                    value = Slerp(times, R.from_quat(values))(t).as_quat()
                else:
                    value = np.array([np.interp(t, times, values[:, axis]) for axis in range(3)])
                poses[target['node']][target['path'] == 'rotation'] = value
        return self.world(poses), poses

    def world(self, poses):
        world = {}
        for i in self.order:
            tr, q = poses[i]
            rot = R.from_quat(q)
            if i in self.parents:
                pt, pr = world[self.parents[i]]
                world[i] = (pt + pr.apply(tr), pr * rot)
            else:
                world[i] = (tr.copy(), rot)
        return world

def compact_buffers(scene, binary):
    """Discard unused source accessors and buffer ranges.

    Copy referenced binary ranges verbatim; mesh/texture values are unchanged.
    """
    used = set()
    for mesh in scene['meshes']:
        for p in mesh['primitives']:
            used.update(p['attributes'].values())
            if 'indices' in p:
                used.add(p['indices'])
    for skin in scene['skins']:
        used.add(skin['inverseBindMatrices'])
    for animation in scene['animations']:
        for sampler in animation['samplers']:
            used.update([sampler['input'], sampler['output']])
    accessors = sorted(used)
    remap = {old: new for new, old in enumerate(accessors)}
    scene['accessors'] = [scene['accessors'][i] for i in accessors]
    views = {a['bufferView'] for a in scene['accessors']}
    views.update(i['bufferView'] for i in scene['images'])
    view_map = {}
    packed, output_views = bytearray(), []
    for i in sorted(views):
        view = deepcopy(scene['bufferViews'][i])
        start = view.get('byteOffset', 0)
        packed.extend(b'\0' * (-len(packed) % 4))
        view['byteOffset'] = len(packed)
        packed.extend(binary[start:start + view['byteLength']])
        view_map[i] = len(output_views)
        output_views.append(view)
    for a in scene['accessors']:
        a['bufferView'] = view_map[a['bufferView']]
    for i in scene['images']:
        i['bufferView'] = view_map[i['bufferView']]
    scene['bufferViews'] = output_views
    for mesh in scene['meshes']:
        for p in mesh['primitives']:
            p['attributes'] = {name: remap[index] for name, index in p['attributes'].items()}
            if 'indices' in p:
                p['indices'] = remap[p['indices']]
    for skin in scene['skins']:
        skin['inverseBindMatrices'] = remap[skin['inverseBindMatrices']]
    for animation in scene['animations']:
        for sampler in animation['samplers']:
            sampler['input'], sampler['output'] = remap[sampler['input']], remap[sampler['output']]
    scene['buffers'] = [{'byteLength': len(packed)}]
    return packed

def write_glb(path, scene, blob):
    scene['buffers'] = [{'byteLength': len(blob)}]
    j = json.dumps(scene, separators=(',', ':')).encode()
    j += b' ' * (-len(j) % 4)
    blob = bytearray(blob)
    blob.extend(b'\0' * (-len(blob) % 4))
    raw = struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(j) + 8 + len(blob))
    raw += struct.pack('<II', len(j), 0x4E4F534A) + j
    raw += struct.pack('<II', len(blob), 0x004E4942) + blob
    Path(path).write_bytes(raw)
