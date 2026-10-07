extends SceneTree

# The HOST half of the shared-order check (its partner is
# tools/shared_order_client.gd). Two processes, one run:
#
#   godot --headless --path <project> -s res://tools/shared_order_host.gd
#   godot --headless --path <project> -s res://tools/shared_order_client.gd
#
# The lobby plans a CUSTOM order here, and both screens have to open the run on
# the exact same sequence of gods - the same first god included. The host writes
# the port it actually bound into user:// so the client knows where to knock.
# It then stays up long enough for the client's shell to ask for the plan.

const PORT := 24681
const PORT_FILE := "user://shared_order_host.txt"
const RESULT_FILE := "user://shared_order_host_result.txt"
const SETTINGS_FILE := "user://lobby_settings_shared_check.cfg"
const WAIT_FRAMES := 1800

var _problems := 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	# The autoload's MultiplayerAPI only exists once the tree has ticked.
	await _frames(5)
	var network: Node = root.get_node("Network")
	network.set_my_name("HOSTPEER")
	# The host remembers its setup on disk: keep the check's setup out of the
	# player's own user://lobby_settings.cfg.
	network.lobby_settings_path = SETTINGS_FILE
	network.start_host(PORT)
	# The lobby's plan, set BEFORE the client joins: a late joiner must still be
	# handed it. A CUSTOM order, so a private random draw on the client would be
	# impossible to mistake for it.
	network.set_run_settings({"trials": 3, "order_mode": "custom", "custom_order": ["tala", "mayari", "hanan"],
		"trial_time": 120.0, "due_step": 750})
	_say("HOST: setup after set = %s" % str(network.run_settings.to_dict()))
	var file := FileAccess.open(PORT_FILE, FileAccess.WRITE)
	if file == null:
		printerr("shared_order_host: cannot write %s" % PORT_FILE)
		return _finish()
	file.store_string(str(int(network._current_port)))
	file.close()
	var old := FileAccess.open(RESULT_FILE, FileAccess.WRITE)
	if old != null:
		old.close()
	_say("HOST: waiting for the client")

	var guard := 0
	while network.players.size() < 2 and guard < WAIT_FRAMES:
		await process_frame
		guard += 1
	_say("HOST: leave the wait (players=%d frames=%d)" % [network.players.size(), guard])
	if network.players.size() < 2:
		_say("FAIL: the client never joined")
		return _finish()
	_say("PASS: the client joined")

	# A beat before starting, so the client can ask for the plan first.
	await _frames(180)
	_say("HOST: setup at start = %s | ids = %s" % [str(network.run_settings.to_dict()), str(network.trial_order_ids)])

	var lobby: Control = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await _frames(3)

	network.start_game()

	guard = 0
	while not _in_run() and guard < WAIT_FRAMES:
		await process_frame
		guard += 1
	# Stay up: the client's shell lost the plan it was told and asks again.
	await _frames(300)

	_check(_in_run(), "the host lands in the run")
	if _in_run():
		var ids: Array = _ids(current_scene.trial_order)
		_say("HOST ORDER: %s" % ", ".join(ids))
		_check(ids == ["tala", "mayari", "hanan", "bathala"], "the host plays the order it planned")
		_check(_god_of(current_scene) == "tala", "the host opens on its first god")
	_check(network.trial_order_ids == [&"tala", &"mayari", &"hanan", &"bathala"], "the host still holds the plan the client asked for")
	_finish()


func _in_run() -> bool:
	var scene := current_scene
	return scene != null and scene.name == "Game" and not scene.trial_order.is_empty()


# The ids of a run's order, as plain strings ("tala", "bathala", ...).
func _ids(order) -> Array:
	var ids := []
	for god in order:
		ids.append(str(god.id))
	return ids


func _god_of(game) -> String:
	if game.arena == null:
		return ""
	return str(game.arena.god_id)


func _check(condition: bool, label: String) -> void:
	_say("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


# The tools' own log, written as it goes: a redirected stdout can lose the tail
# of a run that is cut short.
func _say(line: String) -> void:
	print(line)
	var file := FileAccess.open(RESULT_FILE, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(RESULT_FILE, FileAccess.WRITE)
	if file != null:
		file.seek_end()
		file.store_line(line)
		file.close()


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PORT_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	_say("shared order (host): %d problem(s)" % _problems)
	_say("--- DONE ---")
	quit(1 if _problems > 0 else 0)