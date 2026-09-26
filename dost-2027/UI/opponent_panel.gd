extends PanelContainer

@onready var name_label = $MarginContainer/VBoxContainer/NameLabel
@onready var favor_label = $MarginContainer/VBoxContainer/StatsLabel/FavorBox/FavorValue
@onready var due_label = $MarginContainer/VBoxContainer/StatsLabel/DueBox/DueValue
@onready var e_bar = $MarginContainer/VBoxContainer/SkillRow/EBar
@onready var q_bar = $MarginContainer/VBoxContainer/SkillRow/QBar

var player_id := 0


func setup(id: int, player_name: String, favor: int, due: int) -> void:
	player_id = id
	name_label.text = player_name
	update_stats(favor, due)


func update_stats(favor: int, due: int) -> void:
	favor_label.text = str(favor)
	due_label.text = str(due)


func update_skill_bar(match: GodMatch, mortal: GodMatch.Mortal) -> void:
	_update_bar(e_bar, match, mortal, GodFavor.Slot.E)
	_update_bar(q_bar, match, mortal, GodFavor.Slot.Q)


func _update_bar(bar: ProgressBar, _match: GodMatch, mortal: GodMatch.Mortal, slot: int) -> void:
	var favor := mortal.favor_in_slot(slot)
	if favor == null:
		bar.value = 0.0
		bar.tooltip_text = "%s  --" % ("E" if slot == GodFavor.Slot.E else "Q")
		return
	var ratio := 1.0
	if favor.cooldown > 0.0:
		ratio = clampf(1.0 - mortal.cooldown_left(favor.id) / favor.cooldown, 0.0, 1.0)
	bar.value = ratio * 100.0
	bar.modulate = favor.color
	bar.tooltip_text = "%s  %s" % [("E" if slot == GodFavor.Slot.E else "Q"), favor.display_name]
