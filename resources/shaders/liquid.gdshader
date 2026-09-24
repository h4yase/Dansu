shader_type canvas_item;

uniform vec4 water_color : source_color = vec4(0.1, 0.6, 1.0, 1.0);

uniform float water_height = 0.65;
uniform float amplitude = 0.03;
uniform float speed = 1.2;

void fragment() {
	float x = UV.x;

	float wave =
		sin(x * 7.0 + TIME * speed) * amplitude +
		sin(x * 13.0 - TIME * speed * 1.6) * amplitude * 0.5 +
		sin(x * 19.0 + TIME * speed * 0.7) * amplitude * 0.25;

	float surface = water_height + wave;

	float edge = smoothstep(surface - 0.005, surface + 0.005, UV.y);

	COLOR = mix(vec4(0.0), water_color, edge);
}
