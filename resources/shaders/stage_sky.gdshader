shader_type sky;

uniform vec4 base_color : source_color = vec4(0.025, 0.018, 0.055, 1.0);
uniform vec4 detail_color : source_color = vec4(0.24, 0.16, 0.42, 1.0);
uniform vec4 rail_color : source_color = vec4(0.575, 0.520, 0.860, 1.0);
uniform float mountain_opacity : hint_range(0.0, 1.0) = 0.85;
uniform float mountain_line_strength : hint_range(0.0, 0.03) = 0.0144;

float mountain_hash(vec2 seed) {
	vec3 value = fract(vec3(seed.xyx) * 0.1031);
	value += dot(value, value.yzx + 33.33);
	return fract((value.x + value.y) * value.z);
}

vec3 mountain_barycentric(vec2 point, vec2 a, vec2 b, vec2 c) {
	vec2 ab = b - a;
	vec2 ac = c - a;
	vec2 ap = point - a;
	float area = ab.x * ac.y - ab.y * ac.x;
	float v = (ap.x * ac.y - ap.y * ac.x) / area;
	float w = (ab.x * ap.y - ab.y * ap.x) / area;
	return vec3(1.0 - v - w, v, w);
}

vec2 mountain_vertex(float column, float row, float layer) {
	float width = 0.24 + layer * 0.05;
	float seed = layer * 29.0;
	float x = (column + mountain_hash(vec2(column, seed + row)) * 0.34) * width;
	float baseline = 0.47 - abs(x - layer * 3.71) * 0.025 - layer * 0.008;
	float top = baseline + 0.015 + mountain_hash(vec2(column, seed + 7.0)) * 0.15;
	float bottom = baseline - 0.24 - mountain_hash(vec2(column, seed + 11.0)) * 0.045;
	float middle = mix(bottom, top, 0.35 + mountain_hash(vec2(column, seed + 17.0)) * 0.30);
	float y = row < 0.5 ? bottom : (row < 1.5 ? middle : top);
	return vec2(x, y);
}

vec3 mountain_layer(vec3 background, vec2 point, float layer, float time, float camera_x) {
	float baseline = 0.47 - abs(point.x) * 0.025 - layer * 0.008;
	if (mountain_opacity <= 0.0 || point.y < baseline - 0.34 || point.y > baseline + 0.20 || abs(point.x) < 0.10) {
		return background;
	}
	float drift = time * (0.002 + layer * 0.0015) + camera_x * (layer + 1.0) * 0.001;
	vec2 position = vec2(point.x + drift + layer * 3.71, point.y);
	float width = 0.24 + layer * 0.05;
	float column = floor(position.x / width);
	float side_fade = smoothstep(0.10, 0.50, abs(point.x));
	vec3 brightness_weights = vec3(0.2126, 0.7152, 0.0722);
	vec3 dark_color = dot(base_color.rgb, brightness_weights) <= dot(detail_color.rgb, brightness_weights)
		? base_color.rgb : detail_color.rgb;

	// Shared, jittered vertices form irregular faces along the ridge.
	for (int offset = -1; offset <= 0; offset++) {
		float left = column + float(offset);
		vec2 vertices[6];
		for (int row = 0; row < 3; row++) {
			vertices[row * 2] = mountain_vertex(left, float(row), layer);
			vertices[row * 2 + 1] = mountain_vertex(left + 1.0, float(row), layer);
		}
		float top_progress = clamp((position.x - vertices[4].x) / (vertices[5].x - vertices[4].x), 0.0, 1.0);
		float bottom_progress = clamp((position.x - vertices[0].x) / (vertices[1].x - vertices[0].x), 0.0, 1.0);
		float top_y = mix(vertices[4].y, vertices[5].y, top_progress);
		float bottom_y = mix(vertices[0].y, vertices[1].y, bottom_progress);
		float boundary_fade = smoothstep(0.0, 0.035, top_y - position.y);
		boundary_fade *= smoothstep(0.0, 0.18, position.y - bottom_y);
		for (int band = 0; band < 2; band++) {
			int start = band * 2;
			bool flip = mountain_hash(vec2(left, layer * 13.0 + float(band))) > 0.5;
			for (int triangle = 0; triangle < 2; triangle++) {
				vec2 a = vertices[start];
				vec2 b = vertices[start + 1];
				vec2 c = vertices[start + 2];
				if (flip) {
					c = vertices[start + 3];
					if (triangle == 1) {
						b = vertices[start + 3];
						c = vertices[start + 2];
					}
				} else if (triangle == 1) {
					a = vertices[start + 1];
					b = vertices[start + 3];
					c = vertices[start + 2];
				}
				vec3 barycentric = mountain_barycentric(position, a, b, c);
				if (min(barycentric.x, min(barycentric.y, barycentric.z)) < 0.0) {
					continue;
				}
				vec2 face_id = vec2(left + layer * 31.0, float(band * 2 + triangle));
				float shade = mountain_hash(face_id);
				float cycle_time = (time + shade * 29.0) / (17.0 + shade * 11.0);
				float phase = fract(cycle_time);
				float pulse = smoothstep(0.10, 0.17, phase) * (1.0 - smoothstep(0.20, 0.32, phase));
				pulse *= step(0.84, mountain_hash(face_id + floor(cycle_time) * 5.37));
				float mask = side_fade * boundary_fade * mountain_opacity;
				float saturation = 0.84 + mountain_hash(face_id + vec2(19.7, 8.3)) * 0.10;
				float base_value = max(base_color.r, max(base_color.g, base_color.b));
				vec3 face_color = mix(vec3(base_value), base_color.rgb, saturation);
				face_color *= (0.40 + layer * 0.02) * (0.75 + shade * 0.50 + pulse * 0.10);
				float area = abs((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x));
				vec3 edge_distances = barycentric * area / vec3(length(b - c), length(a - c), length(a - b));
				float edge_distance = min(edge_distances.x, min(edge_distances.y, edge_distances.z));
				float edge = 1.0 - smoothstep(0.00046, 0.00184, edge_distance);
				float glow = exp(-edge_distance * 350.0);
				vec3 color = mix(background, face_color, mask);
				color += (rail_color.rgb * edge + dark_color * glow * 0.20) * mountain_line_strength * mask;
				return color;
			}
		}
	}
	return background;
}

