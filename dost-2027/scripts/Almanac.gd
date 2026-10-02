extends Control

# The Almanac: every Favor in the God Games, in one list.
#
# It reads the gods themselves (Gods.all() -> each god's favors), so a favor is
# listed here the moment it exists in a .tres - nobody has to remember to add it
# to a page. Each row answers the three questions a mortal asks about a boon:
#
#   * /which god bestows it/  - the section header, in that god's colour
#   * /what it does/          - the favor's own description
#   * /what it asks for/      - its condition. A favor with a `requires_god`
#                               param is only OFFERED while the mortal already
#                               holds a favor of that god (Mayari's and
#                               Apolaki's Sibling's Rivalry each ask for a favor
#                               of the other sibling), and a slot favor says
#                               whether it binds to E or Q.
#
# Nothing here is authored by hand: the list is rebuilt from the registry every
# time the scene opens.

const PLACEHOLDER_ICON := preload("res://icon.svg")

@onready var favor_list: VBoxContainer = $CenterContainer/VBoxContainer/ScrollContainer/FavorList
@onready var subtitle_label: Label = $CenterContainer/VBoxContainer/SubtitleLabel
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	_build()


func _build() -> void:
	for child in favor_list.get_children():
		favor_list.remove_child(child)
		child.queue_free()

	var total := 0
	for god in Gods.all():
		if god.favors.is_empty():
			continue
		favor_list.add_child(_god_header(god))
		for favor in god.favors:
			favor_list.add_child(_favor_row(god, favor))
			total += 1
	subtitle_label.text = "%d Favors, bestowed by %d gods" % [total, Gods.all().size()]


func _god_header(god: God) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(god.color.r, god.color.g, god.color.b, 0.16)
	style.border_width_left = 3
	style.border_color = god.color
	style.content_margin_left = 10
	style.content_margin_top = 6
	style.content_margin_right = 10
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if god.icon != null:
		var portrait := TextureRect.new()
		portrait.texture = god.icon
		portrait.custom_minimum_size = Vector2(34, 34)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(portrait)

	var title := Label.new()
	title.text = "%s  -  %s" % [god.display_name.to_upper(), god.game_name]
	title.add_theme_color_override("font_color", god.color)
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	panel.add_child(row)
	return panel


func _favor_row(god: God, favor: GodFavor) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.2, 0.85)
	style.border_width_left = 2
	style.border_color = Color(favor.color.r, favor.color.g, favor.color.b, 0.5)
	style.content_margin_left = 10
	style.content_margin_top = 6
	style.content_margin_right = 10
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var icon := TextureRect.new()
	icon.texture = favor.icon if favor.icon != null else PLACEHOLDER_ICON
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = favor.color
	row.add_child(icon)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)

	var name := Label.new()
	name.text = "%s   [%s]" % [favor.display_name, favor.slot_name()]
	name.add_theme_color_override("font_color", favor.color)
	name.add_theme_font_size_override("font_size", 13)
	box.add_child(name)

	var effect := Label.new()
	effect.text = favor.description
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	effect.add_theme_font_size_override("font_size", 11)
	box.add_child(effect)

	var meta := Label.new()
	meta.text = _condition_text(god, favor)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.add_theme_color_override("font_color", Color(0.62, 0.68, 0.8))
	meta.add_theme_font_size_override("font_size", 10)
	box.add_child(meta)

	row.add_child(box)
	panel.add_child(row)
	return panel


# "Bestowed by X" plus whatever the favor asks for.
func _condition_text(god: God, favor: GodFavor) -> String:
	var parts: Array[String] = ["Bestowed by %s" % god.display_name]
	var required := favor.requires_god_id()
	if required != &"":
		var other := Gods.by_id(required)
		var other_name := other.display_name if other != null else str(required).to_upper()
		parts.append("CONDITION: only offered while you already hold a %s favor" % other_name)
	if favor.is_skill():
		parts.append("binds to %s" % favor.slot_name())
	if favor.cooldown > 0.0:
		parts.append("cooldown %.0fs" % favor.cooldown)
	if favor.duration > 0.0:
		parts.append("lasts %.0fs" % favor.duration)
	return "   |   ".join(parts)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
