import json
import struct
import sys
from pathlib import Path


def read_glb(path: Path) -> dict:
    with path.open("rb") as handle:
        magic, version, length = struct.unpack("<4sII", handle.read(12))
        if magic != b"glTF" or version != 2:
            raise ValueError(f"not a glTF 2 binary: {path}")
        chunk_length, chunk_type = struct.unpack("<II", handle.read(8))
        if chunk_type != 0x4E4F534A:
            raise ValueError("first GLB chunk is not JSON")
        document = json.loads(handle.read(chunk_length).decode("utf-8"))
    document["_file_length"] = length
    return document


def accessor_count(document: dict, primitive: dict) -> int:
    index = primitive.get("indices")
    if index is not None:
        return document["accessors"][index].get("count", 0)
    position = primitive.get("attributes", {}).get("POSITION")
    return document["accessors"][position].get("count", 0) if position is not None else 0


for name in sys.argv[1:]:
    source = Path(name)
    glb = read_glb(source)
    primitives = [p for mesh in glb.get("meshes", []) for p in mesh.get("primitives", [])]
    position_accessors = [
        glb["accessors"][p["attributes"]["POSITION"]]
        for p in primitives
        if "POSITION" in p.get("attributes", {})
    ]
    bounds = {
        "min": [min((a.get("min", [0, 0, 0])[axis] for a in position_accessors), default=0) for axis in range(3)],
        "max": [max((a.get("max", [0, 0, 0])[axis] for a in position_accessors), default=0) for axis in range(3)],
    }
    info = {
        "name": source.name,
        "megabytes": round(source.stat().st_size / 1024 / 1024, 1),
        "nodes": len(glb.get("nodes", [])),
        "meshes": len(glb.get("meshes", [])),
        "primitives": len(primitives),
        "indexed_vertices": sum(accessor_count(glb, p) for p in primitives),
        "materials": len(glb.get("materials", [])),
        "textures": len(glb.get("textures", [])),
        "images": len(glb.get("images", [])),
        "bounds_untransformed": bounds,
        "extensions": glb.get("extensionsUsed", []),
    }
    print(json.dumps(info, ensure_ascii=False))
