shader_type spatial;
// Layered sandstone of the cactus-shaped rocks of Whisky Peak.
uniform vec3 color_a : source_color = vec3(0.78, 0.5, 0.32);
uniform vec3 color_b : source_color = vec3(0.6, 0.33, 0.22);
uniform float band_size = 1.1;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float n = noise(vec2(wpos.x + wpos.z, wpos.y * 0.5) * 0.6);
	float band = sin(wpos.y / band_size + n * 3.0) * 0.5 + 0.5;
	float fine = noise(vec2(wpos.x * 2.0 + wpos.z * 2.0, wpos.y * 3.0));
	ALBEDO = mix(color_b, color_a, smoothstep(0.25, 0.75, band)) * (0.85 + 0.25 * fine);
	ROUGHNESS = 0.95;
}
