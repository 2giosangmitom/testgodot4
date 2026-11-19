// psx_body.gdshaderinc — standard PSX surface (uniforms + vertex() + fragment()).
// Include AFTER psx_common.gdshaderinc. Variant switches (#define before including):
//   PSX_UNLIT  — unshaded output (signs, sky cards, emissive tubes)
//   PSX_FACE   — calls psx_face_vertex(inout vec3 v, vec3 n, float t) / psx_face_uv(vec2 uv, float t)
//                and psx_face_snap_scale() which the including shader must define first.

uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool use_vertex_color = false;
uniform bool use_alpha_scissor = false;
uniform float alpha_scissor_threshold : hint_range(0.0, 1.0) = 0.5;

group_uniforms emission;
uniform sampler2D emission_texture : source_color, filter_nearest, repeat_enable, hint_default_white;
uniform vec4 emission_color : source_color = vec4(1.0);
uniform float emission_strength : hint_range(0.0, 16.0) = 0.0;
#ifdef PSX_UNLIT
// Unlit brightness multiplier, and how bright the surface stays when emit_level = 0 (tube "off").
uniform float brightness : hint_range(0.0, 8.0) = 1.0;
uniform float off_level : hint_range(0.0, 1.0) = 0.12;
#endif
group_uniforms;

group_uniforms psx;
// Per-material scale of the global affine strength. Big floor/wall planes: 0.2–0.5.
uniform float affine_mult : hint_range(0.0, 1.0) = 1.0;
uniform bool vertex_snap = true;
// Per-material snap resolution multiplier (<1 = coarser wobble).
uniform float snap_mult : hint_range(0.05, 4.0) = 1.0;
uniform float fog_mult : hint_range(0.0, 1.0) = 1.0;
uniform bool color_reduce = true;
uniform float dither_strength : hint_range(0.0, 1.0) = 1.0;
group_uniforms;

// Per-instance emission level (FlickerLight drives this on the tube mesh). 1 = on, 0 = off.
instance uniform float emit_level = 1.0;

varying vec3 v_affine_uv;   // xy = UV * w, z = w

void vertex() {
	UV = UV * uv_scale + uv_offset;
#ifdef PSX_FACE
	psx_face_vertex(VERTEX, NORMAL, TIME * psx_time_scale);
#endif
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (vertex_snap) {
		float sm = snap_mult;
#ifdef PSX_FACE
		sm *= psx_face_snap_scale();
#endif
		clip = psx_snap(clip, psx_snap_resolution * sm);
	}
	POSITION = clip;
	v_affine_uv = vec3(UV * clip.w, clip.w);
}

void fragment() {
	vec2 uv = UV;
	float aff = clamp(psx_affine_strength * affine_mult, 0.0, 1.0);
	if (aff > 0.0) {
		uv = mix(UV, v_affine_uv.xy / v_affine_uv.z, aff);
	}
#ifdef PSX_FACE
	uv = psx_face_uv(uv, TIME * psx_time_scale);
#endif
	vec4 col = texture(albedo_texture, uv) * albedo_color;
	if (use_vertex_color) {
		col *= COLOR;
	}
	if (use_alpha_scissor && col.a < alpha_scissor_threshold) {
		discard;
	}
	vec3 c = col.rgb;
	if (color_reduce) {
		c = psx_reduce_linear(c, FRAGCOORD.xy, dither_strength);
	}
	vec3 emis = texture(emission_texture, uv).rgb * emission_color.rgb * emission_strength * emit_level;
	float f = psx_fog_factor(length(VERTEX)) * fog_mult;
	vec3 fog = psx_fog_linear();
#ifdef PSX_UNLIT
	vec3 lit = c * brightness * mix(off_level, 1.0, clamp(emit_level, 0.0, 1.0)) + emis;
	ALBEDO = mix(lit, fog, f);
#else
	// Lit: final = ALBEDO * light + EMISSION. Scaling albedo by (1-f) and blending emission
	// toward the fog colour gives final = mix(lit_colour, fog, f) regardless of lighting.
	ALBEDO = c * (1.0 - f);
	EMISSION = mix(emis, fog, f);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
#endif
}
