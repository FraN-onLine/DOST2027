class_name God
extends Resource

# One of the gods of the God Games (Bathala's contest).
# A god owns an arena game, a colour, an icon and the favors it can bestow - and
# every word it says: its first-trial intro, its closing lines, and what it says
# about each god that can follow it. All of it is data, so a new god is a .tres
# and a scene and never a code change.

@export var id: StringName = &""
@export var display_name: String = ""
@export var epithet: String = ""
@export var color: Color = Color.WHITE
@export var icon: Texture2D
@export var game_name: String = ""
@export_multiline var game_blurb: String = ""
@export var arena_scene: String = ""
@export var implemented: bool = false
@export var favors: Array[GodFavor] = []

# --- DIALOGUE -----------------------------------------------------------------
# The run never stops between gods: one god's closing lines hand the field to the
# next and no winner is declared until Bathala's final trial. So a god carries:
#
#   intro_lines      spoken the FIRST time this god hosts a trial.
#   trial_end_lines  spoken when its trial ends, before the hand-over.
#   transition_lines what it says about the god that follows - one entry per
#                    possible next god, keyed by that god's id, so EVERY
#                    combination (Apolaki -> Mayari, Apolaki -> Tala, ...) is a
#                    data change and never a code change. The key "*" is the
#                    fallback for a god with no line for the next one.
#   success_lines /  spoken only at Bathala's final trial, where the run is
#   failure_lines    finally judged.
@export var intro_lines: Array[String] = []
@export var trial_end_lines: Array[String] = []
@export var success_lines: Array[String] = []
@export var failure_lines: Array[String] = []
@export var transition_lines: Dictionary = {}  # next god id (String) -> Array[String]


func get_favor(favor_id: StringName) -> GodFavor:
	for favor in favors:
		if favor.id == favor_id:
			return favor
	return null


# What this god says about moving on to `next_god_id`, falling back to the "*"
# entry and then to a plain hand-over line.
func transition_to(next_god_id: StringName, next_name: String) -> Array[String]:
	var lines: Array[String] = []
	for key in [str(next_god_id), "*"]:
		var entry = transition_lines.get(key)
		if entry is Array and not (entry as Array).is_empty():
			for line in entry:
				lines.append(str(line))
			return lines
	lines.append("%s, the field is yours." % next_name)
	return lines
