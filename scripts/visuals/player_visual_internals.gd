@tool
extends Node3D

## Runtime/editor 3D player presentation: equipment, sword, animation, loadout visuals.
## Per-frame updates: `player_visual.gd`.


const LoadoutConstantsRef = preload("res://scripts/loadout/loadout_constants.gd")

enum EditorPreviewMode {
	RUNTIME_MATCH,
	T_POSE_SETUP,
	CUSTOM,
}

enum EditorAnimationPreview {
	IDLE,
	WALK,
	MELEE,
	RANGED,
	BOMB,
	DEFEND,
	DOWNED,
}

## Drives role-based animation clips (idle/run/melee/ranged/bomb/downed).
@export var preview_in_editor: bool = true
@export var editor_preview_mode: EditorPreviewMode = EditorPreviewMode.RUNTIME_MATCH
@export var editor_preview_animation: EditorAnimationPreview = EditorAnimationPreview.IDLE
@export var editor_preview_apply: bool = false
@export_range(0.1, 2.5, 0.05) var editor_preview_walk_speed_scale: float = 1.0
@export var editor_live_bone_follow: bool = true
@export var editor_t_pose_preview: bool = false
@export var editor_lock_current_placement_to_rig: bool = false
@export var persist_locked_offsets_to_exports: bool = true
@export var bake_current_offsets_to_rig_on_runtime_ready: bool = false
@export var sword_root_path: NodePath = NodePath("SwordAttachment")
@export var sword_offset_node_name: StringName = &"SwordOffset"
@export var sword_preserve_editor_offset: bool = false
@export var runtime_use_scene_authored_offsets: bool = false
@export var runtime_spawn_sword_if_missing: bool = false
@export var strict_hand_attachment: bool = true

# Sword attachment tuning.
# This is applied by programmatically attaching the sword to a bone inside the imported GLB skeleton,
# then toggling the whole `SwordAttachment` container via `set_sword_active()`.
@export var sword_mesh_path: String = "res://scenes/equipment/weapons/kaykit_sword_1handed.tscn"
@export var sword_bone_name_override: StringName = &"RightHand"
@export var sword_bone_keywords: Array[String] = ["hand", "weapon", "sword", "blade", "arm"]
@export var sword_local_offset: Vector3 = Vector3.ZERO
@export var sword_local_rotation_deg: Vector3 = Vector3.ZERO # Euler degrees
@export var sword_local_scale: Vector3 = Vector3(1.45, 1.45, 1.45)
@export var sword_use_state_offsets: bool = false
@export var sword_walk_offset_delta: Vector3 = Vector3.ZERO
@export var sword_walk_rotation_delta_deg: Vector3 = Vector3.ZERO
@export var sword_walk_scale_mult: Vector3 = Vector3.ONE
@export var sword_attack_use_motion_profile: bool = true
@export var sword_attack_windup_offset_delta: Vector3 = Vector3(-0.22, 0.05, -0.20)
@export var sword_attack_windup_rotation_delta_deg: Vector3 = Vector3(0.0, 52.0, 18.0)
@export var sword_attack_offset_delta: Vector3 = Vector3(0.30, -0.02, 0.30)
@export var sword_attack_rotation_delta_deg: Vector3 = Vector3(0.0, -74.0, -18.0)
@export var sword_attack_recover_offset_delta: Vector3 = Vector3(0.14, -0.06, 0.12)
@export var sword_attack_recover_rotation_delta_deg: Vector3 = Vector3(0.0, -28.0, -6.0)
@export var sword_attack_scale_mult: Vector3 = Vector3.ONE
@export var melee_smear_enabled: bool = true
@export var melee_smear_scene_path: String = "res://scenes/effects/melee_smear.tscn"
@export_range(0.0, 1.0, 0.01) var melee_smear_window_start: float = 0.16
@export_range(0.0, 1.0, 0.01) var melee_smear_window_end: float = 0.74
@export var melee_smear_local_offset: Vector3 = Vector3(0.86, 0.18, 0.0)
@export var melee_smear_local_rotation_deg: Vector3 = Vector3(0.0, 0.0, 104.0)
@export var melee_smear_base_scale: Vector3 = Vector3(1.45, 1.2, 1.1)
@export var melee_smear_peak_scale: Vector3 = Vector3(3.4, 1.95, 1.35)
@export var melee_smear_swing_offset: Vector3 = Vector3(1.05, -0.08, 0.0)
@export var melee_smear_rotation_sweep_deg: Vector3 = Vector3(0.0, 0.0, 74.0)
@export_range(0.0, 1.0, 0.01) var melee_smear_max_alpha: float = 1.0
@export var melee_smear_projectile_lifetime: float = 0.22
@export var melee_smear_projectile_travel_distance: float = 2.8
@export var melee_smear_projectile_spawn_scale: float = 1.8
@export var echo_melee_smear_scale_mult: float = 1.12
@export var echo_melee_smear_lifetime_mult: float = 1.2
@export var echo_melee_smear_travel_mult: float = 1.08
@export_range(0.0, 1.0, 0.01) var echo_melee_smear_max_alpha_mult: float = 0.92
@export var sword_force_visibility_material: bool = true
@export var equipment_force_visibility_material: bool = true
@export var sword_show_debug_proxy: bool = false
@export var sword_show_mode_beacon: bool = false
@export var sword_use_body_anchor_fallback: bool = false
@export var sword_body_anchor_local_position: Vector3 = Vector3(0.8, 1.5, 0.1)
@export var sword_body_anchor_local_rotation_deg: Vector3 = Vector3(0.0, 0.0, 90.0)
@export var sword_debug_log_visibility: bool = false
@export var sword_debug_print_bones: bool = false
@export var modular_equipment_enabled: bool = true
@export var equipment_legs_enabled: bool = false
@export var equipment_chest_root_path: NodePath = NodePath("ArmorAttachment")
@export var equipment_legs_root_path: NodePath = NodePath("LegsAttachment")
@export var equipment_helmet_root_path: NodePath = NodePath("HelmetAttachment")
@export var equipment_shield_root_path: NodePath = NodePath("ShieldAttachment")
@export var equipment_handgun_root_path: NodePath = NodePath("HandgunAttachment")
@export var equipment_bomb_root_path: NodePath = NodePath("BombAttachment")
@export var equipment_preserve_editor_offsets: bool = false
@export var runtime_spawn_equipment_if_missing: bool = false
@export var equipment_chest_scene_path: String = ""
@export var equipment_legs_scene_path: String = "res://scenes/equipment/armor/legs_v02.tscn"
@export var equipment_helmet_scene_path: String = ""
@export var equipment_shield_scene_path: String = "res://scenes/equipment/shields/kaykit_shield_round_color.tscn"
@export var equipment_handgun_scene_path: String = "res://scenes/equipment/weapons/handgun_1.tscn"
@export var equipment_bomb_scene_path: String = "res://scenes/equipment/bombs/bomb_round_placeholder.tscn"
@export var equipment_chest_bone_override: StringName = &"chest"
@export var equipment_legs_bone_override: StringName = &"Hips"
@export var equipment_helmet_bone_override: StringName = &"Head"
@export var equipment_helmet_rotation_bone_override: StringName = &"chest"
@export var equipment_helmet_yaw_only_follow: bool = true
@export var equipment_shield_bone_override: StringName = &"handslot.l"
@export var equipment_handgun_bone_override: StringName = &"handslot.r"
@export var equipment_bomb_bone_override: StringName = &"chest"
@export var equipment_chest_local_offset: Vector3 = Vector3(0.0, 0.04, 0.30)
@export var equipment_legs_local_offset: Vector3 = Vector3.ZERO
@export var equipment_helmet_local_offset: Vector3 = Vector3(0.0, 1.08, 0.08)
@export var equipment_shield_local_offset: Vector3 = Vector3(0.02, -0.08, 0.0)
@export var equipment_handgun_local_offset: Vector3 = Vector3(0.02, 0.0, 0.02)
@export var equipment_bomb_local_offset: Vector3 = Vector3(0.14, 0.08, -0.12)
@export var equipment_chest_local_rotation_deg: Vector3 = Vector3.ZERO
@export var equipment_legs_local_rotation_deg: Vector3 = Vector3.ZERO
@export var equipment_helmet_local_rotation_deg: Vector3 = Vector3.ZERO
@export var equipment_shield_local_rotation_deg: Vector3 = Vector3(0.0, 0.0, 90.0)
@export var equipment_handgun_local_rotation_deg: Vector3 = Vector3(28.0, 262.0, -18.0)
@export var equipment_bomb_local_rotation_deg: Vector3 = Vector3(0.0, 0.0, 0.0)
@export var equipment_chest_local_scale: Vector3 = Vector3(1.55, 1.55, 1.55)
@export var equipment_legs_local_scale: Vector3 = Vector3.ONE
@export var equipment_helmet_local_scale: Vector3 = Vector3(2.20, 2.20, 2.20)
@export var equipment_shield_local_scale: Vector3 = Vector3.ONE
@export var equipment_handgun_local_scale: Vector3 = Vector3(1.5, 1.5, 1.5)
@export var equipment_bomb_local_scale: Vector3 = Vector3(0.45, 0.45, 0.45)
@export var hide_base_head_when_helmet_equipped: bool = false
@export var hidden_head_bone_scale: Vector3 = Vector3(0.001, 0.001, 0.001)
@export var base_model_visor_detached_enabled: bool = true
@export var base_model_visor_root_path: NodePath = NodePath("BaseModelVisorAttachment")
@export var base_model_visor_bone_override: StringName = &"head"
@export var knight_default_texture_path: String = "res://art/characters/player/testing/knight_texture_green.png"
@export var knight_alternate_texture_path: String = "res://art/characters/player/testing/knight_texture.png"

@export var walk_speed_threshold := 8.0
@export var attack_duration_seconds := 1.0
@export var idle_clip_hint := "idle"
@export var run_clip_hint := "running"
@export var melee_clip_hint := "slice"
@export var ranged_clip_hint := "aim"
@export var bomb_clip_hint := "throw"
@export var defend_clip_hint := "block"
@export var downed_clip_hint := "death"

const _IDLE_GLB_CANDIDATES := [
	"res://art/characters/player/testing/animations/Idle_A.glb",
	"res://art/characters/player/Model_Idle_v2.glb",
	"res://art/characters/player/Model_Idle.glb",
	"res://art/characters/player/Base_Model_V01_Idle.glb",
]
const _BASE_MODEL_GLB_CANDIDATES := [
	"res://art/characters/player/testing/Knight.glb",
	"res://art/characters/player/Model_model.glb",
	"res://art/characters/player/Model_Idle_v2.glb",
	"res://art/characters/player/Model_Idle.glb",
	"res://art/characters/player/Base_Model_V01_rigged.glb",
	"res://art/characters/player/Base_Model_V01_Idle.glb",
	"res://art/characters/player/Base_Model_V01.glb",
]
const _BASE_MODEL_TPOSE_GLB_CANDIDATES := [
	"res://art/characters/player/testing/Knight.glb",
	"res://art/characters/player/Model_model.glb",
	"res://art/characters/player/Base_Model_V01.glb",
	"res://art/characters/player/Base_Model_V01_rigged.glb",
	"res://art/characters/player/Base_Model_V01_Idle.glb",
]
const _RUN_GLB_CANDIDATES := [
	"res://art/characters/player/testing/animations/Running_A.glb",
	"res://art/characters/player/Model_Running.glb",
	"res://art/characters/player/Base_Model_V01_Animation_Walking.glb",
	"res://art/characters/player/Base_Model_V01_Running.glb",
]
const _SLASH_GLB_CANDIDATES := [
	"res://art/characters/player/testing/animations/Melee_1H_Attack_Slice_Horizontal.glb",
	"res://art/characters/player/Attack_left_slash.glb",
	"res://art/characters/player/Model_Attack.glb",
	"res://art/characters/player/Base_Model_V01_Attack.glb",
]
const _RANGED_GLB_CANDIDATES := [
	"res://art/characters/player/testing/animations/Ranged_1H_Aiming.glb",
]
const _BOMB_GLB_CANDIDATES := [
	"res://art/characters/player/testing/animations/Throw_Bomb.glb",
]
const _DEFEND_GLB_CANDIDATES := [
	"res://art/characters/player/testing/animations/Melee_Blocking.glb",
	"res://art/characters/player/Model_Block.glb",
	"res://art/characters/player/Base_Model_V01_Block.glb",
]
const _DOWNED_GLB_CANDIDATES := [
	"res://art/characters/player/testing/animations/Death_A.glb",
	"res://art/characters/player/Model_Death.glb",
	"res://art/characters/player/Base_Model_V01_dying_backwards.glb",
]
const _EQUIPMENT_CHEST_BONE_KEYWORDS: Array[String] = ["spine", "chest", "upperchest", "torso"]
const _EQUIPMENT_LEGS_BONE_KEYWORDS: Array[String] = ["hips", "pelvis", "spine"]
const _EQUIPMENT_HELMET_BONE_KEYWORDS: Array[String] = ["head", "neck"]
const _EQUIPMENT_SHIELD_BONE_KEYWORDS: Array[String] = ["lefthand", "left_hand", "hand", "forearm", "arm"]
const _EQUIPMENT_HANDGUN_BONE_KEYWORDS: Array[String] = ["righthand", "right_hand", "hand", "weapon", "arm"]
const _EQUIPMENT_BOMB_BONE_KEYWORDS: Array[String] = ["spine", "chest", "torso", "back", "hips"]
const _BASE_MODEL_HELMET_VISOR_MESH_NAME: StringName = &"Knight_HelmetVisor"
const _BASE_MODEL_VISOR_FOLLOW_KEY: StringName = &"BaseModelVisor"
const _ANIMTREE_UPPER_BODY_BONES: Array[StringName] = [
	&"spine",
	&"chest",
	&"head",
	&"upperarm.l",
	&"lowerarm.l",
	&"hand.l",
	&"handslot.l",
	&"upperarm.r",
	&"lowerarm.r",
	&"hand.r",
	&"handslot.r",
]
const _ANIM_STATE_LOCOMOTION: StringName = &"Locomotion"
const _ANIM_STATE_ATTACK_MELEE: StringName = &"AttackMelee"
const _ANIM_STATE_ATTACK_RANGED: StringName = &"AttackRanged"
const _ANIM_STATE_ATTACK_BOMB: StringName = &"AttackBomb"
const _ANIM_STATE_DOWNED: StringName = &"Downed"
const _ANIM_LOCOMOTION_STATE_NAMES: Array[StringName] = [
	_ANIM_STATE_LOCOMOTION,
	_ANIM_STATE_ATTACK_MELEE,
	_ANIM_STATE_ATTACK_RANGED,
	_ANIM_STATE_ATTACK_BOMB,
]
const _ANIM_XFADE_FAST := 0.08
const _ANIM_XFADE_DOWNED := 0.03

