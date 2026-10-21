class_name Cutscene
extends Resource

# A story cutscene as DATA: an ordered list of steps, each one either
#   a line     {"speaker": "BATHALA", "text": "...", "call": "mayari" (optional)}
#   an action  {"action": "hand_seizes"}   (a staged moment; scenes/OpeningCutscene.tscn plays it)
# `call` marks a roll-call line: the god's name pops up big and its portrait slides in.
#
# A speaker is a god (matched on its display name: colour and portrait come from the
# God resource) or one of NEUTRAL_SPEAKERS - mortals with no god resource, drawn in a
# neutral UITokens colour with a placeholder portrait.

const NEUTRAL_SPEAKERS := {
	"INES": UITokens.IVORY,
	"SUITOR 1": UITokens.MUTED,
	"SUITOR 2": UITokens.MUTED,
}

@export var steps: Array[Dictionary] = []

static var _placeholders := {}  # Color -> GradientTexture2D


# The god a speaker name belongs to, or null (a mortal).
static func god_named(speaker: String) -> God:
	for god in Gods.all():
		if god.display_name == speaker:
			return god
	return null


static func knows_speaker(speaker: String) -> bool:
	return NEUTRAL_SPEAKERS.has(speaker) or god_named(speaker) != null


# The dialogue-box entry for a line step.
static func entry_for(step: Dictionary) -> Dictionary:
	var speaker := str(step.get("speaker", ""))
	var entry := {"speaker": speaker, "text": str(step.get("text", "")), "color": Color.WHITE}
	var god := god_named(speaker)
	if god != null:
		entry["color"] = god.color
		entry["portrait"] = god.portrait if god.portrait != null else god.icon
	elif NEUTRAL_SPEAKERS.has(speaker):
		entry["color"] = NEUTRAL_SPEAKERS[speaker]
		entry["portrait"] = placeholder(entry["color"])
		entry["hide_photo"] = true  # no big photo for a mortal until there is art
	return entry


# A soft round blob in `color`: the portrait of a speaker that has no art yet.
static func placeholder(color: Color) -> Texture2D:
	if not _placeholders.has(color):
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([color, Color(color, 0.0)])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(0.5, 0.0)
		texture.width = 64
		texture.height = 64
		_placeholders[color] = texture
	return _placeholders[color]


# What is wrong with the data, one string per problem (empty = fine).
func problems(known_actions: Array) -> Array[String]:
	var found: Array[String] = []
	if steps.is_empty():
		found.append("the cutscene has no steps")
	for index in range(steps.size()):
		var step := steps[index]
		if step.has("action"):
			if not known_actions.has(str(step["action"])):
				found.append("step %d: unknown action '%s'" % [index, step["action"]])
		elif str(step.get("text", "")) == "":
			found.append("step %d: a line with no text" % index)
		elif not knows_speaker(str(step.get("speaker", ""))):
			found.append("step %d: unknown speaker '%s'" % [index, step.get("speaker", "")])
		if step.has("call") and Gods.by_id(StringName(str(step["call"]))).id != StringName(str(step["call"])):
			found.append("step %d: unknown god '%s' in call" % [index, step["call"]])
	return found
