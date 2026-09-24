shader_type canvas_item;
render_mode unshaded;

uniform vec4 bg_color : source_color = vec4(0.08, 0.09, 0.12, 1.0);
uniform vec4 shape_color : source_color = vec4(0.92, 0.95, 1.0, 1.0);

// ColorRect 크기 (GDScript에서 설정)
uniform vec2 rect_size = vec2(1920.0, 1080.0);

// 셀 크기(픽셀)
uniform float cell_size = 180.0;

// 이동 속도 (셀/초)
uniform float move_speed = 0.025;

// 도형 변환 속도
uniform float cycle_speed = 0.45;

uniform float transition_ratio = 0.12;
uniform float softness = 0.008;

uniform float circle_size = 0.22;
uniform float square_size = 0.22;
uniform float triangle_size = 0.44;

uniform float square_roundness = 0.05;
uniform float triangle_roundness = 0.025;

mat2 rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(
		vec2(c, -s),
		vec2(s, c)
	);
}

float sd_circle(vec2 p, float r) {
	return length(p) - r;
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float sd_triangle_up(vec2 p, float size) {
	p.x = abs(p.x);
	return max(p.x * 0.8660254 + p.y * 0.5, -p.y) - size * 0.5;
}

float op_round(float d, float r) {
	return d - r;
}

float shape_circle(vec2 p) {
	return sd_circle(p, circle_size);
}

float shape_square(vec2 p) {
	return op_round(sd_box(p, vec2(square_size)), square_roundness);
}

float shape_triangle(vec2 p) {
	return op_round(sd_triangle_up(p, triangle_size), triangle_roundness);
}

float blend_shapes(vec2 p, float phase) {
	float d_circle = shape_circle(p);
	float d_square = shape_square(p);
	float d_triangle = shape_triangle(p);

	float seg = phase * 3.0;
	float trans = clamp(transition_ratio, 0.001, 0.49);

	if (seg < 1.0) {
		float t = smoothstep(1.0 - trans, 1.0, seg);
		return mix(d_circle, d_square, t);
	}
	else if (seg < 2.0) {
		float t = smoothstep(1.0 - trans, 1.0, seg - 1.0);
		return mix(d_square, d_triangle, t);
	}

	float t = smoothstep(1.0 - trans, 1.0, seg - 2.0);
	return mix(d_triangle, d_circle, t);
}

void fragment() {
	// 픽셀 좌표계
	vec2 pixel = UV * rect_size;

	// 이동
	pixel += vec2(-1.0, 1.0) * TIME * move_speed * cell_size;

	// 셀 좌표계
	vec2 grid_uv = pixel / cell_size;

	vec2 cell = floor(grid_uv);
	vec2 local = fract(grid_uv) - 0.5;

	local *= rot(-0.35);

	float seed = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
	float phase = fract(TIME * cycle_speed + seed * 0.35);

	float d = blend_shapes(local, phase); 
	float mask = 1.0 - smoothstep(0.0, softness, d);

	COLOR = mix(bg_color, shape_color, mask);
}