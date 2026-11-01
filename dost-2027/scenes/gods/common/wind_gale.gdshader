shader_type canvas_item;

// Winds and Gales of Yesterday: horizontal streaks blowing westward over the
// whole screen. `intensity` is faded by winds_and_gales.gd, so a cast rolls in
// and dies out instead of popping.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.72, 0.86, 1.0, 1.0);
uniform float speed = 0.55;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * speed;
	float streak = 0.0;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float row = floor((uv.y + fi * 0.37) * (16.0 + fi * 12.0));
		float rnd = hash(row * 12.9898 + fi * 78.233);
		float x = fract(uv.x + t * (0.5 + rnd * 1.1) + rnd * 10.0);
		float head = 0.18 + rnd * 0.3;
		float band = smoothstep(0.0, 0.06, x) * (1.0 - smoothstep(head, head + 0.12, x));
		float wobble = 0.5 + 0.5 * sin(uv.y * 26.0 + TIME * 2.0 + fi * 1.7);
		streak += band * wobble * (0.10 + rnd * 0.18);
	}
	float sheen = 0.07 + 0.05 * sin(uv.y * 5.0 + TIME * 1.3);
	COLOR = vec4(tint.rgb, clamp(streak * 0.6 + sheen, 0.0, 1.0) * intensity * tint.a);
}
