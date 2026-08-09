shader_type canvas_item;
render_mode blend_mix, unshaded;

// Grain pixelisé en espace monde. À mettre sur le calque asphalte uniquement.
// world = (VERTEX - xform_origin) / xform_scale  (xform piste → écran).

uniform vec3 base_color : source_color = vec3(0.28, 0.29, 0.31);
uniform vec3 dark_color : source_color = vec3(0.24, 0.25, 0.26);
uniform vec3 light_color : source_color = vec3(0.31, 0.32, 0.34);
uniform float grain_world : hint_range(0.25, 8.0) = 1.15;
uniform vec2 xform_origin = vec2(0.0);
uniform float xform_scale = 1.0;

varying vec2 v_local;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	float s = max(xform_scale, 0.0001);
	vec2 world = (v_local - xform_origin) / s;
	vec2 cell = floor(world / max(grain_world, 0.001));
	float h = hash21(cell);
	vec3 col = base_color;
	if (h > 0.78) {
		col = dark_color;
	} else if (h > 0.70) {
		col = light_color;
	}
	COLOR = vec4(col, COLOR.a);
}
