shader_type canvas_item;
render_mode blend_mix, unshaded;

// Ombres de nuages en world space — deux couches à vitesses distinctes,
// bords fractals (FBM riche + warp). ColorRect plein panneau, mouse_filter IGNORE.

uniform float cloud_amount : hint_range(0.0, 0.8) = 0.22;
uniform float cloud_scale : hint_range(0.0005, 0.05) = 0.0048;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.58;
uniform float cloud_contrast : hint_range(0.0, 1.0) = 0.72;
uniform float cloud_detail : hint_range(0.0, 1.0) = 0.65;
uniform float cloud_speed_near : hint_range(0.0, 80.0) = 26.0;
uniform float cloud_speed_far : hint_range(0.0, 80.0) = 9.5;
uniform float cloud_near_weight : hint_range(0.0, 1.0) = 0.55;
uniform vec2 cloud_wind_near = vec2(1.0, 0.32);
uniform vec2 cloud_wind_far = vec2(0.55, -0.75);
uniform vec2 view_pan = vec2(0.0);
uniform float view_zoom = 1.0;

varying vec2 v_local;

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

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	float sum = 0.0;
	vec2 q = p;
	for (int i = 0; i < 6; i++) {
		if (i >= octaves) {
			break;
		}
		v += a * value_noise(q);
		sum += a;
		q = q * 2.08 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v / max(sum, 0.0001);
}

float cloud_field(vec2 uv, float detail) {
	// Warp basse fréquence pour des silhouettes organiques.
	vec2 w1 = vec2(
		fbm(uv * 0.9 + vec2(0.0, 3.1), 3),
		fbm(uv * 0.9 + vec2(4.2, 1.0), 3)
	);
	vec2 warped = uv + (w1 - 0.5) * (0.7 + detail * 0.55);

	float body = fbm(warped, 4);
	// Seconde warp haute fréquence → digitation / bords fractals.
	vec2 w2 = vec2(
		fbm(warped * 2.4 + vec2(8.1, -2.3), 4),
		fbm(warped * 2.4 + vec2(-3.4, 6.7), 4)
	);
	float rim = fbm(warped * 1.15 + (w2 - 0.5) * (0.9 * detail), 5);
	float fine = fbm(warped * (3.2 + detail * 2.0) + 17.0, 4);

	float clouds = mix(body, rim, 0.42);
	clouds = mix(clouds, fine, 0.18 * detail);
	return clouds;
}

float layer_mask(float clouds, float coverage, float contrast, float detail) {
	clouds = mix(0.5, clouds, contrast);
	float edge = mix(0.16, 0.05, contrast) * mix(1.15, 0.75, detail);
	float mask = smoothstep(coverage - edge, coverage + edge * 1.25, clouds);
	mask = mask * mask * (3.0 - 2.0 * mask);
	return mask;
}

void vertex() {
	v_local = VERTEX;
}

void fragment() {
	vec2 world = (v_local - view_pan) / max(view_zoom, 0.0001);

	vec2 far_uv = (world + cloud_wind_far * (TIME * cloud_speed_far)) * (cloud_scale * 0.92);
	vec2 near_uv = (world + cloud_wind_near * (TIME * cloud_speed_near)) * (cloud_scale * 1.35)
			+ vec2(31.7, -19.3);

	float far_n = cloud_field(far_uv, cloud_detail * 0.85);
	float near_n = cloud_field(near_uv, cloud_detail);

	// Couche lointaine : seuil un peu plus bas (voile large) ; proche : amas plus marquants.
	float far_m = layer_mask(far_n, cloud_coverage - 0.04, cloud_contrast * 0.9, cloud_detail);
	float near_m = layer_mask(near_n, cloud_coverage + 0.03, cloud_contrast, cloud_detail);

	// Addition non linéaire : les deux couches se croisent sans saturer.
	float mask = clamp(far_m * (1.0 - cloud_near_weight * 0.35) + near_m * cloud_near_weight, 0.0, 1.0);

	COLOR = vec4(vec3(0.02, 0.03, 0.05), mask * cloud_amount);
}
