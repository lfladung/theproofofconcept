#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def _resolve_ffmpeg() -> str:
    try:
        import imageio_ffmpeg  # type: ignore

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"


def _run(cmd: list[str]) -> None:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        print("Command failed:", " ".join(cmd))
        if proc.stdout:
            print(proc.stdout)
        if proc.stderr:
            print(proc.stderr)
        raise SystemExit(proc.returncode)


def _normalize_video(ffmpeg_exe: str, src: Path, dst: Path, fps: int) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        ffmpeg_exe,
        "-y",
        "-i",
        str(src),
        "-vf",
        f"fps={fps},scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p",
        "-an",
        str(dst),
    ]
    _run(cmd)


def _default_repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def main() -> None:
    parser = argparse.ArgumentParser(description="Prepare animation example clips for retarget pipeline.")
    parser.add_argument("--repo-root", type=Path, default=_default_repo_root())
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--attack-video", type=Path, default=Path.home() / "Videos" / "attackExample.mp4")
    parser.add_argument("--walk-video", type=Path, default=Path.home() / "Videos" / "walkingExample.mp4")
    parser.add_argument("--defend-video", type=Path, default=Path.home() / "Videos" / "defendexample.mp4")
    args = parser.parse_args()

    repo_root: Path = args.repo_root.resolve()
    work_dir = repo_root / "tools" / "animation_pipeline" / "work"
    videos_dir = work_dir / "videos"
    mocap_dir = work_dir / "mocap"
    videos_dir.mkdir(parents=True, exist_ok=True)
    mocap_dir.mkdir(parents=True, exist_ok=True)

    inputs = {
        "attack": args.attack_video,
        "walk": args.walk_video,
        "defend": args.defend_video,
    }
    for key, src in inputs.items():
        if not src.exists():
            print(f"Missing {key} source video: {src}")
            raise SystemExit(2)

    ffmpeg_exe = _resolve_ffmpeg()
    print(f"Using ffmpeg: {ffmpeg_exe}")

    normalized = {
        "attack": videos_dir / "attack.mp4",
        "walk": videos_dir / "walk.mp4",
        "defend": videos_dir / "defend.mp4",
    }
    for clip_id, src in inputs.items():
        dst = normalized[clip_id]
        print(f"Normalizing {clip_id}: {src} -> {dst}")
        _normalize_video(ffmpeg_exe, src.resolve(), dst, args.fps)

    manifest = {
        "clips": [
            {
                "id": "attack",
                "input_video": str(inputs["attack"].resolve()),
                "normalized_video": str(normalized["attack"].resolve()),
                "expected_mocap": str((mocap_dir / "attack.fbx").resolve()),
            },
            {
                "id": "walk",
                "input_video": str(inputs["walk"].resolve()),
                "normalized_video": str(normalized["walk"].resolve()),
                "expected_mocap": str((mocap_dir / "walk.fbx").resolve()),
            },
            {
                "id": "defend",
                "input_video": str(inputs["defend"].resolve()),
                "normalized_video": str(normalized["defend"].resolve()),
                "expected_mocap": str((mocap_dir / "defend.fbx").resolve()),
            },
        ]
    }
    manifest_path = work_dir / "clip_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    readme_path = mocap_dir / "README.txt"
    readme_path.write_text(
        "\n".join(
            [
                "Place converted mocap files here using these names:",
                "  attack.fbx",
                "  walk.fbx",
                "  defend.fbx",
                "",
                "Then run:",
                "  .\\tools\\animation_pipeline\\run_retarget_pipeline.ps1 -BlenderExe \"<path-to-blender.exe>\"",
            ]
        ),
        encoding="utf-8",
    )

    print(f"Wrote manifest: {manifest_path}")
    print("Next step:")
    print("1) Convert videos in tools/animation_pipeline/work/videos to mocap (FBX/BVH) with your preferred tool.")
    print("2) Save to tools/animation_pipeline/work/mocap as attack.fbx, walk.fbx, defend.fbx.")
    print("3) Run .\\tools\\animation_pipeline\\run_retarget_pipeline.ps1")


if __name__ == "__main__":
    main()
