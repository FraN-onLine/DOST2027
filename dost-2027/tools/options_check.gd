extends SceneTree

# Validation: the Options menu opens from the title screen and BACK returns; volume,
# window mode and a key binding survive save + reload; a key used elsewhere is
# reported as a conflict; reset restores the defaults; the God's Due menu still
# picks with 1/2/3 through the new due_choice_* actions.
# Uses a temporary settings file, never the player's user://settings.cfg.
# Run: godot --headless --path <project> -s res://tools/options_check.gd

const TEMP_CONFIG := "user://settings_check.cfg"

var _problems := 0
var _picked: Array[GodFavor] = []


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _run() -> void:
	await _frames(2)  # let the autoloads finish _ready
	var settings: Node = root.get_node("Settings")
	settings.config_path = TEMP_CONFIG
	settings.reset_all()

	# --- title menu -> Options -> back ---
	var menu: Control = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await _frames(3)
	var button: Button = menu.get_node_or_null("CenterContainer/VBoxContainer/OptionsButton")
	_check(button != null and button.text == "OPTIONS", "the main menu carries an OPTIONS button")
	if button == null:
		return _finish(settings)
	var order := button.get_parent().get_children()
	_check(order.find(button) == order.find(menu.get_node("CenterContainer/VBoxContainer/AlmanacButton")) + 1
		and order.find(button) + 1 == order.find(menu.get_node("CenterContainer/VBoxContainer/QuitButton")),
		"OPTIONS sits between ALMANAC and QUIT")
	button.pressed.emit()
	await _frames(4)
	var options := current_scene
	_check(options != null and options.name == "Options", "OPTIONS opens res://scenes/Options.tscn")
	if options == null:
		return _finish(settings)
	var tabs: TabContainer = options.get_node("Panel/Margin/VBox/Tabs")
	_check(tabs.get_tab_count() == 4, "the Options screen has four tabs")
	_check(options.get_node("Panel/Margin/VBox/Tabs/Controls/List").get_child_count() == settings.ACTIONS.size(),
		"the Controls tab has a row for every rebindable action")
	var back: Button = options.get_node_or_null("Panel/Margin/VBox/Buttons/BackButton")
	_check(back != null, "the Options screen offers a BACK button")
	if back != null:
		back.pressed.emit()
		await _frames(4)
		_check(current_scene != null and current_scene.name == "MainMenu", "BACK returns to the main menu")

	# --- save / reload ---
	settings.set_value("audio", "music", 33)
	settings.set_value("video", "window_mode", 2)
	settings.set_binding("skill_e", _key(KEY_T))
	settings.save()
	settings.reset_all()
	_check(settings.get_value("audio", "music") == 80, "reset_all restores the default music volume")
	_check(settings.get_value("video", "window_mode") == 0, "reset_all restores windowed mode")
	_check(settings.primary_event("skill_e").physical_keycode == KEY_E, "reset_all restores the default Skill E key")
	settings.load_config()
	_check(settings.get_value("audio", "music") == 33, "the saved music volume reloads")
	_check(settings.get_value("video", "window_mode") == 2, "the saved window mode reloads")
	_check(InputMap.event_is_action(_key(KEY_T), "skill_e") and not InputMap.event_is_action(_key(KEY_E), "skill_e"),
		"the saved Skill E binding reloads into the InputMap")

	# --- conflicts, swap, reset ---
	settings.reset_controls()
	_check(settings.conflict_for("skill_q", _key(KEY_E)) == "skill_e", "binding Skill Q to E is reported as a conflict with Skill E")
	_check(settings.conflict_for("skill_q", _key(KEY_T)) == "", "an unused key is no conflict")
	settings.swap_binding("skill_q", _key(KEY_E))
	_check(settings.primary_event("skill_q").physical_keycode == KEY_E and settings.primary_event("skill_e").physical_keycode == KEY_Q,
		"swap exchanges the two bindings")
	settings.set_value("audio", "sfx", 10)
	settings.reset_section("audio")
	_check(settings.get_value("audio", "sfx") == 100, "reset_section restores that tab's defaults")
	settings.reset_controls()
	_check(settings.primary_event("skill_q").physical_keycode == KEY_Q, "reset_controls restores the project.godot keys")

	# --- God's Due 1/2/3 ---
	for index in range(1, 4):
		_check(InputMap.has_action("due_choice_%d" % index), "due_choice_%d exists" % index)
	_check(InputMap.event_is_action(_key(KEY_KP_3), "due_choice_3"), "keypad 3 also picks choice 3")
	var due: Control = load("res://UI/GodsArena/gods_due_menu.tscn").instantiate()
	var rules := GodMatch.new()
	rules.setup(Gods.mayari(), "ME", [])
	root.add_child(rules)
	root.add_child(due)
	await _frames(2)
	due.favor_chosen.connect(func(favor: GodFavor, _left: int) -> void: _picked.append(favor))
	due.open(Gods.mayari(), rules, 1, true)
	await _frames(2)
	due._unhandled_input(_key(KEY_2))
	_check(_picked.size() == 1, "pressing 2 in the God's Due menu picks a favor")
	due.queue_free()
	_finish(settings)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1


func _finish(settings: Node) -> void:
	settings.reset_all()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_CONFIG))
	print("options checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
