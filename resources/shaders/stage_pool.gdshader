shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 pool_color : source_color = vec4(0.76, 0.86, 1.0, 0.18);
uniform float ellipse_x : hint_range(0.2, 3.0) = 1.35;
uniform float ring_size : hint_range(0.05, 0.6) = 0.22;
uniform float fill_strength : hint_range(0.0, 1.0) = 0.2;
uniform float emission_strength : hint_range(0.0, 2.0) = 0.25;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	uv.x *= ellipse_x;
	float dist = length(uv);

	float outer = 1.0 - smoothstep(0.72, 1.0, dist);
	float inner = 1.0 - smoothstep(0.18, 0.18 + ring_size, dist);
	float ring = max(outer - inner, 0.0);
	float fill = (1.0 - smoothstep(0.0, 0.72, dist)) * fill_strength;
	float alpha = (ring + fill) * pool_color.a;

	ALBEDO = pool_color.rgb;
	EMISSION = pool_color.rgb * (emission_strength + ring * 0.35);
	ALPHA = alpha;
}
