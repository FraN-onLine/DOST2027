class_name GodArena
extends RefCounted

# Shared layout contract for every god's arena (Mayari, Apolaki, ...).
#
# The Game shell (scenes/Game.tscn) draws the player panels - your name, FAVOR,
# DUE, the E/Q favor bars and the other players - over the LEFT strip of the
# screen. An arena is therefore authored in screen space, exactly as it will be
# played:
#
#   * the scene is DESIGN_SIZE (1152 x 648) big;
#   * the left UI_STRIP_WIDTH pixels stay EMPTY of gameplay art - no floor, no
#     goal, no clone and no mortal starts there (MayariArena.tscn keeps a locked
#     "GAME UI AREA" body over the strip so the reservation is visible while
#     editing);
#   * the scene owns its own coordinates: nothing scales, stretches or
#     re-centres it at runtime. The shell only instantiates the arena and hands
#     it god_id / embedded / dialogue_prefix.
#
# What the designer sees in the arena scene is what every player gets.
#
# Input every arena can count on (project.godot):
#   move_left/right/up/down  WASD / arrows
#   skill_e / skill_q        the god's two favors
#   attack                   LEFT MOUSE - the mortal's attack (Arnis,
#                            Tumbang Preso). Ignore it while a dialogue or a
#                            menu is open, exactly like the other actions.

const UI_STRIP_WIDTH := 238.0
const DESIGN_SIZE := Vector2(1152.0, 648.0)

# Node name of the locked marker scene designers leave over the strip.
const UI_STRIP_NODE := "GAME UI AREA"


# The left band of the screen the shell's panels cover: keep it clear.
static func ui_strip_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(UI_STRIP_WIDTH, DESIGN_SIZE.y))


# The rest of the screen - the only place an arena may put its art.
static func play_area() -> Rect2:
	return Rect2(
		Vector2(UI_STRIP_WIDTH, 0.0),
		Vector2(DESIGN_SIZE.x - UI_STRIP_WIDTH, DESIGN_SIZE.y)
	)