var _anim: AnimationPlayer
var _anim_tree: AnimationTree
var _anim_state_playback: AnimationNodeStateMachinePlayback
var _attack_playing: bool = false
var _attack_nonce := 0
var _attack_profile_elapsed := 0.0
var _attack_profile_duration := 1.0
var _idle_clip: StringName = &""
var _run_clip: StringName = &""
var _melee_clip: StringName = &""
var _ranged_clip: StringName = &""
var _bomb_clip: StringName = &""
var _defend_clip: StringName = &""
var _downed_clip: StringName = &""
var _last_locomotion_moving := false
var _last_locomotion_speed_scale := 1.0
var _defending_hold_active := false
var _downed_hold_active := false
var _downed_play_nonce := 0

const CHARGE_BAR_FILL_SHADER := preload("res://shaders/charge_bar_fill.gdshader")

## World Y offset for the shared melee/ranged charge strip (world up).
const CHARGE_BAR_Y := -3.5

## Horizontal bar on the ground while charging; `set_melee_charge_progress(-1)` hides it.
var _melee_charge_bar_root: Node3D
var _melee_charge_fill_mi: MeshInstance3D
var _melee_charge_fill_shader_mat: ShaderMaterial
var _melee_charge_border_mi: MeshInstance3D
var _melee_charge_track_mi: MeshInstance3D

var _sword_root: Node3D
var _sword_mode_beacon: MeshInstance3D
var _sword_follow_skeleton: Skeleton3D
var _sword_follow_bone_idx: int = -1
var _sword_local_from_bone: Transform3D = Transform3D.IDENTITY
var _sword_offset_node: Node3D
var _sword_base_offset_position: Vector3 = Vector3.ZERO
var _sword_base_offset_rotation_deg: Vector3 = Vector3.ZERO
var _sword_base_offset_scale: Vector3 = Vector3.ONE
var _sword_base_offset_captured: bool = false
var _active_attack_mode: StringName = &""
var _melee_smear_spawned_attack_nonce: int = -1
var _queued_attack_planar_direction: Vector2 = Vector2.ZERO
var _equipment_follow_targets: Dictionary = {}
var _head_bone_original_scales: Dictionary = {}
var _head_hide_skeleton: Skeleton3D
var _head_hide_bone_indices: Array[int] = []
var _head_hide_active: bool = false
var _base_model_material_sources: Dictionary = {}
var _active_knight_texture_path: String = ""
var _helmet_equipped := true
var _sword_equipped := true
var _sword_active := true
var _handgun_equipped := true
var _handgun_active := false
var _anim_tree_skeleton_track_prefix := "Rig_Medium/Skeleton3D"
var _normalized_speed_ratio := 0.0


func _effective_editor_t_pose_preview() -> bool:
	if not Engine.is_editor_hint():
		return false
	match editor_preview_mode:
		EditorPreviewMode.RUNTIME_MATCH:
			return false
		EditorPreviewMode.T_POSE_SETUP:
			return true
		EditorPreviewMode.CUSTOM:
			return editor_t_pose_preview
	return editor_t_pose_preview


func _effective_editor_live_bone_follow() -> bool:
	if not Engine.is_editor_hint():
		return false
	match editor_preview_mode:
		EditorPreviewMode.RUNTIME_MATCH:
			return true
		EditorPreviewMode.T_POSE_SETUP:
			return true
		EditorPreviewMode.CUSTOM:
			return editor_live_bone_follow
	return editor_live_bone_follow


func _should_preserve_sword_offset() -> bool:
	if runtime_use_scene_authored_offsets:
		return true
	return sword_preserve_editor_offset


func _should_preserve_equipment_offsets() -> bool:
	if runtime_use_scene_authored_offsets:
		return true
	return equipment_preserve_editor_offsets


func _ready() -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	_ensure_preferred_base_model()
	_apply_knight_texture_for_armor_item(&"armor_brigandine")
	_setup_base_model_visor_attachment()
	_anim = _find_or_create_animation_player()
	if _anim:
		_anim.active = true
		_merge_anim_libraries_from_candidates(_IDLE_GLB_CANDIDATES, &"base_idle")
		_merge_anim_libraries_from_candidates(_RUN_GLB_CANDIDATES, &"base_run")
		_merge_anim_libraries_from_candidates(_SLASH_GLB_CANDIDATES, &"base_attack")
		_merge_anim_libraries_from_candidates(_RANGED_GLB_CANDIDATES, &"base_ranged")
		_merge_anim_libraries_from_candidates(_BOMB_GLB_CANDIDATES, &"base_bomb")
		_merge_anim_libraries_from_candidates(_DEFEND_GLB_CANDIDATES, &"base_defend")
		_merge_anim_libraries_from_candidates(_DOWNED_GLB_CANDIDATES, &"base_downed")
		_cache_role_clips()
		_setup_animation_tree()
		if not (Engine.is_editor_hint() and _effective_editor_t_pose_preview()):
			_play_locomotion(false, 1.0)
	_setup_modular_equipment()

	_sword_root = get_node_or_null(sword_root_path) as Node3D
	if _sword_root == null:
		_sword_root = get_node_or_null("SwordAttachment") as Node3D
	if _sword_root == null:
		if runtime_spawn_sword_if_missing:
			_sword_root = Node3D.new()
			_sword_root.name = "SwordAttachment"
			add_child(_sword_root)
			_mark_editor_owned(_sword_root)
		else:
			push_warning("[PlayerVisual] Missing SwordAttachment node. Add it to player_visual.tscn.")
			return
	if _sword_root:
		# Default visible until authoritative weapon sync arrives (initial spawn weapon is sword).
		_sword_root.visible = true
		_ensure_sword_mode_beacon()
		_setup_sword_attachment()
	if not Engine.is_editor_hint() and bake_current_offsets_to_rig_on_runtime_ready:
		_bake_current_offsets_to_rig()
	if Engine.is_editor_hint() and not _effective_editor_live_bone_follow():
		# Align once in editor, then let user move offset nodes without snapping.
		_update_sword_manual_bone_follow()
		_update_modular_equipment_bone_follow()


func _mark_editor_owned(node: Node) -> void:
	if node == null:
		return
	if Engine.is_editor_hint():
		node.owner = self


func set_sword_active(active: bool) -> void:
	# Toggles sword visibility. The sword is attached to the skeleton in `_setup_sword_attachment()`.
	if _sword_root == null or not is_instance_valid(_sword_root):
		return
	_sword_active = active
	_sword_root.visible = _sword_equipped and _sword_active
	if _sword_mode_beacon != null and is_instance_valid(_sword_mode_beacon):
		_sword_mode_beacon.visible = _sword_equipped and _sword_active
	if sword_debug_log_visibility and OS.is_debug_build():
		print("[PlayerVisual] set_sword_active=", active, " node=", _sword_root.get_path())


func set_handgun_active(active: bool) -> void:
	_handgun_active = active
	var handgun_root := _resolve_or_create_attachment_root(equipment_handgun_root_path, "HandgunAttachment")
	var editor_show := Engine.is_editor_hint() and preview_in_editor
	_apply_attachment_visibility(handgun_root, _handgun_equipped and (_handgun_active or editor_show))


func set_armor_visual_item(item_id: StringName) -> void:
	_apply_knight_texture_for_armor_item(item_id)


func set_attack_planar_direction(planar_direction: Vector2) -> void:
	if planar_direction.length_squared() <= 1e-6:
		_queued_attack_planar_direction = Vector2.ZERO
		return
	_queued_attack_planar_direction = planar_direction.normalized()


func _ensure_sword_mode_beacon() -> void:
	if not sword_show_mode_beacon:
		return
	if _sword_mode_beacon != null and is_instance_valid(_sword_mode_beacon):
		return
	var beacon := MeshInstance3D.new()
	beacon.name = "SwordModeBeacon"
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 1.2, 1.2)
	beacon.mesh = box
	beacon.position = Vector3(0.0, 5.0, 0.0)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.15, 1.0, 0.2, 1.0)
	beacon.material_override = mat
	beacon.visible = true
	add_child(beacon)
	_sword_mode_beacon = beacon


func _setup_sword_attachment() -> void:
	if _sword_root == null or not is_instance_valid(_sword_root):
		return

	var skeleton := _find_first_skeleton_3d(self)
	if skeleton == null:
		push_warning("[PlayerVisual] Could not find Skeleton3D for sword attachment.")
		return

	var chosen_bone := _choose_sword_bone_name(skeleton)
	if strict_hand_attachment:
		var right_hand_bone_name: StringName = _find_bone_name_case_insensitive(skeleton, "RightHand")
		if right_hand_bone_name != &"":
			chosen_bone = right_hand_bone_name
	if chosen_bone.is_empty():
		push_warning("[PlayerVisual] Could not choose a bone name for sword attachment.")
		return

	var bone_idx := skeleton.find_bone(String(chosen_bone))
	if bone_idx < 0:
		push_warning("[PlayerVisual] Bone '%s' was selected but not found on skeleton." % [String(chosen_bone)])
		return

	# Remove old BoneAttachment-based setups; we use manual follow for GLB reliability.
	var existing_attach := skeleton.get_node_or_null("SwordBoneAttachment")
	if existing_attach != null and is_instance_valid(existing_attach):
		existing_attach.queue_free()

	# Keep sword root attached to PlayerVisual; do not reparent in @tool mode (can drop scene ownership).
	if _sword_root.get_parent() == null:
		add_child(_sword_root)
		_mark_editor_owned(_sword_root)
	var follow_bone_world: Transform3D = _compute_bone_world_no_scale(skeleton, bone_idx)

	if sword_use_body_anchor_fallback:
		_sword_follow_skeleton = null
		_sword_follow_bone_idx = -1
		_sword_local_from_bone = Transform3D.IDENTITY
		_apply_sword_body_anchor_fallback()
	else:
		_sword_follow_skeleton = skeleton
		_sword_follow_bone_idx = bone_idx
		if strict_hand_attachment:
			_sword_local_from_bone = Transform3D.IDENTITY
		elif runtime_use_scene_authored_offsets or _should_preserve_sword_offset():
			_sword_local_from_bone = follow_bone_world.affine_inverse() * _sword_root.global_transform
		else:
			_sword_local_from_bone = Transform3D.IDENTITY

	var offset: Node3D = _sword_root.get_node_or_null(NodePath(String(sword_offset_node_name))) as Node3D
	if offset == null:
		offset = Node3D.new()
		offset.name = String(sword_offset_node_name)
		_apply_offset_transform(offset, sword_local_offset, sword_local_rotation_deg, sword_local_scale)
		_sword_root.add_child(offset)
		_mark_editor_owned(offset)
	elif not _should_preserve_sword_offset():
		_apply_offset_transform(offset, sword_local_offset, sword_local_rotation_deg, sword_local_scale)
	_sword_offset_node = offset
	_capture_sword_base_offset_from_node()
	_ensure_melee_smear()

	var sword_node: Node = offset.get_node_or_null("SwordMesh")
	if sword_node == null:
		sword_node = _find_first_node3d_child(offset)
	if sword_node == null and runtime_spawn_sword_if_missing and not sword_mesh_path.is_empty():
		var sword_res := load(sword_mesh_path)
		var sword_scene := sword_res as PackedScene
		if sword_scene != null:
			var spawned_sword: Node = sword_scene.instantiate()
			if spawned_sword != null:
				spawned_sword.name = "SwordMesh"
				offset.add_child(spawned_sword)
				_mark_editor_owned(spawned_sword)
				sword_node = spawned_sword
	if sword_node == null:
		push_warning("[PlayerVisual] Sword mesh node missing under SwordOffset. Add child node 'SwordMesh' in player_visual.tscn.")
		return

	if sword_show_debug_proxy and offset.get_node_or_null("SwordDebugProxy") == null:
		offset.add_child(_create_debug_sword_proxy())
	if sword_force_visibility_material:
		_apply_sword_visibility_material_override(sword_node)

	if sword_debug_print_bones:
		_print_skeleton_bones_debug(skeleton, chosen_bone)


func _ensure_melee_smear() -> void:
	var offset_root := _resolve_sword_offset_root()
	if offset_root == null:
		return
	var legacy_smear_root := offset_root.get_node_or_null("MeleeSmear") as Node3D
	if legacy_smear_root != null and is_instance_valid(legacy_smear_root):
		offset_root.remove_child(legacy_smear_root)
		legacy_smear_root.free()
	var spawned_smear_root := get_node_or_null("MeleeSmear") as Node3D
	if spawned_smear_root != null and is_instance_valid(spawned_smear_root):
		remove_child(spawned_smear_root)
		spawned_smear_root.queue_free()


