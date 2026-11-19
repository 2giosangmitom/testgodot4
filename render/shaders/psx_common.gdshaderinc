// psx_common.gdshaderinc — shared PSX globals + helper functions.
// Included by every PSX spatial shader. Globals are declared in project.godot [shader_globals]
// and driven by the RenderSettings autoload.

global uniform vec4 psx_fog_color;
global uniform float psx_fog_near;
global uniform float psx_fog_far;
global uniform vec2 psx_snap_resolution;
global uniform float psx_affine_strength;
global uniform float psx_static;
global uniform float psx_time_scale;

const float PSX_BAYER4[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

// Ordered-dither threshold in [-0.5, 0.5) for a pixel coordinate.
float psx_bayer(vec2 frag) {
	ivec2 p = ivec2(mod(floor(frag), 4.0));
	return (PSX_BAYER4[p.y * 4 + p.x] + 0.5) / 16.0 - 0.5;
}

float psx_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float psx_hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 psx_to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 psx_to_linear(vec3 c) {
	return mix(c / 12.92, pow((max(c, vec3(0.0)) + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// 15-bit (5 bits / channel) colour reduction with optional ordered dither.
// Input/output are LINEAR colours; quantisation happens in sRGB like the real hardware.
vec3 psx_reduce_linear(vec3 lin, vec2 frag, float dither) {
	vec3 s = psx_to_srgb(clamp(lin, 0.0, 1.0));
	s += psx_bayer(frag) * dither / 31.0;
	s = floor(clamp(s, 0.0, 1.0) * 31.0 + 0.5) / 31.0;
	return psx_to_linear(s);
}

// Snap a clip-space position to a coarse screen grid (PS1 integer vertex coordinates).
// Only x/y are changed, so depth (z/w) stays correct.
vec4 psx_snap(vec4 clip, vec2 res) {
	if (clip.w > 0.0) {
		vec2 half_res = max(res, vec2(2.0)) * 0.5;
		vec2 ndc = clip.xy / clip.w;
		ndc = round(ndc * half_res) / half_res;
		clip.xy = ndc * clip.w;
	}
	return clip;
}

// 0 = clear, 1 = fully fogged.
float psx_fog_factor(float dist) {
	return clamp((dist - psx_fog_near) / max(psx_fog_far - psx_fog_near, 0.001), 0.0, 1.0);
}

// Fog colour in linear space (the global is authored as an sRGB Color).
vec3 psx_fog_linear() {
	return psx_to_linear(psx_fog_color.rgb);
}
