@tool
extends Node3D

# Clean first-pass abyss pillar controller for the menu SubViewport scene.
# - GPUParticles3D nodes own amount, lifetime, preprocess, draw-pass mesh, and emission toggle.
# - ParticleProcessMaterial resources own motion and lifetime behaviour such as direction,
#   spread, velocity, damping, orbit, radial/tangential acceleration, scale, and color ramp.

const DEFAULT_ABYSS_TEXTURE := preload("res://art/menu/theabyss.png")
const RingSpiralShader := preload("res://shaders/ui/menu/ring_spiral.gdshader")
const MENU_AMBIENT_COLOR := Color(0.56, 0.54, 0.68, 1.0)
const MENU_AMBIENT_ENERGY := 0.32

@export_group("Placement")
@export_range(-20.0, 20.0, 0.1) var pillar_vertical_offset: float = -5.8
# Match pillar Y so rings share the same column (was offset, which read as a separate effect).
@export_range(-20.0, 20.0, 0.1) var ring_vertical_offset: float = -5.8
@export_range(-20.0, 20.0, 0.1) var fog_vertical_offset: float = -5.85

@export_group("Background Plane")
# When false (default), the 3D plane is hidden so MenuBackgroundVfx's 2D PitBackground is the only abyss art (no double image).
@export var show_background_plane: bool = false
@export var background_texture: Texture2D = DEFAULT_ABYSS_TEXTURE
@export var background_plane_size: Vector2 = Vector2(26.0, 38.0)
@export var background_plane_position: Vector3 = Vector3(0.0, 1.0, -14.0)
@export_range(0.0, 1.0, 0.01) var background_plane_alpha: float = 1.0

@export_group("Shared Motion")
# One slow swirl on the whole pillar reads more cohesive than mismatched child spins.
@export_range(0.0, 8.0, 0.1) var root_rotation_speed_deg: float = 1.0
@export_range(0.0, 8.0, 0.1) var core_spin_speed_deg: float = 0.0
@export_range(0.0, 8.0, 0.1) var hero_spin_speed_deg: float = 0.0

@export_group("Pillar Core")
# High orbit/tangential values smear particles into spiral ribbons (reads like a mesh). Keep low for a speckly column; use PillarRoot rotation for slow swirl.
@export_range(100, 3000, 1) var core_amount: int = 1050
@export_range(1.0, 12.0, 0.1) var core_lifetime: float = 6.0
@export_range(0.1, 8.0, 0.1) var core_emission_radius: float = 1.15
@export_range(0.1, 16.0, 0.1) var core_emission_height: float = 6.6
@export_range(0.1, 45.0, 0.1) var core_spread: float = 4.2
@export_range(0.0, 16.0, 0.1) var core_velocity_min: float = 4.1
@export_range(0.0, 16.0, 0.1) var core_velocity_max: float = 8.0
@export_range(0.001, 0.25, 0.001) var core_particle_size: float = 0.023
@export_range(0.0, 1.0, 0.01) var core_randomness: float = 0.3
@export_range(0.0, 1.0, 0.01) var core_particle_alpha: float = 0.34
@export_range(0.0, 4.0, 0.01) var core_emission_energy: float = 1.28
@export_range(0.5, 4.0, 0.05) var core_disc_falloff: float = 1.55
@export_range(-16.0, 16.0, 0.1) var core_orbit_velocity_min: float = 0.05
@export_range(-16.0, 16.0, 0.1) var core_orbit_velocity_max: float = 0.14
@export_range(-16.0, 16.0, 0.1) var core_tangential_accel_min: float = 0.08
@export_range(-16.0, 16.0, 0.1) var core_tangential_accel_max: float = 0.22
@export_range(-16.0, 16.0, 0.1) var core_radial_accel_min: float = -0.55
@export_range(-16.0, 16.0, 0.1) var core_radial_accel_max: float = -0.18

