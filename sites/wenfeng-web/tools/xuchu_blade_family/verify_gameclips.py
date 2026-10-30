#!/usr/bin/env python3
"""Verify serialized gameplay clips against untouched native source keys."""
from pathlib import Path
import argparse
import hashlib
import json
import numpy as np
from gltf_tools import GLB

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--input', required=True, type=Path)
p.add_argument('--output', required=True, type=Path)
p.add_argument('--meta', required=True, type=Path)
p.add_argument('--report', required=True, type=Path)
a = p.parse_args()
g = GLB(a.input)
out = GLB(a.output)
meta = json.loads(a.meta.read_text())
hip = g.names['mixamorig:Hips']
assert out.bin[:len(g.bin)] == g.bin
assert out.j['animations'][:len(g.j['animations'])] == g.j['animations']
for k in g.j:
    if k not in ('buffers', 'bufferViews', 'accessors', 'animations'):
        assert out.j[k] == g.j[k], k


def tracks(glb, alias):
    result = {}
    for c in glb.anims[alias]['channels']:
        s = glb.anims[alias]['samplers'][c['sampler']]
        result[(c['target']['node'], c['target']['path'])] = (glb.accessor(s['input'])[:, 0].astype(float), glb.accessor(s['output']).astype(float))
    return result


source = {alias: tracks(g, alias) for alias in g.anims if alias.startswith('XuAnatomy_')}
report = {'original_binary_prefix_preserved': True, 'original_scene_skin_mesh_preserved': True, 'original_aliases_preserved': True, 'clips': {}}
anchor = np.array(meta['root_anchor_local_model'])
for alias, info in meta['clips'].items():
    dst = tracks(out, alias)
    ts = np.array(info['times'])
    assert len(ts) == round(info['duration'] * 120) + 1
    assert np.max(np.abs(np.diff(ts) - 1 / 120)) < 1e-12
    expected_root = []
    max_key_time_error = 0.
    max_unchanged_component_error = 0.
    max_unchanged_rotation_component_error = 0.
    for i, t in enumerate(ts):
        segment = info['segments'][0]
        for candidate in info['segments'][1:]:
            if t > candidate['output_start'] + 1e-9:
                segment = candidate
        st = segment['source_start'] + t - segment['output_start']
        if info['static']:
            st = 0.
        src = source[segment['source_alias']]
        for key, (actual_times, actual_values) in dst.items():
            input_times, input_values = src[key]
            j = int(np.argmin(np.abs(input_times - st)))
            max_key_time_error = max(max_key_time_error, float(abs(input_times[j] - st)))
            expected = input_values[j].copy()
            actual = actual_values[i]
            if key == (hip, 'translation'):
                initial_index = np.argmin(np.abs(src[(hip, 'translation')][0] - segment['source_start']))
                delta = expected - src[(hip, 'translation')][1][initial_index]
                root = np.array(segment['root_accumulated_start_model']) + delta
                root[1] = 0
                expected_root.append(root)
                expected[[0, 2]] = anchor[[0, 2]]
            if key[1] == 'rotation':
                error = min(np.max(np.abs(actual - expected)), np.max(np.abs(actual + expected)))
                max_unchanged_rotation_component_error = max(max_unchanged_rotation_component_error, float(error))
            else:
                max_unchanged_component_error = max(max_unchanged_component_error, float(np.max(np.abs(actual - expected))))
        assert abs(actual_times[i] - t) < 2e-7
    root_error = float(np.max(np.abs(np.array(expected_root) - np.array(info['root_delta_model']))))
    assert max_key_time_error < 2e-7
    assert max_unchanged_component_error < 2e-8
    assert max_unchanged_rotation_component_error == 0
    assert root_error < 1e-12
    report['clips'][alias] = {'samples': len(ts), 'max_native_key_time_error_seconds': max_key_time_error, 'max_unmodified_local_component_error': max_unchanged_component_error, 'max_unmodified_rotation_component_error': max_unchanged_rotation_component_error, 'max_root_curve_error_model': root_error}

ct = tracks(g, 'XuAnatomy_Sword_Regular_Combo')[(hip, 'translation')]
def combo_root(t):
    return ct[1][np.argmin(np.abs(ct[0] - t))]

j1 = meta['clips']['XuBladeJ1']
j2 = meta['clips']['XuBladeJ2']
j3 = meta['clips']['XuBladeJ3']
p1 = np.array(j1['root_delta_model'])[round(j1['chain_time'] * 120)]
p2 = np.array(j2['root_delta_model'])[round(j2['chain_time'] * 120)]
p3 = np.array(j3['root_delta_model'])[-1]
expected1 = combo_root(1) - combo_root(0)
expected3 = combo_root(3) - combo_root(0)
expected1[1] = expected3[1] = 0
chain_err = max(float(np.max(np.abs(p1 + p2 - expected1))), float(np.max(np.abs(p1 + p2 + p3 - expected3))))
assert chain_err < 1e-12
report['native_combo_root_chain_max_error_model'] = chain_err
report['passed'] = True
report['output_sha256'] = hashlib.sha256(a.output.read_bytes()).hexdigest()
a.report.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
