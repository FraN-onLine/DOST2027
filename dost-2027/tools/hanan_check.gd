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

	# --- screen blocks cover the bar, the labels stay readable ------------------------
	var vision: CanvasLayer = _arena.get_node("VisionLayer")
	var patches: CanvasLayer = _arena.get_node("Patches")
	var bar_layer: CanvasLayer = _arena.get_node_or_null("BarLayer")
	var label_layer: CanvasLayer = _arena.get_node_or_null("HananHud")
	_check(bar_layer != null and _arena.bar.get_parent() == bar_layer, "the balance bar lives on its own layer")
	_check(bar_layer != null and bar_layer.layer < vision.layer and bar_layer.layer < patches.layer,
		"the bar is drawn below Mayari's blackout (%d) and Apolaki's sun patches (%d)" % [vision.layer, patches.layer])
	_check(label_layer != null and label_layer.layer > vision.layer and label_layer.layer > patches.layer
		and _arena.status_label.get_parent() == label_layer and _arena.callout_label.get_parent() == label_layer
		and _arena.hint_label.get_parent() == label_layer, "the status, callout and hint labels are drawn above them")
	_arena.begin_vault()
	_arena._refresh_hud(0.0)
	var feet: Vector2 = _arena.player.get_global_transform_with_canvas().origin
	var bar_box: Rect2 = Rect2(_arena.bar.position, _arena.bar.size)
	_check(bar_box.grow(_arena.bar_offset.length() + 1.0).has_point(feet), "the bar hangs right beside the mortal (%s, mortal at %s)" % [str(bar_box), str(feet)])
	_check(bar_box.position.x >= Arena.UI_STRIP_WIDTH and bar_box.end.x <= 1152.0 and bar_box.position.y >= 0.0 and bar_box.end.y <= 648.0,
		"the bar stays on screen and clear of the UI strip")
	_arena.player.global_position.x = 1140.0
	_arena._refresh_hud(0.0)
	_check(_arena.bar.position.x + _arena.bar.size.x <= 1152.0, "near the right edge the bar is clamped onto the screen")
	_arena._leave_vault()
	_arena._enter_run()

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

	# --- the God's Due menu pauses a vault --------------------------------------------------
	_arena._leave_vault()
	_arena._enter_run()
	_arena._level = 3  # a box that moves on its own
	_arena.rules.local().favor = 500
	_arena.begin_vault()
	for step in range(20):
		_arena._holding = _arena._ind_pos < _arena._box_center
		_arena._tick_vault(DT)
	var frozen_box: float = _arena._box_center
	var frozen_ind: float = _arena._ind_pos
	var frozen_left: float = _arena._vault_left
	var frozen_favor: int = _arena.rules.local().favor
	_arena._holding = false  # the button is let go to click in the menu
	_arena._toggle_due_menu()
	_check(_arena.due_menu.is_open(), "(the God's Due menu opens mid-vault)")
	for step in range(int(_arena.grace_time * 3.0 / DT)):
		_arena._tick_vault(DT)
	_check(_arena._vault_state == HananArena.Vault.VAULT, "a menu open longer than the grace time does not trip the mortal")
	_check(_arena._box_center == frozen_box and _arena._ind_pos == frozen_ind and _arena._vault_left == frozen_left,
		"the box, the indicator and the vault clock all wait")
	_check(_arena.rules.local().favor == frozen_favor, "nothing is banked while the menu is open")
	_arena._holding = true  # a click used inside the menu...
	_arena.due_menu.close()
	_arena._tick_vault(DT)
	_check(_arena._vault_state == HananArena.Vault.VAULT and not _arena._holding,
		"closing the menu resumes the vault, with the button read fresh (not held)")
	_check(is_equal_approx(_arena._vault_left, frozen_left - DT), "the vault clock picks up where it stopped")
	_arena._leave_vault()
	_arena._enter_run()

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

	# --- the trial ends mid-vault: what it earned is banked --------------------------------
	_arena._level = 1
	_arena._enter_run()
	_arena.begin_vault()
	_arena.rules.local().favor = 500
	_arena._pending_gain = 37.6
	_arena._end_trial()
	_check(_arena.rules.local().favor == 537, "ending the trial mid-vault banks the pending FAVOR (%d)" % _arena.rules.local().favor)
	var result: Dictionary = _arena._results.get(_arena._my_id, {})
	_check(int(result.get("favor", 0)) == 537, "...before the results are written, so it shows in this trial's standings")
	_arena._tick_hanan(DT)
	_check(_arena._vault_state == HananArena.Vault.RUN, "the vault is put away once the round is over")

	print("Hanan arena checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
