#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import Any

import numpy as np

try:
    import cv2  # type: ignore
except ImportError as exc:
    raise SystemExit("Missing dependency 'opencv-python'. Install with: python -m pip install opencv-python") from exc

try:
    import mediapipe as mp  # type: ignore
except ImportError as exc:
    raise SystemExit("Missing dependency 'mediapipe'. Install with: python -m pip install mediapipe") from exc

from mediapipe.tasks import python as mp_python  # type: ignore
from mediapipe.tasks.python import vision as mp_vision  # type: ignore


POSE_MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
    "pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task"
)

MP_INDEX = {
    "NOSE": 0,
    "LEFT_EAR": 7,
    "RIGHT_EAR": 8,
    "LEFT_SHOULDER": 11,
    "RIGHT_SHOULDER": 12,
    "LEFT_ELBOW": 13,
    "RIGHT_ELBOW": 14,
    "LEFT_WRIST": 15,
    "RIGHT_WRIST": 16,
    "LEFT_PINKY": 17,
    "RIGHT_PINKY": 18,
    "LEFT_INDEX": 19,
    "RIGHT_INDEX": 20,
    "LEFT_THUMB": 21,
    "RIGHT_THUMB": 22,
    "LEFT_HIP": 23,
    "RIGHT_HIP": 24,
    "LEFT_KNEE": 25,
    "RIGHT_KNEE": 26,
    "LEFT_ANKLE": 27,
    "RIGHT_ANKLE": 28,
    "LEFT_HEEL": 29,
    "RIGHT_HEEL": 30,
    "LEFT_FOOT_INDEX": 31,
    "RIGHT_FOOT_INDEX": 32,
}

JOINT_ORDER = [
    "Hips",
    "Spine",
    "Chest",
    "Neck",
    "Head",
    "LeftShoulder",
    "LeftArm",
    "LeftForeArm",
    "LeftHand",
    "RightShoulder",
    "RightArm",
    "RightForeArm",
    "RightHand",
    "LeftUpLeg",
    "LeftLeg",
    "LeftFoot",
    "LeftToeBase",
    "RightUpLeg",
    "RightLeg",
    "RightFoot",
    "RightToeBase",
]


def _default_repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _default_blender_script(repo_root: Path) -> Path:
    return repo_root / "tools" / "animation_pipeline" / "mocap_json_to_fbx_blender.py"


def _default_pose_model(repo_root: Path) -> Path:
    return repo_root / "tools" / "animation_pipeline" / "models" / "pose_landmarker_heavy.task"


def _resolve_blender_exe(cli_value: str) -> str:
    if cli_value.strip():
        return cli_value.strip()
    env_value = os.environ.get("BLENDER_EXE", "").strip()
    if env_value:
        return env_value
    return "blender"


def _mp_to_blender(vec: np.ndarray) -> np.ndarray:
    # MediaPipe world landmarks are right-handed with Y down.
    # Convert to Blender-friendly up axis: X right, Y forward, Z up.
    return np.array([vec[0], -vec[2], -vec[1]], dtype=np.float32)


