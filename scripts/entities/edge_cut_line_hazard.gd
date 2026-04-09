class_name EdgeCutLineHazard
extends RefCounted

const EdgeLineTelegraphMeshScript = preload("res://scripts/entities/edge_line_telegraph_mesh.gd")

var hazard_id := 0
var line_start := Vector2.ZERO
var line_end := Vector2.ZERO
var full_half_width := 0.2
var reduced_half_width := 0.2
var telegraph_half_width := 0.14
var telegraph_duration := 0.4
var elapsed := 0.0
var full_damage := 40
var reduced_damage := 40
var debug_label: StringName = &"edge_cut"
var ground_y := 0.06
var blockable := true
var guard_stamina_split_ratio := 0.5
var attack_instance_id := -1
var outline_color := Color(0.0, 0.0, 0.0, 1.0)
var fill_color := Color(1.0, 0.18, 0.12, 0.78)

var _finished := false
var _telegraph_mesh: MeshInstance3D
var _outline_mat: StandardMaterial3D
var _fill_mat: StandardMaterial3D
var _telegraph_meshes: Array[Mesh] = []
var _telegraph_progress_step := -1
var _cached_length := -1.0
var _cached_half_width := -1.0
var _telegraph_steps := 10


func bind_visual(
	visual_world: Node3D,
	outline_color: Color,
	fill_color: Color,
	total_steps: int = 10
) -> void:
	_telegraph_steps = maxi(1, total_steps)
	if visual_world == null:
		return
	if _telegraph_mesh == null or not is_instance_valid(_telegraph_mesh):
		_telegraph_mesh = MeshInstance3D.new()
		_telegraph_mesh.name = &"EdgeCutTelegraph"
		_telegraph_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_telegraph_mesh.visible = false
		visual_world.add_child(_telegraph_mesh)
	self.outline_color = outline_color
	self.fill_color = fill_color
	_outline_mat = EdgeLineTelegraphMeshScript.create_outline_material(self.outline_color)
	_fill_mat = EdgeLineTelegraphMeshScript.create_fill_material(self.fill_color)


func release_visual() -> void:
	if _telegraph_mesh != null and is_instance_valid(_telegraph_mesh):
		_telegraph_mesh.queue_free()
	_telegraph_mesh = null


func configure_from_dict(config: Dictionary) -> void:
	hazard_id = int(config.get("id", hazard_id))
	var start_v: Variant = config.get("s", line_start)
	if start_v is Vector2:
		line_start = start_v as Vector2
	var end_v: Variant = config.get("e", line_end)
	if end_v is Vector2:
		line_end = end_v as Vector2
	full_half_width = maxf(0.02, float(config.get("fw", full_half_width)))
	reduced_half_width = maxf(full_half_width, float(config.get("rw", reduced_half_width)))
	telegraph_half_width = maxf(0.02, float(config.get("tw", telegraph_half_width)))
	telegraph_duration = maxf(0.05, float(config.get("td", telegraph_duration)))
	elapsed = clampf(float(config.get("el", elapsed)), 0.0, telegraph_duration)
	full_damage = maxi(1, int(config.get("fd", full_damage)))
	reduced_damage = maxi(1, int(config.get("rd", reduced_damage)))
	debug_label = StringName(String(config.get("dl", String(debug_label))))
	ground_y = float(config.get("gy", ground_y))
	blockable = bool(config.get("bl", blockable))
	guard_stamina_split_ratio = clampf(
		float(config.get("gs", guard_stamina_split_ratio)),
		0.0,
		1.0
	)
	attack_instance_id = int(config.get("ai", attack_instance_id))
	var outline_v: Variant = config.get("oc", outline_color)
	if outline_v is Color:
		outline_color = outline_v as Color
	var fill_v: Variant = config.get("fc", fill_color)
	if fill_v is Color:
		fill_color = fill_v as Color
	_apply_material_colors()


func to_snapshot() -> Dictionary:
	return {
		"id": hazard_id,
		"s": line_start,
		"e": line_end,
		"fw": full_half_width,
		"rw": reduced_half_width,
		"tw": telegraph_half_width,
		"td": telegraph_duration,
		"el": elapsed,
		"fd": full_damage,
		"rd": reduced_damage,
		"dl": String(debug_label),
		"gy": ground_y,
		"bl": blockable,
		"gs": guard_stamina_split_ratio,
		"ai": attack_instance_id,
		"oc": outline_color,
		"fc": fill_color,
	}


func tick_server(delta: float, owner: Node) -> bool:
	if _finished:
		return true
	elapsed += delta
	if elapsed + 0.0001 < telegraph_duration:
		update_visual()
		return false
	elapsed = telegraph_duration
	if owner != null and owner.has_method(&"_edge_apply_precision_line_damage"):
		owner.call(
			&"_edge_apply_precision_line_damage",
			line_start,
			line_end,
			full_half_width,
			full_damage,
			reduced_half_width,
			reduced_damage,
			debug_label,
			attack_instance_id,
			blockable,
			guard_stamina_split_ratio,
			0.0,
			false
		)
	_finished = true
	_hide_visual()
	return true


func update_visual() -> void:
	if _telegraph_mesh == null or not is_instance_valid(_telegraph_mesh):
		return
	if _finished:
		_hide_visual()
		return
	var length := line_start.distance_to(line_end)
	if not is_equal_approx(length, _cached_length) or not is_equal_approx(telegraph_half_width, _cached_half_width):
		_cached_length = length
		_cached_half_width = telegraph_half_width
		_rebuild_mesh_cache(length, telegraph_half_width)
	var progress := clampf(elapsed / maxf(0.05, telegraph_duration), 0.0, 1.0)
	var dir := line_end - line_start
	if dir.length_squared() <= 0.0001:
		dir = Vector2(0.0, -1.0)
	else:
		dir = dir.normalized()
	_telegraph_mesh.visible = true
	_telegraph_mesh.global_position = Vector3(line_start.x, ground_y, line_start.y)
	_telegraph_mesh.rotation = Vector3(0.0, atan2(dir.x, dir.y), 0.0)
	var progress_step := int(round(progress * float(_telegraph_steps)))
	if progress_step == _telegraph_progress_step:
		return
	_telegraph_progress_step = progress_step
	if progress_step >= 0 and progress_step < _telegraph_meshes.size():
		_telegraph_mesh.mesh = _telegraph_meshes[progress_step]


func is_finished() -> bool:
	return _finished


func _hide_visual() -> void:
	if _telegraph_mesh != null and is_instance_valid(_telegraph_mesh):
		_telegraph_mesh.visible = false
	_telegraph_progress_step = -1


func _rebuild_mesh_cache(length: float, half_width: float) -> void:
	_telegraph_meshes.clear()
	for step in range(_telegraph_steps + 1):
		_telegraph_meshes.append(
			EdgeLineTelegraphMeshScript.build_mesh_for_step(
				step,
				_telegraph_steps,
				length,
				half_width,
				_outline_mat,
				_fill_mat
			)
		)


func _apply_material_colors() -> void:
	if _outline_mat != null:
		_outline_mat.albedo_color = outline_color
	if _fill_mat != null:
		_fill_mat.albedo_color = fill_color
