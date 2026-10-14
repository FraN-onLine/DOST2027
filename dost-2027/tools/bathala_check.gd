extends SceneTree

# Validation: Bathala's Agawan Base. The field is shared, split into three
# sections with two safe bases; up to 4 opponent gods plus Bathala guarding his
# base; a mortal's attack freezes an enemy god (or thaws a frozen ally); gods tag
# mortals in the common field but never on the mortal's own base; holding
# Bathala's base captures it, pays the holder and costs everyone else, and resets
# the round; and the scoring numbers match the rules.
# Run: godot --headless --path <project> -s res://tools/bathala_check.gd

const DT := 0.25  # exact in binary, so four steps are exactly one second

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
	_check(_arena._gods.size() == 5, "four opponent gods plus Bathala (%d)" % _arena._gods.size())
	var bathala_guards := false
	for god in _arena._gods:
		if god.god_id == &"bathala":
			bathala_guards = true
	_check(bathala_guards, "Bathala is always on the field guarding his base")
	var offense := 0
	var defense := 0
	for god in _arena._gods:
		if god.god_id == &"bathala":
			continue
		if god.role == AgawanGod.Role.ATTACK:
			offense += 1
		else:
			defense += 1
	_check(offense == 2 and defense == 2, "Apolaki and Hanan attack; Mayari and Tala defend (off=%d def=%d)" % [offense, defense])
	_check(_arena._my_base != Vector2.ZERO and _arena._bathala_base != Vector2.ZERO, "both bases are authored on the field")
	_check(_arena._bathala_base.x > _arena._my_base.x, "Bathala's base sits across the field from ours")

	_arena._phase = Arena.Phase.PLAYING
	_arena.player.set_lock(false)

	# --- the mortal's attack freezes an enemy god -------------------------------
	_arena._attack_cd = 0.0
	var target: AgawanGod = _arena._gods[0]
	_arena.player.global_position = target.global_position + Vector2(10, 0)
	_set_favor(0, 0, 0)
	var before: int = _rules.local().favor
	_arena._resolve_attack(_arena._my_id, target.global_position)
	_check(target.is_frozen(), "a swing on an enemy god freezes it")
	_check(_rules.local().favor == before + _arena.tag_god_favor, "tagging a god pays %d FAVOR (+%d)" % [_arena.tag_god_favor, _rules.local().favor - before])
	target.unfreeze()
	_arena._attack_cd = 0.0
	_arena.player.global_position = Vector2(600, 340)
	before = _rules.local().favor
	_arena._resolve_attack(_arena._my_id, Vector2(600, 340))
	_check(_rules.local().favor == before, "a swing that catches nothing pays nothing")

	# --- a frozen ally mortal thaws on the same swing ---------------------------
	_freeze(2)
	_set_favor(0, 0, 0)
	_arena.player.global_position = Vector2(600, 340)
	_arena._mortal_positions[2] = Vector2(605, 340)
	_arena._attack_cd = 0.0
	before = _rules.local().favor
	_arena._resolve_attack(_arena._my_id, Vector2(602, 340))
	_check(not _arena._is_frozen(2), "a swing on a frozen ally mortal thaws them")
	_check(_rules.local().favor == before + _arena.unfreeze_favor, "unfreezing an ally pays %d FAVOR (+%d)" % [_arena.unfreeze_favor, _rules.local().favor - before])

	# --- gods tag mortals in the field, never on their own base -----------------
	for god in _arena._gods:
		god.move_speed = 0.0  # hold them still so the test can place a touch exactly
	_arena._frozen_mortals.clear()
	_set_favor(0, 500, 0)
	var hunter: AgawanGod = _arena._gods[0]
	hunter.unfreeze()
	hunter.global_position = Vector2(600, 340)
	_arena._mortal_positions[2] = Vector2(604, 340)  # a rival in the open field
	before = _rules.mortal(2).favor
	_arena.arena_rules_tick(DT)
	_check(_arena._is_frozen(2), "a god touching a mortal in the field freezes them")
	_check(_rules.mortal(2).favor == before - _arena.tagged_favor, "being tagged costs that mortal %d FAVOR (-%d)" % [_arena.tagged_favor, before - _rules.mortal(2).favor])
	# ...but never on the mortal's own base.
	_arena._frozen_mortals.clear()
	hunter.global_position = _arena._my_base + Vector2(200, 0)
	_arena._mortal_positions[2] = _arena._my_base  # safe on its own base
	_arena.arena_rules_tick(DT)
	_check(not _arena._is_frozen(2), "a mortal on its own base cannot be tagged")

	# --- a frozen mortal thaws on its own after freeze_time ---------------------
	for god in _arena._gods:
		god.global_position = Vector2(9000, 9000)  # park the gods far away
	_arena._frozen_mortals.clear()
	_arena._mortal_positions[2] = Vector2(600, 340)
	_freeze(2)
	for step in range(int(ceil(_arena.freeze_time / DT)) + 1):
		_arena.arena_rules_tick(DT)
	_check(not _arena._is_frozen(2), "a frozen mortal thaws on its own after freeze_time (%.1fs)" % _arena.freeze_time)

	# --- capturing Bathala's base pays the holder and costs everyone ------------
	for god in _arena._gods:
		god.global_position = Vector2(9000, 9000)
	_set_favor(0, 0, 0)
	var round_before: int = _arena._round
	_arena.player.global_position = _arena._bathala_base
	var guard2 := 0
	while _arena._round == round_before and guard2 < 40:
		_arena.arena_rules_tick(DT)
		guard2 += 1
	_check(_rules.local().favor >= _arena.capture_favor, "catching the base pays the holder %d FAVOR (%d)" % [_arena.capture_favor, _rules.local().favor])
	_check(_rules.mortal(2).favor == 0 and _rules.mortal(3).favor == 0, "everyone else lost FAVOR to the capture")
	_check(_arena._round == round_before + 1, "a capture starts a fresh round (%d)" % _arena._round)

	print("Bathala Agawan Base checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


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

