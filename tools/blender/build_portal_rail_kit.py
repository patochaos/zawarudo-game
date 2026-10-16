"""Render the wrap portal frames, their looping interior and the mover rail kit.

Blender --background --python tools/blender/build_portal_rail_kit.py
No external textures, add-ons, or Python packages required. Units: 100 px/m.

Same kit materials, camera and lighting as build_platform_damage.py and
build_pendulum_art.py. The frames replace the drawn cyan dashes along a wrap
opening and the rails replace nothing on screen: the mover chevrons stay on the
platform face. Outputs under assets/art/arenas/pendulum/:

- portal-frame-v.png (24 x 96): the left-edge frame in columns 0..12 and the
  right-edge frame in 12..24. Rows 0..12 are the top cap, 12..84 a repeatable
  segment, 84..96 the bottom cap. The 8 px channel between the rails is open.
- portal-frame-h.png (96 x 24): the same frame for the ceiling (rows 0..12)
  and floor (rows 12..24) portal: left cap, 72 px segment, right cap.
- portal-loop-v.png (48 x 72): six 8 x 72 cells, one per loop frame, of
  energy bands sliding along the channel; the pattern repeats every 24 px, so
  frame 6 equals frame 0 and the cells tile along any run length.
- portal-loop-h.png (72 x 48): the six frames stacked for the horizontal portal.
- rail-v.png (16 x 96): a lift rail. Rows 0..16 the top stop, 16..80 a
  repeatable 8 px gunmetal rail with the violet enamel inlay and brass ties,
  80..96 the bottom stop.
- rail-h.png (96 x 16): the same rail for a platform that travels sideways.
"""
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets/art/arenas/pendulum"
OUTPUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version = 0
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 96
scene.cycles.use_denoising = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.film_transparent = True
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"
scene.world = bpy.data.worlds.new("Kit ambient")
scene.world.color = (0.12, 0.12, 0.12)


def material(name, color, metallic=0.0, roughness=0.7, emission=0.0, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1)
        bsdf.inputs["Emission Strength"].default_value = emission
    bsdf.inputs["Alpha"].default_value = alpha
    return mat


dark = material("Recessed ink", (0.009, 0.014, 0.029))
brass = material("Aged satin brass", (0.30, 0.21, 0.09), 0.45)
violet = material("Lift enamel", (0.31, 0.19, 0.49), 0.2)
gunmetal = material("Gunmetal channel", (0.10, 0.11, 0.15), 0.6, 0.5)
# The wrap seam's cyan, matching Arena's former glow colour.
# Emission 1.0 keeps the exact seam colour under the Standard view transform.
lumen = material("Portal lumen", (0.28, 0.95, 1.0), emission=1.0)
haze = material("Portal haze", (0.28, 0.95, 1.0), emission=0.6, alpha=0.2)
lamp = material("Portal lamp", (0.30, 0.96, 1.0), emission=1.2)

collections = {}
active = None


def collection(name):
    global active
    result = bpy.data.collections.new(name)
    scene.collection.children.link(result)
    collections[name] = result
    active = result
    return result


def box(name, loc, size, mat, bevel=0.006):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
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


class Strip:
    """Places boxes by (across, along) so one description renders in every
    orientation. `outer` is the side that meets the screen edge."""

    def __init__(self, origin, vertical, outer):
        self.origin, self.vertical, self.outer = Vector(origin), vertical, outer

    def put(self, name, across, along, width, length, depth, mat, y=0.0, bevel=0.006):
        across *= self.outer
        if self.vertical:
            loc = self.origin + Vector((across, y, along))
            size = (width, depth, length)
        else:
            loc = self.origin + Vector((along, y, across))
            size = (length, depth, width)
        return box(name, loc, size, mat, bevel)


def portal_frame(strip, prefix):
    """Two gunmetal rails with an open 8 px channel, brass caps and a lamp."""
    for across, label in ((-0.045, "outer"), (0.045, "inner")):
        strip.put(prefix + " %s rail" % label, across, 0, 0.03, 0.96, 0.06, gunmetal)
    strip.put(prefix + " inner brass fillet", 0.054, 0, 0.012, 0.72, 0.006, brass, -0.033, 0)
    for along in (-0.24, 0.0, 0.24):
        strip.put(prefix + " outer rivet", -0.045, along, 0.018, 0.018, 0.01, brass, -0.034, 0)
    for along in (-0.42, 0.42):
        strip.put(prefix + " cap", 0, along, 0.12, 0.12, 0.08, brass, 0.0, 0.01)
        strip.put(prefix + " cap socket", 0, along, 0.08, 0.03, 0.02, dark, -0.045, 0)
        strip.put(prefix + " cap lamp", 0, along, 0.03, 0.012, 0.012, lamp, -0.052, 0)


