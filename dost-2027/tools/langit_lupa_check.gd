extends SceneTree

# Validation: Mapulon & Ikapati's Langit Lupa. The rhyme picks the richest mortal
# as Taya (ties random); mortals + 1 Langit, shared by any number of runners for
# as long as they like; the Taya's chant roots it and blocks tags, breaks on a
# wrong key or a missed beat, and on ALIS! closes each runner's Langit to them
# only, shoves off whoever stays and pays the Taya; the host ignores chant
# messages that are not the Taya's or out of order; the Taya is never safe and is
# pushed off a Langit; crossings, close calls and streaks pay; a tag moves
# tag_steal; tagged_mercy stops a tag-back; seasons move every Langit (clear of
# the UI strip and the Taya) and reopen them; Time as Taya, its drain and the
# payout (shown in the results' bonus); the 60s round; and the dash (only here).
# Run: godot --headless --path <project> -s res://tools/langit_lupa_check.gd

const DT := 0.25  # exact in binary, so four steps are exactly one second
const FAR := Vector2(1080, 560)

var _arena: LangitLupaArena
var _rules: GodMatch
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
	_arena = load("res://scenes/gods/mapulon_ikapati/LangitLupaArena.tscn").instantiate()
	view.add_child(_arena)
	await _frames(2)
	_rules = _arena.rules
	var guard := 0
	while _arena.dialogue.is_active() and guard < 40:
		_arena.dialogue.advance()
		guard += 1
	_check(_arena.god.id == Gods.MAPULON_IKAPATI, "the arena belongs to Mapulon & Ikapati")
	_check(not _arena.separate_players() and _arena.shares_mortal_positions(), "Langit Lupa is a shared field")
	_check(is_equal_approx(_arena.trial_time, 60.0), "a standalone round lasts 60s")
	_check(_arena._bots.size() == 2 and not _rules.simulate_rivals, "solo: two bots take the rivals' places (and the quiet FAVOR trickle is off)")

	# --- the field is sized for the mortals playing -------------------------------------
	var drawn: Rect2 = _arena.field_root.authored_rect()
	_check(is_equal_approx(_arena._field.size.x, _arena.field_size_3p.x) and _arena._field.get_center().is_equal_approx(drawn.get_center()),
		"three mortals play on the 3-mortal field, centred where the Border is drawn (%s)" % str(_arena._field))
	_check(drawn.is_equal_approx(_arena._field), "the Border is redrawn around it (%s)" % str(drawn))
	_check(_arena.player.bounds == _arena._field, "the mortal walks inside it")
	for count in [2, 3, 4]:
		var wanted: Vector2 = _arena.field_size_for(count)
		_check(wanted.x == [0, 0, 560.0, 640.0, 720.0][count], "%d mortals -> %d wide" % [count, int(wanted.x)])
	_arena.field_size_3p = Vector2(600, 200)
	_arena._size_field()
	_check(_arena._field.size == Vector2(600, 200), "a height in field_size_Np replaces the drawn one (%s)" % str(_arena._field.size))
	_arena.field_size_3p = Vector2(640, 0)
	_arena._size_field()
	_check(is_equal_approx(_arena._field.size.y, drawn.size.y), "...and 0 keeps the drawn Border's height")
	# a client takes the host's field and redraws its Border
	var client_field := Rect2(400, 360, 500, 200)
	_arena._apply_layout({"field": client_field})
	_check(_arena.field_root.authored_rect().is_equal_approx(client_field) and _arena.player.bounds == client_field,
		"a client draws and walks the host's field (%s)" % str(_arena.field_root.authored_rect()))
	_arena._size_field()

	# --- the countdown is the rhyme, and the rules card shows on a first visit ----------
	_arena._start_countdown()
	_check(_arena._langits.size() == 4, "(the countdown lays out the Langit: 3 mortals -> 4)")
	_arena._show_banner("3", Color.WHITE)
	var first: String = _arena.hud.banner_label.text
	_arena._show_banner("2", Color.WHITE)
	var second: String = _arena.hud.banner_label.text
	_arena._show_banner("1", Color.WHITE)
	_check(first == "LANGIT..." and second == "LUPA..." and _arena.hud.banner_label.text == "IMPYERNO!",
		"the 3-2-1 is the rhyme: LANGIT... LUPA... IMPYERNO! (%s / %s / %s)" % [first, second, _arena.hud.banner_label.text])
	_arena._refresh_hud(0.0)
	_check(_arena.rules_card.visible, "the rules card shows through the countdown of a first visit")

	# --- the first Taya ----------------------------------------------------------
	_set_favor(100, 500, 200)
	_arena._start_trial()
	_check(_arena.taya_id() == 2, "the mortal with the most FAVOR starts as Taya")
	_check(_arena.hud.banner_label.text == "TAYA: MORTAL 2!", "the rhyme lands on them: \"TAYA: MORTAL 2!\" (%s)" % _arena.hud.banner_label.text)
	_arena._refresh_hud(0.0)
	_check(not _arena.rules_card.visible, "the rules card is gone at GO")
	var seen := {}
	for attempt in range(40):
		_set_favor(100, 500, 500)
		_arena._taya = -1
		_arena._start_trial()
		seen[_arena.taya_id()] = true
	_check(seen.size() == 2 and seen.has(2) and seen.has(3), "a tie for the most FAVOR goes to one of the tied, at random")
	_set_favor(100, 500, 200)
	_rules.mortal(2).granary = 400
	_rules.mortal(2).favor = 150
	_arena._start_trial()
	_check(_arena.taya_id() == 3, "FAVOR stored in Kamalig does not count towards the first Taya")
	_rules.mortal(2).granary = 0

	# From here the bots stand where the check puts them.
	for bot in _arena._bots.values():
		bot.queue_free()
	_arena._bots.clear()

	# --- Langit ------------------------------------------------------------------------
	for mortals in [2, 3, 4]:
		_check(_arena.langit_count(mortals) == mortals + 1, "%d mortals -> %d Langit" % [mortals, mortals + 1])
	var spot := Vector2(500, 300)
	var other_spot := Vector2(800, 300)
	_reset(3, [spot, other_spot])
	_put(1, spot + Vector2(-12, 0))
	_put(2, spot + Vector2(12, 5))
	_check(_arena.is_safe(1) and _arena.is_safe(2), "two runners can be safe on the same Langit")
	_put(2, spot + Vector2(_arena.langit_size.x * 0.5 + 4.0, 0))
	_check(_arena.is_safe(2), "standing on the edge (inside langit_safe_margin) still counts")
	_put(2, spot + Vector2(12, 5))
	_put(3, spot + Vector2(0, 50))  # the Taya, right next to them
	for step in range(20):
		_arena.arena_rules_tick(DT)
	_check(_arena.is_safe(1) and _arena.is_safe(2) and _arena.taya_id() == 3, "...and they stay safe there, with no chant, for as long as they like (5s)")
	_put(3, spot)
	_check(not _arena.is_safe(3), "the Taya never counts as safe, even on a Langit")
	var pushed: Vector2 = _arena._push_out(spot + Vector2(10, 4))
	var rect: Rect2 = _arena.langit_rect(0)
	_check(not rect.has_point(pushed) and pushed.distance_to(spot + Vector2(10, 4)) <= rect.size.y * 0.5 + 1.0,
		"a Taya inside a Langit is pushed back out to the nearest edge (%s)" % str(pushed))
	_reset(1, [spot, other_spot])
	_put(1, spot)
	_arena._process(0.0)
	_check(not rect.has_point(_arena.player.global_position), "...on the Taya's own screen, every frame")

	# --- the chant: rooted, no tags, no dash ----------------------------------------------
	_reset(1, [spot, other_spot])
	_put(1, Vector2(650, 450))
	_put(2, Vector2(660, 450))  # on the Lupa, within reach
	_put(3, FAR)
	_check(_arena.start_chant(), "the Taya can start a chant")
	_check(_arena._chanting and _arena.player.locked, "a chant roots the Taya")
	_arena._check_tag()
	_check(_arena.taya_id() == 1, "a chanting Taya cannot tag")
	_check(not _arena.try_dash(), "...nor dash")
	_check(not _arena.start_chant(), "a second chant cannot start over the first")
	# a wrong key breaks it
	_arena.chant_key((_arena._my_chant[0] + 1) % 4)
	_check(not _arena._chanting and _arena._chant_broken == 0, "a wrong key breaks the chant (on its first word)")
	_check(_arena._chant_cd > 0.0 and is_equal_approx(_arena._chant_cd, _arena.chant_cooldown), "...and the cooldown starts anyway")
	_check(_arena.player.locked and _arena._root_left > 0.0, "the Taya stumbles, still rooted")
	_arena._check_tag()
	_check(_arena.taya_id() == 1, "...and still cannot tag")
	_arena._tick_my_chant(_arena.chant_fail_stun + 0.01)
	_arena._tick_chant(_arena.chant_fail_stun + 0.01)
	_check(not _arena.player.locked, "after the stumble the Taya moves again")
	_check(not _arena.start_chant(), "a chant waits for the cooldown")
	# a missed beat breaks it
	_arena._chant_cd = 0.0
	_check(_arena.start_chant(), "(a new chant once the cooldown is ready)")
	_arena.chant_key(_arena._my_chant[0])
	_check(_arena._chant_step == 1, "a right key lights the next word")
	_arena._tick_my_chant(_arena.chant_beat - 0.1)
	_check(_arena._chanting, "the beat is not missed yet")
	_arena._tick_my_chant(0.2)
	_check(not _arena._chanting and _arena._chant_broken == 1 and _arena._chant_cd > 0.0, "a missed beat breaks it (on the word it was on) and starts the cooldown")
	_arena._tick_my_chant(1.0)
	_arena._tick_chant(1.0)
	# RIGHT CLICK, and never while a dialogue or the God's Due menu is open
	_arena._chant_cd = 0.0
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	_arena.dialogue.show_lines([{"speaker": "TEST", "color": Color.WHITE, "text": "A LINE"}])
	_arena._input(right)
	_check(not _arena._chanting, "RIGHT CLICK does not chant while a dialogue is open")
	_arena.dialogue.close_now()
	_arena._toggle_due_menu()
	_arena._input(right)
	_check(not _arena._chanting, "...nor while the God's Due menu is open")
	_arena.due_menu.close()
	_arena._input(right)
	_check(_arena._chanting, "during play RIGHT CLICK starts the chant")
	for word in range(_arena.chant_length):
		var key := InputEventAction.new()
		key.action = LangitLupaArena.MOVE_ACTIONS[_arena._my_chant[word]]
		key.pressed = true
		_arena._input(key)
	_check(not _arena._chanting and _arena._chant_broken == -1 and _arena._chant_cd > 0.0 and not _arena.player.locked,
		"the move keys answer the prompts: a full chant ends it, unroots the Taya and starts the cooldown")

	# --- the chant from a remote Taya: the host checks every message ---------------------------
	_reset(2, [spot, other_spot])
	_put(2, Vector2(650, 300))     # the Taya, between the two Langit
	_put(1, spot)                  # our mortal sits on Langit 0
	_put(3, Vector2(650, 500))     # on the Lupa
	_set_favor(500, 500, 500)
	_arena._on_chant_message(3, "start", 0)
	_check(not _arena._chanting, "the host ignores a chant from a mortal who is not the Taya")
	_arena._season_timer = _arena.shift_warning * 0.5
	_arena._on_chant_message(2, "start", 0)
	_check(not _arena._chanting, "a chant cannot start during the crumble warning")
	_arena._season_timer = 1000.0
	_arena._on_chant_message(2, "start", 0)
	_check(_arena._chanting, "the Taya's start is accepted")
	_arena._on_chant_message(2, "step", 2)
	_check(_arena._chant_step == 0, "a step out of order is ignored")
	_arena._on_chant_message(3, "step", 1)
	_check(_arena._chant_step == 0, "so is a step from somebody else")
	_arena._on_chant_message(2, "step", 1)
	_arena._on_chant_message(2, "result", 1)
	_check(not _arena._chanting and _arena.swap_left(1) == 0.0 and _arena._chant_cd > 0.0,
		"a \"success\" that skipped words is a broken chant, not an ALIS")
	_arena._chant_cd = 0.0
	_arena._root_left = 0.0
	_arena._on_chant_message(2, "start", 0)
	for word in range(1, _arena.chant_length + 1):
		_arena._on_chant_message(2, "step", word)
	_arena._on_chant_message(2, "result", 1)
	_check(is_equal_approx(_arena.swap_left(1), _arena.swap_time), "ALIS! gives the runner on a Langit swap_time to leave")
	_check(_arena.is_closed_for(1, 0) and not _arena.is_closed_for(3, 0), "their Langit is closed to them, and to nobody else")
	_check(_arena.langit_index_at(3, spot) == 0 and _arena.langit_index_at(1, spot) == -1, "...it still counts for the others")
	_check(_arena.swap_left(3) == 0.0 and not _arena._closed.has(3), "a runner who was on the Lupa is left alone")
	_check(_rules.mortal(2).favor == 500 + _arena.chant_favor, "the Taya is paid chant_favor per runner forced off (%d)" % _rules.mortal(2).favor)
	_check(_arena.is_safe(1), "while the swap clock runs the runner is still safe")
	_arena._on_chant_message(2, "start", 0)
	_check(not _arena._chanting, "the next chant waits for the cooldown")
	_arena._tick_swaps(_arena.swap_time + 0.01)
	_arena._tick_swaps(0.01)
	_check(not _arena.is_safe(1) and _arena.player.is_stunned(), "whoever stays on it after swap_time is shoved off, and no longer safe")
	_put(1, other_spot)
	_check(_arena.is_safe(1), "the other Langit is still open to them")
	_arena._turn_season()
	_check(_arena._closed.is_empty() and _arena._swap.is_empty(), "a season change opens the closed Langit again")

	# --- crossings, close calls, streaks, the catch --------------------------------------------------
	_reset(3, [spot, other_spot])
	_set_favor(1000, 1000, 1000)
	_put(3, FAR)
	_put(1, spot)
	_arena._tick_crossings()
	var favor: int = _rules.mortal(1).favor
	_put(1, Vector2(650, 450))
	_arena._tick_crossings()
	_put(1, spot)
	_arena._tick_crossings()
	_check(_rules.mortal(1).favor == favor, "stepping back onto the Langit you left pays nothing")
	_put(1, Vector2(650, 450))
	_arena._tick_crossings()
	_put(1, other_spot)
	_arena._tick_crossings()
	var streak: int = _arena.streak_of(1)
	_check(_rules.mortal(1).favor == favor + _arena.crossing_favor + (streak - 1) * _arena.streak_step,
		"a crossing to a new Langit pays crossing_favor (+ the streak) (%d)" % (_rules.mortal(1).favor - favor))
	favor = _rules.mortal(1).favor
	_put(1, Vector2(650, 450))
	_arena._tick_crossings()
	_put(3, Vector2(650, 450 + _arena.close_call_radius - 10.0))
	_arena._tick_crossings()
	_put(3, FAR)
	_put(1, spot)
	_arena._tick_crossings()
	_check(_rules.mortal(1).favor == favor + _arena.crossing_favor + streak * _arena.streak_step + _arena.close_call_bonus,
		"a close call on the way adds close_call_bonus, and the streak adds streak_step (%d)" % (_rules.mortal(1).favor - favor))
	_check(_arena.streak_of(1) == streak + 1, "the streak grows with each crossing")
	_arena._streak[1] = 20
	favor = _rules.mortal(1).favor
	_put(1, Vector2(650, 450))
	_arena._tick_crossings()
	_put(1, other_spot)
	_arena._tick_crossings()
	_check(_rules.mortal(1).favor == favor + _arena.crossing_favor + _arena.streak_cap, "the streak bonus stops at streak_cap")
	_put(1, Vector2(650, 450))
	_put(3, Vector2(660, 450))
	_arena._tagback = 0.0
	_arena._invuln.clear()
	var runner_before: int = _rules.mortal(1).favor
	var taya_before: int = _rules.mortal(3).favor
	_arena._check_tag()
	_check(_arena.taya_id() == 1, "a touch on the Lupa passes Taya")
	_check(_arena.streak_of(1) == 0, "being tagged resets the streak")
	_check(_rules.mortal(1).favor == runner_before - _arena.tag_steal and _rules.mortal(3).favor == taya_before + _arena.tag_steal,
		"a tag moves tag_steal FAVOR from the runner to the Taya")
	_check(is_equal_approx(_arena._tagback, _arena.tagback_immunity), "the new Taya gets the tag-back buffer")
	_arena._check_tag()
	_check(_arena.taya_id() == 1, "the new Taya cannot tag straight back")
	_arena._tagback = 0.0
	_arena._check_tag()
	_check(_arena.taya_id() == 1, "and once its buffer is over, tagged_mercy still keeps the old Taya safe")
	_arena._tick_invuln(_arena.tagged_mercy + 0.01)
	_arena._check_tag()
	_check(_arena.taya_id() == 3, "after it, the old Taya can be tagged again")
	_rules.mortal(1).favor = 25
	_rules.mortal(3).favor = 0
	_arena._tagback = 0.0
	_arena._invuln.clear()
	_arena._check_tag()
	_check(_arena.taya_id() == 1 and _rules.mortal(3).favor == 25, "the Taya gets only what the runner really lost (25 of 60)")
	_arena._place_marker()
	_check(_arena.taya_marker.visible, "the Taya wears a marker")

	# --- seasons ------------------------------------------------------------------------------------------
	_reset(1, [])
	_arena._place_langits()
	_arena._season_timer = _arena.season_interval
	var season: int = _arena._season
	var before: Array = _arena._langits.duplicate()
	_arena._tick_season(_arena.season_interval - _arena.shift_warning - 0.25)
	_check(not _arena.is_crumbling(), "no warning before the last shift_warning seconds (%.2fs left)" % _arena._season_timer)
	_arena._tick_season(0.5)
	_check(_arena.is_crumbling(), "...then the Langit shake")
	_arena._tick_season(0.5)
	_check(_arena._season == season, "still the same Langit just before the season turns")
	_arena._tick_season(0.5)
	_check(_arena._season == season + 1 and _arena._langits != before, "every season_interval they crumble and move to new spots")
	var placement_ok := true
	var spaced := 0
	var layouts := 0
	_rules.ensure_mortal(4, "MORTAL 4")
	_arena._size_field()  # (the host sizes the field for four, as at a real countdown)
	_check(is_equal_approx(_arena._field.size.x, _arena.field_size_4p.x), "four mortals play on the 4-mortal field (%s)" % str(_arena._field.size))
	for attempt in range(60):
		var taya_at := Vector2(randf_range(_arena._field.position.x, _arena._field.end.x), randf_range(_arena._field.position.y, _arena._field.end.y))
		_put(_arena.taya_id(), taya_at)
		_arena._place_langits()
		layouts += 1
		var all_spaced := true
		for index in range(_arena._langits.size()):
			var here: Rect2 = _arena.langit_rect(index)
			if _arena._langits[index].distance_to(taya_at) < _arena.taya_clearance:
				placement_ok = false
			if not _arena._field.encloses(here) or here.position.x < Arena.UI_STRIP_WIDTH:
				placement_ok = false
			for other in range(index + 1, _arena._langits.size()):
				if here.intersects(_arena.langit_rect(other)):
					placement_ok = false
				if _arena._langits[index].distance_to(_arena._langits[other]) < _arena.langit_spacing:
					all_spaced = false
		spaced += int(all_spaced)
	_check(_arena._langits.size() == 5, "with four mortals the field holds five Langit")
	_rules.remove_mortal(4)
	_arena._size_field()
	_check(placement_ok, "a Langit never lands near the Taya, off the field, in the UI strip or on another Langit")
	_check(spaced * 10 >= layouts * 9, "...and they are spread langit_spacing apart (%d of %d layouts)" % [spaced, layouts])

	# --- Time as Taya and the drain -------------------------------------------------
	_reset(1, [])
	_set_favor(1000, 1000, 1000)
	_put(1, Vector2(300, 120))
	_put(2, Vector2(1100, 560))
	_put(3, Vector2(700, 560))
	_arena._taya_time.clear()
	_arena._drain_pending.clear()
	_arena._drain_tick = 1.0
	for step in range(2):
		_arena.arena_rules_tick(DT)
	_check(is_equal_approx(_arena.taya_seconds(1), 0.5) and _arena.taya_seconds(2) == 0.0 and _arena.taya_seconds(3) == 0.0,
		"Time as Taya grows only for the Taya")
	_check(_rules.mortal(1).favor == 1000, "the drain is not banked every frame")
	for step in range(2):
		_arena.arena_rules_tick(DT)
	_check(_rules.mortal(1).favor == 990, "it lands once a second: -10 after 1s (%d)" % _rules.mortal(1).favor)
	for step in range(4):
		_arena.arena_rules_tick(DT)
	_check(_rules.mortal(1).favor == 980 and _rules.mortal(2).favor == 1000, "...and again after 2s, on the Taya only")
	_rules.mortal(1).favors.append(Gods.favor_by_id(&"waning_moon"))
	for step in range(4):
		_arena.arena_rules_tick(DT)
	_check(_rules.mortal(1).favor == 975, "it goes through lose_favor, so Waning Moon halves it (%d)" % _rules.mortal(1).favor)
	_rules.mortal(1).favors.clear()

	# --- the payout --------------------------------------------------------------------
	_arena._taya_time = {1: 5.0, 2: 10.0, 3: 20.0}
	var paid: Dictionary = _arena.payouts()
	_check(paid[1] == 600 and paid[2] == 350 and paid[3] == 100, "least time as Taya is paid most: 600 / 350 / 100 (%s)" % str(paid))
	_arena._taya_time = {1: 5.0, 2: 5.2, 3: 20.0}
	paid = _arena.payouts()
	_check(paid[1] == 600 and paid[2] == 600 and paid[3] == 100, "times within 0.25s tie and share the better payout (%s)" % str(paid))
	_rules.ensure_mortal(4, "MORTAL 4")
	_arena._taya_time = {1: 1.0, 2: 2.0, 3: 3.0, 4: 4.0}
	paid = _arena.payouts()
	_check(paid[1] == 600 and paid[2] == 433 and paid[3] == 267 and paid[4] == 100, "four places are spread evenly (%s)" % str(paid))
	_rules.remove_mortal(4)
	_arena._taya_time = {1: 5.0, 2: 10.0, 3: 20.0}
	_set_favor(0, 0, 0)
	var reasons: Array[String] = []
	_rules.favor_changed.connect(func(_id: int, _total: int, _delta: int, reason: String) -> void: reasons.append(reason))
	_arena._end_trial()
	var result: Dictionary = _arena._results.get(1, {})
	_check(_rules.mortal(1).favor == 600 and int(result.get("favor", 0)) == 600, "the payout is banked before the results are written")
	_check(reasons.has("Langit Lupa payout"), "...under the reason \"Langit Lupa payout\"")
	_check(int(result.get("bonus", 0)) == 600 and int(_arena._results.get(3, {}).get("bonus", 0)) == 100,
		"...and it shows in the results' bonus column (%s)" % str(result))

	# --- the 60s round through the game shell --------------------------------------------
	var network: Node = root.get_node("Network")
	network.run_settings = RunSettings.from_dict({"trials": 3, "trial_time": 90.0})
	network.run_settings.validate()
	network.rpc_sync_trial_order([Gods.MAPULON_IKAPATI, Gods.BATHALA])
	var game: Control = load("res://scenes/Game.tscn").instantiate()
	view.add_child(game)
	await _frames(4)
	_check(game.arena != null and is_equal_approx(game.arena.trial_time, 60.0), "the shell keeps Langit Lupa at 60s over a 90s lobby setting")
	_check(game.timer_label.text == "1:00", "the clock shows 1:00 (%s)" % game.timer_label.text)
	game.queue_free()
	network.trial_order_ids.clear()
	await _frames(2)

	# --- the dash ----------------------------------------------------------------------------
	for step in range(20):
		await physics_frame  # the shove test's stumble wears off
	_arena._phase = Arena.Phase.PLAYING
	_arena.dialogue.close_now()  # the closing lines of the payout test
	_arena.player.set_lock(false)
	_arena.player.global_position = Vector2(600, 340)
	_arena.player.facing = 1
	_arena._dash_cd = 0.0
	var start := _arena.player.global_position
	_check(_arena.try_dash(), "the mortal can dash")
	for step in range(20):
		await physics_frame
	var moved := _arena.player.global_position.x - start.x
	_check(moved > 90.0 and moved < 130.0, "a dash covers about 110px (%.1f)" % moved)
	_check(not _arena.try_dash(), "the dash respects its cooldown")
	_check(is_equal_approx(_arena.dash_cooldown, 1.6) and _arena.dash_cooldown_left() > 1.0, "...of 1.6s (%.2fs left)" % _arena.dash_cooldown_left())
	_arena._dash_cd = 0.0
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	_arena.dialogue.show_lines([{"speaker": "TEST", "color": Color.WHITE, "text": "A LINE"}])
	_arena._unhandled_input(space)
	_check(_arena.dash_cooldown_left() == 0.0, "SPACE does not dash while a dialogue is open")
	_arena.dialogue.close_now()
	_arena._toggle_due_menu()
	_check(not _arena.try_dash(), "nor while the God's Due menu is open")
	_arena.due_menu.close()
	_arena._unhandled_input(space)
	_check(_arena.dash_cooldown_left() > 0.0, "during play SPACE dashes")
	var other: Arena = load("res://scenes/gods/mayari/MayariArena.tscn").instantiate()
	view.add_child(other)
	await _frames(2)
	other._phase = Arena.Phase.PLAYING
	other.player.set_lock(false)
	_check(not other.dash_enabled and not other.try_dash(), "the dash is off in other arenas")
	other.queue_free()

	# --- the other gods' favors still work here -------------------------------------------------
	_arena._phase = Arena.Phase.PLAYING
	_arena._apply_skill_effect(Gods.favor_by_id(&"half_vision"), 2)
	_check(_arena._blind_time > 0.0, "Mayari's Half Vision darkens this screen")
	_arena._apply_skill_effect(Gods.favor_by_id(&"siblings_compromise_sun"), 2)
	_check((_arena._sun_patches.get(1, []) as Array).size() > 0, "Apolaki's sun patches land")
	_arena._apply_skill_effect(Gods.favor_by_id(&"let_us_light_your_way"), 2)
	_check(_arena._movement_override_caster == 2, "Tala's Let Us Light Your Way pulls towards the caster")
	_set_favor(1000, 0, 0)
	_rules.mortal(1).due = 1
	_check(_rules.grant_favor(Gods.favor_by_id(&"tagtuyot")), "a favor is granted with a God's Due here")
	_rules.mortal(2).favor = 2000
	_arena._use_skill(GodFavor.Slot.E)
	_check(_rules.mortal(2).drought_time > 0.0, "E fires it (Tagtuyot withers the leader)")

	print("Langit Lupa checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


# A quiet field for one test: `taya` is it (with no buffer), the Langit are
# where the test says, nobody's chant, swap, streak or mercy is left over, and
# the season will not turn by itself.
func _reset(taya: int, langits: Array) -> void:
	_arena._phase = Arena.Phase.PLAYING
	_arena._langits.clear()
	for spot in langits:
		_arena._langits.append(spot)
	for runners in [_arena._swap, _arena._closed, _arena._shoving, _arena._on, _arena._last_left, _arena._close_call, _arena._streak]:
		runners.clear()
	_arena._season_timer = 1000.0
	_arena.set_taya(taya)
	_arena._tagback = 0.0
	_arena._chant_cd = 0.0
	_arena._invuln.clear()
	_arena._my_chanting = false
	_arena._my_stumble = 0.0
	_arena._set_rooted(false)


func _set_favor(mine: int, rival: int, rival_two: int) -> void:
	_rules.mortal(1).favor = mine
	_rules.mortal(2).favor = rival
	_rules.mortal(3).favor = rival_two


func _put(id: int, at: Vector2) -> void:
	if id == _arena._my_id:
		_arena.player.global_position = at
	else:
		_arena._mortal_positions[id] = at


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
