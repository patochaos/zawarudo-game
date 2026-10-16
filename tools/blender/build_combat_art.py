"""Render original combat ornament, impact and knife sprites; no external dependencies.

Blender --background --python tools/blender/build_combat_art.py [-- --only a,b,c]

Outputs under assets/art/combat/:
  super-dial.png        24-frame rotation sheet of the temporal dial (6x4, 384 px cells)
  super-accents.png     five accent impact frames for the SUPER cut-in (5x1, 64 px cells)
  impact-stone.png, impact-metal.png, impact-glass.png
                        the four shard poses per surface (4x1, 128 px cells)
  time-stop-shatter.png eight glass-crack frames for the freeze (4x2, 640 px cells)
  knife.png, knife-tint.png, knife-glow.png, knife-streak.png
                        the thrown knife set described at the bottom of this file

`--only` after Blender's `--` limits the run to some of: dial, accents, impacts,
shatter, knife. Cycles noise differs run to run, so re-render only what should
change. Atlases are composited here with Blender's bundled numpy.
"""
from pathlib import Path
import math
import random
import sys
import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/art/combat"
OUT.mkdir(parents=True, exist_ok=True)
TARGETS = {"dial", "accents", "impacts", "shatter", "knife"}
_argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if "--only" in _argv:
    TARGETS = set(_argv[_argv.index("--only") + 1].split(","))
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


def surface_material(name, color, metallic, roughness, alpha=1.0, emission=0.0):
    mat = metal(name, color, metallic)
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = roughness
    if alpha < 1.0:
        shader.inputs["Alpha"].default_value = alpha
        mat.blend_method = "BLEND"
    if emission > 0.0:
        shader.inputs["Emission Color"].default_value = (*color, 1)
        shader.inputs["Emission Strength"].default_value = emission
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


def shard(name, radius, angle, length, width, mats=None, centre=None):
    # A raised central ridge gives each spear-shaped chip two distinct facets.
    # `centre` places the chip's midpoint instead of its base at the polar point.
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([(0, -width, 0), (length, 0, 0), (0, width, 0),
                     (-length * 0.15, 0, 0), (length * 0.22, 0, width * 0.65)],
                    [], [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)])
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    if centre is None:
        obj.location = (radius * math.cos(angle), radius * math.sin(angle), 0)
    else:
        mid = Vector((math.cos(angle), math.sin(angle))) * (length * 0.425)
        obj.location = (centre[0] - mid.x, centre[1] - mid.y, 0)
    obj.rotation_euler.z = angle
    face_mats = mats or (silver, edge)
    obj.data.materials.append(face_mats[0])
    obj.data.materials.append(face_mats[1])
    for face in obj.data.polygons:
        face.material_index = face.index % 2
    return obj


def remove_all(objs):
    for obj in objs:
        bpy.data.objects.remove(obj, do_unlink=True)
    objs.clear()


def set_visible(objs, visible):
    for obj in objs:
        obj.hide_render = not visible
        obj.hide_set(not visible)


def capture(name, pixels_x, pixels_y, span, index=0):
    """Renders the scene as it stands and returns the frame as an RGBA float array."""
    scene.render.resolution_x = pixels_x
    scene.render.resolution_y = pixels_y
    scene.camera.data.ortho_scale = span
    path = OUT / (".%s-%02d.png" % (name, index))
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    image = bpy.data.images.load(str(path))
    buf = np.empty(pixels_x * pixels_y * 4, dtype=np.float32)
    image.pixels.foreach_get(buf)
    bpy.data.images.remove(image)
    path.unlink()
    return buf.reshape(pixels_y, pixels_x, 4)


def render_cells(name, pixels_x, pixels_y, span, parts, angles):
    """Renders `parts` once per angle and returns the cells as RGBA float arrays."""
    cells = []
    for i, angle in enumerate(angles):
        for obj in parts:
            obj.rotation_euler.z = -angle          # Godot angles grow clockwise
        cells.append(capture(name, pixels_x, pixels_y, span, i))
    return cells


