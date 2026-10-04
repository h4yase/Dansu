shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, shadows_disabled, specular_disabled;

uniform vec4 rail_color : source_color = vec4(1.0);
uniform float emission_energy = 1.8;

void fragment() {
	// Vertex red separates the solid body, bright core, and end caps.
	float role = COLOR.r;
	vec3 color = rail_color.rgb;
	float color_peak = max(color.r, max(color.g, color.b));
	vec3 glow_color = color / max(color_peak, 0.05);
	if (role < 0.5) {
		color *= 0.72;
	} else if (role < 0.84) {
		color += glow_color * emission_energy;
	} else {
		color *= 0.90;
	}
	ALBEDO = vec3(0.0);
	EMISSION = color;
}
