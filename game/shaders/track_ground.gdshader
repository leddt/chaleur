shader_type canvas_item;
render_mode blend_mix, unshaded;

// Fond de plateau procédural (gazon / terre / sable). À mettre sur un ColorRect
// plein panneau, sous le tracé, mouse_filter = IGNORE, color = blanc.
// Densité basée sur FRAGCOORD pour rester stable au resize / stretch.

uniform vec3 base_color : source_color = vec3(0.18, 0.32, 0.22);
uniform vec3 accent_color : source_color = vec3(0.30, 0.46, 0.32);
uniform vec3 vein_color : source_color = vec3(0.12, 0.22, 0.15);
uniform float pattern_scale : hint_range(4.0, 40.0) = 14.0;
uniform float contrast : hint_range(0.0, 1.0) = 0.55;
uniform float vein_strength : hint_range(0.0, 1.0) = 0.4;
uniform float grit_amount : hint_range(0.0, 1.0) = 0.2;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	vec2 q = p;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(q);
		q *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 px = FRAGCOORD.xy / max(pattern_scale, 0.001);
	float n = fbm(px * 0.55);
	float detail = fbm(px * 1.7 + 19.7);
	float veins = abs(fbm(px * 0.35 + 7.3) - 0.5) * 2.0;
	veins = smoothstep(0.35, 0.85, veins);

	float blend = mix(n, detail, 0.35);
	blend = mix(0.5, blend, contrast);

	vec3 col = mix(base_color, accent_color, clamp(blend, 0.0, 1.0));
	col = mix(col, vein_color, veins * vein_strength);

	float grit = step(0.92, hash21(floor(FRAGCOORD.xy * 0.5)));
	col = mix(col, vein_color, grit * grit_amount);

	COLOR = vec4(col, 1.0);
}
