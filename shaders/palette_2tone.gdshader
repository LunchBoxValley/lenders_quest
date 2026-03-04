shader_type canvas_item;

// Defaults match your Aseprite colors exactly (so shader does nothing until you change params)
uniform vec4 main_color   : source_color = vec4(0.9411765, 0.9647059, 0.9411765, 1.0); // 240,246,240
uniform vec4 shadow_color : source_color = vec4(0.7764706, 0.7921569, 0.7921569, 1.0); // 198,202,202
uniform float tolerance : hint_range(0.0, 0.25) = 0.05;

// Key colors (what we detect in the sprite)
const vec3 KEY_MAIN  = vec3(0.9411765, 0.9647059, 0.9411765);
const vec3 KEY_SHADE = vec3(0.7764706, 0.7921569, 0.7921569);

float near_color(vec3 a, vec3 b, float tol) {
	return 1.0 - smoothstep(tol, tol * 2.0, distance(a, b));
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	vec3 out_rgb = tex.rgb;

	// Only swap when visible (alpha > tiny)
	float visible = step(0.01, tex.a);

	float m = near_color(tex.rgb, KEY_MAIN,  tolerance) * visible;
	float s = near_color(tex.rgb, KEY_SHADE, tolerance) * visible;

	out_rgb = mix(out_rgb, main_color.rgb,   m);
	out_rgb = mix(out_rgb, shadow_color.rgb, s);

	COLOR = vec4(out_rgb, tex.a);
}