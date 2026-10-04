shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled;

uniform sampler2D note_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float emission_strength : hint_range(0.0, 0.5) = 0.12;

void fragment() {
	vec4 sampled = texture(note_texture, UV);
	vec3 color = sampled.rgb * tint.rgb;
	float brightness = dot(sampled.rgb, vec3(0.2126, 0.7152, 0.0722));
	float saturation = max(max(sampled.r, sampled.g), sampled.b) - min(min(sampled.r, sampled.g), sampled.b);
	// Light the colored face, leaving the dark thickness and white symbols intact.
	float face = smoothstep(0.16, 0.32, brightness) * smoothstep(0.05, 0.18, saturation);
	ALBEDO = color;
	EMISSION = color * face * emission_strength;
	ALPHA = sampled.a * tint.a;
}
