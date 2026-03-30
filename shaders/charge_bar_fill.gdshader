shader_type spatial;
// Opaque clip (no blend_mix) so the fill always draws like the track; depth_test off to match frame/track.
render_mode unshaded, cull_disabled, depth_test_disabled, fog_disabled;

// World L→R: after -90° X, PlaneMesh U increases opposite world +X, so keep UV.x > (1 - fill_ratio).
uniform float fill_ratio : hint_range(0.0, 1.0, 0.001) = 1.0;
uniform vec3 albedo_color : source_color = vec3(0.98, 0.84, 0.12);
uniform vec3 emission_color : source_color = vec3(1.0, 0.88, 0.22);
uniform float emission_energy : hint_range(0.0, 4.0) = 0.55;

void fragment() {
	if (UV.x <= 1.0 - fill_ratio) {
		discard;
	}
	// Unshaded uses ALBEDO; add emission into albedo so yellow reads clearly.
	ALBEDO = albedo_color + emission_color * emission_energy;
}
