import bpy
import json
import os
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT / "source/third_party/quaternius/rpg-characters/upstream"

CAST = {
    "Warrior": {
        "output": "assets/characters/tianque_hero.glb",
        "blend": "source/hero/quaternius_warrior.blend",
        "aliases": {
            "Idle": "Idle_Weapon", "Run": "Run_Weapon",
            "Attack1": "Sword_Attack", "Attack2": "Sword_AttackFast",
            "Attack3": "Sword_Attack", "Heavy": "Sword_AttackFast",
            "Dash": "Roll", "Skill": "Punch",
            "Hit": "RecieveHit_Attacking", "Death": "Death",
        },
    },
    "Rogue": {
        "output": "assets/characters/enemies/guard_rogue.glb",
        "blend": "source/cast/guard_rogue.blend",
        "aliases": {
            "Idle": "Attacking_Idle", "Run": "Run",
            "Attack": "Dagger_Attack", "Attack2": "Dagger_Attack2",
            "Cast": "Dagger_Attack2", "Dash": "Roll",
            "Hit": "RecieveHit_Attacking", "Death": "Death",
        },
    },
    "Monk": {
        "output": "assets/characters/enemies/brute_monk.glb",
        "blend": "source/cast/brute_monk.blend",
        "aliases": {
            "Idle": "Idle_Attacking", "Run": "Run",
            "Attack": "Attack", "Attack2": "Attack2",
            "Cast": "Attack2", "Dash": "Roll",
            "Hit": "RecieveHit_Attacking", "Death": "Death",
        },
    },
    "Wizard": {
        "output": "assets/characters/enemies/caster_wizard.glb",
        "blend": "source/cast/caster_wizard.blend",
        "aliases": {
            "Idle": "Idle_Weapon", "Run": "Run_Weapon",
            "Attack": "Staff_Attack", "Attack2": "Staff_Attack",
            "Cast": "Spell1", "Cast2": "Spell2",
            "Hit": "RecieveHit_Attacking", "Death": "Death",
        },
    },
    "Cleric": {
        "output": "assets/characters/enemies/boss_cleric.glb",
        "blend": "source/cast/boss_cleric.blend",
        "aliases": {
            "Idle": "Idle_Weapon", "Run": "Run_Weapon",
            "Attack": "Staff_Attack", "Attack2": "Staff_Attack",
            "Cast": "Spell1", "Cast2": "Spell2",
            "Hit": "RecieveHit_Attacking", "Death": "Death",
        },
    },
}


def _barycentric(px, py, a, b, c):
    denominator = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(denominator) < 1.0e-9:
        return None
    w0 = ((b[1] - c[1]) * (px - c[0]) + (c[0] - b[0]) * (py - c[1])) / denominator
    w1 = ((c[1] - a[1]) * (px - c[0]) + (a[0] - c[0]) * (py - c[1])) / denominator
    return w0, w1, 1.0 - w0 - w1


def _feature_color(x, z):
    # Facial marks are evaluated in the actual Face mesh coordinates and then
    # rasterized through that mesh's UVs. They therefore lie on the skin and
    # deform with it; no independent spheres or floating boxes are exported.
    for center_x in (-0.088, 0.088):
        eye = ((x - center_x) / 0.044) ** 2 + ((z - 2.655) / 0.016) ** 2
        if eye <= 1.0:
            pupil = ((x - center_x) / 0.011) ** 2 + ((z - 2.654) / 0.013) ** 2
            if pupil <= 1.0:
                return (0.055, 0.028, 0.018, 1.0)
            # Muted sclera keeps the face readable without the previous white
            # bead appearance.
            return (0.63, 0.54, 0.42, 1.0)
    mouth_curve = 2.495 - 0.010 * (x / 0.060) ** 2
    if abs(x) <= 0.060 and abs(z - mouth_curve) <= 0.006:
        return (0.20, 0.040, 0.028, 1.0)
    return None


