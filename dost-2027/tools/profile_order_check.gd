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
	_check(not game.get_node("OtherPlayersPanel").visible, "Apolaki hides the opponent sidebar")
	_check(not game.arena.shares_mortal_positions(), "Apolaki does not publish mortal coordinates")
	_check(not game.arena.hud.results_panel.visible, "Apolaki does not show an intermediate summary")

	game._on_trial_complete()
	await _frames(4)
	_check(game.arena.god_id == &"mayari", "Apolaki transitions to the next selected god")
	_check(game.get_node("OtherPlayersPanel").visible, "Mayari restores the shared-player sidebar")
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