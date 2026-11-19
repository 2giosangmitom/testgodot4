// PSX face: flat 64x64 face texture on a low-poly head. `distort` (0..1) warps it when an entity
// is close: eyes stretch vertically, mouth drags downward, scanline-row jitter, vertex jitter
// and coarser vertex snapping. To keep a face faintly visible in the dark, set emission_texture
// to the face texture and emission_strength ~0.1-0.3.
shader_type spatial;
render_mode vertex_lighting, cull_back, diffuse_lambert, specular_disabled;

#define PSX_FACE
#include "res://render/shaders/psx_common.gdshaderinc"

group_uniforms face;
uniform float distort : hint_range(0.0, 1.0) = 0.0;
// Face layout in texture V (0 = top): eye line, mouth line.
uniform float eye_line : hint_range(0.0, 1.0) = 0.42;
uniform float mouth_line : hint_range(0.0, 1.0) = 0.72;
uniform float eye_stretch : hint_range(0.0, 4.0) = 1.6;
uniform float mouth_stretch : hint_range(0.0, 4.0) = 2.2;
uniform float row_jitter : hint_range(0.0, 0.5) = 0.12;
uniform float vertex_jitter : hint_range(0.0, 0.2) = 0.03;   // metres
uniform float jitter_fps : hint_range(1.0, 60.0) = 12.0;
group_uniforms;

float psx_face_snap_scale() {
	return mix(1.0, 0.3, distort);
}

void psx_face_vertex(inout vec3 v, vec3 n, float t) {
	if (distort <= 0.0) {
		return;
	}
	float step_t = floor(t * jitter_fps);
	float h = psx_hash13(vec3(v * 37.0) + step_t);
	v += n * (h - 0.5) * 2.0 * vertex_jitter * distort;
}

vec2 psx_face_uv(vec2 uv, float t) {
	if (distort <= 0.0) {
		return uv;
	}
	float d = distort;
	// Eyes: magnify vertically around the eye line (smooth falloff keeps the mapping monotonic).
	float de = uv.y - eye_line;
	float we = exp(-pow(de / 0.12, 2.0));
	uv.y -= de * we * (1.0 - 1.0 / (1.0 + eye_stretch * d));
	// Mouth: everything below the mouth line is dragged down (sampled from higher up).
	float dm = uv.y - mouth_line;
	if (dm > 0.0) {
		uv.y = mouth_line + dm / (1.0 + mouth_stretch * d);
	}
	// Row jitter: a few texel rows slide sideways, re-rolled at jitter_fps.
	float step_t = floor(t * jitter_fps);
	float row = floor(uv.y * 32.0);
	float r = psx_hash12(vec2(row, step_t));
	if (r > 1.0 - 0.45 * d) {
		uv.x += (psx_hash12(vec2(step_t, row * 1.7)) - 0.5) * row_jitter * d * 2.0;
	}
	return uv;
}

#include "res://render/shaders/psx_body.gdshaderinc"
