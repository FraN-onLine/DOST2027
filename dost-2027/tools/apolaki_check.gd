extends SceneTree

# Focused regression check for the personal Arnis duel and Apolaki favor rules.
# Run: godot --headless --path <project> -s res://tools/apolaki_check.gd

var _arena: ApolakiArena
var _problems := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	get_root().add_child(view)
	_arena = load("res://scenes/gods/apolaki/ApolakiArena.tscn").instantiate()
	view.add_child(_arena)
	await process_frame
	await process_frame
	if _arena.duelist == null:
		printerr("FAIL: the arena did not resolve its authored Apolaki")
		quit(1)
		return

	var guard := 0
	while _arena.dialogue.is_active() and guard < 40:
		_arena.dialogue.advance()
		guard += 1
	_arena._phase = Arena.Phase.PLAYING
	_arena.player.set_lock(false)
	_arena.rules.local().favor = 500
	_arena.rules.ensure_mortal(2, "RIVAL").favor = 500
	_arena.duelist.global_position = _arena.player.global_position

	_arena.duelist._enter(ApolakiDuelist.State.OPEN)
	_arena._try_strike()
	_check(_arena.rules.local().favor == 535, "open strike gains 35 FAVOR")
	_arena._strike_cd = 0.0
	_arena.rules.local().favor = 500
	_arena.duelist._enter(ApolakiDuelist.State.GUARD)
	_arena._try_strike()
	_check(_arena.rules.local().favor == 475, "guarded strike loses 25 FAVOR")
	_arena._defend_time = 0.2
	_arena.player._knockback = Vector2.ZERO
	_arena._on_duelist_lunge()
	_check(_arena.rules.local().favor == 495, "well-timed defense gains 20 FAVOR")
	_check(_arena.player._knockback == Vector2.ZERO, "a successful defense prevents knockback")
	_arena._on_duelist_lunge()
	_check(_arena.rules.local().favor == 465, "unblocked lunge loses 30 FAVOR")

	var rivalry: GodFavor = _arena.god.get_favor(&"siblings_rivalry")
	_check(not _arena.rules.is_favor_eligible(rivalry), "Sibling's Rivalry is locked without a Mayari favor")
	_arena.rules.bestow_favor(Gods.mayari().favors[0])
	_check(_arena.rules.is_favor_eligible(rivalry), "a Mayari favor unlocks Sibling's Rivalry")
	_arena.rules.bestow_favor(rivalry)
	_arena.rules.local().favor = 2000
	_arena.rules.mortal(2).favor = 1000
	_arena._tick_siblings_rivalry()
	_check((_arena._sun_patches.get(2, []) as Array).size() == 4, "Sibling's Rivalry drops patches after a 1000 FAVOR lead")
	_arena._tick_siblings_rivalry()
	_check((_arena._sun_patches.get(2, []) as Array).size() == 4, "Sibling's Rivalry triggers only once per opponent")

	_arena._sun_patches.clear()
	_arena.rules.bestow_favor(_arena.god.get_favor(&"the_sun_god"))
	_arena.lose_favor(1, "test loss", 2)
	_check((_arena._sun_patches.get(2, []) as Array).size() == 1, "The Sun God patches an opponent who loses FAVOR")
	_arena._sun_patches.clear()
	_arena.rules.bestow_favor(_arena.god.get_favor(&"the_ruler"))
	var ruler_patches_before := _patch_total_except(_arena._my_id)
	_arena.lose_favor(1, "owner loss", _arena._my_id)
	_check(_patch_total_except(_arena._my_id) > ruler_patches_before, "The Ruler patches a random opponent on owner loss")

	_arena.rules.bestow_favor(_arena.god.get_favor(&"the_victor"))
	var rival_favor_before: int = _arena.rules.mortal(2).favor
	_arena.rules.bestow_favor(_arena.god.get_favor(&"the_victor"), 3)
	_arena._add_sun_patches(2, 5, 1.5)
	_check(_arena.rules.mortal(2).favor == rival_favor_before - 400, "each Victor owner removes 200 FAVOR at five patches")
	var immune_id := 4
	_arena.rules.ensure_mortal(immune_id, "IMMUNE")
	_arena.rules.bestow_favor(_arena.god.get_favor(&"the_victor"), immune_id)
	var immune_favor_before: int = _arena.rules.mortal(immune_id).favor
	_arena._add_sun_patches(immune_id, 5, 1.5)
	_check(_arena.rules.mortal(immune_id).favor == immune_favor_before, "a mortal with The Victor ignores other Victor owners")
	_arena.rules.bestow_favor(_arena.god.get_favor(&"the_great"))
	var great_before: int = _arena.rules.local().favor
	_arena._tick_the_great(1.0)
	_check(_arena.rules.local().favor == great_before + 2, "The Great gains 2 FAVOR while any patch is active")

	var compromise: GodFavor = _arena.god.get_favor(&"siblings_compromise_sun")
	_arena.rules.bestow_favor(compromise)
	_arena._apply_skill_effect(compromise, _arena._my_id)
	_check(is_equal_approx(float(_arena._double_loss.get(2, 0.0)), 5.0), "Sibling's Compromise doubles opponent losses for five seconds")
	var doubled_before: int = _arena.rules.mortal(2).favor
	_arena.lose_favor(10, "doubled test", 2)
	_check(_arena.rules.mortal(2).favor == doubled_before - 20, "active Compromise doubles a FAVOR loss")
	var caster_before: int = _arena.rules.local().favor
	_arena.lose_favor(10, "caster test", _arena._my_id)
	_check(_arena.rules.local().favor == caster_before - 5, "Sibling's Compromise does not double the caster's loss")

	var unmoving: GodFavor = _arena.god.get_favor(&"the_unmoving")
	_arena.rules.bestow_favor(unmoving)
	_arena.rules.use_skill(GodFavor.Slot.Q)
	var shielded_before: int = _arena.rules.local().favor
	_arena.lose_favor(50, "shield test", _arena._my_id)
	_check(_arena.rules.local().favor == shielded_before, "The Unmoving prevents FAVOR loss")

	_arena._sun_patches[_arena._my_id] = [1.0]
	_arena._refresh_sun_patches()
	var visible_patches := 0
	for patch in _arena._sun_patch_rects:
		if patch.visible:
			visible_patches += 1
	_check(visible_patches == 1, "sun patches render on the affected player's screen")

	print("Apolaki checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _patch_total_except(player_id: int) -> int:
	var total := 0
	for id in _arena._sun_patches.keys():
		if int(id) != player_id:
			total += (_arena._sun_patches[id] as Array).size()
	return total


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1