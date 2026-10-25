extends SceneTree

# The CLIENT half of the networked rest check (its partner, and how to run the
# two, is in tools/prep_net_host.gd). This screen follows the host through the
# end of the first trial into the rest, receives ONLY its own offers, buys one
# at the Tindahan (the host decides), sees it come back as BINILI, buys a blessing
# for FAVOR at the altar (only a shop) while the voucher the host gave it is kept,
# presses READY, opens the next trial carrying both, and spends the voucher there.

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
	# The host replays a late RESULTS tick from its trial (a LAN reordering): it must
	# not end the rest, lock the mortal, open the closing lines or zero the clock.
	await _until(func() -> bool: return false, 1.5)
	_check(not prep.player.locked and prep._phase == Arena.Phase.INTRO and not prep.dialogue.is_active() and prep._trial_time > 1.0,
		"a late RESULTS tick from the trial leaves the client's rest playable (locked %s, phase %d, clock %.1f)" % [str(prep.player.locked), prep._phase, prep._trial_time])
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

	# --- the altar sells only: a blessing for FAVOR, the voucher kept ---------------------
	var me := prep.rules.local()
	_check(await _until(func() -> bool: return me.due == 1 and me.favor == 1000), "the host left this client a voucher (and 1000 FAVOR)")
	var favor_before := me.favor
	var popups := prep.favor_popups_root.get_child_count()
	prep._toggle_due_menu()
	await _frames(2)
	_check(prep.due_menu.due_label.text == "BUY A BLESSING - 750 FAVOR", "with a voucher held the altar still only sells (%s)" % prep.due_menu.due_label.text)
	var kept := prep.due_menu.get_node_or_null("SidePanel/Margin/VBox/KeptNote") as Label
	_check(kept != null and kept.visible, "...and says the vouchers are kept for the next trial")
	var index := 0
	for at in range(prep.due_menu._shown.size()):
		if (prep.due_menu._shown[at] as GodFavor).kind != GodFavor.Kind.INSTANT:
			index = at
			break
	var boon: GodFavor = prep.due_menu._shown[index]
	prep.due_menu._choose(index)
	_check(await _until(func() -> bool: return me.has_favor(boon.id) and prep.boons_bought_by(my_id) == [boon.id]),
		"the host's answer comes back: %s bought" % boon.display_name)
	_check(me.favor == favor_before - prep.boon_cost and me.due == 1, "...for %d FAVOR (%d -> %d), the voucher kept (%d)" % [prep.boon_cost, favor_before, me.favor, me.due])
	_check(prep.favor_popups_root.get_child_count() == popups, "...and the client shows no loss popup for it")
	_check(await _until(func() -> bool: return prep.hud.event_label.text.ends_with("bought %s" % boon.display_name)),
		"the event line reads \"<name> bought %s\" (%s)" % [boon.display_name, prep.hud.event_label.text])

	prep._ready_up()
	_check(await _until(func() -> bool: return _game().arena != null and not (_game().arena is PrepArea) and _game().arena.god_id == &"mayari"), "both READY: the client opens Mayari's trial")
	await _until(func() -> bool: return _game().rules != null)  # the shell attaches it a frame later
	var carried: GodMatch.Mortal = _game().rules.local()
	_check(carried.pamana_next == item.id or (item.id == Pamanas.SURIGAO_GOLD and carried.surigao_early > 0),
		"the purchase rides into the client's next trial")
	_check(carried.due == 1, "...and so does the kept voucher (%d)" % carried.due)
	var trial: Arena = _game().arena
	var held := carried.favors.size()
	trial._toggle_due_menu()
	await _frames(2)
	_check(trial.due_menu.due_label.text == "GOD'S DUE VOUCHERS: 1", "in the trial F offers the kept voucher (%s)" % trial.due_menu.due_label.text)
	trial.due_menu._choose(0)
	_check(await _until(func() -> bool: return carried.due == 0 and carried.favors.size() == held + 1), "...and spending it gets the favor from the host")
	_finish()


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _finish() -> void:
	print("networked rest (client): %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
