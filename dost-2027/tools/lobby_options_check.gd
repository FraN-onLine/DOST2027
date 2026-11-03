extends SceneTree

# Validation for the lobby's OPTIONS menu (scenes/LobbyOptions.tscn) and the run
# setup behind it (scripts/RunSettings.gd, Network.run_settings):
#   * trials stay within 3..6
#   * every planned run ends with exactly one Bathala and has trials + 1 entries
#   * no god plays twice in a run (RANDOM and CUSTOM)
#   * CUSTOM rows follow the trial count, a god already in a slot is greyed out
#     in the others, and a repeat blocks START
#   * a client cannot change any setting; a synced setup reaches its lobby
#   * trial length, God's Due step and intro mode reach the arena and GodMatch
#   * PREP TIME (shown as 0:20) and CAMERA survive to_dict / from_dict, a bad
#     value is put back by validate(), and the prep time reaches the rest
#   * STARTER SKILLS: OFF / RANDOM (a unique E + Q deal per mortal) / CUSTOM
#     (every player picks its own E and Q in the CUSTOM BUILD card, unshared)
#   * the five loadouts (Default / Long / Short / Random / Strategic) set their
#     own clock, rest and build on top of the house rules they share, light the
#     one in use, and go back to "custom" the moment a row changes
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

	# --- trials stay within 3..5 ------------------------------------------------------
	_network.set_run_setting("trials", 1)
	_check(_settings().trials == Gods.TRIALS_MIN, "trials cannot go below 3")
	_check(options.minus_button.disabled, "the - button stops at 3")
	_network.set_run_setting("trials", 42)
	_check(Gods.TRIALS_MAX == 6 and _settings().trials == 6, "trials cannot go above 6")
	_check(options.plus_button.disabled, "the + button stops at 6")
	options._step_trials(1)
	_check(_settings().trials == Gods.TRIALS_MAX, "+ at 6 changes nothing")

	# --- PREP TIME and CAMERA ----------------------------------------------------------
	var defaults := RunSettings.defaults()
	_check(defaults.prep_time == 20.0 and defaults.camera_mode == RunSettings.CAMERA_ARENA,
		"the defaults are a 0:20 rest and the whole arena on screen")
	var custom := RunSettings.defaults()
	custom.prep_time = 45.0
	custom.camera_mode = RunSettings.CAMERA_FOLLOW
	var round_trip := RunSettings.from_dict(custom.to_dict())
	_check(round_trip.prep_time == 45.0 and round_trip.camera_mode == RunSettings.CAMERA_FOLLOW,
		"prep time and camera survive to_dict / from_dict")
	var broken := RunSettings.from_dict({"prep_time": 33.0, "camera_mode": "drone"})
	broken.validate()
	_check(broken.prep_time == RunSettings.DEFAULT_PREP_TIME and broken.camera_mode == RunSettings.CAMERA_ARENA,
		"validate() puts an unknown prep time and camera back to the defaults")
	var prep_items: Array[String] = []
	for index in range(options.prep_option.item_count):
		prep_items.append(options.prep_option.get_item_text(index))
	_check(prep_items == ["0:10", "0:20", "0:30", "0:40", "0:45", "1:00"], "PREP TIME reads like the clock (%s)" % str(prep_items))
	_check(options.prep_option.get_item_text(options.prep_option.selected) == "0:20", "...and shows the default 0:20")
	options.prep_option.item_selected.emit(4)
	options.camera_option.item_selected.emit(1)
	_check(_settings().prep_time == 45.0 and _settings().camera_mode == RunSettings.CAMERA_FOLLOW,
		"the host's PREP TIME and CAMERA rows change the setup")
	_check(options.camera_option.get_item_text(options.camera_option.selected) == "FOLLOW PLAYER", "CAMERA shows FOLLOW PLAYER")
	_apply(RunSettings.defaults().to_dict())
	_check(options.camera_option.get_item_text(options.camera_option.selected) == "WHOLE ARENA", "...and WHOLE ARENA again")
	_apply(RunSettings.defaults().to_dict())
	_check(_settings().trials == 4 and options.trials_value.text == "4", "the default is 4 trials")
	options._step_trials(1)
	_check(_settings().trials == 5, "+ adds a trial")

	# --- every planned run: trials + 1 entries, one Bathala, last --------------------
	var playable := RunSettings.playable_ids()
	var shape_ok := true
	var no_repeats := true
	var turns_ok := true
	for trials in range(Gods.TRIALS_MIN, Gods.TRIALS_MAX + 1):
		for mode in [RunSettings.ORDER_RANDOM, RunSettings.ORDER_CUSTOM]:
			_apply({"trials": trials, "order_mode": mode})
			for draw in range(12):
				var order := _settings().planned_order()
				if order.size() != trials + 1 or order.count(Gods.BATHALA) != 1 or order[order.size() - 1] != Gods.BATHALA:
					shape_ok = false
				var gods := order.slice(0, trials)
				if _unique(gods) < trials:
					no_repeats = false
				# No god comes back before every other god has had a turn.
				if _unique(gods.slice(0, mini(trials, playable.size()))) != mini(trials, playable.size()):
					turns_ok = false
	_check(shape_ok, "every planned run has trials + 1 entries and ends with exactly one Bathala")
	_check(playable.size() >= Gods.TRIALS_MAX, "there is a god for every trial slot (%d gods, %d slots)" % [playable.size(), Gods.TRIALS_MAX])
	_check(no_repeats, "no god plays twice in a run, a random 5 included (RANDOM and CUSTOM)")
	_check(turns_ok, "no god returns before every other god has had a turn")

	# --- CUSTOM rows follow the trial count ------------------------------------------
	_apply({"trials": 3, "order_mode": "custom"})
	await _frames(1)
	_check(options.order_list.get_child_count() == 4, "CUSTOM shows a row per trial plus Bathala (3 + 1)")
	var finale: Label = options.order_list.get_child(options.order_list.get_child_count() - 1)
	_check(finale.text.contains("BATHALA (finale)") and finale.get_theme_color("font_color") == UITokens.god_text(Gods.bathala()),
		"the last row is BATHALA (finale), in Bathala's text colour")
	var before: Array[StringName] = _settings().custom_order.duplicate()
	options._step_trials(2)
	_check(_settings().custom_order.size() == 5 and options.order_list.get_child_count() == 6, "two more trials, two more rows")
	_check(_settings().custom_order.slice(0, 3) == before, "growing keeps the rows already chosen")
	_check(_settings().repeat_slots().is_empty(), "new rows are filled with gods not playing yet")
	var first_picker: OptionButton = options.order_list.get_child(0).get_node("God")
	var greyed_ok := true
	for index in range(playable.size()):
		var elsewhere: bool = _settings().custom_order.slice(1).has(playable[index])
		if first_picker.is_item_disabled(index) != elsewhere:
			greyed_ok = false
	_check(greyed_ok, "a slot's picker greys out every god already in another slot")
	_apply({"trials": 3, "order_mode": "custom", "custom_order": _strings(_settings().custom_order)})
	_check(_settings().custom_order == before.slice(0, 3), "fewer trials cut rows from the end")

	# A repeat (from a sync or an old file): warned about, and START is blocked.
	_apply({"trials": 3, "order_mode": "custom", "custom_order": ["mayari", "mayari", "tala"]})
	await _frames(1)
	_check(_settings().custom_order == [&"mayari", &"mayari", &"tala"], "the host's repeat stays on screen instead of being changed")
	_check(options.warning_label.visible, "a repeat shows a warning")
	_check(lobby.start_game_button.disabled, "a repeat disables START")
	_network.start_game()
	_check(not _network._game_in_progress, "start_game refuses a run with a repeat")
	options._on_slot_picked(playable.find(&"tala"), 1)
	_check(_settings().custom_order == [&"mayari", &"tala", &"tala"], "the dropdown changes one slot")
	await _frames(1)
	_check(options.warning_label.text.contains("already plays in trial 2") and lobby.start_game_button.disabled,
		"a repeat that is not back to back is still a repeat (%s)" % options.warning_label.text)
	options._on_slot_picked(playable.find(&"apolaki"), 2)
	_check(not options.warning_label.visible and not lobby.start_game_button.disabled, "fixing it clears the warning and enables START")

	# --- RESET -------------------------------------------------------------------------
	_apply({"trials": 7, "order_mode": "custom", "trial_time": 150.0, "due_step": 1500, "intro_mode": "short"})
	options._on_reset_pressed()
	_check(_settings().to_dict() == RunSettings.defaults().to_dict(), "RESET restores the defaults")

	# --- STARTER SKILLS ----------------------------------------------------------------
	_check(RunSettings.defaults().starter_mode == RunSettings.STARTER_OFF, "STARTER SKILLS is off by default")
	_check(not lobby.build_card.visible, "...with no CUSTOM BUILD card")
	options.starter_option.item_selected.emit(1)
	_check(_settings().starter_mode == RunSettings.STARTER_RANDOM, "picking RANDOM turns the random starters on")
	_check(not lobby.build_card.visible, "...with no build card (the deal is random)")
	_check(lobby.run_summary_label.text.ends_with("random starters"),
		"...and the run summary says so (%s)" % lobby.run_summary_label.text)
	options.starter_option.item_selected.emit(2)
	_check(_settings().starter_mode == RunSettings.STARTER_CUSTOM, "picking CUSTOM turns custom builds on")
	_check(lobby.build_card.visible, "...and the CUSTOM BUILD card appears below THE RUN")
	_check(lobby._build_buttons.size() == 2 and lobby._build_names.size() == 2, "the card holds two skill boxes (E and Q)")
	var default_pair: Array = _network.my_build_favors()
	_check(default_pair[0].id == &"half_vision" and default_pair[1].id == &"siblings_compromise",
		"an unpicked build opens with Mayari's own E and Q")
	_check(lobby._build_names[0].text == "Half Vision" and lobby._build_names[1].text == "Sibling's Compromise",
		"...and the boxes name them (%s + %s)" % [lobby._build_names[0].text, lobby._build_names[1].text])
	_check(lobby.run_summary_label.text.ends_with("custom builds"),
		"...the summary saying custom builds (%s)" % lobby.run_summary_label.text)
	# The popup: every E the pool offers, and a press picks one.
	lobby._open_build_picker(GodFavor.Slot.E)
	_check(lobby._picker.visible, "a box opens the all-skills popup")
	_check(lobby._picker_title.text == "YOUR E", "...titled for the slot it edits (%s)" % lobby._picker_title.text)
	var e_pool := RunSettings.starter_pool(GodFavor.Slot.E)
	_check(lobby._picker_grid.get_child_count() == e_pool.size(), "the popup shows every E skill (%d)" % e_pool.size())
	var shown_es := {}
	for card in lobby._picker_grid.get_children():
		shown_es[str(card.text).get_slice("\n", 1)] = true
	_check(shown_es.size() == e_pool.size(), "...each one once")
	lobby._pick_build(GodFavor.Slot.E, &"let_us_light_your_way")
	_check(not lobby._picker.visible, "picking one closes the popup")
	_check(_network.custom_builds.get(1, {}).get("e", &"") == &"let_us_light_your_way",
		"the pick reaches this player's build")
	_network.choose_custom_build(GodFavor.Slot.Q, &"unswerved_unbothered")
	var mine: Array = _network.my_build_favors()
	_check(mine[0].id == &"let_us_light_your_way" and mine[1].id == &"unswerved_unbothered",
		"the two boxes hold this player's own E and Q")
	_check(lobby._build_buttons[0].icon == mine[0].icon and lobby._build_buttons[1].icon == mine[1].icon,
		"...and the boxes wear those skills' icons")
	# Builds are not shared: a second mortal can hold a different pair.
	_network._set_custom_build(2, GodFavor.Slot.E, &"the_west_wind")
	_network._set_custom_build(2, GodFavor.Slot.Q, &"mustve_been_the_wind")
	var rival: Array = _network.build_favors(2)
	_check(rival[0].id == &"the_west_wind" and rival[1].id == &"mustve_been_the_wind",
		"another mortal can hold a different build")
	var kept: Array = _network.build_favors(1)
	_check(kept[0].id == &"let_us_light_your_way" and kept[1].id == &"unswerved_unbothered",
		"...without touching this player's")
	# The host only accepts a skill the slot can actually start with.
	_network._set_custom_build(1, GodFavor.Slot.E, &"unswerved_unbothered")
	_check(_network.build_favors(1)[0].id == &"let_us_light_your_way", "an E box refuses a Q skill")
	_network._set_custom_build(1, GodFavor.Slot.E, &"not_a_favor")
	_check(_network.build_favors(1)[0].id == &"let_us_light_your_way", "...and an unknown one")
	_check(RunSettings.starter_favor(GodFavor.Slot.Q, &"unswerved_unbothered") != null
		and RunSettings.starter_favor(GodFavor.Slot.E, &"unswerved_unbothered") == null,
		"a starter lookup finds only the skills its slot can start with")
	options.starter_option.item_selected.emit(0)
	_check(_settings().starter_mode == RunSettings.STARTER_OFF and not lobby.build_card.visible,
		"picking OFF hides the card again")
	_network.custom_builds.clear()
	var deal_ok := true
	var unique_ok := true
	var pairs_seen := {}
	var six := [1, 2, 3, 4, 5, 6]
	for seed_value in range(200):
		var deal := RunSettings.starter_deal_for(seed_value, six)
		var es := {}
		var qs := {}
		for id in six:
			var pair: Array = deal.get(id, [])
			if pair.size() != 2 or pair[0].slot != GodFavor.Slot.E or pair[1].slot != GodFavor.Slot.Q:
				deal_ok = false
				continue
			if pair[0].god_id == pair[1].god_id or pair[0].god_id == Gods.BATHALA or pair[1].god_id == Gods.BATHALA:
				deal_ok = false
			if pair[0].requires_god_id() != &"" or pair[1].requires_god_id() != &"" \
				or pair[0].requires_favor_id() != &"" or pair[1].requires_favor_id() != &"":
				deal_ok = false
			es[pair[0].id] = true
			qs[pair[1].id] = true
			pairs_seen["%s|%s" % [pair[0].id, pair[1].id]] = true
		if es.size() != 6 or qs.size() != 6:
			unique_ok = false
	_check(deal_ok, "every seed deals one god's E and a DIFFERENT god's Q, never Bathala's")
	_check(unique_ok, "six mortals open with six different Es and six different Qs")
	_check(pairs_seen.size() > 20, "...and the deals really vary (%d pairs in 200 seeds)" % pairs_seen.size())
	var deal_a := RunSettings.starter_deal_for(12345, [3, 1, 2])
	var deal_b := RunSettings.starter_deal_for(12345, [2, 3, 1])
	_check(deal_a[1][0].id == deal_b[1][0].id and deal_a[2][1].id == deal_b[2][1].id
		and deal_a[3][0].id == deal_b[3][0].id,
		"the same seed deals the same pairs to the same mortals, in any order")
	var carried := RunSettings.from_dict({"starter_mode": "custom", "starter_seed": 777})
	_check(carried.starter_mode == RunSettings.STARTER_CUSTOM and carried.starter_seed == 777,
		"a custom setup survives to_dict / from_dict")
	var old_file := RunSettings.from_dict({"starter_skills": true, "starter_seed": 5})
	_check(old_file.starter_mode == RunSettings.STARTER_RANDOM, "an old random-starters file loads as RANDOM")
	_apply(RunSettings.defaults().to_dict())

	# --- the five loadouts -----------------------------------------------------------------
	_check(RunSettings.PRESETS.size() == 5, "there are five loadouts")
	_check(options.presets.get_child_count() == RunSettings.PRESETS.size(),
		"one button per loadout (%d)" % options.presets.get_child_count())
	var named_ok := true
	for entry in RunSettings.PRESETS:
		var button: Button = options.presets.get_node_or_null("Preset_%s" % entry["id"])
		named_ok = named_ok and button != null and button.text == str(entry["name"]).to_upper()
	_check(named_ok, "every loadout is named on its button")
	var expected := {
		"default": [90.0, 30.0, RunSettings.STARTER_OFF],
		"long": [120.0, 40.0, RunSettings.STARTER_OFF],
		"short": [60.0, 20.0, RunSettings.STARTER_OFF],
		"random": [90.0, 30.0, RunSettings.STARTER_RANDOM],
		"strategic": [90.0, 40.0, RunSettings.STARTER_CUSTOM],
	}
	var loadout_ok := true
	var house_ok := true
	var light_ok := true
	for entry in RunSettings.PRESETS:
		var preset_id := str(entry["id"])
		(options.presets.get_node("Preset_%s" % preset_id) as Button).pressed.emit()
		var run := _settings()
		var want: Array = expected[preset_id]
		loadout_ok = loadout_ok and is_equal_approx(run.trial_time, want[0]) \
			and is_equal_approx(run.prep_time, want[1]) and run.starter_mode == want[2]
		house_ok = house_ok and run.trials == 4 and run.order_mode == RunSettings.ORDER_RANDOM \
			and run.intro_mode == RunSettings.INTRO_FULL and run.opening_cutscene == RunSettings.OPENING_SKIP \
			and run.god_blitz_mode and run.camera_mode == RunSettings.CAMERA_ARENA \
			and run.due_step == GodMatch.MILESTONE_STEP
		light_ok = light_ok and run.active_preset() == preset_id \
			and (options.presets.get_node("Preset_%s" % preset_id) as Button) \
				.get_theme_color("font_color") == UITokens.GOLD
	_check(loadout_ok, "each loadout sets its own clock, rest and starting build")
	_check(house_ok, "...on top of the house rules they all share (random order, full intros, no cutscene, blitz, whole arena)")
	_check(light_ok, "the loadout in use is lit gold, and only it")
	_check(options.preset_note.get_theme_color("font_color") == UITokens.GOLD
		and options.preset_note.text == RunSettings.preset_info("strategic")["note"],
		"the sheet explains the loadout in use (%s)" % options.preset_note.text)
	options.prep_option.item_selected.emit(1)
	_check(_settings().active_preset() == "" and options.preset_note.text.begins_with("Custom setup"),
		"changing one row drops back to a custom setup")
	var default_button: Button = options.presets.get_node("Preset_default")
	_check(default_button.get_theme_color("font_color") != UITokens.GOLD,
		"...and no loadout stays lit")
	(default_button as Button).pressed.emit()
	_check(_settings().active_preset() == "default" and is_equal_approx(_settings().prep_time, 30.0),
		"Default Settings is a 0:30 rest again")
	var strategic := RunSettings.from_dict({"trial_time": 90.0, "prep_time": 40.0, "starter_mode": RunSettings.STARTER_CUSTOM})
	_check(strategic.active_preset() == "" and strategic.to_dict() != RunSettings.defaults().to_dict(),
		"the same clock and rest without the house rules is still custom")
	_apply(RunSettings.defaults().to_dict())

	# --- a client cannot change anything --------------------------------------------------
	_apply({"trials": 5, "order_mode": "custom"})
	var locked := _settings().to_dict()
	lobby.is_host = false
	options.open(false)
	await _frames(1)
	var all_disabled: bool = options.minus_button.disabled and options.plus_button.disabled \
		and options.random_box.disabled and options.custom_box.disabled and options.time_option.disabled \
		and options.due_option.disabled and options.intro_option.disabled and options.reset_button.disabled \
		and options.prep_option.disabled and options.camera_option.disabled \
		and options.blitz_box.disabled and options.starter_option.disabled
	for button in options.presets.get_children():
		all_disabled = all_disabled and (button as Button).disabled
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
	options.prep_option.item_selected.emit(4)
	options.camera_option.item_selected.emit(1)
	options.starter_option.item_selected.emit(1)
	for button in options.presets.get_children():
		(button as Button).pressed.emit()
	options._on_reset_pressed()
	_check(_settings().to_dict() == locked, "a client cannot change any setting")
	# ...but the build card is the player's own: a non-host can still pick.
	_apply({"starter_mode": "custom"})
	await _frames(1)
	_check(lobby.build_card.visible, "a non-host sees the CUSTOM BUILD card")
	lobby._pick_build(GodFavor.Slot.E, &"the_west_wind")
	_check(_network.my_build_favors()[0].id == &"the_west_wind", "a non-host can still pick its own build")
	_network.custom_builds.clear()

	# --- a synced setup reaches a client's lobby -------------------------------------------
	_network.rpc_sync_run_settings({"trials": 4, "order_mode": "random", "trial_time": 60.0, "due_step": 750, "intro_mode": "full"})
	await _frames(1)
	_check(_settings().trials == 4 and _settings().trial_time == 60.0, "a client adopts the setup the host sends")
	_check(lobby.run_summary_label.text == "4 trials + Bathala   |   Random order   |   60s", "the lobby summary follows it (%s)" % lobby.run_summary_label.text)
	_check(options.trials_value.text == "4", "so does the open panel")
	lobby.is_host = true
	options.close()

	# --- trial length, God's Due step and intros reach the run ---------------------------
	_apply({"trials": 3, "order_mode": "random", "trial_time": 150.0, "due_step": 1500, "intro_mode": "short",
		"prep_time": 45.0, "starter_mode": "random", "starter_seed": 4242})
	_network.rpc_sync_trial_order([&"mayari", &"tala", &"apolaki", &"bathala"])
	var game: Control = load("res://scenes/Game.tscn").instantiate()
	view.add_child(game)
	await _frames(4)
	_check(game.arena != null and is_equal_approx(game.arena.trial_time, 150.0), "the trial length reaches the arena")
	_check(game.arena != null and game.arena.rules.milestone_step == 1500, "the God's Due step reaches GodMatch")
	_check(game.arena != null and not game.arena.first_visit, "SHORT intros skip the full intro even on a first visit")
	var mortal = game.arena.rules.local()
	var deal := RunSettings.starter_deal_for(4242, game.arena.rules.mortals.keys())
	var dealt: Array = deal.get(mortal.id, [])
	_check(dealt.size() == 2 and mortal.favor_in_slot(GodFavor.Slot.E) != null
		and mortal.favor_in_slot(GodFavor.Slot.Q) != null,
		"a RANDOM starter run opens with an E and a Q in hand")
	_check(mortal.favor_in_slot(GodFavor.Slot.E).id == dealt[0].id
		and mortal.favor_in_slot(GodFavor.Slot.Q).id == dealt[1].id,
		"...the pair the run dealt this mortal (%s + %s)" % [
			str(mortal.favor_in_slot(GodFavor.Slot.E).id), str(mortal.favor_in_slot(GodFavor.Slot.Q).id)])
	var sets := {}
	for id in game.arena.rules.mortals.keys():
		var pair: Array = deal.get(int(id), [])
		if pair.size() == 2:
			sets["%s|%s" % [pair[0].id, pair[1].id]] = true
	_check(sets.size() == game.arena.rules.mortals.size() and sets.size() > 1,
		"every mortal in the run opens with its own pair (%d mortals)" % game.arena.rules.mortals.size())
	mortal.favor = 0
	game.arena.rules.add_favor(1499, "test")
	_check(mortal.due == 0, "1499 FAVOR is not yet a God's Due at 1500")
	game.arena.rules.add_favor(1, "test")
	_check(mortal.due == 1, "1500 FAVOR is")
	game._on_trial_complete()
	await _frames(4)
	_check(game.arena is PrepArea and is_equal_approx(game.arena.prep_time, 45.0) and game.arena._time_left > 44.0,
		"the prep time reaches the rest (%s)" % game.timer_label.text)
	game.queue_free()
	await _frames(2)
	# CUSTOM: each mortal opens with its own lobby build, not a shared pair.
	_network.custom_builds.clear()
	_network._set_custom_build(1, GodFavor.Slot.E, &"the_west_wind")
	_network._set_custom_build(1, GodFavor.Slot.Q, &"unswerved_unbothered")
	_network._set_custom_build(2, GodFavor.Slot.E, &"let_us_light_your_way")
	_network._set_custom_build(2, GodFavor.Slot.Q, &"mustve_been_the_wind")
	_apply({"intro_mode": "full", "trial_time": 90.0, "starter_mode": "custom"})
	var second: Control = load("res://scenes/Game.tscn").instantiate()
	view.add_child(second)
	await _frames(4)
	_check(second.arena != null and second.arena.first_visit, "FULL intros keep the full intro on a first visit")
	_check(second.arena != null and is_equal_approx(second.arena.trial_time, 90.0), "a 90s setting gives a 90s round")
	var custom_mortal = second.arena.rules.local()
	_check(custom_mortal.favor_in_slot(GodFavor.Slot.E) != null
		and custom_mortal.favor_in_slot(GodFavor.Slot.E).id == &"the_west_wind"
		and custom_mortal.favor_in_slot(GodFavor.Slot.Q) != null
		and custom_mortal.favor_in_slot(GodFavor.Slot.Q).id == &"unswerved_unbothered",
		"a CUSTOM run opens with this player's own E and Q (%s + %s)" % [
			str(custom_mortal.favor_in_slot(GodFavor.Slot.E).id) if custom_mortal.favor_in_slot(GodFavor.Slot.E) != null else "none",
			str(custom_mortal.favor_in_slot(GodFavor.Slot.Q).id) if custom_mortal.favor_in_slot(GodFavor.Slot.Q) != null else "none"])
	var own_ok := true
	for id in second.arena.rules.mortals.keys():
		var other = second.arena.rules.mortals[id]
		var wanted: Array = _network.build_favors(int(id))
		if other.favor_in_slot(GodFavor.Slot.E) == null or other.favor_in_slot(GodFavor.Slot.Q) == null \
			or other.favor_in_slot(GodFavor.Slot.E).id != wanted[0].id \
			or other.favor_in_slot(GodFavor.Slot.Q).id != wanted[1].id:
			own_ok = false
	_check(own_ok and second.arena.rules.mortals.size() > 1,
		"every mortal opens with its own CUSTOM build (%d mortals)" % second.arena.rules.mortals.size())
	second.queue_free()
	await _frames(2)
	_network.custom_builds.clear()
	_network.trial_order_ids.clear()

	# --- the host's last setup loads back ------------------------------------------------------
	_apply({"trials": 5, "order_mode": "custom", "trial_time": 120.0, "due_step": 750, "intro_mode": "short",
		"prep_time": 60.0, "camera_mode": "follow"})
	var saved := _settings().to_dict()
	_network.save_host_settings()
	_apply(RunSettings.defaults().to_dict())
	_network.load_host_settings()
	_check(_settings().to_dict() == saved, "saved host settings load back")
	var cfg := ConfigFile.new()
	cfg.set_value("run", "settings", {"trials": 42, "order_mode": "custom", "custom_order": ["bathala", "nobody", "tala", "tala"],
		"trial_time": 77.0, "due_step": 3, "intro_mode": "loud", "prep_time": 5.0, "camera_mode": "drone"})
	cfg.save(TEMP_SETTINGS)
	_network.load_host_settings()
	var loaded := _settings()
	_check(loaded.trials == 6 and loaded.trial_time == 90.0 and loaded.due_step == 1000 and loaded.intro_mode == "full"
		and loaded.prep_time == 20.0 and loaded.camera_mode == "arena", "a bad saved file is validated on load")
	_check(not loaded.custom_order.has(Gods.BATHALA) and loaded.custom_order.size() == 6 and loaded.repeat_slots().is_empty(),
		"...and its order is cleaned (no Bathala, no unknown god, no repeat)")
	# A file saved when a run could hold 9 trials (and gods came round again).
	cfg.set_value("run", "settings", {"trials": 9, "order_mode": "custom", "trial_time": 90.0, "due_step": 1000, "intro_mode": "full",
		"custom_order": ["mayari", "tala", "apolaki", "hanan", "mayari", "tala", "apolaki", "hanan", "mayari"]})
	cfg.save(TEMP_SETTINGS)
	_network.load_host_settings()
	loaded = _settings()
	_check(loaded.trials == 6 and loaded.custom_order.size() == 6 and _unique(loaded.custom_order) == 6,
		"an old 9-trial setup loads as 6 trials, every god once (%s)" % str(loaded.custom_order))
	_check(loaded.custom_order.slice(0, 4) == [&"mayari", &"tala", &"apolaki", &"hanan"], "...keeping the gods it already had in order")
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
