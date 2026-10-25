extends SceneTree

# Validation: the Pamana (heirlooms) the Tindahan sells, and their rules in
# GodMatch. Every item wakes at the next trial's "GO!" and expires at its end
# (Surigao Gold waits for its milestone instead):
#   * the Manunggul Jar returns 25% of what was lost (drains too) before
#     Favorable Outcome judges the top, and Full Moon cannot inflate it
#   * the Agimat cancels exactly three losses - not drains, and never a loss
#     that was already shielded to nothing
#   * Torn Cedulas / the Mighty Pen cut the E / Q cooldown inside the window
#     only, stacking with The Bountiful
#   * the Mutya raises gains inside the window only
#   * the Kampilan recharges the first cast only
#   * Surigao Gold moves one milestone 200 FAVOR early, then stops
#   * every field survives a snapshot round trip
#   * spend_favor is no loss: refused when short, no Waning Moon, no Sun God
#     patch, no red popup, no loss history, and a claimed milestone stays claimed
# Run: godot --headless --path <project> -s res://tools/pamana_check.gd

const DT := 0.125

var _problems := 0
var _fired: Array = []


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	# --- the data -------------------------------------------------------------------
	var items := Pamanas.all()
	_check(items.size() == 8, "eight Pamana are registered (%d)" % items.size())
	var ids: Array = items.map(func(p: Pamana) -> String: return str(p.id))
	_check(ids == ["agimat", "banton_cloth", "kampilan", "manunggul_jar", "mighty_pen", "mutya", "surigao_gold", "torn_cedulas"],
		"they are listed sorted by id")
	_check(Pamanas.by_id(&"agimat").cost == 100 and Pamanas.by_id(&"mutya").cost == 250 and Pamanas.by_id(&"surigao_gold").cost == 50,
		"the costs match the table")
	_check(Pamanas.by_id(&"torn_cedulas").needs == Pamana.Needs.E_SKILL and Pamanas.by_id(&"mighty_pen").needs == Pamana.Needs.Q_SKILL
		and Pamanas.by_id(&"kampilan").needs == Pamana.Needs.ANY_SKILL, "the skill items say what they need")
	_check(Pamanas.by_id(&"mutya").timing == Pamana.Timing.FIRST_WINDOW and is_equal_approx(Pamanas.by_id(&"mutya").window, 30.0),
		"a FIRST_WINDOW item lasts 30 seconds")
	for item in items:
		_check(not item.effect.is_empty() and not item.history.is_empty() and not item.era.is_empty()
			and not item.origin.is_empty() and not item.flavor.is_empty() and item.icon != null,
			"%s carries its effect, history, era, origin, flavor and icon" % item.display_name)

	var full_moon := Gods.favor_by_id(&"full_moon")
	var waning := Gods.favor_by_id(&"waning_moon")
	var favorable := Gods.favor_by_id(&"favorable_outcome")
	var bountiful_e := Gods.favor_by_id(&"the_bountiful_e")
	var e_skill := _skill(GodFavor.Slot.E)
	var q_skill := _skill(GodFavor.Slot.Q)

	# --- activation at "GO!" and expiry at the end -----------------------------------
	var rules := _match()
	var me := rules.mortal(1)
	rules.pamana_fired.connect(func(id: int, item: Pamana, text: String) -> void: _fired.append([id, item.id, text]))
	me.pamana_next = Pamanas.AGIMAT
	_start(rules)
	_check(me.pamana_active == Pamanas.AGIMAT and me.pamana_next == &"" and me.agimat_charges == 3,
		"begin_trial wakes the waiting item (active, 3 charges)")
	_check(_fired.size() == 1 and str(_fired[0][2]) == "THE AGIMAT AWAKENS", "...and announces it (%s)" % str(_fired))
	rules.end_trial()
	_check(me.pamana_active == &"" and me.agimat_charges == 0, "end_trial expires the item and its unused charges")
	_start(rules)
	_check(me.pamana_active == &"", "an item lasts one trial only")

	# --- Manunggul Jar -----------------------------------------------------------------
	rules = _match()
	me = rules.mortal(1)
	var rival := rules.mortal(2)
	me.favors.append(full_moon)
	me.favors.append(favorable)
	me.pamana_next = Pamanas.MANUNGGUL_JAR
	_start(rules)
	me.favor = 1400
	rival.favor = 1050
	rules.lose_favor(300, "Test", 1)
	rules.lose_favor(100, "Taya", 1, true)
	_check(me.jar_lost == 400 and me.favor == 1000, "the jar counts every loss, drains included (%d)" % me.jar_lost)
	var summary := rules.end_trial()
	var outcome := int(favorable.param("bonus", 0.0))
	_check(me.favor == 1000 + 100 + outcome, "the jar returns 25%% (100, not inflated by Full Moon) before Favorable Outcome judges the top (%d)" % me.favor)
	_check(int(summary[1]["bonus"]) == 100 + outcome, "the return shows in the results bonus (%d)" % int(summary[1]["bonus"]))
	_check(me.jar_lost == 0 and me.pamana_active == &"", "the jar empties and expires")

	# --- The Agimat --------------------------------------------------------------------
	rules = _match()
	me = rules.mortal(1)
	me.pamana_next = Pamanas.AGIMAT
	_start(rules)
	me.favor = 1000
	rules.lose_favor(40, "Taya", 1, true)
	_check(me.favor == 960 and me.agimat_charges == 3, "a drain gets through and keeps every charge")
	me.loss_immunity = 1.0
	rules.lose_favor(100, "Test", 1)
	_check(me.favor == 960 and me.agimat_charges == 3, "a loss already shielded to nothing uses no charge")
	me.loss_immunity = 0.0
	me.favors.append(waning)
	for index in range(3):
		rules.lose_favor(100, "Test", 1)
	_check(me.favor == 960 and me.agimat_charges == 0, "three losses are cancelled (%d FAVOR, %d left)" % [me.favor, me.agimat_charges])
	rules.lose_favor(100, "Test", 1)
	_check(me.favor == 910, "the fourth loss lands, after Waning Moon (%d)" % me.favor)
	me.favor = 0
	me.agimat_charges = 3
	rules.lose_favor(100, "Test", 1)
	_check(me.agimat_charges == 3, "nothing to lose uses no charge")

	# --- Torn Cedulas / The Mighty Pen ---------------------------------------------
	rules = _match()
	me = rules.mortal(1)
	rules.bestow_favor(e_skill, 1)
	rules.bestow_favor(q_skill, 1)
	var e_base := e_skill.cooldown
	var q_base := q_skill.cooldown
	me.pamana_next = Pamanas.TORN_CEDULAS
	_start(rules)
	_check(is_equal_approx(rules.skill_cooldown(GodFavor.Slot.E, 1), e_base * 0.8), "the Cedulas cut the E cooldown by 20% in the window")
	_check(is_equal_approx(rules.skill_cooldown(GodFavor.Slot.Q, 1), q_base), "...and leave Q alone")
	me.favors.append(bountiful_e)
	_check(is_equal_approx(rules.skill_cooldown(GodFavor.Slot.E, 1), e_base * 0.8 * bountiful_e.param("cooldown_multiplier", 0.9)),
		"...stacking with The Bountiful")
	rules.use_skill(GodFavor.Slot.E, 1)
	var short := e_base * 0.8 * bountiful_e.param("cooldown_multiplier", 0.9)
	me.pamana_window = 0.0  # the window closes right after the cast
	_check(is_equal_approx(me.cooldown_left(e_skill.id), short), "a cast inside the window keeps its shorter cooldown after it closes (%.2f)" % me.cooldown_left(e_skill.id))
	_check(is_equal_approx(rules.skill_cooldown(GodFavor.Slot.E, 1), e_base * bountiful_e.param("cooldown_multiplier", 0.9)),
		"after the window the E cooldown is back to normal")
	me.pamana_window = 30.0
	_tick(rules, 30.0)
	_check(me.pamana_window <= 0.0, "the window closes after 30 seconds of the trial")
	rules = _match()
	me = rules.mortal(1)
	rules.bestow_favor(q_skill, 1)
	me.pamana_next = Pamanas.MIGHTY_PEN
	_start(rules)
	_check(is_equal_approx(rules.skill_cooldown(GodFavor.Slot.Q, 1), q_base * 0.8), "the Mighty Pen cuts the Q cooldown by 20% in the window")
	rules.trial_active = false
	_tick(rules, 40.0)
	_check(me.pamana_window > 0.0, "the window only runs while a trial does")

	# --- The Mutya -----------------------------------------------------------------------
	rules = _match()
	me = rules.mortal(1)
	me.pamana_next = Pamanas.MUTYA
	_start(rules)
	_check(rules.add_favor(100, "Test", 1) == 120, "the Mutya adds 20% to gains in the window")
	_tick(rules, 30.0)
	_check(rules.add_favor(100, "Test", 1) == 100, "...and nothing after it")

	# --- Kampilan ------------------------------------------------------------------------
	rules = _match()
	me = rules.mortal(1)
	rules.bestow_favor(e_skill, 1)
	rules.bestow_favor(q_skill, 1)
	me.pamana_next = Pamanas.KAMPILAN
	_start(rules)
	_fired.clear()
	rules.pamana_fired.connect(func(id: int, item: Pamana, text: String) -> void: _fired.append([id, item.id, text]))
	rules.use_skill(GodFavor.Slot.E, 1)
	_check(me.cooldown_left(e_skill.id) <= 0.0 and not me.kampilan_ready, "the Kampilan recharges the first cast at once")
	_check(_fired.size() == 1 and str(_fired[0][2]) == "KAMPILAN - SKILL RECHARGED", "...and says so")
	rules.use_skill(GodFavor.Slot.Q, 1)
	_check(me.cooldown_left(q_skill.id) > 0.0, "the second cast recharges as usual")

	# --- Surigao Gold ----------------------------------------------------------------
	rules = _match()
	me = rules.mortal(1)
	me.favor = 300
	_check(rules.buy_pamana(Pamanas.by_id(Pamanas.SURIGAO_GOLD), 1), "Surigao Gold can be bought")
	_check(me.favor == 250 and me.surigao_early == 200 and me.pamana_next == &"", "it costs 50 and waits for a milestone, not a trial")
	_check(not rules.pamana_useful(Pamanas.by_id(Pamanas.SURIGAO_GOLD), 1), "a second one is not offered while it waits")
	rules.add_favor(540, "Test", 1)
	_check(me.due == 0, "nothing at 790")
	rules.add_favor(10, "Test", 1)
	_check(me.due == 1 and me.surigao_early == 0 and me.claimed_milestones.has(1), "the first God's Due arrives at 800, 200 early")
	rules.add_favor(1000, "Test", 1)
	_check(me.due == 1, "the next one is not early (1800)")
	rules.add_favor(200, "Test", 1)
	_check(me.due == 2, "...it arrives at 2000 as usual")
	rules.end_trial()
	rules = _match()
	me = rules.mortal(1)
	me.favor = 900
	rules.buy_pamana(Pamanas.by_id(Pamanas.SURIGAO_GOLD), 1)
	_check(me.due == 1 and me.surigao_early == 0, "bought within 200 of a milestone, it pays at once (850 >= 800)")
	rules = _match()
	me = rules.mortal(1)
	me.surigao_early = 200
	rules.end_trial()
	_check(me.surigao_early == 200, "an unused Surigao Gold survives the trial's end")

	# --- snapshot round trip ---------------------------------------------------------
	rules = _match()
	me = rules.mortal(1)
	me.pamana_next = Pamanas.MUTYA
	me.pamana_active = Pamanas.AGIMAT
	me.pamana_window = 12.5
	me.agimat_charges = 2
	me.jar_lost = 77
	me.kampilan_ready = true
	me.surigao_early = 200
	var copy := _match()
	copy.apply_snapshot(rules.snapshot())
	var mirror := copy.mortal(1)
	_check(mirror.pamana_next == Pamanas.MUTYA and mirror.pamana_active == Pamanas.AGIMAT and is_equal_approx(mirror.pamana_window, 12.5)
		and mirror.agimat_charges == 2 and mirror.jar_lost == 77 and mirror.kampilan_ready and mirror.surigao_early == 200,
		"every Pamana field survives a snapshot round trip")
	var reasons: Array = []
	copy.favor_changed.connect(func(_id: int, _f: int, _d: int, reason: String) -> void: reasons.append(reason))
	copy.mortal(1).is_local = true
	var bought := copy.snapshot()
	bought[1]["favor"] = int(bought[1]["favor"]) + 500
	copy.apply_snapshot(bought)
	reasons.clear()
	bought[1]["favor"] = int(bought[1]["favor"]) - 100
	bought[1]["pamana_next"] = "kampilan"
	copy.apply_snapshot(bought)
	_check(reasons == [GodMatch.PURCHASE_REASON], "a client reads a drop that came with a new item as a purchase (%s)" % str(reasons))

	# --- spend_favor is not a loss -------------------------------------------------------
	rules = _match()
	me = rules.mortal(1)
	me.favor = 80
	_check(not rules.spend_favor(100, GodMatch.PURCHASE_REASON, 1) and me.favor == 80, "spend_favor refuses when the mortal is short")
	_check(not rules.buy_pamana(Pamanas.by_id(Pamanas.MUTYA), 1) and me.pamana_next == &"", "an unaffordable item is not bought")
	me.favor = 1100
	rules._check_milestones(me)
	var due_before := me.due
	me.favors.append(waning)
	me.batman_shield = true
	me.pamana_active = Pamanas.AGIMAT
	me.agimat_charges = 3
	_check(rules.spend_favor(200, GodMatch.PURCHASE_REASON, 1) and me.favor == 900, "spending ignores Waning Moon, Si Batman and the Agimat (%d)" % me.favor)
	_check(me.agimat_charges == 3 and me.loss_history.is_empty() and me.jar_lost == 0, "...uses no charge and leaves no loss history")
	rules.add_favor(200, "Test", 1)
	_check(me.claimed_milestones.has(1) and me.due == due_before, "a claimed milestone stays claimed and pays nothing again")

	# The Sun God, The Ruler and the red popup live in the arena: none of them react.
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)
	var arena: Arena = load("res://scenes/gods/mayari/MayariArena.tscn").instantiate()
	view.add_child(arena)
	await _frames(2)
	arena.rules.simulate_rivals = false
	arena.rules.mortal(2).favors.append(Gods.favor_by_id(&"the_sun_god"))
	arena.rules.mortal(1).favors.append(Gods.favor_by_id(&"the_ruler"))
	arena.rules.mortal(1).favor = 500
	var popups := arena.favor_popups_root.get_child_count()
	arena.rules.spend_favor(250, GodMatch.PURCHASE_REASON, 1)
	await _frames(1)
	_check(arena.rules.mortal(1).favor == 250, "the arena's mortal paid")
	_check(arena._sun_patches.is_empty(), "no Sun God or Ruler patch follows a purchase")
	_check(arena.favor_popups_root.get_child_count() == popups, "no red loss popup follows a purchase")
	arena.lose_favor(100, "Test", 1)
	_check(not arena._sun_patches.is_empty(), "(a real loss still feeds The Sun God and The Ruler)")

	print("Pamana checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


# A fresh match with two mortals, the way an arena builds one.
func _match() -> GodMatch:
	var rules := GodMatch.new()
	rules.setup(Gods.mayari(), "ME", ["RIVAL"], false)
	root.add_child(rules)
	return rules


# The trial's "GO!": the arena marks it running and wakes the items.
func _start(rules: GodMatch) -> void:
	rules.trial_active = true
	rules.begin_trial()


func _tick(rules: GodMatch, seconds: float) -> void:
	for step in range(int(round(seconds / DT))):
		rules._tick_mortal(rules.mortal(1), DT)


# A skill favor in `slot` with a cooldown, from any god.
func _skill(slot: int) -> GodFavor:
	for god in Gods.all():
		for favor in god.favors:
			if favor.slot == slot and favor.cooldown > 0.0 and favor.requires_god_id() == &"" and favor.requires_any_god_ids().is_empty():
				return favor
	return null


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
