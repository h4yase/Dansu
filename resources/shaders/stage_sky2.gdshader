shader_type sky;

uniform vec4 base_color : source_color = vec4(0.1098, 0.1020, 0.1765, 1.0);
uniform vec4 highlight_color : source_color = vec4(0.4392, 0.3569, 0.8706, 1.0);

uniform float horizon_height : hint_range(-0.5, 0.5) = -0.08;
uniform float haze_strength : hint_range(0.0, 2.0) = 0.95;

uniform float beam_intensity : hint_range(0.0, 3.0) = 0.9;
uniform float beam_width : hint_range(0.003, 0.08) = 0.018;
uniform float beam_speed : hint_range(0.0, 3.0) = 0.16;

uniform float laser_intensity : hint_range(0.0, 3.0) = 0.45;
uniform float laser_width : hint_range(0.001, 0.04) = 0.006;
uniform float laser_speed : hint_range(0.0, 4.0) = 0.48;

uniform float arch_intensity : hint_range(0.0, 2.0) = 0.34;
uniform float graffiti_strength : hint_range(0.0, 1.0) = 0.16;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.3;


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		value += noise(p) * amp;
		p = p * 2.0 + vec2(8.3, -5.7);
		amp *= 0.5;
	}
	return value;
}

float line_band(float value, float center, float width, float softness) {
	float dist = abs(value - center);
	return 1.0 - smoothstep(width, width + softness, dist);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float azimuth = atan(dir.x, dir.z);
	float sx = azimuth / PI;
	float y = dir.y - horizon_height;

	vec3 base = base_color.rgb;
	vec3 hi = highlight_color.rgb;
	vec3 deep = base * 0.66;
	vec3 upper = mix(base, hi, 0.08);

	float sky_grad = smoothstep(-0.35, 0.85, y);
	vec3 color = mix(deep, upper, sky_grad);

	float horizon_haze = exp(-abs(y) * 10.0) * haze_strength;
	color += hi * horizon_haze * 0.24;

	float lower_falloff = 1.0 - smoothstep(-0.22, 0.12, y);
	color = mix(color, deep * 0.92, lower_falloff * 0.45);

	float stage_zone = smoothstep(-0.02, 0.18, y) * (1.0 - smoothstep(0.34, 0.62, y));
	float beam1 = line_band(sx, -0.56 + sin(TIME * beam_speed) * 0.06, beam_width, beam_width * 1.3);
	float beam2 = line_band(sx, -0.18 + sin(TIME * beam_speed * 0.73 + 1.2) * 0.05, beam_width * 0.85, beam_width);
	float beam3 = line_band(sx, 0.24 + sin(TIME * beam_speed * 0.91 + 3.1) * 0.04, beam_width * 1.15, beam_width * 1.2);
	float beam4 = line_band(sx, 0.62 + sin(TIME * beam_speed * 0.62 + 4.7) * 0.05, beam_width * 0.95, beam_width);
	float beams = (beam1 + beam2 + beam3 + beam4) * stage_zone * beam_intensity;
	color += hi * beams * 0.34;

	float diag1 = fract(sx * 0.55 + y * 1.45 + TIME * laser_speed * 0.08);
	float diag2 = fract(sx * -0.48 + y * 1.18 - TIME * laser_speed * 0.06);
	float lasers = 0.0;
	lasers += line_band(diag1, 0.22, laser_width, laser_width * 1.8);
	lasers += line_band(diag2, 0.71, laser_width * 1.25, laser_width * 1.9);
	lasers *= smoothstep(0.02, 0.22, y) * (1.0 - smoothstep(0.3, 0.56, y));
	color += hi * lasers * laser_intensity * 0.28;

	vec2 arch_uv = vec2(sx * 1.12, (y + 0.12) * 3.6);
	float arch_dist = length(vec2(arch_uv.x, arch_uv.y * 1.55) - vec2(0.0, 0.94));
	float arch1 = line_band(arch_dist, 0.84, 0.012, 0.02);
	float arch2 = line_band(arch_dist, 1.02, 0.015, 0.024);
	float arch3 = line_band(arch_dist, 1.18, 0.018, 0.028);
	float arches = (arch1 + arch2 * 0.75 + arch3 * 0.5);
	arches *= smoothstep(-0.02, 0.16, y) * (1.0 - smoothstep(0.2, 0.42, y));
	color += hi * arches * arch_intensity * 0.42;

	float far_core = exp(-abs(sx) * 6.0) * exp(-pow(max(y + 0.02, 0.0) * 8.0, 2.0));
	color += hi * far_core * 0.08;

	float skyline_noise = fbm(vec2(sx * 6.0, 0.0));
	float skyline_height = -0.055 + skyline_noise * 0.035;
	float skyline = 1.0 - smoothstep(skyline_height, skyline_height + 0.006, y);
	color = mix(color, deep * 0.82, skyline * 0.32);

	float graffiti_noise = fbm(vec2(sx * 10.0, y * 16.0 + 5.0));
	float graffiti = smoothstep(0.72, 0.9, graffiti_noise);
	graffiti *= 1.0 - smoothstep(0.04, 0.18, y);
	color = mix(color, mix(base, hi, 0.18), graffiti * graffiti_strength * 0.16);

	float vignette = 1.0 - clamp(length(vec2(sx * 0.8, (dir.y * 0.5 + 0.5 - 0.5) * 1.35)), 0.0, 1.0);
	color *= mix(1.0 - vignette_strength, 1.0, pow(vignette, 1.4));

	COLOR = color;
}
