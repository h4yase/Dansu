shader_type canvas_item;
uniform vec2 box_size = vec2(1.0);
void fragment() {
	vec2 p = UV * box_size;
	float radius = min(3.0, min(box_size.x, box_size.y) * 0.5);
	vec2 q = abs(p - box_size * 0.5) - box_size * 0.5 + radius;
	float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float mask = 1.0 - smoothstep(-0.5, 0.5, distance);
	float border = smoothstep(-1.7, -0.7, distance);
	float stripe = 1.0 - smoothstep(1.0, 2.0, abs(mod(p.x + p.y - TIME * 28.0, 12.0) - 6.0));
	COLOR = vec4(mix(vec3(0.7, 0.65, 1.0), vec3(1.0, 0.945, 0.66), border), mask * mix(0.10 + stripe * 0.14, 0.9, border));
}
