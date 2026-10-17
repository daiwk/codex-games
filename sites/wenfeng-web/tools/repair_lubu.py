#!/usr/bin/env python3
"""Remove the two grey triangle fans at Lu Bu's plume tips, preserving his rig.

Run from the complete repository. The unedited input is backed up once under
godot-games/3a-games/source/originals/ before the corrected main GLB is written.
"""
import hashlib
import json
from pathlib import Path

import numpy as np

from gltf_tools import GLB, write_glb

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / 'godot-games/3a-games'


def main():
    path = ASSETS / '吕布.glb'
    backup = ASSETS / 'source/originals/吕布.glb'
    raw = path.read_bytes()
    source = GLB(path)
    primitive = source.j['meshes'][0]['primitives'][0]
    positions = source.accessor(primitive['attributes']['POSITION'])
    accessor = source.j['accessors'][primitive['indices']]
    indices = source.accessor(primitive['indices']).reshape(-1, 3)
    # These are the three duplicated, remote apex vertices shared by the two
    # untextured fans. No plume edge, armor, UV, skin weight or bone is edited.
    apex = np.flatnonzero((np.abs(positions[:, 0]) > .34)
                         & (positions[:, 1] > .30) & (positions[:, 1] < .31)
                         & (positions[:, 2] < -.20))
    removed = np.isin(indices, apex).any(axis=1)
    if removed.sum() == 0 and backup.is_file():
        print('Lu Bu is already repaired.')
        return
    if len(apex) != 3 or removed.sum() != 12:
        raise ValueError('Unexpected mesh: review the plume-tip faces before editing.')
    backup.parent.mkdir(parents=True, exist_ok=True)
    if backup.exists() and backup.read_bytes() != raw:
        raise ValueError('An original backup already exists with different content.')
    backup.write_bytes(raw)
    dtype = {5123: '<u2', 5125: '<u4'}[accessor['componentType']]
    kept = indices[~removed].astype(dtype).reshape(-1)
    view = source.j['bufferViews'][accessor['bufferView']]
    offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    binary = bytearray(source.bin)
    binary[offset:offset + kept.nbytes] = kept.tobytes()
    accessor['count'] = len(kept)
    accessor['min'], accessor['max'] = [int(kept.min())], [int(kept.max())]
    write_glb(path, source.j, binary)
    report = {'original_sha256': hashlib.sha256(raw).hexdigest(),
              'fixed_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'removed_triangle_indices': np.flatnonzero(removed).tolist(),
              'triangles_before': len(indices), 'triangles_after': len(kept) // 3,
              'preserved': 'All vertex attributes, UVs, textures, materials, bones, weights and bind matrices'}
    backup.with_suffix('.repair.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
