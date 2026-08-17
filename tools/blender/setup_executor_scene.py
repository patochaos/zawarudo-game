from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy


CHARACTER_HEIGHT_M = 1.86
REFERENCE_HEIGHT_M = 2.05


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create the Gilded Executor Blender production scene.")
    parser.add_argument("--references", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--preview", required=True, type=Path)
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(argv)


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def collection(name: str) -> bpy.types.Collection:
    value = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(value)
    return value


def image_material(name: str, image_path: Path) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = bpy.data.images.load(str(image_path), check_existing=True)
    emission.inputs["Strength"].default_value = 0.8
    material.node_tree.links.new(texture.outputs["Color"], emission.inputs["Color"])
    material.node_tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    return material


def reference_plane(
    target: bpy.types.Collection,
    name: str,
    image_path: Path,
    location: tuple[float, float, float],
    rotation: tuple[float, float, float],
    render: bool,
) -> bpy.types.Object:
    image = bpy.data.images.load(str(image_path), check_existing=True)
    aspect = image.size[0] / image.size[1]
    half_width = REFERENCE_HEIGHT_M * aspect * 0.5
    half_height = REFERENCE_HEIGHT_M * 0.5
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(
        [(-half_width, -half_height, 0.0), (half_width, -half_height, 0.0), (half_width, half_height, 0.0), (-half_width, half_height, 0.0)],
        [],
        [(0, 1, 2, 3)],
    )
    mesh.uv_layers.new(name="UVMap")
    uv_values = ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))
    for loop, uv in zip(mesh.uv_layers[0].data, uv_values):
        loop.uv = uv
    obj = bpy.data.objects.new(name, mesh)
    target.objects.link(obj)
    obj.location = location
    obj.rotation_euler = rotation
    obj.data.materials.append(image_material(f"{name}_Material", image_path))
    obj.hide_render = not render
    obj.show_in_front = True
    obj.display_type = "TEXTURED"
    return obj


def guide_material() -> bpy.types.Material:
    material = bpy.data.materials.new("ScaleGuide_Gold")
    material.diffuse_color = (0.83, 0.55, 0.12, 1.0)
    return material


def add_scale_guides(target: bpy.types.Collection) -> None:
    material = guide_material()
    for name, z in (("Floor", 0.0), ("Knee", 0.53), ("Hip", 0.98), ("Shoulder", 1.52), ("Crown", CHARACTER_HEIGHT_M)):
        bpy.ops.mesh.primitive_cube_add(location=(0.0, -0.03, z), scale=(0.58, 0.004, 0.004))
        obj = bpy.context.object
        obj.name = f"Guide_{name}_{z:.2f}m"
        for owner in list(obj.users_collection):
            owner.objects.unlink(obj)
        target.objects.link(obj)
        obj.data.materials.append(material)
        obj.hide_render = True


def add_camera() -> bpy.types.Object:
    camera_data = bpy.data.cameras.new("Executor_Ortho_Camera")
    camera = bpy.data.objects.new("Executor_Ortho_Camera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = (0.0, -6.0, 0.93)
    direction = mathutils.Vector((0.0, 0.0, 0.93)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.2
    bpy.context.scene.camera = camera
    return camera


def configure_scene(preview: Path) -> None:
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.length_unit = "METERS"
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(preview)
    scene.world.color = (0.04, 0.04, 0.04)


def main() -> None:
    args = parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.preview.parent.mkdir(parents=True, exist_ok=True)
    reset_scene()
    configure_scene(args.preview)

    refs = collection("REFERENCES_DO_NOT_MODEL")
    guides = collection("SCALE_GUIDES")
    collection("MODEL_EXECUTOR")
    collection("RIG_EXECUTOR")

    front = reference_plane(
        refs,
        "REF_Front",
        args.references / "gilded-executor-front-reference-v1.png",
        (0.0, 0.35, 1.025),
        (math.radians(90.0), 0.0, 0.0),
        True,
    )
    reference_plane(
        refs,
        "REF_Left",
        args.references / "gilded-executor-left-reference-v1.png",
        (0.35, 0.0, 1.025),
        (math.radians(90.0), 0.0, math.radians(90.0)),
        False,
    )
    reference_plane(
        refs,
        "REF_Back",
        args.references / "gilded-executor-back-reference-v1.png",
        (0.0, 0.40, 1.025),
        (math.radians(90.0), 0.0, 0.0),
        False,
    )
    front["approved_reference"] = True
    add_scale_guides(guides)

    # Camera intentionally renders only the approved front reference. Modeling collections start empty.
    camera_data = bpy.data.cameras.new("Executor_Ortho_Camera")
    camera = bpy.data.objects.new("Executor_Ortho_Camera", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = (0.0, -6.0, 1.025)
    direction = mathutils.Vector((0.0, 0.35, 1.025)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.18
    bpy.context.scene.camera = camera

    bpy.context.scene["fighter_id"] = "gilded_executor"
    bpy.context.scene["approved_design"] = "idle-v1"
    bpy.context.scene["target_height_m"] = CHARACTER_HEIGHT_M
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output))
    bpy.ops.render.render(write_still=True)
    print(f"Saved {args.output}")
    print(f"Rendered {args.preview}")


if __name__ == "__main__":
    import mathutils

    main()
