"""Render the damaged breakable platform faces and their debris shards.

Blender --background --python tools/blender/build_platform_damage.py
No external textures, add-ons, or Python packages required. Units: 100 px/m.

The intact breakable face stays `assets/art/arenas/pendulum/breakable.png`, built
by build_pendulum_art.py. That script also regenerates the retired observatory
scenery, so the damage states live here with the same kit materials, camera and
lighting. Outputs, in the same folder:

- breakable-cracked.png: first hit, two cracks and a chipped top edge.
- breakable-broken.png: last hit, four cracks, dropped face segments, chips at
  both ends.
- debris.png: four 32 x 32 ceramic and brass shards for the shatter burst.
"""
from pathlib import Path
import math
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/art/arenas/pendulum"
OUTPUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.film_transparent = True
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"
scene.world = bpy.data.worlds.new("Kit ambient")
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


dark = material("Recessed ink", (0.009, 0.014, 0.029))
brass = material("Aged satin brass", (0.30, 0.21, 0.09), 0.45)
ceramic = material("Breakable amber ceramic", (0.40, 0.19, 0.07))
scorched = material("Scorched ceramic", (0.22, 0.09, 0.04))

collections = {}


def collection(name):
    result = bpy.data.collections.new(name)
    scene.collection.children.link(result)
    collections[name] = result
    return result


active = None


def box(name, loc, size, mat, bevel=0.025, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.rotation_euler = rotation
    if bevel > 0:
        mod = obj.modifiers.new("Cut edges", "BEVEL")
        mod.width, mod.segments = min(bevel, min(size) / 3), 1
    obj.modifiers.new("Face normals", "WEIGHTED_NORMAL")
    obj.name = name
    for col in list(obj.users_collection):
        col.objects.unlink(obj)
    active.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


def slab(prefix, dropped=(), tilted=(), missing_caps=()):
    """The authored breakable face from build_pendulum_art.py, with face
    segments optionally dropped or tilted by damage."""
    box(prefix + " beveled slab", (0, 0, 0), (2.56, 0.30, 0.32), ceramic, 0.022)
    box(prefix + " inset front", (0, -0.16, -0.01), (2.20, 0.025, 0.18), dark, 0.01)
    for x in (-1.16, 1.16):
        if x in missing_caps:
            box(prefix + " sheared cap", (x, -0.185, -0.08), (0.11, 0.05, 0.11), brass, 0.008,
                (0, 0.35, 0))
        else:
            box(prefix + " end cap", (x, -0.185, 0), (0.11, 0.05, 0.27), brass, 0.008)
    for index, x in enumerate((-0.8, -0.4, 0, 0.4, 0.8)):
        z, angle, mat = -0.015, 0.0, ceramic
        if index in dropped:
            z, angle, mat = -0.045, 0.0, scorched
        elif index in tilted:
            angle = 0.18 if index % 2 else -0.14
        box(prefix + " face segment", (x, -0.19, z), (0.35, 0.015, 0.11), mat, 0.008,
            (0, angle, 0))


def crack(prefix, x, angle, length=0.30, width=0.018):
    """A thin ink wedge in front of the face, read as a fracture line."""
    box(prefix + " crack", (x, -0.205, 0.0), (width, 0.02, length), dark, 0, (0, angle, 0))
    box(prefix + " crack branch", (x + 0.06 * math.copysign(1, angle), -0.205, -0.09),
        (width * 0.7, 0.02, length * 0.45), dark, 0, (0, -angle * 1.6, 0))


def chip(prefix, x, z=0.15, size=0.12, angle=0.6):
    """A notch out of the slab's edge: ink geometry breaking the silhouette."""
    box(prefix + " chip", (x, -0.10, z), (size, 0.45, size * 0.55), dark, 0, (0, angle, 0))


# Camera front-on at the kit scale: 2.56 m -> 256 px.
bpy.ops.object.camera_add(location=(0, -20, 0))
camera = bpy.context.object
camera.name = "Orthographic sprite camera"
camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 2.56
scene.camera = camera


def light(name, loc, power, color, size):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.color, data.shape, data.size = power, color, "DISK", size
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    return obj


light("Cool high window", (-3, -4, 6), 400, (0.65, 0.73, 1.0), 7)
light("Warm reflected brass", (4, -3, -1), 80, (1.0, 0.65, 0.33), 6)
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    scene.cycles.device = "GPU"
except Exception as error:  # pragma: no cover - depends on the host
    print("GPU unavailable, rendering on CPU:", error, flush=True)

active = collection("CRACKED_first_hit")
slab("Cracked", tilted=(1,))
crack("Cracked", -0.62, 0.42)
crack("Cracked", 0.55, -0.36)
chip("Cracked", -0.95)

active = collection("BROKEN_last_hit")
slab("Broken", dropped=(1, 3), tilted=(0, 4), missing_caps=(1.16,))
crack("Broken", -0.85, 0.48)
crack("Broken", -0.22, -0.40)
crack("Broken", 0.30, 0.34)
crack("Broken", 0.92, -0.52)
chip("Broken", -1.02, size=0.15)
chip("Broken", 0.18, size=0.11, angle=-0.5)
chip("Broken", 0.86, z=-0.15, size=0.13, angle=0.4)

active = collection("DEBRIS_shards")
# Four shards across a 1.28 m strip, one 32 px cell each.
box("Shard corner", (-0.48, 0, 0.0), (0.20, 0.14, 0.13), ceramic, 0.03, (0.3, 0.6, 0.2))
box("Shard corner brass", (-0.44, -0.08, 0.05), (0.07, 0.03, 0.05), brass, 0.008, (0.3, 0.6, 0.2))
box("Shard splinter", (-0.16, 0, 0.0), (0.24, 0.08, 0.07), ceramic, 0.02, (0.1, -0.5, 0.9))
box("Shard slab", (0.16, 0, 0.0), (0.18, 0.12, 0.16), scorched, 0.03, (0.5, 0.2, -0.4))
box("Shard slab face", (0.15, -0.07, 0.0), (0.12, 0.015, 0.09), ceramic, 0.008, (0.5, 0.2, -0.4))
box("Shard chip", (0.48, 0, 0.0), (0.12, 0.10, 0.09), ceramic, 0.02, (-0.4, 0.3, 0.7))


def render(name, width, height, shown):
    for col_name, col in collections.items():
        col.hide_render = col_name != shown
    scene.render.resolution_x, scene.render.resolution_y = width, height
    scene.render.filepath = str(OUTPUT / name)
    bpy.ops.render.render(write_still=True)
    print("RENDERED", name, flush=True)


render("breakable-cracked.png", 256, 32, "CRACKED_first_hit")
render("breakable-broken.png", 256, 32, "BROKEN_last_hit")
camera.data.ortho_scale = 1.28
render("debris.png", 128, 32, "DEBRIS_shards")
camera.data.ortho_scale = 2.56
for col in collections.values():
    col.hide_render = False
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "art_source/blender/platform-damage-v1.blend"))
print("Platform damage faces and debris complete.", flush=True)
