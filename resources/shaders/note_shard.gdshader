shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;

uniform sampler2D shard_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform int shard_columns = 2;
uniform int shard_rows = 1;
uniform bool flip_h = false;

varying flat float shard_index;
varying float life_progress;

void vertex() {
	shard_index = floor(INSTANCE_CUSTOM.x + 0.5);
	life_progress = INSTANCE_CUSTOM.w;
}

void fragment() {
	int columns = max(shard_columns, 1);
	int rows = max(shard_rows, 1);
	int index = int(shard_index);
	int column = index % columns;
	int row = index / columns;
	int source_column = flip_h ? columns - column - 1 : column;

	vec2 local_uv = UV;
	if (flip_h) {
		local_uv.x = 1.0 - local_uv.x;
	}
	vec2 grid = vec2(float(columns), float(rows));
	vec2 texel = 0.65 / vec2(textureSize(shard_texture, 0));
	vec2 tile_min = vec2(float(source_column), float(row)) / grid + texel;
	vec2 tile_max = vec2(float(source_column + 1), float(row + 1)) / grid - texel;
	vec4 sampled = texture(shard_texture, mix(tile_min, tile_max, local_uv));
	if (sampled.a < 0.015) {
		discard;
	}

	float fade = 1.0 - smoothstep(0.56, 1.0, life_progress);
	float glint = 1.0 - smoothstep(0.0, 0.18, life_progress);
	vec3 color = sampled.rgb * tint.rgb;
	ALBEDO = color;
	EMISSION = color * (0.10 + glint * 0.30);
	ALPHA = sampled.a * tint.a * fade;
}
