shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float direction = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.4, 3.2);
	float edge = 1.0 - smoothstep(0.7, 1.6, abs(p.y));
	// Spread slightly beside the player's feet, then quickly fade away.
	float spread = 1.0 - pow(1.0 - progress, 3.0);
	float front = mix(0.2, 0.65, spread) - p.y * p.y * 0.07;
	float distance_to_front = p.x * direction - front;
	float crest = exp(-abs(distance_to_front) * 22.0);
	float trail = exp(min(distance_to_front, 0.0) * 4.5);
	trail *= 1.0 - smoothstep(-0.02, 0.06, distance_to_front);
	float streaks = pow(0.5 + 0.5 * sin(p.y * 38.0 + distance_to_front * 12.0), 6.0);
	float fade = pow(1.0 - progress, 2.2) * smoothstep(0.0, 0.04, progress);
	float light = (crest * 0.65 + trail * 0.3 + streaks * trail * 0.18) * edge * fade;
	ALBEDO = mix(tint.rgb, vec3(1.0), crest * 0.2) * 0.95;
	ALPHA = clamp(light * 0.55, 0.0, 0.55);
}
