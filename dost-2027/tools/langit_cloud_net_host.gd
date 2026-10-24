extends SceneTree

# The HOST half of the networked check of Langit Lupa's 5 s Langit (its partner is
# tools/langit_cloud_net_client.gd). Two processes on 127.0.0.1:
#
#   godot --headless --path <project> -s res://tools/langit_cloud_net_host.gd
#   godot --headless --path <project> -s res://tools/langit_cloud_net_client.gd
#
# The host's mortal steps onto a Langit: its cloud_life countdown starts and both
# screens show the same timer; stepping off crumbles nothing; at 0 the Langit
# crumbles on both screens together and a new one forms in its slot.

const PORT := 24691
const PORT_FILE := "user://langit_cloud_net_host.txt"
const SETTINGS_FILE := "user://lobby_settings_langit_cloud_check.cfg"
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
	root.get_node("Settings").config_path = "user://settings_langit_cloud_check.cfg"
	network.set_my_name("HOSTPEER")
	network.lobby_settings_path = SETTINGS_FILE
	network.start_host(PORT)
	network.set_run_settings({"trials": 3, "order_mode": "custom", "custom_order": ["mapulon_ikapati", "mayari", "tala"], "trial_time": 90.0, "opening_cutscene": "skip"})
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
	await _frames(30)
	var lobby: Control = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await _frames(3)
	network.start_game()
	_check(await _until(func() -> bool: return _game() != null and _game().arena is LangitLupaArena), "the host opens Langit Lupa")
	var arena: LangitLupaArena = _game().arena
	_check(await _until(func() -> bool: return arena._phase == Arena.Phase.PLAYING), "the trial is under way on the host")
	arena._tagback = 999.0
	arena._season_timer = 1000.0  # no season turns during the check
	arena.cloud_life = 3.0  # (shorter, so the check does not wait 5 s twice; the default is asserted below)
	var authored: Node = load("res://scenes/gods/mapulon_ikapati/LangitLupaArena.tscn").instantiate()
	_check(is_equal_approx(authored.cloud_life, 5.0), "the scene's cloud_life is 5 s")
	authored.free()
	await _until(func() -> bool: return false, 2.0)  # the client gets its first ticks
	# --- the host's mortal steps onto Langit 0, then off --------------------------------------------
	var ids: Array[int] = arena._cloud_id.duplicate()
	arena.player.global_position = arena._langits[0]
	_check(await _until(func() -> bool: return arena._cloud_burn.size() > 0 and arena._cloud_burn[0] >= 0.0, 3.0), "the first step starts the countdown (%.2f)" % arena._cloud_burn[0])
	_check(arena._cloud_burn.size() > 1 and arena._cloud_burn[1] < 0.0, "...only on that Langit")
	await _until(func() -> bool: return false, 1.0)
	arena.player.global_position = arena._field.get_center() + Vector2(0, 200)  # off, onto the Lupa
	await _until(func() -> bool: return false, 0.5)
	_check(arena._cloud_state[0] == LangitLupaArena.Cloud.SOLID and arena._cloud_burn[0] < 3.0, "stepping off crumbles nothing (%.2f left)" % arena._cloud_burn[0])
	_check(await _until(func() -> bool: return arena._cloud_state[0] == LangitLupaArena.Cloud.CRUMBLING, 4.0), "the Langit crumbles when the countdown ends")
	_check(await _until(func() -> bool: return arena._cloud_id[0] != ids[0], 3.0), "...and a new one forms in its slot")
	await _until(func() -> bool: return false, 1.0)  # the client sees the new one
	_finish()


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PORT_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_langit_cloud_check.cfg"))
	print("5 s Langit, networked (host): %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
