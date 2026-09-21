"""Render original combat ornament and impact sprites; no external dependencies.

Blender --background --python tools/blender/build_combat_art.py
"""
from pathlib import Path
import math
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/art/combat"
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 16
scene.cycles.use_denoising = True
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"
scene.world.color = (0.22, 0.22, 0.22)


def metal(name, color, metallic):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = 0.28
    return mat


silver = metal("Neutral silver — runtime player tint", (0.72, 0.76, 0.8), 0.55)
edge = metal("Pale cut edge", (0.94, 0.94, 0.94), 0.3)
bpy.ops.object.camera_add(location=(0, 0, 12))
scene.camera = bpy.context.object
scene.camera.data.type = "ORTHO"
scene.camera.data.ortho_scale = 7
for loc, energy, size in [((-3, 4, 6), 900, 5), ((4, -1, 4), 650, 3)]:
    bpy.ops.object.light_add(type="AREA", location=loc)
    light = bpy.context.object
    light.data.energy = energy
    light.data.shape = "DISK"
    light.data.size = size
    light.rotation_euler = (Vector((0, 0, 0)) - light.location).to_track_quat("-Z", "Y").to_euler()


def shard(name, radius, angle, length, width):
    # A raised central ridge gives each spear-shaped chip two distinct facets.
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([(0, -width, 0), (length, 0, 0), (0, width, 0),
                     (-length * 0.15, 0, 0), (length * 0.22, 0, width * 0.65)],
                    [], [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)])
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    obj.location = (radius * math.cos(angle), radius * math.sin(angle), 0)
    obj.rotation_euler.z = angle
    obj.data.materials.append(silver)
    obj.data.materials.append(edge)
    for face in obj.data.polygons:
        face.material_index = face.index % 2
    return obj


crest = []
for radius, thickness in [(2.45, 0.035), (2.22, 0.018), (1.46, 0.045)]:
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=thickness,
                                   major_segments=96, minor_segments=6)
    ring = bpy.context.object
    ring.name = "Engraved temporal dial"
    ring.data.materials.append(silver)
    crest.append(ring)
for i in range(60):
    angle = i * math.tau / 60
    crest.append(shard("Dial index %02d" % i, 2.55, angle,
                       0.22 if i % 5 == 0 else 0.08, 0.022))
for i in range(5):
    crest.append(shard("Volley blade %d" % (i + 1), 0.30,
                       math.pi / 2 + (i - 2) * 0.31, 1.62, 0.13))


def render(name, pixels, span):
    scene.render.resolution_x = scene.render.resolution_y = pixels
    scene.camera.data.ortho_scale = span
    scene.render.filepath = str(OUT / name)
    bpy.ops.render.render(write_still=True)


render("super-dial.png", 640, 6.2)
for obj in crest:
    obj.hide_render = True
    obj.hide_set(True)
chips = []
for frame in range(4):
    for obj in chips:
        bpy.data.objects.remove(obj, do_unlink=True)
    chips = []
    for i in range(8):
        angle = i * math.tau / 8 + 0.14 * math.sin(i * 3)
        radius = 0.12 + frame * (0.28 + (i % 3) * 0.09)
        length = (0.75 - frame * 0.13) * (1.0 if i % 2 == 0 else 0.55)
        chips.append(shard("Impact facet %d" % i, radius, angle, length,
                           0.075 - frame * 0.012))
    render("impact-%d.png" % frame, 128, 4.4)
for obj in chips:
    obj.hide_render = True
    obj.hide_set(True)
for obj in crest:
    obj.hide_render = False
    obj.hide_set(False)
scene.camera.data.ortho_scale = 6.2
scene.render.resolution_x = scene.render.resolution_y = 640
scene.render.filepath = str(OUT / "super-dial.png")
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "art_source/blender/combat-art-v1.blend"))
