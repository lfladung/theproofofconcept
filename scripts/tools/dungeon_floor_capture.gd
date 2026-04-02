extends Node

const SMALL_DUNGEON_SCENE := preload("res://dungeon/game/small_dungeon.tscn")
const DEFAULT_WINDOW_SIZE := Vector2i(1600, 900)
const DEFAULT_CAPTURE_ROOT := "res://logs/captures/floors"
const DEFAULT_BOOT_TIMEOUT_SECONDS := 20.0
const DEFAULT_SETTLE_SECONDS := 0.6

var _dungeon: Node = null
var _capture_camera: Camera3D = null
var _window_size := DEFAULT_WINDOW_SIZE
var _output_dir := ""
var _report_path := ""
var _boot_timeout_seconds := DEFAULT_BOOT_TIMEOUT_SECONDS
var _settle_seconds := DEFAULT_SETTLE_SECONDS
var _room_limit := 6
var _room_names: Array[String] = []
var _camera_yaw_deg := 180.0
var _camera_pitch_deg := -72.0
var _camera_distance := 160.0
var _camera_projection_mode := "orthogonal"
var _camera_size_multiplier := 0.7
var _camera_height_offset := 0.0
var _timestamp_tag := ""


func _ready() -> void:
	_parse_user_args()
	_prepare_output_paths()
	_configure_window()
	_spawn_dungeon()
	_capture_camera = _create_capture_camera()
	var floor_ready := await _wait_for_floor_generated(_boot_timeout_seconds)
	if not floor_ready:
		_finish_with_error("Timed out waiting for small_dungeon floor generation.")
		return
	await _wait_seconds(_settle_seconds)
	var rooms := _target_rooms()
	if rooms.is_empty():
		_finish_with_error("No authored rooms were available for floor capture.")
		return
	var captures: Array[Dictionary] = []
	for room in rooms:
		var capture := await _capture_room(room)
		if not capture.is_empty():
			captures.append(capture)
	var summary := {
		"scene": "res://dungeon/game/small_dungeon.tscn",
		"timestamp_unix": Time.get_unix_time_from_system(),
		"window_size": {"x": _window_size.x, "y": _window_size.y},
		"output_dir": ProjectSettings.globalize_path(_output_dir),
		"captures": captures,
	}
	_write_summary(summary)
	_print_summary(summary)
	get_tree().quit(0)


func _parse_user_args() -> void:
	for raw_arg in OS.get_cmdline_user_args():
		if not raw_arg.begins_with("--"):
			continue
		var arg := raw_arg.substr(2)
		var parts := arg.split("=", false, 1)
		var key := parts[0]
		var value := ""
		if parts.size() > 1:
			value = parts[1]
		match key:
			"output_dir":
				_output_dir = value
			"report_path":
				_report_path = value
			"boot_timeout":
				_boot_timeout_seconds = maxf(1.0, value.to_float())
			"settle_seconds":
				_settle_seconds = maxf(0.05, value.to_float())
			"room_limit":
				_room_limit = maxi(1, value.to_int())
			"room_names":
				_room_names = []
				for room_name in value.split(",", false):
					var trimmed := room_name.strip_edges()
					if not trimmed.is_empty():
						_room_names.append(trimmed)
			"camera_yaw":
				_camera_yaw_deg = value.to_float()
			"camera_pitch":
				_camera_pitch_deg = value.to_float()
			"camera_distance":
				_camera_distance = maxf(1.0, value.to_float())
			"camera_projection":
				_camera_projection_mode = value.strip_edges().to_lower()
			"camera_size_multiplier":
				_camera_size_multiplier = maxf(0.1, value.to_float())
			"camera_height_offset":
				_camera_height_offset = value.to_float()
			"window_width":
				_window_size.x = maxi(320, value.to_int())
			"window_height":
				_window_size.y = maxi(240, value.to_int())


