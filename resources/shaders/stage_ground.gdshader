shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(0.043, 0.046, 0.056, 1.0);
uniform vec4 near_color : source_color = vec4(0.072, 0.076, 0.088, 1.0);
uniform vec4 aggregate_color : source_color = vec4(0.20, 0.205, 0.215, 1.0);
uniform float mottle_strength : hint_range(0.0, 0.5) = 0.16;
uniform float aggregate_strength : hint_range(0.0, 1.0) = 0.34;
uniform float grain_strength : hint_range(0.0, 0.1) = 0.018;

varying vec2 stage_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);

	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

float fbm(vec2 p) {
	float result = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		result += value_noise(p) * amplitude;
		p = p * 2.03 + vec2(7.1, -4.3);
		amplitude *= 0.5;
	}
	return result;
}

float aggregate_dot(vec2 p, float scale, float density_seed) {
	vec2 scaled = p * scale;
	vec2 cell = floor(scaled);
	vec2 local = fract(scaled) - 0.5;
	vec2 offset = vec2(
		hash(cell + vec2(17.3, 4.1)),
		hash(cell + vec2(-8.7, 12.9))
	) - 0.5;
	float seed = hash(cell + vec2(density_seed, density_seed * 1.73));
	float radius = mix(0.07, 0.17, hash(cell + vec2(2.7, -9.4)));
	float dot_mask = 1.0 - smoothstep(radius, radius + 0.07, length(local - offset * 0.42));
	return dot_mask * step(0.72, seed);
}

void vertex() {
	stage_position = VERTEX.xz;
}

void fragment() {
	vec2 p = stage_position;
	float near_amount = smoothstep(-50.0, 10.0, p.y);
	vec3 color = mix(base_color.rgb * 0.74, near_color.rgb, near_amount * 0.72);

	float coarse_mottle = fbm(p * 0.16);
	float medium_grain = value_noise(p * 2.7);
	color *= 1.0 + (coarse_mottle - 0.5) * mottle_strength;
	color += (medium_grain - 0.5) * grain_strength;

	float medium_visibility = smoothstep(-46.0, -8.0, p.y);
	float fine_visibility = smoothstep(-28.0, 5.0, p.y);
	float medium_stones = aggregate_dot(p, 7.0, 3.7) * medium_visibility;
	float fine_stones = aggregate_dot(p, 19.0, 11.2) * fine_visibility;
	float light_aggregate = clamp(medium_stones * 0.55 + fine_stones, 0.0, 1.0);
	color = mix(color, aggregate_color.rgb, light_aggregate * aggregate_strength);

	float dark_pits = aggregate_dot(p + vec2(4.2, -6.8), 14.0, 23.6) * fine_visibility;
	color *= 1.0 - dark_pits * 0.16;

	float far_edge = smoothstep(-54.0, -46.0, p.y);
	color *= mix(0.52, 1.0, far_edge);

	ALBEDO = color;
}
