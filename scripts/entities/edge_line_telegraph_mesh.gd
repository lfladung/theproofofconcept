class_name EdgeLineTelegraphMesh
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
	line_length: float,
	line_half_width: float,
	outline_material: Material,
	fill_material: Material
) -> Mesh:
	var safe_steps := maxi(1, total_steps)
	var fill_ratio := float(clampi(progress_step, 0, safe_steps)) / float(safe_steps)
	var safe_length := maxf(0.1, line_length)
	var safe_half_width := maxf(0.02, line_half_width)
	var fill_length := safe_length * fill_ratio
	var mesh := ImmediateMesh.new()
	var outline := [
		Vector3(-safe_half_width, 0.0, 0.0),
		Vector3(safe_half_width, 0.0, 0.0),
		Vector3(safe_half_width, 0.0, safe_length),
		Vector3(-safe_half_width, 0.0, safe_length),
	]
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, outline_material)
	for pair in [[0, 1], [1, 2], [2, 3], [3, 0]]:
		mesh.surface_add_vertex(outline[pair[0]] as Vector3)
		mesh.surface_add_vertex(outline[pair[1]] as Vector3)
	mesh.surface_end()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, fill_material)
	var fill_quad := [
		Vector3(-safe_half_width * 0.78, 0.001, 0.0),
		Vector3(safe_half_width * 0.78, 0.001, 0.0),
		Vector3(safe_half_width * 0.78, 0.001, fill_length),
		Vector3(-safe_half_width * 0.78, 0.001, fill_length),
	]
	for tri in [[0, 1, 2], [0, 2, 3]]:
		mesh.surface_add_vertex(fill_quad[tri[0]] as Vector3)
		mesh.surface_add_vertex(fill_quad[tri[1]] as Vector3)
		mesh.surface_add_vertex(fill_quad[tri[2]] as Vector3)
	mesh.surface_end()
	return mesh