func _update_melee_smear_projectile_spawn() -> void:
	var sword_offset_root := _resolve_sword_offset_root()
	if (
		not melee_smear_enabled
		or not _attack_playing
		or String(_active_attack_mode).to_lower() != "melee"
		or melee_smear_window_end <= melee_smear_window_start
	):
		return
	var t := _attack_profile_t()
	if t < melee_smear_window_start or t > melee_smear_window_end:
		return
	if _melee_smear_spawned_attack_nonce == _attack_nonce:
		return
	var spawn_parent := get_parent()
	if spawn_parent == null:
		return
	var smear_scene := load(melee_smear_scene_path) as PackedScene
	if smear_scene == null:
		push_warning("[PlayerVisual] Could not load melee smear scene '%s'." % melee_smear_scene_path)
		return
	var projectile := smear_scene.instantiate() as Node3D
	if projectile == null:
		push_warning("[PlayerVisual] Melee smear scene '%s' is not a Node3D." % melee_smear_scene_path)
		return
	spawn_parent.add_child(projectile)
	var travel_direction := Vector3.ZERO
	if sword_offset_root != null and is_instance_valid(sword_offset_root):
		travel_direction = sword_offset_root.global_transform.origin - global_transform.origin
		travel_direction.y = 0.0
	if travel_direction.length_squared() <= 1e-6:
		travel_direction = Vector3(
			_queued_attack_planar_direction.x,
			0.0,
			_queued_attack_planar_direction.y
		)
	if travel_direction.length_squared() <= 1e-6:
		travel_direction = -global_transform.basis.z
		travel_direction.y = 0.0
	if travel_direction.length_squared() <= 1e-6:
		travel_direction = Vector3.FORWARD
	var spawn_height := melee_smear_local_offset.y
	var smear_scale := melee_smear_base_scale * melee_smear_projectile_spawn_scale
	var smear_transform := Transform3D(
		Basis.IDENTITY.scaled(smear_scale),
		global_transform.origin + Vector3(0.0, spawn_height, 0.0)
	)
	if projectile.has_method(&"configure"):
		projectile.call(
			&"configure",
			smear_transform,
			travel_direction,
			melee_smear_projectile_lifetime,
			melee_smear_projectile_travel_distance,
			melee_smear_max_alpha
		)
	else:
		projectile.global_transform = smear_transform
	_melee_smear_spawned_attack_nonce = _attack_nonce
	_queued_attack_planar_direction = Vector2.ZERO


func spawn_echo_melee_smear(planar_direction: Vector2) -> void:
	if not melee_smear_enabled:
		return
	var spawn_parent := get_parent()
	if spawn_parent == null:
		return
	var dir2 := planar_direction
	if dir2.length_squared() <= 1e-6:
		dir2 = Vector2(_queued_attack_planar_direction.x, _queued_attack_planar_direction.y)
	if dir2.length_squared() <= 1e-6:
		dir2 = Vector2(global_transform.basis.z.x, global_transform.basis.z.z)
	if dir2.length_squared() <= 1e-6:
		dir2 = Vector2(0.0, -1.0)
	dir2 = dir2.normalized()
	var travel_direction := Vector3(dir2.x, 0.0, dir2.y)
	var smear_scene := load(melee_smear_scene_path) as PackedScene
	if smear_scene == null:
		push_warning("[PlayerVisual] Could not load melee smear scene '%s'." % melee_smear_scene_path)
		return
	var projectile := smear_scene.instantiate() as Node3D
	if projectile == null:
		push_warning("[PlayerVisual] Melee smear scene '%s' is not a Node3D." % melee_smear_scene_path)
		return
	spawn_parent.add_child(projectile)
	var spawn_height := melee_smear_local_offset.y
	var smear_scale := (
		melee_smear_base_scale * melee_smear_projectile_spawn_scale * echo_melee_smear_scale_mult
	)
	var smear_transform := Transform3D(
		Basis.IDENTITY.scaled(smear_scale),
		global_transform.origin + Vector3(0.0, spawn_height, 0.0)
	)
	var life := melee_smear_projectile_lifetime * echo_melee_smear_lifetime_mult
	var dist := melee_smear_projectile_travel_distance * echo_melee_smear_travel_mult
	var alpha := melee_smear_max_alpha * echo_melee_smear_max_alpha_mult
	if projectile.has_method(&"configure"):
		projectile.call(&"configure", smear_transform, travel_direction, life, dist, alpha)
	else:
		projectile.global_transform = smear_transform
	_apply_echo_smear_palette(projectile)


func _apply_echo_smear_palette(root: Node3D) -> void:
	if root == null:
		return
	var outer := Color(0.5, 0.32, 0.98, 1.0)
	var inner := Color(0.72, 0.58, 1.0, 1.0)
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			var mat := mi.material_override
			if mat is ShaderMaterial:
				var sm := mat as ShaderMaterial
				sm.set_shader_parameter(&"outer_color", outer)
				sm.set_shader_parameter(&"inner_color", inner)
				var am: Variant = sm.get_shader_parameter(&"alpha_multiplier")
				if typeof(am) == TYPE_FLOAT or typeof(am) == TYPE_INT:
					sm.set_shader_parameter(&"alpha_multiplier", float(am) * 1.12)
		for c in node.get_children():
			stack.append(c)


func _capture_sword_base_offset_from_node() -> void:
	if _sword_offset_node == null or not is_instance_valid(_sword_offset_node):
		_sword_base_offset_captured = false
		return
	_sword_base_offset_position = _sword_offset_node.position
	_sword_base_offset_rotation_deg = _sword_offset_node.rotation_degrees
	_sword_base_offset_scale = _sword_offset_node.scale
	_sword_base_offset_captured = true


func _apply_sword_state_offset_profile() -> void:
	if _sword_offset_node == null or not is_instance_valid(_sword_offset_node):
		return
	if Engine.is_editor_hint() and not _attack_playing and not _last_locomotion_moving:
		# In editor idle pose, treat manual gizmo edits as the authored base profile.
		_capture_sword_base_offset_from_node()
	if not _sword_base_offset_captured:
		_capture_sword_base_offset_from_node()
	if not _sword_base_offset_captured:
		return

	var target_pos: Vector3 = _sword_base_offset_position
	var target_rot_deg: Vector3 = _sword_base_offset_rotation_deg
	var target_scale: Vector3 = _sword_base_offset_scale
	if sword_use_state_offsets:
		if _attack_playing:
			var attack_offset_delta: Vector3 = sword_attack_offset_delta
			var attack_rotation_delta: Vector3 = sword_attack_rotation_delta_deg
			if sword_attack_use_motion_profile:
				var t: float = _attack_profile_t()
				attack_offset_delta = _sample_attack_profile_vec3(
					t,
					sword_attack_windup_offset_delta,
					sword_attack_offset_delta,
					sword_attack_recover_offset_delta
				)
				attack_rotation_delta = _sample_attack_profile_vec3(
					t,
					sword_attack_windup_rotation_delta_deg,
					sword_attack_rotation_delta_deg,
					sword_attack_recover_rotation_delta_deg
				)
			target_pos += attack_offset_delta
			target_rot_deg += attack_rotation_delta
			target_scale = Vector3(
				_sword_base_offset_scale.x * sword_attack_scale_mult.x,
				_sword_base_offset_scale.y * sword_attack_scale_mult.y,
				_sword_base_offset_scale.z * sword_attack_scale_mult.z
			)
		elif _last_locomotion_moving:
			target_pos += sword_walk_offset_delta
			target_rot_deg += sword_walk_rotation_delta_deg
			target_scale = Vector3(
				_sword_base_offset_scale.x * sword_walk_scale_mult.x,
				_sword_base_offset_scale.y * sword_walk_scale_mult.y,
				_sword_base_offset_scale.z * sword_walk_scale_mult.z
			)
	_apply_offset_transform(_sword_offset_node, target_pos, target_rot_deg, target_scale)


func _attack_profile_t() -> float:
	if _attack_profile_duration <= 0.0001:
		return 1.0
	return clampf(_attack_profile_elapsed / _attack_profile_duration, 0.0, 1.0)


func _sample_attack_profile_vec3(
	t: float, windup_delta: Vector3, swing_delta: Vector3, recover_delta: Vector3
) -> Vector3:
	if t <= 0.0:
		return Vector3.ZERO
	if t < 0.2:
		return Vector3.ZERO.lerp(windup_delta, smoothstep(0.0, 1.0, t / 0.2))
	if t < 0.55:
		return windup_delta.lerp(swing_delta, smoothstep(0.0, 1.0, (t - 0.2) / 0.35))
	if t < 0.85:
		return swing_delta.lerp(recover_delta, smoothstep(0.0, 1.0, (t - 0.55) / 0.30))
	return recover_delta.lerp(Vector3.ZERO, smoothstep(0.0, 1.0, (t - 0.85) / 0.15))


func _lock_current_placement_to_rig() -> void:
	# Bakes current t-pose placement into offset nodes, then binds roots to bones.
	_setup_modular_equipment()
	_setup_sword_attachment()
	_bake_current_offsets_to_rig()
	_update_sword_manual_bone_follow()
	_update_modular_equipment_bone_follow()


func _bake_current_offsets_to_rig() -> void:
	_lock_sword_offset_to_bone()
	_lock_equipment_offset_to_bone("Chest")
	if equipment_legs_enabled:
		_lock_equipment_offset_to_bone("Legs")
	_lock_equipment_offset_to_bone("Helmet")
	_lock_equipment_offset_to_bone("Shield")


func _lock_sword_offset_to_bone() -> void:
	if _sword_root == null or not is_instance_valid(_sword_root):
		return
	if _sword_follow_skeleton == null or not is_instance_valid(_sword_follow_skeleton):
		return
	if _sword_follow_bone_idx < 0 or _sword_follow_bone_idx >= _sword_follow_skeleton.get_bone_count():
		return
	var offset: Node3D = _sword_root.get_node_or_null(NodePath(String(sword_offset_node_name))) as Node3D
	if offset == null or not is_instance_valid(offset):
		return
	var desired_offset_world: Transform3D = offset.global_transform
	var bone_world: Transform3D = _compute_bone_world_no_scale(
		_sword_follow_skeleton, _sword_follow_bone_idx
	)
	_sword_local_from_bone = bone_world.affine_inverse() * _sword_root.global_transform
	var baked_local: Transform3D = _sword_root.global_transform.affine_inverse() * desired_offset_world
	var preserved_scale: Vector3 = offset.scale
	offset.transform = Transform3D(baked_local.basis.orthonormalized(), baked_local.origin)
	offset.scale = preserved_scale
	if persist_locked_offsets_to_exports:
		sword_local_offset = offset.position
		sword_local_rotation_deg = offset.rotation_degrees
		sword_local_scale = offset.scale


func _lock_equipment_offset_to_bone(slot_name: String) -> void:
	var record_v: Variant = _equipment_follow_targets.get(slot_name, null)
	if not (record_v is Dictionary):
		return
	var record: Dictionary = record_v as Dictionary
	var root_node: Node3D = record.get("root", null) as Node3D
	var skeleton: Skeleton3D = record.get("skeleton", null) as Skeleton3D
	var bone_idx: int = int(record.get("bone_idx", -1))
	if root_node == null or not is_instance_valid(root_node):
		return
	if skeleton == null or not is_instance_valid(skeleton):
		return
	if bone_idx < 0 or bone_idx >= skeleton.get_bone_count():
		return
	var offset_name: String = "%sOffset" % [slot_name]
	var offset_node: Node3D = root_node.get_node_or_null(NodePath(offset_name)) as Node3D
	if offset_node == null:
		offset_node = _find_first_node3d_child(root_node)
	if offset_node == null:
		return
	var desired_offset_world: Transform3D = offset_node.global_transform
	var bone_world: Transform3D = _compute_bone_world_no_scale(skeleton, bone_idx)
	var local_from_bone: Transform3D = bone_world.affine_inverse() * root_node.global_transform
	var root_world: Transform3D = bone_world * local_from_bone
	var baked_local: Transform3D = root_world.affine_inverse() * desired_offset_world
	var preserved_scale: Vector3 = offset_node.scale
	root_node.global_transform = root_world
	offset_node.transform = Transform3D(baked_local.basis.orthonormalized(), baked_local.origin)
	offset_node.scale = preserved_scale
	record["local_from_bone"] = local_from_bone
	_equipment_follow_targets[slot_name] = record
	if not persist_locked_offsets_to_exports:
		return
	match slot_name:
		"Chest":
			equipment_chest_local_offset = offset_node.position
			equipment_chest_local_rotation_deg = offset_node.rotation_degrees
			equipment_chest_local_scale = offset_node.scale
		"Legs":
			equipment_legs_local_offset = offset_node.position
			equipment_legs_local_rotation_deg = offset_node.rotation_degrees
			equipment_legs_local_scale = offset_node.scale
		"Helmet":
			equipment_helmet_local_offset = offset_node.position
			equipment_helmet_local_rotation_deg = offset_node.rotation_degrees
			equipment_helmet_local_scale = offset_node.scale
		"Shield":
			equipment_shield_local_offset = offset_node.position
			equipment_shield_local_rotation_deg = offset_node.rotation_degrees
			equipment_shield_local_scale = offset_node.scale


func _update_sword_manual_bone_follow() -> void:
	if _sword_root == null or not is_instance_valid(_sword_root):
		return
	if _sword_follow_bone_idx < 0:
		_apply_sword_body_anchor_fallback()
		return
	if _sword_follow_skeleton == null or not is_instance_valid(_sword_follow_skeleton):
		return
	if _sword_follow_bone_idx < 0 or _sword_follow_bone_idx >= _sword_follow_skeleton.get_bone_count():
		return
	var bone_world: Transform3D = _compute_bone_world_no_scale(
		_sword_follow_skeleton, _sword_follow_bone_idx
	)
	_sword_root.global_transform = bone_world * _sword_local_from_bone


func _apply_sword_body_anchor_fallback() -> void:
	if _sword_root == null or not is_instance_valid(_sword_root):
		return
	_sword_root.position = sword_body_anchor_local_position
	_sword_root.rotation = Vector3(
		deg_to_rad(sword_body_anchor_local_rotation_deg.x),
		deg_to_rad(sword_body_anchor_local_rotation_deg.y),
		deg_to_rad(sword_body_anchor_local_rotation_deg.z)
	)
	_sword_root.scale = Vector3.ONE


