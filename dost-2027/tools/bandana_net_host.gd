extends SceneTree

# The HOST half of the networked bandana check (its partner is
# tools/bandana_net_client.gd). Two processes, one LAN run on 127.0.0.1:
#
#   godot --headless --path <project> -s res://tools/bandana_net_host.gd
#   godot --headless --path <project> -s res://tools/bandana_net_client.gd
#
# The joiner is given a free colour and both screens read the same roster; the
# client asks for a free colour (granted) and for the host's own (refused, it keeps
# what it had); the host asks for the client's colour (refused) and for a free one
# (granted); a colour a player has just left is free for the other; and once the host
# presses START a request changes nothing - the colours ride into the run unchanged.

const PORT := 24683
const PORT_FILE := "user://bandana_net_host.txt"
const SETTINGS_FILE := "user://lobby_settings_bandana_check.cfg"
const USER_SETTINGS_FILE := "user://settings_bandana_check.cfg"
const WAIT := 30.0

var _problems := 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


# Wait until `done` says yes, or `seconds` pass.
func _until(done: Callable, seconds := WAIT) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return done.call()


func _pause(seconds: float) -> void:
	await _until(func() -> bool: return false, seconds)


func _run() -> void:
	await _frames(5)
	var network: Node = root.get_node("Network")
	root.get_node("Settings").config_path = USER_SETTINGS_FILE  # never the player's own file
	root.get_node("Settings").set_value("gameplay", "bandana_color", 2)
	network.set_my_name("HOSTPEER")
	network.lobby_settings_path = SETTINGS_FILE
	network.start_host(PORT)
	var file := FileAccess.open(PORT_FILE, FileAccess.WRITE)
	file.store_string(str(int(network._current_port)))
	file.close()
	_check(network.player_bandanas.get(1) == 2, "the host starts on the colour it last picked (2)")
	if not await _until(func() -> bool: return network.players.size() >= 2):
		_check(false, "the client joined")
		return _finish()
	var client_id := 0
	for id in network.players.keys():
		if int(id) != 1:
			client_id = int(id)

	# --- a joiner starts on a free colour, and says which one it last picked -------------------
	await _pause(1.0)
	var first: int = network.player_bandanas.get(client_id, -1)
	_check(first >= 0 and first != network.player_bandanas.get(1), "the joiner got a colour of its own (%d, the host has %d)" % [first, network.player_bandanas.get(1, -1)])
	_check(network.player_data[client_id].bandana_index == first, "...recorded with its player data")

	# --- the client takes a free colour ------------------------------------------------------------
	_check(await _until(func() -> bool: return network.player_bandanas.get(client_id) == 5), "the client's pick (5) is granted")
	_check(network.player_data[client_id].bandana_index == 5, "...and recorded with its player data")

	# --- the host asks for the colour the client holds: refused ---------------------------------
	network.choose_bandana_color(5)
	await _pause(1.0)
	_check(network.player_bandanas.get(1) == 2 and network.player_bandanas.get(client_id) == 5,
		"the host cannot take the client's colour: both keep theirs (%s)" % str(network.player_bandanas))

	# --- the host takes a free one -----------------------------------------------------------------
	network.choose_bandana_color(6)
	_check(network.player_bandanas.get(1) == 6, "the host's pick (6) is granted")
	_check(await _until(func() -> bool: return network.player_bandanas.get(client_id) == 7), "the client was refused 6 (the host's now) and took 7 instead")
	_check(network.player_bandanas.get(1) == 6, "...the host still wears 6")
	_check(network.player_bandanas.get(client_id) == 7 and network.player_bandanas.values().size() == 2, "two players, two colours (%s)" % str(network.player_bandanas))

	# --- START locks the colours -------------------------------------------------------------------
	var lobby: Control = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await _frames(3)
	network.start_game()
	# The client asks for colour 0 somewhere in the next seconds (and then leaves): watch
	# the roster the whole time, every frame it is still here.
	var watched := 0
	var moved := false
	var deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < deadline and watched < 240:
		if network.player_bandanas.has(client_id):
			watched += 1
			moved = moved or network.player_bandanas[client_id] != 7 or network.player_bandanas.get(1) != 6
		await process_frame
	_check(watched > 0 and not moved, "once the run has started a request changes nothing (%d frames watched)" % watched)
	network.choose_bandana_color(1)
	await _pause(0.5)
	_check(network.player_bandanas.get(1) == 6, "...the host's own request is refused too")
	await _pause(2.0)
	_finish()


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PORT_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_SETTINGS_FILE))
	print("networked bandanas (host): %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
