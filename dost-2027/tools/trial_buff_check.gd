extends SceneTree

# Validation: whatever a mortal holds at the end of a trial - FAVOR, God's Due
# vouchers and the favors (buffs) themselves - is waiting for them at the start
# of the next trial. The shell snapshots its GodMatch on trial_complete and
# replays that snapshot into the next arena's fresh GodMatch, so this checks the
# whole round trip: grant -> complete trial -> new arena -> still owned.
# Run: godot --headless --path <project> -s res://tools/trial_buff_check.gd

var _shell


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _watchdog() -> void:
	await create_timer(30.0).timeout
	printerr("trial_buff_check: timed out")
	quit()


func _run() -> void:
	_watchdog()
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	get_root().add_child(view)

	_shell = load("res://scenes/Game.tscn").instantiate()
	view.add_child(_shell)
	await _frames(4)

	if _shell.arena == null or _shell.rules == null:
		printerr("trial_buff_check: NO ARENA LOADED")
		_done()
		return

	var god: God = _shell.arena.god
	var rules: GodMatch = _shell.rules
	# Take two buffs: a passive and the E skill, plus a pile of FAVOR and two
	# vouchers - everything a player would carry out of a trial.
	var passive: GodFavor
	var skill: GodFavor
	for favor in god.favors:
		if not rules.is_favor_eligible(favor):
			continue  # e.g. a rivalry favor that asks for another god's favor first
		if passive == null and favor.slot == GodFavor.Slot.PASSIVE and favor.kind == GodFavor.Kind.PASSIVE:
			passive = favor
		if skill == null and favor.slot == GodFavor.Slot.E:
			skill = favor
	if passive == null or skill == null:
		printerr("trial_buff_check: the opening god needs a passive and an E favor")
		_done()
		return
	rules.bestow_favor(passive)
	rules.bestow_favor(skill)
	rules.local().favor = 4321
	rules.local().due = 2
	print("before trial: buffs=%s favor=%d due=%d" % [
		str(rules.local().favors.map(func(f): return str(f.id))),
		rules.local().favor, rules.local().due])

	# End the trial exactly where the shell does when the arena reports it.
	_shell._on_trial_complete()
	await _frames(8)

	var problems := 0
	if _shell.arena == null:
		printerr("trial_buff_check: the next trial's arena was dropped")
		problems += 1
	if _shell.rules == null:
		printerr("trial_buff_check: the shell lost its GodMatch between trials (HUD and buffs both die)")
		problems += 1
	if _shell.rules == null or _shell.arena == null:
		_done(problems)
		return

	var after: GodMatch = _shell.rules
	var m := after.local()
	var held: Array = m.favors.map(func(f): return str(f.id))
	print("after trial:  buffs=%s favor=%d due=%d | shell rules god=%s" % [
		str(held), m.favor, m.due, str(after.god.id)])
	if not m.has_favor(passive.id):
		printerr("trial_buff_check: the passive buff did not survive the trial")
		problems += 1
	if not m.has_favor(skill.id):
		printerr("trial_buff_check: the E skill buff did not survive the trial")
		problems += 1
	if m.favor != 4321:
		printerr("trial_buff_check: FAVOR did not survive the trial (%d != 4321)" % m.favor)
		problems += 1
	if m.due != 2:
		printerr("trial_buff_check: God's Due vouchers did not survive the trial (%d != 2)" % m.due)
		problems += 1

	# A buff from a previous god must also be findable in the snapshot the shell
	# replays - favors are looked up across every god, not only today's host.
	var foreign := God.new()
	foreign.id = &"apolaki_test"
	var sun: GodFavor = GodFavor.new()
	sun.id = &"the_great"
	sun.god_id = &"apolaki"
	m.favors.append(sun)
	_shell.run_snapshot = after.snapshot()
	_shell._on_trial_complete()
	await _frames(8)
	if _shell.rules != null:
		var later: GodMatch = _shell.rules
		if not later.local().has_favor(&"the_great"):
			printerr("trial_buff_check: a favor from another god was dropped between trials")
			problems += 1
		else:
			print("cross-god buff kept: the_great")

	if problems == 0:
		print("trial buffs: 0 problem(s)")
	else:
		printerr("trial buffs: %d problem(s)" % problems)
	_done(problems)


func _done(problems := 0) -> void:
	print("--- DONE ---")
	quit(1 if problems > 0 else 0)
