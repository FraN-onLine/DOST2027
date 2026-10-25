extends SceneTree

# The HOST half of the networked skill check (its partner is tools/cast_net_client.gd).
# Two processes, one LAN run on 127.0.0.1:
#
#   godot --headless --path <project> -s res://tools/cast_net_host.gd
#   godot --headless --path <project> -s res://tools/cast_net_client.gd
#
# In Mayari's trial the host gives the client an E skill (the client's skill card pops up
# from the host's snapshot), uses a skill of its own (the client sees its name over the
# host's ghost) and then watches the client use its skill (the host sees the name over the
# client's ghost, and the client over its own mortal).

const PORT := 24684
const PORT_FILE := "user://cast_net_host.txt"
const SETTINGS_FILE := "user://lobby_settings_cast_check.cfg"
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


# Advance every dialogue on screen (the intro, the closing lines).
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
	root.get_node("Settings").config_path = "user://settings_cast_check.cfg"
	network.set_my_name("HOSTPEER")
	network.lobby_settings_path = SETTINGS_FILE
	network.start_host(PORT)
	network.set_run_settings({"trials": 3, "order_mode": "custom", "custom_order": ["mayari", "tala", "hanan"], "trial_time": 90.0, "opening_cutscene": "skip"})
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
	_check(await _until(func() -> bool: return _game() != null and _game().arena != null and _game().arena.god_id == &"mayari"),
		"the host opens the run on Mayari")
	_check(await _until(func() -> bool: return _game().arena._phase == Arena.Phase.PLAYING), "the trial is under way on the host")
	var arena: Arena = _game().arena
	await _until(func() -> bool: return arena._ghosts.has(client_id) and is_instance_valid(arena._ghosts[client_id]))
	_check(arena._ghosts.has(client_id), "the host has the client's ghost")

	# --- a skill gained by the client: its card pops up from the host's snapshot --------------
	var e_skill := Gods.favor_by_id(&"half_vision")
	var q_skill := Gods.favor_by_id(&"siblings_compromise")
	_check(arena.rules.bestow_favor(e_skill, client_id), "the host gives the client Half Vision (E)")
	arena._publish_god_state()
	arena.rules.bestow_favor(q_skill)  # and itself a Q skill, to cast
	arena._publish_god_state()
	await _frames(10)
	_check(arena.hud._popup != null and arena.hud._popup.favor == q_skill, "the host's own gain pops up on the host")

	# --- the host casts: the client will see it over the host's ghost -------------------------------
	await _until(func() -> bool: return false, 2.5)  # the client reads its card first
	arena._use_skill(GodFavor.Slot.Q)
	_check(arena.player.floating_text.visible and arena.player.floating_text.text == q_skill.display_name.to_upper(),
		"the host sees its own cast over its mortal (%s)" % arena.player.floating_text.text)

	# --- the client casts: the host sees it over the client's ghost ---------------------------------
	var ghost: ArenaMortal = arena._ghosts[client_id]
	_check(await _until(func() -> bool: return ghost.floating_text.visible and ghost.floating_text.text == e_skill.display_name.to_upper()),
		"the host sees the client's cast over its ghost (%s)" % ghost.floating_text.text)
	await _until(func() -> bool: return false, 3.0)  # the client reads it too
	_finish()


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PORT_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_cast_check.cfg"))
	print("networked casts (host): %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
