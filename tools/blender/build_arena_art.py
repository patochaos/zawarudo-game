"""Render the six companion arenas. Run with Blender --background --python.

Original geometry/materials only; no downloads or add-ons. Pendulum is maintained
by build_pendulum_art.py. Each .blend opens on its complete background scene.
"""
from pathlib import Path
import math
import sys
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
THEMES = ["crosshair-court", "endless-descent", "pulse-chamber",
          "shattered-sanctum", "foundry", "collision-course"]
if "--" in sys.argv:
    requested = sys.argv[sys.argv.index("--") + 1:]
    if requested:
        if any(theme not in THEMES for theme in requested):
            raise ValueError("Unknown arena; pass one or more names after --")
        THEMES = requested
bpy.context.preferences.filepaths.save_version = 0


def mat(name, color, metal=0, emission=0):
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*color, 1)
    result.use_nodes = True
    node = result.node_tree.nodes.get("Principled BSDF")
    node.inputs["Base Color"].default_value = (*color, 1)
    node.inputs["Metallic"].default_value = metal
    node.inputs["Roughness"].default_value = 0.72
    node.inputs["Emission Color"].default_value = (*color, 1)
    node.inputs["Emission Strength"].default_value = emission
    return result


def finish(obj, name, material):
    obj.name = name
    obj.data.materials.append(material)
    return obj


def box(name, x, z, w, h, material, y=0, depth=0.30, angle=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, z))
    obj = bpy.context.object
    obj.dimensions = (w, depth, h)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.rotation_euler.y = angle
    mod = obj.modifiers.new("Cut edges", "BEVEL")
    mod.width, mod.segments = min(0.035, w / 5, h / 5), 1
    obj.modifiers.new("Face normals", "WEIGHTED_NORMAL")
    return finish(obj, name, material)


def ring(name, x, z, r, material, width=0.045, y=0):
    bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=width,
        major_segments=80, minor_segments=6, location=(x, y, z),
        rotation=(math.pi / 2, 0, 0))
    return finish(bpy.context.object, name, material)


def arch(x, z, radius, material, broken=False):
    for i in range(18):
        if broken and i in (6, 7, 13):
            continue
        a = (i + 0.5) * math.pi / 18 - math.pi / 2
        box("Arch voussoir", x + math.sin(a) * radius, z + math.cos(a) * radius,
            radius * 0.16, 0.25, material, angle=a)
    for side in (-1, 1):
        box("Arch pier", x + side * radius, z - 1.5, 0.26, 3, material)


def gear(x, z, radius, material):
    ring("Timing wheel", x, z, radius, material, 0.09)
    ring("Bearing", x, z, radius * 0.25, material, 0.07, -0.08)
    for i in range(24):
        a = i * math.tau / 24
        box("Gear tooth", x + math.sin(a) * radius, z + math.cos(a) * radius,
            0.13, 0.23, material, angle=a)
    for i in range(6):
        a = i * math.tau / 6
        box("Wheel spoke", x + math.sin(a) * radius * 0.55,
            z + math.cos(a) * radius * 0.55, 0.08, radius * 0.78, material, angle=a)


def light(name, loc, power, color, size):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.color, data.shape, data.size = power, color, "DISK", size
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (-obj.location).to_track_quat('-Z', 'Y').to_euler()


