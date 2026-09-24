shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 beam_color : source_color = vec4(0.62, 0.88, 1.0, 0.16);
uniform float side_fade_power : hint_range(0.2, 4.0) = 1.25;
uniform float vertical_fade_power : hint_range(0.2, 4.0) = 1.4;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.35;
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.08;

void fragment() {
	float side = 1.0 - abs(UV.x * 2.0 - 1.0);
	side = pow(clamp(side, 0.0, 1.0), side_fade_power);

	float vertical = pow(clamp(1.0 - UV.y, 0.0, 1.0), vertical_fade_power);
	float pulse = 1.0 + sin(TIME * 1.6 + UV.y * 10.0) * pulse_strength;

	vec3 color = beam_color.rgb;
	float alpha = beam_color.a * side * vertical * pulse;

	ALBEDO = color;
	EMISSION = color * emission_strength * pulse;
	ALPHA = alpha;
}
