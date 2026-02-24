shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;

// ----------------------------
// Scanlines
// ----------------------------
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.55;
uniform float scanline_density  : hint_range(100.0, 1200.0) = 450.0;
uniform float scanline_thickness : hint_range(0.05, 2.0) = 0.85;
uniform float scanline_offset    : hint_range(0.0, 1.0) = 0.2;

// Subtle drift (CRT "breathing")
uniform float scanline_drift_speed  : hint_range(0.0, 0.20) = 0.015;
uniform float scanline_drift_amount : hint_range(0.0, 0.20) = 0.03;

// Optional vertical grille
uniform float grille_strength : hint_range(0.0, 1.0) = 0.10;
uniform float grille_density  : hint_range(100.0, 2400.0) = 900.0;

// ----------------------------
// Phosphor persistence (fake ghosting)
// ----------------------------
uniform float phosphor_strength : hint_range(0.0, 1.0) = 0.09;
uniform float phosphor_offset_px : hint_range(0.0, 3.0) = 1.95;
uniform float phosphor_soften : hint_range(0.0, 1.0) = 0.55;
uniform vec2 phosphor_dir = vec2(-1.0, 0.8);

// ----------------------------
// Extra retro juice (no color change)
// ----------------------------
// Edge-only extra soften (blurrier corners/edges like real CRT glass)
uniform float edge_soften_strength : hint_range(0.0, 1.0) = 0.18;
uniform float edge_soften_radius_px : hint_range(0.0, 2.0) = 1.0;
uniform float edge_soften_start : hint_range(0.0, 1.0) = 0.25; // where edge blur begins
uniform float edge_soften_end   : hint_range(0.0, 2.0) = 1.10; // where edge blur maxes out

// Tiny brightness flicker (not strobe)
uniform float flicker_strength : hint_range(0.0, 0.10) = 0.015;
uniform float flicker_speed    : hint_range(0.0, 5.0) = 1.70;

// Very faint interlace hint
uniform float interlace_strength : hint_range(0.0, 0.10) = 0.02;

// Lock scanline/grille/noise to pixel grid to avoid “crawling”
uniform bool lock_patterns_to_pixels = true;

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.25;
uniform float noise_strength    : hint_range(0.0, 1.0) = 0.05;
uniform float chroma_strength   : hint_range(0.0, 3.0) = 0.6;

// Gentle curvature
uniform float curvature_strength : hint_range(0.0, 0.55) = 0.06;

// Bloom-like softening (overall)
uniform float soften_strength : hint_range(0.0, 1.0) = 0.20;
uniform float soften_radius_px : hint_range(0.0, 2.0) = 1.0;

// Rare glitch
uniform float glitch_probability_per_second : hint_range(0.0, 0.1) = 0.022;
uniform float glitch_duration : hint_range(0.05, 0.5) = 0.18;
uniform float glitch_strength : hint_range(0.0, 1.0) = 0.55;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 barrel_distort(vec2 uv, float k) {
	vec2 p = uv * 2.0 - 1.0;
	float r2 = dot(p, p);
	p *= 1.0 + k * r2;
	return (p * 0.5) + 0.5;
}

vec3 sample_rgb(vec2 uv, float chroma) {
	float off = chroma / 1000.0;
	vec4 cr = texture(SCREEN_TEXTURE, uv + vec2(off, 0.0));
	vec4 cg = texture(SCREEN_TEXTURE, uv);
	vec4 cb = texture(SCREEN_TEXTURE, uv - vec2(off, 0.0));
	return vec3(cr.r, cg.g, cb.b);
}

vec3 soften(vec2 uv, float radius_px) {
	vec2 px = 1.0 / vec2(textureSize(SCREEN_TEXTURE, 0));
	vec2 o = px * radius_px;

	vec3 c0 = sample_rgb(uv, 0.0);
	vec3 c1 = sample_rgb(uv + vec2(o.x, 0.0), 0.0);
	vec3 c2 = sample_rgb(uv - vec2(o.x, 0.0), 0.0);
	vec3 c3 = sample_rgb(uv + vec2(0.0, o.y), 0.0);
	vec3 c4 = sample_rgb(uv - vec2(0.0, o.y), 0.0);

	return (c0 * 0.50) + (c1 + c2 + c3 + c4) * 0.125;
}

float inside01(vec2 uv) {
	float ix = step(0.0, uv.x) * step(uv.x, 1.0);
	float iy = step(0.0, uv.y) * step(uv.y, 1.0);
	return ix * iy;
}

float scanline_mask(vec2 uv, float density, float thickness) {
	float drift = sin(TIME * 6.28318 * scanline_drift_speed) * scanline_drift_amount;

	float y = uv.y * density + scanline_offset + drift;
	float f = fract(y);

	float band = smoothstep(0.0, 0.12 / max(0.001, thickness), f);
	float inv_band = 1.0 - band;

	return 1.0 - 0.18 * inv_band;
}

