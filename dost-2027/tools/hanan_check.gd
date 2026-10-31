extends SceneTree

# Validation: Hanan's Luksong Baka. The balance bar rises while the attack button
# is held and falls when it is released; every vault opens with a READY beat that
# earns nothing and cannot trip; time in the box earns FAVOR and a clean vault
# builds the combo and carries the mortal OVER the Baka to the far side (the next
# vault goes back); leaving the box past the grace time is a trip that leaves them
# on the approach side (FAVOR lost by level, combo reset, no teleport); two trips
# in a row lower the level; the first-visit practice vault; the Baka gets smaller
# / faster as the levels climb; the Gising Na! alarm clock; and the labels never
# shake.
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
	_arena._end_intro_shot()  # straight to play: no countdown, so no intro shot either
	_arena._trial_time = 999.0  # the clock never runs out while the checks await physics frames
	_arena.player.set_lock(false)
	_arena.rules.local().favor = 500
	_check(_arena.separate_players(), "Luksong Baka is a personal trial")

	# --- screen blocks cover the bar, the labels stay readable ------------------------
	var vision: CanvasLayer = _arena.get_node("VisionLayer")
	var patches: CanvasLayer = _arena.get_node("Patches")
	var bar_layer: CanvasLayer = _arena.get_node_or_null("BarLayer")
	var label_layer: CanvasLayer = _arena.popup_layer
	_check(bar_layer != null and _arena.bar.get_parent() == bar_layer, "the balance bar lives on its own layer")
	_check(bar_layer != null and bar_layer.layer < vision.layer and bar_layer.layer < patches.layer,
		"the bar is drawn below Mayari's blackout (%d) and Apolaki's sun patches (%d)" % [vision.layer, patches.layer])
	var band_layer: CanvasLayer = _arena.get_node_or_null("BandLayer")
	_check(label_layer != null and label_layer.layer > vision.layer and label_layer.layer >= patches.layer
		and label_layer.get_index() > patches.get_index() and _arena.callout_label.get_canvas_layer_node() == label_layer,
		"the callout pill is drawn above them (popup layer %d, after the patches)" % (label_layer.layer if label_layer != null else -1))
	_check(band_layer != null and band_layer.layer > vision.layer and band_layer.layer > patches.layer
		and _arena.status_label.get_canvas_layer_node() == band_layer and _arena.hint_label.get_canvas_layer_node() == band_layer,
		"the status and hint, in the bottom band, are drawn above them too")
	_arena.begin_vault()
	_arena._refresh_hud(0.0)
	var feet: Vector2 = _arena.player.get_global_transform_with_canvas().origin
	var bar_box: Rect2 = Rect2(_arena.bar.position, _arena.bar.size)
	_check(bar_box.position.x >= feet.x and not _arena.bar.outer_left, "the bar always sits at the mortal's right (%s, mortal at %s)" % [str(bar_box), str(feet)])
	_check(absf(bar_box.get_center().y - feet.y) <= 1.0, "the bar is centred on the mortal")
	_check(bar_box.position.x >= Arena.UI_STRIP_WIDTH and bar_box.end.x <= 1152.0 and bar_box.position.y >= 0.0 and bar_box.end.y <= 648.0,
		"the bar stays on screen and clear of the UI strip")
	var low_spot := _arena.bar.position
	_arena.player.global_position.y -= 60.0
	_arena._refresh_hud(0.0)
	_check(_arena.bar.position.y < low_spot.y, "the bar follows the mortal up the leap")
	_arena.player.global_position.y += 60.0
	_arena.player.global_position.x = 1140.0
	_arena._refresh_hud(0.0)
	_check(_arena.bar.position.x + _arena.bar.size.x <= 1152.0, "near the right edge the bar is clamped onto the screen")
	_arena._leave_vault()
	_arena._enter_run()
	# It keeps following the mortal - always on the right - at any level, from either side, and never over the bottom band.
	var band_top: float = _arena.band.get_global_rect().position.y
	var followed := true
	for level in [1, 5]:
		_arena._level = level
		_arena._show_baka_height()
		for side in [-1.0, 1.0]:
			_arena.player.global_position = Vector2(_arena.baka.global_position.x + side * _arena.vault_span * 0.5, 470.0)
			_arena.begin_vault()
			_arena._refresh_hud(0.0)
			var gauge := Rect2(_arena.bar.position, _arena.bar.size)
			var live: Vector2 = _arena.player.get_global_transform_with_canvas().origin
			if gauge.position.x < live.x or not is_equal_approx(gauge.get_center().y, live.y) or gauge.end.y > band_top:
				followed = false
				printerr("  level %d side %d: bar %s, mortal at %s, band top %.0f" % [level, int(side), str(gauge), str(live), band_top])
			_arena._leave_vault()
			_arena._enter_run()
	_check(followed, "at levels 1 and 5, from either side, the bar stays at the mortal's right and clear of the bottom band")
	_arena._level = 1
	_arena._show_baka_height()
	_arena.player.global_position = Vector2(400, 470)

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
	# Pin the box where the vault opened it: a level-1 box drifts at random and
	# could follow the falling indicator down, making the trip late or never.
	_arena._box_goal = _arena._box_center
	_arena._box_timer = 999.0
	for step in range(400):
		if _arena._vault_state != HananArena.Vault.VAULT:
			break
		_arena._tick_vault(DT)
	_check(_arena._vault_state == HananArena.Vault.STUMBLE, "drifting out past the grace time trips the mortal")
	_check(_arena.rules.local().favor <= 500 - _arena.trip_penalty() + 40, "a trip costs FAVOR (%d)" % _arena.rules.local().favor)
	_check(is_equal_approx(_arena._combo, 1.0), "a trip resets the combo")
	_arena._state_timer = 0.0
	_arena._tick_hanan(DT)
	_check(_arena._vault_state == HananArena.Vault.RUN, "after the stumble the next run starts")
	# a short wobble outside the box is forgiven
	_arena.begin_vault()
	_arena._ready_left = 0.0
	_arena._ind_pos = 1.0
	_arena._box_center = 0.3
	_arena._tick_vault(DT)
	_check(_arena._vault_state == HananArena.Vault.VAULT, "a moment outside the box inside the grace time is no trip")

	# --- the READY beat ---------------------------------------------------------------------
	_arena._leave_vault()
	_arena._enter_run()
	_arena.rules.local().favor = 500
	_arena.begin_vault()
	_arena._holding = false
	_arena._box_goal = _arena._box_center
	_arena._box_timer = 999.0
	_check(_arena.callout_label.text == "READY...", "a vault opens with READY...")
	for step in range(int((_arena.ready_time - 0.05) / DT)):
		_arena._tick_vault(DT)
	_check(_arena._vault_state == HananArena.Vault.VAULT and _arena._pending_gain == 0.0 and _arena.rules.local().favor == 500,
		"the READY beat earns nothing and never trips, even with the button let go")
	_check(_arena._ind_pos == _arena._box_center and is_equal_approx(_arena._vault_left, _arena.vault_window),
		"...the indicator is held in the box and the vault clock waits")
	_check(_arena.player.scale.y < 1.0, "...and the mortal crouches")
	for step in range(6):
		_arena._tick_vault(DT)
	_check(_arena._ready_left <= 0.0 and _arena.callout_label.text == "LEAP!" and _arena.player.scale == Vector2.ONE, "then LEAP! and the vault runs")
	_arena._refresh_hud(0.0)
	_check(_arena.rate_label.visible and _arena.rate_label.text == "+%d/s  x%.2f" % [int(round(_arena.favor_per_second * _arena._combo)), _arena._combo],
		"inside the box the rate shows beside the bar (%s)" % _arena.rate_label.text)

	# --- the leap carries the mortal over the Baka, back and forth -------------------------
	_arena._leave_vault()
	_arena._enter_run()
	var centre: float = _arena.baka.global_position.x
	var half_span: float = _arena.vault_span * 0.5
	_check(centre - _arena.vault_trigger_distance - _arena._start_position.x >= 140.0 and _arena._start_position.x - 30.0 > Arena.UI_STRIP_WIDTH,
		"the run-up from the spawn is short and clear of the UI strip (%.0fpx)" % (centre - _arena.vault_trigger_distance - _arena._start_position.x))
	_arena.player.global_position = Vector2(centre - half_span - 5.0, _arena.baka.global_position.y)
	_arena._tick_hanan(DT)
	_check(_arena._vault_state == HananArena.Vault.RUN, "just outside the trigger nothing happens")
	_arena.player.global_position.x = centre - _arena.vault_trigger_distance + 2.0
	_arena._tick_hanan(DT)
	_check(_arena._vault_state == HananArena.Vault.VAULT and is_equal_approx(_arena.player.global_position.x, centre - half_span),
		"running into the Baka from the left starts the leap on the left side")
	var mid := false
	for step in range(400):
		if _arena._vault_state != HananArena.Vault.VAULT:
			break
		_arena._holding = _arena._ind_pos < _arena._box_center
		_arena._tick_vault(DT)
		mid = mid or absf(_arena.player.global_position.x - centre) < 10.0
	_check(_arena._vault_state == HananArena.Vault.RUN and mid, "the leap passes over the Baka")
	_check(is_equal_approx(_arena.player.global_position.x, centre + half_span) and not _arena.player.locked,
		"a clean vault lands the mortal on the far side, free to move (x %.0f)" % _arena.player.global_position.x)
	_check(_arena.player.facing == -1, "...facing the Baka again")
	_check(not _arena.player.global_position.is_equal_approx(_arena._start_position), "no teleport back to the start")
	_arena._tick_hanan(DT)
	_check(_arena._vault_state == HananArena.Vault.RUN, "landing does not start the next vault by itself")
	_arena.player.global_position.x = centre + _arena.vault_trigger_distance - 2.0
	_arena._tick_hanan(DT)
	_check(_arena._vault_state == HananArena.Vault.VAULT and _arena._to_x < centre, "the trigger works from the right too, and the next vault goes back")
	for step in range(400):
		if _arena._vault_state != HananArena.Vault.VAULT:
			break
		_arena._holding = _arena._ind_pos < _arena._box_center
		_arena._tick_vault(DT)
	_check(is_equal_approx(_arena.player.global_position.x, centre - half_span), "...landing on the left side again")

	# --- a trip leaves the mortal on the approach side --------------------------------------
	_arena.player.global_position.x = centre - half_span - 20.0
	_arena.begin_vault()
	_arena._ready_left = 0.0
	_arena._holding = false
	_arena._box_goal = _arena._box_center
	_arena._box_timer = 999.0
	for step in range(400):
		if _arena._vault_state != HananArena.Vault.VAULT:
			break
		_arena._tick_vault(DT)
	_check(_arena._vault_state == HananArena.Vault.STUMBLE and is_equal_approx(_arena.player.global_position.x, centre - half_span),
		"a trip drops the mortal at the Baka's feet, on the side they came from")
	for step in range(20):
		await physics_frame
	var after_shove: float = _arena.player.global_position.x
	_check(after_shove < centre - half_span - 5.0, "...the knockback pushes them back (x %.0f)" % after_shove)
	_arena._state_timer = 0.0
	_arena._tick_hanan(DT)
	_check(_arena._vault_state == HananArena.Vault.RUN and is_equal_approx(_arena.player.global_position.x, after_shove),
		"after the stumble they stay where they landed - no teleport")

	# --- the trip penalty scales, and Hanan's mercy --------------------------------------------
	var penalties := []
	for level in range(1, 8):
		_arena._level = level
		penalties.append(_arena.trip_penalty())
	_check(penalties == [40, 60, 80, 100, 120, 120, 120], "the trip penalty is 40 + 20 a level: 40 at Low Baka, 120 at Over the Moon (%s)" % str(penalties))
	_arena._level = 3
	_arena._clean_in_level = 0
	_arena._trips_in_row = 0
	_arena.rules.local().favor = 500
	_arena.begin_vault()
	_arena._trip()
	_check(_arena.rules.local().favor == 420 and _arena._level == 3, "a trip at Standing Baka costs 80; one trip keeps the level")
	_arena.begin_vault()
	_arena._clean_vault()
	_arena.begin_vault()
	_arena._trip()
	_check(_arena._level == 3, "a clean vault in between resets the count")
	_arena.begin_vault()
	_arena._trip()
	_check(_arena._level == 2 and _arena.callout_label.text.contains("THE BAKA CROUCHES"), "two trips in a row drop the level by one: THE BAKA CROUCHES")
	_arena._level = 1
	_arena._trips_in_row = 0
	for trip in range(3):
		_arena.begin_vault()
		_arena._trip()
	_check(_arena._level == 1, "...never below Low Baka")

	# --- the first-visit practice vault --------------------------------------------------------
	_arena._enter_run()
	_arena._level = 1
	_arena._trips_in_row = 0
	_arena.arena_round_reset()
	_arena._phase = Arena.Phase.PLAYING
	_arena.player.set_lock(false)
	_check(_arena._practice == _arena.first_visit, "a first visit opens with a practice vault")
	_arena._practice = true
	var normal_box: float = _arena.current_box_size()
	_arena.rules.local().favor = 500
	_arena.begin_vault()
	_check(is_equal_approx(_arena.current_box_size(), normal_box * _arena.practice_box_scale), "the practice box is 1.5x its size")
	_arena._refresh_hud(0.0)
	_check(_arena.hold_prompt.visible, "\"HOLD LEFT CLICK\" waits beside the bar")
	var hold := InputEventMouseButton.new()
	hold.button_index = MOUSE_BUTTON_LEFT
	hold.pressed = true
	_arena._input(hold)
	_arena._refresh_hud(0.0)
	_check(not _arena.hold_prompt.visible, "...until the button is first held")
	_arena._trip()
	_check(_arena.rules.local().favor == 500 and _arena._trips_in_row == 0, "a practice trip costs nothing and does not count for mercy")
	_arena.begin_vault()
	_check(not _arena._practice_vault and is_equal_approx(_arena.current_box_size(), normal_box), "only the first vault is practice")
	_arena._leave_vault()
	_arena._practice = true
	_arena.begin_vault()
	_arena._pending_gain = 20.0
	_arena._clean_vault()
	_check(_arena.rules.local().favor == 520, "a practice vault still pays FAVOR")

	# --- Over the Moon shakes the field and the bar, never the labels ---------------------------
	_arena._enter_run()
	_arena._level = 5
	_arena.begin_vault()
	var shook := false
	var still := true
	for frame in range(10):
		_arena._refresh_hud(0.0)
		still = still and _arena.popup_layer.offset == Vector2.ZERO and _arena.band.get_canvas_layer_node().offset == Vector2.ZERO
		shook = shook or _arena.bar_layer.offset != Vector2.ZERO or _arena.field_root.position != Vector2.ZERO
	_check(still, "the HUD layer (status, callout, hint) never shakes")
	_check(shook == _arena.screen_shake_allowed(), "level 5 shakes the field and the bar (when shaking is on)")
	_arena._leave_vault()
	_arena._enter_run()
	_arena._refresh_hud(0.0)
	_arena._level = 1

	# --- the God's Due menu pauses a vault --------------------------------------------------
	_arena._leave_vault()
	_arena._enter_run()
	_arena._level = 3  # a box that moves on its own
	_arena.rules.local().favor = 500
	_arena.begin_vault()
	_arena._ready_left = 0.0
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

	# --- Hanan is the Baka: her scene shows the level --------------------------------------
	var baka: HananBaka = _arena.baka
	_check(baka != null and baka.scene_file_path == "res://scenes/gods/hanan/HananBaka.tscn" and baka.name == "Baka",
		"ArenaField/Baka is the HananBaka scene")
	var clips := baka.art.sprite_frames.get_animation_names()
	clips.sort()
	_check(clips == PackedStringArray(["low", "sitting", "standing"]), "...one SpriteFrames with low / sitting / standing (%s)" % str(clips))
	_check(_arena.overseer.visible == ResourceLoader.exists("res://Assets/Gods/Hanan/Hanan-Overseer.png"),
		"the overseer shows only when Hanan-Overseer.png exists")
	_check(_arena.get_node_or_null("ArenaField/Baka/Name") != null, "the Baka keeps its Name label")
	var shown: Array[StringName] = []
	var tall: Array[float] = []
	for level in range(1, 6):
		_arena._level = level
		_arena._show_baka_height()
		shown.append(baka.clip())
		var frame := baka.art.sprite_frames.get_frame_texture(baka.art.animation, 0)
		var tallest_figure := 0.0
		for index in range(baka.art.sprite_frames.get_frame_count(baka.art.animation)):
			tallest_figure = maxf(tallest_figure, _figure_height(baka.art.sprite_frames.get_frame_texture(baka.art.animation, index)))
		tall.append(tallest_figure * baka.art.scale.y)
		_check(is_equal_approx(baka.art.position.y + frame.get_height() * 0.5 * baka.art.scale.y, 0.0),
			"level %d: she stands on the Baka's origin" % level)
	_check(shown == [&"low", &"sitting", &"standing", &"standing", &"standing"],
		"levels 1, 2, 3+ play low, sitting, standing (%s)" % str(shown))
	_check(tall[0] < tall[1] and tall[1] < tall[2] and tall[2] < tall[3] and tall[3] < tall[4],
		"...each level stands taller than the last (%s)" % str(tall))
	var size_before := _arena.current_box_size()
	_arena._level = 1
	_arena._show_baka_height()
	_check(is_equal_approx(_arena.current_box_size(), _arena.box_sizes[0]) and size_before == _arena.box_sizes[4],
		"the vault reads the level's numbers, never the art")
	var authored: AnimatedSprite2D = (load("res://scenes/gods/hanan/HananBaka.tscn") as PackedScene).instantiate().get_node("Art")
	_check(baka.art.scale == authored.scale, "she is drawn at the size authored on Art, never scaled down (%s)" % str(baka.art.scale))
	authored.get_parent().free()
	baka.bump()
	await process_frame  # a tween takes its first step on the frame after it starts
	await process_frame
	_check(baka._bump.is_running() and absf(baka.rotation) > 0.0, "a trip bumps her (%.3f rad)" % baka.rotation)
	await baka._bump.finished
	_check(is_zero_approx(baka.rotation), "...and she settles back (%.3f rad)" % baka.rotation)
	_arena._apply_art()

	# --- the blitz: the last 30 s ---------------------------------------------------------
	_arena._leave_vault()
	_arena._enter_run()
	_arena._level = 1
	_arena._practice = false
	_arena._combo = 1.0
	_arena._trial_time = 31.0
	_arena._update_blitz(DT)
	_check(not _arena._blitz and not _arena.blitz_glow.visible, "with 31 s left there is no blitz yet")
	_arena.begin_vault()
	_check(not _arena._blitz_vault and is_equal_approx(_arena._vault_total, 3.0) and is_equal_approx(_arena._vault_left, 3.0), "a normal vault runs vault_window (3 s)")
	_arena._ready_left = 0.0
	_arena._trial_time = 30.0
	_arena._update_blitz(DT)
	_check(_arena._blitz and _arena.blitz_glow.visible, "at 30 s left the blitz is on, and the field pulses")
	_arena._ind_pos = 0.5
	_arena._ind_vel = 0.0
	_arena._holding = true
	for step in range(10):
		_arena._step_indicator(DT)
	_check(_arena._ind_pos > 0.5 and not _arena._blitz_vault, "a vault already running at 30 s is not inverted: holding still raises it (%.2f)" % _arena._ind_pos)
	_arena._holding = false
	_arena._leave_vault()
	_arena._enter_run()
	_arena.begin_vault()
	_check(_arena._blitz_vault and is_equal_approx(_arena._vault_total, 5.0) and is_equal_approx(_arena._vault_left, 5.0),
		"the next vault is a blitz vault with 5 s on the bar (%.1f)" % _arena._vault_left)
	_check(_arena.callout_label.visible and _arena.callout_label.text.contains("INVERTED!"), "...opening with an INVERTED! callout (%s)" % _arena.callout_label.text.replace("
", " "))
	_arena._ready_left = 0.0
	_arena._ind_pos = 0.5
	_arena._ind_vel = 0.0
	_arena._holding = true
	for step in range(15):
		_arena._step_indicator(DT)
	_check(_arena._ind_pos < 0.5 and _arena._ind_vel < 0.0, "inverted: holding lowers the indicator (%.2f)" % _arena._ind_pos)
	_arena._refresh_hud(0.0)
	_check(_arena.sink_arrow.visible, "...with an arrow on the bar pointing down while held")
	_check(_arena.status_label.text.begins_with("INVERTED: HOLD TO SINK") and _arena.hint_label.text.contains("HOLD TO SINK, LET GO TO RISE"),
		"...the band says INVERTED: HOLD TO SINK and the hint says how (%s | %s)" % [_arena.status_label.text.left(24), _arena.hint_label.text.left(40)])
	_arena._holding = false
	_arena._ind_pos = 0.5
	_arena._ind_vel = 0.0
	for step in range(15):
		_arena._step_indicator(DT)
	_check(_arena._ind_pos > 0.5, "...and letting go raises it (%.2f)" % _arena._ind_pos)
	# the blitz bar is gentler: its own rise, capped at blitz_max_speed; normal vaults keep theirs
	_arena._ind_pos = 0.0
	_arena._ind_vel = 0.0
	_arena._step_indicator(DT)
	_check(is_equal_approx(_arena._ind_vel, _arena.blitz_rise_accel * DT) and _arena.blitz_rise_accel < _arena.lift_accel,
		"a blitz vault rises at blitz_rise_accel (%.2f), slower than lift_accel" % _arena.blitz_rise_accel)
	var fastest := 0.0
	for step in range(120):
		_arena._step_indicator(DT)
		fastest = maxf(fastest, absf(_arena._ind_vel))
	_check(fastest <= _arena.blitz_max_speed + 0.0001 and _arena.blitz_max_speed < _arena.max_speed,
		"...and is capped at blitz_max_speed (%.2f)" % fastest)
	_arena._ind_pos = 0.5
	_arena._ind_vel = 0.0
	for step in range(30):  # 0.5 s let go, from rest
		_arena._step_indicator(DT)
	_check(_arena._ind_pos - 0.5 < (_arena.box_sizes[0] + _arena.indicator_size) * 0.5,
		"...so half a second let go stays inside a level-1 box (%.3f)" % (_arena._ind_pos - 0.5))
	_arena._blitz_vault = false
	_arena._ind_pos = 0.0
	_arena._ind_vel = 0.0
	_arena._holding = true
	_arena._step_indicator(DT)
	_check(is_equal_approx(_arena._ind_vel, _arena.lift_accel * DT), "a normal vault still lifts at lift_accel")
	fastest = 0.0
	for step in range(50):
		_arena._step_indicator(DT)
		fastest = maxf(fastest, absf(_arena._ind_vel))
	_check(is_equal_approx(fastest, _arena.max_speed), "...up to max_speed (%.2f)" % fastest)
	_arena._holding = false
	_arena._blitz_vault = true
	_arena._refresh_hud(0.0)
	_check(not _arena.sink_arrow.visible, "the arrow hides when the button is let go")
	_check(is_equal_approx(_arena.earn_rate(), 48.0), "FAVOR in the box pays x1.2 in the blitz (%.1f/s)" % _arena.earn_rate())
	_arena._pending_gain = 0.0
	_arena._ind_pos = _arena._box_center
	_arena._ind_vel = 0.0
	_arena._tick_vault(0.1)
	_check(is_equal_approx(_arena._pending_gain, 4.8), "...banked in the pending gain (%.2f for 0.1 s)" % _arena._pending_gain)
	_check(_arena.trip_penalty() == 40, "trip penalties are unchanged")
	_arena._leave_vault()
	_arena._enter_run()
	_arena._trial_time = 999.0
	_arena._update_blitz(DT)
	_check(not _arena._blitz and not _arena.blitz_glow.visible and is_equal_approx(_arena.earn_rate(), 40.0), "(back to a normal trial for the rest)")

	# --- standing about costs FAVOR ---------------------------------------------------------
	_arena._enter_run()
	_arena.player.set_lock(false)
	_arena.player.global_position = _arena.baka.global_position + Vector2(400.0, 0.0)  # clear of the trigger
	_arena.rules.local().favor = 500
	_arena._tick_hanan(4.9)
	_check(_arena.rules.local().favor == 500, "4.9 s idle costs nothing")
	_arena._tick_hanan(0.2)
	_check(_arena.rules.local().favor == 300, "5 s idle in RUN costs idle_penalty (%d)" % _arena.rules.local().favor)
	_arena._tick_hanan(5.0)
	_check(_arena.rules.local().favor == 100, "...and 10 s costs 400 in all (%d)" % _arena.rules.local().favor)
	_arena._tick_hanan(5.0)
	_check(_arena.rules.local().favor == 0, "FAVOR never goes below 0 (%d)" % _arena.rules.local().favor)
	_arena._tick_hanan(5.0)
	_check(_arena.rules.local().favor == 0, "nothing is taken at 0 FAVOR")
	_arena.rules.local().favor = 500
	_arena._enter_run()
	_arena._tick_hanan(4.9)
	_arena.begin_vault()
	_arena._tick_idle(10.0)
	_check(_arena.rules.local().favor == 500 and is_equal_approx(_arena._idle_left, _arena.idle_time),
		"a vault started at 4.9 s costs nothing, and the clock pauses during it")
	_arena._vault_state = HananArena.Vault.STUMBLE
	_arena._tick_idle(10.0)
	_check(_arena.rules.local().favor == 500, "the clock is paused during a stumble")
	_arena._enter_run()
	_check(is_equal_approx(_arena._idle_left, _arena.idle_time), "back in RUN it restarts at a full idle_time")
	_arena.player.set_lock(true)
	_arena._tick_idle(10.0)
	_check(_arena.rules.local().favor == 500, "nothing is taken while the mortal is locked")
	_arena.player.set_lock(false)
	_arena._tick_idle(3.5)
	_check(_arena.callout_label.visible and _arena.callout_label.text.begins_with("LEAP!"), "the last 2 s warn LEAP!")
	_check(_arena.arena_local_effects().size() == 1, "...and the effect timers count the IDLE down")
	_arena._enter_run()

	# --- GISING NA!: the alarm clock ----------------------------------------------------------
	# Two alarms a round: one starts with more than 30 s + the clock left (so it always
	# rings before the Blitz), one starts in the last 15-30 s. Standing on Hanan's
	# marked side when the clock hits 0 costs 300 FAVOR.
	_arena._alarm_active = false
	_arena._alarm_left = 0.0
	_arena._alarm_shake_left = 0.0
	_arena._trial_time = 999.0
	_arena._roll_alarms()
	_check(_arena._alarm_starts.size() == 2, "a round sets two alarms")
	var first_start: float = _arena._alarm_starts[0]
	var second_start: float = _arena._alarm_starts[1]
	_check(first_start > _arena.baka_blitz_time + _arena.alarm_time,
		"the first alarm starts so it rings with more than 30 s left (%.1f s)" % first_start)
	_check(second_start >= 15.0 and second_start <= 30.0,
		"the second alarm starts in the last 15-30 s (%.1f s)" % second_start)
	_arena.player.global_position = _arena.baka.global_position + Vector2(300.0, 0.0)
	_arena._trial_time = first_start + 1.0
	_arena._tick_alarm(DT)
	_check(not _arena._alarm_active, "the first alarm waits for its moment")
	_arena._trial_time = first_start - 0.1
	_arena._tick_alarm(DT)
	_check(_arena._alarm_active and _arena._alarm_left <= _arena.alarm_time,
		"then a 10 s clock starts ticking")
	_check(_arena._alarm_starts.size() == 1, "...once, with the second still to come")
	_arena._refresh_alarm()
	_check(_arena.alarm_root.visible and _arena.alarm_count.text == "10",
		"the clock shows 10 and marks the field")
	var split: float = _arena.baka.global_position.x
	var clock_x: float = _arena.alarm_clock.global_position.x
	_check((_arena._alarm_side < 0 and clock_x < split) or (_arena._alarm_side > 0 and clock_x > split),
		"the clock stands on the side it marks")
	_check(_arena._field.has_point(_arena.alarm_clock.global_position), "...and on the floor of that side")
	_check(_arena.alarm_root.get_node_or_null("Half") == null,
		"the marked side is no box over the floor")
	_arena.player.global_position = _arena.baka.global_position + Vector2(_arena._alarm_side * 200.0, 0.0)
	_arena._refresh_alarm(DT)
	_check(_arena.player.modulate.r > _arena.player.modulate.g and _arena.player.modulate.g < 1.0,
		"a mortal standing on the marked side flickers red")
	_arena.player.global_position = _arena.baka.global_position - Vector2(_arena._alarm_side * 200.0, 0.0)
	_arena._refresh_alarm(DT)
	_check(_arena.player.modulate == Color.WHITE, "...and the other side leaves the mortal alone")
	_arena._refresh_hud(DT)
	_check(_arena.status_label.text.begins_with("GISING NA!"), "the bottom band counts the alarm down")
	_check(_arena.hint_label.text.begins_with("GISING NA!"), "...and the hint strip says to get off that side")
	_check(_arena.arena_local_effects().size() == 1, "...and the effect timers count it down")
	# Standing on the marked side when it rings.
	_arena.rules.local().favor = 500
	_arena.player.global_position = _arena.baka.global_position + Vector2(_arena._alarm_side * 200.0, 0.0)
	_arena._alarm_left = 0.05
	_arena._tick_alarm(0.1)
	_arena._refresh_alarm()
	_check(not _arena._alarm_active, "the clock rings at 0")
	_check(_arena.rules.local().favor == 500 - _arena.alarm_penalty,
		"standing on the marked side costs 300 FAVOR (%d left)" % _arena.rules.local().favor)
	_check(_arena.callout_label.text.begins_with("GISING NA!"), '...and says "GISING NA!"')
	_check(_arena._alarm_shake_left > 0.0 and not _arena.alarm_root.visible, "the ring shakes the field and the marking goes")
	_check(_arena.player.modulate == Color.WHITE, "...and the red flick stops with the clock")
	# The other side is safe.
	_arena._alarm_starts.clear()
	_arena._alarm_starts.append(_arena._trial_time)
	_arena._tick_alarm(DT)
	_arena.player.global_position = _arena.baka.global_position - Vector2(_arena._alarm_side * 200.0, 0.0)
	_arena.rules.local().favor = 500
	_arena._alarm_left = 0.05
	_arena._tick_alarm(0.1)
	_check(_arena.rules.local().favor == 500 and _arena.callout_label.text.begins_with("SAFE!"),
		"the side it did not mark is safe when it rings")
	# The penalty never takes FAVOR the mortal does not have.
	_arena._alarm_starts.clear()
	_arena._alarm_starts.append(_arena._trial_time)
	_arena._tick_alarm(DT)
	_arena.player.global_position = _arena.baka.global_position + Vector2(_arena._alarm_side * 200.0, 0.0)
	_arena.rules.local().favor = 100
	_arena._alarm_left = 0.05
	_arena._tick_alarm(0.1)
	_check(_arena.rules.local().favor == 0, "the alarm never takes FAVOR below 0 (%d)" % _arena.rules.local().favor)
	_arena._trial_time = 999.0
	_arena._alarm_starts.clear()
	_arena._alarm_shake_left = 0.0
	_arena._refresh_hud(DT)

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


# The pixels the figure fills in a frame, top to bottom (frames carry padding).
func _figure_height(texture: Texture2D) -> float:
	var image := texture.get_image()
	var top := image.get_height()
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.05:
				top = mini(top, y)
				bottom = maxi(bottom, y)
	return float(bottom - top + 1) if bottom >= 0 else 0.0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
