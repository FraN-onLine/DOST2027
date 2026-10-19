class_name Pamana
extends Resource

# A Pamana (heirloom): one of the temporary items sold at the Tindahan in the
# preparation area between two trials. Each one is a real object or symbol from
# Philippine history or folklore. It is bought with FAVOR, waits for the next
# trial and works only in it (Surigao Gold instead waits for a God's Due).
#
# Everything here is data, like GodFavor: the shop, the HUD badge and the
# Almanac's MGA PAMANA page all read the same resource. The RULES of each item
# live in GodMatch (scripts/gods/god_match.gd, THE PAMANA section), keyed by id.
#
# The files are under res://resources/pamana/ (Pamanas loads them); rebuild them
# with tools/build_pamana.gd or edit the .tres in the editor.

# When it works: the whole next trial, only the first `window` seconds of it, or
# until it has been used (Surigao Gold: the next God's Due).
enum Timing { WHOLE_TRIAL, FIRST_WINDOW, UNTIL_USED }
# What the mortal must hold for the item to help at all: the shop never offers a
# skill item to someone with no skill in that slot.
enum Needs { NOTHING, E_SKILL, Q_SKILL, ANY_SKILL }

@export var id: StringName = &""
@export var display_name: String = ""
@export var cost: int = 0                     # FAVOR
@export_multiline var effect: String = ""     # the one-line rule (shop and Almanac)
@export var timing: Timing = Timing.WHOLE_TRIAL
@export var window: float = 0.0               # FIRST_WINDOW: seconds it lasts
@export var params: Dictionary = {}
@export var era: String = ""
@export var origin: String = ""
@export_multiline var history: String = ""
@export var flavor: String = ""
@export var needs: Needs = Needs.NOTHING
@export var color: Color = Color.WHITE
@export var icon: Texture2D


func param(key: String, fallback: float) -> float:
	return float(params.get(key, fallback))


# The Almanac's timing chip.
func timing_name() -> String:
	match timing:
		Timing.FIRST_WINDOW:
			return "FIRST %ds" % int(window)
		Timing.UNTIL_USED:
			return "UNTIL USED"
	return "NEXT TRIAL"


# The Almanac's needs chip ("" when it needs nothing).
func needs_name() -> String:
	match needs:
		Needs.E_SKILL:
			return "NEEDS E"
		Needs.Q_SKILL:
			return "NEEDS Q"
		Needs.ANY_SKILL:
			return "NEEDS A SKILL"
	return ""
