shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float diamond_pixel_size : hint_range(8.0, 128.0) = 56.0;

uniform vec4 transition_color : source_color = vec4(0.060, 0.055, 0.115, 1.0);
uniform vec4 outline_color : source_color = vec4(0.190, 0.165, 0.350, 1.0);

void fragment() {
	vec2 tile_uv = fract(FRAGCOORD.xy / diamond_pixel_size);
	float diamond = abs(tile_uv.x - 0.5) + abs(tile_uv.y - 0.5);

	float order = diamond + SCREEN_UV.x + SCREEN_UV.y;
	float threshold = progress * 3.10 - 0.05;
	float mask = 1.0 - smoothstep(threshold - 0.025, threshold + 0.025, order);
	float inside_distance = max(threshold - order, 0.0);
	float outline = (1.0 - smoothstep(0.010, 0.045, inside_distance)) * mask;
	vec3 color = mix(transition_color.rgb, outline_color.rgb, outline);

	COLOR = vec4(color, mask * transition_color.a);
}
