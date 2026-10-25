extends SceneTree

# A CLIENT of the 3-player rest check (the host, and how to run all three, is in
# tools/prep_trio_host.gd). `-- shop` stands in the Tindahan with it open when the
# clock runs out; `-- walk` walks the field. Neither presses READY. Each checks its
# rest stays playable through the host's late RESULTS ticks and that it follows
# the host into Mayari's trial when the clock ends the rest.

const PORT_FILE := "user://prep_trio_host.txt"
const WAIT := 30.0

var _problems := 0
var _role := "walk"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_role = args[0]
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
	network.set_my_name("TRIO_" + _role.to_upper())
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
	_check(await _until(func() -> bool: return joined[0]), "%s: joined the host" % _role)
	var lobby: Control = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby)
	current_scene = lobby

	_check(await _until(func() -> bool: return _game() != null and _game().arena is PrepArea, 90.0), "%s: follows the trial's end into the rest" % _role)
	if not (_game() != null and _game().arena is PrepArea):
		return _finish()
	var prep: PrepArea = _game().arena
	await _until(func() -> bool: return false, 2.5)  # the host's late RESULTS ticks land meanwhile
	_check(not prep.player.locked and prep._phase == Arena.Phase.INTRO and not prep.dialogue.is_active() and prep._trial_time > 0.5,
		"%s: the late RESULTS ticks leave the rest playable (locked %s, phase %d, clock %.1f)" % [_role, str(prep.player.locked), prep._phase, prep._trial_time])
	if _role == "shop":
		prep.player.global_position = prep.stall.global_position
		prep.open_shop()
		_check(prep.shop.is_open(), "shop: the Tindahan is open as the clock runs down")
	else:
		var from := prep.player.global_position
		Input.action_press("move_right")
		await _until(func() -> bool: return false, 0.6)
		Input.action_release("move_right")
		_check(prep.player.global_position.distance_to(from) > 20.0, "walk: the mortal walks in the rest (%.0f px)" % prep.player.global_position.distance_to(from))
	_check(await _until(func() -> bool: return _game().arena != null and not (_game().arena is PrepArea) and _game().arena.god_id == &"mayari", 25.0),
		"%s: the clock ends the rest and this screen opens Mayari's trial" % _role)
	_finish()


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _finish() -> void:
	print("3-player rest (client %s): %d problem(s)" % [_role, _problems])
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
