@tool
extends Node3D

## Drives role-based animation clips (idle/run/melee/ranged/bomb/downed).
@export var preview_in_editor: bool = true
@export var editor_live_bone_follow: bool = false
@export var editor_t_pose_preview: bool = true
@export var sword_root_path: NodePath = NodePath("SwordAttachment")
@export var sword_offset_node_name: StringName = &"SwordOffset"
@export var sword_preserve_editor_offset: bool = true
@export var runtime_spawn_sword_if_missing: bool = false

# Sword attachment tuning.
# This is applied by programmatically attaching the sword to a bone inside the imported GLB skeleton,
# then toggling the whole `SwordAttachment` container via `set_sword_active()`.
@export var sword_mesh_path: String = "res://scenes/equipment/weapons/sword_texture.tscn"
@export var sword_bone_name_override: StringName = &"LeftHand"
@export var sword_bone_keywords: Array[String] = ["hand", "weapon", "sword", "blade", "arm"]
@export var sword_local_offset: Vector3 = Vector3(1.6, -0.6, 0.9)
@export var sword_local_rotation_deg: Vector3 = Vector3(90.0, -10.0, 90.0) # Euler degrees
@export var sword_local_scale: Vector3 = Vector3(32.0, 32.0, 32.0)
@export var sword_force_visibility_material: bool = true
@export var sword_show_debug_proxy: bool = false
@export var sword_show_mode_beacon: bool = false
@export var sword_use_body_anchor_fallback: bool = false
@export var sword_body_anchor_local_position: Vector3 = Vector3(0.8, 1.5, 0.1)
@export var sword_body_anchor_local_rotation_deg: Vector3 = Vector3(0.0, 0.0, 90.0)
@export var sword_debug_log_visibility: bool = false
@export var sword_debug_print_bones: bool = false
@export var modular_equipment_enabled: bool = true
@export var equipment_chest_root_path: NodePath = NodePath("ArmorAttachment")
@export var equipment_legs_root_path: NodePath = NodePath("LegsAttachment")
@export var equipment_helmet_root_path: NodePath = NodePath("HelmetAttachment")
@export var equipment_preserve_editor_offsets: bool = true
@export var runtime_spawn_equipment_if_missing: bool = false
@export var equipment_chest_scene_path: String = "res://scenes/equipment/armor/chestplate_v01.tscn"
@export var equipment_legs_scene_path: String = "res://scenes/equipment/armor/legs_v02.tscn"
@export var equipment_helmet_scene_path: String = "res://scenes/equipment/helmet/helmet_v01.tscn"
@export var equipment_chest_bone_override: StringName = &"Spine2"
@export var equipment_legs_bone_override: StringName = &"Hips"
@export var equipment_helmet_bone_override: StringName = &"Head"
@export var equipment_chest_local_offset: Vector3 = Vector3.ZERO
@export var equipment_legs_local_offset: Vector3 = Vector3.ZERO
@export var equipment_helmet_local_offset: Vector3 = Vector3.ZERO
@export var equipment_chest_local_rotation_deg: Vector3 = Vector3.ZERO
@export var equipment_legs_local_rotation_deg: Vector3 = Vector3.ZERO
@export var equipment_helmet_local_rotation_deg: Vector3 = Vector3.ZERO
@export var equipment_chest_local_scale: Vector3 = Vector3.ONE
@export var equipment_legs_local_scale: Vector3 = Vector3.ONE
@export var equipment_helmet_local_scale: Vector3 = Vector3.ONE

@export var walk_speed_threshold := 8.0
@export var attack_duration_seconds := 0.2
@export var idle_clip_hint := "idle"
@export var run_clip_hint := "run"
@export var melee_clip_hint := "attack"
@export var ranged_clip_hint := "attack"
@export var bomb_clip_hint := "attack"
@export var downed_clip_hint := "dying"

