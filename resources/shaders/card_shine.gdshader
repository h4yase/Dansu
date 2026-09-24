shader_type canvas_item;
render_mode blend_add, unshaded;

uniform vec2 cursor_uv = vec2(0.5, 0.5);
uniform float hover_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shine_color : source_color = vec4(0.4392157, 0.35686275, 0.87058824, 1.0);

void fragment() {
	vec2 uv = UV;
	vec2 centered_uv = uv - vec2(0.5);
	vec2 cursor_delta = uv - cursor_uv;

	float radial = smoothstep(0.55, 0.0, length(cursor_delta * vec2(1.15, 0.9)));
	float rim = pow(max(0.0, 1.0 - length(centered_uv) * 1.8), 3.0);

	vec2 band_axis = normalize(vec2(1.0, -0.7));
	float band_coord = dot(cursor_delta, band_axis);
	float band = exp(-pow(band_coord * 8.0, 2.0));

	float shimmer = (radial * 0.18) + (band * 0.22) + (rim * 0.08);
	float alpha = shimmer * hover_strength;

	COLOR = vec4(shine_color.rgb, alpha);
}
