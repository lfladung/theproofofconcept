class_name GroundAoeTelegraphMesh
extends RefCounted


static func create_outline_material(color: Color) -> StandardMaterial3D:
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


static func build_expanding_circle_mesh(
	progress: float,
	outer_radius: float,
	segments: int,
	outline_material: Material,
	fill_material: Material
) -> Mesh:
	var clamped_progress := clampf(progress, 0.0, 1.0)
	var mesh := ImmediateMesh.new()
	var radius := outer_radius * clamped_progress
	var safe_outer_radius := maxf(outer_radius, 0.1)
	var safe_segments := maxi(12, segments)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, outline_material)
	for segment_index in range(safe_segments):
		var t0 := float(segment_index) / float(safe_segments)
		var t1 := float(segment_index + 1) / float(safe_segments)
		var a0 := lerpf(0.0, TAU, t0)
		var a1 := lerpf(0.0, TAU, t1)
		var p0 := Vector3(sin(a0) * safe_outer_radius, 0.0, cos(a0) * safe_outer_radius)
		var p1 := Vector3(sin(a1) * safe_outer_radius, 0.0, cos(a1) * safe_outer_radius)
		mesh.surface_add_vertex(p0)
		mesh.surface_add_vertex(p1)
	mesh.surface_end()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, fill_material)
	for segment_index in range(safe_segments):
		var t0 := float(segment_index) / float(safe_segments)
		var t1 := float(segment_index + 1) / float(safe_segments)
		var a0 := lerpf(0.0, TAU, t0)
		var a1 := lerpf(0.0, TAU, t1)
		var fp0 := Vector3(sin(a0) * radius, 0.001, cos(a0) * radius)
		var fp1 := Vector3(sin(a1) * radius, 0.001, cos(a1) * radius)
		mesh.surface_add_vertex(Vector3(0.0, 0.001, 0.0))
		mesh.surface_add_vertex(fp0)
		mesh.surface_add_vertex(fp1)
	mesh.surface_end()
	return mesh


static func build_crack_ring_mesh(
	progress: float,
	outer_radius: float,
	segments: int,
	outline_material: Material,
	fill_material: Material
) -> Mesh:
	var clamped_progress := clampf(progress, 0.0, 1.0)
	var mesh := build_expanding_circle_mesh(
		progress,
		outer_radius,
		segments,
		outline_material,
		fill_material
	) as ImmediateMesh
	var safe_outer_radius := maxf(outer_radius, 0.1)
	var inner_radius := safe_outer_radius * maxf(0.05, clamped_progress * 0.82)
	var spoke_count := maxi(6, int(round(float(segments) * 0.33)))
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, outline_material)
	for spoke_index in range(spoke_count):
		var t := float(spoke_index) / float(spoke_count)
		var angle := lerpf(0.0, TAU, t) + sin(t * TAU * 2.0) * 0.14
		var inner := Vector3(sin(angle) * inner_radius * 0.35, 0.002, cos(angle) * inner_radius * 0.35)
		var outer := Vector3(sin(angle) * inner_radius, 0.002, cos(angle) * inner_radius)
		mesh.surface_add_vertex(inner)
		mesh.surface_add_vertex(outer)
	mesh.surface_end()
	return mesh
