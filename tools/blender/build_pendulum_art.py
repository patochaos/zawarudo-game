"""Author and render the Pendulum observatory and modular platform kit.

Blender --background --python tools/blender/build_pendulum_art.py
No external textures, add-ons, or Python packages required. Units: 100 px/m.
"""
from pathlib import Path
import math
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/art/arenas/pendulum"
OUTPUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 24
scene.cycles.use_denoising = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.film_transparent = True
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"
scene.world.color = (0.12, 0.12, 0.12)


def material(name, color, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = 0.7
    return mat


stone = material("Midnight blue limestone", (0.065, 0.080, 0.13))
dark = material("Recessed ink", (0.009, 0.014, 0.029))
brass = material("Aged satin brass", (0.30, 0.21, 0.09), 0.45)
edge = material("Cut stone edge", (0.15, 0.19, 0.27))
violet = material("Lift enamel", (0.31, 0.19, 0.49), 0.2)
ceramic = material("Breakable amber ceramic", (0.40, 0.19, 0.07))


def collection(name):
    result = bpy.data.collections.new(name)
    scene.collection.children.link(result)
    return result


architecture = collection("OBSERVATORY_background_only")
kit = collection("PLATFORM_KIT_exact_collision_faces")
machinery = {}
active = architecture


def finish(obj, name, mat):
    obj.name = name
    for col in list(obj.users_collection):
        col.objects.unlink(obj)
    active.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def box(name, loc, size, mat, bevel=0.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new("Broad cut bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 1
        obj.modifiers.new("Weighted face normals", "WEIGHTED_NORMAL")
    return finish(obj, name, mat)


def ring(name, x, z, radius, thickness, mat, y=0):
    bpy.ops.mesh.primitive_torus_add(major_radius=radius,
        minor_radius=thickness, major_segments=96, minor_segments=6,
        location=(x, y, z), rotation=(math.pi / 2, 0, 0))
    return finish(bpy.context.object, name, mat)


def spoke(name, x, z, radius, angle, length, width, mat, y=-0.08):
    obj = box(name, (x + math.sin(angle) * radius, y,
        z + math.cos(angle) * radius), (width, 0.10, length), mat, 0.008)
    obj.rotation_euler.y = angle
    return obj


def gear(name, x, z, radius):
    ring(name + " rim", x, z, radius, 0.07, brass, 0.16)
    ring(name + " hub", x, z, radius * 0.23, 0.08, stone, 0.12)
    for i in range(20):
        spoke(name + " tooth", x, z, radius, i * math.tau / 20,
              0.21, 0.12, brass, 0.16)
    for i in range(6):
        spoke(name + " spoke", x, z, radius * 0.55, i * math.tau / 6,
              radius * 0.75, 0.07, stone, 0.10)


# Deep rear wall, side buttresses and an enormous inset astronomical dial.
box("Recessed chamber", (0, 0.80, 0), (13.4, 0.20, 8), dark)
for x in (-5.70, -4.50, 4.50, 5.70):
    box("Stone buttress", (x, 0.28, -0.1), (0.42, 0.48, 7.4), stone)
    box("Brass vertical inlay", (x - 0.10, 0.01, -0.1), (0.026, 0.035, 7.4), brass, 0)
    for z in (-2.7, -1.1, 0.5, 2.1):
        box("Pillar collar", (x, -0.01, z), (0.55, 0.16, 0.13), edge)

for radius, thickness, mat in ((2.70, 0.13, stone), (2.51, 0.026, brass),
        (2.31, 0.065, brass), (2.19, 0.025, stone), (1.78, 0.020, brass)):
    ring("Astronomical dial", 0, 0.20, radius, thickness, mat)
for i in range(60):
    spoke("Hour division" if i % 5 == 0 else "Minute division", 0, 0.20,
        2.40, i * math.tau / 60, 0.14 if i % 5 == 0 else 0.055,
        0.035 if i % 5 == 0 else 0.016, brass)
for i in range(12):
    spoke("Radial support", 0, 0.20, 2.03, i * math.tau / 12,
        0.34, 0.035, stone, 0.08)
for name, x, z, radius in [("gear-left", -3.40, 1.75, 0.68),
                           ("gear-right", 3.37, -1.65, 0.78)]:
    active = collection("MACHINERY_" + name)
    machinery[name] = (active, x, z, 192, 192)
    gear(name, x, z, radius)
active = architecture

# An armillary inside the dial, instead of an opaque face behind combat.
for angle in (-0.60, 0.60):
    obj = ring("Armillary orbit", 0, 0.20, 1.32, 0.025, brass, 0.05)
    obj.scale.x = 0.44
    obj.rotation_euler.y = angle
ring("Central bearing", 0, 0.20, 0.18, 0.045, brass, -0.10)
for name, radius, angle, length, width, depth in [
        ("hand-long", 0.76, -0.42, 1.5, 0.055, -0.16),
        ("hand-short", 0.44, 1.06, 0.90, 0.085, -0.20)]:
    active = collection("MACHINERY_" + name)
    machinery[name] = (active, 0, 0.20, 336, 336)
    spoke(name, 0, 0.20, radius, angle, length, width, brass, depth)

for name, x, bottom in (("weight-left", -3.22, -2.3), ("weight-right", 3.24, -0.6)):
    active = collection("MACHINERY_" + name)
    machinery[name] = (active, x, bottom, 96, 112)
    # Chains are drawn to the moving attachment in Godot, never baked twice.
    box("Hanging counterweight", (x, 0, bottom), (0.48, 0.30, 0.73), stone)
    box("Weight brass insert", (x, -0.17, bottom), (0.30, 0.04, 0.46), brass)
    for dz in (-0.30, 0.30):
        box("Weight collar", (x, -0.03, bottom + dz), (0.55, 0.34, 0.07), edge)

# Camera front-on: all gameplay faces stay perfectly horizontal in the render.
bpy.ops.object.camera_add(location=(0, -20, 0))
camera = bpy.context.object
camera.name = "Orthographic sprite camera"
camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 12.8
scene.camera = camera


def light(name, loc, power, color, size):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.color, data.shape, data.size = power, color, "DISK", size
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    return obj


key = light("Cool high window", (-3, -4, 6), 650, (0.65, 0.73, 1.0), 7)
fill = light("Warm reflected brass", (4, -3, -1), 170, (1.0, 0.65, 0.33), 6)


def render(name, width, height):
    scene.render.resolution_x, scene.render.resolution_y = width, height
    scene.render.filepath = str(OUTPUT / name)
    bpy.ops.render.render(write_still=True)


for layer, *_ in machinery.values():
    layer.hide_render = True
render("observatory.png", 1280, 720)
architecture.hide_render = True
for name, (layer, x, z, width, height) in machinery.items():
    layer.hide_render = False
    camera.location = (x, -20, z)
    camera.data.ortho_scale = max(width, height) / 100.0
    render(name + ".png", width, height)
    layer.hide_render = True
camera.location = (0, -20, 0)
active = kit
camera.data.ortho_scale = 2.56
key.data.energy = 400
fill.data.energy = 80

for kind, mat in (("solid", stone), ("moving", violet), ("breakable", ceramic)):
    created = []
    created.append(box(kind + " beveled slab", (0, 0, 0), (2.56, 0.30, 0.32), mat, 0.022))
    created.append(box(kind + " inset front", (0, -0.16, -0.01), (2.20, 0.025, 0.18), dark, 0.01))
    for x in (-1.16, 1.16):
        created.append(box(kind + " end cap", (x, -0.185, 0), (0.11, 0.05, 0.27), brass, 0.008))
    for x in (-0.8, -0.4, 0, 0.4, 0.8):
        created.append(box(kind + " face segment", (x, -0.19, -0.015),
            (0.35, 0.015, 0.11), mat, 0.008))
    render(kind + ".png", 256, 32)
    for obj in created:
        obj.hide_render = True

# Leave the source opening on the complete architectural scene.
architecture.hide_render = False
for layer, *_ in machinery.values():
    layer.hide_render = False
kit.hide_render = True
camera.data.ortho_scale = 12.8
key.data.energy, fill.data.energy = 650, 170
scene.render.resolution_x, scene.render.resolution_y = 1280, 720
scene.render.filepath = str(OUTPUT / "observatory.png")
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "art_source/blender/pendulum-observatory-v1.blend"))
print("Pendulum source, architecture, six machinery layers and platform renders complete.")
