shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, cull_disabled, blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec4 c = texture(screen_tex, SCREEN_UV);
	ALBEDO = c.rgb;
	ALPHA = 0.1;
}
