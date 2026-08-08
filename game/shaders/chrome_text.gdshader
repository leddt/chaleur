shader_type canvas_item;
render_mode blend_mix, unshaded;

// Chrome embosse doux : metal uni avec relief subtil.
// NOTE: TEXTURE utilisable seulement dans fragment() (GLES3 / Godot 4.7).

uniform vec3 metal_dark : source_color = vec3(0.32, 0.34, 0.38);
uniform vec3 metal_mid : source_color = vec3(0.6, 0.62, 0.66);
uniform vec3 metal_light : source_color = vec3(0.88, 0.9, 0.92);
uniform vec3 env_tint : source_color = vec3(0.4, 0.55, 0.68);
uniform float sweep_speed : hint_range(0.0, 4.0) = 0.85;
uniform float band_density : hint_range(2.0, 28.0) = 11.0;
uniform float gloss : hint_range(0.0, 1.0) = 0.55;
uniform float emboss_width : hint_range(0.5, 6.0) = 2.1;
uniform float emboss_strength : hint_range(0.0, 1.5) = 0.55;

void fragment() {
	float a = texture(TEXTURE, UV).a;
	if (a < 0.01) {
		discard;
	}

	// Bandes metaliques tres douces, proche du gris moyen.
	float band = sin((UV.y * band_density + UV.x * 2.2) * 3.14159) * 0.5 + 0.5;
	float band2 = sin((UV.y * band_density * 2.6 - UV.x * 1.4) * 3.14159) * 0.5 + 0.5;
	band = mix(band, band2, 0.35);
	band = mix(0.5, band, 0.62); // contraste bande moyen

	vec3 base = mix(metal_dark, metal_mid, band);
	base = mix(base, metal_light, pow(band, 2.0) * 0.42);

	float sweep = UV.x * 1.8 + UV.y * 0.45 - TIME * sweep_speed;
	float spec = pow(max(0.0, sin(sweep * 6.28318)), mix(8.0, 28.0, gloss));
	float rim = pow(1.0 - abs(UV.y - 0.5) * 2.0, 1.6);

	vec3 col = base;
	col = mix(col, metal_light, spec * gloss * 0.5);
	col = mix(col, env_tint, rim * 0.2 + spec * 0.1);
	col += metal_light * smoothstep(0.62, 0.12, UV.y) * 0.14;

	// Emboss lisible sans tout casser.
	vec2 px = TEXTURE_PIXEL_SIZE * emboss_width;
	float a_l = texture(TEXTURE, UV + vec2(-px.x, 0.0)).a;
	float a_r = texture(TEXTURE, UV + vec2(px.x, 0.0)).a;
	float a_u = texture(TEXTURE, UV + vec2(0.0, -px.y)).a;
	float a_d = texture(TEXTURE, UV + vec2(0.0, px.y)).a;
	float a_tl = texture(TEXTURE, UV + vec2(-px.x, -px.y)).a;
	float a_br = texture(TEXTURE, UV + vec2(px.x, px.y)).a;

	float gx = (a_r - a_l) + (a_br - a_tl) * 0.55;
	float gy = (a_d - a_u) + (a_br - a_tl) * 0.55;
	float ndotl = clamp((-0.55 * gx + -0.85 * gy) * 1.9, -1.0, 1.0);

	float highlight = smoothstep(0.08, 0.7, ndotl);
	float shadow = smoothstep(0.08, 0.7, -ndotl);
	float dome = smoothstep(0.25, 0.9, a);

	col = mix(col, metal_light, highlight * emboss_strength * 0.65);
	col = mix(col, metal_dark, shadow * emboss_strength * 0.55);
	col = mix(col, col * 1.06, dome * 0.25);
	float edge = smoothstep(0.18, 0.55, a) * (1.0 - smoothstep(0.55, 0.92, a));
	col += metal_light * highlight * edge * 0.2 * emboss_strength;
	col -= vec3(0.08) * shadow * edge * emboss_strength;

	COLOR = vec4(col, a);
}
