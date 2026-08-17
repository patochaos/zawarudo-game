from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


ARMATURE_NAME = "Executor_Rig_Prototype_v1"
MESH_NAME = "Executor_AI_Base_v1"
FPS = 12


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Rig the Executor candidate and render prototype sprite frames.")
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--frames", required=True, type=Path)
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(argv)


def create_bone(
    armature: bpy.types.Armature,
    name: str,
    head: tuple[float, float, float],
    tail: tuple[float, float, float],
    parent: str | None = None,
) -> None:
    bone = armature.edit_bones.new(name)
    bone.head = head
    bone.tail = tail
    bone.use_deform = name != "root"
    if parent is not None:
        bone.parent = armature.edit_bones[parent]


def create_rig(target: bpy.types.Collection) -> bpy.types.Object:
    existing = bpy.data.objects.get(ARMATURE_NAME)
    if existing is not None:
        bpy.data.objects.remove(existing, do_unlink=True)

    data = bpy.data.armatures.new(f"{ARMATURE_NAME}_Data")
    rig = bpy.data.objects.new(ARMATURE_NAME, data)
    target.objects.link(rig)
    rig.show_in_front = True
    rig.data.display_type = "OCTAHEDRAL"

    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    create_bone(data, "root", (0.0, 0.0, 0.02), (0.0, 0.0, 0.24))
    create_bone(data, "pelvis", (0.0, 0.0, 0.78), (0.0, 0.0, 0.98), "root")
    create_bone(data, "spine", (0.0, 0.0, 0.98), (0.0, 0.0, 1.22), "pelvis")
    create_bone(data, "chest", (0.0, 0.0, 1.22), (0.0, 0.0, 1.44), "spine")
    create_bone(data, "neck", (0.0, 0.0, 1.44), (0.0, 0.0, 1.57), "chest")
    create_bone(data, "head", (0.0, 0.0, 1.57), (0.0, 0.0, 1.80), "neck")

    for suffix, side in (("L", 1.0), ("R", -1.0)):
        create_bone(data, f"clavicle.{suffix}", (0.0, 0.02 * side, 1.42), (0.0, 0.15 * side, 1.42), "chest")
        create_bone(data, f"upper_arm.{suffix}", (0.0, 0.15 * side, 1.42), (0.0, 0.29 * side, 1.17), f"clavicle.{suffix}")
        create_bone(data, f"forearm.{suffix}", (0.0, 0.29 * side, 1.17), (0.0, 0.35 * side, 0.94), f"upper_arm.{suffix}")
        create_bone(data, f"hand.{suffix}", (0.0, 0.35 * side, 0.94), (0.0, 0.36 * side, 0.82), f"forearm.{suffix}")
        create_bone(data, f"thigh.{suffix}", (0.0, 0.10 * side, 0.86), (0.0, 0.11 * side, 0.50), "pelvis")
        create_bone(data, f"shin.{suffix}", (0.0, 0.11 * side, 0.50), (0.0, 0.11 * side, 0.13), f"thigh.{suffix}")
        create_bone(data, f"foot.{suffix}", (0.0, 0.11 * side, 0.13), (0.16, 0.11 * side, 0.06), f"shin.{suffix}")
        create_bone(data, f"coat.{suffix}", (0.02, 0.10 * side, 0.88), (0.02, 0.27 * side, 0.30), "pelvis")
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


def bind_automatic(mesh: bpy.types.Object, rig: bpy.types.Object) -> None:
    mesh.parent = None
    mesh.vertex_groups.clear()
    for modifier in list(mesh.modifiers):
        if modifier.type == "ARMATURE":
            mesh.modifiers.remove(modifier)
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    weighted = sum(1 for vertex in mesh.data.vertices if vertex.groups)
    if weighted < int(len(mesh.data.vertices) * 0.98):
        raise RuntimeError(f"Automatic weights covered only {weighted}/{len(mesh.data.vertices)} vertices")
    print(f"Automatic weights: {weighted}/{len(mesh.data.vertices)} vertices")


def reset_pose(rig: bpy.types.Object) -> None:
    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"
        bone.location = (0.0, 0.0, 0.0)
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def rotate(rig: bpy.types.Object, name: str, x: float = 0.0, y: float = 0.0, z: float = 0.0) -> None:
    bone = rig.pose.bones[name]
    bone.rotation_euler = (x, y, z)