func _prepare_output_paths() -> void:
	_timestamp_tag = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	if _output_dir.is_empty():
		_output_dir = "%s/%s" % [DEFAULT_CAPTURE_ROOT, _timestamp_tag]
	if _report_path.is_empty():
		_report_path = "%s/report.json" % _output_dir
	var abs_dir := ProjectSettings.globalize_path(_output_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)


func _configure_window() -> void:
	var window := get_window()
	if window == null:
		return
	window.size = _window_size
	window.mode = Window.MODE_WINDOWED
	window.title = "Dungeon Floor Capture"


func _spawn_dungeon() -> void:
	_dungeon = SMALL_DUNGEON_SCENE.instantiate()
	if _dungeon == null:
		return
	_dungeon.set("show_fps_counter", false)
	_dungeon.set("show_combat_debug_overlay", false)
	_dungeon.set("authored_room_visual_streaming_enabled", false)
	_dungeon.set("prespawn_encounter_mobs", false)
	add_child(_dungeon)
	var canvas_layer := _dungeon.get_node_or_null("CanvasLayer") as CanvasLayer
	if canvas_layer != null:
		canvas_layer.visible = false


func _create_capture_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "FloorCaptureCamera"
	camera.current = true
	camera.near = 0.05
	if _camera_projection_mode == "orthographic" or _camera_projection_mode == "orthogonal":
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 80.0
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 38.0
	add_child(camera)
	return camera


func _wait_for_floor_generated(timeout_seconds: float) -> bool:
	if _dungeon == null:
		return false
	var deadline_usec := Time.get_ticks_usec() + int(timeout_seconds * 1000000.0)
	while Time.get_ticks_usec() < deadline_usec:
		await get_tree().process_frame
		if bool(_dungeon.get("_has_generated_floor")):
			return true
	return false


func _wait_seconds(seconds: float) -> void:
	var end_usec := Time.get_ticks_usec() + int(seconds * 1000000.0)
	while Time.get_ticks_usec() < end_usec:
		await get_tree().process_frame


func _target_rooms() -> Array:
	if _dungeon == null:
		return []
	var rooms_root := _dungeon.get("_rooms_root") as Node
	if rooms_root == null:
		return []
	var all_rooms: Array = []
	for child in rooms_root.get_children():
		if child is RoomBase:
			var room := child as RoomBase
			if room.authored_layout != null:
				all_rooms.append(room)
	all_rooms.sort_custom(func(a: RoomBase, b: RoomBase) -> bool: return String(a.name) < String(b.name))
	if not _room_names.is_empty():
		var requested: Array = []
		for target_name in _room_names:
			for room_value in all_rooms:
				var room := room_value as RoomBase
				if room != null and String(room.name) == target_name:
					requested.append(room)
					break
		return requested
	var limited: Array = []
	for room_value in all_rooms:
		limited.append(room_value)
		if limited.size() >= _room_limit:
			break
	return limited


func _capture_room(room: RoomBase) -> Dictionary:
	if room == null or _capture_camera == null:
		return {}
	var world_rect := _room_world_rect(room)
	_position_camera_for_rect(world_rect)
	var settle_stats := await _sample_frames(_settle_seconds)
	var screenshot_path := "%s/%s_%s.png" % [
		_output_dir,
		_sanitize_filename(String(room.name)),
		String(room.get_meta(&"runtime_floor_theme", &"unknown")),
	]
	var ok := await _save_viewport_screenshot(screenshot_path)
	if not ok:
		return {}
	return {
		"room_name": String(room.name),
		"room_scene": room.scene_file_path,
		"floor_theme": String(room.get_meta(&"runtime_floor_theme", &"")),
		"screenshot_path": ProjectSettings.globalize_path(screenshot_path),
		"room_rect": {
			"x": world_rect.position.x,
			"y": world_rect.position.y,
			"w": world_rect.size.x,
			"h": world_rect.size.y,
		},
		"settle_profile": settle_stats,
	}


func _room_world_rect(room: RoomBase) -> Rect2:
	var local_rect := room.get_room_rect_world()
	return Rect2(room.global_position - local_rect.size * 0.5, local_rect.size)