def _midpoint(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return (a + b) * 0.5


def _point(landmarks: list[Any], index: int) -> np.ndarray:
    lm = landmarks[index]
    return _mp_to_blender(np.array([lm.x, lm.y, lm.z], dtype=np.float32))


def _safe_normalize(vec: np.ndarray) -> np.ndarray:
    length = float(np.linalg.norm(vec))
    if length < 1e-6:
        return np.array([0.0, 0.0, 1.0], dtype=np.float32)
    return vec / length


def _extract_joint_frame(landmarks: list[Any]) -> dict[str, list[float]]:
    l_shoulder = _point(landmarks, MP_INDEX["LEFT_SHOULDER"])
    r_shoulder = _point(landmarks, MP_INDEX["RIGHT_SHOULDER"])
    l_elbow = _point(landmarks, MP_INDEX["LEFT_ELBOW"])
    r_elbow = _point(landmarks, MP_INDEX["RIGHT_ELBOW"])
    l_wrist = _point(landmarks, MP_INDEX["LEFT_WRIST"])
    r_wrist = _point(landmarks, MP_INDEX["RIGHT_WRIST"])
    l_hip = _point(landmarks, MP_INDEX["LEFT_HIP"])
    r_hip = _point(landmarks, MP_INDEX["RIGHT_HIP"])
    l_knee = _point(landmarks, MP_INDEX["LEFT_KNEE"])
    r_knee = _point(landmarks, MP_INDEX["RIGHT_KNEE"])
    l_ankle = _point(landmarks, MP_INDEX["LEFT_ANKLE"])
    r_ankle = _point(landmarks, MP_INDEX["RIGHT_ANKLE"])
    l_foot = _point(landmarks, MP_INDEX["LEFT_FOOT_INDEX"])
    r_foot = _point(landmarks, MP_INDEX["RIGHT_FOOT_INDEX"])

    hips = _midpoint(l_hip, r_hip)
    chest = _midpoint(l_shoulder, r_shoulder)
    spine = hips + (chest - hips) * 0.5
    nose = _point(landmarks, MP_INDEX["NOSE"])
    ear_mid = _midpoint(_point(landmarks, MP_INDEX["LEFT_EAR"]), _point(landmarks, MP_INDEX["RIGHT_EAR"]))
    head = nose * 0.7 + ear_mid * 0.3
    neck_dir = _safe_normalize(head - chest)
    neck = chest + neck_dir * 0.08

    l_hand = _midpoint(_point(landmarks, MP_INDEX["LEFT_INDEX"]), _point(landmarks, MP_INDEX["LEFT_THUMB"]))
    r_hand = _midpoint(_point(landmarks, MP_INDEX["RIGHT_INDEX"]), _point(landmarks, MP_INDEX["RIGHT_THUMB"]))

    joints = {
        "Hips": hips,
        "Spine": spine,
        "Chest": chest,
        "Neck": neck,
        "Head": head,
        "LeftShoulder": l_shoulder,
        "LeftArm": l_elbow,
        "LeftForeArm": l_wrist,
        "LeftHand": l_hand,
        "RightShoulder": r_shoulder,
        "RightArm": r_elbow,
        "RightForeArm": r_wrist,
        "RightHand": r_hand,
        "LeftUpLeg": l_hip,
        "LeftLeg": l_knee,
        "LeftFoot": l_ankle,
        "LeftToeBase": l_foot,
        "RightUpLeg": r_hip,
        "RightLeg": r_knee,
        "RightFoot": r_ankle,
        "RightToeBase": r_foot,
    }
    return {name: [float(v[0]), float(v[1]), float(v[2])] for name, v in joints.items()}


def _ensure_pose_model(model_path: Path) -> None:
    if model_path.exists():
        return
    model_path.parent.mkdir(parents=True, exist_ok=True)
    print(f"[mocap] downloading pose model -> {model_path}")
    urllib.request.urlretrieve(POSE_MODEL_URL, str(model_path))


def _create_landmarker(
    model_path: Path,
    min_detection_confidence: float,
    min_tracking_confidence: float,
) -> Any:
    base = mp_python.BaseOptions(model_asset_path=str(model_path))
    options = mp_vision.PoseLandmarkerOptions(
        base_options=base,
        running_mode=mp_vision.RunningMode.IMAGE,
        num_poses=1,
        min_pose_detection_confidence=float(min_detection_confidence),
        min_pose_presence_confidence=float(min_tracking_confidence),
        min_tracking_confidence=float(min_tracking_confidence),
        output_segmentation_masks=False,
    )
    return mp_vision.PoseLandmarker.create_from_options(options)


def _smooth_frames(frames: list[dict[str, Any]], alpha: float) -> list[dict[str, Any]]:
    if not frames:
        return frames
    clamped_alpha = max(0.0, min(1.0, alpha))
    smoothed: list[dict[str, Any]] = []
    prev: dict[str, np.ndarray] | None = None
    for frame in frames:
        joints = frame["joints"]
        current: dict[str, np.ndarray] = {
            name: np.array(value, dtype=np.float32) for name, value in joints.items() if name in JOINT_ORDER
        }
        if prev is None:
            merged = current
        else:
            merged = {}
            for name in JOINT_ORDER:
                cur = current.get(name, prev[name])
                merged[name] = prev[name] * (1.0 - clamped_alpha) + cur * clamped_alpha
        prev = merged
        smoothed.append(
            {
                "index": frame["index"],
                "joints": {name: [float(v[0]), float(v[1]), float(v[2])] for name, v in merged.items()},
            }
        )
    return smoothed


def _extract_pose_sequence(
    input_video: Path,
    pose_model: Path,
    sample_stride: int,
    min_detection_confidence: float,
    min_tracking_confidence: float,
) -> tuple[int, list[dict[str, Any]]]:
    cap = cv2.VideoCapture(str(input_video))
    if not cap.isOpened():
        raise SystemExit(f"Unable to open video: {input_video}")

    fps_raw = float(cap.get(cv2.CAP_PROP_FPS))
    fps = int(round(fps_raw)) if fps_raw > 0 else 30
    sample_stride = max(1, int(sample_stride))

    _ensure_pose_model(pose_model)
    detector = _create_landmarker(
        model_path=pose_model,
        min_detection_confidence=min_detection_confidence,
        min_tracking_confidence=min_tracking_confidence,
    )

    frames: list[dict[str, Any]] = []
    frame_index = 0
    sampled_index = 0
    last_good: dict[str, list[float]] | None = None

    while True:
        ok, frame = cap.read()
        if not ok:
            break
        if frame_index % sample_stride != 0:
            frame_index += 1
            continue
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = detector.detect(mp_image)
        joints: dict[str, list[float]] | None = None
        if result.pose_world_landmarks:
            landmarks = result.pose_world_landmarks[0]
            joints = _extract_joint_frame(landmarks)
            last_good = joints
        elif last_good is not None:
            joints = last_good

        if joints is not None:
            frames.append({"index": sampled_index, "joints": joints})
            sampled_index += 1
        frame_index += 1

    detector.close()
    cap.release()
    return fps, frames


def _run_blender_export(blender_exe: str, blender_script: Path, input_json: Path, output_fbx: Path, action_name: str) -> None:
    cmd = [
        blender_exe,
        "-b",
        "--python-exit-code",
        "1",
        "-P",
        str(blender_script),
        "--",
        "--input-json",
        str(input_json),
        "--output-fbx",
        str(output_fbx),
        "--action-name",
        str(action_name),
    ]
    print("[run]", " ".join(cmd))
    try:
        proc = subprocess.run(cmd)
    except FileNotFoundError as exc:
        raise SystemExit(
            f"Blender executable not found: {blender_exe}\n"
            "Pass --blender-exe <full-path-to-blender.exe> or set BLENDER_EXE."
        ) from exc
    if proc.returncode != 0:
        raise SystemExit(proc.returncode)


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert a video clip to a mocap FBX using MediaPipe + Blender.")
    parser.add_argument("--repo-root", type=Path, default=_default_repo_root())
    parser.add_argument("--input-video", type=Path, required=True)
    parser.add_argument("--output-json", type=Path, required=True)
    parser.add_argument("--output-fbx", type=Path, required=True)
    parser.add_argument("--action-name", default="MocapAction")
    parser.add_argument("--sample-stride", type=int, default=1)
    parser.add_argument("--smooth-alpha", type=float, default=0.4)
    parser.add_argument("--pose-model", type=Path, default=None)
    parser.add_argument("--min-detection-confidence", type=float, default=0.5)
    parser.add_argument("--min-tracking-confidence", type=float, default=0.5)
    parser.add_argument("--skip-fbx", action="store_true")
    parser.add_argument("--blender-exe", default="")
    parser.add_argument("--blender-script", type=Path, default=None)
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    input_video = args.input_video.resolve()
    output_json = args.output_json.resolve()
    output_fbx = args.output_fbx.resolve()
    pose_model = (args.pose_model.resolve() if args.pose_model else _default_pose_model(repo_root))
    blender_script = (args.blender_script.resolve() if args.blender_script else _default_blender_script(repo_root))
    blender_exe = _resolve_blender_exe(args.blender_exe)

    if not input_video.exists():
        raise SystemExit(f"Missing input video: {input_video}")

    fps, frames = _extract_pose_sequence(
        input_video=input_video,
        pose_model=pose_model,
        sample_stride=args.sample_stride,
        min_detection_confidence=args.min_detection_confidence,
        min_tracking_confidence=args.min_tracking_confidence,
    )
    if not frames:
        raise SystemExit(
            "No pose frames were detected. Try a clearer side/front view and ensure full body stays visible."
        )

    smoothed = _smooth_frames(frames, alpha=float(args.smooth_alpha))
    payload = {
        "source_video": str(input_video),
        "fps": fps,
        "joint_names": JOINT_ORDER,
        "frames": smoothed,
    }
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"[mocap] wrote pose json: {output_json} (frames={len(smoothed)}, fps={fps})")

    if args.skip_fbx:
        print("[mocap] skip-fbx enabled; JSON extraction complete.")
        return

    if not blender_script.exists():
        raise SystemExit(f"Missing blender script: {blender_script}")
    _run_blender_export(
        blender_exe=blender_exe,
        blender_script=blender_script,
        input_json=output_json,
        output_fbx=output_fbx,
        action_name=str(args.action_name),
    )
    print(f"[mocap] exported fbx: {output_fbx}")


if __name__ == "__main__":
    main()
