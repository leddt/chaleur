shader_type canvas_item;
render_mode unshaded, blend_mix;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	COLOR.a *= 1.0 - smoothstep(0.82, 1.0, length(p));
}
