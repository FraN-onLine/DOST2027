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
#   * the altar only sells: every favor of that god is a blessing for 750 FAVOR,
#     vouchers held or not (never spent there; a line says they are kept and they
#     ride into the next trial) - priced cards, too poor is refused (the price in
#     EMBER), one blessing per rest (then the cards lock and the altar says it was
#     bought) on top of the one Pamana, only that god's favors, a skill boon
#     replaces the old skill and its card says so, and everyone hears "<name> bought <favor>"
#   * in a trial the God's Due menu stays voucher-only, and F still spends a voucher
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
	_check(still, "four seconds of rest move no FAVOR (no regrowth, rival or ticker)")
	_check(is_equal_approx(me.pamana_window, 10.0), "a Pamana window does not run in the rest")
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
	await _altar_boons(prep, me)

	# --- READY ends the rest, the purchase rides on -----------------------------------------
	prep._ready_up()
	await _frames(4)
	_check(game.arena != null and not (game.arena is PrepArea) and game.arena.god_id == &"tala", "READY ends the rest and the next trial starts")
	var carried: GodMatch.Mortal = game.rules.local()
	_check(carried.due == 2, "the vouchers kept at the altar ride into the next trial (%d)" % carried.due)
	await _trial_menu_unchanged(game.arena)
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
	var popups := client.favor_popups_root.get_child_count()
	client._on_god_state_received(host.rules.snapshot())
	client.arena_read_tick(host.arena_tick_fields())
	_check(client.rules.local().favor == 1000 - item.cost and client.bought_by(2) == [item.id], "the client mirrors what it paid and bought")
	_check(client.favor_popups_root.get_child_count() == popups, "the client shows no loss popup for its purchase")

	# The altar's boon, asked for over the (simulated) wire.
	var boon := _plain_favor(Gods.tala().favors, host.rules.mortal(2))
	var client_favor := host.rules.mortal(2).favor
	host._on_boon_purchase_requested(2, str(boon.id))
	_check(host.rules.mortal(2).has_favor(boon.id) and host.rules.mortal(2).favor == client_favor - host.boon_cost,
		"the host sells a client its boon (%s) for %d FAVOR" % [boon.display_name, host.boon_cost])
	host.rules.mortal(2).favor = 5000
	host._on_boon_purchase_requested(2, str(_plain_favor(Gods.tala().favors, host.rules.mortal(2)).id))
	_check(host.boons_bought_by(2) == [boon.id], "...and refuses its second one")
	host.rules.mortal(2).favor = client_favor - host.boon_cost
	popups = client.favor_popups_root.get_child_count()
	client._on_god_state_received(host.rules.snapshot())
	client.arena_read_tick(host.arena_tick_fields())
	_check(client.rules.local().has_favor(boon.id) and client.boons_bought_by(2) == [boon.id] and client.boons_left(2) == 0,
		"the client mirrors its boon and that it has none left")
	_check(client.favor_popups_root.get_child_count() == popups, "...with no loss popup for the FAVOR it spent")

	host._ready_ids = [1, 2]
	host._rest_age = host.presence_grace + 1.0
	host._present = [1, 2]
	_check(host.ready_count() == Vector2i(2, 2) and host._all_ready(), "a mortal who never reached the rest is not waited for (READY 2/2)")
	host._present = [1, 2, 3]
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


