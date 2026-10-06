extends SceneTree

# Validation for the lobby's OPTIONS menu (scenes/LobbyOptions.tscn) and the run
# setup behind it (scripts/RunSettings.gd, Network.run_settings):
#   * trials stay within 3..9
#   * every planned run ends with exactly one Bathala and has trials + 1 entries
#   * with more trials than gods, gods repeat - but never back to back
#   * CUSTOM rows follow the trial count, and a back-to-back repeat blocks START
#   * a client cannot change any setting; a synced setup reaches its lobby
#   * trial length, God's Due step and intro mode reach the arena and GodMatch
#   * RESET restores the defaults, and the host's saved setup loads back
# Uses a temporary settings file, never the host's user://lobby_settings.cfg.
# Run: godot --headless --path <project> -s res://tools/lobby_options_check.gd

const TEMP_SETTINGS := "user://lobby_settings_check.cfg"

var _problems := 0
var _network: Node


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
	await _frames(2)
	_network = root.get_node("Network")
	_network.lobby_settings_path = TEMP_SETTINGS
	_network.players = {1: "HOST", 2: "RIVAL"}
	_network.player_data = {1: PlayerData.new("HOST"), 2: PlayerData.new("RIVAL")}
	_network.player_icons = {1: &"mayari", 2: &"tala"}
	_apply(RunSettings.defaults().to_dict())

	var lobby: Control = load("res://scenes/Lobby.tscn").instantiate()
	view.add_child(lobby)
	await _frames(3)
	var options = lobby.lobby_options
	_check(not options.visible, "the panel is hidden until OPTIONS opens it")
	_check(lobby.options_button.visible, "OPTIONS is there for everyone")
	lobby._on_options_pressed()
	await _frames(2)
	_check(options.visible and options.editable, "the host's panel opens editable")
	var panel: Rect2 = options.get_global_rect()
	_check(panel.position.x >= 0 and panel.position.y >= 0 and panel.end.x <= 1152 and panel.end.y <= 648,
		"the panel fits the 1152x648 screen (%s)" % str(panel))

	# --- trials stay within 3..9 ------------------------------------------------------
	_network.set_run_setting("trials", 1)
	_check(_settings().trials == Gods.TRIALS_MIN, "trials cannot go below 3")
	_check(options.minus_button.disabled, "the - button stops at 3")
	_network.set_run_setting("trials", 42)
	_check(_settings().trials == Gods.TRIALS_MAX, "trials cannot go above 9")
	_check(options.plus_button.disabled, "the + button stops at 9")
	options._step_trials(1)
	_check(_settings().trials == Gods.TRIALS_MAX, "+ at 9 changes nothing")
	_apply(RunSettings.defaults().to_dict())
	_check(_settings().trials == 4 and options.trials_value.text == "4", "the default is 4 trials")
	options._step_trials(1)
	_check(_settings().trials == 5, "+ adds a trial")

	# --- every planned run: trials + 1 entries, one Bathala, last --------------------
	var playable := RunSettings.playable_ids()
	var shape_ok := true
	var no_back_to_back := true
	var repeats_seen := false
	var turns_ok := true
	for trials in range(Gods.TRIALS_MIN, Gods.TRIALS_MAX + 1):
		for mode in [RunSettings.ORDER_RANDOM, RunSettings.ORDER_CUSTOM]:
			_apply({"trials": trials, "order_mode": mode})
			for draw in range(12):
				var order := _settings().planned_order()
				if order.size() != trials + 1 or order.count(Gods.BATHALA) != 1 or order[order.size() - 1] != Gods.BATHALA:
					shape_ok = false
				for index in range(1, trials):
					if order[index] == order[index - 1]:
						no_back_to_back = false
				var gods := order.slice(0, trials)
				if trials > playable.size():
					repeats_seen = repeats_seen or _unique(gods) < trials
				# No god comes back before every other god has had a turn.
				if _unique(gods.slice(0, mini(trials, playable.size()))) != mini(trials, playable.size()):
					turns_ok = false
	_check(shape_ok, "every planned run has trials + 1 entries and ends with exactly one Bathala")
	_check(repeats_seen, "with more trials than gods (%d), gods repeat" % playable.size())
	_check(no_back_to_back, "...but never the same god twice in a row (RANDOM and CUSTOM)")
	_check(turns_ok, "no god returns before every other god has had a turn")

	# --- CUSTOM rows follow the trial count ------------------------------------------
	_apply({"trials": 4, "order_mode": "custom"})
	await _frames(1)
	_check(options.order_list.get_child_count() == 5, "CUSTOM shows a row per trial plus Bathala (4 + 1)")
	var finale: Label = options.order_list.get_child(options.order_list.get_child_count() - 1)
	_check(finale.text.contains("BATHALA (finale)") and finale.get_theme_color("font_color") == Gods.bathala().color,
		"the last row is BATHALA (finale), in Bathala's colour")
	var before: Array[StringName] = _settings().custom_order.duplicate()
	options._step_trials(2)
	_check(_settings().custom_order.size() == 6 and options.order_list.get_child_count() == 7, "two more trials, two more rows")
	_check(_settings().custom_order.slice(0, 4) == before, "growing keeps the rows already chosen")
	_check(_settings().repeat_slots().is_empty(), "new rows are filled without a back-to-back repeat")
	_apply({"trials": 3, "order_mode": "custom", "custom_order": _strings(_settings().custom_order)})
	_check(_settings().custom_order == before.slice(0, 3), "fewer trials cut rows from the end")

	# A back-to-back repeat: warned about, and START is blocked until it is fixed.
	_apply({"trials": 3, "order_mode": "custom", "custom_order": ["mayari", "mayari", "tala"]})
	await _frames(1)
	_check(_settings().custom_order == [&"mayari", &"mayari", &"tala"], "the host's repeat stays on screen instead of being changed")
	_check(options.warning_label.visible, "a repeat shows a warning")
	_check(lobby.start_game_button.disabled, "a repeat disables START")
	_network.start_game()
	_check(not _network._game_in_progress, "start_game refuses a run with a repeat")
	options._on_slot_picked(playable.find(&"tala"), 1)
	_check(_settings().custom_order == [&"mayari", &"tala", &"tala"], "the dropdown changes one slot")
	options._on_slot_picked(playable.find(&"apolaki"), 2)
	_check(not options.warning_label.visible and not lobby.start_game_button.disabled, "fixing it clears the warning and enables START")

	# --- RESET -------------------------------------------------------------------------
	_apply({"trials": 7, "order_mode": "custom", "trial_time": 150.0, "due_step": 1500, "intro_mode": "short"})
	options._on_reset_pressed()
	_check(_settings().to_dict() == RunSettings.defaults().to_dict(), "RESET restores the defaults")

	# --- a client cannot change anything --------------------------------------------------
	_apply({"trials": 5, "order_mode": "custom"})
	var locked := _settings().to_dict()
	lobby.is_host = false
	options.open(false)
	await _frames(1)
	var all_disabled: bool = options.minus_button.disabled and options.plus_button.disabled \
		and options.random_box.disabled and options.custom_box.disabled and options.time_option.disabled \
		and options.due_option.disabled and options.intro_option.disabled and options.reset_button.disabled
	for row in options.order_list.get_children():
		if row is HBoxContainer:
			all_disabled = all_disabled and row.get_node("God").disabled and row.get_node("Up").disabled and row.get_node("Down").disabled
	_check(all_disabled, "every control is disabled on a client")
	_check(options.host_note.visible, "a client is told only the host can change these")
	options._step_trials(1)
	options._on_mode_toggled(true, RunSettings.ORDER_RANDOM)
	options._on_slot_picked(0, 1)
	options._on_move_pressed(1, -1)
	options.time_option.item_selected.emit(3)
	options.due_option.item_selected.emit(2)
	options.intro_option.item_selected.emit(1)
	options._on_reset_pressed()
	_check(_settings().to_dict() == locked, "a client cannot change any setting")

	# --- a synced setup reaches a client's lobby -------------------------------------------
	_network.rpc_sync_run_settings({"trials": 6, "order_mode": "random", "trial_time": 60.0, "due_step": 750, "intro_mode": "full"})
	await _frames(1)
	_check(_settings().trials == 6 and _settings().trial_time == 60.0, "a client adopts the setup the host sends")
	_check(lobby.run_summary_label.text == "6 trials + Bathala   |   Random order   |   60s", "the lobby summary follows it (%s)" % lobby.run_summary_label.text)
	_check(options.trials_value.text == "6", "so does the open panel")
	lobby.is_host = true
	options.close()

	# --- trial length, God's Due step and intros reach the run ---------------------------
	_apply({"trials": 3, "order_mode": "random", "trial_time": 150.0, "due_step": 1500, "intro_mode": "short"})
	_network.rpc_sync_trial_order([&"mayari", &"tala", &"apolaki", &"bathala"])
	var game: Control = load("res://scenes/Game.tscn").instantiate()
	view.add_child(game)
	await _frames(4)
	_check(game.arena != null and is_equal_approx(game.arena.trial_time, 150.0), "the trial length reaches the arena")
	_check(game.arena != null and game.arena.rules.milestone_step == 1500, "the God's Due step reaches GodMatch")
	_check(game.arena != null and not game.arena.first_visit, "SHORT intros skip the full intro even on a first visit")
	var mortal = game.arena.rules.local()
	mortal.favor = 0
	game.arena.rules.add_favor(1499, "test")
	_check(mortal.due == 0, "1499 FAVOR is not yet a God's Due at 1500")
	game.arena.rules.add_favor(1, "test")
	_check(mortal.due == 1, "1500 FAVOR is")
	game.queue_free()
	await _frames(2)
	_apply({"intro_mode": "full", "trial_time": 90.0})
	var second: Control = load("res://scenes/Game.tscn").instantiate()
	view.add_child(second)
	await _frames(4)
	_check(second.arena != null and second.arena.first_visit, "FULL intros keep the full intro on a first visit")
	_check(second.arena != null and is_equal_approx(second.arena.trial_time, 90.0), "a 90s setting gives a 90s round")
	second.queue_free()
	await _frames(2)
	_network.trial_order_ids.clear()

	# --- the host's last setup loads back ------------------------------------------------------
	_apply({"trials": 6, "order_mode": "custom", "trial_time": 120.0, "due_step": 750, "intro_mode": "short"})
	var saved := _settings().to_dict()
	_network.save_host_settings()
	_apply(RunSettings.defaults().to_dict())
	_network.load_host_settings()
	_check(_settings().to_dict() == saved, "saved host settings load back")
	var cfg := ConfigFile.new()
	cfg.set_value("run", "settings", {"trials": 42, "order_mode": "custom", "custom_order": ["bathala", "nobody", "tala", "tala"],
		"trial_time": 77.0, "due_step": 3, "intro_mode": "loud"})
	cfg.save(TEMP_SETTINGS)
	_network.load_host_settings()
	var loaded := _settings()
	_check(loaded.trials == 9 and loaded.trial_time == 90.0 and loaded.due_step == 1000 and loaded.intro_mode == "full",
		"a bad saved file is validated on load")
	_check(not loaded.custom_order.has(Gods.BATHALA) and loaded.custom_order.size() == 9 and loaded.repeat_slots().is_empty(),
		"...and its order is cleaned (no Bathala, no unknown god, no repeat)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SETTINGS))
	_apply(RunSettings.defaults().to_dict())

	print("lobby options checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _settings() -> RunSettings:
	return _network.run_settings


# Merge `changes` into the current setup and hand it to the host's setter.
func _apply(changes: Dictionary) -> void:
	var data: Dictionary = _settings().to_dict()
	data.merge(changes, true)
	_network.set_run_settings(data)


func _unique(ids: Array) -> int:
	var seen := {}
	for id in ids:
		seen[id] = true
	return seen.size()


func _strings(ids: Array) -> Array:
	return ids.map(func(id): return str(id))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
