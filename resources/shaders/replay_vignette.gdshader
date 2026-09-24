shader_type canvas_item;

uniform vec4 dot_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

/* 중앙에 항상 열려있는 gameplay 영역 */
uniform vec2 open_area = vec2(0.72, 0.58);

/* 링 사이 거리 */
uniform float ring_spacing : hint_range(6.0, 64.0) = 18.0;

/* 점 간격 */
uniform float dot_spacing : hint_range(4.0, 64.0) = 16.0;

/* 최대 점 반지름 */
uniform float max_dot_radius : hint_range(1.0, 20.0) = 7.0;

/* 중앙 근처에서 점이 작아지는 거리 */
uniform float shrink_distance : hint_range(10.0, 800.0) = 260.0;

/* 이동 속도(px/sec) */
uniform float speed : hint_range(0.0, 200.0) = 12.0;

/* 원 가장자리 부드러움 */
uniform float softness : hint_range(0.1, 4.0) = 1.0;

/*
2.0 = 완전 원
4.0~6.0 = 둥근 사각형 느낌
너가 원하는 느낌은 4.5 전후 추천
*/
uniform float squareness : hint_range(2.0, 10.0) = 4.5;


float sd_box(vec2 p, vec2 half_size) {
	vec2 q = abs(p) - half_size;
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
}


/* superellipse 거리: 원 -> 둥근사각형 */
float squircle_length(vec2 p, float n) {
	vec2 ap = abs(p);
	return pow(pow(ap.x, n) + pow(ap.y, n), 1.0 / n);
}


/*
주어진 방향(dir)을 해당 superellipse 경계 위 점으로 투영.
dir는 normalize된 방향 벡터라고 가정.
*/
vec2 squircle_direction(vec2 dir, float n) {
	vec2 ad = abs(dir);
	float denom = pow(pow(ad.x, n) + pow(ad.y, n), 1.0 / n);
	if (denom <= 0.00001) {
		return vec2(0.0);
	}
	return dir / denom;
}


void fragment() {
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 center = screen_size * 0.5;

	vec2 pixel = UV * screen_size;
	vec2 p = pixel - center;


	/* -----------------------------
	   중앙 gameplay 영역
	   ----------------------------- */

	vec2 box_half = screen_size * open_area * 0.5;
	float pixel_box_distance = sd_box(p, box_half);


	/* -----------------------------
	   둥근 사각형 기반 inward loop
	   ----------------------------- */

	float travel = TIME * speed;
	float phase = fract(travel / ring_spacing) * ring_spacing;

	/*
	기존 length(p) 대신 superellipse 거리 사용.
	그래서 링 자체가 동그라미가 아니라
	둥근 사각형 쪽으로 변함.
	*/
	float distance_from_center = squircle_length(p, squareness);

	float ring_index = floor((distance_from_center + phase) / ring_spacing + 0.5);
	float ring_radius = ring_index * ring_spacing - phase;


	/* -----------------------------
	   점 각도 배치는 고정해서
	   루프 끊김 방지
	   ----------------------------- */

	float reference_radius = length(screen_size) * 0.5 + ring_spacing * 2.0;

	float dot_count = max(
		floor(TAU * reference_radius / dot_spacing),
		16.0
	);

	float angle_step = TAU / dot_count;

	float angle = atan(p.y, p.x);
	float dot_index = floor(angle / angle_step + 0.5);
	float dot_angle = dot_index * angle_step;

	vec2 circular_dir = vec2(cos(dot_angle), sin(dot_angle));

	/*
	원 방향을 superellipse 경계 방향으로 변형.
	이게 사각형스러운 진행감을 만듦.
	*/
	vec2 shaped_dir = squircle_direction(circular_dir, squareness);

	vec2 dot_center = shaped_dir * ring_radius;


	/* -----------------------------
	   중앙 박스 근처에서 점 작아짐
	   ----------------------------- */

	float distance_to_box = sd_box(dot_center, box_half);

	float size_factor = smoothstep(
		0.0,
		shrink_distance,
		max(distance_to_box, 0.0)
	);

	float radius = max_dot_radius * size_factor;


	/* -----------------------------
	   점 렌더링
	   ----------------------------- */

	float circle_distance = length(p - dot_center);

	float dot_mask = 1.0 - smoothstep(
		radius - softness,
		radius + softness,
		circle_distance
	);


	/* 중앙 gameplay 영역은 완전히 비움 */
	float outside_box = smoothstep(-1.0, 1.0, pixel_box_distance);
	dot_mask *= outside_box;


	/* 중심 지나간 링 제거 */
	if (ring_radius <= 0.0) {
		dot_mask = 0.0;
	}

	COLOR = vec4(
		dot_color.rgb,
		dot_color.a * dot_mask
	);
}