
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec3 base_col : source_color = vec3(0.1, 0.19, 0.05);
uniform vec3 tip_col : source_color = vec3(0.34, 0.44, 0.16);
varying float hgt;
varying vec3 wpos;
void vertex() {
	hgt = VERTEX.y;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wind = sin(TIME * 2.2 + w.x * 0.45 + w.z * 0.3) * 0.5 + sin(TIME * 3.7 + w.x * 1.3) * 0.2;
	VERTEX.x += wind * hgt * hgt * 0.35;
	VERTEX.z += wind * hgt * hgt * 0.15;
	wpos = w;
}
void fragment() {
	float v = fract(sin(dot(floor(wpos.xz * 0.5), vec2(12.9, 78.2))) * 43758.5);
	ALBEDO = mix(base_col, tip_col * (0.85 + 0.3 * v), clamp(hgt * 2.6, 0.0, 1.0));
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.2, 0.3, 0.1);
}
