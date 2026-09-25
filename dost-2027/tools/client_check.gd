extends SceneTree

# Temporary validation: the multiplayer client path (layout, FAVOR mirror, ticks).
# Run: godot --headless --path <project> -s res://tools/client_check.gd

var _host
var _client
var _view: SubViewport

func _initialize() -> void:
	_run()

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _run() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(1152, 648)
	_view.disable_3d = true
	get_root().add_child(_view)

	_host = load("res://scenes/MayariArena.tscn").instantiate()
	_view.add_child(_host)
	await _frames(3)

	print("=== HOST SIDE ===")
	print("host: authority=%s my_id=%d corners=%d clones=%d" % [
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
	var layout := {"field": _host._field, "zones": [], "clones": []}
	for zone in _host._zones:
		layout["zones"].append({"pos": zone.global_position, "size": zone.box_size, "rate": float(zone.base_rate), "label": str(zone.zone_label)})
	for clone in _host._clones:
		layout["clones"].append(_host._clone_definition(clone))
	var god_snapshot: Dictionary = _host.rules.snapshot()
	print("layout: zones=%d clones=%d | snapshot mortals=%s" % [
		layout["zones"].size(), layout["clones"].size(), str(god_snapshot.keys())])

	print("=== CLIENT SIDE (mirror) ===")
	_client = load("res://scenes/MayariArena.tscn").instantiate()
	_view.add_child(_client)
	await _frames(2)
	# Force client mode: authority=false, mirroring the host.
	_client._networked = true
	_client._authority = false
	_client._my_id = 2
	_client.rules.set_local_id(2)
	print("client before sync: corners=%d clones=%d field=%s" % [
		_client._zones.size(), _client._clones.size(), str(_client._field)])

	_client._on_arena_layout_received(layout)
	await _frames(2)
	print("client after layout: corners=%d clones=%d field=%s match_host=%s" % [
		_client._zones.size(), _client._clones.size(), str(_client._field), str(_client._field == _host._field)])
	for index in range(_client._clones.size()):
		print("   client clone %d mode=%d axis=%d self_moving=%s pos=%s" % [
			index, int(_client._clones[index].mode), int(_client._clones[index].axis),
			str(_client._clones[index].self_moving), str(_client._clones[index].global_position)])

	_client._on_god_state_received(god_snapshot)
	await _frames(2)
	print("client mirror favor=%d due=%d mortals=%d" % [
		_client.rules.local().favor, _client.rules.local().due, _client.rules.mortals.size()])
	print("client HUD: FAVOR=%s DUE=%s barE='%s'" % [
		_client.hud.favor_value.text, _client.hud.due_value.text, _client.hud.bar_e.text_label.text])

	print("=== CLIENT FOLLOWS THE HOST TICK ===")
	var tick := {
		"phase": int(_host._phase),
		"trial_time": 42.5,
		"clones": [_host._clones[0].global_position, _host._clones[1].global_position],
		"mortals": {1: Vector2(700.0, 300.0), 2: Vector2(200.0, 500.0)},
		"banner": "MOONLIGHT RUSH!",
		"banner_color": Color(0.55, 0.85, 1.0),
		"event": "Mayari's clones speed up for 5s",
		"event_color": Color(0.55, 0.85, 1.0),
	}
	_client._on_arena_state_received(tick)
	await _frames(3)
	print("client phase=%d (2=PLAYING) timer=%.1f dialogue_active=%s locked=%s" % [
		_client._phase, _client._trial_time, str(_client.dialogue.is_active()), str(_client.player.locked)])
	print("client clone0 at %s (host %s) | mortal positions=%s" % [
		str(_client._clones[0].global_position), str(_host._clones[0].global_position), str(_client._mortal_positions)])
	print("client mirrored banner='%s' event='%s'" % [_client.hud.banner_label.text, _client.hud.event_label.text])

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
	print("client phase=%d (3=RESULTS) dialogue=%s" % [_client._phase, str(_client.dialogue.is_active())])
	var guard2 := 0
	while _client.dialogue.is_active() and guard2 < 40:
		_client.dialogue.advance()
		guard2 += 1
	await _frames(2)
	print("client results visible=%s body='%s'" % [
		str(_client.hud.results_panel.visible), _client.hud.results_label.text.replace("\n", " | ")])

	print("=== SCENES ===")
	for path in ["res://scenes/Lobby.tscn", "res://scenes/MainMenu.tscn", "res://scenes/GodIntro.tscn"]:
		var packed := load(path)
		print("%s -> %s" % [path, "OK" if packed != null else "FAILED"])
	var lobby = load("res://scenes/Lobby.tscn").instantiate()
	_view.add_child(lobby)
	await _frames(2)
	var button = lobby.get_node("CenterContainer/VBoxContainer/ButtonContainer/DetailsButton")
	print("lobby GOD'S GAMES button: '%s' visible=%s" % [button.text, str(button.visible)])
	print("--- DONE ---")
	quit()
