shader_type canvas_item;

// Palette swap for a mortal's bandana and cloak (see UITokens, "the players' bandanas").
//
// Assets/Player/Lamang-Sheet.png draws the headband and its two tails in exactly
// two colours that appear nowhere else on the sheet - the main red #7A0E0E and its
// shadow #570303 - and the cloak (the big top/coat) in exactly three more:
// #581010 light, #4B0000 mid, #2A0000 dark. A pixel within `tolerance` of one of
// those five becomes the matching colour below; every other pixel is untouched.
//
// The tolerance is small on purpose: the cloak's light red (#581010) is only
// 13 / 255 away from the bandana shadow in two channels, so anything wider would
// recolour one into the other. The sheet is pixel art on a nearest-neighbour
// filter, so a pixel is either exactly one of the five or it is not.
//
// The pixel is REPLACED by the new colour, then multiplied by the node's modulate
// (read in vertex() and carried to fragment() as v_mod). A multiplier on the drawn
// colour can't do it: the cloak's mid and dark reds have no green or blue at all,
// so no multiplier could ever turn them blue, green or white. Replace-then-modulate
// keeps every modulate / self_modulate an arena puts on the mortal or the whole
// field - a hit flash, a freeze, Mayari's blitz tint, a fade - working on top.
//
// One ShaderMaterial per mortal (ArenaMortal.set_bandana duplicates it), so each
// mortal carries its own colours. Plain vec4 uniforms, no source_color: the values
// are the sRGB colours UITokens holds, used as they are.

uniform vec4 bandana_color = vec4(0.478431, 0.054902, 0.054902, 1.0);
uniform vec4 bandana_shadow = vec4(0.341176, 0.011765, 0.011765, 1.0);
uniform vec4 cloak_color = vec4(0.345098, 0.062745, 0.062745, 1.0);
uniform vec4 cloak_mid = vec4(0.294118, 0.0, 0.0, 1.0);
uniform vec4 cloak_dark = vec4(0.164706, 0.0, 0.0, 1.0);
uniform float tolerance = 0.012;

const vec3 DRAWN_BANDANA = vec3(0.478431, 0.054902, 0.054902);  // #7A0E0E
const vec3 DRAWN_SHADOW = vec3(0.341176, 0.011765, 0.011765);   // #570303
const vec3 DRAWN_CLOAK = vec3(0.345098, 0.062745, 0.062745);    // #581010
const vec3 DRAWN_MID = vec3(0.294118, 0.0, 0.0);                // #4B0000
const vec3 DRAWN_DARK = vec3(0.164706, 0.0, 0.0);               // #2A0000

varying vec4 v_mod;

void vertex() {
	v_mod = COLOR;  // the node's modulate (and self_modulate), before the texture
}

bool is_drawn(vec3 rgb, vec3 drawn) {
	return all(lessThanEqual(abs(rgb - drawn), vec3(tolerance)));
}

void fragment() {
	vec4 drawn = texture(TEXTURE, UV);
	vec3 rgb = drawn.rgb;
	if (drawn.a > 0.0) {
		if (is_drawn(rgb, DRAWN_BANDANA)) {
			rgb = bandana_color.rgb;
		} else if (is_drawn(rgb, DRAWN_SHADOW)) {
			rgb = bandana_shadow.rgb;
		} else if (is_drawn(rgb, DRAWN_CLOAK)) {
			rgb = cloak_color.rgb;
		} else if (is_drawn(rgb, DRAWN_MID)) {
			rgb = cloak_mid.rgb;
		} else if (is_drawn(rgb, DRAWN_DARK)) {
			rgb = cloak_dark.rgb;
		}
	}
	COLOR = vec4(rgb, drawn.a) * v_mod;
}
