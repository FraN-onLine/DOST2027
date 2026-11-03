extends SceneTree

# Validation: THE PLAYGROUND, through the real Playground scene, solo.
#   * it opens on the camp (the preparation area's art) with no dialogue, no
#     countdown, no rest clock and no Tindahan - it never closes by itself
#   * there is an altar of every god, each painted with that god's name and icon
#   * F at an altar opens that god's favors FREE (no FAVOR, no voucher, no limit)
#     and taking one bestows it; away from every altar F opens nothing
#   * a DUMMY rival stands on the field where the rules and every skill look for
#     a rival, and no rival FAVOR ticker runs
#   * the favors reach the dummy exactly as in a trial: a 3 - 2 - 1 drowsiness
#     then the stars, a root leash that lets it move and ends after 3s (ours is
#     dragged back), 7 sun patches from Apolaki's E, and Bathala's Blindside
#   * It's Kinda Tabu's per-second clock runs here, and The West Wind blows at
#     1.5x the blitz's force - shoving the dummy, never its own (immune) holder
#   * Esc / LEAVE is wired to walk out (checked through its signal), and the
#     MainMenu has a PLAYGROUND button that leads here
# Run: godot --headless --path <project> -s res://tools/playground_check.gd

const DT := 0.125
const DUMMY_ID := 2

