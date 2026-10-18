#!/usr/bin/env python3
"""Prepare the supplied saddle without overwriting its original Tripo GLB.

Keep every triangle and UV. Rotate +X front to +Z, scale into metres, resize
albedo only, and spread the hanging panels to each horse's actual flank.
Brown is the base mesh; one WhiteFit morph uses the same topology and texture.
The saddle's upper frame, seat and bridges retain their supplied shape.
"""
from pathlib import Path
from copy import deepcopy
from io import BytesIO
import hashlib
import json
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree
from gltf_tools import GLB, write_glb

ROOT = Path(__file__).resolve().parents[3]
WEB = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'godot-games/3a-games/马鞍.glb'
OUTPUT = WEB / 'godot/assets/mounts/saddle.glb'
CONFIG = OUTPUT.with_name('saddle_manifest.json')
SCALE = .90
CONTACT = np.array([0., .58543, 0.])
SEAT = np.array([0., .74322, 0.])
ORIENT = np.array([[0., 0., -1.], [0., 1., 0.], [1., 0., 0.]])
CLEARANCE = .035
PANEL_GAP = .016
RIDER_HIP_CLEARANCE = .060


def lateral_bounds(v, triangles, yz, inner=False):
    """Intersect X rays with the real horse flank using YZ barycentrics.

    Triangles are dense; 160 nearest projected centroids contain both sides.
    Use 512 candidates for missed rays before deciding the sample is outside.
    """
    t = v[triangles]
    tree = cKDTree(t[:, :, 1:].mean(1))
    lo, hi = np.full(len(yz), np.nan), np.full(len(yz), np.nan)
    for count in [160, 512]:
        todo = np.flatnonzero(~np.isfinite(lo) | ~np.isfinite(hi))
        for start in range(0, len(todo), 256):
            rows = todo[start:start + 256]
            _, ix = tree.query(yz[rows], k=count)
            sample = t[ix]
            a = sample[:, :, 0, 1:]
            b = sample[:, :, 1, 1:] - a
            c = sample[:, :, 2, 1:] - a
            d = yz[rows, None, :] - a
            determinant = b[:, :, 0] * c[:, :, 1] - b[:, :, 1] * c[:, :, 0]
            valid = abs(determinant) > 1e-10
            det = np.where(valid, determinant, 1.)
            u = (d[:, :, 0] * c[:, :, 1] - d[:, :, 1] * c[:, :, 0]) / det
            w = (b[:, :, 0] * d[:, :, 1] - b[:, :, 1] * d[:, :, 0]) / det
            valid &= (u >= -1e-5) & (w >= -1e-5) & (u + w <= 1.00001)
            x = sample[:, :, 0, 0] + u * (sample[:, :, 1, 0] - sample[:, :, 0, 0]) + w * (sample[:, :, 2, 0] - sample[:, :, 0, 0])
            if inner:
                low = np.where(valid & (x < -.03), x, -np.inf).max(1)
                high = np.where(valid & (x > .03), x, np.inf).min(1)
                hit = np.isfinite(low) & np.isfinite(high)
            else:
                hit = valid.any(1)
                low = np.where(valid, x, np.inf).min(1)
                high = np.where(valid, x, -np.inf).max(1)
            lo[rows[hit]], hi[rows[hit]] = low[hit], high[hit]
    return lo, hi


