extends SceneTree

# Validation: the Almanac is reachable from the main menu (its own button) and
# its BACK button returns to the menu. Inside it:
#   * both index choices (MGA DIYOS, MGA PABOR) open their pages
#   * every god and every favor in the registry has exactly one card
#   * selecting a card fills the detail panel
#   * a favor packet on a god's page jumps to that favor on the favors page
# Run: godot --headless --path <project> -s res://tools/menu_almanac_check.gd

var _problems := 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	var menu: Control = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(menu)
	await _frames(3)

	var button: Button = menu.get_node_or_null("CenterContainer/VBoxContainer/AlmanacButton")
	_check(button != null, "the main menu carries an ALMANAC button")
	if button == null:
		return _finish()
	_check(button.text == "ALMANAC", "the button is labelled ALMANAC")

	current_scene = menu
	button.pressed.emit()
	await _frames(4)
	var almanac := current_scene
	_check(almanac != null and almanac.name == "Almanac", "ALMANAC opens res://scenes/Almanac.tscn")
	if almanac == null:
		return _finish()
	_check(almanac.index_page.visible and not almanac.page.visible, "the almanac opens on its index")

	# --- the gods ------------------------------------------------------------------
	almanac.gods_choice.pressed.emit()
	await _frames(3)
	_check(almanac.page_kind == "gods" and almanac.page.visible, "MGA DIYOS opens the gods page")
	var gods := Gods.all()
	_check(_one_card_each(almanac, gods.map(func(god: God) -> StringName: return god.id)),
		"every god has exactly one card (%d)" % gods.size())
	var second: God = gods[1]
	almanac.card_grid.get_child(1).pressed.emit()
	await _frames(2)
	_check(almanac.selected_id == second.id and almanac.detail_name.text == second.display_name
		and almanac.detail_description.text == second.game_blurb, "selecting a god fills the detail panel")
	_check(almanac.detail_packets.get_child_count() == second.favors.size(), "the god's page shows one packet per favor")
	var packet: Button = almanac.detail_packets.get_child(1) if almanac.detail_packets.get_child_count() > 1 else null
	if packet != null:
		var target := StringName(str(packet.get_meta("id")))
		packet.pressed.emit()
		await _frames(3)
		_check(almanac.page_kind == "favors" and almanac.selected_id == target
			and almanac.detail_name.text == Gods.favor_by_id(target).display_name,
			"a god's favor packet jumps to that favor (%s)" % target)

	# --- back to the index, then the favors ------------------------------------------
	almanac.page_back.pressed.emit()
	await _frames(2)
	_check(almanac.page_kind == "" and almanac.index_page.visible, "the page's BACK returns to the index")
	almanac.favors_choice.pressed.emit()
	await _frames(3)
	_check(almanac.page_kind == "favors" and almanac.page.visible, "MGA PABOR opens the favors page")
	var favor_ids: Array = []
	for god in gods:
		for favor in god.favors:
			favor_ids.append(favor.id)
	_check(_one_card_each(almanac, favor_ids), "every favor has exactly one card (%d)" % favor_ids.size())
	var first_id := StringName(str(almanac.card_grid.get_child(0).get_meta("id")))
	_check(almanac.selected_id == first_id, "the first card is selected when the page opens")
	var last: Button = almanac.card_grid.get_child(almanac.card_grid.get_child_count() - 1)
	last.pressed.emit()
	await _frames(2)
	var last_favor := Gods.favor_by_id(StringName(str(last.get_meta("id"))))
	_check(almanac.detail_name.text == last_favor.display_name and almanac.detail_description.text == last_favor.description,
		"selecting a favor fills the detail panel")
	# A god's filter chip keeps that god's favors only.
	almanac._set_filter(gods[0].id)
	await _frames(2)
	_check(almanac.card_grid.get_child_count() == gods[0].favors.size(), "a filter chip shows only that god's favors")
	almanac._set_filter(&"")
	await _frames(2)

	almanac.page_back.pressed.emit()
	await _frames(2)
	var back: Button = almanac.back_button
	_check(back != null, "the almanac offers a BACK button")
	if back != null:
		back.pressed.emit()
		await _frames(4)
		_check(current_scene != null and current_scene.name == "MainMenu", "BACK returns to the main menu")
	_finish()


# The grid's cards carry exactly the expected ids, each once.
func _one_card_each(almanac: Node, ids: Array) -> bool:
	var seen: Array = []
	for card in almanac.card_grid.get_children():
		seen.append(StringName(str(card.get_meta("id"))))
	if seen.size() != ids.size():
		return false
	for id in ids:
		if seen.count(id) != 1:
			return false
	return true


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1


func _finish() -> void:
	print("menu/almanac checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
