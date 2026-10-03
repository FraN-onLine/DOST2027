extends SceneTree

# Temporary validation: the multiplayer client path (layout, FAVOR mirror, ticks).
# The client mirrors the authored scene: the two Mayaris and the four favor
# zones are already there, so only the lit zone and the positions travel.
# Run: godot --headless --path <project> -s res://tools/client_check.gd

var _host
var _client
var _view: SubViewport


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


# Fail-safe so a broken step can never leave the headless run hanging.
func _watchdog() -> void:
	await create_timer(30.0).timeout
	printerr("client_check: timed out")
	quit()


func _run() -> void:
	_watchdog()
	_view = SubViewport.new()
	_view.size = Vector2i(1152, 648)
	_view.disable_3d = true
	get_root().add_child(_view)

	_host = load("res://scenes/gods/mayari/MayariArena.tscn").instantiate()
	_view.add_child(_host)
	await _frames(3)

	print("=== HOST SIDE ===")
	print("host: authority=%s my_id=%d zones=%d clones=%d" % [
		str(_host._authority), _host._my_id, _host._zones.size(), _host._clones.size()])
	# Move the host into the trial so the client has a PLAYING phase to follow.
	var guard := 0
	while _host.dialogue.is_active() and guard < 40:
		_host.dialogue.advance()
		guard += 1
	_host._countdown = 0.001
	await _frames(3)
	print("host phase=%d (2=PLAYING)" % _host._phase)
	# Pretend peer 2 joined: give the host a remote mortal with a voucher.
	_host.rules.ensure_mortal(2, "MORTAL 2")
	_host.rules.mortal(2).due = 1
	_host._mortal_positions[2] = Vector2(300.0, 300.0)
	var layout := {"field": _host._field, "active_goal": _host._active_goal_index, "zones": []}
	for zone in _host._zones:
		layout["zones"].append({
			"size": zone.box_size,
			"rate": zone.rate,
			"favor_amount": zone.favor_amount,
			"label": str(zone.zone_label),
			"favor_enabled": zone.favor_enabled,
		})
	var god_snapshot: Dictionary = _host.rules.snapshot()
	print("layout keys=%s zones=%d | snapshot mortals=%s" % [
		str(layout.keys()), layout["zones"].size(), str(god_snapshot.keys())])

	print("=== CLIENT SIDE (mirror) ===")
	_client = load("res://scenes/gods/mayari/MayariArena.tscn").instantiate()
	_view.add_child(_client)
	await _frames(2)
	# Force client mode: authority=false, mirroring the host.
	_client._networked = true
	_client._authority = false
	_client._my_id = 2
	_client.rules.set_local_id(2)
	print("client before sync: zones=%d clones=%d field=%s" % [
		_client._zones.size(), _client._clones.size(), str(_client._field)])

	_client._on_arena_layout_received(layout)
	await _frames(2)
	print("client after layout: zones=%d clones=%d field=%s match_host=%s lit=%d" % [
		_client._zones.size(), _client._clones.size(), str(_client._field),
		str(_client._field == _host._field), _client._active_goal_index])
	for index in range(_client._clones.size()):
		var clone: MayariClone = _client._clones[index]
		print("   client %s self_moving=%s path=%.0f px knots=%d pos=%s" % [
			clone.name, str(clone.self_moving), clone.path_length(),
			clone.path_knots().size(), str(clone.global_position)])

	_client._on_god_state_received(god_snapshot)
	await _frames(2)
	print("client mirror favor=%d due=%d mortals=%d" % [
		_client.rules.local().favor, _client.rules.local().due, _client.rules.mortals.size()])
	# Mirroring the host must never cost a client its own identity: the host's
	# mortal is peer 1 and a solo rules object also calls peer 1 "local", so a
	# client that took the solo path would read the HOST's FAVOR, name and
	# results as its own. Arena._detect_networked is what stops that.
	if str(_client.rules.local().display_name) != "MORTAL 2" or int(_client.rules.local_id) != 2:
		printerr("client_check: a client must keep its own mortal as local (got '%s' / id %d)" % [
			str(_client.rules.local().display_name), int(_client.rules.local_id)])
	print("client identity: networked=%s authority=%s my_id=%d local_id=%d local_name='%s'" % [
		str(_client._networked), str(_client._authority), _client._my_id,
		int(_client.rules.local_id), str(_client.rules.local().display_name)])
	print("client HUD: FAVOR=%s DUE=%s barE='%s'" % [
		_client.hud.favor_value.text, _client.hud.due_value.text, _client.hud.bar_e.text_label.text])

	print("=== CLIENT FOLLOWS THE HOST TICK ===")
	var tick := {
		"phase": int(_host._phase),
		"trial_time": 42.5,
		"clones": [_host._clones[0].global_position, _host._clones[1].global_position],
		"mortals": {1: Vector2(700.0, 300.0), 2: Vector2(200.0, 500.0)},
		"banner": "GO!",
		"banner_color": Arena.FAVOR_COLOR,
		"event": "Mayari's light moves to the NW GOAL",
		"event_color": Arena.FAVOR_COLOR,
	}
	_client._on_arena_state_received(tick)
	await _frames(3)
	print("client phase=%d (2=PLAYING) timer=%.1f dialogue_active=%s locked=%s" % [
		_client._phase, _client._trial_time, str(_client.dialogue.is_active()), str(_client.player.locked)])
	print("client clone0 at %s (host %s) | mortal positions=%s" % [
		str(_client._clones[0].global_position), str(_host._clones[0].global_position),
		str(_client._mortal_positions)])
	print("client mirrored banner='%s' event='%s'" % [
		_client.hud.banner_label.text, _client.hud.event_label.text])

	print("=== CLIENT GOD'S DUE MENU (asks the host) ===")
	_client._free_grants = 0
	_client.rules.local().due = 1
	_client._toggle_due_menu()
	await _frames(2)
	print("client menu open=%s rows=%d (remote mode, no local granting)" % [
		str(_client.due_menu.is_open()), _client.due_menu.rows.get_child_count()])
	var owned_before: int = _client.rules.local().favors.size()
	_client.due_menu._choose(0)
	await _frames(2)
	print("after choosing on the client: owned before=%d after=%d (host decides) - menu still open=%s" % [
		owned_before, _client.rules.local().favors.size(), str(_client.due_menu.is_open())])
	_client._toggle_due_menu()

	print("=== THE HOST TELLS THE CLIENT ITS MORTAL WAS HIT ===")
	# The host scores every hit, but a mortal is simulated where it is played: the
	# host only reports the hit and the client shoves its own mortal (Network
	# rpc_arena_hit -> Arena._on_arena_hit_received). Without this a joiner would
	# feel nothing at all when Mayari catches it.
	_client.player.global_position = Vector2(500.0, 480.0)
	_client._on_arena_hit_received({"direction": Vector2.RIGHT, "stun": 1.3, "force": 560.0})
	print("client hit report: knockback %s stun=%.2f (the client shoves its own mortal)" % [
		str(_client.player._knockback), _client.player._stun])
	if _client.player._knockback.length() <= 0.0 or _client.player._stun <= 0.0:
		printerr("client_check: the client ignored the host's hit report")
	# The FAVOR that hit took travels with the next snapshot, and the loss pops
	# over the mortal's head on the client's own screen.
	_host.rules.lose_favor(50, "Mayari's clone", 2)
	_client._on_god_state_received(_host.rules.snapshot())
	var loss_text := _popup_text(_client)
	print("client mirrored loss -> popup '%s' | mirror FAVOR=%d" % [
		loss_text, _client.rules.local().favor])
	if not loss_text.begins_with("-"):
		printerr("client_check: a mirrored FAVOR loss must pop over the mortal")

	# Half Vision: the host reports WHO cast it, and the client's own screen is
	# only darkened when somebody else did.
	_client._on_arena_blind_received(2, 0.16, 1.5)
	await _frames(2)
	print("client cast Half Vision itself: darkness=%.2fs mask_visible=%s" % [
		_client._blind_time, str(_client.vision_mask.visible)])
	if _client._blind_time > 0.0 or _client.vision_mask.visible:
		printerr("client_check: Half Vision blinded the mortal that cast it")
	_client._on_arena_blind_received(1, 0.16, 1.5)
	await _frames(2)
	print("client hit by a rival's Half Vision: darkness=%.2fs radius=%.2f mask_visible=%s" % [
		_client._blind_time, _client._blind_radius, str(_client.vision_mask.visible)])
	if _client._blind_time <= 0.0 or not _client.vision_mask.visible:
		printerr("client_check: a rival's Half Vision must blind this screen")
	_client._blind_time = 0.0
	await _frames(2)

	print("=== HOST GRANTS IT AND THE MIRROR CATCHES UP ===")
	_host.rules.grant_favor(_host.god.get_favor(&"half_vision"), 2)
	_client._on_god_state_received(_host.rules.snapshot())
	await _frames(2)
	print("client favor list=%d barE='%s'" % [
		_client.rules.local().favors.size(), _client.hud.bar_e.text_label.text])

	print("=== HOST ENDS THE TRIAL -> CLIENT FOLLOWS ===")
	_host._trial_time = -0.1
	_host._tick_trial(0.016)
	await _frames(2)
	var results_tick := {"phase": int(_host._phase), "trial_time": 0.0, "clones": [], "mortals": tick["mortals"]}
	_client._on_arena_state_received(results_tick)
	_client._on_god_state_received(_host.rules.snapshot())
	await _frames(2)
	print("client phase=%d (3=RESULTS) dialogue=%s waiting=%s token='%s'" % [
		_client._phase, str(_client.dialogue.is_active()),
		str(_client._dialogue_waiting), _client._dialogue_wait_id])
	var guard2 := 0
	while _client.dialogue.is_active() and guard2 < 40:
		_client.dialogue.advance()
		await process_frame
		guard2 += 1
	await _frames(2)
	# A client never closes its own results: the HOST releases the dialogue and
	# every client follows. Emulate the host here so the mirror can finish.
	if _client._dialogue_waiting:
		_client._on_dialogue_released(_client._dialogue_wait_id)
	else:
		printerr("client_check: the client never started waiting for the host")
	await _frames(2)
	print("client results visible=%s body='%s'" % [
		str(_client.hud.results_panel.visible), _client.hud.results_label.text.replace("\n", " | ")])

	print("=== THE HOST OWNS THE NAME (lobby UPDATE NAME) ===")
	# A rename has to stick on the machine that made it: my_name is what this
	# machine's arena reads for the tag over the mortal, so the host's own rename
	# has to update it - and a client has to take the name the host confirmed,
	# not the one it last typed.
	var network = get_root().get_node_or_null("Network")
	if network == null:
		printerr("client_check: the Network autoload is missing - cannot rename")
	else:
		network.set_my_name("HOSTNAME")
		network.players[1] = "HOSTNAME"
		network.player_data[1] = PlayerData.new("HOSTNAME")
		network.request_name_change(1, "NEWNAME")
		print("host renamed itself: my_name='%s' players[1]='%s' player_data='%s'" % [
			network.my_name, str(network.players[1]), network.player_data[1].name])
		if network.my_name != "NEWNAME" or str(network.players[1]) != "NEWNAME":
			printerr("client_check: the host's own rename must become my_name")
		network.my_name = "TYPED NAME"
		network.rpc_update_player_list({1: "NEWNAME", 2: "OTHER"})
		print("client took the confirmed name: my_name='%s' | host tag '%s' | client tag '%s'" % [
			network.my_name, _host.player.name_tag.text, _client.player.name_tag.text])
		if network.my_name != "NEWNAME":
			printerr("client_check: a client must take the name the host confirmed")
		network.players.clear()
		network.my_name = ""

	print("=== THE FAST POSITION STREAM ===")
	# Mortal positions ride their own message (a few Vector2s, position_tick_rate
	# times a second) instead of waiting for the fat world tick.
	_client._mortal_positions.clear()
	_client._on_mortal_positions_received({7: Vector2(520, 400)})
	_expect(_client._mortal_positions.get(7) == Vector2(520, 400), "the position stream moves a mortal")
	_client._on_mortal_positions_received({8: Vector2(600, 400)})
	_expect(_client._mortal_positions.has(7) and _client._mortal_positions.has(8),
		"a partial position update never wipes the rest of the roster")

	var ghost := Node2D.new()
	_client.ghosts_root.add_child(ghost)
	ghost.global_position = Vector2(100, 100)
	_client._ghosts[9] = ghost
	_client._mortal_positions[9] = Vector2(110, 100)
	_client._move_ghosts(1.0 / 60.0)
	_expect(ghost.global_position.x > 100.0 and ghost.global_position.x < 110.0,
		"a ghost glides towards a nearby position (%.1f px)" % ghost.global_position.x)
	_client._mortal_positions[9] = Vector2(600, 400)
	_client._move_ghosts(1.0 / 60.0)
	_expect(ghost.global_position == Vector2(600, 400),
		"a knockback-sized jump puts the ghost where it belongs instead of gliding it")

	print("=== SCENES ===")
	for path in ["res://scenes/Lobby.tscn", "res://scenes/MainMenu.tscn", "res://scenes/GodIntro.tscn"]:
		var packed := load(path)
		print("%s -> %s" % [path, "OK" if packed != null else "FAILED"])
	var lobby = load("res://scenes/Lobby.tscn").instantiate()
	_view.add_child(lobby)
	await _frames(2)
	var button = lobby.get_node("CenterContainer/VBoxContainer/ButtonContainer/OptionsButton")
	print("lobby Options button: '%s' visible=%s" % [button.text, str(button.visible)])
	print("--- DONE ---")
	quit()


# The text of the newest FAVOR popup over a mortal ('' when there is none).
func _popup_text(arena) -> String:
	var popups: Array = arena.popups_root.get_children()
	if popups.is_empty():
		return ""
	var label: Label = popups[popups.size() - 1].get_node_or_null("Box/Label")
	return label.text if label != null else ""


# One pass/fail line, the way the rest of this probe reports.
func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
