extends SceneTree

# The HOST half of the networked check of the gods as Taya in Langit Lupa (its
# partner is tools/langit_god_net_client.gd). Two processes on 127.0.0.1:
#
#   godot --headless --path <project> -s res://tools/langit_god_net_host.gd
#   godot --headless --path <project> -s res://tools/langit_god_net_client.gd
#
# At GO the gods are the Taya on both screens (banner, body, marker, no second
# Ikapati), the host's chant shows on the client over the gods' heads, and when
# the gods tag the client the fade-out and the hand-over reach it too.

const PORT := 24690
const PORT_FILE := "user://langit_god_net_host.txt"
const SETTINGS_FILE := "user://lobby_settings_langit_god_check.cfg"
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
	root.get_node("Settings").config_path = "user://settings_langit_god_check.cfg"
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
	arena.god_leave_time = 2.0  # a long fade, so the client has time to be seen watching it
	_check(await _until(func() -> bool: return arena._phase == Arena.Phase.PLAYING), "the trial is under way on the host")
	arena._tagback = 999.0  # nobody is tagged until this check says so
	_check(arena._taya == LangitLupaArena.GOD_TAYA, "at GO the gods are the Taya")
	_check(await _until(func() -> bool: return arena.hud.banner_label.text == "MAPULON & IKAPATI ARE TAYA!", 5.0),
		"the banner says MAPULON & IKAPATI ARE TAYA! (%s)" % arena.hud.banner_label.text)
	await _until(func() -> bool: return arena._god_body.visible)
	_check(arena._god_body.visible and not arena._god_body.sprite.visible and not arena.god_overseer.visible,
		"the god body is drawn without the mortal sprite, and the overseer Ikapati is hidden")

	# --- the gods chant: the client sees the words over their heads ------------------------------
	await _until(func() -> bool: return false, 3.0)  # the client checks the body first
	arena._chant_cd = 0.0
	arena._bot_chant.clear()
	arena._on_chant_message(LangitLupaArena.GOD_TAYA, "start", 0)
	arena._on_chant_message(LangitLupaArena.GOD_TAYA, "step", 1)
	arena._on_chant_message(LangitLupaArena.GOD_TAYA, "step", 2)
	_check(arena._chanting and arena._chant_step == 2, "the host has the gods mid-chant (step %d)" % arena._chant_step)
	await _until(func() -> bool: return false, 3.0)

	# --- the tag: the client is the Taya, the gods fade and leave --------------------------------
	arena._break_chant()
	arena._tagback = 0.0
	arena._tag(client_id)
	_check(arena._taya == client_id and arena._god_leave > 0.0, "the gods tag the client and start to fade")
	await _until(func() -> bool: return false, 4.0)  # the client watches the fade and the hand-over
	_check(arena._god_at == Vector2.INF and not arena._god_body.visible and arena.god_overseer.visible,
		"the gods are gone from the host's field and the overseer is back")
	_finish()


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PORT_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_langit_god_check.cfg"))
	print("gods as Taya, networked (host): %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