def portal_loop(strip, prefix, frame):
    """Three bands per 72 px cell, 24 px apart, shifted 4 px per frame."""
    for k in range(3):
        along = (-0.24 + k * 0.24 + frame * 0.04 + 0.36) % 0.72 - 0.36
        for copy in (along - 0.72, along, along + 0.72):
            strip.put(prefix + " band core", 0, copy, 0.08, 0.012, 0.012, lumen, -0.02, 0)
            strip.put(prefix + " band haze", 0, copy - 0.026, 0.08, 0.04, 0.008, haze, -0.015, 0)


def mover_rail(strip, prefix):
    """A gunmetal rail with the lift's violet inlay, brass ties and end stops."""
    strip.put(prefix + " rail", 0, 0, 0.08, 0.64, 0.06, gunmetal)
    strip.put(prefix + " violet inlay", 0, 0, 0.03, 0.64, 0.008, violet, -0.032, 0)
    for along in (-0.24, -0.08, 0.08, 0.24):
        strip.put(prefix + " brass tie", 0, along, 0.08, 0.012, 0.01, brass, -0.034, 0)
    for along in (-0.40, 0.40):
        inward = -1 if along > 0 else 1
        strip.put(prefix + " stop", 0, along, 0.16, 0.14, 0.10, gunmetal, 0.0, 0.01)
        strip.put(prefix + " stop buffer", 0, along + inward * 0.055, 0.12, 0.03, 0.03, brass, -0.055, 0)
        strip.put(prefix + " stop violet plate", 0, along - inward * 0.02, 0.08, 0.05, 0.008, violet, -0.058, 0)


# Camera front-on at the kit scale, moved per sheet; the lights follow it so every
# piece is lit exactly like the platform faces.
bpy.ops.object.camera_add(location=(0, -20, 0))
camera = bpy.context.object
camera.name = "Orthographic sprite camera"
camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.type = "ORTHO"
scene.camera = camera
lights = []


def light(name, loc, power, color, size):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.color, data.shape, data.size = power, color, "DISK", size
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat('-Z', 'Y').to_euler()
    lights.append((obj, Vector(loc)))
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

# Each sheet is laid out at its own world origin, 3 m apart.
SHEETS = {
    "portal-frame-v.png": (0.0, 24, 96),
    "portal-frame-h.png": (3.0, 96, 24),
    "portal-loop-v.png": (6.0, 48, 72),
    "portal-loop-h.png": (9.0, 72, 48),
    "rail-v.png": (12.0, 16, 96),
    "rail-h.png": (15.0, 96, 16),
}

collection("PORTAL_FRAME_vertical")
portal_frame(Strip((-0.06, 0, 0), True, -1), "Left frame")
portal_frame(Strip((0.06, 0, 0), True, 1), "Right frame")
collection("PORTAL_FRAME_horizontal")
portal_frame(Strip((3.0, 0, 0.06), False, 1), "Top frame")
portal_frame(Strip((3.0, 0, -0.06), False, -1), "Bottom frame")
collection("PORTAL_LOOP_vertical")
for frame in range(6):
    portal_loop(Strip((6.0 - 0.20 + frame * 0.08, 0, 0), True, 1), "Loop v%d" % frame, frame)
collection("PORTAL_LOOP_horizontal")
for frame in range(6):
    portal_loop(Strip((9.0, 0, 0.20 - frame * 0.08), False, 1), "Loop h%d" % frame, frame)
collection("RAIL_vertical")
mover_rail(Strip((12.0, 0, 0), True, 1), "Lift rail")
collection("RAIL_horizontal")
mover_rail(Strip((15.0, 0, 0), False, 1), "Sideways rail")

for name, col in zip(SHEETS, collections.values()):
    cx, width, height = SHEETS[name]
    for other_name, other in collections.items():
        other.hide_render = other is not col
    camera.location = (cx, -20, 0)
    camera.data.ortho_scale = max(width, height) / 100.0
    for obj, base in lights:
        obj.location = base + Vector((cx, 0, 0))
    scene.render.resolution_x, scene.render.resolution_y = width, height
    scene.render.filepath = str(OUTPUT / name)
    bpy.ops.render.render(write_still=True)
    print("RENDERED", name, flush=True)

for col in collections.values():
    col.hide_render = False
camera.location = (0, -20, 0)
for obj, base in lights:
    obj.location = base
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "art_source/blender/portal-rail-kit-v1.blend"))
print("Portal frames, loop and mover rails complete.", flush=True)
