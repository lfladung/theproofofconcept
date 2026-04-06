extends RefCounted
class_name MassCombatVfx

## Short 3D readouts for Mass pillar knockback payoffs (planar xz ↔ 3D world).
enum Kind { WALL_SLAM = 0, CARRIER_CLASH = 1, SHOCKWAVE = 2 }


static func _ground_y_for_kind(kind: int) -> float:
	match kind:
		Kind.SHOCKWAVE:
			return 0.08
		Kind.WALL_SLAM:
			return 0.22
		_:
			return 0.35


static func play_on_visual_world(vw: Node3D, kind: int, pos2: Vector2, dir2: Vector2, param: float) -> void:
	if vw == null:
		return
	var root := Node3D.new()
	root.name = &"MassCombatVfx"
	vw.add_child(root)
	root.global_position = Vector3(pos2.x, _ground_y_for_kind(kind), pos2.y)
	match kind:
		Kind.SHOCKWAVE:
			_start_shockwave(root, maxf(4.0, param))
		Kind.WALL_SLAM:
			_start_wall_slam(root, dir2)
		Kind.CARRIER_CLASH:
			_start_carrier_clash(root, dir2, param)
		_:
			root.queue_free()


static func _start_shockwave(root: Node3D, target_radius: float) -> void:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.35, target_radius * 0.04)
	torus.outer_radius = torus.inner_radius + maxf(0.12, target_radius * 0.05)
	mi.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.55, 0.18, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.72, 0.28, 1.0)
	mat.emission_energy_multiplier = 2.4
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi)
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var tween := root.create_tween()
	tween.set_parallel(true)
	var dur := 0.42
	tween.tween_property(mi, "scale", Vector3.ONE * maxf(0.15, target_radius * 0.38), dur).from(
		Vector3.ONE * 0.08
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, dur).set_delay(0.08)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, dur).set_delay(0.12)
	tween.chain().tween_callback(root.queue_free)


static func _start_wall_slam(root: Node3D, wall_normal2: Vector2) -> void:
	var n2 := wall_normal2.normalized() if wall_normal2.length_squared() > 1e-6 else Vector2(0.0, 1.0)
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.85
	cyl.bottom_radius = 1.05
	cyl.height = 0.28
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.35, 0.12, 0.62)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.2, 1.0)
	mat.emission_energy_multiplier = 3.2
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi)
	var fwd := Vector3(n2.x, 0.0, n2.y)
	mi.look_at(root.global_position + fwd, Vector3.UP)
	var tween := root.create_tween()
	tween.set_parallel(true)
	var dur := 0.36
	tween.tween_property(mi, "scale", Vector3(1.35, 1.0, 1.35), dur * 0.35).from(Vector3(0.2, 0.4, 0.2)).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, dur).set_delay(0.05)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, dur).set_delay(0.08)
	tween.chain().tween_callback(root.queue_free)


static func _start_carrier_clash(root: Node3D, dir2: Vector2, _separation: float) -> void:
	var d := dir2.normalized() if dir2.length_squared() > 1e-6 else Vector2(0.0, -1.0)
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.55
	sph.height = 1.1
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.35, 0.75, 1.0, 0.58)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.9, 1.0, 1.0)
	mat.emission_energy_multiplier = 2.8
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi)
	root.look_at(root.global_position + Vector3(d.x, 0.0, d.y), Vector3.UP)
	var tween := root.create_tween()
	tween.set_parallel(true)
	var dur := 0.28
	tween.tween_property(mi, "scale", Vector3.ONE * 1.65, dur * 0.5).from(Vector3.ONE * 0.25).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, dur)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, dur).set_delay(0.04)
	tween.chain().tween_callback(root.queue_free)
