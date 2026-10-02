extends SceneTree

# Validation: the Almanac is reachable from the main menu (its own button) and
# its BACK button returns to the menu.
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
	var favor_list := almanac.get_node_or_null("CenterContainer/VBoxContainer/ScrollContainer/FavorList")
	_check(favor_list != null and favor_list.get_child_count() > 0, "the almanac lists the gods' favors")
	var back: Button = almanac.get_node_or_null("CenterContainer/VBoxContainer/BackButton")
	_check(back != null, "the almanac offers a BACK button")
	if back != null:
		back.pressed.emit()
		await _frames(4)
		_check(current_scene != null and current_scene.name == "MainMenu", "BACK returns to the main menu")
	_finish()


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