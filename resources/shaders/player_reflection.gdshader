shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled;

uniform sampler2D sprite_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.32;
uniform float fade_depth = 1.2;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec4 sampled = texture(sprite_texture, UV);
	float fade = 1.0 - smoothstep(0.0, fade_depth, max(-world_y, 0.0));
	ALBEDO = sampled.rgb * tint.rgb * 0.65;
	ALPHA = sampled.a * tint.a * opacity * fade;
}