const _IDLE_GLB_CANDIDATES := [
	"res://art/characters/player/Base_Model_V01_Idle.glb",
]
const _BASE_MODEL_GLB_CANDIDATES := [
	"res://art/characters/player/Base_Model_V01_Idle.glb",
	"res://art/characters/player/Base_Model_V01_rigged.glb",
	"res://art/characters/player/Base_Model_V01.glb",
]
const _BASE_MODEL_TPOSE_GLB_CANDIDATES := [
	"res://art/characters/player/Base_Model_V01.glb",
	"res://art/characters/player/Base_Model_V01_rigged.glb",
	"res://art/characters/player/Base_Model_V01_Idle.glb",
]
const _RUN_GLB_CANDIDATES := [
	"res://art/characters/player/Base_Model_V01_Running.glb",
]
const _SLASH_GLB_CANDIDATES := [
	"res://art/characters/player/Base_Model_V01_Attack.glb",
]
const _DOWNED_GLB_CANDIDATES := [
	"res://art/characters/player/Base_Model_V01_dying_backwards.glb",
]
const _EQUIPMENT_CHEST_BONE_KEYWORDS: Array[String] = ["spine", "chest", "upperchest", "torso"]
const _EQUIPMENT_LEGS_BONE_KEYWORDS: Array[String] = ["hips", "pelvis", "spine"]
const _EQUIPMENT_HELMET_BONE_KEYWORDS: Array[String] = ["head", "neck"]

var _anim: AnimationPlayer
var _attack_playing: bool = false
var _attack_nonce := 0
var _idle_clip: StringName = &""
var _run_clip: StringName = &""
var _melee_clip: StringName = &""
var _ranged_clip: StringName = &""
var _bomb_clip: StringName = &""
var _downed_clip: StringName = &""
var _last_locomotion_moving := false
var _last_locomotion_speed_scale := 1.0
var _downed_hold_active := false
var _downed_play_nonce := 0

var _sword_root: Node3D
var _sword_mode_beacon: MeshInstance3D
var _sword_follow_skeleton: Skeleton3D
var _sword_follow_bone_idx: int = -1
var _equipment_follow_targets: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	_ensure_preferred_base_model()
	_anim = _find_animation_player(self)
	if _anim:
		_anim.active = true
		_merge_anim_libraries_from_candidates(_IDLE_GLB_CANDIDATES, &"base_idle")
		_merge_anim_libraries_from_candidates(_RUN_GLB_CANDIDATES, &"base_run")
		_merge_anim_libraries_from_candidates(_SLASH_GLB_CANDIDATES, &"base_attack")
		_merge_anim_libraries_from_candidates(_DOWNED_GLB_CANDIDATES, &"base_downed")
		_cache_role_clips()
		if not (Engine.is_editor_hint() and editor_t_pose_preview):
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
	if Engine.is_editor_hint() and not editor_live_bone_follow:
		# Align once in editor, then let user move offset nodes without snapping.
		_update_sword_manual_bone_follow()
		_update_modular_equipment_bone_follow()


func _mark_editor_owned(node: Node) -> void:
	if node == null:
		return
	if Engine.is_editor_hint():
		node.owner = self


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and not preview_in_editor:
		return
	if Engine.is_editor_hint() and not editor_live_bone_follow:
		return
	_update_sword_manual_bone_follow()
	_update_modular_equipment_bone_follow()


