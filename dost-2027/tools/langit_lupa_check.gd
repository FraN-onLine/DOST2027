extends SceneTree

# Validation: Mapulon & Ikapati's Langit Lupa. The richest mortal starts as Taya
# (ties random); a touch on the Lupa passes it, a touch on a claimed Langit does
# not; the new Taya cannot tag back for 1s; one mortal per Langit and the right
# number of them; they move every 3s and never land on the Taya; Time as Taya and
# its drain; the payout by least time; the 60s round; and the dash (only here).
# Run: godot --headless --path <project> -s res://tools/langit_lupa_check.gd

const DT := 0.25  # exact in binary, so four steps are exactly one second

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
	_arena._start_countdown()
	_check(not _arena._langits.is_empty(), "(the countdown lays out the Langit)")

	# --- the first Taya ----------------------------------------------------------
	_set_favor(100, 500, 200)
	_arena._start_trial()
	_check(_arena.taya_id() == 2, "the mortal with the most FAVOR starts as Taya")
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
	_arena._shift_timer = 1000.0

	# --- tagging -----------------------------------------------------------------
	var centre := Vector2(700, 340)
	_arena._langits.clear()
	_arena._claims.clear()
	_put(1, centre)
	_put(2, centre + Vector2(20, 0))
	_put(3, Vector2(1000, 520))
	_arena.set_taya(1)
	_arena._tagback = 0.0
	_arena._check_tag()
	_check(_arena.taya_id() == 2, "a touch on the Lupa passes Taya")
	_check(is_equal_approx(_arena._tagback, _arena.tagback_immunity), "the new Taya gets the tag-back buffer")
	_arena._check_tag()
	_check(_arena.taya_id() == 2, "the new Taya cannot tag straight back")
	for step in range(3):
		_arena.arena_rules_tick(DT)
	_check(_arena.taya_id() == 2, "...for the whole second (0.75s in)")
	for step in range(2):
		_arena.arena_rules_tick(DT)
	_check(_arena.taya_id() == 1, "after 1s the Taya can tag again")
	_arena._place_marker()
	_check(_arena.taya_marker.visible == (_arena._phase == Arena.Phase.PLAYING), "the Taya wears a marker")

	# --- Langit --------------------------------------------------------------------
	var spot := Vector2(500, 300)
	_arena._langits = [spot]
	_arena._claims.clear()
	_arena.set_taya(1)
	_arena._tagback = 0.0
	_put(3, spot)
	_arena._update_claims()
	_put(2, spot + Vector2(10, 5))  # a frame later
	_arena._update_claims()
	_check(_arena.is_safe(3) and not _arena.is_safe(2), "one mortal per Langit: the first on it claims it, the second is not safe")
	_put(1, spot + Vector2(-10, 0))
	_arena._update_claims()
	_check(not _arena._claims.values().has(1), "the Taya can walk over a Langit but never claims one")
	_put(2, Vector2(1000, 520))
	_arena._check_tag()
	_check(_arena.taya_id() == 1, "a touch on a claimed Langit does not pass Taya")
	_put(2, spot + Vector2(10, 5))
	_arena._check_tag()
	_check(_arena.taya_id() == 2, "the unclaimed mortal on the same Langit is tagged")
	_put(3, Vector2(1000, 520))
	_arena._update_claims()
	_check(not _arena.is_safe(3), "stepping off gives the Langit back")

	for mortals in [2, 3, 4]:
		var expected: int = {2: 1, 3: 1, 4: 2}[mortals]
		_check(_arena.langit_count(mortals) == expected, "%d mortals -> %d Langit" % [mortals, expected])
	_rules.ensure_mortal(4, "MORTAL 4")
	_arena._place_langits()
	_check(_arena._langits.size() == 2, "with four mortals the field holds two Langit")
	_rules.remove_mortal(4)
	_arena._place_langits()
	_check(_arena._langits.size() == 1, "with three, one")

	# --- crumbling every 3s ---------------------------------------------------------
	_arena._shift_timer = _arena.shift_interval
	var shifts: int = _arena._shift_count
	var before: Array = _arena._langits.duplicate()
	_arena._tick_shift(2.0)
	_check(not _arena.is_crumbling(), "no warning 1s before the crumble... (%.2fs left)" % _arena._shift_timer)
	_arena._tick_shift(0.5)
	_check(_arena.is_crumbling(), "...the warning shows in the last 0.75s")
	_arena._tick_shift(0.4)
	_check(_arena._shift_count == shifts, "still the same Langit at 2.9s")
	_arena._tick_shift(0.2)
	_check(_arena._shift_count == shifts + 1, "they crumble and move at 3s")
	_check(_arena._langits != before, "...to new spots")
	var placement_ok := true
	_rules.ensure_mortal(4, "MORTAL 4")
	for attempt in range(60):
		var taya_at := Vector2(randf_range(270, 1120), randf_range(100, 580))
		_put(_arena.taya_id(), taya_at)
		_arena._place_langits()
		for index in range(_arena._langits.size()):
			var rect: Rect2 = _arena.langit_rect(index)
			if _arena._langits[index].distance_to(taya_at) < _arena.taya_clearance:
				placement_ok = false
			if not _arena._field.encloses(rect) or rect.position.x < Arena.UI_STRIP_WIDTH:
				placement_ok = false
			for other in range(index + 1, _arena._langits.size()):
				if rect.intersects(_arena.langit_rect(other)):
					placement_ok = false
	_rules.remove_mortal(4)
	_check(placement_ok, "a Langit never lands near the Taya, off the field, in the UI strip or on another Langit")
	_check(_arena._claims.is_empty(), "a crumble sends everybody back to the Lupa")

	# --- Time as Taya and the drain -------------------------------------------------
	_arena._shift_timer = 1000.0
	_arena._langits.clear()
	_arena._claims.clear()
	_arena._taya_time.clear()
	_arena._drain_pending.clear()
	_arena._drain_tick = 1.0
	_set_favor(1000, 1000, 1000)
	_put(1, Vector2(300, 120))
	_put(2, Vector2(1100, 560))
	_put(3, Vector2(700, 560))
	_arena.set_taya(1)
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
	_check(paid[1] == 1200 and paid[2] == 700 and paid[3] == 200, "least time as Taya is paid most: 1200 / 700 / 200 (%s)" % str(paid))
	_arena._taya_time = {1: 5.0, 2: 5.2, 3: 20.0}
	paid = _arena.payouts()
	_check(paid[1] == 1200 and paid[2] == 1200 and paid[3] == 200, "times within 0.25s tie and share the better payout (%s)" % str(paid))
	_rules.ensure_mortal(4, "MORTAL 4")
	_arena._taya_time = {1: 1.0, 2: 2.0, 3: 3.0, 4: 4.0}
	paid = _arena.payouts()
	_check(paid[1] == 1200 and paid[2] == 867 and paid[3] == 533 and paid[4] == 200, "four places are spread evenly (%s)" % str(paid))
	_rules.remove_mortal(4)
	_arena._taya_time = {1: 5.0, 2: 10.0, 3: 20.0}
	_set_favor(0, 0, 0)
	var reasons: Array[String] = []
	_rules.favor_changed.connect(func(_id: int, _total: int, _delta: int, reason: String) -> void: reasons.append(reason))
	_arena._end_trial()
	var result: Dictionary = _arena._results.get(1, {})
	_check(_rules.mortal(1).favor == 1200 and int(result.get("favor", 0)) == 1200, "the payout is banked before the results are written")
	_check(reasons.has("Langit Lupa payout"), "...under the reason \"Langit Lupa payout\"")

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
