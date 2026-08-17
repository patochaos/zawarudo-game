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

## Local AI reconstruction candidate

The Gate A candidate is generated locally with InstantMesh and imported as a modeling reference. It is not approved game geometry: use it for volume, silhouette and retopology, then rebuild the face, hands, boots, coat edges and gold ornaments before rigging.

The 16 GB GPU profile uses a 96³ extraction grid. Generate the textured OBJ from the InstantMesh checkout:

```bash
HF_HOME=/mnt/d/AI-tools/hf-cache \
CUDA_HOME=/usr/local/cuda-12.8 \
TORCH_CUDA_ARCH_LIST=12.0 \
PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
/home/pato/venvs/instantmesh/bin/python -u run.py \
  '/mnt/d/Zawarudo game/tools/instantmesh/instant-mesh-large.yaml' \
  inputs/executor-front-v1.png \
  --output_path outputs/executor-v1-grid96-textured \
  --diffusion_steps 50 \
  --seed 42 \
  --export_texmap
```

Import, normalize to 1.86 m, pack the texture and render the four-angle review from the project root:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background `
  --python 'D:\Zawarudo game\tools\blender\import_instantmesh_gate_a.py' -- `
  --template 'D:\Zawarudo game\art_source\blender\gilded-executor-v1.blend' `
  --mesh 'D:\AI-tools\InstantMesh\outputs\executor-v1-grid96-textured\instant-mesh-large\meshes\executor-front-v1.obj' `
  --output 'D:\Zawarudo game\art_source\blender\gilded-executor-gate-a-ai-textured-v1.blend' `
  --previews 'D:\Zawarudo game\previews\gilded-executor-gate-a-ai-textured-v1' `
  --front-angle 270
```

## Rigged sprite prototype

This experiment is disabled by default and excluded from production exports. Set
`fighter_visuals_enabled` on `GameManager` only when reviewing it in the editor.

Create the non-final armature, automatic skinning and the six deterministic actions (`idle`, `run`, `rise`, `fall`, `shoot`, `lock`):

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background `
  --python 'D:\Zawarudo game\tools\blender\rig_and_render_executor.py' -- `
  --input 'D:\Zawarudo game\art_source\blender\gilded-executor-gate-a-ai-textured-v1.blend' `
  --output 'D:\Zawarudo game\art_source\blender\gilded-executor-rigged-prototype-v1.blend' `
  --frames 'D:\Zawarudo game\art_source\renders\gilded-executor-prototype-v1'
```

Pack the rendered frames into Godot atlases and create the animation review sheet:

```powershell
python .\tools\art\build_executor_sprite_atlases.py `
  --frames '.\art_source\renders\gilded-executor-prototype-v1' `
  --output '.\assets\art\fighters\gilded-executor-prototype-v1' `
  --preview '.\previews\gilded-executor-prototype-v1\animation-contact-sheet.png'
```

`FighterVisual` samples these atlases from simulation ticks. It never drives movement, collision, knife origin or root motion. `SHOT` is reconstructed from `exec_tick` during execution and the replay frame index during replay.
