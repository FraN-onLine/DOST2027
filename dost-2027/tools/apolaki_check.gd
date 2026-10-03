extends SceneTree

# Focused regression check for the personal Arnis duel and Apolaki favor rules.
# Run: godot --headless --path <project> -s res://tools/apolaki_check.gd

var _arena: ApolakiArena
var _problems := 0
var _landed := 0


# Counts ApolakiDuelist.attack_landed without going through the arena's scoring.
func _on_attack_landed() -> void:
	_landed += 1


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
	var rival_visual := Node2D.new()
	_arena.ghosts_root.add_child(rival_visual)
	_arena._ghosts[2] = rival_visual
	_arena._sync_ghosts()
	_check(_arena._ghosts.is_empty(), "Apolaki does not render other players")
	_arena.duelist.global_position = _arena.player.global_position

	# --- THE MORAL'S STRIKE: frames 3..5 of hit-arnis --------------------------
	_check(_arena._strike_frame_in_window(3), "the mortal's strike is live on frame 3 (opens)")
	_check(_arena._strike_frame_in_window(5), "the mortal's strike is live on frame 5 (closes)")
	_check(not _arena._strike_frame_in_window(2), "the mortal's strike is not live before frame 3")
	_check(not _arena._strike_frame_in_window(6), "the mortal's strike is not live after frame 5")

	# The mouse path matters: the shell draws a full-screen Control over the
	# arena, so ATTACK is read in _input - a left click that never reaches
	# _unhandled_input still has to start the swing.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_arena._strike_cd = 0.0
	_arena._swinging = false
	_arena._input(click)
	_check(_arena._swinging, "a left click starts the swing (the _input path)")
	_arena._swinging = false
	_arena._strike_cd = 0.0

	# --- THE BALANCE, SPELLED OUT ----------------------------------------------
	_check(_arena.strike_favor == 200, "hitting him while he IDLES or ATTACKS is worth 200 FAVOR")
	_check(_arena.strike_defend_penalty == 100, "hitting his DEFEND costs 100 FAVOR")
	_check(_arena.block_favor == 100, "DEFENDING his swing is worth 100 FAVOR")
	_check(_arena.hit_penalty == 80, "taking his swing while idle or mid-swing costs 80 FAVOR")

	# --- MORTAL -> APOLAKI: all three of his states -----------------------------
	_arena.duelist.global_position = _arena.player.global_position

	_arena.duelist._enter(ApolakiDuelist.State.IDLE)
	_arena.rules.local().favor = 500
	_arena._try_strike()
	_arena._resolve_strike()
	_check(_arena.rules.local().favor == 500 + _arena.strike_favor, "striking him while he IDLES pays 200")
	_arena._strike_cd = 0.0
	_arena._swinging = false

	_arena.duelist._enter(ApolakiDuelist.State.ATTACK)
	_arena.rules.local().favor = 500
	_arena._try_strike()
	_arena._resolve_strike()
	_check(_arena.rules.local().favor == 500 + _arena.strike_favor, "striking him while he ATTACKS pays the same 200")
	_arena._strike_cd = 0.0
	_arena._swinging = false

	_arena.duelist._enter(ApolakiDuelist.State.DEFEND)
	_arena.rules.local().favor = 500
	_arena._try_strike()
	_arena._resolve_strike()
	_check(_arena.rules.local().favor == 500 - _arena.strike_defend_penalty, "striking his DEFEND costs 100")
	_arena._strike_cd = 0.0
	_arena._swinging = false

	# --- HIS SWING -> THE MORTAL: all three of the mortal's states --------------
	# Idle and mid-swing both pay; only DEFENDING turns it into FAVOR.
	_arena._guarding = false
	_arena._swinging = false
	_arena._invuln.clear()
	_arena.rules.local().favor = 500
	_arena._on_duelist_attack_landed()
	_check(_arena.rules.local().favor == 500 - _arena.hit_penalty, "his swing costs 80 while the mortal is IDLE")
	_check((_arena._hit_patches as Array).size() == _arena.hit_patch_count, "a landed swing blots one sun patch on your screen")
	_check(is_equal_approx(float((_arena._hit_patches as Array)[0]), _arena.hit_patch_time), "the blot starts at hit_patch_time (3s)")
	# It has to burn down over REAL frames, not merely vanish on one big tick:
	# the game loop calls this sixty times a second, so a timer that is never
	# stored back would sit at 3.0 forever.
	_arena._tick_hit_patches(_arena.hit_patch_time * 0.5)
	_check((_arena._hit_patches as Array).size() == 1, "the blot is still up half way through its 3 seconds")
	_check(float((_arena._hit_patches as Array)[0]) < _arena.hit_patch_time, "the blot timer burns down every frame")
	var elapsed := _arena.hit_patch_time * 0.5   # the half-way tick above counts too
	while elapsed < _arena.hit_patch_time + 0.5 and not (_arena._hit_patches as Array).is_empty():
		_arena._tick_hit_patches(1.0 / 60.0)
		elapsed += 1.0 / 60.0
	_check((_arena._hit_patches as Array).is_empty(), "the blot clears after 3 seconds of real frames")
	_check(elapsed >= _arena.hit_patch_time, "and it lasted the whole 3 seconds")

	_arena._invuln.clear()
	_arena._swinging = true
	_arena.rules.local().favor = 500
	_arena._on_duelist_attack_landed()
	_check(_arena.rules.local().favor == 500 - _arena.hit_penalty, "being mid-swing does not save you")
	_arena._swinging = false
	_arena._tick_hit_patches(_arena.hit_patch_time + 0.05)

	_arena._invuln.clear()
	_arena._guarding = true
	_arena.player._knockback = Vector2.ZERO
	_arena.rules.local().favor = 500
	_arena._on_duelist_attack_landed()
	_check(_arena.rules.local().favor == 500 + _arena.block_favor, "DEFENDING his swing gains 100")
	_check(_arena.player._knockback == Vector2.ZERO, "a defended swing does not shove the mortal")
	_check((_arena._hit_patches as Array).is_empty(), "a defended swing leaves no sun patch")
	_arena._guarding = false
	_arena._invuln.clear()

	# --- HIS AREA AND HIS WINDOW -----------------------------------------------
	# Count the signal only: hold the arena in RESULTS so its own scoring
	# handler no-ops and this measures the duelist on its own.
	_landed = 0
	_arena.duelist.attack_landed.connect(_on_attack_landed)
	_arena._phase = Arena.Phase.RESULTS
	_arena.duelist.target = _arena.player.global_position
	_arena.duelist.global_position = _arena.player.global_position + Vector2(600.0, 0.0)
	_arena.duelist._enter(ApolakiDuelist.State.ATTACK)
	_arena.duelist.icon.frame = 3
	_arena.duelist._tick_attack_window()
	_check(_landed == 0, "his swing misses while the mortal stands outside his area")
	_arena.duelist.global_position = _arena.player.global_position
	# The window itself: 1 is too early, 3 is live, 6 is too late.
	_arena.duelist._enter(ApolakiDuelist.State.ATTACK)
	_arena.duelist.icon.frame = 1
	_arena.duelist._tick_attack_window()
	_check(_landed == 0, "his swing is not live before frame 2")
	_arena.duelist.icon.frame = 3
	_arena.duelist._tick_attack_window()
	_arena.duelist._tick_attack_window()
	_check(_landed == 1, "his swing connects once per swing inside his area")
	_arena.duelist._enter(ApolakiDuelist.State.ATTACK)
	_arena.duelist.icon.frame = 6
	_arena.duelist._tick_attack_window()
	_check(_landed == 1, "his swing is closed after frame 5")
	_check(_arena.duelist.attack_hit_open_frame == 2 and _arena.duelist.attack_hit_close_frame == 5,
		"his swing is live on frames 2..5")
	_arena._phase = Arena.Phase.PLAYING

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