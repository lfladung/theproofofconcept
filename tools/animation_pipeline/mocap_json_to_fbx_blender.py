#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy
from mathutils import Quaternion, Vector


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

PARENT_BY_BONE: dict[str, str | None] = {
    "Hips": None,
    "Spine": "Hips",
    "Chest": "Spine",
    "Neck": "Chest",
    "Head": "Neck",
    "LeftShoulder": "Chest",
    "LeftArm": "LeftShoulder",
    "LeftForeArm": "LeftArm",
    "LeftHand": "LeftForeArm",
    "RightShoulder": "Chest",
    "RightArm": "RightShoulder",
    "RightForeArm": "RightArm",
    "RightHand": "RightForeArm",
    "LeftUpLeg": "Hips",
    "LeftLeg": "LeftUpLeg",
    "LeftFoot": "LeftLeg",
    "LeftToeBase": "LeftFoot",
    "RightUpLeg": "Hips",
    "RightLeg": "RightUpLeg",
    "RightFoot": "RightLeg",
    "RightToeBase": "RightFoot",
}

CHILD_AIM_BY_BONE: dict[str, str | None] = {
    "Hips": "Spine",
    "Spine": "Chest",
    "Chest": "Neck",
    "Neck": "Head",
    "Head": None,
    "LeftShoulder": "LeftArm",
    "LeftArm": "LeftForeArm",
    "LeftForeArm": "LeftHand",
    "LeftHand": None,
    "RightShoulder": "RightArm",
    "RightArm": "RightForeArm",
    "RightForeArm": "RightHand",
    "RightHand": None,
    "LeftUpLeg": "LeftLeg",
    "LeftLeg": "LeftFoot",
    "LeftFoot": "LeftToeBase",
    "LeftToeBase": None,
    "RightUpLeg": "RightLeg",
    "RightLeg": "RightFoot",
    "RightFoot": "RightToeBase",
    "RightToeBase": None,
}


def _argv_after_double_dash() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1 :]


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build an FBX mocap clip from extracted pose JSON.")
    parser.add_argument("--input-json", required=True)
    parser.add_argument("--output-fbx", required=True)
    parser.add_argument("--action-name", default="MocapAction")
    parser.add_argument("--armature-name", default="MocapArmature")
    parser.add_argument("--frame-start", type=int, default=1)
    return parser.parse_args(_argv_after_double_dash())


def _clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for data_list in [bpy.data.actions, bpy.data.armatures, bpy.data.meshes, bpy.data.materials]:
        for item in list(data_list):
            if item.users == 0:
                data_list.remove(item)


def _vec3(payload: dict[str, list[float]], key: str) -> Vector:
    value = payload.get(key)
    if value is None or len(value) != 3:
        return Vector((0.0, 0.0, 0.0))
    return Vector((float(value[0]), float(value[1]), float(value[2])))


def _safe_dir(start: Vector, end: Vector, fallback: Vector) -> Vector:
    direction = end - start
    if direction.length <= 1e-6:
        if fallback.length <= 1e-6:
            return Vector((0.0, 1.0, 0.0))
        return fallback.normalized()
    return direction.normalized()


