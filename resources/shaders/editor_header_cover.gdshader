shader_type canvas_item;

void fragment() {
	vec4 cover = texture(TEXTURE, UV);
	cover.rgb = mix(cover.rgb, vec3(0.45, 0.36, 0.62), 0.2);
	cover.a *= (1.0 - smoothstep(0.15, 1.0, UV.x)) * 0.28;
	COLOR = cover;
}
