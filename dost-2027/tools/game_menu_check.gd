extends SceneTree

# Validation: Esc in the Game shell opens the run's own menu. The trials never
# pause - the round clock keeps running under it - but this screen's hands come
# off the arena (no input, no walking) until the menu closes, and Esc closes it
# again. Options opens above the menu and BACK returns to it. What the menu
# offers depends on who opened it: only a host can end the run for the table,
# and QUIT GAME only appears when nobody else would be stranded. The menu sits
# above every arena layer, and ending a run forgets it without touching the
# lobby's roster.
# Run: godot --headless --path <project> -s res://tools/game_menu_check.gd

const GAME_SCENE := "res://scenes/Game.tscn"
const MENU_SCENE := "res://scenes/GameMenu.tscn"
const TEMP_CONFIG := "user://settings_game_menu_check.cfg"
const PLAYING_WAIT := 20.0

var _problems := 0
var _settings: Node = null


func _initialize() -> void:
	_run()


func _watchdog() -> void:
	await create_timer(120.0).timeout
	printerr("game_menu_check: timed out")
	quit(1)


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


# Wait until `done` says yes, or `seconds` pass.
func _until(done: Callable, seconds := 10.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await process_frame
	return done.call()


func _pause(seconds: float) -> void:
	await _until(func() -> bool: return false, seconds)


func _esc() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	return event


func _check(condition: bool, label: String) -> void:
	print("PASS: %s" % label if condition else "FAIL: %s" % label)
	if not condition:
		_problems += 1


func _run() -> void:
	_watchdog()
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	get_root().add_child(view)
	await _frames(2)
	_settings = get_root().get_node("Settings")
	_settings.config_path = TEMP_CONFIG  # never the player's own file
	_settings.reset_all()
	var network: Node = get_root().get_node("Network")
	var forced: Array[StringName] = [&"mayari", &"tala", &"bathala"]
	network.trial_order_ids = forced

	var shell: Node = load(GAME_SCENE).instantiate()
	view.add_child(shell)
	await _frames(4)
	if not await _until(func() -> bool: return shell.arena != null and is_instance_valid(shell.arena), PLAYING_WAIT):
		_check(false, "the first trial loaded")
		return _finish()
	var arena: Node = shell.arena
	var menu: Control = shell.game_menu
	var player: Node = arena.get("player")

	# --- the menu starts closed and covers the screen when it opens --------------------------------
	_check(not menu.is_open() and not shell._menu_open, "the run opens with the menu closed")
	_check(menu.mouse_filter == Control.MOUSE_FILTER_STOP and menu.anchor_right == 1.0 and menu.anchor_bottom == 1.0,
		"the menu is a full-screen blocker (clicks never reach the field)")
	var layer: CanvasLayer = shell.get_node("MenuLayer")
	_check(layer.layer > 45, "the menu sits above every arena layer (layer %d)" % layer.layer)

	# --- Esc during the opening belongs to the cutscene's own skip ------------------------
	shell._cutscene = Node.new()
	shell._unhandled_input(_esc())
	await _frames(1)
	_check(not menu.is_open(), "Esc during the opening does not open the menu")
	shell._cutscene.free()
	shell._cutscene = null

	# --- reach a live round (the intro dialogue's handshake, the 3 - 2 - 1, GO) --------------
	var dialogue: Node = arena.dialogue
	if not await _until(func() -> bool: return dialogue != null and dialogue.is_active(), 5.0):
		_check(false, "the god's intro spoke")
		return _finish()
	dialogue.close_now()
	if not await _until(func() -> bool: return int(arena.get("_phase")) == Arena.Phase.PLAYING, PLAYING_WAIT):
		_check(false, "the round began after the intro")
		return _finish()
	_check(true, "a trial is playing before the menu is opened")

	# --- Esc opens it, and the trial keeps running ------------------------------------------
	var before: float = arena.get("_trial_time")
	shell._unhandled_input(_esc())
	await _frames(2)
	_check(menu.is_open() and shell._menu_open, "Esc opens the menu")
	_check(not paused, "the tree is not paused")
	_check(arena.is_processing() and shell.is_processing(), "the trial and the shell keep processing")
	_check(arena.is_processing_input() == false and arena.is_processing_unhandled_input() == false,
		"the trial stops reading input")
	_check(bool(arena.menu_open), "the arena knows the menu is open (no buffered dash escapes)")
	_check(player != null and bool(player.walk_muted), "the mortal stops walking (held keys included)")
	_check(shell.get_node("HudLayer/FinalePanel/Margin/VBox/HintRow/Hint").text == "MENU",
		"the finale button is labelled MENU")

	var title: Label = menu.get_node("Center/Panel/Margin/VBox/Title")
	var subtitle: Label = menu.get_node("Center/Panel/Margin/VBox/Subtitle")
	_check(title.text == "THE GODS WATCH" and subtitle.text.contains("go on"),
		"the menu says the trials go on (%s / %s)" % [title.text, subtitle.text])
	_check(menu.get_node("Center/Panel/Margin/VBox/Resume").text == "RESUME"
		and menu.get_node("Center/Panel/Margin/VBox/Options").text == "OPTIONS"
		and menu.get_node("Center/Panel/Margin/VBox/MainMenu").text == "MAIN MENU",
		"it offers RESUME, OPTIONS and MAIN MENU")
	_check(menu.resume_button.has_focus(), "RESUME takes the focus")

	# A lone host: no rivals to strand, so the table can be sent home and the game quit.
	_check(menu.lobby_button.visible, "a host (alone) can end the run: BACK TO LOBBY")
	_check(menu.quit_button.visible, "...and QUIT GAME when nobody else is connected")

	await _pause(1.2)
	var after: float = arena.get("_trial_time")
	_check(after < before - 0.5, "the round clock kept running under the menu (%.1f -> %.1f)" % [before, after])

	# --- RESUME gives the trial its hands back ----------------------------------------------
	menu.resume_button.pressed.emit()
	await _frames(2)
	_check(not menu.is_open() and not shell._menu_open, "RESUME closes the menu")
	_check(not bool(arena.menu_open) and arena.is_processing_input() and arena.is_processing_unhandled_input(),
		"the trial reads input again")
	_check(player != null and not bool(player.walk_muted), "the mortal walks again")

	# --- Esc toggles -------------------------------------------------------------------------
	shell._unhandled_input(_esc())
	await _frames(1)
	_check(menu.is_open(), "Esc opens it again")
	shell._unhandled_input(_esc())
	await _frames(1)
	_check(not menu.is_open() and not paused, "Esc closes it again, still without pausing")

	# --- the lobby and main-menu buttons are wired to the run's exits ------------------------
	var lobby_wired: bool = menu.lobby_requested.get_connections().size() == 1 \
		and menu.lobby_requested.get_connections()[0]["callable"].get_method() == "_return_to_lobby"
	var menu_wired: bool = menu.menu_requested.get_connections().size() == 1 \
		and menu.menu_requested.get_connections()[0]["callable"].get_method() == "_return_to_menu"
	_check(lobby_wired and menu_wired, "BACK TO LOBBY and MAIN MENU reach the Game shell's exits")
	_check(network.has_method("end_run") and network.has_method("close_session") and network.has_method("rpc_run_ended"),
		"Network can end a run, close a session and tell every peer")

	# --- OPTIONS opens above the menu, and the trial stays muted -----------------------------
	shell._unhandled_input(_esc())
	await _frames(1)
	menu.options_button.pressed.emit()
	await _frames(3)
	var options = shell._options
	_check(options != null and is_instance_valid(options), "OPTIONS opens over the run")
	if options != null:
		_check(options.get_parent() == layer, "...inside the menu layer")
		_check(not menu.visible, "...the menu itself steps aside")
		_check(bool(arena.menu_open) and not arena.is_processing_input(), "...and the trial stays muted")
		# Esc while Options is open must not reopen the menu underneath it.
		shell._unhandled_input(_esc())
		await _frames(1)
		_check(shell._options == options and not menu.visible, "Esc with Options open leaves the menu closed")
		options.back_button.pressed.emit()
		await _frames(3)
		_check(shell._options == null, "BACK from Options closes it")
		_check(menu.visible and shell._menu_open, "...and returns to the run's menu")
		_check(bool(arena.menu_open) and not arena.is_processing_input(), "the trial is still muted")
	shell._unhandled_input(_esc())
	await _frames(1)
	_check(not menu.is_open() and not bool(arena.menu_open), "closing the menu unmutes the trial")

	# --- who sees which exits -----------------------------------------------------------------
	await _gating(view)

	# --- ending a run forgets it, but not the lobby -------------------------------------------
	network.players = {1: "HOSTPEER", 2: "RIVAL"}
	network.run_settings = RunSettings.defaults()
	network._game_in_progress = true
	network.opening_pending = true
	network.scene_token = "mayari"
	network.god_state = {1: {"favor": 5}}
	network.mortal_positions = {1: Vector2.ONE}
	network.piko_stones = {1: 0}
	network.announced_trial_order = forced
	network._forget_run()
	_check(not network._game_in_progress and not network.opening_pending and network.scene_token == "",
		"ending the run puts the shell's run flags away")
	_check(network.god_state.is_empty() and network.mortal_positions.is_empty() and network.piko_stones.is_empty(),
		"...its per-trial caches too")
	_check(network.trial_order_ids.is_empty() and network.announced_trial_order.is_empty(),
		"...and the run's trial plan (the next START draws a fresh one)")
	_check(network.players.size() == 2 and network.run_settings != null,
		"...while the lobby's roster and run settings survive")
	_finish()


# The same menu, opened as each kind of player would see it.
func _gating(view: SubViewport) -> void:
	var menu: Control = load(MENU_SCENE).instantiate()
	view.add_child(menu)
	await _frames(2)
	menu.open(false, true)
	_check(menu.visible and not menu.lobby_button.visible and menu.quit_button.visible,
		"a client gets no BACK TO LOBBY, but can quit its own game")
	_check(menu.menu_button.tooltip_text.contains("Leave this run"), "a client's MAIN MENU leaves the run")
	menu.open(true, false)
	_check(menu.lobby_button.visible and not menu.quit_button.visible,
		"a host with rivals can end the run, but cannot quit the game")
	_check(menu.menu_button.tooltip_text.contains("Close the session"), "a host's MAIN MENU closes the session")
	menu.open(true, true)
	_check(menu.lobby_button.visible and menu.quit_button.visible, "a host alone can also quit the game")
	menu.queue_free()
	await _frames(2)


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_CONFIG))
	if _settings != null:
		_settings.config_path = "user://settings.cfg"
	print("game menu checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
