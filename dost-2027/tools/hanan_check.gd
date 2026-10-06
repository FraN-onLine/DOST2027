extends SceneTree

# Validation: Hanan's Luksong Baka. The balance bar rises while the attack button
# is held and falls when it is released; time in the box earns FAVOR and a clean
# vault builds the combo; leaving the box past the grace time is a trip (FAVOR
# lost, combo reset); the Baka gets smaller / faster as the levels climb.
# Run: godot --headless --path <project> -s res://tools/hanan_check.gd

const DT := 1.0 / 60.0

var _arena: HananArena
var _problems := 0


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
	if _arena.god == null or _arena.god.id != &"hanan" or _arena.baka == null:
		printerr("FAIL: the arena needs Hanan and a Baka")
		quit(1)
		return
	var guard := 0
	while _arena.dialogue.is_active() and guard < 40:
		_arena.dialogue.advance()
		guard += 1
	_arena._phase = Arena.Phase.PLAYING
	_arena.player.set_lock(false)
	_arena.rules.local().favor = 500
	_check(_arena.separate_players(), "Luksong Baka is a personal trial")

	# --- the bar: hold rises, release falls ---------------------------------------
	_arena.begin_vault()
	_arena._ind_pos = 0.3
	_arena._ind_vel = 0.0
	var before: float = _arena._ind_pos
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	_arena._input(press)
	_check(_arena._holding, "pressing the attack button holds the bar up")
	for step in range(15):
		_arena._step_indicator(DT)
	var risen: float = _arena._ind_pos
	_check(risen > before, "holding raises the indicator (%.2f -> %.2f)" % [before, risen])
	_check(_arena._ind_vel > 0.0, "the indicator has velocity, it does not snap")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	_arena._input(release)
	_check(not _arena._holding, "releasing lets go")
	for step in range(10):
		_arena._step_indicator(DT)
	_check(_arena._ind_vel < 0.65, "the indicator keeps its momentum for a moment - floaty, not snappy")
	for step in range(40):
		_arena._step_indicator(DT)
	_check(_arena._ind_pos < risen, "releasing lowers the indicator")
	for step in range(300):
		_arena._step_indicator(DT)
	_check(_arena._ind_pos == 0.0, "gravity brings it to the floor")
	_arena._ind_pos = 1.0
	_arena._holding = true
	for step in range(300):
		_arena._step_indicator(DT)
	_check(_arena._ind_pos <= 1.0, "the indicator stays on the gauge")
	_arena._holding = false

	# --- a clean vault: FAVOR and combo ---------------------------------------------
	_arena._leave_vault()
	_arena._enter_run()
	_arena.rules.local().favor = 500
	_arena._combo = 1.0
	_arena.begin_vault()
	for step in range(400):
		if _arena._vault_state != HananArena.Vault.VAULT:
			break
		_arena._holding = _arena._ind_pos < _arena._box_center
		_arena._tick_vault(DT)
	_check(_arena._vault_state == HananArena.Vault.RUN, "a vault held in the box ends clean and the next run starts")
	_check(is_equal_approx(_arena._combo, 1.25), "a clean vault adds 0.25 to the combo (%.2f)" % _arena._combo)
	_check(_arena.rules.local().favor > 500 + 60, "time in the box earns FAVOR (%d)" % (_arena.rules.local().favor - 500))
	_arena._combo = _arena.combo_cap
	_arena.begin_vault()
	_arena._clean_vault()
	_check(is_equal_approx(_arena._combo, _arena.combo_cap), "the combo stops at its cap")

	# --- a trip ------------------------------------------------------------------------
	_arena._enter_run()
	_arena.rules.local().favor = 500
	_arena._combo = 2.0
	_arena.begin_vault()
	_arena._holding = false
	for step in range(400):
		if _arena._vault_state != HananArena.Vault.VAULT:
			break
		_arena._tick_vault(DT)
	_check(_arena._vault_state == HananArena.Vault.STUMBLE, "drifting out past the grace time trips the mortal")
	_check(_arena.rules.local().favor <= 500 - _arena.trip_penalty + 40, "a trip costs FAVOR (%d)" % _arena.rules.local().favor)
	_check(is_equal_approx(_arena._combo, 1.0), "a trip resets the combo")
	_arena._state_timer = 0.0
	_arena._tick_hanan(DT)
	_check(_arena._vault_state == HananArena.Vault.RUN, "after the stumble the next run starts")
	# a short wobble outside the box is forgiven
	_arena.begin_vault()
	_arena._ind_pos = 1.0
	_arena._box_center = 0.3
	_arena._tick_vault(DT)
	_check(_arena._vault_state == HananArena.Vault.VAULT, "a moment outside the box inside the grace time is no trip")

	# --- the levels ------------------------------------------------------------------------
	_arena._leave_vault()
	_arena._enter_run()
	_arena._level = 1
	_arena._clean_in_level = 0
	var size_level_1: float = _arena.current_box_size()
	for vault in range(_arena.vaults_per_level):
		_arena.begin_vault()
		_arena._clean_vault()
	_check(_arena._level == 2, "three clean vaults advance the level")
	_check(_arena.current_box_size() < size_level_1, "Sitting Baka has a shorter box")
	_arena._level = 3
	_check(_arena.current_drift_speed() > _arena.drift_speeds[0], "Standing Baka drifts faster")
	_arena._level = 4
	_check(_arena.current_box_size() < _arena.box_sizes[2], "High Baka has a much smaller box")
	_arena._level = 7
	_check(_arena.level_name() == "OVER THE MOON", "level 5 and beyond is Over the Moon")
	for level in range(1, 8):
		_arena._level = level
		_arena._enter_run()
		_arena.begin_vault()
		for step in range(240):
			_arena._step_box(DT)
		var half: float = _arena.current_box_size() * 0.5
		_check(_arena._box_center >= half - 0.0001 and _arena._box_center <= 1.0 - half + 0.0001,
			"level %d keeps the box on the gauge" % level)
		_arena._leave_vault()

	print("Hanan arena checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
