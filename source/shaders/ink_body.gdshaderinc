uniform float wind = 0.34;
uniform vec3 wind_dir = vec3(0.8, 0.0, 0.6);
uniform float edge = 0.22;

varying vec4 v_col;
varying vec3 v_nw;
varying vec2 v_frag;

vec3 ink_sway(vec3 p, float w, float t) {
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
	v_col = COLOR;
	VERTEX = ink_sway(VERTEX, COLOR.r, TIME);
}

void fragment() {
	ALBEDO = vec3(1.0);
	v_nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_frag = FRAGCOORD.xy;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = clamp(ndl, 0.0, 1.0);
	float shadow = ATTENUATION < 0.5 ? 1.0 : 0.0;
	float hemi = 0.5 + 0.5 * v_nw.y;
	// bounce floor keeps undersides as dense dots instead of solid ink
	float v = v_col.g * (0.34 + 0.6 * lit + 0.22 * hemi) * mix(0.75, 1.0, v_col.a);
	v = max(smoothstep(0.1, 0.66, v), 0.2 * v_col.g);
	vec3 c = ink_print(v, v_frag);
	// stems and spokes (blue channel 0.5) are solid ink lines
	if (abs(v_col.b - 0.5) < 0.1) {
		c = ink_lin(c_ink.rgb);
	}
#ifdef INK_THIN
	// grass, stems and leaves are pure ink strokes; petals keep their shading
	if (v_col.g < 0.9) {
		c = ink_lin(c_ink.rgb);
	}
#endif
	// cast shadows: solid ink, hard edged
	if (shadow > 0.5 && ndl > 0.0) {
		c = ink_lin(c_ink.rgb);
	}
#ifdef INK_EDGE
	if (dot(NORMAL, VIEW) < edge) {
		c = ink_lin(c_ink.rgb);
	}
#endif
	DIFFUSE_LIGHT = c;
	SPECULAR_LIGHT = vec3(0.0);
}
