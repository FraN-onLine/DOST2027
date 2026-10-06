extends SceneTree

# Regression check for Hanan's seven favors, edge cases included:
#   The Dawn (0 dues), An Even Playing Field (holder on top, ties, loss modifiers),
#   First Light (last place, everyone tied), Bagong Umaga (only what was really
#   lost, Full Moon cannot inflate it), Break of Day (leader / second place / ties,
#   and a client accepting the cooldown going UP), Morning Chases the Night
#   (eligibility and the 0.5s cap) and The Three Sisters (eligibility and bonus).
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
	var day := _favor("break_of_day")
	var chase := _favor("morning_chases_the_night")
	var sisters := _favor("the_three_sisters")
	_check(umaga.slot == GodFavor.Slot.Q and is_equal_approx(umaga.cooldown, 35.0), "Bagong Umaga is a 35s Q")
	_check(day.slot == GodFavor.Slot.E and is_equal_approx(day.cooldown, 30.0), "Break of Day is a 30s E")

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

	# --- Break of Day ------------------------------------------------------------------
	_setup(500, 2000, 100)
	_give_skills(2)
	_rules.mortal(2).durations[&"siblings_compromise"] = 3.0
	_rules.mortal(2).cooldowns[&"half_vision"] = 0.0
	_rules.mortal(2).cooldowns[&"siblings_compromise"] = 0.0
	_check(_rules.break_of_day(1) == 2, "Break of Day hits the leading mortal")
	_check(_rules.mortal(2).durations.is_empty(), "every active favor duration on them ends")
	_check(is_equal_approx(_rules.mortal(2).cooldown_left(&"half_vision"), 25.0)
		and is_equal_approx(_rules.mortal(2).cooldown_left(&"siblings_compromise"), 30.0), "their E and Q restart at a full cooldown")
	_setup(3000, 2000, 100)
	_check(_rules.break_of_day(1) == 2, "when the caster leads, second place is hit")
	_setup(1000, 1000, 100)
	_check(_rules.break_of_day(1) == 2, "tied at the top with the caster, the other leader is hit")
	_setup(500, 1000, 1000)
	var seen := {}
	for attempt in range(40):
		seen[_rules.break_of_day(1)] = true
	_check(seen.size() == 2 and seen.has(2) and seen.has(3) and not seen.has(1), "tied leaders are picked at random, never the caster")
	_rules.mortals.erase(2)
	_rules.mortals.erase(3)
	_check(_rules.break_of_day(1) == -1, "alone, Break of Day has nobody to reach")
	# Break of Day also ends the effects of the target's casts that live in the
	# arena: Apolaki's Sibling's Compromise (doubled loss + a sun patch on every
	# other mortal) and Tala's Let Us Light Your Way (everyone pulled to them).
	_setup(500, 2000, 100)
	_arena._double_loss.clear()
	_arena._double_loss_source.clear()
	_arena._sun_patches.clear()
	_arena._sun_patch_sources.clear()
	_arena._apply_skill_effect(Gods.favor_by_id(&"siblings_compromise_sun"), 2)
	_arena._apply_skill_effect(Gods.favor_by_id(&"let_us_light_your_way"), 2)
	_arena._add_sun_patches(3, 1, 5.0)  # a patch somebody else put there
	_check(_arena._double_loss.has(1) and _arena._double_loss.has(3), "(Compromise doubles the losses of mortals 1 and 3)")
	_check(_patch_count(1) == 1 and _patch_count(3) == 2, "(...and puts a patch on each of them)")
	_check(_arena._movement_override_caster == 2 and _arena._movement_override_time > 0.0, "(Light Your Way pulls everyone to mortal 2)")
	_arena._apply_skill_effect(day, 1)
	_check(not _arena._double_loss.has(1) and not _arena._double_loss.has(3), "Break of Day ends the doubled loss on their victims")
	_check(_patch_count(1) == 0 and _patch_count(3) == 1, "it removes the patches they added, and only those")
	_check(_arena.active_sun_patches() == 0, "the patch on our own screen comes down")
	_check(_arena._movement_override_time == 0.0, "it ends their Light Your Way pull")
	_arena._start_movement_override(5, 1.0)
	_arena._on_movement_override_received(5, 0.0)
	_check(_arena._movement_override_time == 0.0, "a 0-second override from the host means stop now")

	# a client has to accept the cooldown going UP
	_setup(500, 2000, 100)
	_give_skills(2)
	var client := GodMatch.new()
	client.setup_peers(Gods.hanan(), {1: "ME", 2: "RIVAL", 3: "RIVAL TWO"}, 1)
	root.add_child(client)
	client.apply_snapshot(_rules.snapshot())
	_check(is_equal_approx(client.mortal(2).cooldown_left(&"half_vision"), 0.0), "(a client starts with no cooldown on them)")
	_rules.break_of_day(1)
	client.apply_snapshot(_rules.snapshot())
	_check(is_equal_approx(client.mortal(2).cooldown_left(&"half_vision"), 25.0), "a client accepts a cooldown that jumped UP")
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


func _patch_count(player_id: int) -> int:
	return (_arena._sun_patches.get(player_id, []) as Array).size()


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
