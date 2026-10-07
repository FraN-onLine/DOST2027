extends SceneTree

# Regression check for Mapulon & Ikapati's seven favors, edge cases included:
#   Binhi (grows over three trials, carried between trials), Panahon ng Anihan
#   (inside / outside the window, never on payouts), Kabiyak (closest pairing, the
#   10% share, two mortals paired with each other, Full Moon, re-pairing after a
#   leave), Tagtuyot (targeting, 5 bites, the 400 cap, Waning Moon), Ligaw na Damo
#   (the siphon, Full Moon on the target, the latest caster wins, it runs out),
#   Unang Ulan (only losses in the rain regrow, 125% after 5s) and Kamalig (not a
#   loss for anyone, hides you from "most FAVOR", interest, no second God's Due).
# The favors travel to every trial, so this runs them in Mayari's arena.
# Run: godot --headless --path <project> -s res://tools/mapulon_ikapati_favor_check.gd

const DT := 0.25

var _arena: Arena
var _rules: GodMatch
var _problems := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)
	_arena = load("res://scenes/gods/mayari/MayariArena.tscn").instantiate()
	view.add_child(_arena)
	await process_frame
	await process_frame
	var guard := 0
	while _arena.dialogue.is_active() and guard < 40:
		_arena.dialogue.advance()
		guard += 1
	_arena._phase = Arena.Phase.PLAYING
	_rules = _arena.rules

	# --- the god ---------------------------------------------------------------------
	var pair := Gods.mapulon_ikapati()
	_check(pair != null and pair.id == &"mapulon_ikapati" and pair.implemented and pair.game_name == "LANGIT LUPA", "Mapulon & Ikapati are a registered, implemented god")
	_check(pair.favors.size() == 7, "they bestow seven favors")
	var in_pool := false
	for god in Gods.trial_order():
		in_pool = in_pool or god.id == Gods.MAPULON_IKAPATI
	_check(in_pool and RunSettings.playable_ids().has(Gods.MAPULON_IKAPATI), "they are in the random trial pool and the lobby's list")
	for key in ["mayari", "apolaki", "tala", "hanan", "bathala", "*"]:
		_check(pair.transition_lines.has(key), "they have a hand-over line for %s" % key)
	for other in [Gods.mayari(), Gods.apolaki(), Gods.tala(), Gods.hanan()]:
		_check(other.transition_lines.has("mapulon_ikapati"), "%s has a hand-over line for them" % other.display_name)
	var binhi := _favor("binhi")
	var panahon := _favor("panahon_ng_anihan")
	var kabiyak := _favor("kabiyak")
	var tagtuyot := _favor("tagtuyot")
	var damo := _favor("ligaw_na_damo")
	var ulan := _favor("unang_ulan")
	var kamalig := _favor("kamalig")
	_check(tagtuyot.slot == GodFavor.Slot.E and damo.slot == GodFavor.Slot.E, "two E skills: Tagtuyot and Ligaw na Damo")
	_check(ulan.slot == GodFavor.Slot.Q and kamalig.slot == GodFavor.Slot.Q, "two Q skills: Unang Ulan and Kamalig")
	_check(binhi.kind == GodFavor.Kind.PASSIVE and panahon.kind == GodFavor.Kind.PASSIVE and kabiyak.kind == GodFavor.Kind.INSTANT,
		"Binhi and Panahon are passive, Kabiyak fires on grant")
	_setup(0, 0, 0)
	_rules.bestow_favor(tagtuyot)
	_rules.bestow_favor(damo)
	_check(not _rules.mortal(1).has_favor(&"tagtuyot") and _rules.mortal(1).favor_in_slot(GodFavor.Slot.E) == damo, "a mortal holds one E: the new one replaces the old")

	# --- Binhi ----------------------------------------------------------------------------
	_setup(0, 0, 0)
	_rules.bestow_favor(binhi)
	_rules.end_trial()
	_check(_rules.mortal(1).favor == 50, "Binhi pays 50 after the first trial")
	var next := _next_trial()
	next.end_trial()
	_check(next.mortal(1).favor == 150 and next.mortal(1).binhi_trials == 2, "100 after the second (carried into a new trial's GodMatch)")
	next.end_trial()
	_check(next.mortal(1).favor == 300, "150 after the third: it grows (%d)" % next.mortal(1).favor)
	_check(next.mortal(2).favor == 0, "a mortal without the seed grows nothing")
	next.queue_free()

	# --- Panahon ng Anihan ------------------------------------------------------------------
	_setup(0, 0, 0)
	_rules.bestow_favor(panahon)
	_rules.time_left = 20.0
	_rules.add_favor(100, "early")
	_check(_rules.mortal(1).favor == 100, "outside the last 15s nothing changes")
	_rules.time_left = 10.0
	_rules.add_favor(100, "late")
	_check(_rules.mortal(1).favor == 230, "inside the last 15s FAVOR earned is +30%")
	_rules.add_favor(100, "late", 2)
	_check(_rules.mortal(2).favor == 100, "only the holder")
	_rules.bestow_favor(binhi)
	_rules.mortal(1).favor = 0
	_rules.end_trial()
	_check(_rules.mortal(1).favor == 50, "an end-of-trial payout (Binhi) is never boosted (%d)" % _rules.mortal(1).favor)
	_check(_rules.time_left == INF, "and the window is closed once the trial ends")
	var langit: LangitLupaArena = load("res://scenes/gods/mapulon_ikapati/LangitLupaArena.tscn").instantiate()
	view.add_child(langit)
	await process_frame
	langit._phase = Arena.Phase.PLAYING
	for m in langit.rules.mortals.values():
		m.favor = 0
	langit.rules.mortal(1).favors.append(panahon)
	langit.rules.time_left = 3.0
	langit._taya_time = {1: 0.0, 2: 10.0, 3: 20.0}
	langit._end_trial()
	_check(langit.rules.mortal(1).favor == 1200, "nor is Langit Lupa's payout (%d)" % langit.rules.mortal(1).favor)
	langit.queue_free()

	# --- Kabiyak -----------------------------------------------------------------------------
	_setup(500, 700, 100)
	_check(not _rules.is_favor_eligible(kabiyak), "Kabiyak is locked without a Mapulon & Ikapati favor")
	_rules.bestow_favor(binhi)
	_check(_rules.is_favor_eligible(kabiyak), "a favor of theirs unlocks it")
	_rules.bestow_favor(kabiyak)
	_check(_rules.mortal(1).kabiyak == 2, "the holder is paired with the mortal closest in FAVOR")
	var seen := {}
	for attempt in range(40):
		_setup(500, 600, 400)
		_rules.mortal(1).favors.append(binhi)
		_rules.bestow_favor(kabiyak)
		seen[_rules.mortal(1).kabiyak] = true
	_check(seen.size() == 2 and seen.has(2) and seen.has(3), "a tie for closest is broken at random")
	_setup(500, 700, 100)
	_pair(1, 2)
	_rules.add_favor(100, "zone", 2)
	_check(_rules.mortal(1).favor == 510 and _rules.mortal(2).favor == 800, "the holder gains 10% of what their kabiyak gains; the kabiyak loses nothing")
	_rules.add_favor(5, "trickle", 2)
	_rules.add_favor(5, "trickle", 2)
	_check(_rules.mortal(1).favor == 511, "small gains add up (0.5 + 0.5 = 1)")
	_rules.add_favor(100, "zone", 3)
	_check(_rules.mortal(1).favor == 511, "nobody else's gains are shared")
	_pair(2, 1)
	_rules.add_favor(100, "zone", 2)
	_check(_rules.mortal(1).favor == 521 and _rules.mortal(2).favor == 910, "paired with each other: no loop (1 gets 10, 2 gets exactly 100)")
	_rules.add_favor(100, "zone", 1)
	_check(_rules.mortal(2).favor == 920 and _rules.mortal(1).favor == 621, "...and it works the other way too")
	_rules.mortal(1).favors.append(Gods.favor_by_id(&"full_moon"))
	_rules.add_favor(100, "zone", 2)
	_check(_rules.mortal(1).favor == 631, "Full Moon does not stack on the share")
	_rules.remove_mortal(2)
	_check(_rules.mortal(1).kabiyak == 3, "when the kabiyak leaves, the holder pairs with the next closest")
	var client := GodMatch.new()
	client.setup_peers(pair, {1: "ME", 3: "RIVAL TWO"}, 1)
	root.add_child(client)
	client.apply_snapshot(_rules.snapshot())
	_check(client.mortal(1).kabiyak == 3, "the pairing travels in the snapshot")
	client.queue_free()

	# --- Tagtuyot ------------------------------------------------------------------------------
	_setup(500, 1000, 100)
	_check(_rules.cast_tagtuyot(1, tagtuyot) == 2, "Tagtuyot withers the leader")
	_advance(0.75)
	_check(_rules.mortal(2).favor == 1000, "no bite before the first second")
	_advance(0.25)
	_check(_rules.mortal(2).favor == 970, "3% a second (1000 -> 970)")
	_advance(5.0)
	_check(_rules.mortal(2).favor == 1000 - 30 - 29 - 28 - 27 - 26, "five bites in 5s, then it stops (%d)" % _rules.mortal(2).favor)
	_setup(3000, 1000, 100)
	_check(_rules.cast_tagtuyot(1, tagtuyot) == 2, "when the caster leads, second place withers")
	_setup(500, 20000, 100)
	_rules.cast_tagtuyot(1, tagtuyot)
	_advance(6.0)
	_check(_rules.mortal(2).favor == 19600 and _rules.mortal(2).drought_total == 400, "never more than 400 in all (%d)" % _rules.mortal(2).favor)
	_setup(500, 10000, 100)
	_rules.mortal(2).favors.append(Gods.favor_by_id(&"waning_moon"))
	_rules.cast_tagtuyot(1, tagtuyot)
	_advance(1.0)
	_check(_rules.mortal(2).favor == 9850, "Waning Moon halves each bite (300 -> 150)")
	_advance(5.0)
	var taken: int = 10000 - _rules.mortal(2).favor
	_check(taken == _rules.mortal(2).drought_total and taken < 400, "...and the cap counts what was really lost (%d of 400)" % taken)
	_setup(500, 1000, 100)
	_rules.bestow_favor(tagtuyot)
	_rules.use_skill(GodFavor.Slot.E)
	_arena._apply_skill_effect(tagtuyot, 1)
	_check(_rules.mortal(2).drought_time > 0.0, "the E skill, run through the arena, starts the drought")

	# --- Ligaw na Damo ---------------------------------------------------------------------------
	_setup(0, 0, 0)
	_rules.cast_ligaw_na_damo(1, damo)
	_rules.add_favor(100, "zone", 2)
	_check(_rules.mortal(2).favor == 70 and _rules.mortal(1).favor == 30, "30% of what a weeded mortal gains goes to the caster")
	_rules.add_favor(100, "zone", 1)
	_check(_rules.mortal(1).favor == 130, "the caster's own field has no weeds")
	_setup(0, 0, 0)
	_rules.mortal(2).favors.append(Gods.favor_by_id(&"full_moon"))
	_rules.cast_ligaw_na_damo(1, damo)
	_rules.add_favor(100, "zone", 2)
	_check(_rules.mortal(2).favor == 77 and _rules.mortal(1).favor == 33, "Full Moon on the target applies first: 110 gained, 33 siphoned")
	_setup(0, 0, 0)
	_rules.cast_ligaw_na_damo(1, damo)
	_rules.cast_ligaw_na_damo(3, damo)
	_rules.add_favor(100, "zone", 2)
	_check(_rules.mortal(3).favor == 30 and _rules.mortal(1).favor == 0, "two casters on one mortal: the latest wins")
	_rules.add_favor(100, "zone", 1)
	_check(_rules.mortal(3).favor == 60, "...and the first caster's field is weeded by the second")
	_advance(6.25)
	_rules.add_favor(100, "zone", 2)
	_check(_rules.mortal(2).favor == 170, "after 6s the weeds are gone")
	_setup(0, 0, 0)
	_rules.mortal(1).favors.append(binhi)
	_pair(1, 2)
	_rules.cast_ligaw_na_damo(3, damo)
	_rules.add_favor(100, "zone", 2)
	_check(_rules.mortal(1).favor == 7, "Kabiyak shares only what the weeded mortal really kept (70)")

	# --- Unang Ulan -------------------------------------------------------------------------------
	_setup(1000, 0, 0)
	_rules.bestow_favor(ulan)
	_rules.lose_favor(100, "before the rain")
	_rules.use_skill(GodFavor.Slot.Q)
	_arena._apply_skill_effect(ulan, 1)
	_rules.lose_favor(100, "in the rain")
	_check(_rules.mortal(1).favor == 800, "losses in the rain are still taken now")
	_check(_rules.mortal(1).loss_history.size() == 2, "...so other favors (Bagong Umaga) still see them")
	_advance(6.0)
	_rules.lose_favor(50, "after the rain")
	_advance(4.75)
	_check(_rules.mortal(1).favor == 750, "nothing grows back until 5s after the rain stops")
	_advance(0.5)
	_check(_rules.mortal(1).favor == 875, "then the rain's loss grows back at 125%%, and only that one (%d)" % _rules.mortal(1).favor)
	_advance(10.0)
	_check(_rules.mortal(1).favor == 875, "it grows back once")
	_setup(1000, 0, 0)
	_rules.bestow_favor(ulan)
	_rules.use_skill(GodFavor.Slot.Q)
	_rules.lose_favor(80, "in the rain")
	_rules.end_trial()
	_check(_rules.mortal(1).favor == 1020, "the trial ending first pays the regrowth at once")

	# --- Kamalig ------------------------------------------------------------------------------------
	_setup(1000, 900, 100)
	_rules.mortal(1).due = 0
	_rules.mortal(1).claimed_milestones = {1: true}
	_rules.mortal(2).favors.append(Gods.favor_by_id(&"the_sun_god"))
	_rules.mortal(1).favors.append(Gods.favor_by_id(&"the_ruler"))
	_rules.mortal(1).favors.append(Gods.favor_by_id(&"favorable_outcome"))
	_arena._sun_patches.clear()
	_arena._sun_patch_sources.clear()
	var popups := _arena.popups_root.get_child_count()
	_rules.bestow_favor(kamalig)
	_rules.use_skill(GodFavor.Slot.Q)
	_arena._apply_skill_effect(kamalig, 1)
	_check(_rules.mortal(1).favor == 750 and _rules.mortal(1).granary == 250, "Kamalig stores 25% of the FAVOR")
	_check(_rules.mortal(1).loss_history.is_empty(), "the store is not a loss: nothing in the loss history (Bagong Umaga)")
	_check(_arena._sun_patches.is_empty(), "nor for Apolaki's The Sun God and The Ruler: no sun patch anywhere")
	_check(_arena.popups_root.get_child_count() == popups, "and no red loss popup")
	_check(_rules._highest_other(3).id == 2, "stored FAVOR hides the holder from \"most FAVOR\" targeting")
	_check(_rules.snapshot()[1]["granary"] == 250, "the store travels in the snapshot")
	_rules.end_trial()
	var favorable := int(Gods.favor_by_id(&"favorable_outcome").param("bonus", 0.0))
	_check(_rules.mortal(1).favor == 1050 + favorable and _rules.mortal(1).granary == 0,
		"at trial end it comes back with 20%% interest (250 -> 300), before Favorable Outcome judges the top (%d)" % _rules.mortal(1).favor)
	_check(_rules.mortal(1).due == 0, "coming back past an old milestone hands out no second God's Due")
	_setup(4000, 0, 0)
	_check(_rules.store_in_granary(1, kamalig) == 400 and _rules.mortal(1).favor == 3600, "at most 400 is stored")

	# --- Break of Day ends their casts -------------------------------------------------------------------
	_setup(500, 2000, 100)
	_rules.cast_tagtuyot(2, tagtuyot)
	_rules.cast_ligaw_na_damo(2, damo)
	_rules.mortal(2).favors.append(ulan)
	_rules.mortal(2).durations[&"unang_ulan"] = 4.0
	_rules.mortal(2).rain_lost = 60
	_check(_rules.mortal(1).drought_time > 0.0 and _rules.mortal(3).weeds_time > 0.0, "(mortal 2 sends a drought and weeds)")
	_check(_rules.break_of_day(1) == 2, "(Break of Day hits mortal 2)")
	_check(_rules.mortal(1).drought_time == 0.0 and _rules.mortal(1).weeds_time == 0.0 and _rules.mortal(3).weeds_time == 0.0,
		"Break of Day ends the drought and the weeds its target cast")
	_advance(10.0)
	_check(_rules.mortal(2).favor == 2000, "and the rain they stood in: nothing regrows")

	print("Mapulon & Ikapati favor checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _favor(id: String) -> GodFavor:
	var favor := Gods.mapulon_ikapati().get_favor(StringName(id))
	_check(favor != null, "Mapulon & Ikapati bestow %s" % id)
	return favor


# A fresh trio of mortals (1 is the local one) with the given FAVOR.
func _setup(mine: int, rival: int, rival_two: int) -> void:
	_rules.setup(Gods.mapulon_ikapati(), "ME", ["RIVAL", "RIVAL TWO"], false)
	_rules.mortal(1).favor = mine
	_rules.mortal(2).favor = rival
	_rules.mortal(3).favor = rival_two
	_rules.time_left = INF
	_rules._clock = 0.0


func _pair(holder: int, partner: int) -> void:
	var m := _rules.mortal(holder)
	if not m.has_favor(&"kabiyak"):
		m.favors.append(Gods.favor_by_id(&"kabiyak"))
	m.kabiyak = partner


# The next trial's GodMatch, built from this one's snapshot like the game shell does.
func _next_trial() -> GodMatch:
	var next := GodMatch.new()
	next.setup(Gods.mapulon_ikapati(), "ME", ["RIVAL", "RIVAL TWO"], false)
	root.add_child(next)
	next.apply_snapshot(_rules.snapshot())
	return next


func _advance(seconds: float) -> void:
	for step in range(int(round(seconds / DT))):
		_rules._process(DT)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
