extends Control

# THE PLAYGROUND'S GAME TESTS.
#
# Opened at the campfire with a left click (playground.gd): one row per god, with
# the game it hosts and the same instructions the lobby's almanac shows. TEST
# plays that one trial on its own; the Playground takes it from there and the
# test walks back here when it ends. Solo only - the arenas' own stand-in rivals
# and Langit Lupa's bots are the opposition.
#
# Bathala closes the run in the lobby, but here he is just another game, so his
# Agawan Base sits last in the list. Sidapa raises an extra note: in the
# Playground's fiction he is also the God of Death.

signal test_requested(god_id: StringName)
signal closed

const ROW_ICON := 48
const RULES_WIDTH := 560.0

@onready var rows: VBoxContainer = $Center/Panel/Margin/VBox/Scroll/Rows


func _ready() -> void:
	visible = false
	_fill()


func is_open() -> bool:
	return visible


func open() -> void:
	if visible:
		return
	visible = true
	UITokens.reveal(self)
	for row in rows.get_children():
		var button := row.get_node_or_null("Margin/Body/Test") as Button
		if button != null:
			button.grab_focus()
			return


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


# The playable gods in registry order, with Bathala (the finale in the lobby, a
# trial to try here) last.
static func ordered_gods() -> Array[God]:
	var list: Array[God] = []
	var bathala: God = null
	for god in Gods.all():
		if god.id == Gods.BATHALA:
			bathala = god
		elif god.implemented and god.arena_scene != "":
			list.append(god)
	if bathala != null:
		list.append(bathala)
	return list


func _fill() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for god in ordered_gods():
		rows.add_child(_row(god))


func _row(god: God) -> Control:
	var panel := PanelContainer.new()
	panel.name = "Game_%s" % god.id
	panel.theme_type_variation = &"PanelRow"

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, UITokens.SPACE_8)
	panel.add_child(margin)

	var body := HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", UITokens.SPACE_16)
	margin.add_child(body)

	var icon := TextureRect.new()
	icon.name = "GodIcon"
	icon.custom_minimum_size = Vector2(ROW_ICON, ROW_ICON)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# An unwanted visitor is named here: this is the Playground, not a run's
	# preparation area, and the player is choosing what to test.
	icon.texture = god.icon
	body.add_child(icon)

	var text := VBoxContainer.new()
	text.name = "Text"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	body.add_child(text)

	var title := Label.new()
	title.name = "Title"
	title.text = "%s  -  %s" % [god.display_name.to_upper(), god.game_name.to_upper()]
	title.add_theme_color_override("font_color", UITokens.god_text(god))
	title.add_theme_font_size_override("font_size", UITokens.HEADING)
	text.add_child(title)

	var rules := Label.new()
	rules.name = "Rules"
	rules.text = god.game_blurb
	rules.theme_type_variation = &"MutedLabel"
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.custom_minimum_size.x = RULES_WIDTH
	text.add_child(rules)

	if god.id == &"sidapa":
		var death := Label.new()
		death.name = "DeathNote"
		death.text = "Also the God of Death."
		death.add_theme_color_override("font_color", UITokens.EMBER)
		text.add_child(death)

	var test := Button.new()
	test.name = "Test"
	test.text = "TEST"
	test.theme_type_variation = &"SmallButton"
	test.custom_minimum_size = Vector2(96, UITokens.BUTTON_SMALL.y)
	test.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	test.tooltip_text = "Play %s on its own. You return here when it ends." % god.game_name.capitalize()
	test.pressed.connect(_on_test.bind(god.id))
	body.add_child(test)
	return panel


func _on_test(god_id: StringName) -> void:
	test_requested.emit(god_id)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		close()