def _create_armature(
    armature_name: str, rest_joints: dict[str, list[float]]
) -> tuple[bpy.types.Object, dict[str, Vector], dict[str, Vector]]:
    arm_data = bpy.data.armatures.new(f"{armature_name}Data")
    arm_obj = bpy.data.objects.new(armature_name, arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    arm_obj.select_set(True)

    bpy.ops.object.mode_set(mode="EDIT")
    edit_bones = arm_data.edit_bones
    created: dict[str, bpy.types.EditBone] = {}

    for bone_name in JOINT_ORDER:
        head = _vec3(rest_joints, bone_name)
        child_name = CHILD_AIM_BY_BONE.get(bone_name)
        if child_name:
            tail = _vec3(rest_joints, child_name)
        else:
            tail = head + Vector((0.0, 0.08, 0.0))
        if (tail - head).length <= 1e-4:
            tail = head + Vector((0.0, 0.08, 0.0))
        eb = edit_bones.new(bone_name)
        eb.head = head
        eb.tail = tail
        created[bone_name] = eb

    for bone_name, parent_name in PARENT_BY_BONE.items():
        if parent_name is None:
            continue
        created[bone_name].parent = created[parent_name]
        created[bone_name].use_connect = False

    rest_head: dict[str, Vector] = {}
    rest_dir: dict[str, Vector] = {}
    for bone_name in JOINT_ORDER:
        eb = created[bone_name]
        rest_head[bone_name] = eb.head.copy()
        rest_dir[bone_name] = (eb.tail - eb.head).normalized()

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj, rest_head, rest_dir


def _animate_armature(
    arm_obj: bpy.types.Object,
    frames: list[dict],
    rest_head: dict[str, Vector],
    rest_dir: dict[str, Vector],
    frame_start: int,
    action_name: str,
) -> None:
    scene = bpy.context.scene
    scene.frame_start = frame_start
    scene.frame_end = frame_start + max(1, len(frames) - 1)

    if arm_obj.animation_data is None:
        arm_obj.animation_data_create()
    action = bpy.data.actions.new(action_name)
    arm_obj.animation_data.action = action

    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    pose_bones = arm_obj.pose.bones

    for pb in pose_bones:
        pb.rotation_mode = "QUATERNION"

    track_axis = Vector((0.0, 1.0, 0.0))
    prev_local_quat: dict[str, Quaternion] = {}
    prev_root_location: Vector | None = None
    location_smooth = 0.35
    rotation_smooth = 0.45
    for i, frame_payload in enumerate(frames):
        joints = frame_payload.get("joints", {})
        frame_no = frame_start + i
        scene.frame_set(frame_no)

        root = pose_bones.get("Hips")
        if root is not None:
            hips = _vec3(joints, "Hips")
            root_local = hips - rest_head["Hips"]
            if prev_root_location is not None:
                root_local = prev_root_location.lerp(root_local, location_smooth)
            root.location = root_local
            prev_root_location = root_local.copy()
            root.keyframe_insert(data_path="location", frame=frame_no)

        for bone_name in JOINT_ORDER:
            pb = pose_bones.get(bone_name)
            if pb is None:
                continue
            head = _vec3(joints, bone_name)
            child_name = CHILD_AIM_BY_BONE.get(bone_name)
            if child_name:
                aim_target = _vec3(joints, child_name)
            else:
                aim_target = head + rest_dir[bone_name]
            direction = _safe_dir(head, aim_target, rest_dir[bone_name])
            world_q = track_axis.rotation_difference(direction)
            if pb.parent is not None:
                parent_world_q = pb.parent.matrix.to_quaternion()
                local_q = parent_world_q.inverted() @ world_q
            else:
                local_q = world_q
            prev_q: Quaternion | None = prev_local_quat.get(bone_name)
            if prev_q is not None:
                if local_q.dot(prev_q) < 0.0:
                    local_q = Quaternion((-local_q.w, -local_q.x, -local_q.y, -local_q.z))
                local_q = prev_q.slerp(local_q, rotation_smooth)
            pb.rotation_quaternion = local_q
            prev_local_quat[bone_name] = local_q.copy()
            pb.keyframe_insert(data_path="rotation_quaternion", frame=frame_no)

    if arm_obj.animation_data and arm_obj.animation_data.action:
        arm_obj.animation_data.action.name = action_name

    bpy.ops.object.mode_set(mode="OBJECT")


def _export_fbx(arm_obj: bpy.types.Object, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj

    bpy.ops.export_scene.fbx(
        filepath=str(output_path),
        use_selection=True,
        object_types={"ARMATURE"},
        bake_anim=True,
        bake_anim_use_all_bones=True,
        bake_anim_simplify_factor=0.0,
        add_leaf_bones=False,
        path_mode="AUTO",
        use_armature_deform_only=True,
    )


def main() -> None:
    args = _parse_args()
    input_json = Path(args.input_json).resolve()
    output_fbx = Path(args.output_fbx).resolve()

    if not input_json.exists():
        raise SystemExit(f"Missing input json: {input_json}")

    payload = json.loads(input_json.read_text(encoding="utf-8"))
    frames = payload.get("frames", [])
    if not frames:
        raise SystemExit("No frames found in mocap json.")

    fps = int(payload.get("fps", 30))
    bpy.context.scene.render.fps = max(1, fps)

    first = frames[0].get("joints", {})
    _clear_scene()
    arm_obj, rest_head, rest_dir = _create_armature(args.armature_name, first)
    _animate_armature(
        arm_obj=arm_obj,
        frames=frames,
        rest_head=rest_head,
        rest_dir=rest_dir,
        frame_start=max(1, int(args.frame_start)),
        action_name=args.action_name,
    )
    _export_fbx(arm_obj, output_fbx)
    print(f"[mocap] exported fbx: {output_fbx}")


if __name__ == "__main__":
    main()
