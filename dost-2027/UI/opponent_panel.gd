extends PanelContainer

# One rival in the shell's column: icon and name, FAVOR and DUE, the two favor
# bars, the line a trial puts in the panel (Game.show_trial_row; hidden when none), and the Pamana they carry (a small badge, hidden when none). Framed in
# the accent of the god the rival wears (UITokens.god_accent), with a swatch of
# their bandana colour beside the name - the headband their mortal wears in the arena.

@onready var name_label = $MarginContainer/VBoxContainer/Header/NameLabel
@onready var god_icon: TextureRect = $MarginContainer/VBoxContainer/Header/Icon
@onready var favor_label = $MarginContainer/VBoxContainer/StatsLabel/FavorBox/FavorValue
@onready var due_label = $MarginContainer/VBoxContainer/StatsLabel/DueBox/DueValue
@onready var e_bar = $MarginContainer/VBoxContainer/SkillRow/EBar
@onready var q_bar = $MarginContainer/VBoxContainer/SkillRow/QBar
@onready var trial_row: Label = $MarginContainer/VBoxContainer/TrialRow
@onready var pamana_row: HBoxContainer = $MarginContainer/VBoxContainer/PamanaRow
@onready var pamana_icon: TextureRect = $MarginContainer/VBoxContainer/PamanaRow/PamanaIcon
@onready var pamana_label: Label = $MarginContainer/VBoxContainer/PamanaRow/PamanaLabel

var player_id := 0
var _bandana: BandanaSwatch = null


func setup(id: int, player_name: String, favor: int, due: int) -> void:
	player_id = id
	name_label.text = player_name
	update_stats(favor, due)


# The name is live - the lobby's UPDATE NAME can change it mid-game - so it is
# repainted on its own instead of rebuilding the whole column.
func set_name_text(player_name: String) -> void:
	name_label.text = player_name


# The colour of this rival's bandana (an index into UITokens.BANDANA_COLORS).
func set_bandana(color_index: int) -> void:
	if _bandana == null:
		_bandana = BandanaSwatch.mark(color_index)
		var header := name_label.get_parent()
		header.add_child(_bandana)
		header.move_child(_bandana, name_label.get_index())
	_bandana.setup(color_index)


func set_god_icon(god_id: StringName) -> void:
	var god := Gods.by_id(god_id)
	if god != null:
		god_icon.texture = god.icon
		add_theme_stylebox_override("panel", UITokens.accent_box(get_theme_stylebox("panel", &"PanelRow"), UITokens.god_accent(god)))


func update_stats(favor: int, due: int) -> void:
	favor_label.text = str(favor)
	due_label.text = str(due)


# The rival's Pamana, the same badge as on our own panel (Game._show_pamana_badge).
func update_pamana(mortal: GodMatch.Mortal) -> void:
	var badges := GodMatch.pamana_badges(mortal)
	pamana_row.visible = not badges.is_empty()
	if badges.is_empty():
		return
	var first: Pamana = badges[0]["pamana"]
	pamana_icon.texture = first.icon
	pamana_icon.modulate = UICards.pamana_edge(first)
	var texts: Array[String] = []
	for badge in badges:
		texts.append(str(badge["text"]))
	pamana_label.text = "  ".join(texts)
	pamana_row.tooltip_text = first.effect


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
