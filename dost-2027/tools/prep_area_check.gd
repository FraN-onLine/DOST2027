extends SceneTree

# Validation: the preparation area (PAHINGA) between two trials. Through the real
# Game shell, solo:
#   * it opens after a trial and before Bathala's finale, never after the finale
#   * it is hosted by the god who just played and names the next trial
#   * no FAVOR moves in it except purchases (no ticker, no simulated rival)
#   * the Tindahan offers up to 3 different Pamana, only those the mortal can use,
#     and the same shelf every time it is asked
#   * one purchase per mortal; an unaffordable one, or one not on the shelf, is
#     refused; a bought card reads BINILI and the others lock
#   * READY ends the rest early, and the clock ends it too
#   * the God's Due menu there offers the previous god's favors
#   * what was bought rides into the next trial and wakes at its "GO!"
# Run: godot --headless --path <project> -s res://tools/prep_area_check.gd

const DT := 0.125

var _problems := 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)
	var network: Node = root.get_node("Network")
	var order: Array[StringName] = [&"apolaki", &"tala", &"bathala"]
	network.rpc_sync_trial_order(order)
	var game: Control = load("res://scenes/Game.tscn").instantiate()
	view.add_child(game)
	await _frames(4)
	_check(game.arena != null and not (game.arena is PrepArea) and game.arena.god_id == &"apolaki", "the run opens on its first trial")

	# --- after a trial: the rest -----------------------------------------------------
	game.rules.local().favor = 1000
	game._on_trial_complete()
	await _frames(4)
	var prep: PrepArea = game.arena as PrepArea
	_check(prep != null, "a finished trial opens the preparation area")
	if prep == null:
		return _finish()
	_check(prep.god.id == &"apolaki" and prep.next_god_id == &"tala", "it is hosted by the god who just played, and knows the next")
	_check(prep.next_label.visible and prep.next_label.text == "NEXT: TALA - %s" % Gods.tala().game_name.to_upper(),
		"the banner names the next trial (%s)" % prep.next_label.text)
	_check(game.timer_label.text.begins_with("PAHINGA "), "the timer pill reads PAHINGA (%s)" % game.timer_label.text)
	_check(game.rules == prep.rules and game.rules.local().favor == 1000, "the shell reads the rest's match, carrying the run")
	_check(not prep.rules.trial_active, "no trial is running in the rest")

	# --- no FAVOR moves here except purchases -------------------------------------------
	var rules: GodMatch = prep.rules
	var me := rules.local()
	for id in ["the_great", "panahon_ng_anihan", "binhi", "first_light", "full_moon"]:
		me.favors.append(Gods.favor_by_id(StringName(id)))
	me.drought_time = 5.0
	me.drought_caster = 2
	me.regrowths = [[1.0, 300]]
	me.pamana_window = 10.0
	var before := {}
	for m in rules.mortals.values():
		before[m.id] = m.favor
	for step in range(int(4.0 / DT)):
		prep._process(DT)
		rules._process(DT)
	var still := true
	for m in rules.mortals.values():
		still = still and m.favor == int(before[m.id])
	_check(still, "four seconds of rest move no FAVOR (no drought, regrowth, rival or ticker)")
	_check(is_equal_approx(me.pamana_window, 10.0), "a Pamana window does not run in the rest")
	me.drought_time = 0.0
	me.regrowths = []
	me.pamana_window = 0.0

	# --- the Tindahan's offers ---------------------------------------------------------------
	var offers: Array[StringName] = prep.offers_for(1)
	var distinct := {}
	for id in offers:
		distinct[id] = true
	_check(offers.size() == 3 and distinct.size() == 3, "three different Pamana are offered (%s)" % str(offers))
	_check(prep.offers_for(1) == offers and prep.my_offers() == offers, "asking again gets the same shelf")
	var skill_items := [Pamanas.TORN_CEDULAS, Pamanas.MIGHTY_PEN, Pamanas.KAMPILAN]
	var leaked := false
	for roll in range(40):
		for id in prep._roll_offers(1):
			if skill_items.has(id):
				leaked = true
	_check(not leaked, "without E or Q no skill Pamana is ever offered")
	var e_skill: GodFavor = null
	for favor in Gods.apolaki().favors:
		if favor.slot == GodFavor.Slot.E:
			e_skill = favor
	rules.bestow_favor(e_skill, 1)
	var seen := {}
	for roll in range(60):
		for id in prep._roll_offers(1):
			seen[id] = true
	_check(not seen.has(Pamanas.MIGHTY_PEN) and seen.has(Pamanas.TORN_CEDULAS) and seen.has(Pamanas.KAMPILAN),
		"with an E skill only: the Cedulas and the Kampilan can come, the Pen never (%s)" % str(seen.keys()))
	me.surigao_early = 200
	seen.clear()
	for roll in range(60):
		for id in prep._roll_offers(1):
			seen[id] = true
	_check(not seen.has(Pamanas.SURIGAO_GOLD), "no Surigao Gold while one is still waiting")
	me.surigao_early = 0

	# --- buying ---------------------------------------------------------------------------
	var not_offered: StringName = &""
	for item in Pamanas.all():
		if not offers.has(item.id):
			not_offered = item.id
	_check(not prep.try_purchase(1, not_offered), "an item that is not on your shelf cannot be bought")
	me.favor = 10
	_check(not prep.try_purchase(1, offers[0]) and me.favor == 10, "an unaffordable purchase is refused")
	me.favor = 1000
	prep.player.global_position = prep.stall.global_position
	prep.open_shop()
	_check(prep.shop.is_open() and prep.shop.rows.get_child_count() == 3, "LEFT CLICK at the stall opens the Tindahan with the three cards")
	var item := Pamanas.by_id(offers[0])
	_check(prep.shop.choose(0), "a card is chosen with its key / a click")
	_check(me.favor == 1000 - item.cost, "the purchase costs %d FAVOR (%d)" % [item.cost, me.favor])
	_check(me.pamana_next == item.id or (item.id == Pamanas.SURIGAO_GOLD and me.surigao_early > 0), "the item waits for the next trial")
	_check(not prep.try_purchase(1, offers[1]) and me.favor == 1000 - item.cost, "a second purchase is refused")
	prep._process(DT)
	await _frames(2)
	var prices: Array = []
	for column in prep.shop.rows.get_children():
		prices.append((column.get_node("Price") as Label).text)
	_check(prices[0] == "BINILI" and str(prices[1]).ends_with("LOCKED") and str(prices[2]).ends_with("LOCKED"),
		"the bought card reads BINILI and the others lock (%s)" % str(prices))
	_check(prep.hud.banner_label.text == "%s bought %s" % [me.display_name, item.display_name], "everyone hears about it (%s)" % prep.hud.banner_label.text)
	_check(game.pamana_row.visible and game.pamana_label.text.contains(item.display_name), "our panel shows the Pamana badge (%s)" % game.pamana_label.text)
	prep.player.global_position = Vector2(700, 470)
	prep._process(DT)
	_check(not prep.shop.is_open(), "walking away from the stall closes the Tindahan")

	# --- late God's Due: the previous god's favors ---------------------------------------
	me.due = 1
	prep._toggle_due_menu()
	await _frames(2)
	var from_host: bool = not prep.due_menu._shown.is_empty()
	for favor in prep.due_menu._shown:
		from_host = from_host and favor.god_id == &"apolaki"
	_check(prep.due_menu.is_open() and from_host, "F opens the God's Due menu with Apolaki's favors")
	prep._toggle_due_menu()

	# --- READY ends the rest, the purchase rides on -----------------------------------------
	prep._ready_up()
	await _frames(4)
	_check(game.arena != null and not (game.arena is PrepArea) and game.arena.god_id == &"tala", "READY ends the rest and the next trial starts")
	var carried: GodMatch.Mortal = game.rules.local()
	if item.id != Pamanas.SURIGAO_GOLD:
		_check(carried.pamana_next == item.id, "the purchase rides into the next trial")
		game.arena._start_trial()
		_check(carried.pamana_active == item.id, "...and wakes at its GO!")
	else:
		_check(carried.surigao_early > 0, "Surigao Gold rides into the next trial")

	# --- the rest before the finale, closed by its clock --------------------------------------
	game._on_trial_complete()
	await _frames(4)
	prep = game.arena as PrepArea
	_check(prep != null and prep.next_god_id == &"bathala" and prep.god.id == &"tala", "there is a rest right before Bathala's finale")
	if prep != null:
		var start := prep.rules.local().favor
		for step in range(int((prep.prep_time + 1.0) / DT)):
			if game.arena != prep:
				break
			prep._process(DT)
		await _frames(4)
		_check(game.arena != null and not (game.arena is PrepArea) and game.arena.god_id == &"bathala", "the clock ends the rest on its own")
		_check(game.rules.local().favor == start, "a rest with no purchase cost nothing")
	game._on_trial_complete()
	await _frames(4)
	_check(game.arena == null and game.finale_panel.visible, "after the finale there is no rest - the run is judged")
	game.queue_free()
	await _frames(2)
	await _networked_rest(view, network)
	_finish()