def render_silhouettes(name, pixels_x, pixels_y, span, parts, angles):
    """Same cells as render_cells with every material replaced by flat white."""
    override = bpy.data.materials.new("Knife glow silhouette (flat white)")
    override.use_nodes = True
    nodes = override.node_tree.nodes
    nodes.clear()
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    output = nodes.new("ShaderNodeOutputMaterial")
    override.node_tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    view_layer = scene.view_layers[0]
    view_layer.material_override = override
    try:
        return render_cells(name, pixels_x, pixels_y, span, parts, angles)
    finally:
        view_layer.material_override = None


def save_atlas(name, cells, columns):
    rows = math.ceil(len(cells) / columns)
    cell_h, cell_w = cells[0].shape[:2]
    atlas = np.zeros((rows * cell_h, columns * cell_w, 4), dtype=np.float32)
    for i, cell in enumerate(cells):
        col, row = i % columns, i // columns
        # Blender stores rows bottom-up; row 0 of the atlas is the top strip.
        y0 = (rows - 1 - row) * cell_h
        atlas[y0:y0 + cell_h, col * cell_w:(col + 1) * cell_w] = cell
    # The denoiser leaves faint colour noise under fully transparent pixels,
    # which PNG cannot compress; clearing it shrinks the sheets several times.
    atlas[..., :3] *= atlas[..., 3:] > 0.0
    image = bpy.data.images.new(name, atlas.shape[1], atlas.shape[0], alpha=True)
    image.pixels.foreach_set(atlas.ravel())
    image.file_format = "PNG"
    image.filepath_raw = str(OUT / name)
    image.save()
    bpy.data.images.remove(image)


# ------------------------------------------------------------------ dial ----
# The engraved temporal dial: three rings, sixty index chips and five volley
# blades. The cut-in used to turn the single render in Godot; it now picks one
# of DIAL_FRAMES renders, DIAL_STEP radians apart, so the facets catch the fixed
# scene lights differently as the dial drifts. Frame 12 is upright: that is the
# frame reduced flashes holds, and the small symmetric range covers the sweep
# of either player's cut-in (-0.12..+0.06 rad for P1, mirrored for P2).
DIAL_FRAMES = 24
DIAL_STEP = 0.011
DIAL_CELL = 384
DIAL_SPAN = 6.2
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
bpy.ops.object.empty_add(location=(0, 0, 0))
dial_pivot = bpy.context.object
dial_pivot.name = "Dial pivot"
for obj in crest:
    obj.parent = dial_pivot

if "dial" in TARGETS:
    scene.cycles.samples = 40         # cleaner rings compress far better
    cells = []
    for i in range(DIAL_FRAMES):
        dial_pivot.rotation_euler.z = -(i - 12) * DIAL_STEP      # Godot angles grow clockwise
        cells.append(capture("super-dial", DIAL_CELL, DIAL_CELL, DIAL_SPAN, i))
    save_atlas("super-dial.png", cells, 6)
    dial_pivot.rotation_euler.z = 0.0
    scene.cycles.samples = 16
set_visible(crest, False)


# --------------------------------------------------------------- accents ----
# The five accents under the SUPER title were drawn strokes; each is now its own
# rendered blade chip pointing up-right like the old stroke, with one more
# splinter flung off the tip per wave, so the fifth accent is the hardest hit.
ACCENT_FRAMES = 5
ACCENT_CELL = 64
ACCENT_SPAN = 3.0
ACCENT_ANGLE = 0.563            # atan2(12, 19): the former stroke's direction
if "accents" in TARGETS:
    cells = []
    parts = []
    for k in range(ACCENT_FRAMES):
        remove_all(parts)
        parts.append(shard("Accent blade %d" % k, 0.0, ACCENT_ANGLE, 1.25 + 0.07 * k, 0.12,
                           centre=(0.0, 0.0)))
        tip = Vector((math.cos(ACCENT_ANGLE), math.sin(ACCENT_ANGLE))) * (0.55 + 0.035 * k)
        for j in range(k):
            side = -1.0 if j % 2 == 0 else 1.0
            spread = ACCENT_ANGLE + side * (0.55 + 0.22 * j)
            at = tip + Vector((math.cos(spread), math.sin(spread))) * (0.42 + 0.12 * j)
            parts.append(shard("Accent splinter %d.%d" % (k, j), 0.0, spread,
                               0.30 - 0.03 * j, 0.035, centre=(at.x, at.y)))
        cells.append(capture("super-accents", ACCENT_CELL, ACCENT_CELL, ACCENT_SPAN, k))
    remove_all(parts)
    save_atlas("super-accents.png", cells, ACCENT_FRAMES)


