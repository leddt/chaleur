shader_type canvas_item;
render_mode blend_mix, unshaded;

// Texte qui brule : langues organiques qui sortent du glyphe,
// montees vers le haut et legerement a gauche.
// IMPORTANT: hors glyphe, COLOR.a vaut deja 0 (TEXTURE pre-multipliee) —
// ne jamais faire outer * COLOR.a, sinon les flammes disparaissent.
// NOTE: TEXTURE utilisable seulement dans fragment() (GLES3 / Godot 4.7).

uniform vec3 flame_core : source_color = vec3(1.0, 0.98, 0.55);
uniform vec3 flame_mid : source_color = vec3(1.0, 0.42, 0.02);
uniform vec3 flame_tip : source_color = vec3(1.0, 0.08, 0.0);
uniform float rise_speed : hint_range(0.0, 6.0) = 3.2;
uniform float flame_height : hint_range(8.0, 120.0) = 68.0;
uniform float lean : hint_range(0.0, 1.5) = 0.62;
uniform float intensity : hint_range(0.5, 3.0) = 1.85;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.07 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float fill = texture(TEXTURE, UV).a;

	float best = 0.0;
	float best_t = 1.0;
	float max_h = flame_height * TEXTURE_PIXEL_SIZE.y;
	float lean_x = lean * flame_height * TEXTURE_PIXEL_SIZE.x;

	for (int i = 1; i <= 64; i++) {
		float fi = float(i);
		// Jitter le long du rayon : evite les bandes / escaliers visibles.
		float jitter = (hash(UV * 37.0 + vec2(fi * 1.7, TIME * 0.15)) - 0.5) * 0.85;
		float t = clamp((fi + jitter) / 64.0, 0.002, 1.0);
		// TIME signe pour que le bruit defile HORS des lettres (haut-gauche),
		// pas vers l'interieur. f(p + TIME * dir) => motifs vers -dir en UV.
		float n1 = fbm(vec2(UV.x * 10.0 + t * 3.0 + TIME * rise_speed * 0.35, UV.y * 6.0 + TIME * rise_speed));
		float n2 = fbm(vec2(UV.x * 18.0 + TIME * 1.5, UV.y * 11.0 + t * 5.0 + TIME * rise_speed * 0.85));
		float n3 = fbm(vec2(UV.x * 5.0 + TIME * 0.55, UV.y * 3.0 + TIME * 0.85));
		float n4 = fbm(vec2(UV.x * 28.0 - t * 4.0 + TIME * 0.9, UV.y * 7.0 + TIME * rise_speed * 0.5));

		// Combustible en bas-droite => flammes au-dessus, penchent a gauche.
		vec2 fuel_uv = UV + vec2(
			lean_x * t + (n1 - 0.4) * TEXTURE_PIXEL_SIZE.x * 40.0 * t,
			max_h * t + (n3 - 0.5) * TEXTURE_PIXEL_SIZE.y * 8.0 * t
		);
		float src = texture(TEXTURE, fuel_uv).a;

		float taper = pow(1.0 - t, 1.55);
		// Colonnes irregulieres : casse la copie du glyphe en langues.
		float wisp = mix(0.35, 1.4, pow(n2, 1.15)) * mix(0.6, 1.25, n4);
		float cand = src * taper * wisp;
		if (cand > best) {
			best = cand;
			best_t = t;
		}
	}

	float outer = clamp(best * (1.0 - fill) * intensity, 0.0, 1.0);
	outer *= mix(1.15, 0.22, best_t);
	float tip_cut = mix(0.55, 1.2, fbm(vec2(UV.x * 20.0 + TIME * 0.9, UV.y * 4.0 + TIME * rise_speed)));
	outer *= mix(1.0, tip_cut, clamp(best_t * 1.2, 0.0, 1.0));
	outer = clamp(outer, 0.0, 1.0);

	float heat = clamp(1.0 - best_t * 1.1 + tip_cut * 0.2, 0.0, 1.0);
	vec3 tongue_col = mix(flame_tip, flame_mid, smoothstep(0.0, 0.55, heat));
	tongue_col = mix(tongue_col, flame_core, smoothstep(0.4, 0.92, heat));
	// Pic satures : les langues restent vives meme en se melangeant.
	tongue_col = mix(tongue_col, flame_mid, 0.18);
	tongue_col = min(tongue_col * vec3(1.12, 1.05, 1.0), vec3(1.0));

	float ember_n = fbm(vec2(UV.x * 5.5 + TIME * 0.2, UV.y * 3.2 + TIME * rise_speed * 0.5));
	vec3 body = mix(flame_mid, flame_core, 0.35 + ember_n * 0.5);
	body = mix(flame_tip, body, 0.72);
	body = min(body * vec3(1.1, 1.05, 1.0), vec3(1.0));

	// Soft edge : alpha du glyphe seul (anti-alias natif), sans contour sombre.
	if (fill > 0.001) {
		vec3 col = mix(tongue_col, body, smoothstep(0.0, 0.45, fill));
		float a = max(fill, outer);
		COLOR = vec4(col, a);
	} else if (outer > 0.04) {
		COLOR = vec4(tongue_col, outer);
	} else {
		COLOR = vec4(0.0);
	}
}
