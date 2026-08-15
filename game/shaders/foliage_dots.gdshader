shader_type canvas_item;
render_mode unshaded, blend_mix;

varying float v_phase;

// INSTANCE_CUSTOM: x=phase (léger décalage local), z=amplitude mesh.
void vertex() {
	v_phase = INSTANCE_CUSTOM.x;
	float amp = INSTANCE_CUSTOM.z;
	// Vent global: direction et force lentes, partagées par tout le feuillage.
	float dir = TIME * 0.045 + 0.55 * sin(TIME * 0.019) + 0.22 * sin(TIME * 0.007);
	float strength = 1.05 + 1.15 * (0.5 + 0.5 * sin(TIME * 0.13 + 0.4 * sin(TIME * 0.031)));
	vec2 wind = vec2(cos(dir), sin(dir)) * strength;
	vec2 perp = vec2(-wind.y, wind.x);
	float local = 0.78 + 0.22 * sin(v_phase);
	float flutter = sin(TIME * 2.4 + v_phase * 3.1);
	VERTEX += (wind * local + perp * (0.16 * flutter)) * amp;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float disc = 1.0 - smoothstep(0.82, 1.0, length(p));
	COLOR.a *= disc;
}