# --------------------------------------------------------------- impacts ----
# The four shared shard poses, once per surface. Stone chips are short, wide and
# matte with a few dust motes; metal keeps the original silver spears; glass is
# long translucent slivers with a bright lit edge. Effects tints every set with
# the hit colour, so the materials stay light.
stone = surface_material("Stone chip", (0.56, 0.51, 0.45), 0.0, 0.88)
stone_edge = surface_material("Stone fracture face", (0.74, 0.70, 0.63), 0.0, 0.70)
glass = surface_material("Glass sliver", (0.80, 0.91, 0.98), 0.10, 0.06, alpha=0.58)
glass_edge = surface_material("Glass lit edge", (0.97, 0.99, 1.0), 0.05, 0.05, emission=0.35)
SURFACES = {
    "stone": {"mats": (stone, stone_edge), "width": 1.7, "length": 0.72, "dust": True},
    "metal": {"mats": (silver, edge), "width": 1.0, "length": 1.0, "dust": False},
    "glass": {"mats": (glass, glass_edge), "width": 0.62, "length": 1.18, "dust": False},
}
if "impacts" in TARGETS:
    scene.cycles.samples = 48         # translucent glass needs the extra samples
    for surface, spec in SURFACES.items():
        cells = []
        chips = []
        for frame in range(4):
            remove_all(chips)
            for i in range(8):
                angle = i * math.tau / 8 + 0.14 * math.sin(i * 3)
                radius = 0.12 + frame * (0.28 + (i % 3) * 0.09)
                length = (0.75 - frame * 0.13) * (1.0 if i % 2 == 0 else 0.55) * spec["length"]
                chips.append(shard("Impact facet %s %d" % (surface, i), radius, angle, length,
                                   (0.075 - frame * 0.012) * spec["width"], spec["mats"]))
            if spec["dust"]:
                for j in range(5):
                    angle = j * math.tau / 5 + 0.9 + 0.3 * math.sin(j * 7)
                    radius = 0.30 + frame * (0.42 + (j % 2) * 0.10)
                    bpy.ops.mesh.primitive_ico_sphere_add(
                        subdivisions=1, radius=0.055 - frame * 0.009,
                        location=(radius * math.cos(angle), radius * math.sin(angle), 0.0))
                    mote = bpy.context.object
                    mote.name = "Stone dust %d" % j
                    mote.data.materials.append(stone)
                    chips.append(mote)
            cells.append(capture("impact-" + surface, 128, 128, 4.4, frame))
        remove_all(chips)
        save_atlas("impact-%s.png" % surface, cells, 4)
    scene.cycles.samples = 16


# --------------------------------------------------------------- shatter ----
# The time-stop crack: a seeded fracture tree spreading from the clock centre.
# Frame f shows the tree at time (f + 1) / SHATTER_FRAMES. Seven main rays grow
# through the first five frames, branches follow, and only the last two frames
# bring the ring fractures and the flakes at the point of impact, so the
# density lands on the decisive beat rather than building up through the whole
# sequence. TimeStopLayer draws the cell 1150 px wide over the arena (about
# 1.8x the render), so the main rays are 3 px thick at the centre and taper to
# under a pixel: a crack over the frozen world, not a wall in front of it.
SHATTER_FRAMES = 8
SHATTER_CELL = 640
SHATTER_SPAN = 10.0
SHATTER_RADIUS = 4.5
crack_face = surface_material("Glass crack facet", (0.84, 0.92, 1.0), 0.2, 0.15, emission=0.35)
crack_edge = surface_material("Glass crack edge", (1.0, 1.0, 1.0), 0.1, 0.10, emission=0.7)