@export_group("Hero Sparkles")
@export_range(10, 400, 1) var hero_amount: int = 88
@export_range(1.0, 16.0, 0.1) var hero_lifetime: float = 8.0
@export_range(0.1, 8.0, 0.1) var hero_emission_radius: float = 0.52
@export_range(0.1, 16.0, 0.1) var hero_emission_height: float = 6.0
@export_range(0.1, 60.0, 0.1) var hero_spread: float = 5.2
@export_range(0.0, 16.0, 0.1) var hero_velocity_min: float = 4.8
@export_range(0.0, 16.0, 0.1) var hero_velocity_max: float = 7.8
@export_range(0.001, 0.5, 0.001) var hero_particle_size: float = 0.09
@export_range(0.0, 1.0, 0.01) var hero_randomness: float = 0.34
@export_range(0.0, 1.0, 0.01) var hero_particle_alpha: float = 0.48
@export_range(0.0, 4.0, 0.01) var hero_emission_energy: float = 1.95
@export var hero_pulse_enabled: bool = true
@export_range(0.05, 1.0, 0.01) var hero_base_amount_ratio: float = 0.88
@export_range(0.0, 0.3, 0.01) var hero_pulse_strength: float = 0.08
@export_range(0.05, 3.0, 0.01) var hero_pulse_speed: float = 0.22

@export_group("Ring Spiral")
@export_range(2, 5, 1) var ring_layer_count: int = 4
@export_range(0.5, 12.0, 0.1) var ring_stack_height: float = 5.6
@export_range(0.1, 12.0, 0.1) var ring_base_diameter: float = 3.35
@export_range(0.1, 12.0, 0.1) var ring_top_diameter: float = 1.45
@export_range(0.01, 3.0, 0.01) var ring_drift_speed: float = 0.18
@export_range(0.0, 1.0, 0.01) var ring_opacity: float = 0.095
@export_range(0.0, 2.0, 0.01) var ring_emission_strength: float = 0.16
@export_range(0.0, 1.0, 0.01) var ring_inner_radius: float = 0.72
@export_range(0.0, 1.0, 0.01) var ring_outer_radius: float = 0.93
@export_range(0.001, 0.25, 0.001) var ring_edge_softness: float = 0.05
@export_range(1.0, 24.0, 0.1) var ring_arc_density_min: float = 5.2
@export_range(1.0, 24.0, 0.1) var ring_arc_density_max: float = 8.5
@export_range(0.0, 1.0, 0.01) var ring_arc_balance: float = 0.42
@export_range(0.001, 0.5, 0.001) var ring_arc_softness: float = 0.28
@export_range(0.0, 1.0, 0.01) var ring_arc_segment_mix: float = 0.2
@export_range(0.0, 1.0, 0.01) var ring_jitter: float = 0.008

@export_group("Fog")
@export var fog_enabled: bool = true
@export_range(10, 800, 1) var fog_amount: int = 190
@export_range(1.0, 20.0, 0.1) var fog_lifetime: float = 10.0
@export_range(0.1, 20.0, 0.1) var fog_emission_radius: float = 2.65
@export_range(0.1, 20.0, 0.1) var fog_emission_height: float = 3.0
@export_range(0.1, 180.0, 0.1) var fog_spread: float = 14.0
@export_range(0.0, 8.0, 0.1) var fog_velocity_min: float = 0.12
@export_range(0.0, 8.0, 0.1) var fog_velocity_max: float = 0.55
@export_range(0.01, 4.0, 0.01) var fog_particle_size: float = 1.85
@export_range(0.0, 1.0, 0.001) var fog_particle_alpha: float = 0.055
@export_range(0.0, 1.0, 0.001) var fog_emission_energy: float = 0.04

@export_group("Renderer")
@export var use_fixed_fps: bool = false
@export_range(15, 120, 1) var fixed_fps_value: int = 30
@export var warm_start_particles: bool = true
@export_range(0.5, 6.0, 0.1) var warm_start_factor: float = 2.0

@onready var _pillar_core: GPUParticles3D = $PillarCore
@onready var _hero_sparkles: GPUParticles3D = $HeroSparkles
@onready var _ring_spiral_root: Node3D = $RingSpiral
@onready var _fog: GPUParticles3D = $Fog
@onready var _background_plane: MeshInstance3D = get_node_or_null("../BackgroundPlane")
@onready var _world_environment: WorldEnvironment = get_node_or_null("../WorldEnvironment")

var _pulse_time: float = 0.0
var _editor_refresh_accumulator: float = 0.0
var _core_texture: Texture2D
var _hero_texture: Texture2D
var _fog_texture: Texture2D


