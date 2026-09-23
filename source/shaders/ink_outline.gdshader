shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, shadows_disabled, ambient_light_disabled;
// Inverted hull: a one-pixel ink line around every thick silhouette.
#include "res://shaders/ink.gdshaderinc"
uniform float wind = 0.34;
uniform vec3 wind_dir = vec3(0.8, 0.0, 0.6);
uniform float line_px = 1.0;

vec3 sway(vec3 p, float w, float t) {
	if (w <= 0.001) {
		return p;
	}
	float ph = dot(p.xz, vec2(0.9, 1.3));
	float g = sin(t * 1.3 + ph) * 0.55 + sin(t * 2.9 + ph * 1.7) * 0.2 + sin(t * 0.41 + ph * 0.23) * 0.45;
	float amp = wind * (0.35 + 0.65 * wind);
	vec3 off = wind_dir * (g * 0.16 + 0.1 * wind) * amp * w * w;
	p += off;
	p.y -= length(off) * 0.35 * w;
	return p;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wc = (MODEL_MATRIX * vec4(UV.x, UV2.x, UV.y, 1.0)).xyz;
	wp = sway(ink_soft(wp, wc, UV2.y, TIME), COLOR.r, TIME);
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	vec2 dir = (PROJECTION_MATRIX * VIEW_MATRIX * vec4(wn, 0.0)).xy;
	if (dot(dir, dir) > 1e-8) {
		clip.xy += normalize(dir) * line_px * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = ink_lin(c_ink.rgb);
}
