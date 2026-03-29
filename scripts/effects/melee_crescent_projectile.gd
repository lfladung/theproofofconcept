extends Node3D
class_name MeleeCrescentProjectile

@export var lifetime_seconds: float = 0.24
@export var travel_distance: float = 2.8
@export var end_scale_multiplier: Vector3 = Vector3(1.35, 1.1, 1.0)
@export var fallback_pitch_deg: float = -38.0
@export var fallback_yaw_deg: float = 180.0
@export var screen_roll_offset_deg: float = -90.0

var _travel_direction: Vector3 = Vector3.ZERO
var _start_position: Vector3 = Vector3.ZERO
var _start_scale: Vector3 = Vector3.ONE
var _elapsed: float = 0.0
var _materials: Array[Material] = []


func configure(
	start_transform: Transform3D,
	travel_direction: Vector3,
	lifetime: float,
	distance: float,
	start_alpha: float
) -> void:
	global_transform = start_transform
	_start_position = start_transform.origin
	_start_scale = scale
	lifetime_seconds = maxf(0.05, lifetime)
	travel_distance = maxf(0.0, distance)
	var flattened_dir := Vector3(travel_direction.x, 0.0, travel_direction.z)
	if flattened_dir.length_squared() <= 1e-6:
		flattened_dir = -start_transform.basis.z
		flattened_dir.y = 0.0
	_travel_direction = flattened_dir.normalized() if flattened_dir.length_squared() > 1e-6 else Vector3.FORWARD
	_cache_materials()
	_set_effect_alpha(start_alpha)
	_update_camera_aligned_orientation()


func _ready() -> void:
	top_level = true
	if _materials.is_empty():
		_cache_materials()


func _process(delta: float) -> void:
	_elapsed += delta
	var phase := clampf(_elapsed / maxf(lifetime_seconds, 0.001), 0.0, 1.0)
	global_position = _start_position + (_travel_direction * travel_distance * phase)
	scale = Vector3(
		_start_scale.x * lerpf(1.0, end_scale_multiplier.x, phase),
		_start_scale.y * lerpf(1.0, end_scale_multiplier.y, phase),
		_start_scale.z * lerpf(1.0, end_scale_multiplier.z, phase)
	)
	_update_camera_aligned_orientation()
	_set_effect_alpha(pow(1.0 - phase, 1.15))
	if phase >= 1.0:
		queue_free()


func _cache_materials() -> void:
	_materials.clear()
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.material_override is Material:
				var override_mat := mesh_instance.material_override.duplicate(true) as Material
				mesh_instance.material_override = override_mat
				_materials.append(override_mat)
		for child in node.get_children():
			stack.append(child)


func _set_effect_alpha(alpha: float) -> void:
	var safe_alpha := clampf(alpha, 0.0, 1.0)
	for mat in _materials:
		if mat == null:
			continue
		if mat is BaseMaterial3D:
			var base_mat := mat as BaseMaterial3D
			var color := base_mat.albedo_color
			color.a = safe_alpha
			base_mat.albedo_color = color
		elif mat is ShaderMaterial:
			var shader_mat := mat as ShaderMaterial
			shader_mat.set_shader_parameter(&"effect_alpha", safe_alpha)


func _update_camera_aligned_orientation() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		var fallback_basis := Basis.from_euler(
			Vector3(deg_to_rad(fallback_pitch_deg), deg_to_rad(fallback_yaw_deg), 0.0)
		).scaled(scale)
		global_transform = Transform3D(fallback_basis, global_position)
		return
	var view_normal := (camera.global_position - global_position).normalized()
	if view_normal.length_squared() <= 1e-6:
		view_normal = -camera.global_transform.basis.z
	var visual_forward := _travel_direction - view_normal * _travel_direction.dot(view_normal)
	if visual_forward.length_squared() <= 1e-6:
		visual_forward = camera.global_transform.basis.x
	visual_forward = visual_forward.normalized()
	var visual_up := view_normal.cross(visual_forward).normalized()
	var oriented_basis := Basis(visual_forward, visual_up, view_normal).orthonormalized()
	if absf(screen_roll_offset_deg) > 0.001:
		oriented_basis = oriented_basis.rotated(view_normal, deg_to_rad(screen_roll_offset_deg))
	global_transform = Transform3D(oriented_basis.scaled(scale), global_position)
