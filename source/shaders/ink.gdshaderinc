// Moss / Ink - two-tone print model.
// Warm paper and one charcoal ink. Lighting is computed per pixel, then each
// pixel of the low-resolution render becomes either paper or ink by comparing
// its light against an ordered 4x4 threshold. Tone is read only through dot
// density; cast shadows are solid ink.

uniform vec4 c_paper = vec4(0.659, 0.647, 0.620, 1.0);
uniform vec4 c_ink = vec4(0.157, 0.141, 0.122, 1.0);

// Palette values are authored in sRGB; the compatibility renderer encodes
// the output, so decode them here once.
vec3 ink_lin(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

float ink_bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x * 0.5 + a.y * a.y * 0.75);
}
float ink_bayer4(vec2 a) {
	return ink_bayer2(0.5 * a) * 0.25 + ink_bayer2(a);
}

// v in [0,1]: 0 = solid ink, 1 = bare paper.
vec3 ink_print(float v, vec2 frag) {
	float th = ink_bayer4(frag) + 0.03125;
	return ink_lin(v > th ? c_paper.rgb : c_ink.rgb);
}
