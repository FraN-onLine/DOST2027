shader_type canvas_item;

// Palette swap for a mortal's bandana (see UITokens, "the players' bandanas").
//
// Assets/Player/Lamang-Sheet.png draws the headband and its two tails in exactly
// two colours that appear nowhere else on the sheet: the main red #7A0E0E and its
// shadow #570303. A pixel within `tolerance` of the first becomes `bandana_color`,
// one near the second becomes `bandana_shadow`; every other pixel is untouched.
//
// The tolerance is small on purpose: the shirt's darkest red (#581010) is only
// 13 / 255 away from the shadow red in two channels, so anything wider would
// recolour the shirt. The sheet is pixel art on a nearest-neighbour filter, so a
// pixel is either exactly a bandana colour or it is not.
//
// The new colour is applied as a multiplier on the pixel the engine already
// produced (texture x the node's modulate), so every modulate / self_modulate an
// arena puts on the mortal or the whole field - a hit flash, a freeze, Mayari's
// blitz tint, a fade - still works on top of it instead of being replaced.
//
// One ShaderMaterial per mortal (ArenaMortal.set_bandana duplicates it), so each
// mortal carries its own colour. Plain vec4 uniforms, no source_color: the values
// are the sRGB colours UITokens holds, used as they are.

uniform vec4 bandana_color = vec4(0.478431, 0.054902, 0.054902, 1.0);
uniform vec4 bandana_shadow = vec4(0.341176, 0.011765, 0.011765, 1.0);
uniform float tolerance = 0.012;

const vec3 DRAWN_LIGHT = vec3(0.478431, 0.054902, 0.054902);   // #7A0E0E
const vec3 DRAWN_SHADOW = vec3(0.341176, 0.011765, 0.011765);  // #570303

void fragment() {
	vec4 drawn = texture(TEXTURE, UV);
	if (drawn.a > 0.0) {
		if (all(lessThanEqual(abs(drawn.rgb - DRAWN_LIGHT), vec3(tolerance)))) {
			COLOR.rgb *= bandana_color.rgb / DRAWN_LIGHT;
		} else if (all(lessThanEqual(abs(drawn.rgb - DRAWN_SHADOW), vec3(tolerance)))) {
			COLOR.rgb *= bandana_shadow.rgb / DRAWN_SHADOW;
		}
	}
}