def sliver(name, p0, p1, w0, w1, height, z):
    """A tapering crack segment from p0 to p1 with a raised ridge: two facets."""
    d = p1 - p0
    if d.length < 1e-4:
        return None
    n = Vector((-d.y, d.x)) / d.length
    verts = [(*(p0 + n * w0), z), (*(p0 - n * w0), z), (*p0, z + height),
             (*(p1 + n * w1), z), (*(p1 - n * w1), z), (*p1, z + height)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], [(0, 3, 5, 2), (2, 5, 4, 1)])
    mesh.validate()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    obj.data.materials.append(crack_face)
    obj.data.materials.append(crack_edge)
    obj.data.polygons[1].material_index = 1
    return obj


def crack_tree(seed):
    """Returns (segments, flakes): segments are (p0, p1, w0, w1, birth), flakes
    (centre, angle, length, width, birth). Births are in 0..1."""
    rng = random.Random(seed)
    segments = []

    def grow(p, angle, length, width, birth, depth):
        steps = 5 if depth == 0 else 3
        span = length / steps
        for k in range(steps):
            angle += rng.uniform(-0.30, 0.30)
            q = p + Vector((math.cos(angle), math.sin(angle))) * span
            w_end = width * (1.0 - 0.72 * (k + 1) / steps)
            segments.append((p, q, width, w_end, birth))
            if depth == 0 and k in (1, 3) and rng.random() < 0.85:
                side = rng.choice((-1.0, 1.0))
                grow(q, angle + side * rng.uniform(0.55, 1.0), length * rng.uniform(0.28, 0.45),
                     w_end * 0.7, birth + rng.uniform(0.10, 0.18), 1)
            width = w_end
            p = q
            birth += 0.52 / steps if depth == 0 else 0.07

    # The point of impact: short spokes already present in the first frame.
    for i in range(6):
        angle = i * math.tau / 6 + rng.uniform(-0.3, 0.3)
        segments.append((Vector((0.0, 0.0)),
                         Vector((math.cos(angle), math.sin(angle))) * rng.uniform(0.25, 0.4),
                         0.026, 0.008, 0.0))
    for i in range(7):
        angle = i * math.tau / 7 + rng.uniform(-0.22, 0.22)
        grow(Vector((0.0, 0.0)), angle, SHATTER_RADIUS * rng.uniform(0.62, 1.0), 0.026,
             0.04 + rng.uniform(0.0, 0.05), 0)
    # Ring fractures: broken arcs that only appear on the decisive beat.
    for radius, chords in ((1.35, 10), (2.65, 14)):
        start = rng.uniform(0.0, math.tau)
        for c in range(chords):
            if rng.random() < 0.3:
                continue
            a0 = start + c * math.tau / chords + rng.uniform(-0.05, 0.05)
            a1 = a0 + math.tau / chords * rng.uniform(0.55, 0.9)
            r0 = radius * rng.uniform(0.96, 1.04)
            r1 = radius * rng.uniform(0.96, 1.04)
            segments.append((Vector((math.cos(a0), math.sin(a0))) * r0,
                             Vector((math.cos(a1), math.sin(a1))) * r1,
                             0.013, 0.009, rng.uniform(0.66, 0.80)))
    flakes = []
    for i in range(16):
        angle = rng.uniform(0.0, math.tau)
        radius = rng.uniform(0.25, 1.1)
        flakes.append((Vector((math.cos(angle), math.sin(angle))) * radius,
                       rng.uniform(0.0, math.tau), rng.uniform(0.12, 0.30),
                       rng.uniform(0.014, 0.028), 0.84))
    return segments, flakes


if "shatter" in TARGETS:
    segments, flakes = crack_tree(1409)
    scene.cycles.samples = 48          # thin lines need the extra samples
    cells = []
    parts = []
    for f in range(SHATTER_FRAMES):
        remove_all(parts)
        t = (f + 1) / SHATTER_FRAMES
        for i, (p0, p1, w0, w1, birth) in enumerate(segments):
            reach = min(1.0, (t - birth) / 0.15)
            if reach <= 0.0:
                continue
            obj = sliver("Crack %03d" % i, p0, p0 + (p1 - p0) * reach,
                         w0, w0 + (w1 - w0) * reach, 0.03, 0.0)
            if obj is not None:
                parts.append(obj)
        for i, (centre, angle, length, width, birth) in enumerate(flakes):
            if t >= birth:
                parts.append(shard("Crack flake %02d" % i, 0.0, angle, length, width,
                                   (crack_face, crack_edge), centre=(centre.x, centre.y)))
        cells.append(capture("time-stop-shatter", SHATTER_CELL, SHATTER_CELL, SHATTER_SPAN, f))
    remove_all(parts)
    scene.cycles.samples = 16
    save_atlas("time-stop-shatter.png", cells, 4)