def paint_face_texture(image, face):
    width, height = image.size
    pixels = list(image.pixels[:])
    mesh = face.data
    uv_data = mesh.uv_layers.active.data
    painted = set()
    for polygon in mesh.polygons:
        # The character looks toward -Y. Only rasterize outward-facing front
        # skin so mirrored/back UV islands cannot receive facial marks.
        center = face.matrix_world @ polygon.center
        if center.y > -0.30 or polygon.normal.y > -0.05:
            continue
        loops = list(polygon.loop_indices)
        for fan_index in range(1, len(loops) - 1):
            triangle_loops = (loops[0], loops[fan_index], loops[fan_index + 1])
            uvs = []
            positions = []
            for loop_index in triangle_loops:
                uv = uv_data[loop_index].uv
                uvs.append((uv.x * (width - 1), uv.y * (height - 1)))
                vertex_index = mesh.loops[loop_index].vertex_index
                positions.append(face.matrix_world @ mesh.vertices[vertex_index].co)
            min_x = max(0, int(min(uv[0] for uv in uvs)) - 1)
            max_x = min(width - 1, int(max(uv[0] for uv in uvs)) + 1)
            min_y = max(0, int(min(uv[1] for uv in uvs)) - 1)
            max_y = min(height - 1, int(max(uv[1] for uv in uvs)) + 1)
            for pixel_y in range(min_y, max_y + 1):
                for pixel_x in range(min_x, max_x + 1):
                    weights = _barycentric(pixel_x + 0.5, pixel_y + 0.5, *uvs)
                    if weights is None or min(weights) < -0.0001:
                        continue
                    point = positions[0] * weights[0] + positions[1] * weights[1] + positions[2] * weights[2]
                    color = _feature_color(point.x, point.z)
                    if color is None:
                        continue
                    offset = (pixel_y * width + pixel_x) * 4
                    pixels[offset:offset + 4] = color
                    painted.add((pixel_x, pixel_y))
    image.pixels[:] = pixels
    image.update()
    print("FACE_TEXTURE_PIXELS=" + str(len(painted)))


def embed_texture(character):
    path = ROOT / "Textures" / (character + "_Texture.png")
    image = bpy.data.images.load(str(path), check_existing=False)
    if character == "Warrior":
        face = bpy.data.objects.get("Face")
        if face is None:
            raise RuntimeError("Warrior Face mesh was not found")
        paint_face_texture(image, face)
        generated = PROJECT / "assets/characters/tianque_hero_face.png"
        image.filepath_raw = str(generated)
        image.file_format = 'PNG'
        image.save()
    image.pack()
    for mat in list(bpy.data.materials):
        if character.lower() not in mat.name.lower() and not mat.name.lower().endswith("texture"):
            continue
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        links = mat.node_tree.links
        bsdf = nodes.get("Principled BSDF")
        if bsdf is None:
            continue
        node = next((item for item in nodes if item.type == 'TEX_IMAGE'), None) or nodes.new("ShaderNodeTexImage")
        node.image = image
        if not bsdf.inputs["Base Color"].is_linked:
            links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.62


def export_character(character, config):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(ROOT / "FBX" / (character + ".fbx")))
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == 'ARMATURE')
    rig.name = rig.data.name = "Tianque" + character + "Rig"
    rig.animation_data_create()
    for track in list(rig.animation_data.nla_tracks):
        rig.animation_data.nla_tracks.remove(track)
    source_actions = {action.name.split('|')[-1]: action for action in bpy.data.actions}
    selected = []
    for alias, upstream in config["aliases"].items():
        action = source_actions[upstream].copy()
        action.name = alias
        action.use_fake_user = True
        selected.append(action)
        track = rig.animation_data.nla_tracks.new()
        track.name = alias
        strip = track.strips.new(alias, 1, action)
        strip.action_frame_start, strip.action_frame_end = action.frame_range
    rig.animation_data.action = None
    embed_texture(character)
    output = PROJECT / config["output"]
    blend = PROJECT / config["blend"]
    output.parent.mkdir(parents=True, exist_ok=True)
    blend.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    desired = {
        "filepath": str(output), "export_format": "GLB", "use_selection": False,
        "export_animations": True, "export_skins": True, "export_morph": False,
        "export_apply": True, "export_force_sampling": True,
        "export_animation_mode": "NLA_TRACKS", "export_nla_strips": True,
    }
    bpy.ops.export_scene.gltf(**{key: value for key, value in desired.items() if key in props})
    print("CAST_BUILT=" + json.dumps({
        "character": character, "output": str(output), "bones": len(rig.data.bones),
        "actions": [action.name for action in selected],
        "vertices": sum(len(obj.data.vertices) for obj in bpy.context.scene.objects if obj.type == 'MESH'),
    }))


for character, config in CAST.items():
    export_character(character, config)
