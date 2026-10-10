import json
import math
import struct
import sys
from pathlib import Path

COMPONENT_FORMAT = {5126: ("f", 4), 5123: ("H", 2), 5125: ("I", 4)}
TYPE_COUNT = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}

path = Path(sys.argv[1])
with path.open("rb") as handle:
    handle.read(12)
    json_length, json_type = struct.unpack("<II", handle.read(8))
    document = json.loads(handle.read(json_length))
    bin_length, bin_type = struct.unpack("<II", handle.read(8))
    binary = handle.read(bin_length)

def accessor_values(index):
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    fmt, component_size = COMPONENT_FORMAT[accessor["componentType"]]
    component_count = TYPE_COUNT[accessor["type"]]
    stride = view.get("byteStride", component_size * component_count)
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    values = []
    for row in range(accessor["count"]):
        start = offset + row * stride
        values.append(struct.unpack_from("<" + fmt * component_count, binary, start))
    return values

for animation in document.get("animations", []):
    if animation.get("name") not in {"Idle", "Run", "Attack1", "Heavy", "Dash"}:
        continue
    rows = []
    for channel in animation["channels"]:
        target = channel["target"]
        node_name = document["nodes"][target["node"]].get("name", "")
        if target["path"] != "rotation" or node_name not in {"DEF-upper_arm.R", "DEF-forearm.R", "DEF-spine.003", "DEF-thigh.R"}:
            continue
        sampler = animation["samplers"][channel["sampler"]]
        values = accessor_values(sampler["output"])
        base = values[0]
        max_delta = max(math.sqrt(sum((v[i] - base[i]) ** 2 for i in range(4))) for v in values)
        rows.append((node_name, len(values), round(max_delta, 6), tuple(round(v, 4) for v in base), tuple(round(v, 4) for v in values[len(values)//2])))
    print(animation.get("name"), rows)