func _apply_sword_visibility_material_override(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var mesh: Mesh = mi.mesh
			if mesh != null:
				var surface_count: int = mesh.get_surface_count()
				for i in range(surface_count):
					var source_mat: Material = mi.get_surface_override_material(i)
					if source_mat == null:
						source_mat = mesh.surface_get_material(i)
					var visible_mat: Material = _build_sword_visible_material(source_mat)
					if visible_mat != null:
						mi.set_surface_override_material(i, visible_mat)
		for c in n.get_children():
			var child: Node = c
			stack.append(child)


func _build_sword_visible_material(source_mat: Material) -> Material:
	if source_mat != null and source_mat is BaseMaterial3D:
		var src: BaseMaterial3D = source_mat as BaseMaterial3D
		var visible_material: StandardMaterial3D = StandardMaterial3D.new()
		# Keep original albedo texture so the sword uses real art, but force visibility-safe flags.
		visible_material.albedo_texture = src.albedo_texture
		visible_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		visible_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		visible_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		visible_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		visible_material.no_depth_test = false
		visible_material.texture_filter = src.texture_filter
		visible_material.texture_repeat = src.texture_repeat
		visible_material.uv1_scale = src.uv1_scale
		visible_material.uv1_offset = src.uv1_offset
		return visible_material

	var fallback: StandardMaterial3D = StandardMaterial3D.new()
	fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fallback.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
	fallback.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	return fallback


func _apply_equipment_visibility_material_override(root: Node, slot_name: String) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var mesh: Mesh = mi.mesh
			if mesh != null:
				var surface_count: int = mesh.get_surface_count()
				for i in range(surface_count):
					var source_mat: Material = mi.get_surface_override_material(i)
					if source_mat == null:
						source_mat = mesh.surface_get_material(i)
					var visible_mat: Material = _build_equipment_visible_material(source_mat, slot_name)
					if visible_mat != null:
						mi.set_surface_override_material(i, visible_mat)
		for c in n.get_children():
			var child: Node = c
			stack.append(child)


func _build_equipment_visible_material(source_mat: Material, slot_name: String) -> Material:
	var tint: Color = Color(0.68, 0.74, 0.84, 1.0)
	if slot_name == "Helmet":
		tint = Color(0.92, 0.95, 1.0, 1.0)
	elif slot_name == "Chest":
		tint = Color(0.64, 0.70, 0.80, 1.0)
	elif slot_name == "Shield":
		tint = Color(0.78, 0.84, 0.98, 1.0)
	elif slot_name == "Handgun":
		tint = Color(0.30, 0.33, 0.38, 1.0)
	elif slot_name == "Bomb":
		tint = Color(0.84, 0.24, 0.16, 1.0)
	var visible_material: StandardMaterial3D = StandardMaterial3D.new()
	visible_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visible_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	visible_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if source_mat != null and source_mat is BaseMaterial3D:
		var src: BaseMaterial3D = source_mat as BaseMaterial3D
		tint = src.albedo_color
		if src.albedo_texture != null:
			visible_material.albedo_texture = src.albedo_texture
			tint = Color(1.0, 1.0, 1.0, 1.0)
		visible_material.texture_filter = src.texture_filter
		visible_material.texture_repeat = src.texture_repeat
		visible_material.uv1_scale = src.uv1_scale
		visible_material.uv1_offset = src.uv1_offset
	visible_material.albedo_color = tint
	visible_material.render_priority = 3
	if slot_name == "Helmet":
		# Helmet should respect depth/culling to avoid rendering the front while facing away.
		visible_material.cull_mode = BaseMaterial3D.CULL_BACK
		visible_material.no_depth_test = false
	return visible_material


func _create_debug_sword_proxy() -> MeshInstance3D:
	var proxy_mesh := MeshInstance3D.new()
	proxy_mesh.name = "SwordDebugProxy"
	var blade := BoxMesh.new()
	blade.size = Vector3(0.32, 3.2, 0.32)
	proxy_mesh.mesh = blade
	proxy_mesh.position = Vector3(0.0, 1.2, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.95, 1.0, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.albedo_color = Color(0.90, 0.98, 1.0, 1.0)
	proxy_mesh.material_override = mat
	return proxy_mesh


func _setup_modular_equipment() -> void:
	_equipment_follow_targets.clear()
	if not modular_equipment_enabled:
		return

	var skeleton: Skeleton3D = _find_first_skeleton_3d(self)
	if skeleton == null:
		push_warning("[PlayerVisual] Could not find Skeleton3D for modular equipment.")
		return

	_bind_or_spawn_modular_equipment_piece(
		"Chest",
		equipment_chest_root_path,
		"ArmorAttachment",
		"ChestOffset",
		equipment_chest_scene_path,
		skeleton,
		equipment_chest_bone_override,
		&"",
		_EQUIPMENT_CHEST_BONE_KEYWORDS,
		equipment_chest_local_offset,
		equipment_chest_local_rotation_deg,
		equipment_chest_local_scale
	)
	if equipment_legs_enabled:
		_bind_or_spawn_modular_equipment_piece(
			"Legs",
			equipment_legs_root_path,
			"LegsAttachment",
			"LegsOffset",
			equipment_legs_scene_path,
			skeleton,
			equipment_legs_bone_override,
			&"",
			_EQUIPMENT_LEGS_BONE_KEYWORDS,
			equipment_legs_local_offset,
			equipment_legs_local_rotation_deg,
			equipment_legs_local_scale
		)
	_bind_or_spawn_modular_equipment_piece(
		"Helmet",
		equipment_helmet_root_path,
		"HelmetAttachment",
		"HelmetOffset",
		equipment_helmet_scene_path,
		skeleton,
		equipment_helmet_bone_override,
		equipment_helmet_rotation_bone_override,
		_EQUIPMENT_HELMET_BONE_KEYWORDS,
		equipment_helmet_local_offset,
		equipment_helmet_local_rotation_deg,
		equipment_helmet_local_scale
	)
	_bind_or_spawn_modular_equipment_piece(
		"Shield",
		equipment_shield_root_path,
		"ShieldAttachment",
		"ShieldOffset",
		equipment_shield_scene_path,
		skeleton,
		equipment_shield_bone_override,
		&"",
		_EQUIPMENT_SHIELD_BONE_KEYWORDS,
		equipment_shield_local_offset,
		equipment_shield_local_rotation_deg,
		equipment_shield_local_scale
	)
	_ensure_dynamic_loadout_attachment(
		"Handgun",
		equipment_handgun_root_path,
		"HandgunAttachment",
		"HandgunOffset",
		equipment_handgun_bone_override,
		&"",
		_EQUIPMENT_HANDGUN_BONE_KEYWORDS,
		equipment_handgun_local_offset,
		equipment_handgun_local_rotation_deg,
		equipment_handgun_local_scale,
		equipment_handgun_scene_path
	)
	set_handgun_active(_handgun_active)
	_apply_head_hide_from_helmet_state(skeleton)


func apply_loadout_visuals(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	var equipped_slots_v: Variant = snapshot.get("equipped_slots", {})
	var definitions_v: Variant = snapshot.get("item_definitions", {})
	if equipped_slots_v is not Dictionary or definitions_v is not Dictionary:
		return
	var equipped_slots: Dictionary = equipped_slots_v as Dictionary
	var definitions_by_id: Dictionary = definitions_v as Dictionary
	var armor_item_id := StringName(String(equipped_slots.get(String(LoadoutConstantsRef.SLOT_ARMOR), "")))
	var sword_scene_path := _loadout_scene_path_for_slot(
		equipped_slots, definitions_by_id, LoadoutConstantsRef.SLOT_SWORD
	)
	var armor_scene_path := _loadout_scene_path_for_slot(
		equipped_slots, definitions_by_id, LoadoutConstantsRef.SLOT_ARMOR
	)
	var helmet_scene_path := _loadout_scene_path_for_slot(
		equipped_slots, definitions_by_id, LoadoutConstantsRef.SLOT_HELMET
	)
	var shield_scene_path := _loadout_scene_path_for_slot(
		equipped_slots, definitions_by_id, LoadoutConstantsRef.SLOT_SHIELD
	)
	var handgun_scene_path := _loadout_scene_path_for_slot(
		equipped_slots, definitions_by_id, LoadoutConstantsRef.SLOT_HANDGUN
	)
	_apply_knight_texture_for_armor_item(armor_item_id)

	_sword_equipped = not sword_scene_path.is_empty()
	_handgun_equipped = not handgun_scene_path.is_empty()
	_helmet_equipped = not helmet_scene_path.is_empty()
	_replace_attachment_child(_resolve_sword_offset_root(), "SwordMesh", sword_scene_path, true, "Sword")
	_apply_attachment_visibility(_sword_root, _sword_equipped and _sword_active)
	_apply_loadout_attachment_scene(
		equipment_chest_root_path,
		"ArmorAttachment",
		"ChestOffset",
		"EquipmentChestMesh",
		armor_scene_path,
		equipment_chest_local_offset,
		equipment_chest_local_rotation_deg,
		equipment_chest_local_scale,
		"Chest"
	)
	_apply_loadout_attachment_scene(
		equipment_helmet_root_path,
		"HelmetAttachment",
		"HelmetOffset",
		"EquipmentHelmetMesh",
		helmet_scene_path,
		equipment_helmet_local_offset,
		equipment_helmet_local_rotation_deg,
		equipment_helmet_local_scale,
		"Helmet"
	)
	_apply_loadout_attachment_scene(
		equipment_shield_root_path,
		"ShieldAttachment",
		"ShieldOffset",
		"EquipmentShieldMesh",
		shield_scene_path,
		equipment_shield_local_offset,
		equipment_shield_local_rotation_deg,
		equipment_shield_local_scale,
		"Shield"
	)
	_ensure_dynamic_loadout_attachment(
		"Handgun",
		equipment_handgun_root_path,
		"HandgunAttachment",
		"HandgunOffset",
		equipment_handgun_bone_override,
		&"",
		_EQUIPMENT_HANDGUN_BONE_KEYWORDS,
		equipment_handgun_local_offset,
		equipment_handgun_local_rotation_deg,
		equipment_handgun_local_scale,
		handgun_scene_path
	)
	set_handgun_active(_handgun_active)
	_ensure_dynamic_loadout_attachment(
		"Bomb",
		equipment_bomb_root_path,
		"BombAttachment",
		"BombOffset",
		equipment_bomb_bone_override,
		&"",
		_EQUIPMENT_BOMB_BONE_KEYWORDS,
		equipment_bomb_local_offset,
		equipment_bomb_local_rotation_deg,
		equipment_bomb_local_scale,
		""
	)
	_apply_attachment_visibility(
		_resolve_or_create_attachment_root(equipment_bomb_root_path, "BombAttachment"),
		false
	)
	_apply_head_hide_from_helmet_state(_find_first_skeleton_3d(self))
	_enforce_head_hide_pose()
	_update_sword_manual_bone_follow()
	_update_modular_equipment_bone_follow()


func _loadout_scene_path_for_slot(
	equipped_slots: Dictionary, definitions_by_id: Dictionary, slot_id: StringName
) -> String:
	var item_id := String(equipped_slots.get(String(slot_id), ""))
	if item_id.is_empty():
		return ""
	var definition_v: Variant = definitions_by_id.get(item_id, {})
	if definition_v is not Dictionary:
		return ""
	var visual_v: Variant = (definition_v as Dictionary).get("visual", {})
	if visual_v is not Dictionary:
		return ""
	return String((visual_v as Dictionary).get("equipment_scene_path", ""))


func _apply_loadout_attachment_scene(
	root_path: NodePath,
	root_fallback_name: String,
	offset_name: String,
	child_name: String,
	scene_path: String,
	local_offset: Vector3,
	local_rotation_deg: Vector3,
	local_scale: Vector3,
	slot_name: String
) -> void:
	var attachment_root: Node3D = _resolve_or_create_attachment_root(root_path, root_fallback_name)
	if attachment_root == null:
		return
	var offset_root: Node3D = _resolve_or_create_offset_root(
		attachment_root, offset_name, local_offset, local_rotation_deg, local_scale
	)
	if offset_root == null:
		return
	_replace_attachment_child(offset_root, child_name, scene_path, false, slot_name)
	_apply_attachment_visibility(attachment_root, not scene_path.is_empty())


func _ensure_dynamic_loadout_attachment(
	slot_name: String,
	root_path: NodePath,
	root_fallback_name: String,
	offset_name: String,
	bone_name_override: StringName,
	rotation_bone_name_override: StringName,
	bone_keywords: Array[String],
	local_offset: Vector3,
	local_rotation_deg: Vector3,
	local_scale: Vector3,
	scene_path: String
) -> void:
	var skeleton := _find_first_skeleton_3d(self)
	if skeleton == null:
		return
	var force_identity_follow := slot_name == "Handgun"
	if not _equipment_follow_targets.has(slot_name):
		var created_attachment_root: Node3D = _resolve_or_create_attachment_root(root_path, root_fallback_name)
		var created_offset_root: Node3D = _resolve_or_create_offset_root(
			created_attachment_root, offset_name, local_offset, local_rotation_deg, local_scale
		)
		if created_offset_root == null:
			return
		var bone_idx := _resolve_equipment_bone_idx(skeleton, bone_name_override, bone_keywords)
		if bone_idx < 0:
			return
		var rotation_bone_idx := bone_idx
		if rotation_bone_name_override != &"":
			var explicit_rotation_idx: int = skeleton.find_bone(String(rotation_bone_name_override))
			if explicit_rotation_idx >= 0:
				rotation_bone_idx = explicit_rotation_idx
		_equipment_follow_targets[slot_name] = {
			"root": created_attachment_root,
			"skeleton": skeleton,
			"bone_idx": bone_idx,
			"rotation_bone_idx": rotation_bone_idx,
			"yaw_only_follow": false,
			"local_from_bone": (
				Transform3D.IDENTITY
				if force_identity_follow
				else _compute_equipment_anchor_world(
					skeleton,
					bone_idx,
					rotation_bone_idx,
					false
				).affine_inverse() * created_attachment_root.global_transform
			),
		}
	elif force_identity_follow:
		var handgun_record := (_equipment_follow_targets.get(slot_name, {}) as Dictionary).duplicate(true)
		handgun_record["local_from_bone"] = Transform3D.IDENTITY
		_equipment_follow_targets[slot_name] = handgun_record
	var attachment_root_v: Variant = (_equipment_follow_targets.get(slot_name, {}) as Dictionary).get(
		"root",
		null
	)
	var attachment_root: Node3D = attachment_root_v as Node3D
	if attachment_root == null:
		return
	var offset_root: Node3D = _resolve_or_create_offset_root(
		attachment_root, offset_name, local_offset, local_rotation_deg, local_scale
	)
	if offset_root == null:
		return
	_replace_attachment_child(offset_root, "%sMesh" % [slot_name], scene_path, false, slot_name)
	_apply_attachment_visibility(attachment_root, not scene_path.is_empty())


func _resolve_sword_offset_root() -> Node3D:
	if _sword_root == null or not is_instance_valid(_sword_root):
		_sword_root = _resolve_or_create_attachment_root(sword_root_path, "SwordAttachment")
	if _sword_root == null:
		return null
	var offset: Node3D = _sword_root.get_node_or_null(NodePath(String(sword_offset_node_name))) as Node3D
	if offset != null and is_instance_valid(offset):
		return offset
	offset = Node3D.new()
	offset.name = String(sword_offset_node_name)
	_apply_offset_transform(offset, sword_local_offset, sword_local_rotation_deg, sword_local_scale)
	_sword_root.add_child(offset)
	_mark_editor_owned(offset)
	_sword_offset_node = offset
	_capture_sword_base_offset_from_node()
	return offset


func _replace_attachment_child(
	offset_root: Node3D, child_name: String, scene_path: String, use_sword_material: bool, slot_name: String
) -> void:
	if offset_root == null:
		return
	var existing_children: Array[Node3D] = []
	var matching_child: Node3D
	for child_v in offset_root.get_children():
		if child_v is not Node3D:
			continue
		var child := child_v as Node3D
		existing_children.append(child)
		if child.name == child_name:
			matching_child = child
	if matching_child != null and is_instance_valid(matching_child):
		var existing_path := String(matching_child.get_meta(&"loadout_scene_path", ""))
		var authored_scene_path := String(matching_child.scene_file_path)
		if existing_path == scene_path and existing_children.size() == 1:
			return
		if authored_scene_path == scene_path and existing_children.size() == 1:
			matching_child.set_meta(&"loadout_scene_path", scene_path)
			return
	for existing in existing_children:
		if existing == null or not is_instance_valid(existing):
			continue
		offset_root.remove_child(existing)
		existing.free()
	if scene_path.is_empty():
		return
	var scene_res := load(scene_path) as PackedScene
	if scene_res == null:
		push_warning("[PlayerVisual] Could not load loadout scene '%s' for %s." % [scene_path, slot_name])
		return
	var scene_instance := scene_res.instantiate() as Node3D
	if scene_instance == null:
		push_warning("[PlayerVisual] Loadout scene '%s' is not a Node3D for %s." % [scene_path, slot_name])
		return
	scene_instance.name = child_name
	scene_instance.set_meta(&"loadout_scene_path", scene_path)
	offset_root.add_child(scene_instance)
	_mark_editor_owned(scene_instance)
	if use_sword_material and sword_force_visibility_material:
		_apply_sword_visibility_material_override(scene_instance)
	elif equipment_force_visibility_material:
		_apply_equipment_visibility_material_override(scene_instance, slot_name)


func _apply_attachment_visibility(root: Node3D, is_visible: bool) -> void:
	if root == null or not is_instance_valid(root):
		return
	root.visible = is_visible


func _find_bone_idx_case_insensitive(skeleton: Skeleton3D, target_name: String) -> int:
	if skeleton == null or target_name.is_empty():
		return -1
	var target_lower: String = target_name.to_lower()
	for i in range(skeleton.get_bone_count()):
		var bone_name: String = String(skeleton.get_bone_name(i)).to_lower()
		if bone_name == target_lower:
			return i
	return -1


func _find_bone_name_case_insensitive(skeleton: Skeleton3D, target_name: String) -> StringName:
	var idx: int = _find_bone_idx_case_insensitive(skeleton, target_name)
	if idx < 0:
		return &""
	return skeleton.get_bone_name(idx)


func _apply_head_hide_from_helmet_state(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	var should_hide_head: bool = (
		hide_base_head_when_helmet_equipped and modular_equipment_enabled and _helmet_equipped
	)
	# Keep the white base head hidden whenever this feature is enabled.
	_head_hide_skeleton = skeleton
	_head_hide_bone_indices.clear()
	_head_hide_active = should_hide_head

	var head_bones: Array[String] = ["Head", "head_end", "headfront", "neck"]
	for bone_name in head_bones:
		var idx: int = _find_bone_idx_case_insensitive(skeleton, bone_name)
		if idx < 0:
			continue
		_head_hide_bone_indices.append(idx)
		var key: String = str(idx)
		if not _head_bone_original_scales.has(key):
			_head_bone_original_scales[key] = skeleton.get_bone_pose_scale(idx)
		if should_hide_head:
			skeleton.set_bone_pose_scale(idx, hidden_head_bone_scale)
		else:
			var restore_scale_v: Variant = _head_bone_original_scales.get(key, Vector3.ONE)
			var restore_scale: Vector3 = (
				restore_scale_v as Vector3 if restore_scale_v is Vector3 else Vector3.ONE
			)
			skeleton.set_bone_pose_scale(idx, restore_scale)


func _enforce_head_hide_pose() -> void:
	if not _head_hide_active:
		return
	if _head_hide_skeleton == null or not is_instance_valid(_head_hide_skeleton):
		return
	if _head_hide_bone_indices.is_empty():
		return
	for idx in _head_hide_bone_indices:
		if idx < 0 or idx >= _head_hide_skeleton.get_bone_count():
			continue
		_head_hide_skeleton.set_bone_pose_scale(idx, hidden_head_bone_scale)


func _setup_base_model_visor_attachment() -> void:
	var meshy := get_node_or_null("Meshy")
	if meshy == null:
		return
	var source_visor := _find_base_model_visor_source_mesh(meshy)
	if source_visor == null:
		return
	var attachment_root := _resolve_or_create_attachment_root(
		base_model_visor_root_path, "BaseModelVisorAttachment"
	)
	if attachment_root == null:
		return
	var offset_root := attachment_root.get_node_or_null("BaseModelVisorOffset") as Node3D
	if offset_root == null:
		offset_root = Node3D.new()
		offset_root.name = "BaseModelVisorOffset"
		attachment_root.add_child(offset_root)
		_mark_editor_owned(offset_root)

	if not base_model_visor_detached_enabled:
		source_visor.visible = true
		attachment_root.visible = false
		_equipment_follow_targets.erase(_BASE_MODEL_VISOR_FOLLOW_KEY)
		return

	var skeleton := _find_first_skeleton_3d(meshy)
	if skeleton == null:
		return
	var visor_bone_idx := _resolve_equipment_bone_idx(
		skeleton, base_model_visor_bone_override, _EQUIPMENT_HELMET_BONE_KEYWORDS
	)
	if visor_bone_idx < 0:
		push_warning("[PlayerVisual] Could not resolve visor bone for detached base visor.")
		return

	var anchor_world := _compute_equipment_anchor_world(skeleton, visor_bone_idx, visor_bone_idx, false)
	attachment_root.visible = true
	attachment_root.global_transform = anchor_world
	if offset_root.transform.is_equal_approx(Transform3D.IDENTITY):
		offset_root.transform = anchor_world.affine_inverse() * source_visor.global_transform
	_sync_detached_base_model_visor_mesh(source_visor, skeleton, offset_root)
	source_visor.visible = false
	_equipment_follow_targets[_BASE_MODEL_VISOR_FOLLOW_KEY] = {
		"root": attachment_root,
		"skeleton": skeleton,
		"bone_idx": visor_bone_idx,
		"rotation_bone_idx": visor_bone_idx,
		"yaw_only_follow": false,
		"local_from_bone": Transform3D.IDENTITY,
	}


func _find_base_model_visor_source_mesh(root: Node) -> MeshInstance3D:
	if root == null:
		return null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and node.name == _BASE_MODEL_HELMET_VISOR_MESH_NAME:
			return node as MeshInstance3D
		for child in node.get_children():
			stack.append(child)
	return null


func _sync_detached_base_model_visor_mesh(
	source_visor: MeshInstance3D, skeleton: Skeleton3D, offset_root: Node3D
) -> void:
	if source_visor == null or skeleton == null or offset_root == null:
		return
	var visor_mesh := offset_root.get_node_or_null("BaseModelVisorMesh") as MeshInstance3D
	if visor_mesh == null:
		visor_mesh = source_visor.duplicate() as MeshInstance3D
		if visor_mesh == null:
			return
		visor_mesh.name = "BaseModelVisorMesh"
		offset_root.add_child(visor_mesh)
		_mark_editor_owned(visor_mesh)
	visor_mesh.transform = Transform3D.IDENTITY
	visor_mesh.visible = true
	visor_mesh.skin = source_visor.skin
	visor_mesh.skeleton = visor_mesh.get_path_to(skeleton)


func _resolve_or_create_attachment_root(path: NodePath, fallback_name: String) -> Node3D:
	var existing: Node3D = get_node_or_null(path) as Node3D
	if existing != null and is_instance_valid(existing):
		return existing
	var root := Node3D.new()
	root.name = fallback_name
	add_child(root)
	return root


func _resolve_or_create_offset_root(
	attachment_root: Node3D,
	offset_name: String,
	local_offset: Vector3,
	local_rotation_deg: Vector3,
	local_scale: Vector3
) -> Node3D:
	if attachment_root == null:
		return null
	var existing_offset: Node3D = attachment_root.get_node_or_null(NodePath(offset_name)) as Node3D
	if existing_offset != null and is_instance_valid(existing_offset):
		if not _should_preserve_equipment_offsets():
			_apply_offset_transform(
				existing_offset, local_offset, local_rotation_deg, local_scale
			)
		return existing_offset
	var local_offset_root: Node3D = Node3D.new()
	local_offset_root.name = offset_name
	_apply_offset_transform(local_offset_root, local_offset, local_rotation_deg, local_scale)
	attachment_root.add_child(local_offset_root)
	return local_offset_root


func _apply_offset_transform(
	node: Node3D, local_offset: Vector3, local_rotation_deg: Vector3, local_scale: Vector3
) -> void:
	if node == null:
		return
	node.position = local_offset
	node.rotation = Vector3(
		deg_to_rad(local_rotation_deg.x),
		deg_to_rad(local_rotation_deg.y),
		deg_to_rad(local_rotation_deg.z)
	)
	node.scale = local_scale


func _local_transform_from_offset(
	local_offset: Vector3, local_rotation_deg: Vector3, local_scale: Vector3
) -> Transform3D:
	var rotation_radians := Vector3(
		deg_to_rad(local_rotation_deg.x),
		deg_to_rad(local_rotation_deg.y),
		deg_to_rad(local_rotation_deg.z)
	)
	var local_basis := Basis.from_euler(rotation_radians).scaled(local_scale)
	return Transform3D(local_basis, local_offset)


func _bind_or_spawn_modular_equipment_piece(
	slot_name: String,
	root_path: NodePath,
	root_fallback_name: String,
	offset_name: String,
	scene_path: String,
	skeleton: Skeleton3D,
	bone_name_override: StringName,
	rotation_bone_name_override: StringName,
	bone_keywords: Array[String],
	local_offset: Vector3,
	local_rotation_deg: Vector3,
	local_scale: Vector3
) -> void:
	var attachment_root: Node3D = _resolve_or_create_attachment_root(root_path, root_fallback_name)
	if attachment_root == null:
		return

	var local_offset_root: Node3D = _resolve_or_create_offset_root(
		attachment_root, offset_name, local_offset, local_rotation_deg, local_scale
	)
	if local_offset_root == null:
		return

	var piece_instance: Node3D = _find_first_node3d_child(local_offset_root)
	if piece_instance == null and runtime_spawn_equipment_if_missing and not scene_path.is_empty():
		var scene_res: PackedScene = load(scene_path) as PackedScene
		if scene_res != null:
			var piece_instance_raw: Node = scene_res.instantiate()
			var spawned_piece: Node3D = piece_instance_raw as Node3D
			if spawned_piece != null:
				spawned_piece.name = "Equipment%sMesh" % [slot_name]
				local_offset_root.add_child(spawned_piece)
				piece_instance = spawned_piece

	if piece_instance == null:
		if scene_path.is_empty():
			_apply_attachment_visibility(attachment_root, false)
			return
		push_warning("[PlayerVisual] Missing equipment mesh under %s/%s. Add the scene as a child for %s." % [attachment_root.name, offset_name, slot_name])
	else:
		if equipment_force_visibility_material:
			_apply_equipment_visibility_material_override(piece_instance, slot_name)

	var bone_idx: int = _resolve_equipment_bone_idx(skeleton, bone_name_override, bone_keywords)
	if strict_hand_attachment and slot_name == "Shield" and bone_idx < 0:
		# Older rigs exposed the shield anchor on LeftHand, but KayKit Knight has an explicit
		# hand slot. Only fall back when we truly failed to resolve a configured anchor.
		var forced_left_hand_idx: int = _find_bone_idx_case_insensitive(skeleton, "LeftHand")
		if forced_left_hand_idx >= 0:
			bone_idx = forced_left_hand_idx
	if bone_idx < 0:
		push_warning("[PlayerVisual] Could not resolve bone for %s equipment '%s'." % [slot_name, scene_path])
		return
	var rotation_bone_idx: int = bone_idx
	if rotation_bone_name_override != &"":
		var explicit_rotation_idx: int = skeleton.find_bone(String(rotation_bone_name_override))
		if explicit_rotation_idx >= 0:
			rotation_bone_idx = explicit_rotation_idx
	var yaw_only_follow: bool = slot_name == "Helmet" and equipment_helmet_yaw_only_follow
	var anchor_world: Transform3D = _compute_equipment_anchor_world(
		skeleton, bone_idx, rotation_bone_idx, yaw_only_follow
	)
	var local_from_bone: Transform3D = Transform3D.IDENTITY
	if strict_hand_attachment and slot_name == "Shield":
		local_from_bone = Transform3D.IDENTITY
	elif runtime_use_scene_authored_offsets or _should_preserve_equipment_offsets():
		local_from_bone = anchor_world.affine_inverse() * attachment_root.global_transform

	var follow_record: Dictionary = {
		"root": attachment_root,
		"skeleton": skeleton,
		"bone_idx": bone_idx,
		"rotation_bone_idx": rotation_bone_idx,
		"yaw_only_follow": yaw_only_follow,
		"local_from_bone": local_from_bone,
	}
	_equipment_follow_targets[slot_name] = follow_record


func _resolve_equipment_bone_idx(
	skeleton: Skeleton3D, bone_name_override: StringName, bone_keywords: Array[String]
) -> int:
	if skeleton == null:
		return -1
	if bone_name_override != &"":
		var explicit_idx: int = skeleton.find_bone(String(bone_name_override))
		if explicit_idx < 0:
			explicit_idx = _find_bone_idx_case_insensitive(skeleton, String(bone_name_override))
		if explicit_idx >= 0:
			return explicit_idx

	for i in range(skeleton.get_bone_count()):
		var bone_name_l: String = String(skeleton.get_bone_name(i)).to_lower()
		for kw in bone_keywords:
			var kw_l: String = String(kw).to_lower()
			if kw_l.is_empty():
				continue
			if bone_name_l.find(kw_l) >= 0:
				return i
	return -1


func _update_modular_equipment_bone_follow() -> void:
	if _equipment_follow_targets.is_empty():
		return
	var keys: Array = _equipment_follow_targets.keys()
	for k in keys:
		var record_v: Variant = _equipment_follow_targets.get(k, null)
		if not (record_v is Dictionary):
			continue
		var record: Dictionary = record_v as Dictionary
		var root_v: Variant = record.get("root", null)
		var skeleton_v: Variant = record.get("skeleton", null)
		var bone_idx_v: Variant = record.get("bone_idx", -1)
		var rotation_bone_idx_v: Variant = record.get("rotation_bone_idx", -1)
		var yaw_only_follow_v: Variant = record.get("yaw_only_follow", false)
		var local_from_bone_v: Variant = record.get("local_from_bone", Transform3D.IDENTITY)
		if not (root_v is Node3D) or not (skeleton_v is Skeleton3D):
			continue
		var root_node: Node3D = root_v as Node3D
		var skeleton: Skeleton3D = skeleton_v as Skeleton3D
		var bone_idx: int = int(bone_idx_v)
		var rotation_bone_idx: int = int(rotation_bone_idx_v)
		var yaw_only_follow: bool = bool(yaw_only_follow_v)
		var local_from_bone: Transform3D = (
			local_from_bone_v as Transform3D if local_from_bone_v is Transform3D else Transform3D.IDENTITY
		)
		if root_node == null or not is_instance_valid(root_node):
			continue
		if skeleton == null or not is_instance_valid(skeleton):
			continue
		if bone_idx < 0 or bone_idx >= skeleton.get_bone_count():
			continue
		var anchor_world: Transform3D = _compute_equipment_anchor_world(
			skeleton, bone_idx, rotation_bone_idx, yaw_only_follow
		)
		root_node.global_transform = anchor_world * local_from_bone


func _compute_equipment_anchor_world(
	skeleton: Skeleton3D, position_bone_idx: int, rotation_bone_idx: int, yaw_only_follow: bool = false
) -> Transform3D:
	var position_world: Transform3D = _compute_bone_world_no_scale(skeleton, position_bone_idx)
	var rotation_world: Transform3D = _compute_bone_world_no_scale(
		skeleton, rotation_bone_idx if rotation_bone_idx >= 0 else position_bone_idx
	)
	if yaw_only_follow:
		var up_axis: Vector3 = rotation_world.basis.y.normalized()
		var forward_axis: Vector3 = position_world.basis.z - up_axis * position_world.basis.z.dot(up_axis)
		if forward_axis.length_squared() < 0.0001:
			forward_axis = rotation_world.basis.z - up_axis * rotation_world.basis.z.dot(up_axis)
		if forward_axis.length_squared() < 0.0001:
			forward_axis = rotation_world.basis.z
		forward_axis = forward_axis.normalized()
		var right_axis: Vector3 = up_axis.cross(forward_axis)
		if right_axis.length_squared() < 0.0001:
			right_axis = rotation_world.basis.x
		right_axis = right_axis.normalized()
		forward_axis = right_axis.cross(up_axis).normalized()
		return Transform3D(Basis(right_axis, up_axis, forward_axis), position_world.origin)
	return Transform3D(rotation_world.basis, position_world.origin)


func _compute_bone_world_no_scale(skeleton: Skeleton3D, bone_idx: int) -> Transform3D:
	if skeleton == null or not is_instance_valid(skeleton):
		return Transform3D.IDENTITY
	if bone_idx < 0 or bone_idx >= skeleton.get_bone_count():
		return Transform3D(skeleton.global_transform.basis.orthonormalized(), skeleton.global_transform.origin)
	var bone_pose: Transform3D = skeleton.get_bone_global_pose(bone_idx)
	var bone_world: Transform3D = skeleton.global_transform * bone_pose
	return Transform3D(bone_world.basis.orthonormalized(), bone_world.origin)


func _find_first_skeleton_3d(root: Node) -> Skeleton3D:
	for c in root.get_children():
		if c is Skeleton3D:
			return c as Skeleton3D
		var found := _find_first_skeleton_3d(c)
		if found != null:
			return found
	return null


func _find_first_node3d_child(root: Node) -> Node3D:
	if root == null:
		return null
	for c in root.get_children():
		var child: Node = c as Node
		if child == null:
			continue
		if child is Node3D:
			return child as Node3D
	return null


func _choose_sword_bone_name(skeleton: Skeleton3D) -> StringName:
	if skeleton == null:
		return &""

	if sword_bone_name_override != &"":
		var idx := skeleton.find_bone(String(sword_bone_name_override))
		if idx >= 0:
			return sword_bone_name_override

	var best_name: StringName = &""
	var best_score := 0.0

	# Score bones by keyword matches. This lets you "just set" the sword even if you don't know the bone name yet.
	var any_keyword_match := false
	for i in range(skeleton.get_bone_count()):
		var name_i := skeleton.get_bone_name(i)
		var name_l := String(name_i).to_lower()
		var score := 0.0
		var this_bone_keyword_match := false

		for kw in sword_bone_keywords:
			var kw_l := String(kw).to_lower()
			if kw_l.is_empty():
				continue
			if name_l.find(kw_l) >= 0:
				score += 10.0
				this_bone_keyword_match = true
				# Small preference nudges for likely weapon/hand bones.
				if kw_l == "hand":
					score += 3.0
				if kw_l in ["weapon", "sword", "blade"]:
					score += 2.0

		# Bonus if the bone name suggests left/right and sword usage.
		if name_l.find("left") >= 0 or name_l.find("right") >= 0:
			score += 1.5

		if this_bone_keyword_match:
			any_keyword_match = true
		if score > best_score and this_bone_keyword_match:
			best_score = score
			best_name = name_i

	# If keywords didn't match at all, fall back to the first bone so the sword is visible and debuggable.
	if not any_keyword_match and skeleton.get_bone_count() > 0:
		push_warning("[PlayerVisual] Sword bone keywords didn't match; falling back to bone[0].")
		return skeleton.get_bone_name(0)

	return best_name


func _print_skeleton_bones_debug(skeleton: Skeleton3D, chosen: StringName) -> void:
	var bones: Array[String] = []
	for i in range(skeleton.get_bone_count()):
		var n := String(skeleton.get_bone_name(i))
		if n.is_empty():
			continue
		bones.append(n)
	var out := "[PlayerVisual] Sword bone chosen='%s' candidates=%s" % [String(chosen), bones.size()]
	print(out)
	for n in bones:
		if String(chosen) == n:
			print("  * %s" % [n])
		else:
			print("    %s" % [n])


func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_animation_player(c)
		if found:
			return found
	return null


func _find_or_create_animation_player() -> AnimationPlayer:
	var existing := _find_animation_player(self)
	if existing != null:
		return existing
	var host := get_node_or_null("Meshy")
	if host == null:
		return null
	var created := AnimationPlayer.new()
	created.name = "AnimationPlayer"
	host.add_child(created)
	_mark_editor_owned(created)
	return created


func _first_existing_path(paths: Array) -> String:
	for p in paths:
		var path := String(p)
		if path.is_empty():
			continue
		var abs_path: String = ProjectSettings.globalize_path(path)
		if ResourceLoader.exists(path) or FileAccess.file_exists(abs_path):
			return path
	return ""


func _ensure_preferred_base_model() -> void:
	var desired_path: String = ""
	var desired_scene: PackedScene = null
	var preferred_candidates: Array = _BASE_MODEL_GLB_CANDIDATES
	if Engine.is_editor_hint() and _effective_editor_t_pose_preview():
		preferred_candidates = _BASE_MODEL_TPOSE_GLB_CANDIDATES
	for candidate in preferred_candidates:
		var path: String = String(candidate)
		if path.is_empty():
			continue
		var candidate_scene: PackedScene = load(path) as PackedScene
		if candidate_scene == null:
			continue
		desired_scene = candidate_scene
		desired_path = path
		break
	if desired_path.is_empty():
		return
	var current := get_node_or_null("Meshy")
	if current != null and String(current.scene_file_path) == desired_path:
		return
	if desired_scene == null:
		return
	var desired_instance := desired_scene.instantiate()
	if desired_instance == null:
		return
	desired_instance.name = "Meshy"
	if current != null and current is Node3D and desired_instance is Node3D:
		(desired_instance as Node3D).transform = (current as Node3D).transform
	if current == null:
		add_child(desired_instance)
		_reset_base_model_material_cache()
		_setup_base_model_visor_attachment()
		return
	var insert_index := current.get_index()
	remove_child(current)
	current.free()
	add_child(desired_instance)
	move_child(desired_instance, insert_index)
	_reset_base_model_material_cache()
	_setup_base_model_visor_attachment()


func _reset_base_model_material_cache() -> void:
	_base_model_material_sources.clear()
	_active_knight_texture_path = ""


func _knight_texture_path_for_armor_item(armor_item_id: StringName) -> String:
	if armor_item_id == &"armor_scale":
		return knight_alternate_texture_path
	return knight_default_texture_path


func _apply_knight_texture_for_armor_item(armor_item_id: StringName) -> void:
	var target_texture_path := _knight_texture_path_for_armor_item(armor_item_id)
	if target_texture_path.is_empty() or target_texture_path == _active_knight_texture_path:
		return
	var texture := load(target_texture_path) as Texture2D
	if texture == null:
		push_warning("[PlayerVisual] Could not load Knight texture '%s'." % target_texture_path)
		return
	var meshy := get_node_or_null("Meshy")
	if meshy == null:
		return
	var stack: Array[Node] = [meshy]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			_apply_knight_texture_to_mesh_instance(node as MeshInstance3D, texture)
		for child in node.get_children():
			stack.append(child)
	_active_knight_texture_path = target_texture_path
	_setup_base_model_visor_attachment()


func _apply_knight_texture_to_mesh_instance(mesh_instance: MeshInstance3D, texture: Texture2D) -> void:
	if mesh_instance == null or not is_instance_valid(mesh_instance):
		return
	var mesh := mesh_instance.mesh
	if mesh == null:
		return
	var surface_count := mesh.get_surface_count()
	for surface_idx in range(surface_count):
		var cache_key := "%s#%d" % [String(mesh_instance.get_path()), surface_idx]
		var source_mat_v: Variant = _base_model_material_sources.get(cache_key, null)
		var source_mat := source_mat_v as BaseMaterial3D
		if source_mat == null:
			var candidate_mat: Material = mesh_instance.get_surface_override_material(surface_idx)
			if candidate_mat == null:
				candidate_mat = mesh.surface_get_material(surface_idx)
			if candidate_mat is not BaseMaterial3D:
				continue
			source_mat = (candidate_mat as BaseMaterial3D).duplicate(true) as BaseMaterial3D
			_base_model_material_sources[cache_key] = source_mat
		var replacement := source_mat.duplicate(true) as BaseMaterial3D
		if replacement == null:
			continue
		replacement.albedo_texture = texture
		replacement.texture_filter = source_mat.texture_filter
		replacement.texture_repeat = source_mat.texture_repeat
		mesh_instance.set_surface_override_material(surface_idx, replacement)


func _merge_anim_libraries_from_glb(glb_path: String, library_prefix: StringName) -> bool:
	if _anim == null:
		return false
	var ps: PackedScene = load(glb_path) as PackedScene
	if ps == null:
		return false
	var inst: Node = ps.instantiate()
	var tmp: AnimationPlayer = _find_animation_player(inst)
	if tmp == null:
		inst.free()
		return false
	var idx := 0
	var merged_any := false
	for lib_key in tmp.get_animation_library_list():
		var lib: AnimationLibrary = tmp.get_animation_library(lib_key)
		if lib == null:
			continue
		var new_name := String(library_prefix) + (("_" + str(idx)) if idx > 0 else "")
		idx += 1
		if _anim.has_animation_library(new_name):
			continue
		_anim.add_animation_library(new_name, lib.duplicate(true))
		merged_any = true
	inst.free()
	return merged_any


func _merge_anim_libraries_from_candidates(
	glb_candidates: Array, library_prefix: StringName
) -> void:
	for path in glb_candidates:
		var candidate_path: String = String(path)
		if candidate_path.is_empty():
			continue
		if _merge_anim_libraries_from_glb(candidate_path, library_prefix):
			return


func _find_clip_by_hint_or_keywords(hint: String, keywords: Array) -> StringName:
	if _anim == null or _anim.get_animation_list().is_empty():
		return &""
	var names := _anim.get_animation_list()
	var hint_l := hint.to_lower()
	if not hint_l.is_empty():
		for n in names:
			if hint_l in String(n).to_lower():
				return n
	for keyword in keywords:
		var key_l := String(keyword).to_lower()
		if key_l.is_empty():
			continue
		for n in names:
			if key_l in String(n).to_lower():
				return n
	for n in names:
		var lower := String(n).to_lower()
		if "reset" not in lower:
			return n
	return names[0]


func _cache_role_clips() -> void:
	_idle_clip = _find_clip_by_hint_or_keywords(idle_clip_hint, ["idle", "stand", "walk"])
	_run_clip = _find_clip_by_hint_or_keywords(run_clip_hint, ["walk", "walking", "run", "running", "sprint"])
	_melee_clip = _find_clip_by_hint_or_keywords(melee_clip_hint, ["slash", "attack"])
	_ranged_clip = _find_clip_by_hint_or_keywords(
		ranged_clip_hint, ["shoot", "ranged", "slash", "attack"]
	)
	_bomb_clip = _find_clip_by_hint_or_keywords(
		bomb_clip_hint, ["bomb", "throw", "slash", "attack"]
	)
	_defend_clip = _find_clip_by_hint_or_keywords(defend_clip_hint, ["block", "defend", "guard"])
	_downed_clip = _find_clip_by_hint_or_keywords(
		downed_clip_hint, ["shot", "fall", "down", "hit"]
	)
	if _ranged_clip == &"":
		_ranged_clip = _melee_clip
	if _bomb_clip == &"":
		_bomb_clip = _melee_clip
	if _run_clip == &"":
		_run_clip = _idle_clip
	_set_clip_looping(_idle_clip, true)
	_set_clip_looping(_run_clip, true)
	_set_clip_looping(_defend_clip, true)


func _set_clip_looping(clip: StringName, should_loop: bool) -> void:
	if _anim == null or clip == &"":
		return
	var anim_res := _anim.get_animation(clip)
	if anim_res == null:
		return
	anim_res.loop_mode = Animation.LOOP_LINEAR if should_loop else Animation.LOOP_NONE


func _setup_animation_tree() -> void:
	if _anim == null:
		return
	if Engine.is_editor_hint() and _effective_editor_t_pose_preview():
		return
	_anim_tree_skeleton_track_prefix = _detect_animation_tree_skeleton_track_prefix()
	var tree := _find_or_create_animation_tree()
	if tree == null:
		return
	var state_machine := AnimationNodeStateMachine.new()
	state_machine.add_node(
		_ANIM_STATE_LOCOMOTION, _build_locomotion_state_tree(), Vector2(0.0, 0.0)
	)
	state_machine.add_node(
		_ANIM_STATE_ATTACK_MELEE,
		_build_attack_state_tree(_melee_clip, &"action_blend"),
		Vector2(280.0, -120.0)
	)
	state_machine.add_node(
		_ANIM_STATE_ATTACK_RANGED,
		_build_attack_state_tree(_ranged_clip, &"action_blend"),
		Vector2(280.0, 0.0)
	)
	state_machine.add_node(
		_ANIM_STATE_ATTACK_BOMB,
		_build_attack_state_tree(_bomb_clip, &"action_blend"),
		Vector2(280.0, 120.0)
	)
	var downed_node := AnimationNodeAnimation.new()
	downed_node.animation = _downed_clip
	state_machine.add_node(_ANIM_STATE_DOWNED, downed_node, Vector2(560.0, 0.0))
	_add_state_machine_transition(
		state_machine, _ANIM_STATE_LOCOMOTION, _ANIM_STATE_ATTACK_MELEE, _ANIM_XFADE_FAST
	)
	_add_state_machine_transition(
		state_machine, _ANIM_STATE_LOCOMOTION, _ANIM_STATE_ATTACK_RANGED, _ANIM_XFADE_FAST
	)
	_add_state_machine_transition(
		state_machine, _ANIM_STATE_LOCOMOTION, _ANIM_STATE_ATTACK_BOMB, _ANIM_XFADE_FAST
	)
	_add_state_machine_transition(
		state_machine, _ANIM_STATE_ATTACK_MELEE, _ANIM_STATE_LOCOMOTION, _ANIM_XFADE_FAST
	)
	_add_state_machine_transition(
		state_machine, _ANIM_STATE_ATTACK_RANGED, _ANIM_STATE_LOCOMOTION, _ANIM_XFADE_FAST
	)
	_add_state_machine_transition(
		state_machine, _ANIM_STATE_ATTACK_BOMB, _ANIM_STATE_LOCOMOTION, _ANIM_XFADE_FAST
	)
	for from_state in [
		_ANIM_STATE_LOCOMOTION,
		_ANIM_STATE_ATTACK_MELEE,
		_ANIM_STATE_ATTACK_RANGED,
		_ANIM_STATE_ATTACK_BOMB,
	]:
		_add_state_machine_transition(
			state_machine, from_state, _ANIM_STATE_DOWNED, _ANIM_XFADE_DOWNED
		)
	_add_state_machine_transition(
		state_machine, _ANIM_STATE_DOWNED, _ANIM_STATE_LOCOMOTION, _ANIM_XFADE_FAST
	)
	tree.anim_player = tree.get_path_to(_anim)
	tree.tree_root = state_machine
	tree.active = true
	_anim_tree = tree
	_anim_state_playback = tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if _anim_state_playback != null:
		_anim_state_playback.start(_ANIM_STATE_LOCOMOTION, true)
	_sync_animation_tree_parameters()


func _find_or_create_animation_tree() -> AnimationTree:
	var existing := get_node_or_null(^"AnimationTree") as AnimationTree
	if existing != null and is_instance_valid(existing):
		return existing
	var created := AnimationTree.new()
	created.name = &"AnimationTree"
	add_child(created)
	_mark_editor_owned(created)
	return created


func _build_locomotion_state_tree() -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = _idle_clip
	var run_node := AnimationNodeAnimation.new()
	run_node.animation = _run_clip
	var defend_node := AnimationNodeAnimation.new()
	defend_node.animation = _defend_clip
	var speed_blend := AnimationNodeBlend2.new()
	var defend_blend := AnimationNodeBlend2.new()
	_apply_upper_body_filter(defend_blend)
	tree.add_node(&"idle", idle_node, Vector2(-560.0, -120.0))
	tree.add_node(&"run", run_node, Vector2(-560.0, 0.0))
	tree.add_node(&"defend", defend_node, Vector2(-560.0, 120.0))
	tree.add_node(&"speed_blend", speed_blend, Vector2(-280.0, -40.0))
	tree.add_node(&"defend_blend", defend_blend, Vector2(0.0, -20.0))
	tree.connect_node(&"speed_blend", 0, &"idle")
	tree.connect_node(&"speed_blend", 1, &"run")
	tree.connect_node(&"defend_blend", 0, &"speed_blend")
	tree.connect_node(&"defend_blend", 1, &"defend")
	tree.connect_node(&"output", 0, &"defend_blend")
	return tree


func _build_attack_state_tree(
	action_clip: StringName, blend_node_name: StringName = &"action_blend"
) -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = _idle_clip
	var run_node := AnimationNodeAnimation.new()
	run_node.animation = _run_clip
	var action_node := AnimationNodeAnimation.new()
	action_node.animation = action_clip
	var speed_blend := AnimationNodeBlend2.new()
	var action_blend := AnimationNodeBlend2.new()
	_apply_upper_body_filter(action_blend)
	tree.add_node(&"idle", idle_node, Vector2(-560.0, -120.0))
	tree.add_node(&"run", run_node, Vector2(-560.0, 0.0))
	tree.add_node(&"action", action_node, Vector2(-560.0, 120.0))
	tree.add_node(&"speed_blend", speed_blend, Vector2(-280.0, -20.0))
	tree.add_node(blend_node_name, action_blend, Vector2(0.0, 0.0))
	tree.connect_node(&"speed_blend", 0, &"idle")
	tree.connect_node(&"speed_blend", 1, &"run")
	tree.connect_node(blend_node_name, 0, &"speed_blend")
	tree.connect_node(blend_node_name, 1, &"action")
	tree.connect_node(&"output", 0, blend_node_name)
	return tree


func _add_state_machine_transition(
	state_machine: AnimationNodeStateMachine,
	from_state: StringName,
	to_state: StringName,
	xfade_time: float
) -> void:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = xfade_time
	transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_DISABLED
	transition.reset = true
	state_machine.add_transition(from_state, to_state, transition)


func _detect_animation_tree_skeleton_track_prefix() -> String:
	for clip in [_defend_clip, _melee_clip, _ranged_clip, _bomb_clip, _run_clip, _idle_clip]:
		var prefix := _animation_track_prefix_for_clip(clip)
		if not prefix.is_empty():
			return prefix
	return "Rig_Medium/Skeleton3D"


func _animation_track_prefix_for_clip(clip: StringName) -> String:
	if _anim == null or clip == &"":
		return ""
	var anim_res := _anim.get_animation(clip)
	if anim_res == null:
		return ""
	for i in range(anim_res.get_track_count()):
		var path_text := String(anim_res.track_get_path(i))
		var colon_idx := path_text.rfind(":")
		if colon_idx > 0:
			return path_text.substr(0, colon_idx)
	return ""


func _apply_upper_body_filter(node: AnimationNode) -> void:
	if node == null:
		return
	node.set_filter_enabled(true)
	var prefix := _anim_tree_skeleton_track_prefix
	for bone_name in _ANIMTREE_UPPER_BODY_BONES:
		node.set_filter_path(NodePath("%s:%s" % [prefix, String(bone_name)]), true)


func _is_animation_tree_active() -> bool:
	return _anim_tree != null and is_instance_valid(_anim_tree) and _anim_tree.active


func _set_animation_tree_enabled(active: bool) -> void:
	if _anim_tree == null or not is_instance_valid(_anim_tree):
		return
	_anim_tree.active = active


func _set_animation_tree_parameter(path: String, value: Variant) -> void:
	if not _is_animation_tree_active():
		return
	_anim_tree.set(path, value)


func _travel_animation_state(state_name: StringName, reset: bool = true) -> void:
	if _anim_state_playback == null:
		return
	_anim_state_playback.travel(state_name, reset)


func _current_animation_state() -> StringName:
	if _anim_state_playback == null:
		return &""
	return _anim_state_playback.get_current_node()


func _sync_animation_tree_parameters() -> void:
	if _anim_tree == null or not is_instance_valid(_anim_tree):
		return
	_set_animation_tree_enabled(not (Engine.is_editor_hint() and _effective_editor_t_pose_preview()))
	if not _is_animation_tree_active():
		return
	for state_name in _ANIM_LOCOMOTION_STATE_NAMES:
		_set_animation_tree_parameter(
			"parameters/%s/speed_blend/blend_amount" % [String(state_name)],
			_normalized_speed_ratio
		)
	_set_animation_tree_parameter(
		"parameters/%s/defend_blend/blend_amount" % [String(_ANIM_STATE_LOCOMOTION)],
		1.0 if _defending_hold_active else 0.0
	)
	_set_animation_tree_parameter(
		"parameters/%s/action_blend/blend_amount" % [String(_ANIM_STATE_ATTACK_MELEE)],
		1.0
	)
	_set_animation_tree_parameter(
		"parameters/%s/action_blend/blend_amount" % [String(_ANIM_STATE_ATTACK_RANGED)],
		1.0
	)
	_set_animation_tree_parameter(
		"parameters/%s/action_blend/blend_amount" % [String(_ANIM_STATE_ATTACK_BOMB)],
		1.0
	)


func _pick_locomotion_clip(running: bool) -> StringName:
	if running and _run_clip != &"":
		return _run_clip
	if _idle_clip != &"":
		return _idle_clip
	if _anim == null or _anim.get_animation_list().is_empty():
		return &""
	var names := _anim.get_animation_list()
	for n in names:
		var lower := String(n).to_lower()
		if "reset" not in lower and "attack" not in lower:
			return n
	return names[0]


func _play_locomotion(moving: bool, speed_scale: float) -> void:
	_last_locomotion_moving = moving
	_last_locomotion_speed_scale = speed_scale
	_normalized_speed_ratio = clampf(speed_scale if _last_locomotion_moving else 0.0, 0.0, 1.0)
	if _is_animation_tree_active():
		_sync_animation_tree_parameters()
		if not _attack_playing and not _downed_hold_active:
			_travel_animation_state(_ANIM_STATE_LOCOMOTION, false)
		return
	if _anim == null or _attack_playing or _downed_hold_active or _defending_hold_active:
		return
	var clip := _pick_locomotion_clip(moving)
	if clip == &"":
		return
	if _anim.current_animation != String(clip) or not _anim.is_playing():
		_anim.play(clip)
	_anim.speed_scale = 1.0


func set_locomotion_from_planar_speed(planar_speed: float, max_speed: float) -> void:
	var moving := planar_speed > 0.05
	var t := clampf(planar_speed / max(max_speed, 0.001), 0.0, 1.0)
	_play_locomotion(moving, t if moving else 0.0)


func _sync_charge_bar_world_pose() -> void:
	if _melee_charge_bar_root == null or not is_instance_valid(_melee_charge_bar_root):
		return
	if not _melee_charge_bar_root.visible:
		return
	# World-locked orientation so yaw / jump tilt on PlayerVisual does not spin or tip the bar.
	_melee_charge_bar_root.global_position = global_position + Vector3(0.0, CHARGE_BAR_Y, 0.0)
	_melee_charge_bar_root.global_rotation = Vector3.ZERO


func _ensure_melee_charge_bar() -> void:
	if _melee_charge_bar_root != null and is_instance_valid(_melee_charge_bar_root):
		return
	var root := Node3D.new()
	root.name = &"MeleeChargeBar"
	root.visible = false
	add_child(root)
	_mark_editor_owned(root)
	# scenes/ui/health_bar.tscn: Bars 208px wide, HealthFrame 27px tall, Inner 2px inset → 204×23 inner.
	# REF_INNER_W_WORLD maps health inner width to world meters; full bar aspect × CHARGE_BAR_SIZE_MULT (~4× area vs old 1/3 size).
	const HEALTH_INNER_W_PX := 204.0
	const HEALTH_INNER_H_PX := 23.0
	const HEALTH_OUTER_W_PX := 208.0
	const HEALTH_OUTER_H_PX := 27.0
	const REF_INNER_W_WORLD := 0.82
	const CHARGE_BAR_SIZE_MULT := 1.25
	var m_per_px := REF_INNER_W_WORLD / HEALTH_INNER_W_PX
	var OUTER := Vector2(HEALTH_OUTER_W_PX * m_per_px, HEALTH_OUTER_H_PX * m_per_px) * CHARGE_BAR_SIZE_MULT
	var INNER := Vector2(HEALTH_INNER_W_PX * m_per_px, HEALTH_INNER_H_PX * m_per_px) * CHARGE_BAR_SIZE_MULT
	# Health-bar-style strip: black frame, dark track, yellow fill L→R. Flat in world XZ (no billboard — billboard breaks scale.x fill).
	const CHARGE_FRAME := Color(0.0, 0.0, 0.0, 1.0)
	const CHARGE_TRACK := Color(0.32, 0.22, 0.06, 1.0)
	const CHARGE_FILL := Color(0.98, 0.84, 0.12, 1.0)
	const CHARGE_FILL_EMISSION := Color(1.0, 0.88, 0.22)
	# StandardMaterial3D.render_priority must be <= RenderingServer RENDER_PRIORITY_MAX (127 in 4.6).
	const CHARGE_BAR_PRI_FRAME := 120
	const CHARGE_BAR_PRI_TRACK := 121
	const CHARGE_BAR_PRI_FILL := 122
	const CHARGE_BAR_SORT_FRAME := 4.0
	const CHARGE_BAR_SORT_TRACK := 5.0
	const CHARGE_BAR_SORT_FILL := 6.0
	var layer_step := maxf(0.001, OUTER.y * 0.05)
	var border_mi := MeshInstance3D.new()
	border_mi.name = &"ChargeFrame"
	border_mi.sorting_offset = CHARGE_BAR_SORT_FRAME
	var border_mesh := PlaneMesh.new()
	border_mesh.size = OUTER
	border_mi.mesh = border_mesh
	border_mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	border_mi.position = Vector3(0.0, 0.0, -layer_step)
	var border_mat := StandardMaterial3D.new()
	border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	border_mat.albedo_color = CHARGE_FRAME
	border_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	border_mat.no_depth_test = true
	border_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	border_mat.render_priority = CHARGE_BAR_PRI_FRAME
	border_mi.material_override = border_mat
	border_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(border_mi)
	var track_mi := MeshInstance3D.new()
	track_mi.name = &"ChargeTrack"
	track_mi.sorting_offset = CHARGE_BAR_SORT_TRACK
	var track_mesh := PlaneMesh.new()
	track_mesh.size = INNER
	track_mi.mesh = track_mesh
	track_mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	track_mi.position = Vector3(0.0, layer_step, 0.0)
	var track_mat := StandardMaterial3D.new()
	track_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	track_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	track_mat.albedo_color = CHARGE_TRACK
	track_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	track_mat.no_depth_test = true
	track_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	track_mat.render_priority = CHARGE_BAR_PRI_TRACK
	track_mi.material_override = track_mat
	track_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(track_mi)
	var fill_mi := MeshInstance3D.new()
	fill_mi.name = &"ChargeFill"
	fill_mi.sorting_offset = CHARGE_BAR_SORT_FILL
	var fill_mesh := PlaneMesh.new()
	fill_mesh.size = INNER
	fill_mi.mesh = fill_mesh
	fill_mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	fill_mi.position = Vector3(0.0, layer_step * 2.5, 0.0)
	var fill_shader_mat := ShaderMaterial.new()
	fill_shader_mat.shader = CHARGE_BAR_FILL_SHADER
	fill_shader_mat.set_shader_parameter(&"albedo_color", Vector3(CHARGE_FILL.r, CHARGE_FILL.g, CHARGE_FILL.b))
	fill_shader_mat.set_shader_parameter(&"emission_color", Vector3(CHARGE_FILL_EMISSION.r, CHARGE_FILL_EMISSION.g, CHARGE_FILL_EMISSION.b))
	fill_shader_mat.set_shader_parameter(&"emission_energy", 0.55)
	fill_shader_mat.set_shader_parameter(&"fill_ratio", 1.0)
	fill_shader_mat.render_priority = CHARGE_BAR_PRI_FILL
	fill_mi.material_override = fill_shader_mat
	fill_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fill_mi)
	_melee_charge_bar_root = root
	_melee_charge_border_mi = border_mi
	_melee_charge_track_mi = track_mi
	_melee_charge_fill_shader_mat = fill_shader_mat
	_melee_charge_fill_mi = fill_mi


## progress in [0, 1] shows the fill; negative progress hides the bar.
func set_melee_charge_progress(progress: float) -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	_ensure_melee_charge_bar()
	if _melee_charge_bar_root == null:
		return
	if progress < 0.0:
		_melee_charge_bar_root.visible = false
		return
	var p := clampf(progress, 0.0, 1.0)
	_melee_charge_bar_root.visible = true
	_sync_charge_bar_world_pose()
	if _melee_charge_fill_shader_mat != null:
		_melee_charge_fill_shader_mat.set_shader_parameter(&"fill_ratio", p)


func set_jump_tilt(vertical_velocity: float, jump_impulse: float) -> void:
	rotation.x = PI / 6.0 * vertical_velocity / jump_impulse


func _clip_for_attack_mode(mode: StringName) -> StringName:
	match String(mode).to_lower():
		"ranged", "gun":
			return _ranged_clip if _ranged_clip != &"" else _melee_clip
		"bomb":
			return _bomb_clip if _bomb_clip != &"" else _melee_clip
		_:
			return _melee_clip


func _clip_length_seconds(clip: StringName) -> float:
	if _anim == null or clip == &"":
		return 0.0
	var anim_res := _anim.get_animation(clip)
	if anim_res == null:
		return 0.0
	return maxf(0.0, anim_res.length)


func get_attack_duration_seconds_for_mode(mode: StringName = &"melee") -> float:
	if attack_duration_seconds > 0.0:
		return attack_duration_seconds
	return _clip_length_seconds(_clip_for_attack_mode(mode))


func get_attack_duration_seconds() -> float:
	return get_attack_duration_seconds_for_mode(&"melee")


func try_play_attack_for_mode(mode: StringName = &"melee") -> void:
	if _anim == null or _attack_playing or _downed_hold_active or _defending_hold_active:
		return
	var normalized_mode := StringName(String(mode).to_lower())
	var clip := _clip_for_attack_mode(mode)
	if clip == &"":
		_cache_role_clips()
		clip = _clip_for_attack_mode(mode)
	if clip == &"":
		return
	_attack_playing = true
	_active_attack_mode = normalized_mode
	_attack_nonce += 1
	_attack_profile_elapsed = 0.0
	var attack_nonce := _attack_nonce
	var target_duration := get_attack_duration_seconds_for_mode(mode)
	var anim_len := _clip_length_seconds(clip)
	if anim_len <= 0.0:
		_attack_playing = false
		_active_attack_mode = &""
		_queued_attack_planar_direction = Vector2.ZERO
		return
	target_duration = maxf(
		target_duration if anim_len > 0.0 and target_duration > 0.0 else anim_len,
		0.01
	)
	if _is_animation_tree_active():
		_sync_animation_tree_parameters()
		match String(normalized_mode):
			"ranged", "gun":
				_travel_animation_state(_ANIM_STATE_ATTACK_RANGED)
			"bomb":
				_travel_animation_state(_ANIM_STATE_ATTACK_BOMB)
			_:
				_travel_animation_state(_ANIM_STATE_ATTACK_MELEE)
	else:
		_anim.play(clip)
		_anim.speed_scale = anim_len / target_duration if anim_len > 0.0 else 1.0
	_attack_profile_duration = maxf(target_duration, 0.01)
	await get_tree().create_timer(maxf(target_duration, 0.01)).timeout
	if attack_nonce != _attack_nonce:
		return
	_attack_playing = false
	_active_attack_mode = &""
	_queued_attack_planar_direction = Vector2.ZERO
	if _is_animation_tree_active() and not _downed_hold_active:
		_travel_animation_state(_ANIM_STATE_LOCOMOTION)
	_play_locomotion(_last_locomotion_moving, _last_locomotion_speed_scale)


func try_play_attack() -> void:
	try_play_attack_for_mode(&"melee")


func set_defending_state(active: bool) -> void:
	if _anim == null:
		return
	if active:
		if _downed_hold_active:
			return
		if _defending_hold_active:
			return
		_defending_hold_active = true
		_attack_nonce += 1
		_attack_playing = false
		_active_attack_mode = &""
		_queued_attack_planar_direction = Vector2.ZERO
		var clip: StringName = _defend_clip
		if clip == &"":
			_cache_role_clips()
			clip = _defend_clip
		if clip == &"":
			_defending_hold_active = false
			return
		if _is_animation_tree_active():
			_sync_animation_tree_parameters()
			return
		_anim.play(clip)
		_anim.speed_scale = 1.0
		return
	if not _defending_hold_active:
		return
	_defending_hold_active = false
	_active_attack_mode = &""
	_queued_attack_planar_direction = Vector2.ZERO
	if _is_animation_tree_active():
		_sync_animation_tree_parameters()
		return
	_anim.speed_scale = 1.0
	_play_locomotion(_last_locomotion_moving, _last_locomotion_speed_scale)


func set_downed_state(is_downed: bool) -> void:
	if _anim == null:
		return
	if is_downed:
		if _downed_hold_active:
			return
		_defending_hold_active = false
		_downed_hold_active = true
		_attack_nonce += 1
		_attack_playing = false
		_active_attack_mode = &""
		_queued_attack_planar_direction = Vector2.ZERO
		if _is_animation_tree_active():
			_sync_animation_tree_parameters()
			_travel_animation_state(_ANIM_STATE_DOWNED)
			return
		_downed_play_nonce += 1
		_play_downed_once_then_hold(_downed_play_nonce)
		return
	if not _downed_hold_active:
		return
	_downed_hold_active = false
	_defending_hold_active = false
	_downed_play_nonce += 1
	_attack_playing = false
	_active_attack_mode = &""
	_queued_attack_planar_direction = Vector2.ZERO
	if _is_animation_tree_active():
		_sync_animation_tree_parameters()
		_travel_animation_state(_ANIM_STATE_LOCOMOTION)
		return
	_anim.speed_scale = 1.0
	_play_locomotion(_last_locomotion_moving, _last_locomotion_speed_scale)


func _play_downed_once_then_hold(play_nonce: int) -> void:
	var clip := _downed_clip
	if clip == &"":
		_cache_role_clips()
		clip = _downed_clip
	if clip == &"":
		return
	_anim.speed_scale = 1.0
	_anim.play(clip)
	var anim_len := _clip_length_seconds(clip)
	if anim_len <= 0.0:
		return
	await get_tree().create_timer(anim_len).timeout
	if play_nonce != _downed_play_nonce or not _downed_hold_active:
		return
	_anim.seek(maxf(anim_len - 0.0001, 0.0), true)
	_anim.pause()
	_anim.speed_scale = 1.0


## Phase infusion readability: translucent blue silhouette in world space (2D x,y → 3D x,z).
func show_phase_spatial_cue(planar_xy: Vector2, delay_sec: float, duration_sec: float = 0.2) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var self_ref := self
	var cb := func () -> void:
		if not is_instance_valid(self_ref):
			return
		self_ref._spawn_phase_cue_at_planar(planar_xy, maxf(0.05, duration_sec))
	tree.create_timer(maxf(0.0, delay_sec)).timeout.connect(cb, CONNECT_ONE_SHOT)


func show_phase_dash_trail_cue(planar_xy: Vector2, direction_xy: Vector2, duration_sec: float = 0.18) -> void:
	var dir := direction_xy.normalized() if direction_xy.length_squared() > 1e-6 else Vector2(0.0, -1.0)
	var mid := planar_xy + dir * 1.85
	show_phase_spatial_cue(mid, 0.0, duration_sec)


func _spawn_phase_cue_at_planar(planar_xy: Vector2, duration_sec: float) -> void:
	var vw: Node3D = get_parent() as Node3D
	if vw == null:
		vw = self
	var mi := MeshInstance3D.new()
	mi.name = &"PhaseInfusionCue"
	var sph := SphereMesh.new()
	sph.radius = 0.42
	sph.height = 0.84
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.25, 0.55, 1.0, 0.42)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sph.material = mat
	mi.mesh = sph
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vw.add_child(mi)
	var h := 1.12
	mi.global_position = Vector3(planar_xy.x, h, planar_xy.y)
	var tree := get_tree()
	if tree == null:
		mi.queue_free()
		return
	var done := func () -> void:
		if is_instance_valid(mi):
			mi.queue_free()
	tree.create_timer(duration_sec).timeout.connect(done, CONNECT_ONE_SHOT)
