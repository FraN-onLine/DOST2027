extends SceneTree

# The CLIENT half of the networked skill check (its partner, and how to run the two, is
# in tools/cast_net_host.gd). It follows the host into Mayari's trial, sees the card of the
# skill the host gave it pop up (read off a snapshot, not announced by anything local),
# sees the host's cast over the host's ghost, then casts its own skill.

const PORT_FILE := "user://cast_net_host.txt"
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
	root.get_node("Settings").config_path = "user://settings_cast_check_client.cfg"
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

	_check(await _until(func() -> bool: return _game() != null and _game().arena != null and _game().arena.god_id == &"mayari", 60.0),
		"the client follows the host into Mayari's trial")
	var arena: Arena = _game().arena
	_check(await _until(func() -> bool: return arena._phase == Arena.Phase.PLAYING), "the trial is under way on the client")
	var e_skill := Gods.favor_by_id(&"half_vision")

	# --- the card: the host's snapshot brought the skill ---------------------------------------------
	_check(await _until(func() -> bool: return arena.hud._popup != null and arena.hud._popup.favor == e_skill),
		"the skill the host gave this client pops up its card (read off the snapshot)")
	if arena.hud._popup != null:
		_check(arena.hud._popup.name_label.text == e_skill.display_name.to_upper() and arena.hud._popup.key_label.text == UITokens.key_text(&"skill_e"),
			"...with its name and the key it is on")
	var held_at_start := arena.rules.local().favors.size()
	_check(held_at_start >= 1, "the client holds it")

	# --- the host's cast, over the host's ghost -------------------------------------------------------
	var q_skill := Gods.favor_by_id(&"siblings_compromise")
	await _until(func() -> bool: return arena._ghosts.has(1) and is_instance_valid(arena._ghosts[1]))
	var host_ghost: ArenaMortal = arena._ghosts[1]
	_check(await _until(func() -> bool: return host_ghost.floating_text.visible and host_ghost.floating_text.text == q_skill.display_name.to_upper()),
		"the host's cast shows over the host's ghost on this screen (%s)" % host_ghost.floating_text.text)

	# --- the client casts ------------------------------------------------------------------------------
	arena._use_skill(GodFavor.Slot.E)
	_check(await _until(func() -> bool: return arena.player.floating_text.visible and arena.player.floating_text.text == e_skill.display_name.to_upper()),
		"the client's own cast shows over its mortal, sent back by the host (%s)" % arena.player.floating_text.text)
	await _until(func() -> bool: return false, 2.0)
	_finish()


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_cast_check_client.cfg"))
	print("networked casts (client): %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