def pose_idle(rig: bpy.types.Object, phase: float) -> None:
    wave = math.sin(phase * math.tau)
    rig.pose.bones["pelvis"].location.z = 0.008 * wave
    rotate(rig, "spine", x=0.025 * wave)
    rotate(rig, "chest", x=-0.035 * wave)
    rotate(rig, "head", x=0.018 * wave)
    rotate(rig, "upper_arm.L", x=0.035 * wave)
    rotate(rig, "upper_arm.R", x=-0.035 * wave)
    rotate(rig, "coat.L", x=0.025 * wave)
    rotate(rig, "coat.R", x=-0.025 * wave)


def pose_run(rig: bpy.types.Object, phase: float) -> None:
    wave = math.sin(phase * math.tau)
    lift = abs(math.cos(phase * math.tau))
    rig.pose.bones["pelvis"].location.z = -0.018 * lift
    rotate(rig, "spine", y=-0.10)
    rotate(rig, "thigh.L", x=0.34 * wave)
    rotate(rig, "thigh.R", x=-0.34 * wave)
    rotate(rig, "shin.L", x=-0.38 * max(0.0, -wave))
    rotate(rig, "shin.R", x=-0.38 * max(0.0, wave))
    rotate(rig, "upper_arm.L", x=-0.34 * wave)
    rotate(rig, "upper_arm.R", x=0.34 * wave)
    rotate(rig, "forearm.L", x=-0.18)
    rotate(rig, "forearm.R", x=-0.18)
    rotate(rig, "coat.L", x=-0.16 * wave)
    rotate(rig, "coat.R", x=0.16 * wave)


def pose_rise(rig: bpy.types.Object, phase: float) -> None:
    tuck = math.sin(phase * math.pi) * 0.7 + 0.2
    rotate(rig, "spine", y=-0.10)
    rotate(rig, "thigh.L", x=0.34 * tuck)
    rotate(rig, "thigh.R", x=-0.26 * tuck)
    rotate(rig, "shin.L", x=-0.52 * tuck)
    rotate(rig, "shin.R", x=-0.35 * tuck)
    rotate(rig, "upper_arm.L", x=-0.30 * tuck)
    rotate(rig, "upper_arm.R", x=0.22 * tuck)
    rotate(rig, "coat.L", x=-0.18 * tuck)
    rotate(rig, "coat.R", x=0.14 * tuck)


def pose_fall(rig: bpy.types.Object, phase: float) -> None:
    spread = 0.22 + phase * 0.18
    rotate(rig, "spine", y=0.08)
    rotate(rig, "thigh.L", x=-0.12)
    rotate(rig, "thigh.R", x=0.12)
    rotate(rig, "shin.L", x=0.18)
    rotate(rig, "shin.R", x=0.18)
    rotate(rig, "upper_arm.L", x=spread)
    rotate(rig, "upper_arm.R", x=-spread)
    rotate(rig, "forearm.L", x=-0.20)
    rotate(rig, "forearm.R", x=0.20)
    rotate(rig, "coat.L", x=0.22)
    rotate(rig, "coat.R", x=-0.22)


def pose_shoot(rig: bpy.types.Object, phase: float) -> None:
    recoil = math.sin(min(1.0, phase * 2.0) * math.pi)
    rotate(rig, "spine", y=-0.08 - recoil * 0.08)
    rotate(rig, "chest", x=-0.04, y=-recoil * 0.10)
    rotate(rig, "clavicle.R", x=-0.28)
    rotate(rig, "upper_arm.R", x=-1.18 + recoil * 0.18, y=-0.12)
    rotate(rig, "forearm.R", x=-0.04 - recoil * 0.08)
    rotate(rig, "hand.R", x=0.04)
    rotate(rig, "upper_arm.L", x=0.22)
    rotate(rig, "forearm.L", x=-0.32)
    rotate(rig, "head", y=0.07)
    rotate(rig, "coat.L", x=0.06 * recoil)
    rotate(rig, "coat.R", x=-0.10 * recoil)


def pose_lock(rig: bpy.types.Object, phase: float) -> None:
    pose_shoot(rig, min(phase, 0.6))
    rotate(rig, "spine", y=-0.14)
    rotate(rig, "head", x=-0.06, y=0.10)


