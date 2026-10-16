#!/usr/bin/env python3
"""Fetch and verify the pinned official single-threaded Godot Web template."""
import hashlib
from pathlib import Path
import struct
import subprocess
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".cache"
VERSION = "4.7.2"
URL = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/Godot_v{VERSION}-stable_export_templates.tpz"
TEMPLATE_SHA256 = "d3ee2f08cef0cf3cf6678a6355a92a8db48ccdd35cbd2e8bfd5f0e8a0b4032a0"


def download(url, dest, byte_range=None, limit=None):
    dest.parent.mkdir(parents=True, exist_ok=True)
    args = ["curl", "--fail", "--location", "--silent", "--show-error", "--retry", "2", "--connect-timeout", "20", "--max-time", "300"]
    if byte_range:
        args += ["--range", byte_range]
    if limit:
        args += ["--max-filesize", str(limit)]
    partial = dest.with_name(dest.name + '.download')
    subprocess.run(args + [url, "--output", str(partial)], check=True)
    partial.replace(dest)
    return dest.read_bytes()


def fetch_template():
    target = CACHE / "web_nothreads_release.zip"
    if target.exists():
        if hashlib.sha256(target.read_bytes()).hexdigest() != TEMPLATE_SHA256:
            raise RuntimeError("Cached Web template checksum does not match the pinned official release")
        print(f"Cached Web template: {target.stat().st_size:,} bytes", flush=True)
        return
    with tempfile.TemporaryDirectory(prefix="wenfeng-web-template-") as tmp:
        tmp = Path(tmp)
        # Pinned upstream archive length; explicit ranges also work on hosts
        # whose object storage does not support suffix-byte requests.
        archive_size = 1281349702
        tail_path = CACHE / "templates-tail.bin"
        tail = tail_path.read_bytes() if tail_path.exists() else download(URL, tail_path, f"{archive_size-65536}-{archive_size-1}", 100000)
        eocd = tail.rfind(b"PK\x05\x06")
        if eocd < 0:
            raise RuntimeError("Official template ZIP directory is missing")
        header = struct.unpack_from("<4s4H2LH", tail, eocd)
        cd_size, cd_offset = header[5], header[6]
        directory = tail[cd_offset-(archive_size-len(tail)):eocd]
        if len(directory) != cd_size:
            raise RuntimeError("Official ZIP directory falls outside the retained tail")
        offset = 0
        found = None
        while offset < len(directory):
            entry = struct.unpack_from("<4s6H3L5H2L", directory, offset)
            if entry[0] != b"PK\x01\x02":
                raise RuntimeError("Unexpected central directory entry")
            name = directory[offset+46:offset+46+entry[10]].decode()
            if name == "templates/web_nothreads_release.zip":
                found = entry
                break
            offset += 46 + entry[10] + entry[11] + entry[12]
        if not found:
            raise RuntimeError("Single-threaded Web release template was not found")
        start, compressed_size = found[16], found[8]
        record = download(URL, tmp / "packed", f"{start}-{start+compressed_size+4095}", compressed_size+4097)
        local = struct.unpack_from("<4s5H3L2H", record)
        data_offset = 30 + local[9] + local[10]
        packed = record[data_offset:data_offset+compressed_size]
        if len(packed) != compressed_size or local[0] != b"PK\x03\x04":
            raise RuntimeError("Incorrect range response from template server")
        data = zlib.decompress(packed, -15) if found[4] == 8 else packed
        if len(data) != found[9] or zlib.crc32(data) != found[7]:
            raise RuntimeError("Official Web template ZIP CRC verification failed")
        if hashlib.sha256(data).hexdigest() != TEMPLATE_SHA256:
            raise RuntimeError("Official Web template SHA256 verification failed")
        target.write_bytes(data)
        print(f"Verified official Web template: {len(data):,} bytes; SHA256 {hashlib.sha256(data).hexdigest()}", flush=True)


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    fetch_template()


if __name__ == "__main__":
    main()
