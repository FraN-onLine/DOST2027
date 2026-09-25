shader_type canvas_item;

// Mayari's "Half Vision" / blindness effects.
// Everything goes black except for a circle around the given UV point.
// radius = 0.0 -> the whole screen is dark, radius >= 1.5 -> fully open.

uniform float radius : hint_range(0.0, 1.5) = 0.16;
uniform vec2 center = vec2(0.5, 0.5);
uniform float softness : hint_range(0.001, 0.5) = 0.06;
uniform float aspect : hint_range(0.1, 10.0) = 1.7777778;

void fragment() {
	vec2 delta = (UV - center) * vec2(aspect, 1.0);
	float dist = length(delta);
	float alpha = smoothstep(radius, radius + softness, dist);
	COLOR = vec4(0.0, 0.0, 0.0, alpha);
}
