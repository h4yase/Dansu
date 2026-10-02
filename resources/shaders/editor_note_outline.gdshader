shader_type canvas_item;

uniform bool selected = false;
uniform vec2 draw_size = vec2(68.0, 42.0);
uniform float outline_width = 2.0;
uniform vec4 outline_color : source_color = vec4(1.0, 0.945, 0.659, 1.0);

varying vec4 draw_color;

void vertex() {
	draw_color = COLOR;
}

void fragment() {
	vec4 pixel = texture(TEXTURE, UV);
	float outline_alpha = 0.0;
	if (selected) {
		vec2 offset = vec2(outline_width) / draw_size;
		for (int i = 0; i < 16; i++) {
			float angle = float(i) * 6.283185 / 16.0;
			vec2 sample_uv = UV + vec2(cos(angle), sin(angle)) * offset;
			outline_alpha = max(outline_alpha, texture(TEXTURE, sample_uv).a);
		}
	}
	float border_alpha = outline_alpha * (1.0 - pixel.a) * outline_color.a;
	float alpha = pixel.a + border_alpha;
	vec3 color = (pixel.rgb * draw_color.rgb * pixel.a + outline_color.rgb * border_alpha) / max(alpha, 0.0001);
	COLOR = vec4(color, alpha * draw_color.a);
}
