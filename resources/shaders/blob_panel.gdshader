shader_type canvas_item;

uniform vec4 fill_color : source_color = vec4(0.09, 0.08, 0.18, 0.86);
uniform vec4 fill_color_2 : source_color = vec4(0.28, 0.22, 0.62, 0.78);
uniform vec4 rim_color : source_color = vec4(0.80, 0.74, 1.0, 0.9);
uniform vec4 glow_color : source_color = vec4(0.45, 0.40, 0.95, 0.22);
uniform vec4 shadow_color : source_color = vec4(0.02, 0.02, 0.06, 0.46);
uniform float roundness : hint_range(0.05, 0.8) = 0.36;
uniform float wobble_amount : hint_range(0.0, 0.2) = 0.045;
uniform float wobble_speed : hint_range(0.0, 5.0) = 1.0;
uniform float rim_width : hint_range(0.0, 0.2) = 0.035;
uniform float glow_width : hint_range(0.0, 0.3) = 0.11;
uniform vec2 shadow_offset = vec2(0.035, 0.05);

float rounded_box_sdf(vec2 p, vec2 bounds, float radius) {
	vec2 q = abs(p) - bounds + vec2(radius);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

vec2 wobble_uv(vec2 p) {
	p.x += sin(p.y * 3.2 + TIME * wobble_speed) * wobble_amount * 0.26;
	p.x += sin(p.y * 7.6 - TIME * wobble_speed * 1.7) * wobble_amount * 0.11;
	p.y += sin(p.x * 2.9 - TIME * wobble_speed * 0.85) * wobble_amount * 0.22;
	p.y += sin(p.x * 6.5 + TIME * wobble_speed * 1.35) * wobble_amount * 0.08;
	return p;
}

void fragment() {
	vec2 uv = UV;
	vec2 p = uv * 2.0 - 1.0;
	vec2 warped = wobble_uv(p);

	float body_sdf = rounded_box_sdf(warped, vec2(0.84, 0.66), roundness);
	float body = smoothstep(0.03, -0.03, body_sdf);
	float inner = smoothstep(-0.1, -0.42, body_sdf);
	float rim = smoothstep(rim_width, rim_width - 0.02, abs(body_sdf));
	float glow = smoothstep(glow_width, glow_width - 0.04, abs(body_sdf));

	vec2 shadow_pos = warped + shadow_offset;
	float shadow_sdf = rounded_box_sdf(shadow_pos, vec2(0.84, 0.66), roundness);
	float shadow = smoothstep(0.08, -0.06, shadow_sdf) * (1.0 - body);

	float gradient = clamp(uv.y * 0.8 + uv.x * 0.2, 0.0, 1.0);
	vec3 fill = mix(fill_color.rgb, fill_color_2.rgb, gradient);
	fill = mix(fill, fill_color_2.rgb, inner * 0.35);

	float gleam = smoothstep(0.24, -0.18, warped.x * -0.55 + warped.y * -0.85 + sin(TIME * 0.8) * 0.08);

	vec3 color = fill;
	color = mix(color, rim_color.rgb, rim * rim_color.a);
	color += glow_color.rgb * glow * glow_color.a;
	color += rim_color.rgb * gleam * 0.08 * body;
	color = mix(color, shadow_color.rgb, shadow * shadow_color.a);

	float alpha = max(body * fill_color.a, shadow * shadow_color.a);
	alpha = max(alpha, glow * glow_color.a * 0.75);
	COLOR = vec4(color, alpha);
}
