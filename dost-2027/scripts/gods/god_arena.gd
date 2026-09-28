class_name GodArena
extends Node2D

# The shared base every god's arena extends (Mayari now, Apolaki and the rest
# later): an arena scene's root script says `extends GodArena` and inherits
# everything below.
#
# WHAT EVERY ARENA GETS FROM HERE
#
#   * UI_STRIP_WIDTH - the left band of the screen the Game shell
#     (scenes/Game.tscn) covers with its panels (your name, FAVOR, DUE, the E/Q
#     favor bars, the other mortals). An arena is therefore authored in screen
#     space, exactly as it will be played: the scene is 1152 x 648 big, the left
#     UI_STRIP_WIDTH pixels stay EMPTY of gameplay art (no floor, no goal, no
#     clone and no mortal starts there - MayariArena.tscn keeps a locked
#     "GAME UI AREA" body over the strip so the reservation is visible while
#     editing) and nothing scales, stretches or re-centres the scene at runtime.
#     The shell only instantiates the arena and hands it god_id / embedded /
#     dialogue_prefix. What the designer sees in the arena scene is what every
#     player gets.
#
#   * trial_time - THE round clock: one minute thirty seconds. Every arena runs
#     on this single number, so change it here (in the arena code) and all of
#     them change with it.
#
#   * countdown_time - the "3 - 2 - 1" the mortals wait through before it does.
#
#   * FAVOR_COLOR - the yellow a favor zone burns in while it is lit.
#
# Input every arena can count on (project.godot):
#   move_left/right/up/down  WASD / arrows
#   skill_e / skill_q        the god's two favors
#   attack                   LEFT MOUSE - the mortal's attack (Arnis,
#                            Tumbang Preso). Ignore it while a dialogue or a
#                            menu is open, exactly like the other actions.

const UI_STRIP_WIDTH := 238.0

# The colour a favor zone glows while Mayari is lighting it.
const FAVOR_COLOR := Color(1.0, 0.86, 0.25)


@export_category("Shared Arena Rules")
# The round every arena is played in - 1:30. This is the one clock shared by all
# arenas: edit this number and every arena follows.
@export var trial_time := 90.0
# The "3 - 2 - 1" the mortals wait through before the round starts.
@export var countdown_time := 3.0
