shader_type canvas_item;
render_mode unshaded;

uniform vec4 edge_color : source_color;
uniform float strength : hint_range(0.0, 1.0) = 0.46;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	vec2 shaped = centered * vec2(0.74, 1.0);
	float radial = smoothstep(0.53, 1.18, length(shaped));
	float top_fade = smoothstep(0.55, 0.0, UV.y) * 0.15;
	float alpha = clamp((radial + top_fade) * strength, 0.0, 0.62);
	COLOR = vec4(edge_color.rgb, alpha);
}
