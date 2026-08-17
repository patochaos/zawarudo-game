from __future__ import annotations

import sys

import bpy


REQUIRED_COLLECTIONS = {
    "REFERENCES_DO_NOT_MODEL",
    "SCALE_GUIDES",
    "MODEL_EXECUTOR",
    "RIG_EXECUTOR",
}
REQUIRED_REFERENCES = {"REF_Front", "REF_Left", "REF_Back"}


def fail(message: str) -> None:
    print(f"EXECUTOR SCENE INVALID: {message}")
    raise SystemExit(1)


missing_collections = REQUIRED_COLLECTIONS - set(bpy.data.collections.keys())
if missing_collections:
    fail(f"missing collections: {sorted(missing_collections)}")

missing_references = REQUIRED_REFERENCES - set(bpy.data.objects.keys())
if missing_references:
    fail(f"missing references: {sorted(missing_references)}")

if bpy.context.scene.get("fighter_id") != "gilded_executor":
    fail("fighter_id is not gilded_executor")
if bpy.context.scene.get("approved_design") != "idle-v1":
    fail("approved_design is not idle-v1")
if abs(float(bpy.context.scene.get("target_height_m", 0.0)) - 1.86) > 0.001:
    fail("target height is not 1.86 m")
if bpy.context.scene.camera is None or bpy.context.scene.camera.data.type != "ORTHO":
    fail("orthographic review camera is missing")

print("Executor Blender scene: all structural checks passed")
sys.exit(0)
