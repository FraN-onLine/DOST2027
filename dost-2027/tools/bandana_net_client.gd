extends SceneTree

# The CLIENT half of the networked bandana check (its partner, and how to run the
# two, is in tools/bandana_net_host.gd). It joins, reads the colours the host sent,
# asks for a free colour and for the host's own (refused), and after START asks once
# more - nothing changes.

const PORT_FILE := "user://bandana_net_host.txt"
const USER_SETTINGS_FILE := "user://settings_bandana_check_client.cfg"
const WAIT := 30.0

var _problems := 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _until(done: Callable, seconds := WAIT) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return done.call()


func _pause(seconds: float) -> void:
	await _until(func() -> bool: return false, seconds)


func _game() -> Node:
	return current_scene if current_scene != null and current_scene.name == "Game" else null


func _run() -> void:
	await _frames(5)
	var network: Node = root.get_node("Network")
	var settings: Node = root.get_node("Settings")
	settings.config_path = USER_SETTINGS_FILE
	settings.set_value("gameplay", "bandana_color", 2)  # the same colour the host wants: it asks for it, and is refused
	network.set_my_name("CLIENTPEER")
	var found := [0]
	await _until(func() -> bool:
		var file := FileAccess.open(PORT_FILE, FileAccess.READ)
		if file != null:
			found[0] = int(file.get_as_text().strip_edges())
			file.close()
		return found[0] != 0)
	if found[0] == 0:
		_check(false, "the host announced its port")
		return _finish()
	var joined := [false]
	network.connected.connect(func(success: bool, _reason: String) -> void: joined[0] = success)
	network.join_host("127.0.0.1", found[0])
	_check(await _until(func() -> bool: return joined[0]), "the client joined the host")
	var lobby: Control = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby)
	current_scene = lobby
	var my_id: int = network.multiplayer.get_unique_id()

	# --- the roster the host sent ---------------------------------------------------------------
	_check(await _until(func() -> bool: return network.player_bandanas.has(my_id) and network.player_bandanas.has(1)), "the roster brings both colours")
	var mine: int = network.player_bandanas.get(my_id, -1)
	_check(mine != 2 and network.player_bandanas.get(1) == 2,
		"the host's colour (2) was asked for first by the host, so this client (it asked for 2 too) wears %d" % mine)
	_check(lobby.get_node("Page/VBox/Scroll/Columns/Roster/VBox/PlayerListVBox").get_child_count() > 0, "the lobby draws the roster")
	# The picker: my own slot has 8 swatches, the host's colour locked.
	await _frames(2)
	var picker: Node = lobby.get_node("Page/VBox/Scroll/Columns/Roster/VBox/PlayerListVBox").find_child("BandanaPicker", true, false)
	_check(picker != null and picker.get_child_count() == 9, "my slot carries the picker (8 swatches and its caption)")
	if picker != null:
		var locked: Array[int] = []
		for swatch in picker.get_children():
			if swatch is BandanaSwatch and swatch.locked:
				locked.append(swatch.index)
		_check(locked == [2], "the colour the host holds is locked in my picker (%s)" % str(locked))
		var other: BandanaSwatch = picker.get_node("Color5")
		other.pressed.emit()  # click a free swatch
	_check(await _until(func() -> bool: return network.player_bandanas.get(my_id) == 5), "a free colour I click (5) comes back granted")
	_check(settings.get_value("gameplay", "bandana_color") == 5, "...and is saved as my pick for next time")

	# --- the host's colour is refused --------------------------------------------------------------
	_check(await _until(func() -> bool: return network.player_bandanas.get(1) == 6), "the host took 6")
	picker = lobby.get_node("Page/VBox/Scroll/Columns/Roster/VBox/PlayerListVBox").find_child("BandanaPicker", true, false)
	if picker != null:
		_check((picker.get_node("Color6") as BandanaSwatch).locked and (picker.get_node("Color6") as BandanaSwatch).disabled, "6 is now locked in my picker")
	network.choose_bandana_color(6)  # a click that raced the host's
	await _pause(1.5)
	_check(network.player_bandanas.get(my_id) == 5 and network.player_bandanas.get(1) == 6,
		"asking for the host's colour changes nothing: I keep 5 (%s)" % str(network.player_bandanas))
	network.choose_bandana_color(7)
	_check(await _until(func() -> bool: return network.player_bandanas.get(my_id) == 7), "7 is free, and granted")

	# --- START ---------------------------------------------------------------------------------------
	_check(await _until(func() -> bool: return _game() != null, 60.0), "the run starts on this screen")
	await _frames(5)
	network.rpc_id(1, "request_bandana_color", 0)
	await _pause(2.0)
	_check(network.player_bandanas.get(my_id) == 7 and network.player_bandanas.get(1) == 6,
		"a request after START changes nothing (%s)" % str(network.player_bandanas))
	_finish()


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_SETTINGS_FILE))
	print("networked bandanas (client): %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
