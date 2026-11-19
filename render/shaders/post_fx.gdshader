// Full-screen PSX/VHS post-process (on a ColorRect in render/post_fx.tscn, CanvasLayer 90).
// Base look: 15-bit colour + 4x4 Bayer dither, subtle VHS tracking wobble and line noise,
// slight chromatic shift, scanlines, vignette, grain.
// Static (max of global psx_static and uniform static_amount): noise overlay, horizontal tearing,
// colour bleed, rolling bar.
shader_type canvas_item;
render_mode unshaded;

global uniform float psx_static;
global uniform float psx_time_scale;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;

uniform float intensity : hint_range(0.0, 2.0) = 1.0;     // scales the "always on" VHS effects
uniform float static_amount : hint_range(0.0, 1.0) = 0.0; // set by post_fx.gd from EventBus
uniform bool quantize = true;
uniform float color_levels : hint_range(2.0, 255.0) = 31.0;
uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;
uniform float wobble : hint_range(0.0, 4.0) = 0.6;          // pixels of tracking wobble
uniform float line_noise : hint_range(0.0, 1.0) = 0.35;
uniform float chroma_shift : hint_range(0.0, 4.0) = 0.8;    // pixels
uniform float scanlines : hint_range(0.0, 0.5) = 0.06;
uniform float vignette : hint_range(0.0, 1.5) = 0.45;
uniform float grain : hint_range(0.0, 0.3) = 0.035;
uniform vec4 static_tint : source_color = vec4(0.85, 0.9, 1.0, 1.0);

const float BAYER4[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 sample_rgb(vec2 uv, float shift_px, vec2 px) {
	vec3 c;
	c.r = texture(screen_tex, clamp(uv + vec2(shift_px * px.x, 0.0), 0.0, 1.0)).r;
	c.g = texture(screen_tex, clamp(uv, 0.0, 1.0)).g;
	c.b = texture(screen_tex, clamp(uv - vec2(shift_px * px.x, 0.0), 0.0, 1.0)).b;
	return c;
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 res = 1.0 / px;
	vec2 uv = SCREEN_UV;
	vec2 frag = floor(uv * res);
	float t = TIME * psx_time_scale;
	float s = clamp(max(psx_static, static_amount), 0.0, 1.0);
	float k = intensity;

	// --- VHS tracking wobble (per-line horizontal offset, slowly drifting) ---
	float wob = sin(uv.y * 23.0 + t * 1.7) * sin(t * 0.63 + uv.y * 3.0);
	float off = wob * wobble * k * px.x;
	// Thin tracking-noise band crawling up the screen.
	float band_y = 1.0 - fract(t * 0.045);
	float band = smoothstep(0.018, 0.0, abs(uv.y - band_y));
	off += band * (hash12(vec2(frag.y, floor(t * 30.0))) - 0.5) * 6.0 * px.x * k;

	// --- Static: horizontal tearing in row blocks ---
	if (s > 0.0) {
		float blk = floor(uv.y * mix(24.0, 70.0, hash12(vec2(floor(t * 7.0), 3.0))));
		float tick = floor(t * 18.0);
		float on = step(1.0 - s * 0.55, hash12(vec2(blk, tick)));
		off += on * (hash12(vec2(tick, blk * 1.37)) - 0.5) * s * 0.18;
		// Whole-frame jolt at high static.
		off += step(0.985 - s * 0.08, hash12(vec2(tick, 9.1))) * s * 0.03;
	}
	uv.x += off;

	// --- Chromatic shift + colour bleed ---
	float shift = chroma_shift * k + s * 5.0;
	vec3 col = sample_rgb(uv, shift, px);
	if (s > 0.0) {
		// Colour bleed: chroma smeared to the right (average a few samples to the left).
		vec3 bleed = vec3(0.0);
		for (int i = 1; i <= 4; i++) {
			bleed += texture(screen_tex, clamp(uv - vec2(float(i) * (1.0 + s * 3.0) * px.x, 0.0), 0.0, 1.0)).rgb;
		}
		bleed *= 0.25;
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		vec3 chroma = bleed - vec3(dot(bleed, vec3(0.299, 0.587, 0.114)));
		col = mix(col, vec3(luma) + chroma * (1.0 + s), s * 0.7);
	}

	// --- Line noise (sparse bright specks along random scanlines) ---
	float ln = hash12(vec2(frag.y * 0.71, floor(t * 24.0)));
	if (ln > 1.0 - 0.012 * line_noise * k) {
		float seg = step(0.55, hash12(vec2(floor(frag.x / 37.0), frag.y + floor(t * 24.0))));
		float spk = step(0.5, hash12(vec2(frag.x * 0.13, frag.y + floor(t * 60.0))));
		col += vec3(0.18 * spk * seg);
	}

	// --- Static noise overlay + rolling bar ---
	if (s > 0.0) {
		float n = hash12(frag + vec2(floor(t * 60.0) * 17.0, floor(t * 60.0) * 3.0));
		float roll_y = fract(t * (0.25 + s * 0.4));
		float d = fract(uv.y - roll_y);
		float bar = smoothstep(0.0, 0.08, d) * smoothstep(0.28, 0.12, d);
		col = mix(col, vec3(n) * static_tint.rgb, clamp(s * s * 0.85 + bar * s * 0.35, 0.0, 0.95));
		col *= 1.0 - bar * s * 0.35;
		col += bar * s * 0.08;
	}

	// --- Scanlines, vignette, grain ---
	col *= 1.0 - scanlines * k * mod(frag.y, 2.0);
	vec2 vc = SCREEN_UV - 0.5;
	float vig = 1.0 - dot(vc, vc) * vignette * k * 1.8;
	col *= clamp(vig, 0.0, 1.0);
	col += (hash12(frag + fract(t) * 431.0) - 0.5) * grain * k;

	// --- 15-bit colour + ordered dither ---
	if (quantize) {
		ivec2 p = ivec2(mod(frag, 4.0));
		float b = (BAYER4[p.y * 4 + p.x] + 0.5) / 16.0 - 0.5;
		col += b * dither_strength / color_levels;
		col = floor(clamp(col, 0.0, 1.0) * color_levels + 0.5) / color_levels;
	}
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
