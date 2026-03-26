# Animation Replacement Pipeline

This pipeline converts your reference clips into game-ready replacement animations for the player model.

It is designed for this repo and outputs replacement GLBs that `PlayerVisual` already prioritizes:

- `art/characters/player/replacements/Base_Model_V01_Walking_Replacement.glb`
- `art/characters/player/replacements/Base_Model_V01_Attack_Replacement.glb`
- `art/characters/player/replacements/Base_Model_V01_Defend_Replacement.glb`

## What the pipeline does

1. Normalizes your example videos (`attackExample`, `walkingExample`, `defendexample`).
2. Stages expected mocap source files (`attack.fbx`, `walk.fbx`, `defend.fbx`).
3. Retargets mocap data to your player rig in Blender via script.
4. Exports Godot-ready GLB replacement clips.

## Prerequisites

- Python 3.10+
- Blender (4.x recommended) available via CLI
- A video-to-mocap output for each clip (FBX/BVH), generated from your staged videos
  - You can use your preferred tool/service (Rokoko Vision, DeepMotion, Plask, etc.)

## One-command flow

Run from repo root.

1) Prepare example clips:

```powershell
.\tools\animation_pipeline\prepare_example_clips.ps1
```

2) Convert staged videos to mocap externally and place files here:

- `tools/animation_pipeline/work/mocap/attack.fbx`
- `tools/animation_pipeline/work/mocap/walk.fbx`
- `tools/animation_pipeline/work/mocap/defend.fbx`

3) Retarget + export replacement animation GLBs:

```powershell
.\tools\animation_pipeline\run_retarget_pipeline.ps1 -BlenderExe "C:\Program Files\Blender Foundation\Blender 4.2\blender.exe"
```

4) Import into Godot:

```powershell
.\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe --headless --path . --import
```

## Bone maps

Default map:

- `tools/animation_pipeline/bone_maps/mixamo_to_base_model_v01.json`

Edit `tools/animation_pipeline/retarget_jobs.json` if your mocap provider uses different bone names.

## Notes

- The game now prefers replacement clips first in `scripts/visuals/player_visual.gd`.
- If a replacement file is missing, it automatically falls back to the existing clip.
