extends Node3D

const PLAYER_VISUAL_SCENE_PATH := "res://scenes/visuals/player_visual.tscn"

var _player_visual: Node3D = null
var _mode: String = "idle"
var _camera_yaw_deg: float = 180.0
var _camera_pitch_deg: float = -38.0
var _camera_distance: float = 150.0
var _camera_height_offset: float = 0.0
var _auto_distance: bool = false
var _camera_projection_mode: String = "orthogonal"
var _camera_size: float = 50.0
var _use_bounds_target: bool = false
var _distance_multiplier: float = 1.25
var _screenshot_path: String = ""
var _screenshot_time: float = 0.75
var _auto_quit: bool = true
var _attack_interval_seconds: float = 1.3
var _elapsed: float = 0.0
var _captured: bool = false
var _next_attack_time: float = 0.0
var _camera_target_override: Vector3 = Vector3.ZERO
var _camera_target_ready: bool = false
var _bounds_size: Vector3 = Vector3.ZERO
var _armor_item: String = ""
var _player_yaw_deg: float = 0.0


func _ready() -> void:
	_parse_user_args()
	_spawn_player_visual()
	_compute_camera_target_from_visual_bounds()
	_configure_camera()
	_configure_lights()
	_apply_mode_immediate()
	print(
		"[Capture] mode=%s screenshot_path=%s yaw=%.2f pitch=%.2f dist=%.2f"
		% [_mode, _screenshot_path, _camera_yaw_deg, _camera_pitch_deg, _camera_distance]
	)


func _process(delta: float) -> void:
	_elapsed += delta
	if _player_visual == null:
		return

	match _mode:
		"walk":
			_player_visual.call("set_locomotion_from_planar_speed", 1.0, 1.0)
		"attack":
			_player_visual.call("set_locomotion_from_planar_speed", 0.0, 1.0)
			if _elapsed >= _next_attack_time:
				_player_visual.call("try_play_attack_for_mode", StringName("melee"))
				_next_attack_time = _elapsed + _attack_interval_seconds
		"defend":
			_player_visual.call("set_defending_state", true)
		_:
			_player_visual.call("set_locomotion_from_planar_speed", 0.0, 1.0)

	if not _captured and not _screenshot_path.is_empty() and _elapsed >= _screenshot_time:
		_capture_screenshot()


func _parse_user_args() -> void:
	for raw_arg in OS.get_cmdline_user_args():
		if not raw_arg.begins_with("--"):
			continue
		var arg: String = raw_arg.substr(2)
		var parts: PackedStringArray = arg.split("=", false, 1)
		var key: String = parts[0]
		var value: String = ""
		if parts.size() > 1:
			value = parts[1]
		match key:
			"mode":
				_mode = value.strip_edges().to_lower()
			"camera_yaw":
				_camera_yaw_deg = value.to_float()
			"camera_pitch":
				_camera_pitch_deg = value.to_float()
			"camera_distance":
				_camera_distance = maxf(0.5, value.to_float())
			"camera_height_offset":
				_camera_height_offset = value.to_float()
			"auto_distance":
				_auto_distance = _parse_bool(value)
			"camera_projection":
				_camera_projection_mode = value.strip_edges().to_lower()
			"camera_size":
				_camera_size = maxf(0.1, value.to_float())
			"use_bounds_target":
				_use_bounds_target = _parse_bool(value)
			"distance_multiplier":
				_distance_multiplier = maxf(0.1, value.to_float())
			"screenshot_path":
				_screenshot_path = value
			"screenshot_time":
				_screenshot_time = maxf(0.05, value.to_float())
			"auto_quit":
				_auto_quit = _parse_bool(value)
			"attack_interval":
				_attack_interval_seconds = maxf(0.15, value.to_float())
			"armor_item":
				_armor_item = value.strip_edges()
			"player_yaw":
				_player_yaw_deg = value.to_float()


func _parse_bool(value: String) -> bool:
	var v: String = value.strip_edges().to_lower()
	return v == "1" or v == "true" or v == "yes" or v == "on"


func _spawn_player_visual() -> void:
	var player_scene: PackedScene = load(PLAYER_VISUAL_SCENE_PATH) as PackedScene
	if player_scene == null:
		push_error("[Capture] Could not load %s" % PLAYER_VISUAL_SCENE_PATH)
		return
	_player_visual = player_scene.instantiate() as Node3D
	if _player_visual == null:
		push_error("[Capture] Failed to instantiate PlayerVisual")
		return
	add_child(_player_visual)
	_player_visual.global_position = Vector3.ZERO
	_player_visual.rotation = Vector3.ZERO
	_player_visual.rotation_degrees.y = _player_yaw_deg

	# Prevent preview-only behavior from affecting runtime captures.
	_player_visual.set("preview_in_editor", false)
	_player_visual.set("editor_preview_apply", false)
	if not _armor_item.is_empty():
		_player_visual.call("set_armor_visual_item", StringName(_armor_item))


