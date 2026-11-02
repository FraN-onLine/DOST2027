extends SceneTree

# The CLIENT half of the networked opening check (its partner, and how to run the
# two, is in tools/opening_net_host.gd). This screen joins, the host skips the
# opening before this scene has loaded it - the cutscene must still end (the host
# keeps saying so until every screen has left it). The first trial's intro is then
# left unread until the host has already released it; the late report gets that
# release again, so this screen follows into the round instead of waiting at a
# barrier everybody else walked past - and the late release must not drag it back
# to the 3 - 2 - 1.

const PORT_FILE := "user://opening_net_host.txt"
const DONE_FILE := "user://opening_net_client_done.txt"
const WAIT := 90.0
const INTRO_TOKEN := "trial_1_intro"

var _problems := 0
var _released_playing := false
var _phase_at_release := -1


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _pause(seconds: float) -> void:
	await _until(func() -> bool: return false, seconds)


# Wait until `done` says yes, or `seconds` pass, reading the opening's dialogue.
# The trial's intro is deliberately NOT read here.
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
	if cutscene == null or not is_instance_valid(cutscene):
		return
	var dialogue = cutscene.get("dialogue")
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
	var network: Node = root.get_node("Network")
	network.set_my_name("CLIENTPEER")
	var found := [0]  # a lambda captures locals by value: it writes through this
	await _until(func() -> bool:
		var file := FileAccess.open(PORT_FILE, FileAccess.READ)
		if file != null:
			found[0] = int(file.get_as_text().strip_edges())
			file.close()
		return found[0] != 0)
	var port: int = found[0]
	if port == 0:
		_check(false, "the host announced its port")
		return _finish()
	network.join_host("127.0.0.1", port)
	if not await _until(func() -> bool: return network.players.size() >= 2, 30.0):
		_check(false, "the client joined the lobby")
		return _finish()

	if not await _until(func() -> bool: return _game() != null):
		_check(false, "the host started the run")
		return _finish()
	var game := _game()
	if not await _until(func() -> bool: return game.get("_cutscene") != null, 30.0):
		_check(false, "the client's opening started")
		return _finish()
	var cutscene = game.get("_cutscene")
	_check(true, "the client played the opening too")
	_check(not bool(cutscene.can_skip), "a client cannot skip")

	# The skip was sent before this scene existed. The host says it again while it
	# waits for everyone to leave, so the cutscene still ends here.
	var started := Time.get_ticks_msec()
	if not await _until(func() -> bool:
		var now = game.get("_cutscene")
		return now == null or not is_instance_valid(now)):
		_check(false, "the opening ended on the client")
		return _finish()
	var took := (Time.get_ticks_msec() - started) / 1000.0
	print("client left the opening %.1fs after it appeared (skip had been sent before it)" % took)
	_check(took < 20.0, "the missed skip was repeated, not waited out (%.1fs)" % took)

	if not await _until(func() -> bool: return game.arena != null and is_instance_valid(game.arena)):
		_check(false, "the client opened the first trial")
		return _finish()
	var arena = game.arena
	network.dialogue_released.connect(func(token: String) -> void:
		if token == INTRO_TOKEN and int(arena.get("_phase")) == Arena.Phase.PLAYING:
			_released_playing = true
			_phase_at_release = int(arena.get("_phase")))

	# Do not read the intro: wait for the host's round, which closes it for us.
	if not await _until(func() -> bool: return int(arena.get("_phase")) == Arena.Phase.PLAYING):
		_check(false, "the client followed the host into the round")
		return _finish()
	_check(not bool(arena.dialogue.is_active()), "the host's round closed the unread intro")

	# This screen settles its intro only now: it reports the barrier the host has
	# already released, and the host answers this screen alone.
	arena._wait_for_dialogue("intro")
	if not await _until(func() -> bool: return _released_playing, 20.0):
		_check(false, "the late intro report was released")
	else:
		_check(true, "the late intro report was released")
	_check(_phase_at_release == int(Arena.Phase.PLAYING),
		"the late release did not pull the client back to the countdown (phase at release: %d)" % _phase_at_release)
	_check(int(arena.get("_phase")) == Arena.Phase.PLAYING, "the late release left the round playing")
	var player = arena.get("player")
	_check(player != null and not bool(player.locked), "the client's mortal is free to walk")

	# Everyone reads the same clock: the client mirrors the host's running round.
	var before: float = arena.get("_trial_time")
	await _pause(1.0)
	_check(float(arena.get("_trial_time")) < before - 0.5,
		"the client's clock follows the host (%.1f -> %.1f)" % [before, float(arena.get("_trial_time"))])
	_finish()


func _finish() -> void:
	# The host holds the round open until this file says the client's checks are done.
	var file := FileAccess.open(DONE_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string("done")
		file.close()
	print("networked opening (client): %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