var _problems := 0
var _checks := 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)
	var playground: PrepArea = load("res://scenes/prep/Playground.tscn").instantiate()
	view.add_child(playground)
	await _frames(4)
	if playground == null or not playground.is_inside_tree():
		_check(false, "the Playground scene loads")
		return _finish()
	_check(true, "the Playground scene loads")

	# Manual ticks keep the checks deterministic: the scene itself and the rules
	# stop running on their own frames.
	playground.set_process(false)
	playground.rules.set_process(false)
	playground.player.set_physics_process(false)
	var dummy: ArenaMortal = playground.mortal_node(DUMMY_ID)
	if dummy != null:
		dummy.set_physics_process(false)

	# --- WHAT IT OPENS AS ---------------------------------------------------------------
	_check(playground is PrepArea, "the Playground is built on the preparation area's camp")
	_check(playground._phase == Arena.Phase.PLAYING, "it opens in a playing phase (favors live)")
	_check(not playground.rules.trial_active, "no trial is running")
	_check(not playground.rules.simulate_rivals, "no rival FAVOR ticker")
	_check(is_inf(playground.rules.time_left), "no trial clock")
	_check(not playground.player.locked, "the mortal may walk at once")
	_check(playground.get_node_or_null("Camp/Campfire") != null and playground.get_node_or_null("Lobbymap") != null,
		"the Pahinga camp and its fire are there")
	_check(not playground.is_closed(), "nothing closes it")

	# --- THE HUD ------------------------------------------------------------------------
	_check(not (playground.hud.get_node("TrialPanel") as Control).visible, "no trial clock panel")
	_check(playground.hud.god_label.text == "PLAYGROUND", "the HUD names the Playground (%s)" % playground.hud.god_label.text)
	_check(playground.next_label.visible and playground.next_label.text == "PLAYGROUND - STAND BY AN ALTAR",
		"the top banner says what to do (%s)" % playground.next_label.text)
	_check(not playground.ready_label.visible, "no READY handshake here")
	_check(not playground.stall.visible and not playground.shop.is_open(), "no Tindahan in the Playground")
	_check(playground.hint_label.text.contains("LEAVE"), "the hint band says how to leave (%s)" % playground.hint_label.text)
	_check(playground.leave_button != null and playground.leave_button.text == "LEAVE", "there is a LEAVE button")

	# --- THE CAMPFIRE'S SIGN ------------------------------------------------------------
	var fire: Node2D = playground.get_node("Camp/Campfire") as Node2D
	var play_hint := fire.get_node_or_null("PlayHint") as Label
	_check(play_hint != null and play_hint.visible, "a message under the campfire says how to play")
	_check(play_hint != null and play_hint.text.to_upper().contains("CLICK")
		and play_hint.text.to_upper().contains("PLAY"),
		"...telling the mortal to click it to play (%s)" % (play_hint.text if play_hint != null else "none"))
	_check(play_hint != null and play_hint.global_position.y > fire.global_position.y + 20.0,
		"...and it sits below the fire (%s)" % (str(play_hint.global_position) if play_hint != null else "none"))

	# --- AN ALTAR OF EVERY GOD ----------------------------------------------------------
	var gods := Gods.all()
	_check(gods.size() == 8, "eight gods in the registry (%d)" % gods.size())
	_check(playground._altars.size() == gods.size(), "one altar per god (%d)" % playground._altars.size())
	var seen_gods := {}
	var seen_positions := {}
	var painted := true
	var lit := true
	var inside := true
	var spawn_clear := true
	var above := 0
	var beside := 0
	var below := 0
	var left_beside := 0
	var right_beside := 0
	for altar in playground._altars.keys():
		var altar_god: God = playground._altars[altar]
		var at := (altar as Node2D).global_position
		seen_gods[altar_god.id] = true
		seen_positions[str((altar as Node2D).position)] = true
		var name_label := (altar as Node2D).get_node("Name") as Label
		var icon := (altar as Node2D).get_node("GodIcon") as Sprite2D
		painted = painted and name_label.text == "ALTAR OF %s" % altar_god.display_name
		painted = painted and altar_god.icon != null and icon.texture == altar_god.icon
		lit = lit and (altar as Node2D).visible
		inside = inside and playground._field.has_point(at)
		spawn_clear = spawn_clear and playground._start_position.distance_to(at) > 120.0
		if at.y < fire.global_position.y - 24.0:
			above += 1
		elif at.y > fire.global_position.y + 24.0:
			below += 1
		else:
			beside += 1
			if at.x < fire.global_position.x:
				left_beside += 1
			else:
				right_beside += 1
	_check(seen_gods.size() == gods.size(), "every god has an altar (%s)" % str(seen_gods.keys()))
	_check(seen_positions.size() == gods.size(), "the altars stand apart around the fire")
	_check(inside, "every altar stands inside the field")
	_check(spawn_clear, "the mortal spawns clear of every altar")
	_check(painted, "each altar is painted with its god's name and icon")
	_check(lit, "...and every altar is visible")
	_check(above == 3 and beside == 2 and below == 3,
		"the altars ring the fire 3 above, 2 beside, 3 below (%d/%d/%d)" % [above, beside, below])
	_check(left_beside == 1 and right_beside == 1, "one altar stands on each side of the fire")

	# --- THE DUMMY ----------------------------------------------------------------------
	var dummy_mortal: GodMatch.Mortal = playground.rules.mortal(DUMMY_ID)
	_check(dummy_mortal != null and dummy != null, "the dummy exists in the rules and on the field")
	_check(dummy != null and dummy.locked, "the dummy stands still (a ghost, not a player)")
	_check(dummy != null and dummy.name_tag.text == "DUMMY", "its name tag reads DUMMY (%s)" % (dummy.name_tag.text if dummy != null else "none"))
	_check(dummy_mortal != null and dummy_mortal.favor == 1000, "the dummy can be aimed at (%d FAVOR)" % (dummy_mortal.favor if dummy_mortal != null else -1))
	_check(playground._mortal_positions.has(DUMMY_ID), "the rules know where the dummy stands")
	var authored_dummy := playground.get_node_or_null("Ghosts/Dummy") as ArenaMortal
	_check(authored_dummy != null and authored_dummy == dummy,
		"the dummy is authored under Ghosts and used as the rival's body")
	var dummy_start: Vector2 = dummy.global_position if dummy != null else Vector2.ZERO
	# The dummy is a target, not decoration: it is authored off to the left, clear
	# of the altars and the fire.
	var dummy_clear := true
	for altar in playground._altars.keys():
		dummy_clear = dummy_clear and dummy_start.distance_to((altar as Node2D).global_position) > 120.0
	dummy_clear = dummy_clear and dummy_start.distance_to(fire.global_position) > 100.0
	_check(dummy_clear, "it stands in the left area, clear of the altars and the fire (%s)" % str(dummy_start))
	_check(dummy_start.x < fire.global_position.x - 200.0,
		"the dummy is off to the fire's left (%s)" % str(dummy_start))

	# The dummy is pushable: leaning into it shoves it along the field.
	playground.player.global_position = dummy_start - Vector2(40.0, 0.0)
	playground._process(DT)
	_check(dummy.global_position.x > dummy_start.x + 1.0,
		"walking into the dummy pushes it along (%.1f -> %.1f)" % [dummy_start.x, dummy.global_position.x])
	_check(playground._mortal_positions[DUMMY_ID].distance_to(dummy.global_position) < 0.01,
		"...and the rules follow where it was pushed, so it stays there")
	playground.player.global_position = playground._start_position
	dummy.global_position = dummy_start
	playground._mortal_positions[DUMMY_ID] = dummy_start

	# No trial runs here, but the weeds' clock does: it used to freeze with
	# trial_active false (and so in the Playground, forever).
	playground.rules.cast_ligaw_na_damo(playground._my_id, Gods.favor_by_id(&"ligaw_na_damo"))
	var weeds_before := dummy_mortal.weeds_time
	_tick(playground, 1.0)
	_check(weeds_before > 0.0 and is_equal_approx(dummy_mortal.weeds_time, weeds_before - 1.0),
		"the weeds' clock runs with no trial (%.2fs left)" % dummy_mortal.weeds_time)
	_check(dummy.status_tag.visible and dummy.status_tag.text == "WEEDED",
		"...and the dummy says WEEDED while they last")
	dummy_mortal.weeds_time = 0.0
	playground._process(DT)
	_check(not dummy.status_tag.visible, "...and both go when the clock runs out")

	# Nothing in the rest moves FAVOR: no rival drip, no regrowth, no clock.
	var before := {}
	for mortal in playground.rules.mortals.values():
		before[mortal.id] = mortal.favor
	_tick(playground, 4.0)
	var still := true
	for mortal in playground.rules.mortals.values():
		still = still and mortal.favor == int(before[mortal.id])
	_check(still, "four seconds of playground move no FAVOR")
	_check(not playground.is_closed(), "...and do not close it")

	# --- THE ALTARS: EVERY GOD'S FAVORS, FREE --------------------------------------------
	var bathala_altar: Node2D = null
	var apolaki_altar: Node2D = null
	for altar in playground._altars.keys():
		match (playground._altars[altar] as God).id:
			&"bathala":
				bathala_altar = altar
			&"apolaki":
				apolaki_altar = altar
	_check(bathala_altar != null and apolaki_altar != null, "Bathala's and Apolaki's altars exist")
	playground.player.global_position = bathala_altar.global_position
	playground._process(DT)
	_check(playground._nearest_altar() == bathala_altar, "standing by Bathala's altar finds it")
	_check(playground.next_label.text == "ALTAR OF BATHALA - %s BLESSING" % playground.key_cap(&"due_menu"),
		"the top banner names the altar (%s)" % playground.next_label.text)

	playground._toggle_due_menu()
	await _frames(2)
	var menu = playground.due_menu
	_check(menu.is_open(), "F at the altar opens its God's Due menu")
	_check(menu._free_boons and menu.selling(), "...as free blessings (no purchase, no voucher)")
	_check(menu.due_label.text == "FREE BLESSINGS OF BATHALA", "the menu says they are free (%s)" % menu.due_label.text)
	_check(menu._shown.size() == 3, "up to three favors are shown (%d)" % menu._shown.size())
	_check(_price(menu, 0) == "FREE", "a card's price reads FREE (%s)" % _price(menu, 0))

	# Pick a skill card (no instant side effect), re-opening until one is shown.
	var pick := -1
	var picked: GodFavor = null
	for attempt in range(60):
		for index in range(menu._shown.size()):
			if (menu._shown[index] as GodFavor).is_skill():
				pick = index
				break
		if pick >= 0:
			picked = menu._shown[pick]
			break
		menu.close()
		playground._toggle_due_menu()
		await _frames(1)
	_check(picked != null, "one of Bathala's skills can be offered")
	if picked != null:
		var me: GodMatch.Mortal = playground.rules.local()
		var paid := me.favor
		menu._choose(pick)
		_check(me.has_favor(picked.id), "choosing a card bestows %s" % picked.display_name)
		_check(me.favor == paid, "...and costs no FAVOR at the Playground's altar (%d)" % me.favor)
		_check(not menu.is_open(), "...and closes the menu")
	if menu.is_open():
		menu.close()

	# Away from every altar and the fire F does nothing.
	playground.player.global_position = playground._start_position
	playground._process(DT)
	_check(playground._nearest_altar() == null, "the fire is out of reach of every altar")
	_check(not playground._near_fire(), "...and the fire is out of reach too")
	_check(playground.next_label.text == "PLAYGROUND - STAND BY AN ALTAR", "...and the banner says so (%s)" % playground.next_label.text)
	var f_key := InputEventAction.new()
	f_key.action = &"due_menu"
	f_key.pressed = true
	playground._unhandled_input(f_key)
	await _frames(1)
	_check(not menu.is_open(), "away from every altar F opens nothing")

	# F at an altar goes through the real input path.
	playground.player.global_position = apolaki_altar.global_position
	playground._unhandled_input(f_key)
	await _frames(2)
	_check(menu.is_open() and menu._free_boons, "F at Apolaki's altar opens his free blessings")
	menu.close()

	# --- THE CAMPFIRE: EVERY GAME, TESTABLE SOLO -----------------------------------------
	_check(playground.game_menu != null, "the Playground carries the game list")
	_check(not playground.game_menu.is_open(), "the game list starts closed")
	playground.player.global_position = fire.global_position
	playground._process(DT)
	_check(playground._near_fire(), "standing at the campfire finds it")
	_check(playground.next_label.text == "CAMPFIRE - %s TEST A GAME" % playground.key_cap(&"attack"),
		"the banner names the campfire (%s)" % playground.next_label.text)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(576, 340)
	playground._input(click)
	await _frames(2)
	var game_menu = playground.game_menu
	_check(game_menu.is_open(), "a left click at the fire opens the game list")
	_check(playground.player.locked, "...and holds the mortal still while it is open")

	var game_rows: Array[Control] = []
	for row in game_menu.rows.get_children():
		game_rows.append(row as Control)
	_check(game_rows.size() == 8, "one game per god (%d)" % game_rows.size())
	_check(game_rows.size() == Gods.all().size(), "...every god of the registry")
	var named_games := true
	var instructions := true
	var test_buttons := true
	for index in range(game_rows.size()):
		var row: Control = game_rows[index]
		var row_god: God = Gods.by_id(StringName(str(row.name).trim_prefix("Game_")))
		var title := row.get_node("Margin/Body/Text/Title") as Label
		var rules := row.get_node("Margin/Body/Text/Rules") as Label
		var test := row.get_node("Margin/Body/Test") as Button
		named_games = named_games and row_god != null \
			and title.text == "%s  -  %s" % [row_god.display_name.to_upper(), row_god.game_name.to_upper()]
		instructions = instructions and rules.text == row_god.game_blurb and rules.text != ""
		test_buttons = test_buttons and test.text == "TEST" and not test.disabled
	_check(named_games, "every row names its god and game")
	_check(instructions, "...and carries that game's instructions")
	_check(test_buttons, "...with a TEST button on each")
	_check(game_rows[game_rows.size() - 1].name == "Game_bathala", "Bathala's Agawan Base sits last")
	var sidapa_row: Control = null
	for row in game_rows:
		if row.name == "Game_sidapa":
			sidapa_row = row
	_check(sidapa_row != null, "Sidapa's Piko has a row")
	_check(sidapa_row != null and sidapa_row.get_node_or_null("Margin/Body/Text/DeathNote") != null
		and (sidapa_row.get_node("Margin/Body/Text/DeathNote") as Label).text == "Also the God of Death.",
		"...and says he is also the God of Death")
	var wired := false
	for connection in game_menu.test_requested.get_connections():
		if (connection["callable"] as Callable).get_method() == "_launch_test":
			wired = true
	_check(wired, "the TEST buttons hand the god to the Playground")

	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	playground._unhandled_input(esc)
	await _frames(1)
	_check(not game_menu.is_open(), "Esc closes the game list")
	_check(not playground.player.locked, "...and frees the mortal")

	# Away from the fire a left click opens nothing.
	playground.player.global_position = playground._start_position
	playground._process(DT)
	playground._input(click)
	await _frames(1)
	_check(not game_menu.is_open(), "a left click away from the fire opens nothing")

	# The 3-below row crowds the fire's foot, but altars only listen to F: a click
	# still opens the list from an altar's reach.
	playground.player.global_position = Vector2(700, 450)
	playground._process(DT)
	_check(playground._nearest_altar() != null and playground._near_fire(),
		"the fire can be reached from the edge of an altar")
	playground._input(click)
	await _frames(1)
	_check(game_menu.is_open(), "a click at the fire opens the list even beside an altar")
	playground._unhandled_input(esc)
	await _frames(1)
	_check(not game_menu.is_open() and not playground.player.locked, "Esc closes it again")

	# --- HANAN: REST AND REFRESHED, 3 - 2 - 1, THEN THE STARS ---------------------------
	playground.player.global_position = playground._start_position
	var me := playground.rules.local()
	var rest := Gods.favor_by_id(&"rest_and_refreshed")
	_check(playground.rules.bestow_favor(rest), "Rest and Refreshed can be taken")
	_check(me.favor_in_slot(GodFavor.Slot.E) == rest, "...and sits in E")
	playground._use_skill(GodFavor.Slot.E)
	_check(playground.rules.mortal(DUMMY_ID).drowsy_time > 0.0, "the dummy grows drowsy")
	_tick(playground, 0.2)
	_check(dummy.drowsy_count.visible and dummy.drowsy_count.text == "3",
		"the 3 over its head starts the countdown (%s)" % dummy.drowsy_count.text)
	_tick(playground, 1.0)
	_check(dummy.drowsy_count.visible and dummy.drowsy_count.text == "2", "then 2 (%s)" % dummy.drowsy_count.text)
	_tick(playground, 1.0)
	_check(dummy.drowsy_count.visible and dummy.drowsy_count.text == "1", "then 1 (%s)" % dummy.drowsy_count.text)
	_tick(playground, 1.0)
	var stunned: GodMatch.Mortal = playground.rules.mortal(DUMMY_ID)
	_check(not dummy.drowsy_count.visible, "the count clears when the drowsiness ends")
	_check(stunned.stun_time > 0.0, "...and the dummy is stunned (%.2fs)" % stunned.stun_time)
	_check(dummy._stun_fx > 0.0, "...with the usual stars over its head")
	_tick(playground, 1.0)

	# --- MAPULON: A ROOT THAT DOES NOT HOLD ---------------------------------------------
	var homeland := Gods.favor_by_id(&"down_to_homeland")
	_check(playground.rules.bestow_favor(homeland), "Down to Homeland can be taken")
	playground._use_skill(GodFavor.Slot.E)
	_check(playground.rules.mortal(DUMMY_ID).rooted_time > 0.0, "the dummy is rooted")
	playground._process(DT)
	_check(playground._root_leashes.has(DUMMY_ID), "its root is drawn as a leash on this screen")
	var shadow: Vector2 = (playground._root_leashes[DUMMY_ID] as Dictionary)["shadow"]
	var moved := dummy.global_position + Vector2(70, 30)
	dummy.global_position = moved
	playground._mortal_positions[DUMMY_ID] = moved  # the host says the dummy walked
	_tick(playground, 1.0)
	_check(dummy.global_position.distance_to(moved) < 1.0, "a rooted dummy still moves while the leash lasts")
	_check(playground._root_leashes.has(DUMMY_ID)
		and (playground._root_leashes[DUMMY_ID] as Dictionary)["shadow"] == shadow,
		"...and its shadow stays planted")
	_tick(playground, 2.0)
	_check(not playground._root_leashes.has(DUMMY_ID), "the leash is gone after 3s")
	_check(playground._root_pulls.has(DUMMY_ID), "the dummy is pulled back toward its shadow")
	var before_drag := dummy.global_position.distance_to(shadow)
	_tick(playground, 0.25)
	_check(dummy.global_position.distance_to(shadow) < before_drag - 1.0 and playground._root_pulls.has(DUMMY_ID),
		"...visibly walking to the circle while the leash stays up (%.1f px left)" % dummy.global_position.distance_to(shadow))
	_tick(playground, 0.625)
	_check(dummy.global_position.distance_to(shadow) < 1.0 and not playground._root_pulls.has(DUMMY_ID),
		"...landing on it before the leash fades")

	# Our own mortal's root is drawn here too, and drags us back when it ends.
	playground.player.global_position = playground._start_position
	playground.rules.cast_down_to_homeland(DUMMY_ID, homeland)
	playground._process(DT)
	_check(playground._root_leashes.has(playground._my_id), "our own root gets its own leash")
	var mine: Vector2 = (playground._root_leashes[playground._my_id] as Dictionary)["shadow"]
	playground.player.global_position += Vector2(-40, 0)
	_tick(playground, 3.1)
	_check(not playground._root_leashes.has(playground._my_id), "our root ends after 3s")
	_check(playground.player._return_time > 0.0 and playground.player._return_target.distance_to(mine) < 1.0,
		"...and drags us back toward the shadow")

	# --- TALA: THE PULL REACHES THE DUMMY TOO -------------------------------------------
	playground.player.global_position = playground._start_position
	var light_way := Gods.favor_by_id(&"let_us_light_your_way")
	_check(playground.rules.bestow_favor(light_way), "Let Us Light Your Way can be taken")
	var pulled_from := dummy.global_position.distance_to(playground.player.global_position)
	playground._use_skill(GodFavor.Slot.E)
	_check(playground._movement_override_time > 0.0, "the pull is running")
	playground._process(DT)
	_check(dummy.global_position.distance_to(playground.player.global_position) < pulled_from - 1.0,
		"the dummy is pulled toward the caster (%.1f -> %.1f px)" % [pulled_from, dummy.global_position.distance_to(playground.player.global_position)])
	_check(dummy.tranced_sprite.visible and dummy.tranced_sprite.is_playing(), "...wearing the tranced sparkles")
	_tick(playground, 1.5)
	playground._process(DT)
	_check(not dummy.tranced_sprite.visible, "...until the pull ends")

	# --- APOLAKI: THE E ADDS SEVEN SUN PATCHES ------------------------------------------
	var sun := Gods.favor_by_id(&"siblings_compromise_sun")
	_check(playground.rules.bestow_favor(sun), "Sibling's Compromise can be taken without a Mayari favor")
	playground._use_skill(GodFavor.Slot.E)
	var patches: Array = playground._sun_patches.get(DUMMY_ID, [])
	_check(patches.size() == 7, "Apolaki's E puts 7 sun patches on the dummy (%d)" % patches.size())
	_check(float(playground._loss_boost.get(DUMMY_ID, 0.0)) > 0.0, "...and marks what it loses while they last")
	var dummy_favor: int = playground.rules.mortal(DUMMY_ID).favor
	playground.lose_favor(100, "test", DUMMY_ID)
	_check(playground.rules.mortal(DUMMY_ID).favor == dummy_favor - 110, "...making that loss 10%% larger (%d)" % (dummy_favor - playground.rules.mortal(DUMMY_ID).favor))

	# --- BATHALA: BLINDSIDE (THE PLAYGROUND'S OWN OVERRIDE) -----------------------------
	var blind := Gods.favor_by_id(&"half_vision_sacrifice")
	if not me.has_favor(blind.id):
		_check(playground.rules.bestow_favor(blind), "Blindside can be taken")
	else:
		me.cooldowns.erase(blind.id)
		_check(true, "Blindside is already held")
	me.favor = 1000
	playground.rules.mortal(DUMMY_ID).favor = 1000
	playground._use_skill(GodFavor.Slot.E)
	_check(playground.rules.mortal(DUMMY_ID).favor == 500,
		"Blindside cuts the dummy's FAVOR in half (%d)" % playground.rules.mortal(DUMMY_ID).favor)
	_check(me.favor == 1000, "...and costs the caster nothing")
	_check(not playground.rules.mortal(DUMMY_ID).bathala_regrowth.is_empty(),
		"...while the dummy slowly wins it back")

	# --- BATHALA: VANTAGE POINT ---------------------------------------------------------
	var vantage := Gods.favor_by_id(&"siblings_compromise_bathala")
	if not me.has_favor(vantage.id):
		_check(playground.rules.bestow_favor(vantage), "Vantage Point can be taken")
	else:
		me.cooldowns.erase(vantage.id)
		_check(true, "Vantage Point is already held")
	me.favor = 1000
	playground._use_skill(GodFavor.Slot.Q)
	_check(me.favor == 500, "Vantage Point cuts our own FAVOR in half (%d)" % me.favor)
	_check(not me.bathala_regrowth.is_empty(), "...then grows 120% of it back")

	# --- THE KEYS -----------------------------------------------------------------------
	var q_key := InputEventAction.new()
	q_key.action = &"skill_q"
	q_key.pressed = true
	_check(playground.rules.bestow_favor(Gods.favor_by_id(&"the_unmoving")), "a fresh Q skill can be taken")
	playground._unhandled_input(q_key)
	_check(float(me.cooldowns.get(&"the_unmoving", 0.0)) > 0.0, "Q casts the favor in the Q slot")
	_check(me.loss_immunity > 0.0, "...and its loss immunity is on")

	# --- ANITUN TABU: THE PASSIVE AND THE WINDS IN THE PLAYGROUND -----------------------
	var kinda := Gods.favor_by_id(&"its_kinda_tabu")
	_check(playground.rules.passives_live, "per-second passives run with no trial clock")
	_check(playground.rules.bestow_favor(kinda), "It's Kinda Tabu can be taken here")
	me.bathala_regrowth.clear()  # the Vantage Point test above must not pay during the count
	me.favor = 1000
	me.cooldowns.clear()
	_tick(playground, 1.0)
	_check(me.favor == 1008, "a ready Q pays 8 FAVOR a second here (%d)" % me.favor)
	playground._use_skill(GodFavor.Slot.Q)
	me.favor = 1000
	_tick(playground, 1.0)
	_check(me.favor == 992, "a recharging Q takes 8 FAVOR a second here (%d)" % me.favor)

	var west := Gods.favor_by_id(&"the_west_wind")
	_check(west.gale_immunity(), "The West Wind carries its gale_immunity clause")
	_check(playground.rules.bestow_favor(west), "The West Wind can be taken here")
	# Clear of the mortal's reach, so only the gales can move the dummy.
	playground.player.global_position = playground._start_position
	dummy.global_position = Vector2(900, 300)
	playground._mortal_positions[DUMMY_ID] = dummy.global_position
	playground.player.wind_drag = Vector2.ZERO
	playground._use_skill(GodFavor.Slot.E)
	var dummy_from: Vector2 = dummy.global_position
	playground._process(DT)
	_check(playground.wind_active() and playground.wind_push.x < 0.0,
		"the gales blow west here (%s)" % str(playground.wind_push))
	_check(is_equal_approx(-playground.wind_push.x, Arena.WIND_DRAG * Arena.WEST_WIND_FORCE),
		"...at %s%% of the blitz's force" % str(Arena.WEST_WIND_FORCE * 100.0))
	_check(playground.player.wind_drag == Vector2.ZERO, "...and their own holder walks through untouched")
	_tick(playground, 0.5)
	_check(dummy.global_position.x < dummy_from.x - 50.0 and is_equal_approx(dummy.global_position.y, dummy_from.y),
		"the dummy is shoved west too (%s -> %s)" % [str(dummy_from), str(dummy.global_position)])
	_check(playground.winds != null and playground.winds.visible, "...and the full-screen gale plays")
	playground._wind_time = 0.0
	_tick(playground, DT)
	var settled: Vector2 = dummy.global_position
	_tick(playground, 0.5)
	_check(dummy.global_position.distance_to(settled) < 0.01, "...and the dummy stops when the gales do")

	# --- LEAVING ------------------------------------------------------------------------
	var leaves := false
	for connection in playground.leave_button.pressed.get_connections():
		var target: Callable = connection["callable"]
		if target.get_method() == "_leave" and target.get_object() == playground:
			leaves = true
	_check(leaves, "the LEAVE button calls the Playground's own leave")

	var main_menu: Control = load("res://scenes/MainMenu.tscn").instantiate()
	view.add_child(main_menu)
	await _frames(2)
	var button := main_menu.get_node_or_null("CenterContainer/VBoxContainer/PlaygroundButton") as Button
	_check(button != null and button.text == "PLAYGROUND", "the MainMenu has a PLAYGROUND button")
	var opens := false
	if button != null:
		for connection in button.pressed.get_connections():
			if (connection["callable"] as Callable).get_method() == "_on_playground_pressed":
				opens = true
	_check(opens, "...wired to open the Playground")
	main_menu.queue_free()

	playground.queue_free()
	await _frames(2)
	_finish()


# One step of the rules and the screen, both on the same clock.
func _tick(playground: PrepArea, seconds: float) -> void:
	var steps := int(round(seconds / DT))
	for index in range(steps):
		playground.rules._process(DT)
		playground._process(DT)


# The card at `index`: its price (or cost) line.
func _price(menu: Control, index: int) -> String:
	if index >= menu.rows.get_child_count():
		return ""
	var label := menu.rows.get_child(index).get_node_or_null("Price") as Label
	return label.text if label != null else ""


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1


func _finish() -> void:
	print("playground checks: %d check(s), %d problem(s)" % [_checks, _problems])
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