void sky() {
	// Perspective frames surround the highway; its vanishing point stays quiet.
	vec2 point = EYEDIR.xy / max(abs(EYEDIR.z), 0.2);
	float height = point.y - 0.52;
	float side = abs(point.x);
	float horizon = exp(-abs(height) * 7.0);
	float center_quiet = smoothstep(0.08, 0.48, side);
	vec3 color = base_color.rgb * 0.55;

	// Distant landscape sits behind the original approaching frames.
	for (int layer = 0; layer < 3; layer++) {
		color = mountain_layer(color, point, float(layer), TIME, POSITION.x);
	}
	// Apply the original background lighting after the landscape so it stays visible.
	color += detail_color.rgb * horizon * (0.035 + center_quiet * 0.13);

	float frame_distance = max(side * 0.72 + max(height, 0.0) * 0.18, height * 1.35);
	float frame_light = 0.0;
	float frame_body = 0.0;
	for (int index = 0; index < 6; index++) {
		// Fade both the light and body to zero before wrapping back into the distance.
		float progress = fract(float(index) / 6.0 + TIME / 48.0);
		float visibility = smoothstep(0.0, 0.14, progress);
		visibility *= 1.0 - smoothstep(0.82, 1.0, progress);
		float radius = 0.075 * pow(46.6667, progress);
		float distance_to_frame = abs(frame_distance - radius);
		float width = 0.0015 + radius * 0.002;
		float edge = 1.0 - smoothstep(width, width * 2.5, distance_to_frame);
		float glow = exp(-distance_to_frame / (width * 6.0));
		frame_light += (edge * 0.22 + glow * 0.065) * (0.65 + progress * 0.42) * visibility;
		frame_body += (1.0 - smoothstep(width * 3.0, width * 11.0, distance_to_frame)) * visibility;
	}
	float above_floor = smoothstep(-0.10, 0.03, height);
	color *= 1.0 - frame_body * above_floor * 0.35;
	color += detail_color.rgb * frame_light * above_floor;

	// Broad, slow light behind the architecture, with no flashing or scanning.
	float haze = exp(-pow((side - 0.58 - sin(TIME * 0.08) * 0.04) * 3.0, 2.0));
	haze *= exp(-abs(height - 0.18) * 3.8);
	color += detail_color.rgb * haze * 0.09;

	COLOR = color;
}
