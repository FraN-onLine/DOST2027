class_name God
extends Resource

# One of the gods of the God Games (Bathala's contest).
# A god owns an arena game, a color and the favors it can bestow.

@export var id: StringName = &""
@export var display_name: String = ""
@export var epithet: String = ""
@export var color: Color = Color.WHITE
@export var game_name: String = ""
@export_multiline var game_blurb: String = ""
@export var arena_scene: String = ""
@export var implemented: bool = false
@export var favors: Array[GodFavor] = []
@export var intro_lines: Array[String] = []
@export var success_lines: Array[String] = []
@export var failure_lines: Array[String] = []


func get_favor(favor_id: StringName) -> GodFavor:
	for favor in favors:
		if favor.id == favor_id:
			return favor
	return null


func favors_for_slot(slot: int) -> Array[GodFavor]:
	var out: Array[GodFavor] = []
	for favor in favors:
		if int(favor.slot) == slot:
			out.append(favor)
	return out
