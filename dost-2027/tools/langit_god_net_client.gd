extends SceneTree

# The CLIENT half of the networked check of the gods as Taya in Langit Lupa (its
# partner, and how to run the two, is in tools/langit_god_net_host.gd). It follows
# the host into the trial and checks what its own screen draws: the banner, the
# god body (mortal sprite hidden, Ikapati looping, where the host says), the
# marker above it, the one Ikapati, the chant words, the fade and the hand-over.

const PORT_FILE := "user://langit_god_net_host.txt"
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
	root.get_node("Settings").config_path = "user://settings_langit_god_check_client.cfg"
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

	_check(await _until(func() -> bool: return _game() != null and _game().arena is LangitLupaArena, 60.0), "the client follows the host into Langit Lupa")
	var arena: LangitLupaArena = _game().arena
	arena.god_leave_time = 2.0  # the host's fade is 2 s here too
	_check(await _until(func() -> bool: return arena._phase == Arena.Phase.PLAYING), "the trial is under way on the client")

	# --- GO: the gods are the Taya on this screen too -----------------------------------------------
	_check(await _until(func() -> bool: return arena._taya == LangitLupaArena.GOD_TAYA), "the client learns the gods are the Taya")
	_check(await _until(func() -> bool: return arena.hud.banner_label.text == "MAPULON & IKAPATI ARE TAYA!", 5.0),
		"the client's banner says MAPULON & IKAPATI ARE TAYA! (%s)" % arena.hud.banner_label.text)
	var body := arena._god_body
	_check(await _until(func() -> bool: return body.visible), "the god body appears on the client")
	_check(not body.sprite.visible and not arena.god_overseer.visible, "...without the mortal sprite, and the overseer Ikapati is hidden here too")
	var art := arena._god_art as AnimatedSprite2D
	_check(art != null and art.is_playing(), "...with Ikapati looping")
	await _until(func() -> bool: return arena._god_at != Vector2.INF and body.global_position.distance_to(arena._god_at) < 40.0)
	_check(body.global_position.distance_to(arena._god_at) < 40.0, "the body stands where the host's tick says (%.0f px off)" % body.global_position.distance_to(arena._god_at))
	await _frames(3)
	_check(arena.taya_marker.visible and absf(arena.taya_marker.global_position.x - body.global_position.x) < 1.0
		and arena.taya_marker.global_position.y < body.global_position.y - arena._god_lift + 1.0, "the Taya marker is over the god body")

	# --- the chant: the words light up over the gods' heads -----------------------------------------
	_check(await _until(func() -> bool: return arena._chanting and arena._chant_step >= 2, 20.0), "the client sees the gods chant (step %d)" % arena._chant_step)
	await _frames(3)
	_check(arena.chant_row.visible and arena.chant_row.global_position.y < body.global_position.y - 90.0
		and absf(arena.chant_row.global_position.x - body.global_position.x) < 2.0, "the chant words are drawn over the god body")
	var word := arena.chant_row.get_child(0).get_node("Word") as Label
	_check(word.text == "LANGIT" and word.get_theme_color("font_color") == UITokens.GOLD, "...the first one lit (%s)" % word.text)

	# --- the tag: the fade, the line, the hand-over -----------------------------------------------
	_check(await _until(func() -> bool: return arena._god_leave > 0.0, 20.0), "the client sees the gods start to fade")
	await _frames(4)
	_check(body.visible and body.modulate.a < 1.0 and body.floating_text.visible and body.floating_text.text == arena.god_tag_line,
		"...the body half-faded with their line over it (alpha %.2f)" % body.modulate.a)
	_check(arena._taya == network.multiplayer.get_unique_id(), "the client is the Taya now")
	_check(await _until(func() -> bool: return arena.hud.banner_label.text == "YOU ARE TAYA", 3.0), "...and its banner says so (%s)" % arena.hud.banner_label.text)
	_check(await _until(func() -> bool: return arena._god_at == Vector2.INF and not body.visible, 6.0), "the gods leave the client's field")
	_check(arena.god_overseer.visible, "...and the overseer Ikapati is back")
	_finish()


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_langit_god_check_client.cfg"))
	print("gods as Taya, networked (client): %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
