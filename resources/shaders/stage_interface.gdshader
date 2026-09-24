shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

uniform vec4 floor_color : source_color;
uniform vec4 guide_color : source_color;
uniform vec4 accent_color : source_color;
uniform vec4 detail_color : source_color;
uniform float line_opacity : hint_range(0.0, 1.0) = 0.58;
uniform float floor_opacity : hint_range(0.0, 1.0) = 0.10;
uniform float volume_alpha_boost : hint_range(0.0, 1.0) = 0.34;
uniform float scroll_offset = 0.0;
uniform float low_energy : hint_range(0.0, 1.0) = 0.0;
uniform float mid_energy : hint_range(0.0, 1.0) = 0.0;
uniform float high_energy : hint_range(0.0, 1.0) = 0.0;
uniform float volume_level : hint_range(0.0, 1.0) = 0.0;

varying vec2 stage_position;

float repeated_line(float coordinate, float spacing, float width) {
	float distance_to_line = abs(fract(coordinate / spacing + 0.5) - 0.5) * spacing;
	float antialias = max(fwidth(coordinate) * 1.2, 0.006);
	return 1.0 - smoothstep(width, width + antialias, distance_to_line);
}

float box_mask(vec2 point, vec2 half_size) {
	vec2 distance_to_box = abs(point) - half_size;
	float outside = length(max(distance_to_box, vec2(0.0)));
	float inside = min(max(distance_to_box.x, distance_to_box.y), 0.0);
	float signed_distance = outside + inside;
	return 1.0 - smoothstep(0.0, max(fwidth(signed_distance) * 1.5, 0.008), signed_distance);
}

void vertex() {
	stage_position = VERTEX.xz;
}

void fragment() {
	vec2 p = stage_position;
	float abs_x = abs(p.x);
	float moving_z = p.y - scroll_offset;

	float horizon_fade = smoothstep(-51.0, -34.0, p.y);
	float camera_fade = 1.0 - smoothstep(4.0, 18.0, p.y);
	float depth_visibility = horizon_fade * camera_fade;
	float side_visibility = smoothstep(5.8, 8.8, abs_x);

	float broad_tone = smoothstep(-48.0, 5.0, p.y);
	vec3 dark_base = floor_color.rgb * mix(0.055, 0.14, broad_tone);
	vec3 color = dark_base;
	float rail_corridor = 1.0 - smoothstep(6.0, 9.5, abs_x);
	color *= 1.0 - rail_corridor * 0.18;
	float pulse_response = volume_level;
	float peak_response = smoothstep(0.72, 1.0, pulse_response);
	vec3 audio_color = mix(guide_color.rgb, accent_color.rgb, 0.22 + mid_energy * 0.28 + high_energy * 0.22);
	vec3 glow_color = mix(audio_color, vec3(1.0), high_energy * 0.075 + peak_response * 0.16);
	color += glow_color * pulse_response * 0.052 * depth_visibility;

	float longitudinal_major = repeated_line(p.x, 2.5, 0.018);
	float longitudinal_minor = repeated_line(p.x + 1.25, 2.5, 0.007);
	float cross_major = repeated_line(moving_z, 5.5, 0.030);
	float cross_minor = repeated_line(moving_z, 1.375, 0.006);

	float center_quiet = mix(0.78, 1.0, side_visibility);
	float grid = longitudinal_major * 0.135 * center_quiet;
	grid += longitudinal_minor * 0.030 * center_quiet;
	grid += cross_major * 0.240 * center_quiet;
	grid += cross_minor * 0.040 * center_quiet;
	grid *= depth_visibility;

	float guide_band = smoothstep(7.1, 7.5, abs_x) * (1.0 - smoothstep(9.0, 9.4, abs_x));
	float tick_row = repeated_line(moving_z, 1.05, 0.019);
	float tick_column = 1.0 - smoothstep(0.0, 0.16, abs(fract((abs_x - 7.4) / 0.58) - 0.5) - 0.30);
	float ticks = tick_row * tick_column * guide_band * depth_visibility;

	vec2 dot_cell = fract(vec2((abs_x - 9.45) / 0.52, moving_z / 0.68)) - 0.5;
	float dot = 1.0 - smoothstep(0.10, 0.15, length(dot_cell));
	float dot_band = smoothstep(9.2, 9.6, abs_x) * (1.0 - smoothstep(11.15, 11.55, abs_x));
	float dots = dot * dot_band * depth_visibility * (0.10 + high_energy * 0.18);

	float panel_cell = floor((moving_z + 60.0) / 8.0);
	float panel_selector = step(0.66, fract(sin(panel_cell * 17.13 + floor(abs_x) * 3.71) * 43758.5453));
	vec2 panel_local = vec2(fract((abs_x - 10.2) / 1.5) - 0.5, fract(moving_z / 8.0) - 0.5);
	float panel = box_mask(panel_local, vec2(0.30, 0.16));
	float panel_band = smoothstep(10.0, 10.3, abs_x) * (1.0 - smoothstep(11.45, 11.75, abs_x));
	panel *= panel_selector * panel_band * depth_visibility;

	vec3 guide_mix = mix(guide_color.rgb, glow_color, 0.26 + pulse_response * 0.44);
	vec3 grid_color = detail_color.rgb;
	color = mix(color, grid_color, clamp(grid * line_opacity * 1.16, 0.0, 0.26));
	color += guide_mix * ticks * line_opacity * (0.010 + mid_energy * 0.082 + peak_response * 0.036);
	color += glow_color * dots * line_opacity * (0.018 + high_energy * 0.140);
	color += audio_color * panel * line_opacity * (0.004 + pulse_response * 0.020);
	float feature_alpha = grid * 3.8;
	feature_alpha += ticks * 0.10 + dots * 0.14 + panel * 0.07;
	feature_alpha = clamp(feature_alpha * line_opacity, 0.0, 0.24);
	float surface_alpha = floor_opacity * mix(0.18, 0.42, broad_tone);
	float pulse_alpha = pulse_response * depth_visibility * volume_alpha_boost * 0.78;

	ALBEDO = color;
	EMISSION = grid_color * line_opacity * grid * 0.22 + glow_color * line_opacity * (
		ticks * (mid_energy * 0.070 + peak_response * 0.050) +
		dots * (high_energy * 0.085 + peak_response * 0.060)
	);
	ALPHA = clamp(surface_alpha + feature_alpha + pulse_alpha, 0.0, 0.72);
}
