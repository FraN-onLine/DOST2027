extends SceneTree

# Validation: Bathala's Agawan Base, the finale. The field is shared, with two
# bases; one god per mortal (Apolaki, Tala, Mayari, Hanan in that order) plus
# Bathala; a mortal's swing freezes a god outside Bathala's base, thaws a frozen
# ally or breaks Tala's star; gods freeze mortals off their own base; frozen
# means frozen (no move, swing or capture); holding Bathala's base pays the
# holders and shares with the team, faster with more holders and for the pitied
# last-place mortal, doubled in the final judgment; a god holding the mortals'
# base costs every mortal once; gods thaw each other (touch, Hanan's dawn); and
# Bathala's wariness caps.
# Run: godot --headless --path <project> -s res://tools/bathala_check.gd

const DT := 0.125  # exact in binary, so eight steps are exactly one second
const FIELD := Vector2(640, 340)  # the common field, away from both bases

var _arena: BathalaArena
var _rules: GodMatch
var _problems := 0


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
	_arena = load("res://scenes/gods/bathala/BathalaArena.tscn").instantiate()
	view.add_child(_arena)
	await _frames(2)
	_rules = _arena.rules
	var guard := 0
	while _arena.dialogue.is_active() and guard < 40:
		_arena.dialogue.advance()
		guard += 1
	_check(_arena.god.id == Gods.BATHALA, "the arena belongs to Bathala")
	_check(_arena.god.implemented and _arena.god.arena_scene != "", "Bathala is now an implemented god with an arena")
	_check(not _arena.separate_players() and _arena.shares_mortal_positions(), "Agawan Base is a shared field")
	_check(_arena.god.color.is_equal_approx(Color(0.30, 0.31, 0.36, 1)), "Bathala is dark grey")
	_check(UITokens.god_text(_arena.god) == UITokens.GOLD and UITokens.god_accent(_arena.god) == UITokens.GOLD,
		"Bathala's text and accents are drawn in the gold")
	_check(_arena._my_base != Vector2.ZERO and _arena._bathala_base != Vector2.ZERO, "both bases are authored on the field")
	_check(_arena._bathala_base.x > _arena._my_base.x, "Bathala's base sits across the field from ours")

	# --- the roster: one god per mortal plus Bathala, in slot order -------------
	_check(_arena.roster_ids() == ["apolaki", "tala", "bathala"], "solo testing meets 2+1 (%s)" % str(_arena.roster_ids()))
	_check(BathalaArena.roster_for(1).size() == 2, "one mortal still gets two gods")
	var order := ["apolaki", "tala", "mayari", "hanan"]
	for players in [2, 3, 4]:
		_arena._build_gods(BathalaArena.roster_for(players))
		var expected: Array = order.slice(0, players) + ["bathala"]
		_check(_arena.roster_ids() == expected, "%d players meet %d+1 in slot order (%s)" % [players, players, str(_arena.roster_ids())])
	var roles_ok := true
	for god_node in _arena._gods:
		var attacks := god_node.god_id == &"apolaki" or god_node.god_id == &"mayari"
		if (god_node.role == AgawanGod.Role.ATTACK) != attacks:
			roles_ok = false
	_check(roles_ok, "Apolaki and Mayari attack; Tala, Hanan and Bathala defend")
	var layout := _arena.arena_layout_fields()
	_check((layout["gods"] as Array).size() == 5 and str(layout["gods"][2]["id"]) == "mayari", "the roster travels in the layout")
	var tick_keys := _arena.arena_tick_fields().keys()
	var wanted := ["god_hold", "hold", "holders", "stars", "pulses", "wary", "pity", "judgment"]
	var has_all := true
	for key in wanted:
		has_all = has_all and tick_keys.has(key)
	_check(has_all and _arena.arena_tick_fields()["gods"][0].has("windup"), "the tick carries both holds, the stars, the pulses, the wariness, the pity, the judgment and the lunge")

	_arena._phase = Arena.Phase.PLAYING
	_arena._trial_time = 90.0
	_arena.player.set_lock(false)
	_fresh_round()

	# --- the mortal's swing ----------------------------------------------------
	var apolaki := _god(&"apolaki")
	var tala := _god(&"tala")
	var mayari := _god(&"mayari")
	var hanan := _god(&"hanan")
	apolaki.global_position = FIELD + Vector2(60, 0)
	_set_favor(0, 0, 0)
	_arena._resolve_attack(1, apolaki.global_position)
	_check(apolaki.is_frozen(), "a swing on a god in the field freezes it")
	_check(_mine() == _arena.tag_god_favor, "tagging a god pays %d FAVOR (%d)" % [_arena.tag_god_favor, _mine()])
	apolaki.unfreeze()
	_set_favor(0, 0, 0)
	_arena._resolve_attack(1, FIELD + Vector2(0, 200))
	_check(_mine() == 0, "a swing that catches nothing pays nothing")
	tala.global_position = _arena._bathala_base + Vector2(10, 0)
	_arena._resolve_attack(1, tala.global_position)
	_check(not tala.is_frozen() and _mine() == 0, "a god inside Bathala's base cannot be tagged")
	tala.global_position = _arena._my_base + Vector2(10, 0)
	_arena._resolve_attack(1, tala.global_position)
	_check(tala.is_frozen(), "a god inside the mortals' base can be tagged (that is how you defend it)")
	_fresh_round()

	# --- a frozen ally mortal thaws on the same swing ---------------------------
	_arena._mortal_positions[2] = FIELD + Vector2(5, 0)
	_freeze(2)
	_set_favor(0, 0, 0)
	_arena._resolve_attack(1, FIELD + Vector2(2, 0))
	_check(not _arena._is_frozen(2), "a swing on a frozen ally mortal thaws them")
	_check(_mine() == _arena.unfreeze_favor, "unfreezing an ally pays %d FAVOR (%d)" % [_arena.unfreeze_favor, _mine()])

	# --- Tala's star -------------------------------------------------------------
	_fresh_round()
	_arena._stars.append({"pos": FIELD + Vector2(8, 0), "vel": Vector2.ZERO, "left": 3.0})
	_set_favor(0, 0, 0)
	_arena._resolve_attack(1, FIELD)
	_check(_arena._stars.is_empty() and _mine() == _arena.star_break_favor,
		"a swing breaks Tala's star for %d FAVOR (%d)" % [_arena.star_break_favor, _mine()])
	_fresh_round()
	_arena.star_interval = 5.0
	tala.global_position = FIELD + Vector2(150, 0)
	_arena.player.global_position = FIELD
	_arena._star_cd = DT
	_set_favor(500, 0, 0)
	_tick(1)
	_check(_arena._stars.size() == 1, "Tala throws a star at the nearest mortal in the field")
	_tick(16)
	_check(_arena._is_frozen(1) and _mine() == 500 - _arena.tagged_favor, "Tala's star freezes the mortal it hits (-%d)" % _arena.tagged_favor)
	_arena.star_interval = 0.0

	# --- gods tag mortals in the field, never on their own base -----------------
	_fresh_round()
	_set_favor(0, 500, 0)
	apolaki.global_position = FIELD
	_arena._mortal_positions[2] = FIELD + Vector2(4, 0)
	_tick(1)
	_check(_arena._is_frozen(2), "a god touching a mortal in the field freezes them")
	_check(_rules.mortal(2).favor == 500 - _arena.tagged_favor, "being tagged costs that mortal %d FAVOR" % _arena.tagged_favor)
	_fresh_round()
	apolaki.global_position = _arena._my_base + Vector2(4, 0)
	_arena._mortal_positions[2] = _arena._my_base
	_tick(1)
	_check(not _arena._is_frozen(2), "a mortal on its own base cannot be tagged")

	# --- frozen means frozen -----------------------------------------------------
	_fresh_round()
	_arena._mortal_positions[2] = FIELD + Vector2(0, 120)
	_freeze(1)
	_arena._refresh_lock()
	_check(_arena.player.locked, "a frozen mortal's own screen locks it (it cannot move or dash)")
	_arena._refresh_marks()
	var mark: Label = _arena._mark_labels.get(1)
	_check(mark != null and mark.text == "5", "a frozen mortal carries a 5-4-3-2-1 over its head")
	apolaki.global_position = _arena.player.global_position + Vector2(10, 0)
	_set_favor(0, 0, 0)
	_arena._resolve_attack(1, _arena.player.global_position)
	_check(not apolaki.is_frozen() and _mine() == 0, "a frozen mortal's swing does nothing")
	_freeze(2)
	apolaki.global_position = _arena._mortal_positions[2] + Vector2(5, 0)
	_arena._on_agawan_attack_requested(2, _arena._mortal_positions[2])
	_check(not apolaki.is_frozen() and _rules.mortal(2).favor == 0, "a frozen client's attack request is rejected")
	_park()
	_arena.player.global_position = _arena._bathala_base
	var round_before: int = _arena._round
	_tick(16)
	_check(_arena._round == round_before and _arena._hold_progress == 0.0, "a frozen mortal holds nothing in Bathala's base")
	_arena._frozen_mortals.clear()
	_arena._refresh_lock()
	_check(not _arena.player.locked, "the mortal is free again once it thaws")
	_fresh_round()
	_arena._mortal_positions[2] = FIELD
	_freeze(2)
	_tick(int(ceil(_arena.freeze_time / DT)) + 1)
	_check(not _arena._is_frozen(2), "a frozen mortal thaws on its own after freeze_time (%.1fs)" % _arena.freeze_time)

	# --- capturing Bathala's base: holders 500, everyone else 150, nobody loses --
	_fresh_round()
	_set_favor(1000, 1000, 1000)
	_arena._mortal_positions[2] = FIELD
	_arena._mortal_positions[3] = FIELD + Vector2(0, 60)
	_arena.player.global_position = _arena._bathala_base
	round_before = _arena._round
	var ticks_one := _ticks_to_capture()
	_check(_mine() == 1000 + _arena.capture_favor, "the holder gets %d FAVOR (%d)" % [_arena.capture_favor, _mine() - 1000])
	_check(_rules.mortal(2).favor == 1000 + _arena.capture_share_favor and _rules.mortal(3).favor == 1000 + _arena.capture_share_favor,
		"every other mortal shares %d FAVOR and nobody loses any" % _arena.capture_share_favor)
	_check(_arena._round == round_before + 1 and _arena._pause > 0.0, "a capture ends the round and the field stands still")
	_arena._refresh_lock()
	_check(_arena.player.locked, "the mortals cannot move while the field stands still")
	_arena.player.global_position = FIELD
	_tick(int(ceil((_arena.round_pause + _arena.countdown_time) / DT)) + 2)
	_check(_arena._pause <= 0.0 and _arena._count <= 0.0 and _arena.player.global_position == _arena._start_position,
		"after the pause and the 3-2-1 everyone is back at spawn")
	_arena._refresh_lock()
	_check(not _arena.player.locked, "...and free to play the next round")
	_fresh_round()
	_arena.player.global_position = _arena._bathala_base
	_arena._mortal_positions[2] = _arena._bathala_base + Vector2(10, 0)
	var ticks_two := _ticks_to_capture()
	_check(ticks_two < ticks_one, "two holders capture faster than one (%d < %d steps)" % [ticks_two, ticks_one])

	# --- the final judgment doubles both payouts ---------------------------------
	_fresh_round()
	_arena._mortal_positions[2] = FIELD
	_arena._trial_time = _arena.judgment_time - 1.0
	_tick(1)
	_check(_arena._judgment, "the final judgment begins with %ds left" % int(_arena.judgment_time))
	_check(_arena.field_root.border.default_color.is_equal_approx(Color(UITokens.GOLD_HI, _arena.field_root.border.default_color.a)),
		"the field border turns gold for the judgment")
	_set_favor(0, 0, 0)
	_arena.player.global_position = _arena._bathala_base
	_ticks_to_capture()
	_check(_mine() == 2 * _arena.capture_favor and _rules.mortal(2).favor == 2 * _arena.capture_share_favor,
		"the judgment doubles the capture (%d) and the share (%d)" % [_mine(), _rules.mortal(2).favor])
	_arena._judgment = false
	_arena._trial_time = 90.0

	# --- Bathala's pity: the last-place mortal holds for pity_hold ----------------
	_set_favor(1000, 200, 600)
	_fresh_round()
	_check(_arena._pity_id == 2, "the last-place mortal is pitied at the round's start (%d)" % _arena._pity_id)
	_check(is_equal_approx(_arena.hold_needed([2]), _arena.pity_hold) and is_equal_approx(_arena.hold_needed([1]), _arena.hold_to_capture),
		"the pitied mortal holds %.1fs, everyone else %.1fs" % [_arena.pity_hold, _arena.hold_to_capture])
	_arena.player.global_position = FIELD
	_arena._mortal_positions[2] = _arena._bathala_base
	var ticks_pity := _ticks_to_capture()
	_check(ticks_pity < ticks_one, "the pitied mortal captures faster (%d < %d steps)" % [ticks_pity, ticks_one])
	_arena._mortal_positions.clear()
	_fresh_round()
	_check(_arena._pity_id == -1, "with one mortal nobody is pitied")

	# --- the gods capture your base: every mortal loses 500, once ----------------
	_arena._mortal_positions[2] = FIELD
	_arena._mortal_positions[3] = FIELD + Vector2(0, 60)
	_arena.player.global_position = FIELD + Vector2(0, -60)
	_fresh_round()
	_set_favor(1000, 1000, 1000)
	apolaki.global_position = _arena._my_base
	round_before = _arena._round
	_tick(int(_arena.god_hold_to_capture / DT) - 1)
	_check(_arena._round == round_before and _arena._god_hold > 0.5, "the gods' hold fills a ring on your base (%.2f)" % _arena._god_hold)
	_tick(1)
	_check(_arena._round == round_before + 1, "a god held in your base for %.1fs captures it" % _arena.god_hold_to_capture)
	_tick(int(ceil((_arena.round_pause + _arena.countdown_time) / DT)))
	_check(_mine() == 500 and _rules.mortal(2).favor == 500 and _rules.mortal(3).favor == 500,
		"every mortal loses %d exactly once (%d %d %d)" % [_arena.base_lost_favor, _mine(), _rules.mortal(2).favor, _rules.mortal(3).favor])
	_fresh_round()
	apolaki.global_position = _arena._my_base
	apolaki.freeze_for(_arena.freeze_time)
	round_before = _arena._round
	_tick(int(_arena.god_hold_to_capture / DT) * 2)
	_check(_arena._round == round_before and _arena._god_hold == 0.0, "a god frozen inside your base stops its hold")

	# --- the gods thaw each other ------------------------------------------------
	_fresh_round()
	tala.global_position = FIELD + Vector2(0, 200)
	tala.freeze_for(_arena.freeze_time)
	mayari.global_position = tala.global_position + Vector2(20, 0)
	_tick(1)
	_check(not tala.is_frozen(), "a live god touching a frozen god thaws it")
	_fresh_round()
	_arena.ally_pulse_interval = 5.0
	hanan.global_position = FIELD + Vector2(0, 200)
	tala.global_position = hanan.global_position + Vector2(80, 0)
	mayari.global_position = hanan.global_position + Vector2(-200, 0)
	tala.freeze_for(_arena.freeze_time)
	mayari.freeze_for(_arena.freeze_time)
	_arena._pulse_timers[_arena._gods.find(hanan)] = DT
	_tick(1)
	_check(not tala.is_frozen() and mayari.is_frozen(), "Hanan's dawn thaws the frozen gods in range, and only those")
	_arena.ally_pulse_interval = 0.0

	# --- Bathala grows wary -------------------------------------------------------
	_arena._wary = 1
	_check(is_equal_approx(_arena.wary_speed(), 1.0 + _arena.wary_speed_step), "every capture makes the gods %d%% faster" % int(_arena.wary_speed_step * 100))
	_arena._wary = 20
	_check(is_equal_approx(_arena.wary_speed(), 1.0 + _arena.wary_speed_cap), "the wariness caps at +%d%% (%.2f)" % [int(_arena.wary_speed_cap * 100), _arena.wary_speed()])
	_tick(1)
	_check(is_equal_approx(apolaki.speed_mult, _arena.wary_speed()), "the gods walk at the wary speed")

	print("Bathala Agawan Base checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _god(id: StringName) -> AgawanGod:
	return _arena._god_by_id(id)


# A clean round with every god held still and parked off the field, so a test
# only meets the gods it puts somewhere. Tala's star and Hanan's dawn stay off
# unless a test turns them on.
func _fresh_round() -> void:
	_arena.star_interval = 0.0
	_arena.ally_pulse_interval = 0.0
	_arena.arena_round_reset()
	_arena._invuln.clear()
	for god_node in _arena._gods:
		god_node.move_speed = 0.0
		god_node.lunge_interval = 0.0
	_park()


func _park() -> void:
	for index in range(_arena._gods.size()):
		_arena._gods[index].global_position = Vector2(9000, 9000 + index * 100)


func _tick(steps: int) -> void:
	for step in range(steps):
		_arena.arena_rules_tick(DT)


# Rules steps until the round ends (at most 40).
func _ticks_to_capture() -> int:
	var round_before: int = _arena._round
	var steps := 0
	while _arena._round == round_before and steps < 40:
		_arena.arena_rules_tick(DT)
		steps += 1
	return steps


func _mine() -> int:
	return _rules.local().favor


func _set_favor(mine: int, rival: int, rival_two: int) -> void:
	_rules.mortal(1).favor = mine
	_rules.mortal(2).favor = rival
	_rules.mortal(3).favor = rival_two


func _freeze(mortal_id: int) -> void:
	_arena._frozen_mortals[mortal_id] = _arena.freeze_time


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
