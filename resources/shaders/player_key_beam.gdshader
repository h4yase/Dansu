shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(3.2, 12.0);
	float fade = pow(1.0 - progress, 1.6);
	float width = mix(0.16, 0.48, progress);
	float beam = exp(-abs(p.x) / width);
	float length_mask = 1.0 - smoothstep(0.5, 6.0, abs(p.y));
	// A narrow forward streak, with a small glow behind the player's feet.
	length_mask *= mix(1.0, 0.25, smoothstep(0.0, 1.8, p.y));
	float core = exp(-abs(p.x) / 0.045) * length_mask;
	float radius = mix(0.18, 1.35, progress);
	float ring = exp(-abs(length(p) - radius) * 22.0);
	float foot_glow = exp(-dot(p, p) * 4.0);
	float light = (beam * length_mask * 0.65 + core + ring * 0.65 + foot_glow) * fade;
	ALBEDO = mix(tint.rgb, vec3(1.0), 0.12) * 0.85;
	ALPHA = clamp(light * 0.45, 0.0, 0.45);
}
