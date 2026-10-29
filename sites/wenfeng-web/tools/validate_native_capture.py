"""Validate native_combat_capture output integrity, never animation quality.

Requires Pillow + NumPy; ffmpeg must be on PATH (or pass --ffmpeg).
Usage: python3 validate_capture.py CAPTURE_DIR --encode
"""
import argparse
import json
import shutil
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image


def barcode(rgb):
    return sum(int(rgb[16, 11 + bit * 8].mean() > 128) << bit for bit in range(16))


def body_difference(folder, first, second):
    coords = np.array(list(first['player']['screen_bones'].values())
                      + list(second['player']['screen_bones'].values()))
    if not coords.size:
        return {'frames': [first['index'], second['index']], 'missing_bones': True}
    x0, y0 = np.floor(coords.min(0) - [28, 12]).astype(int)
    x1, y1 = np.ceil(coords.max(0) + [28, 12]).astype(int)
    rect = [max(0, int(x0)), max(40, int(y0)), min(1280, int(x1)), min(760, int(y1))]
    if rect[2] <= rect[0] or rect[3] <= rect[1]:
        return {'frames': [first['index'], second['index']], 'offscreen': True}
    arrays = [np.asarray(Image.open(folder / 'frames' / f'{row["index"]:05d}.jpg')
                         .convert('RGB').crop(rect), dtype=float) for row in [first, second]]
    delta = np.abs(arrays[0] - arrays[1]).mean(2)
    return {'frames': [first['index'], second['index']], 'roi': rect,
            'mean_pixel_abs_difference': float(delta.mean()),
            'changed_pixel_fraction_over_8': float((delta > 8).mean())}


def video_barcodes(ffmpeg, video, expected):
    command = [ffmpeg, '-v', 'error', '-i', str(video), '-vf', 'crop=140:32:0:0',
               '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1']
    proc = subprocess.Popen(command, stdout=subprocess.PIPE)
    index, errors = 0, []
    size = 140 * 32 * 3
    while True:
        data = proc.stdout.read(size)
        if not data:
            break
        if len(data) != size:
            raise RuntimeError('Incomplete decoded video frame')
        value = barcode(np.frombuffer(data, np.uint8).reshape(32, 140, 3))
        if value != index:
            errors.append([index, value])
        index += 1
    code = proc.wait()
    return {'frames': index, 'expected': expected, 'barcode_errors': errors, 'decoder_exit': code}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--encode', action='store_true', help='Encode ordered JPGs to capture.mp4')
    parser.add_argument('--video', type=Path, help='Existing movie to validate; default: CAPTURE_DIR/capture.mp4')
    parser.add_argument('--ffmpeg', default=shutil.which('ffmpeg'))
    args = parser.parse_args()
    folder = args.capture.resolve()
    trace = json.loads((folder / 'trace.json').read_text())
    rows = trace['frames']
    images = sorted((folder / 'frames').glob('*.jpg'))
    expected = trace['seconds'] * trace['fps']
    errors = []
    for index, path in enumerate(images):
        rgb = np.asarray(Image.open(path).convert('RGB'))
        value = barcode(rgb)
        if value != index or int(path.stem) != index:
            errors.append({'file': path.name, 'expected': index, 'barcode': value})
    ticks = sorted({b['physics_frame'] - a['physics_frame'] for a, b in zip(rows, rows[1:])})
    observer_lags = sorted({row['physics_frame'] - row['player'].get('bone_sample_physics_frame', row['physics_frame'])
                            for row in rows})
    probes = {}
    for stage in dict.fromkeys(row['stage'] for row in rows):
        active = [row for row in rows if row['stage'] == stage
                  and row['player']['state'] in ['attack', 'skill', 'ultimate', 'dodge', 'move']]
        # These are visual freeze checks at several actual poses, not a test
        # of good foot planting, impact timing, or source-faithful animation.
        selected = active[::12]
        probes[stage] = [body_difference(folder, a, b) for a, b in zip(selected, selected[1:])]
    video = args.video.resolve() if args.video else folder / 'capture.mp4'
    if args.encode:
        if not args.ffmpeg:
            raise RuntimeError('ffmpeg is required for --encode')
        subprocess.run([args.ffmpeg, '-hide_banner', '-loglevel', 'warning', '-y',
                        '-framerate', str(trace['fps']), '-i', str(folder / 'frames/%05d.jpg'),
                        '-c:v', 'libx264', '-preset', 'fast', '-crf', '18', '-pix_fmt', 'yuv420p',
                        '-movflags', '+faststart', str(video)], check=True)
    encoded = video_barcodes(args.ffmpeg, video, expected) if video.exists() and args.ffmpeg else None
    passed = len(images) == len(rows) == expected and not errors and ticks == [1]
    static_stages = [stage for stage, pairs in probes.items() if pairs
                     and max(pair.get('mean_pixel_abs_difference', 0.) for pair in pairs) < 0.5]
    passed = passed and not static_stages
    if encoded:
        passed = passed and encoded['frames'] == expected and not encoded['barcode_errors'] and encoded['decoder_exit'] == 0
    report = {'passed_capture_integrity': passed, 'expected_frames': expected,
              'image_frames': len(images), 'trace_frames': len(rows), 'barcode_errors': errors,
              'physics_frame_deltas': ticks, 'observer_frame_lags': observer_lags,
              'suspected_frozen_stages': static_stages,
              'bone_sample_point': trace.get('bone_sample_point', 'unspecified'),
              'body_change_evidence': probes, 'encoded_video': encoded,
              'limitation': 'Barcode and body-region changes detect capture failures. They do not approve animation quality or real-time performance.'}
    (folder / 'capture-validation.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['passed_capture_integrity', 'image_frames', 'barcode_errors',
                                           'physics_frame_deltas', 'observer_frame_lags', 'encoded_video']}, indent=2))
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()