func _ready() -> void:
	_apply_configuration()
	set_process(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_editor_refresh_accumulator += delta
		if _editor_refresh_accumulator >= 0.25:
			_editor_refresh_accumulator = 0.0
			_apply_configuration()
		return

	_pulse_time += delta
	rotate_y(deg_to_rad(root_rotation_speed_deg) * delta)
	_pillar_core.rotate_y(deg_to_rad(core_spin_speed_deg) * delta)
	_hero_sparkles.rotate_y(deg_to_rad(hero_spin_speed_deg) * delta)
	_animate_ring_layers()
	_apply_hero_pulse()


func _apply_configuration() -> void:
	position = Vector3(0.0, pillar_vertical_offset, 0.0)
	if _ring_spiral_root != null:
		_ring_spiral_root.position = Vector3(0.0, ring_vertical_offset, 0.0)
	if _fog != null:
		_fog.position = Vector3(0.0, fog_vertical_offset, 0.0)
		_fog.visible = fog_enabled

	_configure_world_environment()
	_configure_background_plane()

	_core_texture = _build_soft_disc_texture(128, core_disc_falloff)
	_hero_texture = _build_soft_disc_texture(128, 0.72)
	_fog_texture = _build_soft_disc_texture(128, 0.38)

	_configure_particle_system(
		_pillar_core,
		core_amount,
		core_lifetime,
		core_particle_size,
		core_randomness,
		true,
		_build_particle_draw_material(
			_core_texture,
			Color(1.0, 1.0, 1.0, core_particle_alpha),
			core_emission_energy,
			true
		),
		_build_core_process_material()
	)

	_configure_particle_system(
		_hero_sparkles,
		hero_amount,
		hero_lifetime,
		hero_particle_size,
		hero_randomness,
		true,
		_build_particle_draw_material(
			_hero_texture,
			Color(1.0, 1.0, 1.0, hero_particle_alpha),
			hero_emission_energy,
			true
		),
		_build_hero_process_material()
	)

	_configure_particle_system(
		_fog,
		fog_amount if fog_enabled else 0,
		fog_lifetime,
		fog_particle_size,
		0.18,
		false,
		_build_particle_draw_material(
			_fog_texture,
			Color(0.8, 0.86, 1.0, fog_particle_alpha),
			fog_emission_energy,
			false
		),
		_build_fog_process_material()
	)

	_rebuild_ring_layers()
	_apply_hero_pulse()


func _configure_world_environment() -> void:
	if _world_environment == null:
		return
	var environment := Environment.new()
	environment.background_mode = Environment.BG_KEEP
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = MENU_AMBIENT_COLOR
	environment.ambient_light_energy = MENU_AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_strength = 0.25
	environment.glow_bloom = 0.1
	environment.sdfgi_enabled = false
	_world_environment.environment = environment


func _configure_background_plane() -> void:
	if _background_plane == null:
		return
	if not show_background_plane:
		_background_plane.visible = false
		return
	_background_plane.visible = true
	var quad := QuadMesh.new()
	quad.size = background_plane_size
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = background_texture
	material.albedo_color = Color(1.0, 1.0, 1.0, background_plane_alpha)
	quad.material = material
	_background_plane.mesh = quad
	_background_plane.position = background_plane_position


func _configure_particle_system(
	particles: GPUParticles3D,
	amount: int,
	lifetime: float,
	particle_size: float,
	particle_randomness: float,
	use_local_coords: bool,
	draw_material: Material,
	process_material: ParticleProcessMaterial
) -> void:
	if particles == null:
		return

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * particle_size
	quad.material = draw_material
	var is_enabled := amount > 0
	var safe_amount := maxi(amount, 1)

	particles.emitting = false
	particles.amount = safe_amount
	particles.amount_ratio = 1.0 if is_enabled else 0.0
	particles.lifetime = lifetime
	particles.preprocess = lifetime * warm_start_factor
	particles.speed_scale = 1.0
	particles.explosiveness = 0.0
	particles.randomness = particle_randomness
	particles.fixed_fps = fixed_fps_value if use_fixed_fps else 0
	particles.local_coords = use_local_coords
	particles.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	particles.draw_passes = 1
	particles.draw_pass_1 = quad
	particles.process_material = process_material
	particles.visibility_aabb = AABB(Vector3(-12.0, -4.0, -12.0), Vector3(24.0, 26.0, 24.0))

	if not is_enabled:
		return

	if warm_start_particles and not Engine.is_editor_hint():
		particles.call_deferred("set", "emitting", true)
	else:
		particles.emitting = true


func _build_core_process_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(core_emission_radius, core_emission_height * 0.5, core_emission_radius)
	material.direction = Vector3.UP
	material.spread = core_spread
	material.gravity = Vector3(0.0, -0.08, 0.0)
	material.initial_velocity_min = core_velocity_min
	material.initial_velocity_max = core_velocity_max
	material.orbit_velocity_min = core_orbit_velocity_min
	material.orbit_velocity_max = core_orbit_velocity_max
	material.radial_accel_min = core_radial_accel_min
	material.radial_accel_max = core_radial_accel_max
	material.tangential_accel_min = core_tangential_accel_min
	material.tangential_accel_max = core_tangential_accel_max
	material.damping_min = 0.06
	material.damping_max = 0.22
	material.scale_min = 0.58
	material.scale_max = 1.52
	material.hue_variation_min = -0.1
	material.hue_variation_max = 0.1
	material.angle_min = -0.65
	material.angle_max = 0.65
	material.color_ramp = _build_core_color_ramp()
	return material


func _build_hero_process_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(hero_emission_radius, hero_emission_height * 0.5, hero_emission_radius)
	material.direction = Vector3.UP
	material.spread = hero_spread
	material.gravity = Vector3(0.0, -0.14, 0.0)
	material.initial_velocity_min = hero_velocity_min
	material.initial_velocity_max = hero_velocity_max
	material.orbit_velocity_min = core_orbit_velocity_min * 1.05
	material.orbit_velocity_max = core_orbit_velocity_max * 1.05
	material.radial_accel_min = core_radial_accel_min * 0.55
	material.radial_accel_max = core_radial_accel_max * 0.55
	material.tangential_accel_min = core_tangential_accel_min * 0.95
	material.tangential_accel_max = core_tangential_accel_max * 0.95
	material.damping_min = 0.04
	material.damping_max = 0.12
	material.scale_min = 0.9
	material.scale_max = 1.55
	material.hue_variation_min = -0.08
	material.hue_variation_max = 0.08
	material.color_ramp = _build_hero_color_ramp()
	return material


func _build_fog_process_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(fog_emission_radius, fog_emission_height * 0.5, fog_emission_radius)
	material.direction = Vector3.UP
	material.spread = fog_spread
	material.gravity = Vector3.ZERO
	material.initial_velocity_min = fog_velocity_min
	material.initial_velocity_max = fog_velocity_max
	material.damping_min = 0.45
	material.damping_max = 0.78
	material.scale_min = 1.2
	material.scale_max = 2.5
	material.color_ramp = _build_fog_color_ramp()
	return material


func _build_particle_draw_material(
	texture: Texture2D,
	base_color: Color,
	emission_energy: float,
	additive: bool
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = base_color
	material.albedo_texture = texture
	material.emission_enabled = true
	material.emission = base_color
	material.emission_energy_multiplier = emission_energy
	material.emission_texture = texture
	return material


func _build_core_color_ramp() -> GradientTexture1D:
	# Narrower bright window + slightly lower peak alpha so additive stacks read as many dots, not one solid volume.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.08, 0.22, 0.42, 0.62, 0.82, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.58, 0.34, 0.95, 0.0),
		Color(0.58, 0.34, 0.95, 0.12),
		Color(1.0, 0.56, 0.84, 0.2),
		Color(0.35, 0.84, 1.0, 0.17),
		Color(1.0, 1.0, 1.0, 0.08),
		Color(1.0, 1.0, 1.0, 0.02),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _build_hero_color_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.32, 0.55, 0.78, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.58, 0.34, 0.95, 0.0),
		Color(0.58, 0.34, 0.95, 0.2),
		Color(1.0, 0.56, 0.84, 0.28),
		Color(0.35, 0.84, 1.0, 0.24),
		Color(1.0, 1.0, 1.0, 0.1),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _build_fog_color_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.22, 0.68, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.32, 0.26, 0.48, 0.0),
		Color(0.42, 0.34, 0.58, 0.045),
		Color(0.55, 0.48, 0.72, 0.038),
		Color(0.62, 0.58, 0.82, 0.0),
	])
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _build_soft_disc_texture(size: int, falloff_power: float) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2((size - 1) * 0.5, (size - 1) * 0.5)
	var max_distance := center.length()

	for y in size:
		for x in size:
			var delta := Vector2(x, y) - center
			var distance_ratio := clampf(delta.length() / max_distance, 0.0, 1.0)
			var alpha := pow(1.0 - distance_ratio, falloff_power * 2.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))

	return ImageTexture.create_from_image(image)


