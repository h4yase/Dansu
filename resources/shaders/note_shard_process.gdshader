shader_type particles;

uniform vec2 full_size = vec2(1.0);
uniform int shard_columns = 2;
uniform int shard_rows = 1;
uniform float burst_speed_min = 1.15;
uniform float burst_speed_max = 2.45;
uniform float vertical_lift = 0.85;
uniform float gravity = 16.0;
uniform float drag = 1.2;
uniform float spin_min = 0.45;
uniform float spin_max = 1.5;
uniform float forward_inertia = 1.0;

float hash(float value) {
	return fract(sin(value * 91.3458 + 17.173) * 47453.5453);
}

void start() {
	int total_shards = max(shard_columns * shard_rows, 1);
	int shard_index = int(NUMBER) % total_shards;
	int column = shard_index % shard_columns;
	int row = shard_index / shard_columns;

	vec2 grid = vec2(float(shard_columns), float(shard_rows));
	vec2 cell = full_size / grid;
	vec2 center = vec2(
		(float(column) + 0.5) * cell.x - full_size.x * 0.5,
		full_size.y * 0.5 - (float(row) + 0.5) * cell.y
	);
	TRANSFORM[3].xyz = vec3(center, 0.0);

	float seed = float(NUMBER) + float(RANDOM_SEED % 65521u) * 0.001;
	float random_a = hash(seed + 1.7);
	float random_b = hash(seed + 8.3);
	float random_c = hash(seed + 19.1);
	vec2 radial = center / max(full_size, vec2(0.001));
	radial.x *= 1.45;
	radial.y = radial.y * 0.72 + vertical_lift;
	radial += vec2(random_a - 0.5, random_b - 0.5) * 0.42;
	radial = normalize(radial + vec2(0.0001));
	float speed = mix(burst_speed_min, burst_speed_max, random_c);
	VELOCITY = vec3(radial * speed, forward_inertia + (random_b - 0.5) * 0.34);

	float spin_direction = random_a < 0.5 ? -1.0 : 1.0;
	float spin_speed = mix(spin_min, spin_max, random_b) * spin_direction;
	CUSTOM = vec4(float(shard_index), spin_speed, (random_c - 0.5) * 0.24, 0.0);
}

void process() {
	CUSTOM.w = clamp(CUSTOM.w + DELTA / max(LIFETIME, 0.001), 0.0, 1.0);
	VELOCITY.y -= gravity * DELTA;
	VELOCITY *= exp(-drag * DELTA);
	TRANSFORM[3].xyz += VELOCITY * DELTA;

	CUSTOM.z += CUSTOM.y * DELTA;
	float shrink = mix(0.7, 0.6, smoothstep(0.45, 1.0, CUSTOM.w));
	float cosine = cos(CUSTOM.z) * shrink;
	float sine = sin(CUSTOM.z) * shrink;
	TRANSFORM[0].xyz = vec3(cosine, sine, 0.0);
	TRANSFORM[1].xyz = vec3(-sine, cosine, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, shrink);
}
