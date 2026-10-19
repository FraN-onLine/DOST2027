extends SceneTree

# The CLIENT half of the networked rest check (its partner, and how to run the
# two, is in tools/prep_net_host.gd). This screen follows the host through the
# end of the first trial into the rest, receives ONLY its own offers, buys one
# at the Tindahan (the host decides), sees it come back as BINILI, presses READY
# and opens the next trial carrying it.

const PORT_FILE := "user://prep_net_host.txt"
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
	var joined := [false]
	network.connected.connect(func(success: bool, _reason: String) -> void: joined[0] = success)
	network.join_host("127.0.0.1", port)
	_check(await _until(func() -> bool: return joined[0]), "the client joined the host")
	var lobby: Control = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby)
	current_scene = lobby
	var my_id: int = network.multiplayer.get_unique_id()

	_check(await _until(func() -> bool: return _game() != null and _game().arena is PrepArea, 60.0),
		"the client follows the host's trial end into the rest")
	if not (_game() != null and _game().arena is PrepArea):
		return _finish()
	var prep: PrepArea = _game().arena
	_check(not prep._authority and prep.next_god_id == &"mayari", "the client's rest mirrors the host and names Mayari")
	_check(await _until(func() -> bool: return prep.my_offers().size() == 3), "the host sent this client its own three offers (%s)" % str(prep.my_offers()))
	_check(await _until(func() -> bool: return prep.rules.local().favor == 1000), "the client mirrors the FAVOR the host gave it")

	prep.player.global_position = prep.stall.global_position
	prep.open_shop()
	var item := Pamanas.by_id(prep.my_offers()[0])
	_check(prep.shop.is_open() and prep.shop.choose(0), "the client asks to buy %s" % item.display_name)
	_check(await _until(func() -> bool: return prep.bought_by(my_id).has(item.id) and prep.rules.local().favor == 1000 - item.cost),
		"the host's answer comes back: bought, %d FAVOR paid" % item.cost)
	prep._refresh_prep_hud()
	await _frames(2)
	var price := ""
	for column in prep.shop.rows.get_children():
		if price == "":
			price = (column.get_node("Price") as Label).text
	_check(price == "BINILI", "the card reads BINILI on the client (%s)" % price)
	_check(_game().pamana_row.visible, "the client's own panel carries the Pamana badge")

	prep._ready_up()
	_check(await _until(func() -> bool: return _game().arena != null and not (_game().arena is PrepArea) and _game().arena.god_id == &"mayari"), "both READY: the client opens Mayari's trial")
	await _until(func() -> bool: return _game().rules != null)  # the shell attaches it a frame later
	var carried: GodMatch.Mortal = _game().rules.local()
	_check(carried.pamana_next == item.id or (item.id == Pamanas.SURIGAO_GOLD and carried.surigao_early > 0),
		"the purchase rides into the client's next trial")
	_finish()


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _finish() -> void:
	print("networked rest (client): %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