# ----------------------------------------------------------------- knife ----
# The Duelist's hourglass dagger (docs/characters/duelist.md): a symmetrical
# end-to-end diamond with a waist, antique-gold outer edge, near-black inner
# body and a small hollow diamond at the centre. Only the waist wrap and that
# centre diamond are rendered white, into a separate tint layer, so the game can
# keep ownership colour on the knife without recolouring the gold and black.
#
# Rotation atlas: 16 cells of KNIFE_CELL px in a 4x4 grid, cell i holding the
# knife pointing at screen angle i * 22.5 degrees clockwise (Godot's y-down
# convention, so the Blender object turns by minus that angle). Lighting stays
# fixed to the scene, which is what rotating one sprite in Godot cannot do.
# The glow atlas is the same 16 cells as a flat white silhouette; the game draws
# it enlarged under the dagger in the owner's colour so a dark body still reads
# on a dark backdrop. The streak is one motion-stretched frame at angle 0 for
# near-cap speeds: knife-streak.png rows are body, tint layer, glow silhouette.
KNIFE_CELL = 128
KNIFE_SPAN = 4.0            # scene units across one cell: 32 px per unit
KNIFE_LENGTH = 3.5          # tip to tip, 112 px in the atlas
KNIFE_STEPS = 16
GOLD = (0.571, 0.328, 0.044)        # #C79B3B
IVORY = (0.800, 0.724, 0.559)       # #E7DDC5
NEAR_BLACK = (0.030, 0.030, 0.042)  # #111117, lifted a touch so facets read


def knife_material(name, color, metallic, roughness, alpha=1.0):
    return surface_material(name, color, metallic, roughness, alpha)


def ridged(name, outline, height, z, material, scale_x=1.0, offset_x=0.0, drop=0.0):
    """Mirror `outline` (right half, tip first, ending on the axis of symmetry)
    into a closed hourglass and lift a central ridge so the two long facets
    catch the lights differently."""
    right = [(x * scale_x + offset_x, y) for x, y in outline]
    left = [(-x * scale_x + offset_x, y) for x, y in reversed(outline[:-1])]
    top = right + left
    verts = []
    faces = []
    last = len(top) - 1
    for i, (x, y) in enumerate(top):
        lift = height if 0 < i < last else 0.0
        verts.append((x, y, z - drop))
        verts.append((x, -y, z - drop))
        verts.append((x, 0.0, z - drop + lift))
    for i in range(last):
        a, b = i * 3, (i + 1) * 3
        faces.append((a, b, b + 2, a + 2))
        faces.append((a + 2, b + 2, b + 1, a + 1))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


EDGE_OUTLINE = [(1.75, 0.0), (1.30, 0.23), (0.95, 0.40), (0.50, 0.30), (0.22, 0.17), (0.0, 0.14)]
BODY_OUTLINE = [(1.42, 0.0), (1.18, 0.11), (0.95, 0.20), (0.52, 0.145), (0.26, 0.075), (0.0, 0.055)]
WRAP_OUTLINE = [(0.32, 0.0), (0.28, 0.20), (0.15, 0.25), (0.0, 0.26)]
CENTRE_OUTLINE = [(0.17, 0.0), (0.0, 0.085)]
HOLLOW_OUTLINE = [(0.10, 0.0), (0.0, 0.045)]