func _configure_camera() -> void:
	var camera: Camera3D = Camera3D.new()
	camera.name = "CaptureCamera"
	camera.current = true
	camera.near = 0.02
	if _camera_projection_mode == "orthogonal" or _camera_projection_mode == "ortho":
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = _camera_size
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 32.0
	add_child(camera)

	var target: Vector3 = Vector3(0.0, _camera_height_offset, 0.0)
	if _camera_target_ready and _use_bounds_target:
		target = _camera_target_override + Vector3(0.0, _camera_height_offset, 0.0)
	var effective_distance: float = _camera_distance
	if (
		_auto_distance
		and _camera_target_ready
		and camera.projection == Camera3D.PROJECTION_PERSPECTIVE
	):
		var frame_radius: float = maxf(_bounds_size.x, maxf(_bounds_size.y, _bounds_size.z)) * 0.5
		var fov_rad: float = deg_to_rad(maxf(1.0, camera.fov))
		var fit_distance: float = frame_radius / tan(fov_rad * 0.5)
		effective_distance = maxf(fit_distance * _distance_multiplier, 0.5)
	var yaw_rad: float = deg_to_rad(_camera_yaw_deg)
	var pitch_rad: float = deg_to_rad(_camera_pitch_deg)
	var horizontal: float = effective_distance * cos(pitch_rad)
	var camera_pos: Vector3 = Vector3(
		sin(yaw_rad) * horizontal,
		effective_distance * sin(-pitch_rad),
		cos(yaw_rad) * horizontal
	)
	camera.global_position = target + camera_pos
	camera.look_at(target, Vector3.UP)


func _compute_camera_target_from_visual_bounds() -> void:
	if _player_visual == null:
		return
	var stack: Array[Node] = [_player_visual]
	var has_bounds: bool = false
	var min_p: Vector3 = Vector3.ZERO
	var max_p: Vector3 = Vector3.ZERO
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n as MeshInstance3D
			var mesh: Mesh = mi.mesh
			if mesh != null:
				var aabb_local: AABB = mesh.get_aabb()
				var corners: Array[Vector3] = [
					aabb_local.position,
					aabb_local.position + Vector3(aabb_local.size.x, 0.0, 0.0),
					aabb_local.position + Vector3(0.0, aabb_local.size.y, 0.0),
					aabb_local.position + Vector3(0.0, 0.0, aabb_local.size.z),
					aabb_local.position + Vector3(aabb_local.size.x, aabb_local.size.y, 0.0),
					aabb_local.position + Vector3(aabb_local.size.x, 0.0, aabb_local.size.z),
					aabb_local.position + Vector3(0.0, aabb_local.size.y, aabb_local.size.z),
					aabb_local.position + aabb_local.size
				]
				for c in corners:
					var world_p: Vector3 = mi.global_transform * c
					if not has_bounds:
						min_p = world_p
						max_p = world_p
						has_bounds = true
					else:
						min_p = Vector3(minf(min_p.x, world_p.x), minf(min_p.y, world_p.y), minf(min_p.z, world_p.z))
						max_p = Vector3(maxf(max_p.x, world_p.x), maxf(max_p.y, world_p.y), maxf(max_p.z, world_p.z))
		for c in n.get_children():
			stack.append(c)
	if not has_bounds:
		return
	var center: Vector3 = (min_p + max_p) * 0.5
	var size: Vector3 = max_p - min_p
	_bounds_size = size
	_camera_target_override = center + Vector3(0.0, size.y * 0.08, 0.0)
	_camera_target_ready = true


func _configure_lights() -> void:
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.light_energy = 2.1
	key_light.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	add_child(key_light)

	var fill_light: DirectionalLight3D = DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.light_energy = 0.9
	fill_light.rotation_degrees = Vector3(-18.0, -145.0, 0.0)
	add_child(fill_light)


func _apply_mode_immediate() -> void:
	if _player_visual == null:
		return
	_player_visual.call("set_downed_state", false)
	_player_visual.call("set_defending_state", false)
	match _mode:
		"walk":
			_player_visual.call("set_locomotion_from_planar_speed", 1.0, 1.0)
		"attack":
			_player_visual.call("set_locomotion_from_planar_speed", 0.0, 1.0)
			_player_visual.call("try_play_attack_for_mode", StringName("melee"))
			_next_attack_time = _attack_interval_seconds
		"defend":
			_player_visual.call("set_defending_state", true)
		_:
			_player_visual.call("set_locomotion_from_planar_speed", 0.0, 1.0)


func _capture_screenshot() -> void:
	_captured = true
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		push_error("[Capture] Failed to read viewport image.")
		if _auto_quit:
			get_tree().quit(1)
		return

	var target_path: String = _normalize_output_path(_screenshot_path)
	if target_path.is_empty():
		push_error("[Capture] Empty screenshot path.")
		if _auto_quit:
			get_tree().quit(1)
		return
	_ensure_directory_for_file(target_path)
	var err: Error = image.save_png(target_path)
	if err != OK:
		push_error("[Capture] Failed to save screenshot to %s (err=%d)" % [target_path, err])
		if _auto_quit:
			get_tree().quit(1)
		return
	print("[Capture] Screenshot saved: %s" % target_path)
	if _auto_quit:
		get_tree().quit(0)


func _normalize_output_path(path: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	return ProjectSettings.globalize_path(path)


func _ensure_directory_for_file(path: String) -> void:
	var dir_path: String = path.get_base_dir()
	if dir_path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(dir_path)
