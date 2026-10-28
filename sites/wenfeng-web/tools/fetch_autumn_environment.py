#!/usr/bin/env python3
"""Restore the reviewed CC0 courtyard textures from their recorded URLs.

No API key or third-party package is required. Existing valid files are kept.
"""
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'source-assets/environment/autumn_court/SOURCE.json'
DEST = ROOT / 'godot/assets/environment/autumn_court'


def main():
    manifest = json.loads(SOURCE.read_text())
    DEST.mkdir(parents=True, exist_ok=True)
    for row in manifest['files']:
        target = DEST / row['file']
        if target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == row['sha256']:
            print('Verified', row['file'])
            continue
        request = urllib.request.Request(row['url'], headers={'User-Agent': 'Wenfeng-CC0-asset-restore/1.0'})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
        if len(data) != row['bytes'] or hashlib.sha256(data).hexdigest() != row['sha256']:
            raise ValueError('Source bytes failed verification: ' + row['file'])
        temporary = target.with_suffix(target.suffix + '.tmp')
        temporary.write_bytes(data)
        temporary.replace(target)
        print('Restored', row['file'])


if __name__ == '__main__':
    main()