float grille_mask(vec2 uv, float density) {
	float x = uv.x * density;
	float f = fract(x);
	float stripe = 1.0 - smoothstep(0.0, 0.08, f) * (1.0 - smoothstep(0.30, 0.38, f));
	return mix(1.0, 0.96, stripe);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Curvature
	uv = barrel_distort(uv, curvature_strength);

	float inside = inside01(uv);
	vec2 uvc = clamp(uv, vec2(0.0), vec2(1.0));

	// Pixel size + pattern-locked UV (prevents scanline/grille crawl)
	vec2 tex_sz = vec2(textureSize(SCREEN_TEXTURE, 0));
	vec2 px = 1.0 / tex_sz;
	vec2 uv_pat = uvc;
	if (lock_patterns_to_pixels) {
		uv_pat = (floor(uvc * tex_sz) + vec2(0.5)) * px;
	}

	// Rare glitch trigger
	float sec = floor(TIME);
	float r = hash12(vec2(sec, sec * 1.37));
	float glitch_on = step(r, glitch_probability_per_second);

	float t = fract(TIME);
	float pulse_in  = smoothstep(0.00, 0.03, t);
	float pulse_out = 1.0 - smoothstep(glitch_duration, glitch_duration + 0.04, t);
	float glitch = glitch_on * pulse_in * pulse_out * glitch_strength;

	vec2 uv_gl = uvc;

	if (glitch > 0.001) {
		float band = floor(uv_gl.y * 24.0);
		float band_r = hash12(vec2(band, sec));
		float jitter = (band_r - 0.5) * 0.03 * glitch;
		uv_gl.x += jitter;

		float tear = step(0.85, hash12(vec2(sec, 91.7)));
		uv_gl.y += tear * (hash12(vec2(band, 13.1)) - 0.5) * 0.01 * glitch;

		uv_gl = clamp(uv_gl, vec2(0.0), vec2(1.0));
	}

	// Base color with chroma
	float chroma = chroma_strength + (glitch * 1.2);
	vec3 col = sample_rgb(uv_gl, chroma);

	// Overall soften
	if (soften_strength > 0.001 && soften_radius_px > 0.0) {
		vec3 blur = soften(uv_gl, soften_radius_px);
		col = mix(col, blur, soften_strength);
	}

	// Edge-only extra soften (CRT glass)
	if (edge_soften_strength > 0.001 && edge_soften_radius_px > 0.0) {
		vec2 pp = uv_gl * 2.0 - 1.0;
		float edge = smoothstep(edge_soften_start, edge_soften_end, dot(pp, pp));
		vec3 eblur = soften(uv_gl, edge_soften_radius_px);
		col = mix(col, eblur, edge_soften_strength * edge);
	}

	// Phosphor persistence (fake ghosting)
	if (phosphor_strength > 0.001 && phosphor_offset_px > 0.0) {
		vec2 dir = phosphor_dir;
		float dl = max(0.0001, length(dir));
		dir /= dl;

		vec2 off_uv = dir * (phosphor_offset_px * px);

		vec3 g0 = sample_rgb(clamp(uv_gl + off_uv, vec2(0.0), vec2(1.0)), chroma * 0.5);
		vec3 g1 = sample_rgb(clamp(uv_gl + off_uv + vec2(px.x, 0.0), vec2(0.0), vec2(1.0)), 0.0);
		vec3 g2 = sample_rgb(clamp(uv_gl + off_uv - vec2(px.x, 0.0), vec2(0.0), vec2(1.0)), 0.0);

		vec3 ghost = mix(g0, (g0 + g1 + g2) / 3.0, phosphor_soften);

		float w = luma(col);
		col = mix(col, max(col, ghost), phosphor_strength * w);
	}

	// Scanlines (pattern-locked UV)
	float sl = scanline_mask(uv_pat, scanline_density, scanline_thickness);
	col *= mix(1.0, sl, scanline_strength);

	// Grille (pattern-locked UV)
	if (grille_strength > 0.001) {
		float gm = grille_mask(uv_pat, grille_density);
		col *= mix(1.0, gm, grille_strength);
	}

	// Interlace hint (tiny)
	if (interlace_strength > 0.001) {
		float frame = floor(TIME * 60.0);
		float parity = mod(frame, 2.0);
		float row = mod(floor(uv_pat.y * tex_sz.y), 2.0);
		float match = 1.0 - abs(row - parity); // 1 when same parity, 0 otherwise
		float inter = 1.0 - interlace_strength * (1.0 - match);
		col *= inter;
	}

	// Tiny brightness flicker (no color shift)
	if (flicker_strength > 0.001) {
		float flick = 1.0 + flicker_strength * sin(TIME * flicker_speed);
		col *= flick;
	}

	// Vignette
	vec2 p = uv_gl * 2.0 - 1.0;
	float v = 1.0 - vignette_strength * smoothstep(0.2, 1.1, dot(p, p));
	col *= v;

	// Noise (pattern-locked UV; stronger during glitch)
	float n = hash12(uv_pat * (TIME * 60.0));
	float ns = noise_strength + glitch * 0.08;
	col += (n - 0.5) * ns;

	// Apply curvature mask
	col *= inside;

	COLOR = vec4(col, 1.0);
}