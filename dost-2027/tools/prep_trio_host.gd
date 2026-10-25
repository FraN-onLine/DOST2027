extends SceneTree

# The HOST of the 3-player rest check (its partner, run twice, is
# tools/prep_trio_client.gd - once with `-- shop`, once with `-- walk`):
#
#   godot --headless --path <project> -s res://tools/prep_trio_host.gd
#   godot --headless --path <project> -s res://tools/prep_trio_client.gd -- shop
#   godot --headless --path <project> -s res://tools/prep_trio_client.gd -- walk
#
# Three mortals play Tala's trial into the rest. While the rest opens the host
# replays late RESULTS ticks from the trial (the reordering a real LAN does), and
# nobody presses READY - one client stands in the Tindahan with it open - so the
# rest ends on its clock, and all three open Mayari's trial.

const PORT := 24694
const PORT_FILE := "user://prep_trio_host.txt"
const SETTINGS_FILE := "user://lobby_settings_prep_trio.cfg"
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
		_pump()
		await process_frame
	return done.call()


func _pump() -> void:
	var game := _game()
	if game != null and game.arena != null and is_instance_valid(game.arena):
		var dialogue = game.arena.get("dialogue")
		if dialogue != null and dialogue.is_active():
			dialogue.advance()


func _game() -> Node:
	return current_scene if current_scene != null and current_scene.name == "Game" else null


func _run() -> void:
	await _frames(5)
	var network: Node = root.get_node("Network")
	network.set_my_name("HOSTPEER")
	network.lobby_settings_path = SETTINGS_FILE
	network.start_host(PORT)
	network.set_run_settings({"trials": 3, "order_mode": "custom", "custom_order": ["tala", "mayari", "hanan"],
		"trial_time": 60.0, "prep_time": 10.0, "opening_cutscene": "skip"})
	var file := FileAccess.open(PORT_FILE, FileAccess.WRITE)
	file.store_string(str(int(network._current_port)))
	file.close()
	if not await _until(func() -> bool: return network.players.size() >= 3, 60.0):
		_check(false, "both clients joined (%d players)" % network.players.size())
		return _finish()
	await _frames(30)
	var lobby: Control = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await _frames(3)
	network.start_game()
	_check(await _until(func() -> bool: return _game() != null and _game().arena != null and _game().arena.god_id == &"tala"), "three mortals open the run on Tala")
	_check(await _until(func() -> bool: return _game().arena._phase == Arena.Phase.PLAYING), "the trial starts")
	await _frames(20)
	_game().arena._trial_time = 0.05
	_check(await _until(func() -> bool: return _game().arena is PrepArea), "the trial's end opens the rest")
	var prep: PrepArea = _game().arena
	# The trial's late RESULTS ticks, landing on the clients' rests (a LAN reorders).
	for beat in range(6):
		network.rpc("rpc_arena_state", {"scene": "trial_1:tala", "phase": int(Arena.Phase.RESULTS), "trial_time": 0.0, "mortals": {}})
		await _until(func() -> bool: return false, 0.3)
	var readied := [false]
	var timed_out := [false]
	prep.prep_closed.connect(func() -> void:  # (it is freed in the frame it closes)
		readied[0] = not prep._ready_ids.is_empty()
		timed_out[0] = prep._time_left <= 0.0)
	_check(await _until(func() -> bool:
		return _game().arena != null and not (_game().arena is PrepArea) and _game().arena.god_id == &"mayari", 25.0),
		"with nobody READY the rest ends on its clock and the host opens Mayari's trial")
	_check(not readied[0] and timed_out[0], "...nobody was ready, the clock ran out (ready %s, out of time %s)" % [str(readied[0]), str(timed_out[0])])
	await _until(func() -> bool: return false, 8.0)  # the clients check they followed
	_finish()


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PORT_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	print("3-player rest (host): %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
