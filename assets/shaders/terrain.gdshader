
shader_type spatial;
render_mode diffuse_burley;
uniform vec3 grass_a : source_color = vec3(0.15, 0.27, 0.09);
uniform vec3 grass_b : source_color = vec3(0.3, 0.38, 0.16);
uniform vec3 dry : source_color = vec3(0.55, 0.52, 0.28);
uniform vec3 sand : source_color = vec3(0.82, 0.74, 0.54);
uniform vec3 dirt : source_color = vec3(0.45, 0.34, 0.22);
uniform vec3 paving : source_color = vec3(0.4, 0.39, 0.37);
uniform vec3 rock_a : source_color = vec3(0.32, 0.3, 0.28);
uniform vec3 rock_b : source_color = vec3(0.58, 0.55, 0.5);
varying vec3 wpos;
varying vec3 wnrm;
varying vec4 mask;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; } return v; }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	mask = COLOR;
}
void fragment() {
	vec2 p = wpos.xz;
	float big = fbm(p * 0.02);
	float mid = fbm(p * 0.15);
	float fine = noise(p * 2.5);
	vec3 grass = mix(grass_a, grass_b, big * 0.8 + fine * 0.2);
	grass = mix(grass, dry, smoothstep(0.55, 0.85, fbm(p * 0.05 + 7.0)) * 0.6);
	grass *= 0.85 + 0.3 * mid;
	vec3 col = grass;
	float rough = 0.95;
	// dirt path
	col = mix(col, dirt * (0.8 + 0.4 * mid) * (0.9 + 0.2 * fine), smoothstep(0.3, 0.7, mask.g + (mid - 0.5) * 0.4));
	// sand
	col = mix(col, sand * (0.9 + 0.2 * mid) * (0.95 + 0.1 * fine), smoothstep(0.3, 0.7, mask.r + (mid - 0.5) * 0.3));
	// paving / stone floor
	vec2 tile = fract(p * 1.0);
	float grout = smoothstep(0.0, 0.06, tile.x) * smoothstep(0.0, 0.06, tile.y) * smoothstep(1.0, 0.94, tile.x) * smoothstep(1.0, 0.94, tile.y);
	vec3 pav = paving * (0.75 + 0.35 * hash(floor(p))) * (0.6 + 0.4 * grout);
	col = mix(col, pav, step(0.5, mask.b));
	// rock on slopes and heights
	float slope = 1.0 - wnrm.y;
	vec3 rock = mix(rock_a, rock_b, fbm(vec2(p.x + wpos.y * 0.7, p.y) * 0.25)) * (0.8 + 0.25 * sin(wpos.y * 3.0 + mid * 4.0));
	float rk = smoothstep(0.25, 0.42, slope + (mid - 0.5) * 0.15);
	rk = max(rk, smoothstep(14.0, 22.0, wpos.y + mid * 4.0));
	col = mix(col, rock, rk);
	// snow on peaks
	float snow = smoothstep(30.0, 36.0, wpos.y + mid * 5.0) * smoothstep(0.55, 0.3, slope);
	col = mix(col, vec3(0.92, 0.94, 0.97), snow);
	// wet sand near the water
	col *= mix(0.7, 1.0, smoothstep(-0.3, 0.4, wpos.y));
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.6, snow);
	NORMAL_MAP = normalize(vec3(0.5 + (noise(p * 3.0) - 0.5) * 0.35, 0.5 + (noise(p * 3.0 + 9.0) - 0.5) * 0.35, 1.0));
}
