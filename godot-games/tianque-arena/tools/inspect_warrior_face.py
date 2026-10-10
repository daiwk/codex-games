import bpy
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
SOURCE = PROJECT / "source/third_party/quaternius/rpg-characters/upstream/FBX/Warrior.fbx"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(SOURCE))
rig = bpy.data.objects.get("CharacterArmature")
face = bpy.data.objects.get("Face")
print("RIG_MATRIX", [[round(v, 4) for v in row] for row in rig.matrix_world])
head = rig.data.bones.get("Head")
print("HEAD", tuple(round(v, 4) for v in head.head_local), tuple(round(v, 4) for v in head.tail_local), "matrix", [[round(v,4) for v in row] for row in head.matrix_local])
points = [face.matrix_world @ vertex.co for vertex in face.data.vertices]
print("FACE_BOUNDS", tuple(round(min(p[i] for p in points),4) for i in range(3)), tuple(round(max(p[i] for p in points),4) for i in range(3)))
# Front-most vertices by both Y extremes help establish whether the face looks -Y or +Y.
for direction in ("min_y", "max_y"):
    selected=sorted(points,key=lambda p:p.y,reverse=direction=="max_y")[:20]
    print(direction,[(round(p.x,3),round(p.y,3),round(p.z,3)) for p in selected])
uv_layer = face.data.uv_layers.active.data
front_loops = []
for polygon in face.data.polygons:
    center = face.matrix_world @ polygon.center
    if center.y < -0.30:
        entries = []
        for loop_index in polygon.loop_indices:
            vertex_index = face.data.loops[loop_index].vertex_index
            position = face.matrix_world @ face.data.vertices[vertex_index].co
            uv = uv_layer[loop_index].uv
            entries.append((vertex_index, tuple(round(v, 4) for v in position), tuple(round(v, 5) for v in uv)))
        front_loops.append((polygon.index, tuple(round(v, 4) for v in center), entries))
print("FRONT_UV_POLYGONS", front_loops)
for material_index, slot in enumerate(face.material_slots):
    print("FACE_MATERIAL", material_index, slot.material.name if slot.material else None)
