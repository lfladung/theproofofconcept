# One-Command Launchers

Run these from repo root (`C:\git\dungeonGame\dungeonGameConvertToMultplayer`).

## Start Session Allocator (Recommended)

```powershell
.\tools\start_dedicated_server.ps1
```

This starts the session allocator (registry + on-demand dedicated instance spawning).
Players can host/join using only session codes.

The dedicated launcher waits up to 30 seconds for registry health by default. Override if needed:

```powershell
.\tools\start_dedicated_server.ps1 -RegistryReadyTimeoutSeconds 60
```

Set allocator networking options:

```powershell
.\tools\start_dedicated_server.ps1 -RegistryUrl http://127.0.0.1:8787 -PublicHost 127.0.0.1 -Port 7000
```

To launch one fixed dedicated server manually (legacy/debug only):

```powershell
.\tools\start_dedicated_server.ps1 -LaunchBootstrapInstance:$true -Detached
```

Use desktop executable instead of console (not recommended for server runs):

```powershell
.\tools\start_dedicated_server.ps1 -UseDesktopExe
```

Default logs:
- Registry stdout (if auto-started): `logs\instance_registry.log`
- Registry stderr (if auto-started): `logs\instance_registry.log.err`
- Dedicated engine log: `logs\dedicated_server_engine.log`
- Dedicated gameplay log: `logs\dedicated_server.log`
- Spawned game instances: `logs\inst_*.log` and `logs\inst_*_engine.log`

## Start Player Client

```powershell
.\tools\start_player_client.ps1
```

## Tail Dedicated Gameplay Log

```powershell
.\tools\tail_dedicated_log.ps1
```

(Wait up to 30 seconds for log file creation)

```powershell
.\tools\tail_dedicated_log.ps1 -WaitTimeoutSeconds 30
```

## Tail Engine Log

```powershell
Get-Content .\logs\dedicated_server_engine.log -Wait
```

## Start Registry

```powershell
.\tools\start_registry.ps1
```

Normally not required anymore if you launch with `.\tools\start_dedicated_server.ps1`.

## Fast Lane Asset Pipeline

Pipeline docs and templates:

- `tools/asset_pipeline/FAST_LANE_PIPELINE.md`
- `tools/asset_pipeline/meshy_prompt_templates.md`
- `tools/asset_pipeline/asset_checklist.md`

Quick GLB audit commands:

```powershell
python tools/asset_pipeline/audit_glb.py --path art/characters/player/Base_Model_V01.glb
python tools/asset_pipeline/audit_glb.py --path art/equipment/weapons/Sword_texture.glb --category weapon --anchor art/characters/player/Base_Model_V01.glb
python tools/asset_pipeline/audit_glb.py --path art/equipment/weapons/Shield_texture.glb --category shield --anchor art/characters/player/Base_Model_V01.glb
```

## Animation Replacement Pipeline

Pipeline docs:

- `tools/animation_pipeline/README.md`

Prepare your example videos (normalizes and stages them):

```powershell
.\tools\animation_pipeline\prepare_example_clips.ps1
```

Install local mocap dependencies:

```powershell
python -m pip install -r .\tools\animation_pipeline\requirements_mocap.txt
```

If permissions block system install:

```powershell
python -m pip install --user -r .\tools\animation_pipeline\requirements_mocap.txt
```

Convert staged videos to mocap FBX locally:

```powershell
.\tools\animation_pipeline\convert_example_clips_to_mocap.ps1 -BlenderExe "C:\Program Files\Blender Foundation\Blender 4.2\blender.exe"
```

Then run retarget:

```powershell
.\tools\animation_pipeline\run_retarget_pipeline.ps1 -BlenderExe "C:\Program Files\Blender Foundation\Blender 4.2\blender.exe"
```

Force Godot to import generated replacement GLBs:

```powershell
.\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe --headless --path . --import
```

## Player Visual Auto-Capture

Generate one still frame for a mode (`idle`, `walk`, `attack`, `defend`):

```powershell
.\tools\capture_player_still.ps1 -Mode attack
```

Capture from a left-profile style angle:

```powershell
.\tools\capture_player_still.ps1 -Mode idle -CameraYaw -90 -CameraPitch -22 -CameraHeightOffset 0.8
```

Generate short walk/attack clips with Godot Movie Maker:

```powershell
.\tools\capture_player_clips.ps1 -Modes walk,attack -DurationSeconds 2.0 -CameraYaw -90 -CameraPitch -22 -CameraHeightOffset 0.8
```

Output folders:
- `logs\captures\stills`
- `logs\captures\videos`