func _position_camera_for_rect(world_rect: Rect2) -> void:
	var target := Vector3(world_rect.get_center().x, _camera_height_offset, world_rect.get_center().y)
	if _capture_camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		_capture_camera.size = maxf(world_rect.size.x, world_rect.size.y) * _camera_size_multiplier
	var yaw_rad := deg_to_rad(_camera_yaw_deg)
	var pitch_rad := deg_to_rad(_camera_pitch_deg)
	var horizontal := _camera_distance * cos(pitch_rad)
	var camera_offset := Vector3(
		sin(yaw_rad) * horizontal,
		_camera_distance * sin(-pitch_rad),
		cos(yaw_rad) * horizontal
	)
	_capture_camera.global_position = target + camera_offset
	_capture_camera.look_at(target, Vector3.UP)


func _sample_frames(seconds: float) -> Dictionary:
	var samples: Array[float] = []
	var start_usec := Time.get_ticks_usec()
	var end_usec := start_usec + int(seconds * 1000000.0)
	var last_usec := start_usec
	while Time.get_ticks_usec() < end_usec:
		await get_tree().process_frame
		var now_usec := Time.get_ticks_usec()
		samples.append(float(now_usec - last_usec) / 1000.0)
		last_usec = now_usec
	return _bucket_stats(samples)


func _bucket_stats(samples_ms: Array[float]) -> Dictionary:
	if samples_ms.is_empty():
		return {
			"frames": 0,
			"avg_ms": 0.0,
			"avg_fps": 0.0,
			"p95_ms": 0.0,
			"max_ms": 0.0,
		}
	var total_ms := 0.0
	var max_ms := 0.0
	for sample in samples_ms:
		total_ms += sample
		max_ms = maxf(max_ms, sample)
	var sorted_samples := samples_ms.duplicate()
	sorted_samples.sort()
	var p95_index := clampi(int(floor(float(sorted_samples.size() - 1) * 0.95)), 0, sorted_samples.size() - 1)
	var avg_ms := total_ms / float(samples_ms.size())
	return {
		"frames": samples_ms.size(),
		"avg_ms": snapped(avg_ms, 0.01),
		"avg_fps": snapped(1000.0 / avg_ms if avg_ms > 0.001 else 0.0, 0.01),
		"p95_ms": snapped(float(sorted_samples[p95_index]), 0.01),
		"max_ms": snapped(max_ms, 0.01),
	}


func _save_viewport_screenshot(path: String) -> bool:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("[FloorCapture] Failed to read viewport image.")
		return false
	var output_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var err := image.save_png(output_path)
	if err != OK:
		push_error("[FloorCapture] Failed to save screenshot to %s (err=%d)" % [output_path, err])
		return false
	print("[FloorCapture] Saved %s" % output_path)
	return true


func _write_summary(summary: Dictionary) -> void:
	var output_path := ProjectSettings.globalize_path(_report_path)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_warning("[FloorCapture] Failed to write summary to %s" % output_path)
		return
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	print("[FloorCapture] Wrote %s" % output_path)


func _print_summary(summary: Dictionary) -> void:
	print("[FloorCapture] summary begin")
	for capture_value in summary.get("captures", []):
		var capture := capture_value as Dictionary
		var profile := capture.get("settle_profile", {}) as Dictionary
		print(
			"[FloorCapture] room=%s theme=%s avg_ms=%s p95_ms=%s max_ms=%s file=%s"
			% [
				String(capture.get("room_name", "")),
				String(capture.get("floor_theme", "")),
				float(profile.get("avg_ms", 0.0)),
				float(profile.get("p95_ms", 0.0)),
				float(profile.get("max_ms", 0.0)),
				String(capture.get("screenshot_path", "")),
			]
		)
	print("[FloorCapture] summary end")


func _sanitize_filename(value: String) -> String:
	var out := value.strip_edges().replace(" ", "_")
	for invalid in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		out = out.replace(invalid, "_")
	return out


func _finish_with_error(message: String) -> void:
	push_error("[FloorCapture] %s" % message)
	get_tree().quit(1)
