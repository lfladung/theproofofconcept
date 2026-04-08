class_name FlowTelegraphArrowMesh
extends RefCounted


static func create_outline_material(color: Color = Color(0.0, 0.0, 0.0, 1.0)) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func create_fill_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func build_mesh_for_step(
	progress_step: int,
	total_steps: int,
	arrow_length: float,
	arrow_head_length: float,
	arrow_half_width: float,
	outline_material: Material,
	fill_material: Material
) -> Mesh:
	var safe_steps := maxi(1, total_steps)
	var fill_ratio := float(progress_step) / float(safe_steps)
	var shaft_end_z := maxf(0.1, arrow_length - arrow_head_length)
	var tip_z := arrow_length
	var half_width := arrow_half_width
	var head_half_width := arrow_half_width * 1.8
	var fill_tip_z := arrow_length * fill_ratio
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, outline_material)
	for pair in [
		[Vector3(half_width, 0.0, 0.0), Vector3(half_width, 0.0, shaft_end_z)],
		[Vector3(half_width, 0.0, shaft_end_z), Vector3(head_half_width, 0.0, shaft_end_z)],
		[Vector3(head_half_width, 0.0, shaft_end_z), Vector3(0.0, 0.0, tip_z)],
		[Vector3(0.0, 0.0, tip_z), Vector3(-head_half_width, 0.0, shaft_end_z)],
		[Vector3(-head_half_width, 0.0, shaft_end_z), Vector3(-half_width, 0.0, shaft_end_z)],
		[Vector3(-half_width, 0.0, shaft_end_z), Vector3(-half_width, 0.0, 0.0)],
		[Vector3(-half_width, 0.0, 0.0), Vector3(half_width, 0.0, 0.0)],
	]:
		mesh.surface_add_vertex(pair[0] as Vector3)
		mesh.surface_add_vertex(pair[1] as Vector3)
	mesh.surface_end()

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, fill_material)
	for vertex in [
		Vector3(half_width * 0.55, 0.001, 0.0),
		Vector3(-half_width * 0.55, 0.001, 0.0),
		Vector3(0.0, 0.001, fill_tip_z),
	]:
		mesh.surface_add_vertex(vertex as Vector3)
	mesh.surface_end()
	return mesh
