shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

const int SAMPLE_COUNT = 48;
uniform float spectrum_levels[48];
uniform float sample_shift = 0.0;
uniform float z_shift = 0.0;
uniform float base_offset = 0.72;
uniform float surface_y = -0.018;
uniform float backing_y = -0.055;
uniform vec4 accent_color : source_color = vec4(1.0);
uniform vec4 shadow_color : source_color = vec4(0.0);
uniform float volume_level = 0.0;
uniform float fade_start_z = -50.0;
uniform float fade_end_z = -41.0;
uniform float fade_out_start_z = 3.5;
uniform float fade_out_end_z = 6.0;
uniform float emission_strength = 0.035;

varying vec4 wave_color;
varying float stage_z;

void vertex() {
	float sample_position = mod(UV.x * float(SAMPLE_COUNT - 1) + sample_shift, float(SAMPLE_COUNT));
	int first = int(floor(sample_position));
	int next = (first + 1) % SAMPLE_COUNT;
	float blend = smoothstep(0.0, 1.0, fract(sample_position));
	float level = mix(spectrum_levels[first], spectrum_levels[next], blend);
	float x = base_offset + 0.15 + level * 1.18;
	float top_y = surface_y - level * 0.012;
	float edge = UV.y * 2.0 - 1.0;

	if (UV2.x < 0.5) {
		VERTEX.x = x;
		VERTEX.y = mix(backing_y, top_y, UV.y);
		wave_color = vec4(accent_color.rgb, (0.10 + level * 0.18) * mix(0.35, 1.0, UV.y));
	} else if (UV2.x < 1.5) {
		VERTEX.x = x + edge * (0.035 + level * 0.035);
		VERTEX.y = top_y;
		wave_color = vec4(accent_color.rgb, 0.30 + level * 0.46 + volume_level * 0.08);
	} else {
		VERTEX.x = x + 0.07 + edge * (0.065 + level * 0.025);
		VERTEX.y = backing_y + 0.004;
		wave_color = vec4(shadow_color.rgb, 0.12);
	}
	VERTEX.z += z_shift;
	stage_z = VERTEX.z;
}

void fragment() {
	float spawn_alpha = smoothstep(fade_start_z, fade_end_z, stage_z);
	float near_alpha = 1.0 - smoothstep(fade_out_start_z, fade_out_end_z, stage_z);
	float alpha = clamp(wave_color.a * spawn_alpha * near_alpha * (1.0 + volume_level * 0.35), 0.0, 1.0);
	ALBEDO = wave_color.rgb;
	EMISSION = wave_color.rgb * emission_strength * alpha * (1.0 + volume_level * 0.60);
	ALPHA = alpha;
}
