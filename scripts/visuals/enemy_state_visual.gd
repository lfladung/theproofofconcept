extends Node3D
class_name EnemyStateVisual

var mesh_ground_y := 0.0
var mesh_scale := Vector3.ONE
var facing_yaw_offset_deg := 180.0
var rotation_offset_degrees := Vector3.ZERO

var _state_configs: Dictionary = {}
var _current_state: StringName = &""
var _pivot: Node3D
var _active_clip_root: Node3D
var _active_anim_player: AnimationPlayer
var _active_clip_name: StringName = &""
var _playback_speed_scale := 1.0
var _playback_paused := false


func _ready() -> void:
	_ensure_pivot()


func configure_states(state_configs: Dictionary) -> void:
	_state_configs = state_configs.duplicate(true)


func set_state(state: StringName, restart: bool = false) -> float:
	_ensure_pivot()
	var resolved_state := _resolve_state_name(state)
	if resolved_state == &"":
		return 0.0
	var config := _state_configs.get(resolved_state, {}) as Dictionary
	var desired_scene := config.get("scene", null) as PackedScene
	var needs_reload := (
		_active_clip_root == null
		or _current_state != resolved_state
		or restart
		or desired_scene == null
		or String(_active_clip_root.scene_file_path) != desired_scene.resource_path
	)
	if needs_reload:
		_swap_active_clip(desired_scene)
	_current_state = resolved_state
	_apply_scene_config(config)
	return _play_current_animation(config, restart or needs_reload)


func set_playback_speed_scale(scale_value: float) -> void:
	_playback_speed_scale = maxf(0.01, scale_value)
	_apply_active_anim_speed()


func set_playback_paused(paused: bool) -> void:
	_playback_paused = paused
	_apply_active_anim_speed()


func get_current_state() -> StringName:
	return _current_state


func sync_from_2d(world_position: Vector2, facing_direction: Vector2) -> void:
	global_position = Vector3(world_position.x, mesh_ground_y, world_position.y)
	scale = mesh_scale
	var yaw := deg_to_rad(facing_yaw_offset_deg)
	if facing_direction.length_squared() > 0.0001:
		yaw += atan2(facing_direction.x, facing_direction.y)
	rotation = Vector3(
		deg_to_rad(rotation_offset_degrees.x),
		yaw,
		deg_to_rad(rotation_offset_degrees.z)
	)


func get_current_animation_duration_seconds() -> float:
	if _active_anim_player == null:
		return 0.0
	var clip_name := _active_clip_name
	if clip_name == &"":
		clip_name = _pick_animation_name({})
	if clip_name == &"":
		return 0.0
	var anim := _active_anim_player.get_animation(clip_name)
	return maxf(0.0, anim.length) if anim != null else 0.0


func seek_current_animation_seconds(time_seconds: float) -> void:
	if _active_anim_player == null:
		return
	var duration := get_current_animation_duration_seconds()
	var clamped_time := clampf(time_seconds, 0.0, duration)
	_active_anim_player.seek(clamped_time, true)


func _resolve_state_name(state: StringName) -> StringName:
	if _state_configs.has(state):
		return state
	if _state_configs.has(&"idle"):
		return &"idle"
	for key_v in _state_configs.keys():
		if key_v is StringName:
			return key_v as StringName
	return &""


func _swap_active_clip(desired_scene: PackedScene) -> void:
	if _active_clip_root != null and is_instance_valid(_active_clip_root):
		_active_clip_root.queue_free()
	_active_clip_root = null
	_active_anim_player = null
	_active_clip_name = &""
	if desired_scene == null or _pivot == null:
		return
	var instance := desired_scene.instantiate()
	if instance is not Node3D:
		if instance is Node:
			(instance as Node).queue_free()
		return
	_active_clip_root = instance as Node3D
	_pivot.add_child(_active_clip_root)


func _play_current_animation(config: Dictionary, restart: bool) -> float:
	_active_anim_player = _find_animation_player(_active_clip_root)
	if _active_anim_player == null:
		return 0.0
	_active_clip_name = _pick_animation_name(config)
	if _active_clip_name == &"":
		return 0.0
	var current_name := String(_active_anim_player.current_animation)
	if restart or current_name != String(_active_clip_name) or not _active_anim_player.is_playing():
		_active_anim_player.play(_active_clip_name)
	_apply_active_anim_speed()
	var anim := _active_anim_player.get_animation(_active_clip_name)
	return maxf(0.0, anim.length) if anim != null else 0.0


func _apply_scene_config(config: Dictionary) -> void:
	if _active_clip_root == null:
		return
	var scene_scale_v: Variant = config.get("scene_scale", Vector3.ONE)
	if scene_scale_v is Vector3:
		_active_clip_root.scale = scene_scale_v as Vector3
	else:
		var scale_scalar := float(scene_scale_v)
		_active_clip_root.scale = Vector3.ONE * scale_scalar


func _pick_animation_name(config: Dictionary) -> StringName:
	if _active_anim_player == null:
		return &""
	var clip_hint := String(config.get("clip_hint", ""))
	var keywords := config.get("keywords", []) as Array
	if not _active_anim_player.get_animation_list().is_empty():
		var clip_names: Array = []
		for clip_name in _active_anim_player.get_animation_list():
			clip_names.append(clip_name)
		return _find_animation_name_from_list(clip_names, clip_hint, keywords)
	for library_name in _active_anim_player.get_animation_library_list():
		var library := _active_anim_player.get_animation_library(library_name)
		if library == null:
			continue
		var prefixed_names: Array[StringName] = []
		for clip_name in library.get_animation_list():
			var full_name := clip_name
			if library_name != &"":
				full_name = StringName("%s/%s" % [String(library_name), String(clip_name)])
			prefixed_names.append(full_name)
		if not prefixed_names.is_empty():
			return _find_animation_name_from_list(prefixed_names, clip_hint, keywords)
	return &""


func _find_animation_name_from_list(
	names: Array, clip_hint: String, keywords: Array
) -> StringName:
	var hint_lower := clip_hint.to_lower()
	if not hint_lower.is_empty():
		for clip_name in names:
			if hint_lower in String(clip_name).to_lower():
				return clip_name
	for keyword_v in keywords:
		var keyword_lower := String(keyword_v).to_lower()
		if keyword_lower.is_empty():
			continue
		for clip_name in names:
			if keyword_lower in String(clip_name).to_lower():
				return clip_name
	for clip_name in names:
		if "reset" not in String(clip_name).to_lower():
			return clip_name
	return names[0] if not names.is_empty() else &""


func _ensure_pivot() -> void:
	if _pivot != null and is_instance_valid(_pivot):
		return
	_pivot = Node3D.new()
	_pivot.name = &"Pivot"
	add_child(_pivot)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node == null:
		return null
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _apply_active_anim_speed() -> void:
	if _active_anim_player == null:
		return
	_active_anim_player.speed_scale = 0.0 if _playback_paused else _playback_speed_scale
