#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import bpy


def _argv_after_double_dash() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1 :]


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Retarget source mocap animation to target rig and export GLB.")
    parser.add_argument("--target-glb", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--output-glb", required=True)
    parser.add_argument("--action-name", default="RetargetedAction")
    parser.add_argument("--bone-map", default="")
    parser.add_argument("--root-bone", default="Hips")
    parser.add_argument("--root-motion-scale", type=float, default=1.0)
    parser.add_argument("--copy-root-location", action="store_true")
    parser.add_argument("--copy-root-rotation", action="store_true")
    parser.add_argument("--frame-start", type=int, default=1)
    parser.add_argument("--frame-end", type=int, default=-1)
    return parser.parse_args(_argv_after_double_dash())


def _norm_name(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())


def _clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for data_list in [
        bpy.data.actions,
        bpy.data.armatures,
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.images,
    ]:
        for item in list(data_list):
            if item.users == 0:
                data_list.remove(item)


def _new_objects(before_names: set[str]) -> list[bpy.types.Object]:
    return [obj for obj in bpy.context.scene.objects if obj.name not in before_names]


def _import_target(target_glb: Path) -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    before = {o.name for o in bpy.context.scene.objects}
    bpy.ops.import_scene.gltf(filepath=str(target_glb))
    imported = _new_objects(before)
    armatures = [o for o in imported if o.type == "ARMATURE"]
    if not armatures:
        raise RuntimeError(f"No armature found in target: {target_glb}")
    target = max(armatures, key=lambda a: len(a.data.bones))
    return target, imported


def _import_source(source_path: Path) -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    before = {o.name for o in bpy.context.scene.objects}
    ext = source_path.suffix.lower()
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(source_path), automatic_bone_orientation=True)
    elif ext in {".glb", ".gltf"}:
        bpy.ops.import_scene.gltf(filepath=str(source_path))
    elif ext == ".bvh":
        bpy.ops.import_anim.bvh(filepath=str(source_path), update_scene_fps=False, update_scene_duration=True)
    else:
        raise RuntimeError(f"Unsupported source extension: {ext}")
    imported = _new_objects(before)
    armatures = [o for o in imported if o.type == "ARMATURE"]
    if not armatures:
        raise RuntimeError(f"No armature found in source: {source_path}")
    source = max(armatures, key=lambda a: len(a.data.bones))
    return source, imported


def _load_bone_map(path: Path | None) -> dict[str, str]:
    if path is None or not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def _build_mapping(
    target_arm: bpy.types.Object, source_arm: bpy.types.Object, configured: dict[str, str]
) -> dict[str, str]:
    target_names = [b.name for b in target_arm.data.bones]
    source_names = [b.name for b in source_arm.data.bones]
    source_set = set(source_names)
    source_norm: dict[str, str] = {_norm_name(n): n for n in source_names}

    mapping: dict[str, str] = {}
    for tname in target_names:
        if tname in configured and configured[tname] in source_set:
            mapping[tname] = configured[tname]
            continue
        if tname in source_set:
            mapping[tname] = tname
            continue
        norm = _norm_name(tname)
        if norm in source_norm:
            mapping[tname] = source_norm[norm]
    return mapping


def _add_constraints(
    target_arm: bpy.types.Object,
    source_arm: bpy.types.Object,
    mapping: dict[str, str],
    root_bone: str,
    copy_root_location: bool,
    copy_root_rotation: bool,
) -> None:
    bpy.context.view_layer.objects.active = target_arm
    bpy.ops.object.mode_set(mode="POSE")
    root_norm = _norm_name(root_bone)
    for tname, sname in mapping.items():
        tb = target_arm.pose.bones.get(tname)
        sb = source_arm.pose.bones.get(sname)
        if tb is None or sb is None:
            continue
        is_root = _norm_name(tname) == root_norm
        if (not is_root) or copy_root_rotation:
            c_rot = tb.constraints.new(type="COPY_ROTATION")
            c_rot.target = source_arm
            c_rot.subtarget = sname
            c_rot.target_space = "WORLD"
            c_rot.owner_space = "WORLD"
        if is_root and copy_root_location:
            c_loc = tb.constraints.new(type="COPY_LOCATION")
            c_loc.target = source_arm
            c_loc.subtarget = sname
            c_loc.target_space = "WORLD"
            c_loc.owner_space = "WORLD"