func _rebuild_ring_layers() -> void:
	if _ring_spiral_root == null:
		return
	while _ring_spiral_root.get_child_count() < ring_layer_count:
		var ring := MeshInstance3D.new()
		ring.name = "RingLayer_%s" % _ring_spiral_root.get_child_count()
		_ring_spiral_root.add_child(ring)
	while _ring_spiral_root.get_child_count() > ring_layer_count:
		_ring_spiral_root.get_child(_ring_spiral_root.get_child_count() - 1).queue_free()

	for index in ring_layer_count:
		var ring := _ring_spiral_root.get_child(index) as MeshInstance3D
		if ring == null:
			continue
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE * lerpf(ring_base_diameter, ring_top_diameter, _ring_layer_t(index))
		var material := ShaderMaterial.new()
		material.shader = RingSpiralShader
		var colors := _ring_palette_pair(index)
		material.set_shader_parameter("color_a", colors[0])
		material.set_shader_parameter("color_b", colors[1])
		material.set_shader_parameter("opacity", ring_opacity * lerpf(1.0, 0.6, _ring_layer_t(index)))
		material.set_shader_parameter("emission_strength", ring_emission_strength * lerpf(1.0, 0.7, _ring_layer_t(index)))
		material.set_shader_parameter("inner_radius", ring_inner_radius)
		material.set_shader_parameter("outer_radius", ring_outer_radius)
		material.set_shader_parameter("edge_softness", ring_edge_softness)
		material.set_shader_parameter("arc_density", lerpf(ring_arc_density_min, ring_arc_density_max, _ring_layer_t(index)))
		material.set_shader_parameter("arc_balance", ring_arc_balance)
		material.set_shader_parameter("arc_softness", ring_arc_softness)
		material.set_shader_parameter("arc_segment_mix", ring_arc_segment_mix)
		material.set_shader_parameter("scroll_speed", 0.08)
		material.set_shader_parameter("drift_phase", float(index) * 0.77)
		material.set_shader_parameter("rotation_offset", 0.0)
		quad.material = material
		ring.mesh = quad
		ring.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		ring.position = Vector3(0.0, lerpf(0.0, ring_stack_height, _ring_layer_t(index)), 0.0)


