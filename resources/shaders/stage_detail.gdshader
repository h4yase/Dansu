shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

uniform float scroll_offset = 0.0;
uniform float fade_start_z = -50.0;
uniform float fade_end_z = -41.0;
uniform float fade_out_start_z = 3.5;
uniform float fade_out_end_z = 6.0;
uniform float emission_strength : hint_range(0.0, 1.0) = 0.035;
uniform float low_energy : hint_range(0.0, 1.0) = 0.0;
uniform float volume_level : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_color : source_color = vec4(1.0);

varying vec4 mesh_color;
varying float stage_z;

void vertex() {
	mesh_color = COLOR;
	stage_z = VERTEX.z + scroll_offset;
}

void fragment() {
	float spawn_alpha = smoothstep(fade_start_z, fade_end_z, stage_z);
	float near_alpha = 1.0 - smoothstep(fade_out_start_z, fade_out_end_z, stage_z);
	float response = 1.0 + volume_level * 0.35;
	float alpha = clamp(mesh_color.a * spawn_alpha * near_alpha * response, 0.0, 1.0);
	vec3 color = mesh_color.rgb * tint_color.rgb;
	ALBEDO = color;
	EMISSION = color * emission_strength * alpha * (1.0 + volume_level * 0.60);
	ALPHA = alpha;
}
