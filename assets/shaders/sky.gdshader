
shader_type sky;
uniform vec3 top : source_color = vec3(0.16, 0.38, 0.72);
uniform vec3 horizon : source_color = vec3(0.68, 0.8, 0.9);
uniform vec3 below : source_color = vec3(0.2, 0.3, 0.4);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 6; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; } return v; }
void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col = mix(horizon, top, pow(clamp(y, 0.0, 1.0), 0.6));
	if (y < 0.0) { col = mix(horizon, below, clamp(-y * 4.0, 0.0, 1.0)); }
	vec3 sd = LIGHT0_DIRECTION;
	float sun = max(dot(d, sd), 0.0);
	col += vec3(1.0, 0.85, 0.6) * pow(sun, 8.0) * 0.35 + vec3(1.0, 0.95, 0.85) * smoothstep(0.9993, 0.9997, sun) * 4.0;
	if (y > 0.0) {
		vec2 uv = d.xz / (y + 0.15) * 1.2 + vec2(TIME * 0.005, TIME * 0.002);
		float c = fbm(uv * 1.5);
		float cloud = smoothstep(0.5, 0.78, c) * smoothstep(0.0, 0.18, y);
		vec3 cc = mix(vec3(0.75, 0.78, 0.82), vec3(1.0), smoothstep(0.55, 0.9, c));
		col = mix(col, cc, cloud * 0.9);
	}
	COLOR = col;
}
