shader_type spatial;
// The sea of the voyage: one big plane that follows the camera (scripts/world.gd). The waves are the
// same as Ship.wave_height(). Near every island a mask (r = 1 at the coast) gives the shallow colour
// and the foam: rect_N = (x, z, width, depth) of the mask in the world.
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;
uniform vec3 deep : source_color = vec3(0.02, 0.16, 0.3);
uniform vec3 shallow : source_color = vec3(0.1, 0.55, 0.6);
uniform sampler2D shore0 : filter_linear, repeat_disable;
uniform sampler2D shore1 : filter_linear, repeat_disable;
uniform sampler2D shore2 : filter_linear, repeat_disable;
uniform vec4 rect0 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 rect1 = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 rect2 = vec4(0.0, 0.0, 0.0, 0.0);
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float waves(vec2 p, float t) {
	return sin(p.x * 0.18 + t * 1.1) * 0.22 + sin(p.y * 0.23 - t * 0.9 + p.x * 0.07) * 0.18 + sin((p.x + p.y) * 0.5 + t * 1.8) * 0.06;
}
float shore_at(sampler2D tex, vec4 r, vec2 p) {
	if (r.z <= 0.0) { return 0.0; }
	vec2 uv = (p - r.xy) / r.zw;
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) { return 0.0; }
	return texture(tex, uv).r;
}
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += waves(w.xz, TIME);
	wpos = w;
}
void fragment() {
	vec2 p = wpos.xz;
	float sh = max(shore_at(shore0, rect0, p), max(shore_at(shore1, rect1, p), shore_at(shore2, rect2, p)));
	float e = 0.4;
	float t = TIME;
	float hx = waves(p + vec2(e, 0.0), t) - waves(p - vec2(e, 0.0), t);
	float hz = waves(p + vec2(0.0, e), t) - waves(p - vec2(0.0, e), t);
	float ripple = noise(p * 1.5 + t * 0.6) - 0.5;
	vec3 n = normalize(vec3(-hx * 1.5 + ripple * 0.15, 1.0, -hz * 1.5 + ripple * 0.15));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 col = mix(deep, shallow, sh);
	float foam = smoothstep(0.75, 0.95, sh + (noise(p * 0.8 + t * 0.4) - 0.5) * 0.35) * (0.6 + 0.4 * sin(t * 2.0 + sh * 12.0));
	// white caps far from the coast
	float caps = smoothstep(0.82, 0.95, noise(p * 0.12 + vec2(t * 0.05, -t * 0.03))) * smoothstep(0.62, 0.8, noise(p * 0.9 + t * 0.5)) * (1.0 - sh);
	col = mix(col, vec3(0.95), max(foam * 0.8, caps * 0.5));
	ALBEDO = col + fres * 0.08;
	ALPHA = mix(1.0, 0.6, sh * (1.0 - foam));
	ROUGHNESS = mix(0.04, 0.6, foam);
	METALLIC = 0.0;
	SPECULAR = 0.8;
}
