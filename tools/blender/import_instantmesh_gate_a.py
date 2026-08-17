from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


TARGET_HEIGHT_M = 1.86


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import and render an InstantMesh Gate A candidate.")
    parser.add_argument("--template", required=True, type=Path)
    parser.add_argument("--mesh", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--previews", required=True, type=Path)
    parser.add_argument("--flip-vertical", action="store_true", help="Rotate non-textured InstantMesh exports upright.")
    parser.add_argument("--front-angle", type=float, default=270.0)
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(argv)


def world_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    corners = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    minimum = Vector(tuple(min(c[i] for c in corners) for i in range(3)))
    maximum = Vector(tuple(max(c[i] for c in corners) for i in range(3)))
    return minimum, maximum


def move_to_collection(objects: list[bpy.types.Object], target: bpy.types.Collection) -> None:
    for obj in objects:
        for owner in list(obj.users_collection):
            owner.objects.unlink(obj)
        target.objects.link(obj)


def normalize_scale(objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    minimum, maximum = world_bounds(objects)
    source_height = maximum.z - minimum.z
    if source_height <= 0.0:
        raise RuntimeError("Imported mesh has no measurable height")
    scale = TARGET_HEIGHT_M / source_height
    for obj in objects:
        obj.scale *= scale
    bpy.context.view_layer.update()

    minimum, maximum = world_bounds(objects)
    offset = Vector((-(minimum.x + maximum.x) * 0.5, -(minimum.y + maximum.y) * 0.5, -minimum.z))
    for obj in objects:
        obj.location += offset
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def candidate_material(obj: bpy.types.Object) -> bpy.types.Material:
    material = bpy.data.materials.new("Executor_AI_VertexColor")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = nodes.get("Principled BSDF")
    principled.inputs["Roughness"].default_value = 0.5
    principled.inputs["Metallic"].default_value = 0.08

    if obj.data.color_attributes:
        attribute_name = obj.data.color_attributes.active_color_name or obj.data.color_attributes[0].name
        attribute = nodes.new("ShaderNodeAttribute")
        attribute.attribute_name = attribute_name
        links.new(attribute.outputs["Color"], principled.inputs["Base Color"])
    else:
        principled.inputs["Base Color"].default_value = (0.62, 0.52, 0.34, 1.0)
    return material


def configure_candidate(objects: list[bpy.types.Object]) -> None:
    for obj in objects:
        obj.name = "Executor_AI_Base_v1"
        obj.data.name = "Executor_AI_Base_v1_Mesh"
        has_image_texture = any(
            material is not None
            and material.use_nodes
            and any(node.type == "TEX_IMAGE" and node.image is not None for node in material.node_tree.nodes)
            for material in obj.data.materials
        )
        if not has_image_texture:
            obj.data.materials.clear()
            obj.data.materials.append(candidate_material(obj))
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        obj["source"] = "InstantMesh"
        obj["gate"] = "A_candidate_unapproved"
        obj["target_height_m"] = TARGET_HEIGHT_M


def remove_review_objects() -> None:
    for name in ("Executor_GateA_Ground", "Executor_GateA_Key", "Executor_GateA_Fill", "Executor_GateA_Rim"):
        obj = bpy.data.objects.get(name)
        if obj is not None:
            bpy.data.objects.remove(obj, do_unlink=True)


def add_area_light(name: str, location: tuple[float, float, float], energy: float, color: tuple[float, float, float], size: float) -> None:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.color = color
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = ((Vector((0.0, 0.0, 1.0)) - obj.location).to_track_quat("-Z", "Y").to_euler())


def configure_review_scene() -> bpy.types.Object:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 600
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.world.color = (0.012, 0.009, 0.022)

    for collection_name in ("REFERENCES_DO_NOT_MODEL", "SCALE_GUIDES"):
        collection = bpy.data.collections.get(collection_name)
        if collection is not None:
            collection.hide_render = True

    remove_review_objects()
    bpy.ops.mesh.primitive_plane_add(size=20.0, location=(0.0, 0.0, -0.006))
    ground = bpy.context.object
    ground.name = "Executor_GateA_Ground"
    ground_material = bpy.data.materials.new("Executor_GateA_Ground_Material")
    ground_material.diffuse_color = (0.018, 0.014, 0.03, 1.0)
    ground.data.materials.append(ground_material)

    add_area_light("Executor_GateA_Key", (-3.0, -4.0, 5.0), 950.0, (1.0, 0.78, 0.48), 4.0)
    add_area_light("Executor_GateA_Fill", (4.0, -2.0, 2.8), 700.0, (0.42, 0.52, 1.0), 4.0)
    add_area_light("Executor_GateA_Rim", (1.5, 3.5, 4.0), 1200.0, (1.0, 0.58, 0.18), 3.0)

    camera = bpy.data.objects.get("Executor_Ortho_Camera")
    if camera is None:
        camera_data = bpy.data.cameras.new("Executor_Ortho_Camera")
        camera = bpy.data.objects.new("Executor_Ortho_Camera", camera_data)
        scene.collection.objects.link(camera)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.15
    scene.camera = camera
    return camera


def point_camera(camera: bpy.types.Object, angle_degrees: float) -> None:
    angle = math.radians(angle_degrees)
    target = Vector((0.0, 0.0, TARGET_HEIGHT_M * 0.5))
    camera.location = Vector((5.5 * math.sin(angle), -5.5 * math.cos(angle), target.z))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()


def main() -> None:
    args = parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.previews.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(args.template))

    model_collection = bpy.data.collections["MODEL_EXECUTOR"]
    for obj in list(model_collection.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=str(args.mesh), forward_axis="NEGATIVE_Y", up_axis="Z")
    imported = [obj for obj in bpy.data.objects if obj not in before and obj.type == "MESH"]
    if not imported:
        raise RuntimeError("OBJ import produced no mesh objects")
    if args.flip_vertical:
        for obj in imported:
            obj.rotation_euler.y = math.pi
    move_to_collection(imported, model_collection)
    normalize_scale(imported)
    configure_candidate(imported)
    camera = configure_review_scene()

    bpy.context.scene["gate_a_status"] = "candidate_unapproved"
    bpy.context.scene["source_mesh"] = str(args.mesh)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output))

    views = (
        ("front", args.front_angle),
        ("three-quarter", args.front_angle + 45.0),
        ("side", args.front_angle + 90.0),
        ("back", args.front_angle + 180.0),
    )
    for name, angle in views:
        point_camera(camera, angle)
        bpy.context.scene.render.filepath = str(args.previews / f"executor-gate-a-{name}.png")
        bpy.ops.render.render(write_still=True)

    minimum, maximum = world_bounds(imported)
    print(f"Imported {sum(len(obj.data.vertices) for obj in imported)} vertices")
    print(f"Normalized bounds: min={tuple(round(v, 4) for v in minimum)}, max={tuple(round(v, 4) for v in maximum)}")
    print(f"Saved candidate: {args.output}")


if __name__ == "__main__":
    main()
