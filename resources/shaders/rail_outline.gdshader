shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float rail_origin_z = 0.0;
uniform float min_visible_z = 0.0;

varying float playfield_z;

void vertex() {
	playfield_z = rail_origin_z + VERTEX.z;
}

void fragment() {
	if (playfield_z < min_visible_z) {
		discard;
	}
	ALBEDO = vec3(0.0);
	EMISSION = vec3(0.0);
}