func set_sword_active(active: bool) -> void:
	# Toggles sword visibility. The sword is attached to the skeleton in `_setup_sword_attachment()`.
	if _sword_root == null or not is_instance_valid(_sword_root):
		return
	_sword_root.visible = active
	if _sword_mode_beacon != null and is_instance_valid(_sword_mode_beacon):
		_sword_mode_beacon.visible = active
	if sword_debug_log_visibility and OS.is_debug_build():
		print("[PlayerVisual] set_sword_active=", active, " node=", _sword_root.get_path())


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
	_sword_root.position = Vector3.ZERO
	_sword_root.rotation = Vector3.ZERO
	_sword_root.scale = Vector3.ONE

	if sword_use_body_anchor_fallback:
		_sword_follow_skeleton = null
		_sword_follow_bone_idx = -1
		_apply_sword_body_anchor_fallback()
	else:
		_sword_follow_skeleton = skeleton
		_sword_follow_bone_idx = bone_idx

	var offset: Node3D = _sword_root.get_node_or_null(NodePath(String(sword_offset_node_name))) as Node3D
	if offset == null:
		offset = Node3D.new()
		offset.name = String(sword_offset_node_name)
		offset.position = sword_local_offset
		offset.rotation = Vector3(
			deg_to_rad(sword_local_rotation_deg.x),
			deg_to_rad(sword_local_rotation_deg.y),
			deg_to_rad(sword_local_rotation_deg.z)
		)
		offset.scale = sword_local_scale
		_sword_root.add_child(offset)
		_mark_editor_owned(offset)

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
	var bone_pose: Transform3D = _sword_follow_skeleton.get_bone_global_pose(_sword_follow_bone_idx)
	var bone_world: Transform3D = _sword_follow_skeleton.global_transform * bone_pose
	_sword_root.global_transform = bone_world


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
		var visible: StandardMaterial3D = StandardMaterial3D.new()
		# Keep original albedo texture so the sword uses real art, but force visibility-safe flags.
		visible.albedo_texture = src.albedo_texture
		visible.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		visible.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		visible.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		visible.cull_mode = BaseMaterial3D.CULL_DISABLED
		visible.no_depth_test = false
		visible.texture_filter = src.texture_filter
		visible.texture_repeat = src.texture_repeat
		visible.uv1_scale = src.uv1_scale
		visible.uv1_offset = src.uv1_offset
		return visible

	var fallback: StandardMaterial3D = StandardMaterial3D.new()
	fallback.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fallback.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
	fallback.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	return fallback


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
		_EQUIPMENT_CHEST_BONE_KEYWORDS,
		equipment_chest_local_offset,
		equipment_chest_local_rotation_deg,
		equipment_chest_local_scale
	)
	_bind_or_spawn_modular_equipment_piece(
		"Legs",
		equipment_legs_root_path,
		"LegsAttachment",
		"LegsOffset",
		equipment_legs_scene_path,
		skeleton,
		equipment_legs_bone_override,
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
		_EQUIPMENT_HELMET_BONE_KEYWORDS,
		equipment_helmet_local_offset,
		equipment_helmet_local_rotation_deg,
		equipment_helmet_local_scale
	)


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
		return existing_offset
	var local_offset_root: Node3D = Node3D.new()
	local_offset_root.name = offset_name
	local_offset_root.position = local_offset
	local_offset_root.rotation = Vector3(
		deg_to_rad(local_rotation_deg.x),
		deg_to_rad(local_rotation_deg.y),
		deg_to_rad(local_rotation_deg.z)
	)
	local_offset_root.scale = local_scale
	attachment_root.add_child(local_offset_root)
	return local_offset_root


