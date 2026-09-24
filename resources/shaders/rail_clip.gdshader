shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float rail_origin_z = 0.0;
uniform float min_visible_z = 0.0;
uniform float clip_fade_length : hint_range(0.1, 8.0) = 2.5;
uniform vec4 fill_color : source_color = vec4(0.135, 0.132, 0.205, 1.0);
uniform vec4 outline_color : source_color = vec4(0.455, 0.420, 0.690, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.025, 0.025, 0.04, 1.0);
uniform vec4 accent_color : source_color = vec4(0.575, 0.520, 0.860, 1.0);
uniform float brightness : hint_range(0.0, 1.0) = 1.0;
uniform float fill_width_ratio : hint_range(0.01, 1.0) = 0.285714;
uniform float outline_width_ratio : hint_range(0.01, 1.0) = 0.857143;

varying float playfield_z;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void vertex() {
	playfield_z = rail_origin_z + VERTEX.z;
}

void fragment() {
	if (playfield_z < min_visible_z) {
		discard;
	}
	float clip_coverage = smoothstep(min_visible_z, min_visible_z + clip_fade_length, playfield_z);
	float clip_dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (clip_coverage < clip_dither) {
		discard;
	}

	float distance_to_center = clamp(abs(UV.x * 2.0 - 1.0), 0.0, 1.0);
	float fill_center = clamp(1.0 - distance_to_center / max(fill_width_ratio, 0.001), 0.0, 1.0);
	float outline_center = clamp(1.0 - distance_to_center / max(outline_width_ratio, 0.001), 0.0, 1.0);

	float core_mask = smoothstep(0.18, 0.92, fill_center);
	float core_glow = pow(fill_center, 3.4);
	float outline_edge_mask = smoothstep(0.56, 0.98, 1.0 - outline_center);

	vec3 fill_base = fill_color.rgb;
	vec3 highlight_color = mix(fill_base, accent_color.rgb, 0.68);
	vec3 fill_shadow = fill_base * 0.58;

	float active_strength = mix(0.34, 1.0, brightness);
	float soft_sweep = sin(playfield_z * 0.058 - TIME * 2.15) * 0.5 + 0.5;
	soft_sweep = smoothstep(0.80, 0.99, soft_sweep) * core_glow;

	float pulse = sin(playfield_z * 0.028 + TIME * 1.15) * 0.5 + 0.5;
	float grain = hash(floor(playfield_z * 0.045) + floor(UV.x * 14.0) * 13.0);
	float breakup = mix(0.975, 1.025, grain * 0.5 + pulse * 0.5);

	vec3 fill_surface = mix(fill_shadow, fill_base, 0.78);
	fill_surface = mix(fill_surface, highlight_color, core_mask * 0.075);
	fill_surface += highlight_color * soft_sweep * (0.045 + active_strength * 0.065);
	fill_surface *= breakup;
	fill_surface += highlight_color * core_glow * active_strength * 0.055;
	fill_surface *= active_strength;

	vec3 outline_surface = mix(outline_color.rgb, accent_color.rgb, 0.62);
	outline_surface += accent_color.rgb * outline_edge_mask * 0.018;

	float edge_softness = max(fwidth(distance_to_center), 0.001);
	float fill_mask = 1.0 - smoothstep(
		fill_width_ratio - edge_softness,
		fill_width_ratio + edge_softness,
		distance_to_center
	);
	float outline_mask = 1.0 - smoothstep(
		outline_width_ratio - edge_softness,
		outline_width_ratio + edge_softness,
		distance_to_center
	);

	vec3 outside_fill = mix(shadow_color.rgb, outline_surface, outline_mask);
	vec3 final_color = mix(outside_fill, fill_surface, fill_mask);
	float fill_emission = (0.07 + core_glow * 0.22 + soft_sweep * 0.26) * active_strength;

	ALBEDO = final_color;
	EMISSION = final_color * fill_emission * fill_mask;
}
