shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform vec4 rail_color : source_color = vec4(1.0);
uniform vec4 guide_color : source_color = vec4(1.0);
uniform float emission_energy = 0.10;

void fragment() {
	// Vertex red identifies the strip; alpha preserves its original opacity.
	float role = COLOR.r;
	vec3 color;
	if (role < 0.16) {
		color = mix(guide_color.rgb, vec3(1.0), 0.34);
	} else if (role < 0.5) {
		color = guide_color.rgb * 0.80;
	} else if (role < 0.84) {
		color = mix(rail_color.rgb, guide_color.rgb, 0.14) * 0.92;
	} else {
		color = rail_color.rgb * 0.82;
	}
	ALBEDO = color;
	EMISSION = rail_color.rgb * 0.84 * emission_energy;
	ALPHA = COLOR.a;
}
