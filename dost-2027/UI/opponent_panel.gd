extends PanelContainer

@onready var name_label = $MarginContainer/VBoxContainer/NameLabel
@onready var god_icon: TextureRect = $MarginContainer/VBoxContainer/Icon
@onready var favor_label = $MarginContainer/VBoxContainer/StatsLabel/FavorBox/FavorValue
@onready var due_label = $MarginContainer/VBoxContainer/StatsLabel/DueBox/DueValue
@onready var e_bar = $MarginContainer/VBoxContainer/SkillRow/EBar
@onready var q_bar = $MarginContainer/VBoxContainer/SkillRow/QBar

var player_id := 0


func setup(id: int, player_name: String, favor: int, due: int) -> void:
	player_id = id
	name_label.text = player_name
	update_stats(favor, due)


# The name is live - the lobby's UPDATE NAME can change it mid-game - so it is
# repainted on its own instead of rebuilding the whole column.
func set_name_text(player_name: String) -> void:
	name_label.text = player_name


func set_god_icon(god_id: StringName) -> void:
	var god := Gods.by_id(god_id)
	if god != null:
		god_icon.texture = god.icon


func update_stats(favor: int, due: int) -> void:
	favor_label.text = str(favor)
	due_label.text = str(due)


func update_skill_bar(match: GodMatch, mortal: GodMatch.Mortal) -> void:
	_update_bar(e_bar, match, mortal, GodFavor.Slot.E)
	_update_bar(q_bar, match, mortal, GodFavor.Slot.Q)


func _update_bar(bar: ProgressBar, match: GodMatch, mortal: GodMatch.Mortal, slot: int) -> void:
	var favor := mortal.favor_in_slot(slot)
	if favor == null:
		bar.value = 0.0
		bar.tooltip_text = "%s  --" % ("E" if slot == GodFavor.Slot.E else "Q")
		return
	var ratio := match.skill_cooldown_ratio(slot, mortal.id)
	bar.value = ratio * 100.0
	bar.modulate = favor.color
	bar.tooltip_text = "%s  %s" % [("E" if slot == GodFavor.Slot.E else "Q"), favor.display_name]