func _bind_or_spawn_modular_equipment_piece(
	slot_name: String,
	root_path: NodePath,
	root_fallback_name: String,
	offset_name: String,
	scene_path: String,
	skeleton: Skeleton3D,
	bone_name_override: StringName,
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
		push_warning("[PlayerVisual] Missing equipment mesh under %s/%s. Add the scene as a child for %s." % [attachment_root.name, offset_name, slot_name])

	var bone_idx: int = _resolve_equipment_bone_idx(skeleton, bone_name_override, bone_keywords)
	if bone_idx < 0:
		push_warning("[PlayerVisual] Could not resolve bone for %s equipment '%s'." % [slot_name, scene_path])
		return

	var follow_record: Dictionary = {
		"root": attachment_root,
		"skeleton": skeleton,
		"bone_idx": bone_idx,
	}
	_equipment_follow_targets[slot_name] = follow_record


func _resolve_equipment_bone_idx(
	skeleton: Skeleton3D, bone_name_override: StringName, bone_keywords: Array[String]
) -> int:
	if skeleton == null:
		return -1
	if bone_name_override != &"":
		var explicit_idx: int = skeleton.find_bone(String(bone_name_override))
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
		if not (root_v is Node3D) or not (skeleton_v is Skeleton3D):
			continue
		var root_node: Node3D = root_v as Node3D
		var skeleton: Skeleton3D = skeleton_v as Skeleton3D
		var bone_idx: int = int(bone_idx_v)
		if root_node == null or not is_instance_valid(root_node):
			continue
		if skeleton == null or not is_instance_valid(skeleton):
			continue
		if bone_idx < 0 or bone_idx >= skeleton.get_bone_count():
			continue
		var bone_pose: Transform3D = skeleton.get_bone_global_pose(bone_idx)
		root_node.global_transform = skeleton.global_transform * bone_pose


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


func _first_existing_path(paths: Array) -> String:
	for p in paths:
		var path := String(p)
		if path.is_empty():
			continue
		if ResourceLoader.exists(path):
			return path
	return ""


func _ensure_preferred_base_model() -> void:
	var desired_path: String = ""
	var desired_scene: PackedScene = null
	var preferred_candidates: Array = _BASE_MODEL_GLB_CANDIDATES
	if Engine.is_editor_hint() and editor_t_pose_preview:
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
		return
	var insert_index := current.get_index()
	remove_child(current)
	current.free()
	add_child(desired_instance)
	move_child(desired_instance, insert_index)


func _merge_anim_libraries_from_glb(glb_path: String, library_prefix: StringName) -> void:
	if _anim == null:
		return
	var ps: PackedScene = load(glb_path) as PackedScene
	if ps == null:
		return
	var inst: Node = ps.instantiate()
	var tmp: AnimationPlayer = _find_animation_player(inst)
	if tmp == null:
		inst.free()
		return
	var idx := 0
	for lib_key in tmp.get_animation_library_list():
		var lib: AnimationLibrary = tmp.get_animation_library(lib_key)
		if lib == null:
			continue
		var new_name := String(library_prefix) + (("_" + str(idx)) if idx > 0 else "")
		idx += 1
		if _anim.has_animation_library(new_name):
			continue
		_anim.add_animation_library(new_name, lib.duplicate(true))
	inst.free()


func _merge_anim_libraries_from_candidates(
	glb_candidates: Array, library_prefix: StringName
) -> void:
	for path in glb_candidates:
		if not ResourceLoader.exists(path):
			continue
		_merge_anim_libraries_from_glb(path, library_prefix)
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
	_run_clip = _find_clip_by_hint_or_keywords(run_clip_hint, ["run", "running", "sprint"])
	_melee_clip = _find_clip_by_hint_or_keywords(melee_clip_hint, ["slash", "attack"])
	_ranged_clip = _find_clip_by_hint_or_keywords(
		ranged_clip_hint, ["shoot", "ranged", "slash", "attack"]
	)
	_bomb_clip = _find_clip_by_hint_or_keywords(
		bomb_clip_hint, ["bomb", "throw", "slash", "attack"]
	)
	_downed_clip = _find_clip_by_hint_or_keywords(
		downed_clip_hint, ["shot", "fall", "down", "hit"]
	)
	if _ranged_clip == &"":
		_ranged_clip = _melee_clip
	if _bomb_clip == &"":
		_bomb_clip = _melee_clip
	if _run_clip == &"":
		_run_clip = _idle_clip


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
	if _anim == null or _attack_playing or _downed_hold_active:
		return
	var clip := _pick_locomotion_clip(moving and speed_scale * 14.0 >= walk_speed_threshold)
	if clip == &"":
		return
	_last_locomotion_moving = moving and speed_scale * 14.0 >= walk_speed_threshold
	_last_locomotion_speed_scale = speed_scale
	if _anim.current_animation != String(clip) or not _anim.is_playing():
		_anim.play(clip)
	_anim.speed_scale = speed_scale if _last_locomotion_moving else 1.0


func set_locomotion_from_planar_speed(planar_speed: float, max_speed: float) -> void:
	if _attack_playing or _downed_hold_active:
		return
	var moving := planar_speed > 0.05
	var t := clampf(planar_speed / max(max_speed, 0.001), 0.0, 2.5)
	_play_locomotion(moving, maxf(t, 0.35) if moving else 1.0)


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
	if _anim == null or _attack_playing or _downed_hold_active:
		return
	var clip := _clip_for_attack_mode(mode)
	if clip == &"":
		_cache_role_clips()
		clip = _clip_for_attack_mode(mode)
	if clip == &"":
		return
	_attack_playing = true
	_attack_nonce += 1
	var attack_nonce := _attack_nonce
	_anim.play(clip)
	var target_duration := get_attack_duration_seconds_for_mode(mode)
	var anim_len := _clip_length_seconds(clip)
	if anim_len <= 0.0:
		_attack_playing = false
		return
	if anim_len > 0.0 and target_duration > 0.0:
		_anim.speed_scale = anim_len / target_duration
	else:
		target_duration = maxf(anim_len, 0.01)
	await get_tree().create_timer(maxf(target_duration, 0.01)).timeout
	if attack_nonce != _attack_nonce:
		return
	_attack_playing = false
	_play_locomotion(_last_locomotion_moving, _last_locomotion_speed_scale)


func try_play_attack() -> void:
	try_play_attack_for_mode(&"melee")


func set_downed_state(is_downed: bool) -> void:
	if _anim == null:
		return
	if is_downed:
		if _downed_hold_active:
			return
		_downed_hold_active = true
		_attack_nonce += 1
		_attack_playing = false
		_downed_play_nonce += 1
		_play_downed_once_then_hold(_downed_play_nonce)
		return
	if not _downed_hold_active:
		return
	_downed_hold_active = false
	_downed_play_nonce += 1
	_attack_playing = false
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
