// Moss / Ink - shared ink model.
// Lighting is computed per pixel, then quantised to a five-ink palette.
// The dither threshold is anchored to the surface (rest-pose world position),
// and its scale follows the on-screen footprint in power-of-two octaves, so
// dots stay attached to the world instead of swimming with the camera.

uniform vec4 c_deep = vec4(0.110, 0.153, 0.196, 1.0);
uniform vec4 c_mid = vec4(0.286, 0.329, 0.369, 1.0);
uniform vec4 c_ash = vec4(0.541, 0.576, 0.608, 1.0);
uniform vec4 c_fog = vec4(0.851, 0.867, 0.878, 1.0);
uniform vec4 c_lift = vec4(0.933, 0.941, 0.945, 1.0);
uniform vec4 c_berry = vec4(0.643, 0.247, 0.341, 1.0);
uniform float cell_px = 2.0;

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
float ink_bayer8(vec2 a) {
	return ink_bayer4(0.5 * a) * 0.25 + ink_bayer2(a);
}

// p: rest world position, n: world normal. Returns a threshold in [0,1).
float ink_threshold(vec3 p, vec3 n) {
	vec3 an = abs(n);
	vec2 uv = (an.y >= an.x && an.y >= an.z) ? p.xz : ((an.x >= an.z) ? p.zy : p.xy);
	// world length covered by one pixel, measured on the surface itself
	float footprint = sqrt(length(cross(dFdx(p), dFdy(p))));
	float l = log2(max(footprint * cell_px, 1e-5));
	float lo = floor(l);
	float t = l - lo;
	float s = exp2(lo);
	float a = ink_bayer8(uv / s);
	float b = ink_bayer8(uv / (s * 2.0));
	return mix(a, b, t);
}

vec3 ink_pick(float lum, float th, bool berry) {
	float q = clamp(lum, 0.0, 0.999) * 4.0;
	float lvl = floor(q) + step(th, fract(q));
	vec3 c = lvl < 0.5 ? c_deep.rgb : (lvl < 1.5 ? c_mid.rgb : (lvl < 2.5 ? c_ash.rgb : (lvl < 3.5 ? c_fog.rgb : c_lift.rgb)));
	if (berry && lvl > 1.5) {
		c = lvl > 2.5 ? c_berry.rgb : mix(c_mid.rgb, c_berry.rgb, 0.55);
	}
	return ink_lin(c);
}
