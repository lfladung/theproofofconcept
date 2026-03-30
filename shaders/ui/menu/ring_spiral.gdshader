shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 color_a : source_color = vec4(0.55, 0.80, 1.0, 1.0);
uniform vec4 color_b : source_color = vec4(0.95, 0.55, 0.85, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.08;
uniform float emission_strength : hint_range(0.0, 4.0) = 0.25;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.72;
uniform float outer_radius : hint_range(0.0, 1.0) = 0.92;
uniform float edge_softness : hint_range(0.001, 0.25) = 0.06;
uniform float arc_density : hint_range(1.0, 24.0) = 8.0;
uniform float arc_balance : hint_range(0.0, 1.0) = 0.55;
uniform float arc_softness : hint_range(0.001, 0.5) = 0.16;
// 0 = full continuous ring (cohesive with pillar); 1 = original broken arc segments.
uniform float arc_segment_mix : hint_range(0.0, 1.0) = 0.22;
uniform float scroll_speed : hint_range(-2.0, 2.0) = 0.08;
uniform float drift_phase : hint_range(-10.0, 10.0) = 0.0;
uniform float rotation_offset : hint_range(-10.0, 10.0) = 0.0;

void fragment() {
	vec2 centered_uv = UV * 2.0 - vec2(1.0);
	float radius = length(centered_uv);
	float angle = atan(centered_uv.y, centered_uv.x) + rotation_offset;

	float outer = 1.0 - smoothstep(outer_radius - edge_softness, outer_radius + edge_softness, radius);
	float inner = smoothstep(inner_radius - edge_softness, inner_radius + edge_softness, radius);
	float ring_mask = outer * inner;

	float primary_arc = 0.5 + 0.5 * sin(angle * arc_density + TIME * scroll_speed + drift_phase);
	float secondary_arc = 0.5 + 0.5 * sin(angle * (arc_density * 0.47) - TIME * scroll_speed * 0.55 + drift_phase * 1.37);
	float arc_mix = mix(primary_arc, secondary_arc, 0.35);
	float arc_mask = smoothstep(arc_balance - arc_softness, arc_balance + arc_softness, arc_mix);
	float arc_contrib = mix(1.0, arc_mask, arc_segment_mix);

	float radial_fade = 1.0 - smoothstep(inner_radius, outer_radius, radius);
	vec3 color = mix(color_a.rgb, color_b.rgb, clamp(primary_arc * 0.65 + secondary_arc * 0.35, 0.0, 1.0));
	float alpha = ring_mask * arc_contrib * opacity * mix(1.0, 0.55, radial_fade);

	ALBEDO = color;
	EMISSION = color * emission_strength;
	ALPHA = alpha;
}
