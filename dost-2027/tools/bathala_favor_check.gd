extends SceneTree

# Regression check for Bathala's six favors - every one is about sacrifice:
#   Our Partnership Ends Here (Mayari)  - pay 500, curse the field with blindness.
#   Our Partnership Ends Here (Apolaki) - pay 500, curse the field with Sun Patches.
#   Bathala Na                          - pour out every God's Due, +350 each.
#   Si Batman                           - pay 1500, then nothing can take FAVOR.
#   Blindside (E)                       - halve the leader, they win 80% back over 4s.
#   Vantage Point (Q)                   - halve yourself, win 120% back over 6s.
# Run: godot --headless --path <project> -s res://tools/bathala_favor_check.gd

const DT := 0.25  # exact in binary: four steps are exactly one second

var _arena: BathalaArena
var _rules: GodMatch
var _problems := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)
	_arena = load("res://scenes/gods/bathala/BathalaArena.tscn").instantiate()
	view.add_child(_arena)
	await process_frame
	await process_frame
	var guard := 0
	while _arena.dialogue.is_active() and guard < 40:
		_arena.dialogue.advance()
		guard += 1
	_arena._phase = Arena.Phase.PLAYING
	_rules = _arena.rules

	var bathala := Gods.bathala()
	_check(bathala != null and bathala.implemented, "Bathala is a registered, implemented god")
	_check(bathala.favors.size() == 6, "Bathala bestows six favors (%d)" % bathala.favors.size())

	var mayari := _favor("our_partnership_ends_mayari")
	var apolaki := _favor("our_partnership_ends_apolaki")
	var na := _favor("bathala_na")
	var batman := _favor("si_batman")
	var half := _favor("half_vision_sacrifice")
	var sibling := _favor("siblings_compromise_bathala")
	_check(half.display_name == "Blindside" and sibling.display_name == "Vantage Point", "the E and Q favors are named Blindside and Vantage Point")
	_check(half.slot == GodFavor.Slot.E and is_equal_approx(half.cooldown, 60.0), "Blindside is a 60s E")
	_check(sibling.slot == GodFavor.Slot.Q and is_equal_approx(sibling.cooldown, 45.0), "Vantage Point is a 45s Q")

	# --- Our Partnership Ends Here (Mayari): pay 500, curse the field ------------
	_setup(1000, 800, 600)
	_rules.bestow_favor(mayari)
	_check(_rules.mortal(1).favor == 500, "Our Partnership Ends Here (Mayari) costs 500 FAVOR (%d)" % _rules.mortal(1).favor)
	_check(_rules.mortal(1).mayari_curse > 0.0, "...and marks Mayari's blindness on the field")
	_arena._on_favor_fired(2, mayari, "curse")
	_check(_arena._blind_time > 0.0, "Mayari's curse darkens the opposing mortal's screen")

	# --- Our Partnership Ends Here (Apolaki): pay 500, Sun Patches ---------------
	_setup(1000, 800, 600)
	_rules.bestow_favor(apolaki)
	_check(_rules.mortal(1).favor == 500, "Our Partnership Ends Here (Apolaki) costs 500 FAVOR (%d)" % _rules.mortal(1).favor)
	_check(_rules.mortal(1).apolaki_curse > 0.0 and _rules.mortal(1).apolaki_patches == 4, "...and promises 4 Sun Patches")
	_arena._on_favor_fired(2, apolaki, "curse")
	_check((_arena._sun_patches.get(2, []) as Array).size() == 4, "Apolaki's curse lands 4 Sun Patches on the opposing mortal")

	# --- Bathala Na: pour out every God's Due, +350 each ------------------------
	_setup(0, 0, 0)
	_rules.milestone_step = 1 << 30  # keep the 1050 payout from handing a fresh Due back
	_rules.mortal(1).due = 3
	_rules.bestow_favor(na)
	_check(_rules.mortal(1).due == 0, "Bathala Na spends every God's Due (%d left)" % _rules.mortal(1).due)
	_check(_rules.mortal(1).favor == 3 * 350, "...and pays 350 FAVOR for each (%d)" % _rules.mortal(1).favor)
	_setup(0, 0, 0)
	_rules.mortal(1).due = 0
	_rules.bestow_favor(na)
	_check(_rules.mortal(1).favor == 0, "with no God's Due it pays nothing")

	# --- Si Batman: pay 1500, then nothing can take FAVOR -----------------------
	_setup(2000, 0, 0)
	_rules.bestow_favor(batman)
	_check(_rules.mortal(1).favor == 500, "Si Batman costs 1500 FAVOR up front (%d)" % _rules.mortal(1).favor)
	_check(_rules.mortal(1).batman_shield, "...and raises the shield")
	_rules.lose_favor(9999, "anything", 1)
	_check(_rules.mortal(1).favor == 500, "nothing can take the shielded mortal's FAVOR away (%d)" % _rules.mortal(1).favor)
	_check(_rules.mortal(2).batman_shield == false, "other mortals are not shielded")

	# --- Blindside (E): halve the leader, they win 80% back over 4s --------------
	_setup(0, 1000, 0)
	_rules.bestow_favor(half, 1)
	_arena._apply_skill_effect(half, 1)
	_check(_rules.mortal(2).favor == 500, "Blindside cuts the leader's FAVOR in half (%d)" % _rules.mortal(2).favor)
	_check(not (_rules.mortal(2).bathala_regrowth as Array).is_empty(), "...and queues a slow return for the leader")
	var before_recover: int = _rules.mortal(2).favor
	for step in range(int(4.0 / DT) + 1):
		_rules._tick_mortal(_rules.mortal(2), DT)
	_check(_rules.mortal(2).favor - before_recover >= 390 and _rules.mortal(2).favor - before_recover <= 410,
		"over 4s the leader wins back 80%% of the cut (+%d)" % (_rules.mortal(2).favor - before_recover))

	# --- Vantage Point (Q): halve yourself, win 120% back over 6s ----------------
	_setup(1000, 0, 0)
	_rules.bestow_favor(sibling, 1)
	_arena._apply_skill_effect(sibling, 1)
	_check(_rules.mortal(1).favor == 500, "Vantage Point cuts your own FAVOR in half (%d)" % _rules.mortal(1).favor)
	before_recover = _rules.mortal(1).favor
	for step in range(int(6.0 / DT) + 1):
		_rules._tick_mortal(_rules.mortal(1), DT)
	_check(_rules.mortal(1).favor - before_recover >= 590 and _rules.mortal(1).favor - before_recover <= 610,
		"over 6s you win back 120%% of the cut (+%d)" % (_rules.mortal(1).favor - before_recover))

	print("Bathala favor checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _favor(id: String) -> GodFavor:
	var favor := Gods.bathala().get_favor(StringName(id))
	_check(favor != null, "Bathala bestows %s" % id)
	return favor


func _setup(mine: int, rival: int, rival_two: int) -> void:
	_rules.setup(Gods.bathala(), "ME", ["RIVAL", "RIVAL TWO"], false)
	_rules.mortal(1).favor = mine
	_rules.mortal(2).favor = rival
	_rules.mortal(3).favor = rival_two
	_rules._clock = 0.0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1

