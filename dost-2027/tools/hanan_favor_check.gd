extends SceneTree

# Regression check for Hanan's seven favors, edge cases included:
#   The Dawn (0 dues), An Even Playing Field (holder on top, ties, loss modifiers),
#   First Light (last place, everyone tied), Bagong Umaga (only what was really
#   lost, Full Moon cannot inflate it), Rest and Refreshed (every other mortal
#   drowsy for 3s, then 0.8s stunned), Morning Chases the Night (eligibility and
#   the 0.5s cap) and The Three Sisters (eligibility and bonus).
# Run: godot --headless --path <project> -s res://tools/hanan_favor_check.gd

var _arena: HananArena
var _rules: GodMatch
var _problems := 0
var _due_events := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)
	_arena = load("res://scenes/gods/hanan/HananArena.tscn").instantiate()
	view.add_child(_arena)
	await process_frame
	await process_frame
	var guard := 0
	while _arena.dialogue.is_active() and guard < 40:
		_arena.dialogue.advance()
		guard += 1
	_arena._phase = Arena.Phase.PLAYING
	_rules = _arena.rules
	_rules.due_changed.connect(func(_id: int, _due: int) -> void: _due_events += 1)

	var hanan := Gods.hanan()
	_check(hanan != null and hanan.id == &"hanan" and hanan.implemented, "Hanan is a registered, implemented god")
	_check(hanan.favors.size() == 7, "Hanan bestows seven favors")
	var in_pool := false
	for god in Gods.trial_order():
		in_pool = in_pool or god.id == &"hanan"
	_check(in_pool, "Hanan is in the random trial pool")
	for key in ["mayari", "apolaki", "tala", "bathala", "*"]:
		_check(hanan.transition_lines.has(key), "Hanan has a hand-over line for %s" % key)
	for other in [Gods.mayari(), Gods.apolaki(), Gods.tala()]:
		_check(other.transition_lines.has("hanan"), "%s has a hand-over line for Hanan" % other.display_name)

	var dawn := _favor("the_dawn")
	var even := _favor("even_playing_field")
	var light := _favor("first_light")
	var umaga := _favor("bagong_umaga")
	var rest := _favor("rest_and_refreshed")
	var chase := _favor("morning_chases_the_night")
	var sisters := _favor("the_three_sisters")
	_check(umaga.slot == GodFavor.Slot.Q and is_equal_approx(umaga.cooldown, 35.0), "Bagong Umaga is a 35s Q")
	_check(rest.slot == GodFavor.Slot.E and is_equal_approx(rest.cooldown, 30.0), "Rest and Refreshed is a 30s E")

	# --- The Dawn --------------------------------------------------------------------
	_setup(0, 0, 0)
	_rules.mortal(1).due = 2
	_rules.mortal(2).due = 1
	_due_events = 0
	_rules.bestow_favor(dawn)
	_check(_rules.mortal(1).due == 1 and _rules.mortal(2).due == 0 and _rules.mortal(3).due == 0,
		"The Dawn takes one God's Due from every mortal and never goes below 0")
	_check(_due_events == 2, "due_changed fires for each mortal whose Due changed (%d)" % _due_events)
	_setup(0, 0, 0)
	_due_events = 0
	_rules.bestow_favor(dawn)
	_check(_rules.mortal(1).due == 0 and _rules.mortal(2).due == 0 and _due_events == 0, "The Dawn at 0 dues changes nothing")

	# --- An Even Playing Field --------------------------------------------------------
	_setup(300, 1000, 100)
	_rules.bestow_favor(even)
	_check(_rules.mortal(2).favor == 550 and _rules.mortal(3).favor == 100 and _rules.mortal(1).favor == 300,
		"the top rival loses half the gap to the lowest mortal (1000 -> 550)")
	_setup(2000, 1000, 100)
	_rules.bestow_favor(even)
	_check(_rules.mortal(1).favor == 2000 and _rules.mortal(2).favor == 550, "when the holder is on top the best OTHER mortal is hit, never the holder")
	_setup(300, 1000, 1000)
	_rules.bestow_favor(even)
	var hit := int(_rules.mortal(2).favor < 1000) + int(_rules.mortal(3).favor < 1000)
	_check(hit == 1, "a tie for top hits exactly one of them")
	_setup(300, 1000, 100)
	_rules.mortal(2).favors.append(Gods.favor_by_id(&"waning_moon"))
	_rules.bestow_favor(even)
	_check(_rules.mortal(2).favor == 775, "the loss goes through lose_favor, so Waning Moon halves it (1000 -> 775)")
	_setup(300, 0, 0)
	_rules.bestow_favor(even)
	_check(_rules.mortal(2).favor == 0 and _rules.mortal(3).favor == 0, "with no gap nothing is taken")

	# --- First Light -------------------------------------------------------------------
	_setup(0, 500, 500)
	_rules.mortal(1).favors.append(light)
	_rules.begin_trial()
	_check(_rules.mortal(1).favor == 150, "the holder in last place gains 150 at the start of a trial")
	_setup(100, 0, 500)
	_rules.mortal(1).favors.append(light)
	_rules.begin_trial()
	_check(_rules.mortal(1).favor == 100, "a holder who is not last gains nothing")
	_setup(0, 0, 500)
	_rules.mortal(1).favors.append(light)
	_rules.mortal(2).favors.append(light)
	_rules.begin_trial()
	_check(_rules.mortal(1).favor == 150 and _rules.mortal(2).favor == 150, "every tied-last holder gets the bonus")
	_setup(400, 400, 400)
	_rules.mortal(1).favors.append(light)
	_rules.begin_trial()
	_check(_rules.mortal(1).favor == 400, "with everybody tied nobody is last, so nothing is paid")

	# --- Bagong Umaga -----------------------------------------------------------------
	_setup(1000, 0, 0)
	_rules.mortal(1).favors.append(umaga)
	_rules._clock = 100.0
	_rules.lose_favor(100, "old")
	_rules._clock = 110.0
	_rules.lose_favor(60, "recent")
	_rules._clock = 112.0
	var restored := _rules.restore_recent_losses(1, 5.0)
	_check(restored == 60 and _rules.mortal(1).favor == 900, "only the losses of the last 5s come back (%d)" % restored)
	_check(_rules.restore_recent_losses(1, 5.0) == 0, "a loss is only restored once")
	_setup(30, 0, 0)
	_rules._clock = 5.0
	_rules.lose_favor(100, "capped")
	_check(_rules.restore_recent_losses(1, 5.0) == 30 and _rules.mortal(1).favor == 30, "it never restores more than was actually lost")
	_setup(1000, 0, 0)
	_rules.mortal(1).favors.append(Gods.favor_by_id(&"full_moon"))
	_rules.mortal(1).favors.append(Gods.favor_by_id(&"waning_moon"))
	_rules._clock = 5.0
	_rules.lose_favor(200, "halved")  # Waning Moon: 100 really lost
	_check(_rules.restore_recent_losses(1, 5.0) == 100 and _rules.mortal(1).favor == 1000,
		"it restores what was lost AFTER loss modifiers, and Full Moon does not inflate it")
	_setup(1000, 0, 0)
	_rules.bestow_favor(umaga)
	_rules.lose_favor(80, "ouch")
	_rules.use_skill(GodFavor.Slot.Q)
	_arena._apply_skill_effect(umaga, 1)
	_check(_rules.mortal(1).favor == 1000, "the Q skill, run through the arena, gives the FAVOR back")

	# --- Rest and Refreshed ------------------------------------------------------------
	_setup(500, 2000, 100)
	_give_skills(2)
	_rules.mortal(2).durations[&"siblings_compromise"] = 3.0
	_rules.mortal(2).cooldowns[&"half_vision"] = 0.0
	_check(_rules.cast_rest_and_refreshed(1, rest) == 2, "Rest and Refreshed reaches every other mortal")
	_check(is_equal_approx(_rules.mortal(2).drowsy_time, 3.0) and is_equal_approx(_rules.mortal(3).drowsy_time, 3.0),
		"the other mortals grow drowsy for 3s")
	_check(_rules.mortal(1).drowsy_time == 0.0 and _rules.mortal(1).drowsy_stun == 0.0, "the caster is untouched")
	_check(_rules.mortal(2).durations.size() == 1 and is_equal_approx(_rules.mortal(2).cooldown_left(&"half_vision"), 0.0),
		"their own running skills and cooldowns are left alone")
	_rules._tick_afflictions(_rules.mortal(2), 2.9)
	_check(_rules.mortal(2).stun_time == 0.0, "no stun while the drowsiness still runs")
	_rules._tick_afflictions(_rules.mortal(2), 0.2)
	_check(_rules.mortal(2).drowsy_time == 0.0 and is_equal_approx(_rules.mortal(2).stun_time, 0.8), "...then 0.8s of stun")
	_rules._tick_afflictions(_rules.mortal(2), 0.9)
	_check(_rules.mortal(2).stun_time == 0.0, "...and the stun runs out")
	_setup(500, 2000, 100)
	_rules.mortals.erase(2)
	_rules.mortals.erase(3)
	_check(_rules.cast_rest_and_refreshed(1, rest) == 0, "alone, Rest and Refreshed has nobody to reach")
	# The E, cast through the arena (the real flow: use_skill, then the effect).
	_setup(0, 0, 0)
	_rules.bestow_favor(rest, 1)
	_rules.use_skill(GodFavor.Slot.E)
	_arena._apply_skill_effect(rest, 1)
	_check(is_equal_approx(_rules.mortal(2).drowsy_time, 3.0) and is_equal_approx(_rules.mortal(3).drowsy_time, 3.0),
		"the E, run through the arena, drowses the rivals")
	# a client sees the afflictions in the host's snapshot
	_setup(0, 0, 0)
	_rules.cast_rest_and_refreshed(1, rest)
	var client := GodMatch.new()
	client.setup_peers(Gods.hanan(), {1: "ME", 2: "RIVAL", 3: "RIVAL TWO"}, 1)
	root.add_child(client)
	client.apply_snapshot(_rules.snapshot())
	_check(is_equal_approx(client.mortal(2).drowsy_time, 3.0) and is_equal_approx(client.mortal(2).drowsy_stun, 0.8),
		"a client sees the drowsiness, and the stun it ends in")
	_check(is_equal_approx(client.mortal(2).stun_time, 0.0), "...with no stun until it does")
	client.queue_free()

	# --- Morning Chases the Night ------------------------------------------------------------
	_setup(0, 0, 0)
	_check(not _rules.is_favor_eligible(chase), "Morning Chases the Night is locked without a Mayari favor")
	_rules.bestow_favor(Gods.favor_by_id(&"full_moon"))
	_check(_rules.is_favor_eligible(chase), "a Mayari favor unlocks it")
	_setup(0, 0, 0)
	_rules.bestow_favor(Gods.apolaki().favors[0])
	_check(not _rules.is_favor_eligible(chase), "an Apolaki favor does not")
	_rules.bestow_favor(Gods.favor_by_id(&"waning_moon"))
	_rules.bestow_favor(chase)
	_rules.mortal(1).favor = 0
	_check(is_equal_approx(_arena._morning_cap(2.0), 0.5), "a 2s vision block is cut to 0.5s")
	_check(_rules.mortal(1).favor == 50, "...and pays +50 (%d)" % _rules.mortal(1).favor)
	_rules.mortal(1).favor = 0
	_check(is_equal_approx(_arena._morning_cap(0.4), 0.4) and _rules.mortal(1).favor == 0, "a block already under 0.5s is untouched and pays nothing")
	_rules.mortal(2).favors.append(chase)
	var rival_before: int = _rules.mortal(2).favor
	_check(is_equal_approx(_arena._morning_cap_for(_rules.mortal(2), 5.0), 0.5), "Mayari's Sibling's Rivalry block on a holder is cut to 0.5s")
	_check(_rules.mortal(2).favor == rival_before + 50, "...and the cut-short block pays the rival +50")
	_check(is_equal_approx(_arena._morning_cap_for(_rules.mortal(3), 5.0), 5.0), "a mortal without the favor keeps the full block")

	# --- The Three Sisters ---------------------------------------------------------------------
	_setup(0, 0, 0)
	_check(not _rules.is_favor_eligible(sisters), "The Three Sisters is locked with no sister's favor")
	_rules.bestow_favor(Gods.apolaki().favors[0])
	_check(not _rules.is_favor_eligible(sisters), "an Apolaki favor is not enough")
	_rules.bestow_favor(Gods.tala().favors[0])
	_check(_rules.is_favor_eligible(sisters), "a Tala favor alone unlocks it")
	_rules.mortal(2).favors.append(Gods.favor_by_id(&"half_vision"))
	_check(_rules.is_favor_eligible(sisters, 2), "a Mayari favor alone unlocks it")
	var mayari_id := "half_vision"
	var tala_id := str(Gods.tala().favors[0].id)
	_check(GodMatch.three_sisters_bonus(["the_three_sisters", mayari_id, tala_id, "waning_moon"]) == 300, "+150 for each of the two sisters held")
	_check(GodMatch.three_sisters_bonus(["the_three_sisters", mayari_id, "waning_moon"]) == 150, "two favors of one sister still count once")
	_check(GodMatch.three_sisters_bonus([mayari_id, tala_id]) == 0, "without the favor there is no bonus")
	_check(GodMatch.three_sisters_bonus(["the_three_sisters"]) == 0, "the favor alone, with no sisters, pays nothing")

	print("Hanan favor checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _favor(id: String) -> GodFavor:
	var favor := Gods.hanan().get_favor(StringName(id))
	_check(favor != null, "Hanan bestows %s" % id)
	return favor


# A fresh trio of mortals (1 is the local one) with the given FAVOR.
func _setup(mine: int, rival: int, rival_two: int) -> void:
	_rules.setup(Gods.hanan(), "ME", ["RIVAL", "RIVAL TWO"], false)
	_rules.mortal(1).favor = mine
	_rules.mortal(2).favor = rival
	_rules.mortal(3).favor = rival_two
	_rules._clock = 0.0


func _give_skills(player_id: int) -> void:
	_rules.bestow_favor(Gods.favor_by_id(&"half_vision"), player_id)
	_rules.bestow_favor(Gods.favor_by_id(&"siblings_compromise"), player_id)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