func _animate_ring_layers() -> void:
	if _ring_spiral_root == null:
		return
	var count := _ring_spiral_root.get_child_count()
	if count <= 0:
		return
	for index in count:
		var ring := _ring_spiral_root.get_child(index) as MeshInstance3D
		if ring == null:
			continue
		var base_t := _ring_layer_t(index)
		var travel := fposmod(base_t + _pulse_time * ring_drift_speed * 0.05, 1.0)
		var diameter := lerpf(ring_base_diameter, ring_top_diameter, travel)
		var quad := ring.mesh as QuadMesh
		if quad != null:
			quad.size = Vector2.ONE * diameter
		ring.position = Vector3(
			cos(_pulse_time * 0.35 + float(index)) * ring_jitter,
			lerpf(0.0, ring_stack_height, travel),
			sin(_pulse_time * 0.35 + float(index)) * ring_jitter
		)
		var material: ShaderMaterial = null
		if quad != null:
			material = quad.material as ShaderMaterial
		if material != null:
			material.set_shader_parameter("rotation_offset", _pulse_time * 0.1 + float(index) * 0.55)
			material.set_shader_parameter("opacity", ring_opacity * lerpf(1.0, 0.55, travel))


func _ring_palette_pair(index: int) -> PackedColorArray:
	# Same violet / pink / cyan vocabulary as the core ramp so rings feel part of one beam.
	const VIOLET := Color(0.58, 0.34, 0.95, 1.0)
	const PINK := Color(1.0, 0.56, 0.84, 1.0)
	const CYAN := Color(0.35, 0.84, 1.0, 1.0)
	const SOFT := Color(0.75, 0.7, 0.95, 1.0)
	match index % 4:
		0:
			return PackedColorArray([CYAN, PINK])
		1:
			return PackedColorArray([VIOLET, CYAN])
		2:
			return PackedColorArray([PINK, VIOLET])
		_:
			return PackedColorArray([SOFT, CYAN])


func _ring_layer_t(index: int) -> float:
	if ring_layer_count <= 1:
		return 0.0
	return float(index) / float(ring_layer_count - 1)


func _apply_hero_pulse() -> void:
	if _hero_sparkles == null:
		return
	if not hero_pulse_enabled:
		_hero_sparkles.amount_ratio = hero_base_amount_ratio
		return
	var pulse := sin(_pulse_time * TAU * hero_pulse_speed)
	var ratio := hero_base_amount_ratio + pulse * hero_pulse_strength
	_hero_sparkles.amount_ratio = clampf(ratio, 0.05, 1.0)
