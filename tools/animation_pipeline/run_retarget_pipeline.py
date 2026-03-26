#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def _default_repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _default_config(repo_root: Path) -> Path:
    return repo_root / "tools" / "animation_pipeline" / "retarget_jobs.json"


def _resolve_blender_exe(cli_value: str | None) -> str:
    if cli_value and cli_value.strip():
        return cli_value.strip()
    env_value = os.environ.get("BLENDER_EXE", "").strip()
    if env_value:
        return env_value
    return "blender"


def _run(cmd: list[str], cwd: Path) -> None:
    print("[run]", " ".join(cmd))
    proc = subprocess.run(cmd, cwd=str(cwd))
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run full animation retarget pipeline via Blender.")
    parser.add_argument("--repo-root", type=Path, default=_default_repo_root())
    parser.add_argument("--config", type=Path, default=None)
    parser.add_argument("--blender-exe", default="")
    parser.add_argument("--root-bone", default="Hips")
    parser.add_argument("--root-motion-scale", type=float, default=1.0)
    args = parser.parse_args()

    repo_root: Path = args.repo_root.resolve()
    config_path = (args.config.resolve() if args.config else _default_config(repo_root))
    blender_exe = _resolve_blender_exe(args.blender_exe)
    blender_script = repo_root / "tools" / "animation_pipeline" / "retarget_in_blender.py"

    if not config_path.exists():
        raise SystemExit(f"Missing config: {config_path}")
    if not blender_script.exists():
        raise SystemExit(f"Missing blender script: {blender_script}")

    config = json.loads(config_path.read_text(encoding="utf-8"))
    target_glb = (repo_root / config["target_character_glb"]).resolve()
    if not target_glb.exists():
        raise SystemExit(f"Missing target character GLB: {target_glb}")

    global_bone_map = config.get("bone_map", "")
    clips = config.get("clips", [])
    if not clips:
        raise SystemExit("No clips found in config.")

    for clip in clips:
        clip_id = str(clip.get("id", "clip"))
        source = (repo_root / clip["source"]).resolve()
        output_glb = (repo_root / clip["output"]).resolve()
        action_name = clip.get("action_name", f"{clip_id}_Replacement")
        bone_map = clip.get("bone_map", global_bone_map)
        bone_map_abs = (repo_root / bone_map).resolve() if bone_map else None

        if not source.exists():
            raise SystemExit(
                f"Missing source mocap for '{clip_id}': {source}\n"
                "Generate/download mocap first into tools/animation_pipeline/work/mocap/"
            )
        if bone_map_abs is not None and not bone_map_abs.exists():
            raise SystemExit(f"Missing bone map for '{clip_id}': {bone_map_abs}")
        output_glb.parent.mkdir(parents=True, exist_ok=True)

        cmd = [
            blender_exe,
            "-b",
            "-P",
            str(blender_script),
            "--",
            "--target-glb",
            str(target_glb),
            "--source",
            str(source),
            "--output-glb",
            str(output_glb),
            "--action-name",
            str(action_name),
            "--root-bone",
            str(args.root_bone),
            "--root-motion-scale",
            str(args.root_motion_scale),
        ]
        if bone_map_abs is not None:
            cmd.extend(["--bone-map", str(bone_map_abs)])
        _run(cmd, cwd=repo_root)

    print("Retarget pipeline complete.")
    print("Next: run Godot import so replacement GLBs are available in engine cache.")
    print(r'.\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64_console.exe --headless --path . --import')


if __name__ == "__main__":
    main()
