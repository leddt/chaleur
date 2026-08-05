shader_type canvas_item;
render_mode blend_mix;

// Grain de papier + vignettage. A mettre sur un ColorRect plein ecran, place
// AU-DESSUS de tout le reste, avec mouse_filter = IGNORE et color = blanc.
//
// C'est le seul "effet" du jeu, et il fait le gros du travail pour que
// l'interface ait l'air d'un objet imprime plutot que d'un ecran.

uniform float grain_amount : hint_range(0.0, 0.4) = 0.10;
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.40;
uniform vec3 grain_tint : source_color = vec3(0.92, 0.88, 0.79);

float hash(vec2 p) {
	p = fract(p * vec2(443.897, 441.423));
	p += dot(p, p + 19.19);
	return fract((p.x + p.y) * p.x);
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Grain fixe. Un grain anime fait "video"; un grain fixe fait "papier".
	float g = hash(floor(uv * vec2(1920.0, 1080.0)));

	// Vignettage doux : un plateau eclaire par le dessus.
	float d = distance(uv, vec2(0.5));
	float vig = smoothstep(0.35, 0.95, d) * vignette_amount;

	// Deux couches empilees dans un seul fragment : le grain clair par-dessus,
	// l'assombrissement des bords en dessous.
	vec3 col = mix(vec3(0.0), grain_tint, g);
	float a = g * grain_amount + vig;

	COLOR = vec4(mix(vec3(0.0), col, step(vig, g * grain_amount)), clamp(a, 0.0, 1.0));
}