def fit_panels(base, source_normals, triangles, horse, mount):
    pr = horse.j['meshes'][0]['primitives'][0]
    hv = horse.accessor(pr['attributes']['POSITION'])
    ht = horse.accessor(pr['indices'])[:, 0].reshape(-1, 3)
    offset = np.array(mount['saddle_surface']) + [0., CLEARANCE, 0.]
    world = base + offset
    lo, hi = lateral_bounds(hv, ht, world[:, 1:])
    inner_left, inner_right = lateral_bounds(base, triangles, base[:, 1:], inner=True)
    fitted = base.copy()
    # Only side panels below the frame need to follow the two flanks. Nothing
    # above 12 cm over the contact point is deformed (seat/bridges untouched).
    blend = np.clip((.12 - base[:, 1]) / .07, 0., 1.)
    active = np.isfinite(lo) & np.isfinite(inner_left) & (abs(base[:, 0]) > .07) & (blend > 0.)
    target = world[:, 0].copy()
    right = active & (base[:, 0] > 0.)
    left = active & (base[:, 0] < 0.)
    # Translate the whole section by its inner-wall clearance. Clamping each
    # vertex separately to one flank would collapse the original thickness
    # and buckle/cloth relief into a paper-thin surface.
    target[right] += np.maximum(0., hi[right] + PANEL_GAP - (inner_right[right] + offset[0]))
    target[left] -= np.maximum(0., (inner_left[left] + offset[0]) - (lo[left] - PANEL_GAP))
    fitted[:, 0] += (target - world[:, 0]) * blend
    # Smooth just the sideways displacement over welded UV seams; the outer
    # silhouette and all panel details move together, never split by a cut.
    welded, inverse = np.unique(np.round(base, 6), axis=0, return_inverse=True)
    displacement = fitted[:, 0] - base[:, 0]
    sums = np.bincount(inverse, weights=displacement)
    counts = np.bincount(inverse)
    fitted[:, 0] = base[:, 0] + (sums / counts)[inverse]
    face = np.cross(fitted[triangles[:, 1]] - fitted[triangles[:, 0]], fitted[triangles[:, 2]] - fitted[triangles[:, 0]])
    normal = np.zeros_like(welded)
    for col in range(3):
        np.add.at(normal, inverse[triangles[:, col]], face)
    normal = normal[inverse]
    normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-10)
    normal = np.where((normal * source_normals).sum(1, keepdims=True) < 0., -normal, normal)
    normal = source_normals * (1. - blend[:, None]) + normal * blend[:, None]
    normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-10)
    # Actual interior points must be outside the flanks, not merely hidden.
    still_inside = active & (blend > .999) & (fitted[:, 0] + offset[0] > lo + .002) & (fitted[:, 0] + offset[0] < hi - .002)
    assert not still_inside.any(), 'Saddle panels must clear the supplied horse flank'
    return fitted, normal, {'saddle_offset': [0., CLEARANCE, 0.], 'seat_surface_y': float((SEAT[1] - CONTACT[1]) * SCALE + CLEARANCE), 'rider_seat_y': float((SEAT[1] - CONTACT[1]) * SCALE + CLEARANCE + RIDER_HIP_CLEARANCE), 'flank_clearance_m': PANEL_GAP, 'panel_adjusted_vertices': int(np.sum(abs(displacement) > .001)), 'panel_max_expansion_m': float(abs(displacement).max()), 'bounds_min': fitted.min(0).tolist(), 'bounds_max': fitted.max(0).tolist()}