# The altar of the god who just hosted (Apolaki here), solo. Called after the
# Tindahan purchase, so the boon below is bought on top of a Pamana.
func _altar_boons(prep: PrepArea, me: GodMatch.Mortal) -> void:
	var menu = prep.due_menu
	var paid_pamana := me.pamana_next != &"" or me.surigao_early > 0
	_check(prep.altar_hint.text.ends_with("BUY A BLESSING (750 FAVOR)"), "the altar says what F does there (%s)" % prep.altar_hint.text)

	# Vouchers held, too little FAVOR: still a shop - the price in EMBER on a greyed
	# card, refused, and the vouchers kept.
	me.due = 2
	me.favor = 500
	prep._toggle_due_menu()
	await _frames(2)
	_check(menu.due_label.text == "BUY A BLESSING - 750 FAVOR", "with vouchers held the altar still only sells (%s)" % menu.due_label.text)
	var kept := menu.get_node_or_null("SidePanel/Margin/VBox/KeptNote") as Label
	_check(kept != null and kept.visible and kept.text == "Your God's Due vouchers are kept for the next trial.", "...and says the vouchers are kept")
	var price := _price_label(menu, 0)
	_check(price.text == "750 FAVOR" and price.get_theme_color("font_color") == UITokens.readable_on_dark(UITokens.EMBER, UITokens.NIGHT_800)
		and is_equal_approx(menu.rows.get_child(0).modulate.a, 0.5), "too poor: the card is greyed and its price is EMBER (%s)" % price.text)
	var wanted: GodFavor = menu._shown[_plain_index(menu)]
	menu._choose(_plain_index(menu))
	_check(menu.is_open() and not me.has_favor(wanted.id) and me.favor == 500 and me.due == 2, "...choosing it does nothing, and no voucher is spent")
	_check(not prep.try_buy_boon(me.id, wanted.id) and me.due == 2, "the host refuses it too, and the mortal keeps both vouchers")
	menu.close()

	# 2 vouchers and 1000 FAVOR: bought for FAVOR, the vouchers untouched.
	me.favor = 1000
	prep._toggle_due_menu()
	await _frames(2)
	price = _price_label(menu, 0)
	_check(price.text == "750 FAVOR" and price.get_theme_color("font_color") == UITokens.readable_on_dark(UITokens.JADE, UITokens.NIGHT_800),
		"affordable: the price reads 750 FAVOR in JADE")
	var popups := prep.favor_popups_root.get_child_count()
	var index := _plain_index(menu)
	var boon: GodFavor = menu._shown[index]
	menu._choose(index)
	_check(me.has_favor(boon.id) and me.favor == 1000 - prep.boon_cost and me.due == 2 and prep.boons_bought_by(me.id) == [boon.id],
		"a blessing is bought: %s for %d FAVOR, still 2 vouchers (%d)" % [boon.display_name, prep.boon_cost, me.due])
	prep._refresh_prep_hud()
	_check(prep.altar_hint.text == "BLESSING BOUGHT", "...the altar says the blessing was bought (%s)" % prep.altar_hint.text)
	_check(paid_pamana and (me.pamana_next != &"" or me.surigao_early > 0), "...on top of the Pamana bought at the Tindahan")
	_check(prep.hud.event_label.text == "%s bought %s" % [me.display_name, boon.display_name], "everyone hears it (%s)" % prep.hud.event_label.text)
	_check(prep.favor_popups_root.get_child_count() == popups, "spending is not a loss: no red popup")

	# One boon per rest: refused, and the cards lock.
	var second := _plain_favor(Gods.apolaki().favors, me)
	_check(second != null and not prep.try_buy_boon(me.id, second.id) and me.favor == 1000 - prep.boon_cost and me.due == 2, "a second blessing in the same rest is refused")
	prep._toggle_due_menu()
	await _frames(2)
	_check(_price(menu, 0) == "750 FAVOR - LOCKED", "...and the altar's cards lock (%s)" % _price(menu, 0))
	menu.close()

	# Only this god's favors, never one already held.
	var mayari_favor: GodFavor = Gods.mayari().favors[0]
	_check(not prep.rules.can_buy_boon(mayari_favor, me.id) and not prep.try_buy_boon(me.id, mayari_favor.id),
		"a favor of another god is not for sale at Apolaki's altar")
	_check(not prep.rules.can_buy_boon(boon, me.id), "nor one the mortal already holds")

	# A skill boon takes its slot: the card warns, and the old skill goes. (The Q
	# slot is cleared first - the voucher above may have filled it with Apolaki's.)
	for at in range(me.favors.size() - 1, -1, -1):
		if me.favors[at].slot == GodFavor.Slot.Q:
			me.favors.remove_at(at)
	var old_q: GodFavor = null
	for favor in Gods.mayari().favors:
		if favor.slot == GodFavor.Slot.Q and prep.rules.is_favor_eligible(favor, me.id):
			old_q = favor
	var new_q: GodFavor = null
	for favor in Gods.apolaki().favors:
		if favor.slot == GodFavor.Slot.Q and not me.has_favor(favor.id) and prep.rules.is_favor_eligible(favor, me.id):
			new_q = favor
	if old_q != null and new_q != null:
		prep.rules.bestow_favor(old_q, me.id)
		var card: Control = menu._make_row(1, new_q, 0)
		var warning := card.get_node_or_null("Replaces") as Label
		_check(warning != null and warning.text == "REPLACES %s" % old_q.display_name,
			"a skill boon's card warns what it replaces (%s)" % (warning.text if warning != null else "none"))
		card.free()
		me.favor = 1000
		_check(prep.rules.buy_boon(new_q, me.id, prep.boon_cost) and me.favor_in_slot(GodFavor.Slot.Q) == new_q and not me.has_favor(old_q.id),
			"...and buying it puts %s in Q in place of %s" % [new_q.display_name, old_q.display_name])
	else:
		_check(false, "a Q skill of Mayari and of Apolaki to swap (%s, %s)" % [str(old_q), str(new_q)])
	me.favor = 1000


# In a trial the God's Due menu stays voucher-only: no prices, nothing for FAVOR.
func _trial_menu_unchanged(arena: Arena) -> void:
	var me := arena.rules.local()
	me.due = 0
	me.favor = 5000
	arena._toggle_due_menu()
	await _frames(2)
	var menu = arena.due_menu
	_check(menu._boon_cost == 0 and menu.due_label.text == "GOD'S DUE VOUCHERS: 0"
		and (_price(menu, 0) in ["NEEDS 1 GOD'S DUE", ""] or _price(menu, 0).begins_with("REPLACES")),
		"in a trial the God's Due menu is voucher-only (%s / %s)" % [menu.due_label.text, _price(menu, 0)])
	var held := me.favors.size()
	menu._choose(0)
	_check(me.favors.size() == held and me.favor == 5000, "...and no FAVOR buys a favor there")
	menu.close()
	me.due = 1
	arena._toggle_due_menu()
	await _frames(2)
	var spent: GodFavor = menu._shown[_plain_index(menu)]
	menu._choose(_plain_index(menu))
	_check(me.has_favor(spent.id) and me.due == 0 and me.favor == 5000, "in a trial F still spends a voucher (%s)" % spent.display_name)


# The card at `index`: its price (or cost) line.
func _price_label(menu: Control, index: int) -> Label:
	if index >= menu.rows.get_child_count():
		return null
	return menu.rows.get_child(index).get_node_or_null("Price") as Label


func _price(menu: Control, index: int) -> String:
	var label := _price_label(menu, index)
	return label.text if label != null else ""


# A shown favor that is not an INSTANT one (whose own FAVOR would blur the sums).
func _plain_index(menu: Control) -> int:
	for index in range(menu._shown.size()):
		if (menu._shown[index] as GodFavor).kind != GodFavor.Kind.INSTANT:
			return index
	return 0


func _plain_favor(favors: Array, mortal: GodMatch.Mortal) -> GodFavor:
	for favor in favors:
		if favor.kind != GodFavor.Kind.INSTANT and not mortal.has_favor(favor.id) and favor.requires_god_id() == &"" and favor.requires_any_god_ids().is_empty():
			return favor
	return null


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
