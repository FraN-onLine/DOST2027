extends SceneTree

# The CLIENT half of the networked check of Langit Lupa's 5 s Langit (its partner,
# and how to run the two, is in tools/langit_cloud_net_host.gd). It follows the host
# into the trial and checks that its own screen shows the same Langit timers: the
# countdown starts with the host's step, runs down in step with it, the Langit
# shakes in its last second, crumbles together with the host's and a new one forms.

const PORT_FILE := "user://langit_cloud_net_host.txt"
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
	root.get_node("Settings").config_path = "user://settings_langit_cloud_check_client.cfg"
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
	_check(await _until(func() -> bool: return arena._phase == Arena.Phase.PLAYING, 60.0), "the trial is under way on the client")
	# --- the host steps on Langit 0: the same countdown here ------------------------------------------
	var ids: Array[int] = arena._cloud_id.duplicate()
	_check(await _until(func() -> bool: return arena._cloud_burn.size() > 0 and arena._cloud_burn[0] >= 0.0, 10.0), "the client sees the countdown start on the host's Langit")
	var first: float = arena._cloud_burn[0]
	await _frames(1)
	var node := arena.langits_root.get_child(0) as Node2D
	var title := node.get_node("Name") as Label
	_check(title.text.begins_with("LANGIT ") and int(title.text.get_slice(" ", 1)) >= 1, "...drawn with its seconds on the client (%s)" % title.text)
	_check(arena._cloud_burn.size() > 1 and arena._cloud_burn[1] < 0.0, "...and no timer on the others")
	await _until(func() -> bool: return arena._cloud_anim.size() > 0, 3.0)
	await _frames(1)
	node = arena.langits_root.get_child(0) as Node2D
	_check(arena._cloud_anim.size() > 0 and node.scene_file_path.ends_with("Langit%d.tscn" % (int(arena._cloud_anim[0]) + 1)),
		"...the same pillar variant the host picked (%s)" % node.scene_file_path)
	await _until(func() -> bool: return false, 1.0)
	_check(arena._cloud_burn[0] < first - 0.5, "the client's countdown runs down (%.2f -> %.2f)" % [first, arena._cloud_burn[0]])
	# --- the last second shakes, then it crumbles with the host's ----------------------------------------
	_check(await _until(func() -> bool: return arena._cloud_burn[0] > 0.0 and arena._cloud_burn[0] <= arena.shift_warning, 4.0), "the client reaches the last second")
	await _frames(2)
	node = arena.langits_root.get_child(0) as Node2D
	_check(node.modulate.a < 0.9, "...the Langit shakes and fades on the client (alpha %.2f)" % node.modulate.a)
	_check(await _until(func() -> bool: return arena._cloud_state[0] == LangitLupaArena.Cloud.CRUMBLING, 4.0), "the client sees it crumble")
	_check(await _until(func() -> bool: return arena._cloud_id[0] != ids[0], 3.0), "...and a new one form in its slot")
	await _frames(2)
	node = arena.langits_root.get_child(0) as Node2D
	_check(arena._cloud_burn[0] < 0.0 and node.position.distance_to(arena._langits[0]) < 4.0, "...fresh (no timer), drawn where the host put it")
	_finish()


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings_langit_cloud_check_client.cfg"))
	print("5 s Langit, networked (client): %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
