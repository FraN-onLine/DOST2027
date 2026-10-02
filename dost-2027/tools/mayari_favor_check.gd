extends SceneTree

# Focused regression check for Mayari's favors - the ones the two siblings share
# and the one that asks for nothing at all:
#
#   * Sibling's Compromise (Q) doubles the FAVOR you gain for 5s on a 30s
#     cooldown and is offered whether or not you hold an Apolaki favor,
#   * Sibling's Rivalry is only offered while an Apolaki favor is held, and once
#     you are 1000 FAVOR BEHIND a mortal it blocks part of that rival's screen
#     for 5s - once per rival, once per trial.
#
# Run: godot --headless --path <project> -s res://tools/mayari_favor_check.gd

var _arena: MayariArena
var _problems := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	get_root().add_child(view)
	_arena = load("res://scenes/gods/mayari/MayariArena.tscn").instantiate()
	view.add_child(_arena)
	await process_frame
	await process_frame
	if _arena.god == null or _arena.rules == null:
		printerr("FAIL: the arena did not resolve Mayari and her match")
		quit(1)
		return

	var guard := 0
	while _arena.dialogue.is_active() and guard < 40:
		_arena.dialogue.advance()
		guard += 1
	_arena._phase = Arena.Phase.PLAYING
	_arena.player.set_lock(false)
	_arena.rules.local().favor = 0
	_arena.rules.ensure_mortal(2, "RIVAL").favor = 0

	# --- Sibling's Compromise: no Apolaki favor required ----------------------
	var compromise: GodFavor = _arena.god.get_favor(&"siblings_compromise")
	_check(compromise != null, "Mayari bestows Sibling's Compromise")
	_check(_arena.rules.is_favor_eligible(compromise),
		"Sibling's Compromise is offered without an Apolaki favor")
	_check(is_equal_approx(compromise.cooldown, 30.0) and is_equal_approx(compromise.duration, 5.0),
		"Sibling's Compromise is a 5s effect on a 30s cooldown")
	_arena.rules.bestow_favor(compromise)
	_check(_arena.rules.local().has_favor(&"siblings_compromise"), "Sibling's Compromise binds to the mortal")
	var used := _arena.rules.use_skill(GodFavor.Slot.Q)
	_check(used != null and used.id == &"siblings_compromise", "the Q slot fires Sibling's Compromise")
	_check(is_equal_approx(_arena.rules.gain_multiplier(_arena.rules.local()), 2.0),
		"an active Sibling's Compromise doubles the FAVOR you gain")
	var gain_before: int = _arena.rules.local().favor
	_arena.rules.add_favor(50, "test gain")
	_check(_arena.rules.local().favor == gain_before + 100, "a +50 payout lands as +100 while it lasts")
	_arena.rules.local().durations[&"siblings_compromise"] = 0.0
	_check(is_equal_approx(_arena.rules.gain_multiplier(_arena.rules.local()), 1.0),
		"the doubling stops when the five seconds run out")

	# --- Sibling's Rivalry: an Apolaki favor is the ticket --------------------
	var rivalry: GodFavor = _arena.god.get_favor(&"siblings_rivalry_moon")
	_check(rivalry != null, "Mayari bestows Sibling's Rivalry")
	_check(not _arena.rules.is_favor_eligible(rivalry), "Sibling's Rivalry is locked without an Apolaki favor")
	_arena.rules.bestow_favor(Gods.apolaki().favors[0])
	_check(_arena.rules.is_favor_eligible(rivalry), "an Apolaki favor unlocks Sibling's Rivalry")
	_arena.rules.bestow_favor(rivalry)

	# Ahead of a rival: Mayari's half stays silent - that is Apolaki's moment.
	_arena.rules.local().favor = 2000
	_arena.rules.mortal(2).favor = 1000
	_arena._tick_siblings_rivalry()
	_check(_patch_count(2) == 0, "being AHEAD does not fire Mayari's Sibling's Rivalry")

	# Behind by the threshold: the rival's screen goes dark, once per rival.
	_arena._sun_patches.clear()
	_arena._rivalry_claimed.clear()
	_arena.rules.local().favor = 1
	_arena.rules.mortal(2).favor = 1000
	_arena._tick_siblings_rivalry()
	_check(_patch_count(2) == 0, "999 FAVOR behind is not far enough")
	_arena.rules.local().favor = 0
	_arena._tick_siblings_rivalry()
	_check(_patch_count(2) == 4, "1000 FAVOR behind blocks part of the rival's screen")
	_arena._tick_siblings_rivalry()
	_check(_patch_count(2) == 4, "it fires only once per rival")
	_check(is_equal_approx(_patch_seconds(2), 5.0), "the rival's screen stays blocked for 5 seconds")

	# A second rival is a second claim: one per mortal.
	_arena.rules.ensure_mortal(3, "RIVAL TWO").favor = 5000
	_arena._tick_siblings_rivalry()
	_check(_patch_count(3) == 4, "each rival gets its own claim")

	print("Mayari favor checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


# How many screen-blocking patches sit on the given mortal.
func _patch_count(player_id: int) -> int:
	return (_arena._sun_patches.get(player_id, []) as Array).size()


# Seconds left on the first of them (0.0 when there is none).
func _patch_seconds(player_id: int) -> float:
	var timers: Array = _arena._sun_patches.get(player_id, [])
	if timers.is_empty():
		return 0.0
	return float(timers[0])


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1