def _frame_range_from_source(source_arm: bpy.types.Object, start_hint: int, end_hint: int) -> tuple[int, int]:
    if end_hint > 0 and end_hint >= start_hint:
        return start_hint, end_hint
    anim = source_arm.animation_data
    if anim and anim.action:
        frame_start = int(anim.action.frame_range[0])
        frame_end = int(anim.action.frame_range[1])
        return max(1, min(start_hint, frame_start)), max(frame_start + 1, frame_end)
    scene = bpy.context.scene
    return max(1, start_hint), max(start_hint + 1, scene.frame_end)


def _bake_to_target(target_arm: bpy.types.Object, frame_start: int, frame_end: int) -> bpy.types.Action:
    bpy.ops.object.mode_set(mode="POSE")
    bpy.context.view_layer.objects.active = target_arm
    bpy.ops.nla.bake(
        frame_start=frame_start,
        frame_end=frame_end,
        step=1,
        only_selected=False,
        visual_keying=True,
        clear_constraints=True,
        clear_parents=False,
        use_current_action=True,
        clean_curves=True,
        bake_types={"POSE"},
    )
    if target_arm.animation_data is None or target_arm.animation_data.action is None:
        raise RuntimeError("Bake failed: no action generated on target armature.")
    return target_arm.animation_data.action


def _scale_root_motion(action: bpy.types.Action, root_bone: str, scale: float) -> None:
    if abs(scale - 1.0) < 1e-6:
        return
    path = f'pose.bones["{root_bone}"].location'
    for fc in action.fcurves:
        if fc.data_path != path:
            continue
        for kp in fc.keyframe_points:
            kp.co[1] *= scale
            kp.handle_left[1] *= scale
            kp.handle_right[1] *= scale
        fc.update()


def _remove_objects(objects: list[bpy.types.Object]) -> None:
    for obj in objects:
        if obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)


def _keep_only_action(target_arm: bpy.types.Object, keep_action: bpy.types.Action) -> None:
    if target_arm.animation_data is None:
        target_arm.animation_data_create()
    target_arm.animation_data.action = keep_action
    # Clear any NLA strips that may reference imported source actions.
    if target_arm.animation_data is not None:
        for track in list(target_arm.animation_data.nla_tracks):
            target_arm.animation_data.nla_tracks.remove(track)
    # Retain only the baked action so Godot cannot accidentally pick a stale mocap clip.
    for action in list(bpy.data.actions):
        if action == keep_action:
            continue
        bpy.data.actions.remove(action, do_unlink=True)


def _export_glb(output_glb: Path) -> None:
    output_glb.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output_glb),
        export_format="GLB",
        use_selection=False,
        export_animations=True,
        export_nla_strips=False,
        export_force_sampling=True,
        export_skins=True,
        export_yup=True,
    )


def main() -> None:
    args = _parse_args()
    target_glb = Path(args.target_glb).resolve()
    source = Path(args.source).resolve()
    output_glb = Path(args.output_glb).resolve()
    bone_map = Path(args.bone_map).resolve() if args.bone_map else None

    if not target_glb.exists():
        raise SystemExit(f"Missing target_glb: {target_glb}")
    if not source.exists():
        raise SystemExit(f"Missing source mocap: {source}")

    _clear_scene()
    target_arm, _target_objs = _import_target(target_glb)
    source_arm, source_objs = _import_source(source)

    configured = _load_bone_map(bone_map)
    mapping = _build_mapping(target_arm, source_arm, configured)
    if not mapping:
        raise SystemExit("No bones mapped between source and target armatures.")

    print(f"[retarget] mapped bones: {len(mapping)}")
    _add_constraints(
        target_arm,
        source_arm,
        mapping,
        args.root_bone,
        copy_root_location=bool(args.copy_root_location),
        copy_root_rotation=bool(args.copy_root_rotation),
    )
    frame_start, frame_end = _frame_range_from_source(source_arm, args.frame_start, args.frame_end)
    print(f"[retarget] frame range: {frame_start} -> {frame_end}")
    action = _bake_to_target(target_arm, frame_start, frame_end)
    action.name = args.action_name
    _scale_root_motion(action, args.root_bone, args.root_motion_scale)

    _remove_objects(source_objs)
    _keep_only_action(target_arm, action)
    _export_glb(output_glb)
    print(f"[retarget] exported: {output_glb}")


if __name__ == "__main__":
    main()