def main():
    raw = GLB(SOURCE)
    scene = deepcopy(raw.j)
    p = raw.j['meshes'][0]['primitives'][0]
    base = (raw.accessor(p['attributes']['POSITION']) - CONTACT) @ ORIENT.T * SCALE
    source_normals = raw.accessor(p['attributes']['NORMAL']) @ ORIENT.T
    uv = raw.accessor(p['attributes']['TEXCOORD_0'])
    triangles = raw.accessor(p['indices'])[:, 0].reshape(-1, 3)
    mount_manifest = json.loads(OUTPUT.with_name('manifest.json').read_text())
    fits, vertices, normals = {}, {}, {}
    for color in ['brown', 'white']:
        horse = GLB(OUTPUT.with_name('horse_' + color + '.glb'))
        vertices[color], normals[color], fits[color] = fit_panels(base, source_normals, triangles, horse, mount_manifest[color])
    blob = bytearray()
    scene['accessors'], scene['bufferViews'] = [], []
    def append_array(values, kind, component=5126):
        data = np.asarray(values, dtype={5126: '<f4', 5123: '<u2'}[component])
        blob.extend(b'\0' * (-len(blob) % 4))
        vi = len(scene['bufferViews'])
        scene['bufferViews'].append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': data.nbytes})
        blob.extend(data.tobytes())
        acc = {'bufferView': vi, 'componentType': component, 'count': len(data), 'type': kind}
        if kind in ['SCALAR', 'VEC3']:
            acc['min'], acc['max'] = data.min(0).tolist(), data.max(0).tolist()
        scene['accessors'].append(acc)
        return len(scene['accessors']) - 1
    primitive = {'attributes': {'POSITION': append_array(vertices['brown'], 'VEC3'), 'NORMAL': append_array(normals['brown'], 'VEC3'), 'TEXCOORD_0': append_array(uv, 'VEC2')}, 'indices': append_array(triangles.reshape(-1, 1), 'SCALAR', 5123), 'material': 0, 'targets': [{'POSITION': append_array(vertices['white'] - vertices['brown'], 'VEC3'), 'NORMAL': append_array(normals['white'] - normals['brown'], 'VEC3')}]}
    scene['meshes'] = [{'name': 'FittedSaddle', 'primitives': [primitive], 'weights': [0.], 'extras': {'targetNames': ['WhiteFit']}}]
    scene['nodes'] = [{'name': 'Saddle', 'mesh': 0}]
    scene['scenes'], scene['scene'], scene['skins'], scene['animations'] = [{'nodes': [0]}], 0, [], []
    for im in scene['images']:
        source_view = raw.j['bufferViews'][im['bufferView']]
        start = source_view.get('byteOffset', 0)
        image = Image.open(BytesIO(raw.bin[start:start + source_view['byteLength']])).convert('RGB')
        image.thumbnail((2048, 2048), Image.Resampling.LANCZOS)
        stream = BytesIO(); image.save(stream, 'JPEG', quality=91, optimize=True)
        data = stream.getvalue(); blob.extend(b'\0' * (-len(blob) % 4))
        im['bufferView'] = len(scene['bufferViews']); im['mimeType'] = 'image/jpeg'
        scene['bufferViews'].append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data)})
        blob.extend(data)
    scene['asset']['generator'] = 'Wenfeng prepare_saddle.py: user Tripo geometry, per-horse side-panel fitting'
    scene['extras'] = {'source': SOURCE.name, 'units': 'metres', 'front_axis': '+Z', 'geometry_unchanged_above_local_y': .12}
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    write_glb(OUTPUT, scene, blob)
    manifest = {'source': str(SOURCE.relative_to(ROOT)), 'source_bytes': SOURCE.stat().st_size, 'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(), 'file': OUTPUT.name, 'runtime_bytes': OUTPUT.stat().st_size, 'vertices': len(base), 'triangles': len(triangles), 'texture_maximum': 2048, 'source_to_runtime': {'uniform_scale': SCALE, 'yaw_degrees': -90., 'source_contact': CONTACT.tolist(), 'source_seat': SEAT.tolist()}, 'fits': fits, 'white_blend_shape': 'WhiteFit', 'provenance': 'User-supplied Tripo saddle; original remains unchanged. Original triangles/UV and textured upper seat/frame preserved. Lower hanging panels fit each supplied horse flank.'}
    CONFIG.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    archive = ROOT / 'godot-games/glb-manifest.json'
    saved = json.loads(archive.read_text())
    path = str(SOURCE.relative_to(ROOT))
    old = [e for e in saved['files'] if e['path'] == path]
    record = {'path': path, 'bytes': SOURCE.stat().st_size, 'sha256': manifest['source_sha256']}
    if old:
        assert old[0] == record, 'Existing raw saddle hash must remain unchanged'
    else:
        saved['files'].append(record)
        saved['files'].sort(key=lambda e: e['path'])
        archive.write_text(json.dumps(saved, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
