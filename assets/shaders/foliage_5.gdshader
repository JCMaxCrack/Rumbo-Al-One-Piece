
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec3 leaf : source_color;
varying vec3 wpos;
varying float lh;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
void vertex() {
	lh = VERTEX.y;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = max(VERTEX.y - 1.0, 0.0) * 0.035;
	VERTEX.x += sin(TIME * 1.6 + w.x * 0.3 + w.z * 0.2) * sway;
	VERTEX.z += cos(TIME * 1.3 + w.z * 0.3) * sway * 0.7;
	wpos = w;
}
void fragment() {
	float n = hash(floor(wpos * 6.0));
	vec3 col = leaf * (0.7 + 0.45 * n);
	col *= mix(0.6, 1.1, clamp((lh - 1.5) * 0.25, 0.0, 1.0));
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SSS_STRENGTH = 0.3;
	BACKLIGHT = vec3(0.25, 0.35, 0.1);
}