# The same rest, host and client, driven by the messages they would exchange
# (like tools/client_check.gd does for an arena): each client gets only its own
# shelf, the host decides a client's purchase, and the tick tells the client
# what it bought and who is ready. A player who leaves counts as ready.
func _networked_rest(view: SubViewport, network: Node) -> void:
	var players_before: Dictionary = network.players.duplicate()
	network.players = {1: "HOST", 2: "CLIENT", 3: "THIRD"}
	var scene: PackedScene = load("res://scenes/prep/PrepArea.tscn")
	var host: PrepArea = scene.instantiate()
	host.god_id = &"tala"
	host.next_god_id = &"mayari"
	view.add_child(host)
	var client: PrepArea = scene.instantiate()
	client.god_id = &"tala"
	client.next_god_id = &"mayari"
	view.add_child(client)
	await _frames(2)
	host._networked = true
	for id in [2, 3]:
		host.rules.ensure_mortal(id, network.players[id])
		host.rules.mortal(id).favor = 1000
	client._networked = true
	client._authority = false
	client._my_id = 2
	client.rules.authority = false
	client.rules.ensure_mortal(2, "CLIENT")
	client.rules.set_local_id(2)
	client._on_god_state_received(host.rules.snapshot())

	var shelf: Array[StringName] = host.offers_for(2)
	client._on_prep_offers_received(shelf.map(func(id: StringName) -> String: return str(id)))
	_check(client.my_offers() == shelf, "a client's shelf is exactly what the host rolled for it")
	_check(host.offers_for(3).size() == 3 and host._offers.has(2) and host._offers.has(3), "every mortal gets a shelf of its own")
	var item := Pamanas.by_id(shelf[0])
	host._on_prep_purchase_requested(2, str(item.id))
	_check(host.rules.mortal(2).favor == 1000 - item.cost and host.bought_by(2) == [item.id], "the host makes a client's purchase")
	host._on_prep_purchase_requested(2, str(shelf[1]))
	_check(host.bought_by(2).size() == 1, "...and refuses its second one")
	var popups := client.popups_root.get_child_count()
	client._on_god_state_received(host.rules.snapshot())
	client.arena_read_tick(host.arena_tick_fields())
	_check(client.rules.local().favor == 1000 - item.cost and client.bought_by(2) == [item.id], "the client mirrors what it paid and bought")
	_check(client.popups_root.get_child_count() == popups, "the client shows no loss popup for its purchase")

	host._ready_ids = [1, 2]
	_check(host.ready_count() == Vector2i(2, 3) and not host._all_ready(), "READY 2/3: the rest waits for the third mortal")
	client.arena_read_tick(host.arena_tick_fields())
	client._refresh_prep_hud()
	_check(client.ready_label.text == "READY 2/3" and client.is_ready(2), "the client reads READY 2/3 (%s)" % client.ready_label.text)
	_check(client.player.name_tag.text.ends_with(PrepArea.READY_MARK), "a ready player's name tag carries the tick (%s)" % client.player.name_tag.text)
	network.players.erase(3)
	_check(host._all_ready(), "a player who leaves counts as ready")
	network.players = players_before
	host.queue_free()
	client.queue_free()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1


func _finish() -> void:
	print("preparation area checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
