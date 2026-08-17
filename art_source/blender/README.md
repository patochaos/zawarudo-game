# Executor Blender source

Open `gilded-executor-v1.blend` in Blender 5.2 LTS.

Collections:

- `REFERENCES_DO_NOT_MODEL`: approved front, left and back references.
- `SCALE_GUIDES`: 1.86 m character height and joint-height guides.
- `MODEL_EXECUTOR`: the only collection used for character geometry.
- `RIG_EXECUTOR`: reserved for the approved rig.

Use numpad `1` for the front reference and numpad `3` for the side reference. Toggle the reference objects in the Outliner as needed. Never apply modifiers or edits to the reference collection.

Regenerate the setup from the project root:

```powershell
python .\tools\art\prepare_executor_references.py .\docs\concepts\gilded-executor-model-sheet-v1.png .\art_source\blender\references\gilded-executor-v1

& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --python 'D:\Zawarudo game\tools\blender\setup_executor_scene.py' -- --references 'D:\Zawarudo game\art_source\blender\references\gilded-executor-v1' --output 'D:\Zawarudo game\art_source\blender\gilded-executor-v1.blend' --preview 'D:\Zawarudo game\previews\gilded-executor-blender-setup-v1.png'
```

The `.gdignore` at `art_source/` prevents Godot from importing DCC source files.
