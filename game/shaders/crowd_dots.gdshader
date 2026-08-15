shader_type canvas_item;
render_mode unshaded, blend_mix;

varying float v_phase;
varying float v_bob;

// INSTANCE_CUSTOM: x=phase, y=bob (0.45..1), z=wobble amplitude in mesh units.
void vertex() {
	v_phase = INSTANCE_CUSTOM.x;
	v_bob = max(INSTANCE_CUSTOM.y, 0.35);
	float amp = INSTANCE_CUSTOM.z;
	VERTEX += vec2(
		sin(TIME * 1.55 + v_phase),
		cos(TIME * 1.95 + v_phase * 1.3)
	) * amp;
	VERTEX *= 1.0 + 0.12 * v_bob * sin(TIME * 2.35 + v_phase * 0.7);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float disc = 1.0 - smoothstep(0.82, 1.0, length(p));
	float breathe = 0.5 + 0.5 * sin(TIME * 1.12 + v_phase * 1.55);
	float opacity = mix(0.68, 1.0, mix(0.4, 1.0, v_bob) * breathe);
	float lift = 0.5 + 0.5 * sin(TIME * 1.75 + v_phase + 0.9);
	COLOR.rgb *= 1.0 + 0.16 * v_bob * lift;
	COLOR.a *= disc * opacity;
}
