extends SceneTree

# Regression check for the shared trial sequence and god-icon profile flow.
# Run: godot --headless --path <project> -s res://tools/profile_order_check.gd

var _problems := 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)
	await _frames(2)
	var local_id := 1
	var network: Node = root.get_node("Network")
	network.players = {local_id: "HOST", 2: "RIVAL"}
	network.player_data = {local_id: PlayerData.new("HOST"), 2: PlayerData.new("RIVAL")}
	network.player_icons = {local_id: &"mayari", 2: &"apolaki"}
	network.my_god_icon_id = &"mayari"

	var lobby: Control = load("res://scenes/Lobby.tscn").instantiate()
	view.add_child(lobby)
	await _frames(3)
	var apolaki_index := _god_option_index(lobby, &"apolaki")
	_check(apolaki_index >= 0, "lobby lists Apolaki as a selectable icon")
	if apolaki_index >= 0:
		lobby._on_god_icon_selected(apolaki_index)
	_check(network.player_icons.get(local_id) == &"apolaki", "host selection is stored as the player's icon ID")
	_check(lobby.god_icon_preview.texture == Gods.apolaki().icon, "lobby preview shows the selected god portrait")
	_check(lobby.player_list_vbox.get_child(1).get_child(0).texture == Gods.apolaki().icon, "lobby roster shows the selected portrait")
	var options = lobby.lobby_options
	_check(not options.visible, "the Lobby Options panel stays out of sight until OPTIONS asks for it")
	_check(lobby.options_button.text == "OPTIONS" and lobby.options_button.visible, "the lobby carries an OPTIONS button")
	lobby._on_options_pressed()
	_check(options.visible and options.editable, "OPTIONS opens the host's editable Lobby Options")
	await _frames(2)
	# CUSTOM: one row per trial slot, filled by the no-repeat rule, plus the
	# Bathala row; the arrows walk a slot up and down.
	network.set_run_settings(RunSettings.defaults().to_dict())
	options.custom_box.button_pressed = true
	var settings: RunSettings = network.run_settings
	_check(settings.order_mode == RunSettings.ORDER_CUSTOM and settings.custom_order.size() == settings.trials,
		"CUSTOM starts with one god per trial")
	_check(options.order_list.get_child_count() == settings.trials + 1, "CUSTOM shows one row per trial, then Bathala's finale")
	await _frames(2)
	var panel_box: Rect2 = options.get_global_rect()
	var rows_box: Rect2 = options.order_scroll.get_global_rect()
	_check(rows_box.end.x <= panel_box.end.x and rows_box.end.y <= panel_box.end.y,
		"the open panel is big enough for the list it shows")
	var start: Array[StringName] = settings.custom_order.duplicate()
	var moved: Array[StringName] = start.duplicate()
	moved[0] = start[1]
	moved[1] = start[0]
	options._on_move_pressed(1, -1)
	_check(network.run_settings.custom_order == moved, "the UP arrow walks a god one place up")
	options._on_move_pressed(0, 1)
	_check(network.run_settings.custom_order == start, "the DOWN arrow walks it back down")
	# Only the host holds the setup: a client sees it read-only and cannot move a
	# god, even by calling in.
	lobby.is_host = false
	options.open(false)
	_check(options.host_note.visible and options.plus_button.disabled and options.custom_box.disabled,
		"a client sees the setup read-only")
	options._on_move_pressed(1, -1)
	_check(network.run_settings.custom_order == start, "a client cannot reorder the run")
	lobby.is_host = true
	options.open(true)
	_check(not options.host_note.visible and not options.plus_button.disabled, "the host gets the controls back")
	# RANDOM: the tick box hands the order back to the host's draw.
	options.random_box.button_pressed = true
	_check(network.run_settings.order_mode == RunSettings.ORDER_RANDOM and options.run_line.text.begins_with("Random"),
		"RANDOM hands the order back to the draw")
	_check(options.order_list.get_child_count() == 0, "RANDOM leaves nothing to walk")
	options.close()

	# The host owns the order: a plan it already announced is the plan the run
	# plays - start_game must never redraw behind its players' backs - and the
	# NEXT run draws its own.
	network.set_run_settings({"trials": 3, "order_mode": "custom", "custom_order": ["tala", "apolaki", "mayari"]})
	var promised: Array = network.planned_trial_order()
	network.announced_trial_order = promised.duplicate()
	var settled: Array = network._settle_trial_order()
	_check(settled == promised, "the run plays the plan the host already announced")
	_check(network.announced_trial_order.is_empty(), "the announcement is spent on the run it was made for")
	network.set_run_settings(RunSettings.defaults().to_dict())
	var redrawn: Array = network._settle_trial_order()
	_check(redrawn.size() == Gods.TRIALS_DEFAULT + 1 and StringName(str(redrawn[redrawn.size() - 1])) == Gods.BATHALA,
		"the next run draws an order of its own")
	# The announcement is a CALL_LOCAL rpc, so on a hosted lobby the host runs the
	# handler on its own live data. The handler must copy what it was handed, or
	# the setup vanishes the moment it is sent.
	network.set_run_settings({"trials": 3, "order_mode": "custom", "custom_order": ["tala", "mayari", "hanan"]})
	var live: Dictionary = network.run_settings.to_dict()
	network.rpc_sync_run_settings(live)
	_check(network.run_settings.custom_order == [&"tala", &"mayari", &"hanan"], "the host's own setup survives its own announcement")
	network.set_run_settings(RunSettings.defaults().to_dict())
	var run_order: Array[StringName] = [&"tala", &"mayari", &"apolaki", &"bathala"]
	network.trial_order_ids = run_order
	network.rpc_sync_trial_order(network.trial_order_ids)
	_check(network.trial_order_ids == run_order, "the host's run order survives its own announcement")
	var gods := Gods.all()
	for source in gods:
		if not source.implemented or source.arena_scene == "":
			continue
		_check(source.intro_lines.size() <= 3, "%s opening has at most three dialogue lines" % source.display_name)
		_check(not source.trial_end_lines.is_empty(), "%s has neutral trial-end dialogue" % source.display_name)
		for destination in gods:
			_check(source.transition_lines.has(str(destination.id)), "%s has a transition to %s" % [source.display_name, destination.display_name])

	var order: Array[StringName] = [&"apolaki", &"mayari", &"tala", &"bathala"]
	network.rpc_sync_trial_order(order)
	var game: Control = load("res://scenes/Game.tscn").instantiate()
	view.add_child(game)
	await _frames(4)
	var actual: Array[StringName] = []
	for god in game.trial_order:
		actual.append(god.id)
	_check(actual == order, "game shell follows the synchronized order exactly")
	_check(game.own_god_icon.texture == Gods.apolaki().icon, "own sidebar shows the selected portrait")
	var rival_panel = game.other_player_panels.get(2)
	_check(rival_panel != null and rival_panel.god_icon.texture == Gods.apolaki().icon, "opponent sidebar shows that player's portrait")
	_check(game.get_node("OtherPlayersPanel").visible, "Apolaki keeps the shared-player sidebar on screen (Apolaki is local, the roster is not)")
	_check(not game.arena.shares_mortal_positions(), "Apolaki does not publish mortal coordinates")
	_check(not game.arena.hud.results_panel.visible, "Apolaki does not show an intermediate summary")

	game._on_trial_complete()
	await _frames(4)
	_check(game.arena.god_id == &"mayari", "Apolaki transitions to the next selected god")
	_check(game.get_node("OtherPlayersPanel").visible, "the shared-player sidebar stays on screen after the hand-over")
	_check(not game.finale_panel.visible, "the run summary stays hidden after the first game")
	game._on_trial_complete()
	await _frames(4)
	_check(game.arena.god_id == &"tala", "Mayari transitions to Tala")
	_check(not game.finale_panel.visible, "the run summary stays hidden before the final marker")
	game._on_trial_complete()
	await _frames(4)
	_check(game.arena == null and game.finale_panel.visible, "Bathala shows the cumulative summary after all games")
	game.run_snapshot = {
		1: {"name": "HOST", "favor": 900, "due": 0},
		2: {"name": "RIVAL", "favor": 750, "due": 0},
	}
	game._show_finale()
	_check(game.finale_summary.text.contains("HOST") and game.finale_summary.text.contains("RIVAL"), "final summary includes all players")

	var second_game: Control = load("res://scenes/Game.tscn").instantiate()
	view.add_child(second_game)
	await _frames(3)
	var second_order: Array[StringName] = []
	for god in second_game.trial_order:
		second_order.append(god.id)
	_check(second_order == order, "a second player's game shell receives the same trial sequence")

	print("profile/order checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _god_option_index(lobby: Control, god_id: StringName) -> int:
	var option: OptionButton = lobby.god_icon_option
	for index in range(option.item_count):
		if StringName(str(option.get_item_metadata(index))) == god_id:
			return index
	return -1


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1