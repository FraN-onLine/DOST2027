extends SceneTree

# The HOST half of the networked check of the gods as Taya in Langit Lupa (its
# partner is tools/langit_god_net_client.gd). Two processes on 127.0.0.1:
#
#   godot --headless --path <project> -s res://tools/langit_god_net_host.gd
#   godot --headless --path <project> -s res://tools/langit_god_net_client.gd
#
# At GO the gods are the Taya on both screens (banner, body, marker, no second
# Ikapati), the host's chant shows on the client over the gods' heads, and when
# the gods tag the client the fade-out and the hand-over reach it too. Then the
# blitz: the banner, Ikapati back as a second Taya (two markers) and a Langit
# crumbling and forming alone reach the client; her tag makes the host's mortal the
# one Taya and her a runner (her marker hides), and the host's mortal tagging her
# makes her the Taya again - both screens agree on her role and marker.

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
	_check(is_equal_approx(arena._field.size.x, 868.0) and is_equal_approx(arena._field.position.x, 262.0), "the host plays on the authored, full-width field (%s)" % str(arena._field))
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

	# --- the blitz: Ikapati comes back as a second Taya; one Langit crumbles alone -----------------
	arena._trial_time = arena.langit_blitz_time + 0.2
	_check(await _until(func() -> bool: return arena._blitz, 3.0), "the blitz starts on the host at %ds left" % int(arena.langit_blitz_time))
	_check(arena.second_taya() and arena._taya == client_id and arena._taya2 == LangitLupaArena.GOD_TAYA,
		"Ikapati is back as a second Taya beside the client")
	arena.set_mortal_invuln(1, 999.0)  # she cannot tag the host's mortal until the check below says so
	await _until(func() -> bool: return false, 2.0)  # the client checks the banner and the two markers
	for attempt in range(6):
		if arena._cloud_state[0] == LangitLupaArena.Cloud.SOLID and arena._cloud_timer[0] <= 0.0:
			arena._crumble(0)
		await _until(func() -> bool: return false, 1.0)
	_check(arena._blitz and arena.second_taya(), "...and she is still hunting at the end")
	await _until(func() -> bool: return false, 2.0)

	# --- Ikapati's tag passes her slot: the host's mortal takes it, the client stays the first Taya --
	arena._reset_god_chant()
	arena._invuln.clear()
	arena.player.set_lock(false)
	arena.player.global_position = arena._god_at + Vector2(0, 14)
	await _until(func() -> bool: return arena._taya2 == 1, 3.0)  # she tags it on her next tick
	_check(arena._taya == client_id and arena._taya2 == 1, "Ikapati tags the host's mortal: it holds the second Taya slot, the client stays the first")
	_check(arena.is_mortal_invulnerable(LangitLupaArena.GOD_TAYA), "...Ikapati, the old slot holder, is a runner with tagged_mercy")
	_check(arena._god_runs and arena.second_taya() and arena._god_leave == 0.0 and arena._god_at != Vector2.INF, "...and she is a runner: still two Tayas")
	await _until(func() -> bool: return false, 4.0)  # the client draws both markers

	# --- the host's mortal (the second Taya) tags the running Ikapati: she takes her slot back ----
	arena._tagback2 = 0.0
	arena._invuln.clear()
	arena._god_at = arena._god_spot()
	arena.player.global_position = arena._god_at + Vector2(10, 0)
	arena._check_tag()
	_check(arena._taya == client_id and arena._taya2 == LangitLupaArena.GOD_TAYA and not arena._god_runs,
		"the second Taya tags her on the Lupa: Ikapati is the second Taya again, the client stays the first")
	arena.set_mortal_invuln(1, 999.0)  # nobody is tagged while the client looks
	arena.set_mortal_invuln(client_id, 999.0)
	await _until(func() -> bool: return false, 4.0)  # the client sees her back as the Taya
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
