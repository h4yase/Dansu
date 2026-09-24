shader_type sky;

uniform vec4 base_color : source_color = vec4(0.075, 0.078, 0.09, 1.0);
uniform vec4 detail_color : source_color = vec4(0.19, 0.19, 0.22, 1.0);

void sky() {
	float horizon = exp(-abs(EYEDIR.y) * 4.8);
	float upper_fade = smoothstep(-0.15, 0.85, EYEDIR.y);
	vec3 color = mix(base_color.rgb * 0.72, base_color.rgb, upper_fade);
	color = mix(color, detail_color.rgb, horizon * 0.62);
	COLOR = color;
}
