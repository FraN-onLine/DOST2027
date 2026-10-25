extends SceneTree

# The HOST half of the networked rest check (its partner is
# tools/prep_net_client.gd). Two processes, one LAN run on 127.0.0.1:
#
#   godot --headless --path <project> -s res://tools/prep_net_host.gd
#   godot --headless --path <project> -s res://tools/prep_net_client.gd
#
# The first trial really ends (clock out -> closing lines -> the dialogue
# handshake), both screens land in the preparation area, the client is sent its
# own offers and buys one over the wire, then at the altar (only a shop) buys a
# blessing for FAVOR (request_boon_purchase) while keeping the voucher the host
# gave it; the host buys one at its own altar too, its voucher kept; both press
# READY, both open the next trial with the client's purchases and both vouchers
# riding along, and the client spends its kept voucher there (request_god_grant).

const PORT := 24682
const PORT_FILE := "user://prep_net_host.txt"
const SETTINGS_FILE := "user://lobby_settings_prep_check.cfg"
const WAIT := 30.0   # seconds any one step may take

var _problems := 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


# Wait (pumping every dialogue on screen) until `done` says yes, or `seconds` pass.
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
	network.set_my_name("HOSTPEER")
	network.lobby_settings_path = SETTINGS_FILE
	network.start_host(PORT)
	network.set_run_settings({"trials": 3, "order_mode": "custom", "custom_order": ["tala", "mayari", "hanan"],
		"trial_time": 60.0, "due_step": 1000, "prep_time": 60.0, "opening_cutscene": "skip"})  # a rest long enough for the altar below
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
	_check(await _until(func() -> bool: return _game() != null and _game().arena != null and _game().arena.god_id == &"tala"),
		"the host opens the run on Tala")

	# --- the first trial: GO!, then the clock runs out ---------------------------------
	_check(await _until(func() -> bool: return _game().arena._phase == Arena.Phase.PLAYING), "the trial starts on both screens")
	var arena: Arena = _game().arena
	arena.rules.mortal(client_id).favor = 1000
	arena._publish_god_state()
	await _frames(10)
	arena._trial_time = 0.05
	_check(await _until(func() -> bool: return _game().arena is PrepArea), "the trial's end hands both screens to the rest")
	var prep: PrepArea = _game().arena
	_check(prep.next_god_id == &"mayari" and prep._networked, "the host's rest is networked and names Mayari")
	var shelf: Array[StringName] = prep.offers_for(client_id)
	_check(shelf.size() == 3, "the host rolled the client a shelf of three (%s)" % str(shelf))
	# A voucher left over, for the client's altar below - once the shell has put
	# the run's snapshot into the rest (a frame later), or it would wipe it.
	await _until(func() -> bool: return _game().rules == prep.rules)
	prep.rules.mortal(client_id).due = 1
	prep._publish_god_state()

	# --- the client buys over the wire ----------------------------------------------
	_check(await _until(func() -> bool: return prep.bought_by(client_id).size() == 1), "the client's purchase reaches the host")
	if prep.bought_by(client_id).size() == 1:
		var item := Pamanas.by_id(prep.bought_by(client_id)[0])
		var buyer := prep.rules.mortal(client_id)
		_check(shelf.has(item.id), "it was on the client's shelf")
		_check(buyer.favor == 1000 - item.cost, "the host charged %d FAVOR (%d)" % [item.cost, buyer.favor])

	# --- the altar sells only: the client's blessing for FAVOR, its voucher kept --------
	var buyer := prep.rules.mortal(client_id)
	await _until(func() -> bool: return false, 2.0)  # (the client checks what its Pamana cost first)
	buyer.favor = 1000  # enough for a blessing on top of the Pamana
	prep._publish_god_state()
	_check(await _until(func() -> bool: return prep.boons_bought_by(client_id).size() == 1), "the client's blessing purchase reaches the host")
	if prep.boons_bought_by(client_id).size() == 1:
		var boon := Gods.tala().get_favor(prep.boons_bought_by(client_id)[0])
		_check(boon != null and buyer.has_favor(boon.id) and buyer.favor == 1000 - prep.boon_cost,
			"the host sold it a blessing of Tala's for %d FAVOR (%d)" % [prep.boon_cost, buyer.favor])
		_check(buyer.due == 1, "...and the client keeps its voucher (%d)" % buyer.due)

	# --- the host's own altar: a blessing for FAVOR, its voucher kept --------------------------
	# (A moment first: the client is still reading "<name> bought ..." off the
	# event line, which the host's own purchase would replace.)
	await _until(func() -> bool: return false, 2.0)
	var me := prep.rules.local()
	me.due = 1
	me.favor = 1000
	prep._toggle_due_menu()
	await _frames(2)
	var plain := 0
	for at in range(prep.due_menu._shown.size()):
		if (prep.due_menu._shown[at] as GodFavor).kind != GodFavor.Kind.INSTANT:
			plain = at
			break
	prep.due_menu._choose(plain)
	_check(prep.boons_bought_by(1).size() == 1 and me.favor == 1000 - prep.boon_cost and me.due == 1,
		"F at the host's altar buys a blessing for FAVOR and keeps the voucher (%d FAVOR, %d due)" % [me.favor, me.due])

	# --- READY on both screens ends the rest ------------------------------------------
	await _frames(20)
	prep._ready_up()
	_check(await _until(func() -> bool: return _game().arena != null and not (_game().arena is PrepArea) and _game().arena.god_id == &"mayari"), "both READY: the host opens Mayari's trial")
	await _until(func() -> bool: return _game().rules != null)  # the shell attaches it a frame later
	var next_rules: GodMatch = _game().rules
	_check(next_rules != null and (next_rules.mortal(client_id).pamana_next != &"" or next_rules.mortal(client_id).surigao_early > 0),
		"the client's purchase rides into the host's next trial")
	_check(next_rules != null and next_rules.mortal(client_id).due == 1 and next_rules.local().due == 1, "...and both kept vouchers do too")
	var client_favors := next_rules.mortal(client_id).favors.size() if next_rules != null else 0
	_check(await _until(func() -> bool: return next_rules.mortal(client_id).due == 0 and next_rules.mortal(client_id).favors.size() == client_favors + 1),
		"the client spends its kept voucher in Mayari's trial (the host grants it)")
	# Stay up while the client finishes its own checks.
	await _until(func() -> bool: return false, 6.0)
	_finish()


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PORT_FILE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	print("networked rest (host): %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
