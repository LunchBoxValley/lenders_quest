shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;

uniform float scanline_strength : hint_range(0.0, 1.0) = 0.25;
uniform float scanline_density  : hint_range(100.0, 1200.0) = 450.0;

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.25;

uniform float noise_strength    : hint_range(0.0, 1.0) = 0.05;

uniform float chroma_strength   : hint_range(0.0, 3.0) = 0.6;

// Gentle curvature
uniform float curvature_strength : hint_range(0.0, 0.55) = 0.06;

// Bloom-like softening
uniform float soften_strength : hint_range(0.0, 1.0) = 0.20;
uniform float soften_radius_px : hint_range(0.0, 2.0) = 1.0;

// Rare glitch
uniform float glitch_probability_per_second : hint_range(0.0, 0.1) = 0.022; // ~1 per 45s avg
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
	// 1.0 if inside [0,1], else 0.0
	float ix = step(0.0, uv.x) * step(uv.x, 1.0);
	float iy = step(0.0, uv.y) * step(uv.y, 1.0);
	return ix * iy;
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Curvature
	uv = barrel_distort(uv, curvature_strength);

	// Mask for out-of-bounds after curvature
	float inside = inside01(uv);

	// Clamp for safe sampling (outside gets masked to black)
	vec2 uvc = clamp(uv, vec2(0.0), vec2(1.0));

	// Rare glitch trigger
	float sec = floor(TIME);
	float r = hash12(vec2(sec, sec * 1.37));
	float glitch_on = step(r, glitch_probability_per_second);

	float t = fract(TIME);
	float pulse_in  = smoothstep(0.00, 0.03, t);
	float pulse_out = 1.0 - smoothstep(glitch_duration, glitch_duration + 0.04, t);
	float glitch = glitch_on * pulse_in * pulse_out * glitch_strength;

	// Glitch: horizontal band jitter + slight chroma boost
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

	// Bloom-like softening
	if (soften_strength > 0.001 && soften_radius_px > 0.0) {
		vec3 blur = soften(uv_gl, soften_radius_px);
		col = mix(col, blur, soften_strength);
	}

	// Scanlines
	float s = sin(uv_gl.y * scanline_density * 3.14159);
	float scan = mix(1.0, 0.85 + 0.15 * s, scanline_strength);
	col *= scan;

	// Vignette
	vec2 p = uv_gl * 2.0 - 1.0;
	float v = 1.0 - vignette_strength * smoothstep(0.2, 1.1, dot(p, p));
	col *= v;

	// Noise (stronger during glitch)
	float n = hash12(uv_gl * (TIME * 60.0));
	float ns = noise_strength + glitch * 0.08;
	col += (n - 0.5) * ns;

	// Apply curvature mask: outside becomes black
	col *= inside;

	COLOR = vec4(col, 1.0);
}