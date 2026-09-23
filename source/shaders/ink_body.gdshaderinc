uniform float wind = 0.34;
uniform vec3 wind_dir = vec3(0.8, 0.0, 0.6);
uniform float edge = 0.16;

varying vec3 v_rest;
varying vec4 v_col;
varying vec3 v_nw;
varying float v_th;

void vertex() {
	v_rest = VERTEX;
	v_col = COLOR;
	float w = COLOR.r;
	if (w > 0.001) {
		float ph = dot(VERTEX.xz, vec2(0.9, 1.3));
		float g = sin(TIME * 1.3 + ph) * 0.55 + sin(TIME * 2.9 + ph * 1.7) * 0.2 + sin(TIME * 0.41 + ph * 0.23) * 0.45;
		float amp = wind * (0.35 + 0.65 * wind);
		vec3 off = wind_dir * (g * 0.16 + 0.1 * wind) * amp * w * w;
		VERTEX += off;
		VERTEX.y -= length(off) * 0.35 * w;
	}
}

void fragment() {
	ALBEDO = vec3(1.0);
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_nw = nw;
	v_th = ink_threshold(v_rest, nw);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float sun = clamp(ndl * 1.1, 0.0, 1.0) * ATTENUATION;
	float hemi = 0.5 + 0.5 * v_nw.y;
	float lum = v_col.g * (0.1 + 0.72 * sun + 0.3 * hemi) * mix(0.5, 1.0, v_col.a);
	vec3 c = ink_pick(lum, v_th, v_col.b > 0.5);
#ifdef INK_EDGE
	if (dot(NORMAL, VIEW) < edge) {
		c = ink_lin(c_deep.rgb);
	}
#endif
	DIFFUSE_LIGHT = c;
	SPECULAR_LIGHT = vec3(0.0);
}