ANIMATIONS = {
    "idle": (6, pose_idle),
    "run": (8, pose_run),
    "rise": (4, pose_rise),
    "fall": (4, pose_fall),
    "shoot": (6, pose_shoot),
    "lock": (2, pose_lock),
}


def key_action(rig: bpy.types.Object, name: str, frame_count: int, pose_fn) -> bpy.types.Action:
    action = bpy.data.actions.get(f"Executor_{name.upper()}") or bpy.data.actions.new(f"Executor_{name.upper()}")
    action.use_fake_user = True
    action.frame_start = 1
    action.frame_end = frame_count
    rig.animation_data_create()
    rig.animation_data.action = action
    for frame in range(1, frame_count + 1):
        reset_pose(rig)
        phase = float(frame - 1) / float(max(1, frame_count))
        pose_fn(rig, phase)
        for bone in rig.pose.bones:
            bone.keyframe_insert("location", frame=frame, group=bone.name)
            bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
            bone.keyframe_insert("scale", frame=frame, group=bone.name)
    return action


def add_area_light(name: str, location: tuple[float, float, float], energy: float, color: tuple[float, float, float], size: float) -> None:
    old = bpy.data.objects.get(name)
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.color = color
    data.shape = "DISK"
    data.size = size
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0.0, 0.0, 0.95)) - obj.location).to_track_quat("-Z", "Y").to_euler()


def configure_render(frames_path: Path) -> bpy.types.Object:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.fps = FPS

    for name in ("Executor_GateA_Ground", "Executor_GateA_Key", "Executor_GateA_Fill", "Executor_GateA_Rim"):
        obj = bpy.data.objects.get(name)
        if obj is not None:
            obj.hide_render = True
    for collection_name in ("REFERENCES_DO_NOT_MODEL", "SCALE_GUIDES"):
        collection = bpy.data.collections.get(collection_name)
        if collection is not None:
            collection.hide_render = True

    add_area_light("Executor_Sprite_Key", (-3.0, -4.0, 5.0), 850.0, (1.0, 0.78, 0.48), 4.0)
    add_area_light("Executor_Sprite_Fill", (3.5, -2.0, 3.0), 520.0, (0.42, 0.54, 1.0), 4.0)
    add_area_light("Executor_Sprite_Rim", (1.5, 3.5, 4.0), 950.0, (1.0, 0.56, 0.18), 3.0)

    camera = bpy.data.objects.get("Executor_Sprite_Camera")
    if camera is None:
        camera_data = bpy.data.cameras.new("Executor_Sprite_Camera")
        camera = bpy.data.objects.new("Executor_Sprite_Camera", camera_data)
        scene.collection.objects.link(camera)
    target = Vector((0.0, 0.0, 0.94))
    camera.location = Vector((-5.5, 0.0, target.z))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.16
    scene.camera = camera
    frames_path.mkdir(parents=True, exist_ok=True)
    return camera


def render_actions(rig: bpy.types.Object, actions: dict[str, bpy.types.Action], frames_path: Path) -> None:
    scene = bpy.context.scene
    for name, action in actions.items():
        rig.animation_data.action = action
        frame_count = int(action.frame_end)
        for index in range(frame_count):
            scene.frame_set(index + 1)
            scene.render.filepath = str(frames_path / f"{name}_{index:02d}.png")
            bpy.ops.render.render(write_still=True)
        print(f"Rendered {name}: {frame_count} frames")


def main() -> None:
    args = parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(args.input))
    mesh = bpy.data.objects.get(MESH_NAME)
    if mesh is None or mesh.type != "MESH":
        raise RuntimeError(f"Missing mesh object: {MESH_NAME}")
    rig_collection = bpy.data.collections.get("RIG_EXECUTOR")
    if rig_collection is None:
        rig_collection = bpy.data.collections.new("RIG_EXECUTOR")
        bpy.context.scene.collection.children.link(rig_collection)
    rig = create_rig(rig_collection)
    bind_automatic(mesh, rig)
    actions = {name: key_action(rig, name, count, pose_fn) for name, (count, pose_fn) in ANIMATIONS.items()}
    configure_render(args.frames)

    bpy.context.scene["rig_status"] = "prototype_v1"
    bpy.context.scene["sprite_fps"] = FPS
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output))
    render_actions(rig, actions, args.frames)
    print(f"Saved rigged prototype: {args.output}")


if __name__ == "__main__":
    main()