def build_knife(prefix, scale_x=1.0, offset_x=0.0, alpha=1.0, drop=0.0, stretch_all=False):
    """Returns (body_parts, tint_parts) for one knife. The blades stretch by
    scale_x; the waist and centre stretch too only when stretch_all is set
    (motion echoes). `drop` lowers the whole knife so an echo sits under the
    knife in front of it instead of fighting it for the same surface."""
    sx = scale_x if stretch_all else 1.0
    gold = knife_material(prefix + " antique gold edge", GOLD, 0.85, 0.22, alpha)
    black = knife_material(prefix + " near-black body", NEAR_BLACK, 0.80, 0.20, alpha)
    ivory = knife_material(prefix + " ivory wrap trim", IVORY, 0.15, 0.45, alpha)
    white = knife_material(prefix + " tint layer (white, player colour at runtime)",
                           (0.90, 0.90, 0.90), 0.25, 0.40, alpha)
    body = [
        ridged(prefix + " gold edge", EDGE_OUTLINE, 0.14, 0.0, gold, scale_x, offset_x, drop),
        ridged(prefix + " black body", BODY_OUTLINE, 0.12, 0.09, black, scale_x, offset_x, drop),
        ridged(prefix + " ivory trim", WRAP_OUTLINE, 0.06, 0.20, ivory, sx, offset_x, drop),
        ridged(prefix + " centre diamond rim", CENTRE_OUTLINE, 0.03, 0.30, gold, sx, offset_x, drop),
    ]
    tint = [
        ridged(prefix + " waist wrap", WRAP_OUTLINE, 0.08, 0.25, white, 0.78 * sx, offset_x, drop),
        ridged(prefix + " hollow centre", HOLLOW_OUTLINE, 0.02, 0.34, white, sx, offset_x, drop),
    ]
    return body, tint


knife_body, knife_tint = build_knife("Knife")
angles = [i * math.tau / KNIFE_STEPS for i in range(KNIFE_STEPS)]
# Motion streak: the same dagger drawn out along its flight, with two fading
# echoes behind it. One frame; the game rotates it to the real velocity.
streak_body, streak_tint, streak_glow = [], [], []
for offset, alpha, drop in [(0.0, 1.0, 0.0), (-0.65, 0.40, 0.6), (-1.25, 0.16, 1.2)]:
    body, tint = build_knife("Knife streak %.2f" % offset, 1.45, offset, alpha, drop, offset < 0.0)
    streak_body += body
    streak_tint += tint
    if offset > -1.0:
        streak_glow += body      # the faintest echo stays out of the glow
set_visible(knife_body + knife_tint + streak_body + streak_tint, False)

if "knife" in TARGETS:
    set_visible(knife_body, True)
    save_atlas("knife.png", render_cells("knife", KNIFE_CELL, KNIFE_CELL, KNIFE_SPAN,
                                         knife_body, angles), 4)
    set_visible(knife_body, False)
    set_visible(knife_tint, True)
    save_atlas("knife-tint.png", render_cells("knife-tint", KNIFE_CELL, KNIFE_CELL, KNIFE_SPAN,
                                              knife_tint, angles), 4)
    set_visible(knife_tint, False)
    set_visible(knife_body, True)
    save_atlas("knife-glow.png", render_silhouettes("knife-glow", KNIFE_CELL, KNIFE_CELL, KNIFE_SPAN,
                                                    knife_body, angles), 4)
    set_visible(knife_body, False)

    set_visible(streak_body, True)
    streak_cells = render_cells("knife-streak", KNIFE_CELL * 2, KNIFE_CELL, KNIFE_SPAN * 2,
                                streak_body, [0.0])
    set_visible(streak_body, False)
    set_visible(streak_tint, True)
    streak_cells += render_cells("knife-streak-tint", KNIFE_CELL * 2, KNIFE_CELL, KNIFE_SPAN * 2,
                                 streak_tint, [0.0])
    set_visible(streak_tint, False)
    set_visible(streak_glow, True)
    streak_cells += render_silhouettes("knife-streak-glow", KNIFE_CELL * 2, KNIFE_CELL, KNIFE_SPAN * 2,
                                       streak_glow, [0.0])
    set_visible(streak_glow, False)
    save_atlas("knife-streak.png", streak_cells, 1)

set_visible(crest, True)
scene.camera.data.ortho_scale = DIAL_SPAN
scene.render.resolution_x = scene.render.resolution_y = DIAL_CELL
scene.render.filepath = str(OUT / "super-dial.png")
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "art_source/blender/combat-art-v1.blend"))
