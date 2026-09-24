shader_type canvas_item;

uniform vec4 fill_color : source_color = vec4(0.23, 0.20, 0.34, 0.92);
uniform vec4 outline_color : source_color = vec4(0.88, 0.86, 1.0, 1.0);
uniform vec4 bubble_color : source_color = vec4(1.0, 1.0, 1.0, 0.18);

uniform float roundness : hint_range(0.05, 0.95) = 0.55;
uniform float wobble_strength : hint_range(0.0, 0.12) = 0.03;
uniform float wobble_speed : hint_range(0.0, 4.0) = 0.9;
uniform float outline_width : hint_range(0.0, 0.12) = 0.028;
uniform float edge_softness : hint_range(0.001, 0.08) = 0.015;

uniform float bubble_speed : hint_range(0.0, 3.0) = 0.55;
uniform float bubble_amount : hint_range(0.0, 1.0) = 0.75;
uniform float bubble_size : hint_range(0.01, 0.18) = 0.07;

float rounded_box_sdf(vec2 p, vec2 bounds, float radius) {
	vec2 q = abs(p) - bounds + vec2(radius);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

float circle(vec2 p, vec2 center, float radius) {
	return 1.0 - smoothstep(radius, radius + 0.02, length(p - center));
}

vec2 wobble(vec2 p) {
	p.x += sin(p.y * 2.8 + TIME * wobble_speed) * wobble_strength;
	p.x += sin(p.y * 6.2 - TIME * wobble_speed * 1.4) * wobble_strength * 0.35;
	p.y += sin(p.x * 3.1 - TIME * wobble_speed * 0.85) * wobble_strength * 0.7;
	return p;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = uv * 2.0 - 1.0;
	vec2 wp = wobble(p);

	float sdf = rounded_box_sdf(wp, vec2(0.82, 0.72), roundness);
	float body = 1.0 - smoothstep(0.0, edge_softness, sdf);
	float outline = smoothstep(outline_width + edge_softness, outline_width, abs(sdf));

	float bubbles = 0.0;
	for (int i = 0; i < 10; i++) {
		float fi = float(i);
		float seed = fi + 1.0;
		float lane = mix(-0.72, 0.72, hash(seed * 3.17));
		float drift = (hash(seed * 7.91) - 0.5) * 0.16;
		float phase = fract(hash(seed * 5.73) + TIME * bubble_speed * (0.55 + hash(seed * 1.91)));
		float y = mix(0.95, -0.95, phase);
		float x = lane + sin(TIME * (0.8 + hash(seed * 4.21)) + seed * 2.4) * drift;
		float radius = bubble_size * mix(0.55, 1.1, hash(seed * 9.13));
		bubbles += circle(wp, vec2(x, y), radius) * (0.45 + hash(seed * 2.31) * 0.55);
	}
	bubbles = clamp(bubbles * bubble_amount, 0.0, 1.0) * body;

	vec3 color = fill_color.rgb;
	color = mix(color, bubble_color.rgb, bubbles * bubble_color.a);
	color = mix(color, outline_color.rgb, outline * outline_color.a);

	float alpha = max(body * fill_color.a, outline * outline_color.a);
	alpha = max(alpha, bubbles * bubble_color.a * fill_color.a);

	COLOR = vec4(color, alpha);
}
