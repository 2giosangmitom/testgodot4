// PSX glass (store windows, fridge doors): tinted alpha blend, fake reflection from a low-res
// texture (looked up by world reflection vector), fresnel edge brightening, PSX fog, snapping.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, specular_disabled;

#include "res://render/shaders/psx_common.gdshaderinc"

uniform vec4 tint : source_color = vec4(0.70, 0.82, 0.80, 0.16);
// Unlit glass would glow at night: tint colour is scaled by this (alpha is not).
uniform float tint_energy : hint_range(0.0, 2.0) = 0.35;
// Optional dirt/smudge/sticker texture: drawn over the tint with opacity = tex.a * texture_opacity.
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_enable, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float texture_opacity : hint_range(0.0, 1.0) = 0.0;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);

group_uniforms reflection;
uniform sampler2D reflection_texture : source_color, filter_nearest, repeat_enable, hint_default_black;
uniform float reflection_strength : hint_range(0.0, 2.0) = 0.35;
// Procedural streaks (fake reflected tube lights) when no reflection texture is set.
uniform float streak_strength : hint_range(0.0, 1.0) = 0.07;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.35;
group_uniforms;

group_uniforms psx;
uniform float affine_mult : hint_range(0.0, 1.0) = 1.0;
uniform bool vertex_snap = true;
uniform float snap_mult : hint_range(0.05, 4.0) = 1.0;
uniform float fog_mult : hint_range(0.0, 1.0) = 1.0;
uniform bool color_reduce = true;
uniform float dither_strength : hint_range(0.0, 1.0) = 1.0;
group_uniforms;

varying vec3 v_affine_uv;
varying vec3 v_world_n;
varying vec3 v_world_pos;

void vertex() {
	UV = UV * uv_scale + uv_offset;
	v_world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	if (vertex_snap) {
		clip = psx_snap(clip, psx_snap_resolution * snap_mult);
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
	vec4 dirt = texture(albedo_texture, uv) * albedo_color;
	vec3 glass_tint = tint.rgb;
	if (OUTPUT_IS_SRGB) {
		dirt.rgb = psx_to_linear(dirt.rgb);
		glass_tint = psx_to_linear(glass_tint);
	}

	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 view_dir = normalize(v_world_pos - cam);
	vec3 n = normalize(v_world_n);
	if (dot(n, view_dir) > 0.0) {
		n = -n;   // double-sided glass
	}
	float ndv = clamp(-dot(n, view_dir), 0.0, 1.0);
	float fres = pow(1.0 - ndv, fresnel_power) * fresnel_strength;

	vec3 r = reflect(view_dir, n);
	vec2 ruv = vec2(atan(r.x, r.z) / 6.2831853 + 0.5, 0.5 - r.y * 0.5);
	vec3 refl = texture(reflection_texture, ruv).rgb;
	if (OUTPUT_IS_SRGB) {
		refl = psx_to_linear(refl);
	}
	refl *= reflection_strength;
	// Fake streaks: thin bright vertical bands sliding with the reflection direction.
	float streak = step(0.93, fract(ruv.x * 7.0 + v_world_pos.y * 0.05)) * step(0.35, ruv.y) * step(ruv.y, 0.75);
	refl += vec3(streak * streak_strength);

	float ta = dirt.a * texture_opacity;
	vec3 c = mix(glass_tint * tint_energy, dirt.rgb, ta) + refl + vec3(fres) * 0.3;
	float a = clamp(max(tint.a, ta) + fres + dot(refl, vec3(0.333)), 0.0, 1.0);

	if (color_reduce) {
		c = psx_reduce_linear(c, FRAGCOORD.xy, dither_strength);
	}
	float f = psx_fog_factor(length(VERTEX)) * fog_mult;
	vec3 fogged = mix(c, psx_fog_linear(), f);
	ALBEDO = OUTPUT_IS_SRGB ? psx_to_srgb(fogged) : fogged;
	ALPHA = a;
}
