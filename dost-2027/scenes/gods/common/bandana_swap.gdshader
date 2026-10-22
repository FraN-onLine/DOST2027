shader_type canvas_item;

// Palette swap for a mortal's bandana and vest (see UITokens, "the players' bandanas").
//
// Assets/Gods/lam-ang.png and lam-ang-walking.png (the idle, the walk and the
// hit-arnis strike) draw the headband, its tails AND the vest in the same three reds
// and nowhere else on either sheet: #581010 light, #410B0B mid, #2A0000 dark. A pixel
// within `tolerance` of one of them becomes shade_light / shade_mid / shade_dark
// (the player's colour, x0.74, x0.48 - the drawn 88 : 65 : 42 steps); every other
// pixel is untouched.
//
// LEGACY: the defend-arnis clip still comes from the old Assets/Player/Lamang-Sheet.png,
// which draws the bandana in #7A0E0E / #570303 and the cloak in #581010 / #4B0000 /
// #2A0000. `legacy` (ArenaMortal sets it from the playing clip) maps those five
// instead - the cloak's light and dark reds are the same pixels as the new light and
// dark, so the two palettes can't be told apart per pixel, only per clip. Drop the
// legacy uniforms and constants when defend-arnis gets new art.
//
// The tolerance is small on purpose (the old cloak's light red is only 13 / 255 from
// the old bandana shadow in two channels). The sheets are pixel art on a
// nearest-neighbour filter, so a pixel is either exactly one of them or it is not.
//
// The pixel is REPLACED by the new colour, then multiplied by the node's modulate
// (read in vertex() and carried to fragment() as v_mod). A multiplier on the drawn
// colour can't do it: the drawn mid and dark reds have almost no green or blue, so
// no multiplier could ever turn them blue, green or white. Replace-then-modulate
// keeps every modulate / self_modulate an arena puts on the mortal or the whole
// field - a hit flash, a freeze, Mayari's blitz tint, a fade - working on top.
//
// One ShaderMaterial per mortal (ArenaMortal.set_bandana duplicates it), so each
// mortal carries its own colours. Plain vec4 uniforms, no source_color: the values
// are the sRGB colours UITokens holds, used as they are.

uniform vec4 shade_light = vec4(0.345098, 0.062745, 0.062745, 1.0);
uniform vec4 shade_mid = vec4(0.254902, 0.043137, 0.043137, 1.0);
uniform vec4 shade_dark = vec4(0.164706, 0.0, 0.0, 1.0);
uniform bool legacy = false;
uniform vec4 bandana_color = vec4(0.478431, 0.054902, 0.054902, 1.0);
uniform vec4 bandana_shadow = vec4(0.341176, 0.011765, 0.011765, 1.0);
uniform vec4 cloak_color = vec4(0.345098, 0.062745, 0.062745, 1.0);
uniform vec4 cloak_mid = vec4(0.294118, 0.0, 0.0, 1.0);
uniform vec4 cloak_dark = vec4(0.164706, 0.0, 0.0, 1.0);
uniform float tolerance = 0.012;

const vec3 DRAWN_LIGHT = vec3(0.345098, 0.062745, 0.062745);    // #581010
const vec3 DRAWN_MID = vec3(0.254902, 0.043137, 0.043137);      // #410B0B
const vec3 DRAWN_DARK = vec3(0.164706, 0.0, 0.0);               // #2A0000
const vec3 OLD_BANDANA = vec3(0.478431, 0.054902, 0.054902);    // #7A0E0E
const vec3 OLD_SHADOW = vec3(0.341176, 0.011765, 0.011765);     // #570303
const vec3 OLD_CLOAK_MID = vec3(0.294118, 0.0, 0.0);            // #4B0000

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
		if (legacy) {
			if (is_drawn(rgb, OLD_BANDANA)) {
				rgb = bandana_color.rgb;
			} else if (is_drawn(rgb, OLD_SHADOW)) {
				rgb = bandana_shadow.rgb;
			} else if (is_drawn(rgb, DRAWN_LIGHT)) {
				rgb = cloak_color.rgb;
			} else if (is_drawn(rgb, OLD_CLOAK_MID)) {
				rgb = cloak_mid.rgb;
			} else if (is_drawn(rgb, DRAWN_DARK)) {
				rgb = cloak_dark.rgb;
			}
		} else if (is_drawn(rgb, DRAWN_LIGHT)) {
			rgb = shade_light.rgb;
		} else if (is_drawn(rgb, DRAWN_MID)) {
			rgb = shade_mid.rgb;
		} else if (is_drawn(rgb, DRAWN_DARK)) {
			rgb = shade_dark.rgb;
		}
	}
	COLOR = vec4(rgb, drawn.a) * v_mod;
}
