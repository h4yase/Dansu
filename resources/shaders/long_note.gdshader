shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never;

uniform vec4 body_color : source_color = vec4(0.55, 0.60, 0.95, 1.0);
uniform vec4 edge_color : source_color = vec4(0.35, 0.34, 0.82, 1.0);
uniform float spawn_fade_distance = 9.0;
uniform float playfield_origin_z = 0.0;
uniform vec3 owner_z_axis = vec3(0.0, 0.0, 1.0);
uniform float holding : hint_range(0.0, 1.0) = 0.0;
uniform float clip_local_z = 100000.0;

varying float note_local_z;
varying float playfield_z;

void vertex() {
	note_local_z = VERTEX.z;
	playfield_z = playfield_origin_z + dot(owner_z_axis, VERTEX);
}

void fragment() {
	if (note_local_z > clip_local_z || playfield_z <= 0.0) {
		discard;
	}

	float dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float opacity = clamp(playfield_z / max(spawn_fade_distance, 0.001), 0.0, 1.0);
	if (opacity < dither) {
		discard;
	}

	float center = clamp(1.0 - abs(UV.x * 2.0 - 1.0), 0.0, 1.0);
	float edge = smoothstep(0.76, 0.98, 1.0 - center);
	float core = pow(center, 2.4);
	float pulse = sin(TIME * 5.2 - note_local_z * 0.12) * 0.5 + 0.5;
	float active_glow = holding * (0.10 + pulse * 0.13);

	vec3 color = mix(body_color.rgb, edge_color.rgb, edge);
	color += body_color.rgb * (core * 0.08 + active_glow * core);

	ALBEDO = color;
	EMISSION = color * (0.08 + core * 0.08 + active_glow);
}
