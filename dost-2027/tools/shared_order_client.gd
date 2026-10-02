extends SceneTree

# The CLIENT half of the shared-order check (its partner is
# tools/shared_order_host.gd) - the players must always enter the same god, in
# the same order, on every screen:
#
#   1. a client that has no plan asks the host for it (request_trial_order)
#   2. the run starts with the plan thrown away before the shell loads - the
#      shape of a lost sync - so the shell has to ask again instead of drawing
#      a run of its own
#   3. it then opens the run on the host's first god

const PORT_FILE := "user://shared_order_host.txt"
const RESULT_FILE := "user://shared_order_client_result.txt"
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
	network.set_my_name("CLIENTPEER")
	var old := FileAccess.open(RESULT_FILE, FileAccess.WRITE)
	if old != null:
		old.close()

	var port := await _wait_for_port()
	if port == 0:
		printerr("shared_order_client: the host never announced its port")
		return _finish()

	var handshake := [false, false]
	network.connected.connect(func(success: bool, _reason: String) -> void:
		handshake[0] = true
		handshake[1] = success)
	network.join_host("127.0.0.1", port)
	var guard := 0
	while not handshake[0] and guard < WAIT_FRAMES:
		await process_frame
		guard += 1
	_check(handshake[1], "the client joined the host")
	if not handshake[1]:
		return _finish()

	# Join first, lobby second: the lobby reads multiplayer.is_server() to know
	# whose button to show, and that is only true once the peer is in place.
	var lobby: Control = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await _frames(3)
	_check(not network.is_game_host(), "the joined peer is a client, not a host")

	# 1) No plan? Ask for it - never draw one.
	network.rpc_id(1, "request_trial_order")
	guard = 0
	while network.trial_order_ids.is_empty() and guard < WAIT_FRAMES:
		await process_frame
		guard += 1
	_check(network.trial_order_ids == [&"tala", &"bathala"], "the host answers a request with the plan it will play")
	_say("CLIENT: after request ids=%s custom=%s" % [str(network.trial_order_ids), str(network.trial_order_custom)])

	# 2) Throw that plan away the moment the run announces it, so the shell that
	#    loads next starts blind - exactly like a client whose sync was lost.
	#    The reply to its own request arrives once the shell is up, and is kept.
	var drop := func(_ids: Array) -> void:
		if current_scene == null or current_scene.name != "Game":
			_say("CLIENT: drop the plan (scene=%s)" % (str(current_scene.name) if current_scene != null else "none"))
			network.trial_order_ids.clear()
		else:
			_say("CLIENT: keep the plan (scene=%s)" % str(current_scene.name))
	network.trial_order_changed.connect(drop)

	guard = 0
	var seen := str(network.trial_order_ids)
	while not _in_run() and guard < WAIT_FRAMES:
		await process_frame
		guard += 1
		if str(network.trial_order_ids) != seen:
			seen = str(network.trial_order_ids)
			_say("CLIENT: ids changed at frame %d -> %s (scene=%s)" % [
				guard, seen, str(current_scene.name) if current_scene != null else "none"])
	await _frames(10)
	_say("CLIENT: ids when the run opened = %s" % str(network.trial_order_ids))

	_check(_in_run(), "the client lands in the run")
	if _in_run():
		var ids: Array = _ids(current_scene.trial_order)
		_say("CLIENT ORDER: %s" % ", ".join(ids))
		_check(ids == ["tala", "bathala"], "the blind client still enters the host's order")
		_check(_god_of(current_scene) == "tala", "the client opens on the host's first god")
	_finish()


func _in_run() -> bool:
	var scene := current_scene
	return scene != null and scene.name == "Game" and not scene.trial_order.is_empty()


# The port the host wrote down (0 when it never did).
func _wait_for_port() -> int:
	var guard := 0
	while guard < WAIT_FRAMES:
		var file := FileAccess.open(PORT_FILE, FileAccess.READ)
		if file != null:
			var port := int(file.get_as_text().strip_edges())
			file.close()
			return port
		await process_frame
		guard += 1
	return 0


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
	_say("shared order (client): %d problem(s)" % _problems)
	_say("--- DONE ---")
	quit(1 if _problems > 0 else 0)