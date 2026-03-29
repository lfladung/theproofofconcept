# Animation Replacement Pipeline

Non-runtime **FBX** and **Blender (`.blend`)** sources were moved out of the repo to keep Git/LFS lean. They live under:

`C:\git\dungeonGame\random\dungeonGameConvertToMultplayer\` (mirrors paths: `art\...`, `tools\animation_pipeline\work\mocap\...`).

`retarget_jobs.json` points mocap FBX inputs at that folder. `convert_example_clips_to_mocap.ps1` still writes new FBX into **this repo** at `tools/animation_pipeline/work/mocap/`; copy or retarget from there if you regenerate locally.

---

This pipeline converts your reference clips into game-ready replacement animations for the player model.

It is designed for this repo and outputs replacement GLBs that `PlayerVisual` already prioritizes:

- `art/characters/player/replacements/Base_Model_V01_Walking_Replacement.glb`
- `art/characters/player/replacements/Base_Model_V01_Attack_Replacement.glb`
- `art/characters/player/replacements/Base_Model_V01_Defend_Replacement.glb`

## What the pipeline does

1. Normalizes your example videos (`attackExample`, `walkingExample`, `defendexample`).
2. Converts staged videos into local mocap FBX clips (`attack.fbx`, `walk.fbx`, `defend.fbx`) using MediaPipe + Blender.
3. Retargets mocap data to your player rig in Blender via script.
4. Exports Godot-ready GLB replacement clips.

## Prerequisites

- Python 3.10+
- Blender (4.x recommended) available via CLI
- Python dependencies:

```powershell
python -m pip install -r .\tools\animation_pipeline\requirements_mocap.txt
```

If system-wide install is blocked:

```powershell
python -m pip install --user -r .\tools\animation_pipeline\requirements_mocap.txt
```

- First run auto-downloads `pose_landmarker_heavy.task` to:
  - `tools/animation_pipeline/models/pose_landmarker_heavy.task`

## One-command flow

Run from repo root.

1) Prepare example clips:

```powershell
.\tools\animation_pipeline\prepare_example_clips.ps1
```

2) Convert staged videos to mocap FBX locally:

```powershell
.\tools\animation_pipeline\convert_example_clips_to_mocap.ps1 -BlenderExe "C:\Program Files\Blender Foundation\Blender 4.2\blender.exe"
```

The converter auto-prefers V2 clip names when present:
- `AttackV2.mov` / `AttackV2.mp4` (fallback `attack.mov` / `attack.mp4`)
- `WalkingV2.mov` / `WalkingV2.mp4` (fallback `walk.mov` / `walk.mp4`)
- `DefendV2.mov` / `DefendV2.mp4` (fallback `defend.mov` / `defend.mp4`)

Generated files:
- `tools/animation_pipeline/work/mocap/attack.fbx`
- `tools/animation_pipeline/work/mocap/walk.fbx`
- `tools/animation_pipeline/work/mocap/defend.fbx`
- `tools/animation_pipeline/work/mocap/*.pose.json` (debug pose data)

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
- If you want to inspect mocap extraction quality before FBX export, run:

```powershell
python .\tools\animation_pipeline\video_to_mocap_fbx.py --input-video .\tools\animation_pipeline\work\videos\attack.mp4 --output-json .\tools\animation_pipeline\work\mocap\attack.pose.json --output-fbx .\tools\animation_pipeline\work\mocap\attack.fbx --skip-fbx
```