for theme in THEMES:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.world = bpy.data.worlds.new("Quiet ambient")
    scene.world.color = (0.10, 0.10, 0.10)
    output = ROOT / "assets/art/arenas" / theme
    output.mkdir(parents=True, exist_ok=True)
    cold = mat("Blue slate", (0.075, 0.105, 0.16))
    edge = mat("Dressed limestone", (0.19, 0.21, 0.27))
    ink = mat("Deep recess", (0.010, 0.016, 0.028))
    brass = mat("Old bronze", (0.34, 0.24, 0.11), 0.4)
    iron = mat("Cast iron", (0.10, 0.10, 0.13), 0.35)
    teal = mat("Oxidized copper", (0.075, 0.28, 0.29), 0.25)
    wine = mat("Wine velvet", (0.18, 0.035, 0.065))
    purple = mat("Violet enamel", (0.22, 0.12, 0.28), 0.20)
    ember = mat("Banked furnace", (0.52, 0.10, 0.024), emission=0.55)
    cyan = mat("Reactor glass", (0.045, 0.25, 0.30), emission=0.20)
    box("Rear chamber", 0, 0, 13.5, 8, ink, y=1.0)

    if theme == "crosshair-court":
        arch(0, 0.35, 2.20, edge)
        for x in (-4.50, 4.50):
            arch(x, 0.60, 0.95, cold)
            box("Recessed ceremonial door", x, -0.20, 1.5, 3.1, iron, y=0.25)
            for dx in (-0.50, 0, 0.50):
                box("Door inlay", x + dx, -0.2, 0.025, 2.8, brass, y=0.05)
        for x in (-2.95, 2.95):
            box("Hanging banner", x, 0.40, 0.66, 3.35, wine)
            box("Banner rail", x, 2.10, 0.85, 0.08, brass, y=-0.08)
            box("Banner emblem", x, 0.75, 0.22, 0.50, brass, y=-0.18, angle=0.40)
        for r in (0.55, 0.66):
            ring("Recessed dueling crest", 0, 0.85, r, brass, 0.035, 0.2)
        for angle in (-0.55, 0.55):
            box("Crossed ceremonial blade", 0, 0.85, 0.055, 1.95, edge, y=0.05, angle=angle)
        for z in (-2.90, -3.20):
            box("Distant podium", 0, z, 8.3, 0.12, cold)
        tile, trim = cold, brass

    elif theme == "endless-descent":
        # A deep industrial well, with dense engineering confined to the wings.
        # The central firing space is a quiet recess, never a fake platform.
        for material in (cold, iron, teal, brass):
            nodes = material.node_tree.nodes
            noise = nodes.new("ShaderNodeTexNoise")
            noise.inputs["Scale"].default_value = 38
            bump = nodes.new("ShaderNodeBump")
            bump.inputs["Strength"].default_value = 0.18
            bump.inputs["Distance"].default_value = 0.018
            material.node_tree.links.new(noise.outputs["Fac"], bump.inputs["Height"])
            material.node_tree.links.new(bump.outputs["Normal"], nodes.get("Principled BSDF").inputs["Normal"])
        # Receding frames create architectural depth without a scrolling camera.
        for tier in range(7):
            scale = 0.79 ** tier
            width, height = 8.15 * scale, 7.7 * scale
            z0 = -0.30
            shade = mat("Shaft depth %d" % tier,
                        tuple(v * (0.73 ** tier) for v in (0.10, 0.17, 0.22)), 0.25)
            for side in (-1, 1):
                box("Receding well upright", side * width / 2, z0, 0.10 * scale,
                    height, shade, y=0.68 - tier * 0.005)
                for end in (-1, 1):
                    box("Corner chamfer", side * (width / 2 - 0.18 * scale),
                        z0 + end * (height / 2 - 0.18 * scale), 0.08 * scale,
                        0.55 * scale, shade, y=0.65, angle=-side * end * 0.78)
            for end in (-1, 1):
                box("Deep cross rib", 0, z0 + end * height / 2,
                    width - 0.5 * scale, 0.055 * scale, shade, y=0.70)
        for side in (-1, 1):
            x = side * 4.83
            box("Armoured service spine", x, 0, 1.15, 8, iron, y=0.25, depth=0.7)
            for dx in (-0.48, 0.48):
                box("Machined copper rail", x + dx, 0, 0.085, 8, teal, y=-0.18)
                box("Rail inset highlight", x + dx - 0.02, 0, 0.018, 8, brass, y=-0.24)
            for storey in range(7):
                z = -3.0 + storey * 1.02
                box("Maintenance hatch frame", x, z, 0.92, 0.74, cold, y=-0.12)
                box("Maintenance hatch inset", x, z, 0.76, 0.57, ink, y=-0.30)
                for slat in range(5):
                    box("Vent louvre", x, z - 0.21 + slat * 0.10, 0.62, 0.035,
                        iron, y=-0.49, depth=0.06)
                for dx in (-0.38, 0.38):
                    for dz in (-0.27, 0.27):
                        box("Captive bronze bolt", x + dx, z + dz,
                            0.045, 0.045, brass, y=-0.34, depth=0.025)
                box("Service spine bracket", x, z - 0.42, 1.30, 0.10, edge, y=-0.24)
                box("Recessed indicator housing", x - side * 0.73, z,
                    0.15, 0.43, iron, y=0.10)
                box("Recessed cyan lamp", x - side * 0.73, z,
                    0.045, 0.27, cyan, y=-0.02)
                box("Outer diagonal brace", side * 5.82, z, 0.13, 1.16,
                    cold, y=0.12, angle=side * 0.40)
            # Hoist assemblies sit in the upper side structure, away from aim.
            for radius in (0.42, 0.33, 0.12):
                ring("Cable sheave", side * 3.8, 2.48, radius, brass, 0.045, 0.10)
            for spoke in range(8):
                a = spoke * math.tau / 8
                box("Sheave spoke", side * 3.8 + math.sin(a) * 0.23,
                    2.48 + math.cos(a) * 0.23, 0.045, 0.31, iron, y=0.10, angle=a)
            for dx in (-0.35, 0.35):
                box("Tension cable", side * 3.8 + dx, -0.5, 0.019, 5.8, edge, y=0.30)
            # Angled braces support the floor ends but don't imitate landing lips.
            for z in (-2.75, 0.75):
                box("Cantilever support", side * 3.72, z, 0.18, 1.15,
                    teal, y=0.25, angle=side * 0.70)
        # Far hanging cages make the scale read without adding combat objects.
        for side in (-1, 1):
            x, z = side * 2.85, -side * 0.75
            for dx in (-0.35, 0.35):
                box("Distant cage upright", x + dx, z, 0.035, 1.2, iron, y=0.75)
            for dz in (-0.6, 0.6):
                box("Distant cage lintel", x, z + dz, 0.75, 0.04, iron, y=0.75)
            for dx in (-0.2, 0, 0.2):
                box("Distant cage mesh", x + dx, z, 0.016, 1.18, cold, y=0.77)
        tile, trim = cold, teal

    elif theme == "pulse-chamber":
        for x, h in ((-3.7, 3.5), (0, 4.6), (3.7, 3.5)):
            box("Capacitor housing", x, -0.15, 1.8, h, iron)
            box("Inset reactor glass", x, -0.15, 1.14, h - 0.45, cyan, y=-0.18)
            for dz in (-h * 0.5, h * 0.5):
                box("Capacitor end cap", x, dz - 0.15, 2.05, 0.22, teal, y=-0.1)
            for dx in (-0.80, -0.56, 0.56, 0.80):
                box("Cooling fin", x + dx, -0.15, 0.06, h, cold, y=-0.24)
            for z in (-1.1, -0.55, 0, 0.55, 1.1):
                box("Glass retaining band", x, z, 1.6, 0.065, cold, y=-0.25)
        for x in (-5.30, 5.30):
            box("Coolant riser", x, 0, 0.20, 8, teal)
        for z in (-2.75, 2.65):
            box("Coolant manifold", 0, z, 10.6, 0.16, teal)
        tile, trim = cold, teal

    elif theme == "shattered-sanctum":
        arch(0.4, 0.1, 2.35, edge, True)
        arch(-4.40, 0.75, 0.85, cold, True)
        arch(4.60, 0.20, 0.90, cold, True)
        ring("Broken sanctuary oculus", 0.4, 1.25, 0.78, brass, 0.065, 0.35)
        for i in range(8):
            a = i * math.tau / 8
            box("Oculus spoke", 0.4 + math.sin(a) * 0.4, 1.25 + math.cos(a) * 0.4,
                0.035, 0.65, purple, y=0.25, angle=a)
        for x, height in ((-3.4, 3.8), (3.5, 2.5), (-5.7, 2.0), (5.8, 4.7)):
            box("Broken column", x, -3.1 + height / 2, 0.42, height, edge)
            box("Fractured capital", x + 0.05, -3.1 + height, 0.65, 0.20, brass, angle=0.12)
            for dx in (-0.12, 0.12):
                box("Column fluting", x + dx, -3.1 + height / 2, 0.035, height, cold, y=-0.17)
        for i in range(14):
            x = (-1 if i % 2 else 1) * (3.2 + (i % 4) * 0.6)
            box("Fallen masonry", x, -3.1 + (i % 3) * 0.17, 0.48, 0.22,
                cold, angle=(i % 5 - 2) * 0.20)
        tile, trim = edge, brass

    elif theme == "foundry":
        for x in (-3.1, 3.1):
            box("Furnace chimney", x, 1.80, 1.7, 4.2, iron)
            box("Furnace outer casting", x, -1.25, 3.2, 2.9, iron)
            box("Firebrick recess", x, -1.2, 2.65, 2.25, brass, y=-0.18)
            box("Banked fire chamber", x, -1.2, 2.25, 1.95, ember, y=-0.35)
            for offset in (-0.9, -0.45, 0, 0.45, 0.9):
                box("Furnace shutter slat", x + offset, -1.2, 0.23, 2.15, iron, y=-0.55)
            for z in (0.7, 1.8, 2.9):
                box("Chimney flange", x, z, 1.95, 0.12, cold, y=-0.08)
        for x in (-5.8, 5.8):
            box("Overhead crane upright", x, 0, 0.34, 8, cold)
        box("Overhead crane beam", 0, 2.9, 12.2, 0.25, cold)
        for x in (-0.16, 0.16):
            box("Crane chain", x, 1.9, 0.025, 1.8, brass)
        ring("Empty crane hook", 0.0, 0.9, 0.24, iron, 0.07)
        tile, trim = iron, brass

    else:
        for angle in (-0.72, 0.72):
            for offset in (-0.16, 0.16):
                box("Crossing conveyor rail", offset, -0.1, 0.10, 12,
                    cold, y=0.4, angle=angle)
            for step in range(-7, 8):
                distance = step * 0.55
                box("Rail junction sleeper", math.sin(angle) * distance,
                    math.cos(angle) * distance - 0.1, 0.54, 0.075,
                    iron, y=0.55, angle=angle)
        gear(-3.4, 1.2, 1.00, brass)
        gear(3.4, -1.2, 1.15, purple)
        gear(0, 0, 0.64, cold)
        for x in (-5.50, 5.50):
            box("Junction pillar", x, 0, 0.5, 8, iron)
            for z in (-2, 0, 2):
                box("Pillar bearing plate", x, z, 0.73, 0.40, purple, y=-0.18)
        tile, trim = iron, purple

    geometry = [o for o in scene.objects if o.type == 'MESH']
    bpy.ops.object.camera_add(location=(0, -20, 0))
    camera = bpy.context.object
    camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.type, camera.data.ortho_scale = "ORTHO", 12.8
    scene.camera = camera
    light("Cool window", (-3, -4, 6), 650, (0.65, 0.75, 1), 7)
    light("Warm bounce", (4, -3, -1), 150, (1, 0.65, 0.40), 6)
    scene.render.filepath = str(output / "backdrop.png")
    if theme == "endless-descent":
        scene.render.resolution_x, scene.render.resolution_y = 1920, 1080
        scene.cycles.samples = 48
    bpy.ops.render.render(write_still=True)
    for obj in geometry:
        obj.hide_render = True
    # Authored face rendered straight-on; runtime preserves its end caps.
    box("Platform slab", 0, 0, 2.56, 0.32, tile)
    box("Platform inset", 0, -0.015, 2.2, 0.17, ink, y=-0.17)
    for x in (-1.16, 1.16):
        box("Platform cap", x, 0, 0.10, 0.27, trim, y=-0.20)
    for x in (-0.8, -0.4, 0, 0.4, 0.8):
        box("Platform face panel", x, -0.015, 0.34, 0.10, tile, y=-0.20)
    camera.data.ortho_scale = 2.56
    scene.render.resolution_x, scene.render.resolution_y = 256, 32
    scene.render.filepath = str(output / "solid.png")
    bpy.ops.render.render(write_still=True)
    kit = bpy.data.collections.new("PLATFORM_KIT_enable_for_editing")
    scene.collection.children.link(kit)
    for obj in list(scene.objects):
        if obj.type == 'MESH' and obj not in geometry:
            for col in list(obj.users_collection):
                col.objects.unlink(obj)
            kit.objects.link(obj)
    kit.hide_render = True
    kit.hide_viewport = True
    for obj in geometry:
        obj.hide_render = False
    camera.data.ortho_scale = 12.8
    scene.render.resolution_x, scene.render.resolution_y = (1920, 1080) if theme == "endless-descent" else (1280, 720)
    scene.render.filepath = str(output / "backdrop.png")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "art_source/blender" / (theme + "-v1.blend")))
    print("ARENA COMPLETE:", theme, flush=True)
