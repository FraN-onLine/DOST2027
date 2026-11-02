extends SceneTree

# The HOST half of the networked opening check (its partner is
# tools/opening_net_client.gd). Two processes, one LAN run on 127.0.0.1:
#
#   godot --headless --path <project> -s res://tools/opening_net_host.gd
#   godot --headless --path <project> -s res://tools/opening_net_client.gd
#
# The host presses START with the full opening and skips it at once - before the
# client can possibly have loaded the cutscene - and the opening still ends on
# both screens: the host stays at the cutscene's last barrier until the client
# reports it done, so the "other player" is never left behind in the opening.
# The first trial's intro is then released before the client has read it (what the
# trial's 20 s timeout does to a slow screen); the client reads it late and is
# handed that release again instead of waiting forever, and both screens walk
# into the same live round.

const PORT := 24685
const PORT_FILE := "user://opening_net_host.txt"
const DONE_FILE := "user://opening_net_client_done.txt"
const SETTINGS_FILE := "user://lobby_settings_opening_check.cfg"
const USER_SETTINGS_FILE := "user://settings_opening_check.cfg"
const WAIT := 90.0
const INTRO_TOKEN := "trial_1_intro"

var _problems := 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _pause(seconds: float) -> void:
	await _until(func() -> bool: return false, seconds)


# Wait until `done` says yes, or `seconds` pass, reading the dialogue on the way
# (the opening's and, later, the first trial's).
func _until(done: Callable, seconds := WAIT) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		_pump()
		await process_frame
	return done.call()


func _pump() -> void:
	var game := _game()
	if game == null:
		return
	var cutscene = game.get("_cutscene")
	var dialogue = null
	if cutscene != null and is_instance_valid(cutscene):
		dialogue = cutscene.get("dialogue")
	elif game.arena != null and is_instance_valid(game.arena):
		dialogue = game.arena.get("dialogue")
	if dialogue != null and dialogue.is_active():
		dialogue.advance()


func _game() -> Node:
	return current_scene if current_scene != null and current_scene.name == "Game" else null


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _run() -> void:
	await _frames(5)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DONE_FILE))  # never a stale one
	var settings: Node = root.get_node("Settings")
	settings.config_path = USER_SETTINGS_FILE  # never the player's own file
	var network: Node = root.get_node("Network")
	network.set_my_name("HOSTPEER")
	network.lobby_settings_path = SETTINGS_FILE
	network.start_host(PORT)
	network.set_run_settings({"trials": 2, "order_mode": "custom", "custom_order": ["mayari", "tala"],
		"trial_time": 60.0, "due_step": 1000, "prep_time": 20.0, "opening_cutscene": "full"})
	var file := FileAccess.open(PORT_FILE, FileAccess.WRITE)
	file.store_string(str(int(network._current_port)))
	file.close()
	if not await _until(func() -> bool: return network.players.size() >= 2):
		_check(false, "the client joined")
		return _finish()
	var client_id := 0
	for id in network.players.keys():
		if int(id) != 1:
			client_id = int(id)

	# A lobby, as the real flow: START hands out the order, the settings and the scene.
	var lobby: Control = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await _frames(3)
	network.start_game()
	if not await _until(func() -> bool: return _game() != null, 30.0):
		_check(false, "the game shell loaded")
		return _finish()
	var game := _game()
	if not await _until(func() -> bool: return game.get("_cutscene") != null, 30.0):
		_check(false, "the host's opening started")
		return _finish()

	# The host skips at once. The client has only just been told to change scene, so
	# its cutscene is born without the skip - the case that used to strand it.
	var started := Time.get_ticks_msec()
	var cutscene = game.get("_cutscene")
	_check(bool(cutscene.can_skip), "the host may skip the opening")
	cutscene.skip()
	if not await _until(func() -> bool: return game.get("_cutscene") == null and game.arena != null):
		_check(false, "the opening ended and the first trial opened")
		return _finish()
	var took := (Time.get_ticks_msec() - started) / 1000.0
	print("opening skipped before the client had it; both screens out in %.1fs" % took)
	_check(took < 20.0, "the skipped opening did not leave the host hanging (%.1fs)" % took)

	var arena = game.arena
	_check(str(arena.god_id) == "mayari", "the first trial is the order's first god")
	# Let the client's arena land, then read the host's own intro as a player would.
	if not await _until(func() -> bool: return bool(arena.get("_dialogue_waiting")), 30.0):
		_check(false, "the host's intro reached its handshake")
		return _finish()
	# The client has NOT read its intro yet (its half holds it until the round
	# begins). Release it now, the way the trial's own timeout would.
	arena._release_dialogue()
	_check(network._dialogue_released.has(INTRO_TOKEN), "the intro's release is remembered for a late screen")

	if not await _until(func() -> bool: return int(arena.get("_phase")) == Arena.Phase.PLAYING):
		_check(false, "the host's round began")
		return _finish()
	if not await _until(func() -> bool: return network.mortal_positions.has(client_id)):
		_check(false, "the client is in the round and reporting its mortal")
	else:
		_check(true, "the client is in the round and reporting its mortal")
	_check(int(arena.get("_phase")) == Arena.Phase.PLAYING, "the host's round is playing, not stuck in the opening")
	await _pause(1.0)
	_check(int(arena.get("_phase")) == Arena.Phase.PLAYING, "the round was not pulled back to the countdown")
	# Stay in the round until the client's half is done: its late-report and clock
	# checks need the host still connected and still ticking.
	if not await _until(func() -> bool:
		return FileAccess.file_exists(DONE_FILE), 30.0):
		_check(false, "the client finished its checks")
	_finish()


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PORT_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DONE_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(USER_SETTINGS_FILE))
	print("networked opening (host): %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
