extends SceneTree

# Focused regression check for patintero's tuning:
#
#   * the lit zone pays 65% of its first tuning (82 -> 53.3 a second),
#   * BLITZ - the last blitz_time seconds: the light jumps every
#     blitz_switch_interval instead of goal_switch_interval and the lit zone
#     pays blitz_gain_mult (double) while it lasts,
#   * another player is knocked rival_knock_mult (2.5x) as hard as our own
#     mortal - by her touch and by a shockwave,
#   * a clone touching you answers on YOUR screen - the shared shake and wash
#     (the same one Apolaki's duel uses),
#   * a clone braces (blocking animation) when she catches a mortal, then
#     settles back into her idle loop - and a client replays it,
#   * Mayari's own sprite is never modulated - the glow is gone.
#
# Run: godot --headless --path <project> -s res://tools/mayari_check.gd

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
	if _arena.god == null or _arena.zones_root == null or _arena._zones.is_empty():
		printerr("FAIL: the arena did not resolve Mayari's field")
		quit(1)
		return

	var guard := 0
	while _arena.dialogue.is_active() and guard < 40:
		_arena.dialogue.advance()
		guard += 1
	_arena._phase = Arena.Phase.PLAYING
	_arena.player.set_lock(false)
	_arena.set_mortal_invuln(_arena._my_id, 60.0)  # no clone steals this test's FAVOR
	_arena._trial_time = 90.0
	_arena._update_blitz()
	_stand_in_lit_zone()

	# --- THE LIT ZONE PAYS 65% OF ITS FIRST TUNING -----------------------------
	_check(is_equal_approx(_arena.favor_rate, 53.3), "the lit zone pays 53.3 a second (65% of 82)")
	_check(_gain_for(1.0) == 53, "one second in the lit box banks 53 FAVOR")

	# --- BLITZ - THE LAST 20 SECONDS --------------------------------------------
	_arena._trial_time = 90.0
	_arena._update_blitz()
	_check(not _arena._blitz, "eighty seconds left is still a normal round")
	_arena._trial_time = _arena.blitz_time
	_arena._update_blitz()
	_check(_arena._blitz, "the last %ds of the round is BLITZ" % int(_arena.blitz_time))
	_check(_gain_for(1.0) == 106, "in BLITZ the same box pays double (106 a second)")

	# The light's clock is the short one, and it still moves on and refills with it.
	_arena._goal_switch_timer = 5.0
	_arena.arena_rules_tick(0.016)
	_check(_arena._goal_switch_timer <= _arena.blitz_switch_interval + 0.001,
		"in BLITZ a slow light's clock is pulled onto the fast one")
	var before := _arena._active_goal_index
	_arena._goal_switch_timer = 0.0
	_arena.arena_rules_tick(0.016)
	_check(_arena._active_goal_index != before, "the light still moves on")
	_check(is_equal_approx(_arena._goal_switch_timer, _arena.blitz_switch_interval),
		"and holds each box for only %.1fs" % _arena.blitz_switch_interval)

	# ... and the round goes back to normal afterwards.
	_arena._trial_time = 90.0
	_arena._update_blitz()
	_check(not _arena._blitz, "the last stand is over with the clock")
	_check(_gain_for(1.0) == 53, "after BLITZ the box pays 53 a second again")
	_arena._goal_switch_timer = 5.0
	_arena.arena_rules_tick(0.016)
	_check(_arena._goal_switch_timer > _arena.blitz_switch_interval,
		"outside BLITZ the light keeps its slow clock")

	# --- OTHER PLAYERS TAKE 2.5x THE SHOVE --------------------------------------
	_check(is_equal_approx(_arena._knock_force_for(_arena._my_id), _arena.knock_force),
		"our own mortal is knocked at the normal force")
	_check(is_equal_approx(_arena._knock_force_for(2), _arena.knock_force * 2.5),
		"another player is knocked 2.5x as hard")
	_check(is_equal_approx(_arena._knock_force_for(2, _arena.shock_force), _arena.shock_force * 2.5),
		"the shockwave's shove is 2.5x for them too")

	# --- WHEN SHE TOUCHES YOU, THE SCREEN ANSWERS -------------------------------
	_check(_arena.hit_flash != null, "the arena authors the wash on the screen")
	_arena._reset_screen_impact()
	_arena.player._knockback = Vector2.ZERO
	var touching: MayariClone = _arena._clones[0]
	_arena.knock_mortal(_arena._my_id, touching.global_position, 0.0,
		_arena._knock_force_for(_arena._my_id), true)
	_check(_arena.player._knockback != Vector2.ZERO, "her touch shoves you")
	_check((_arena._shake_left > 0.0) == _arena.screen_shake_allowed(),
		"her touch shakes your screen (whenever shaking is on)")
	_check(_arena.hit_flash.visible, "and reddens it")
	_arena._tick_shake(10.0)
	_arena._tick_flash(10.0)
	_check(_arena.field_root.position == Vector2.ZERO, "the field settles back to rest")
	_check(not _arena.hit_flash.visible, "the wash fades out")
	_arena._reset_screen_impact()

	# --- HER SPRITE IS NEVER MODULATED ------------------------------------------
	var clone: MayariClone = _arena._clones[0]
	await _frames(2)
	_check(clone.icon != null and clone.icon.modulate == Color.WHITE,
		"her sprite is drawn unmodulated")
	var patrol_line := clone.path.default_color
	clone.set_hunting(true)
	clone._hunt_left = 5.0
	await _frames(1)
	_check(clone.is_hunting() and clone.icon.modulate == Color.WHITE,
		"even a hunt leaves the sprite unmodulated")
	_check(clone.path.default_color.a > patrol_line.a,
		"the hunt still lights the path line instead")

	# --- HER TOUCH BRACES HER, THEN SHE RETURNS TO IDLE -------------------------
	clone.block()
	_check(clone.icon.animation == &"blocking",
		"a mortal running into her snaps her into the blocking stance")
	_check(clone.block_count() == 1, "the touch is counted so clients can replay it")
	await create_timer(0.8).timeout
	_check(clone.icon.animation == &"default",
		"the block plays once, then she settles back into her idle loop")
	var synced: MayariClone = _arena._clones[1]
	synced.set_block_count(1)
	_check(synced.icon.animation == &"blocking",
		"a client replays the block from the host's hit count")

	# --- SHE FACES THE WAY SHE WALKS --------------------------------------------
	var walker: MayariClone = _arena._clones[0]
	var at := walker.global_position
	walker._last_pos = Vector2.INF
	walker._face_movement()
	walker.global_position = at + Vector2(5, 0)
	walker._face_movement()
	_check(not walker.icon.flip_h, "walking right she faces right")
	walker.global_position = at
	walker._face_movement()
	_check(walker.icon.flip_h, "walking left she is flipped")
	walker.global_position = at + Vector2(-0.2, 0)
	walker._face_movement()
	_check(walker.icon.flip_h, "a tiny move keeps her facing")
	walker._face_movement()
	_check(walker.icon.flip_h, "standing still keeps her facing")
	walker.global_position = at + Vector2(-0.2, 5)
	walker._last_vertical = 0
	walker._face_movement()
	walker.global_position = at + Vector2(-0.2, 10)
	walker._face_movement()
	_check(walker.icon.flip_h, "walking on down a vertical line does not turn her")
	walker.global_position = at + Vector2(-0.2, 5)
	walker._face_movement()
	_check(not walker.icon.flip_h, "reversing on a vertical line turns her round")

	print("Mayari / patintero checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


# Stand exactly in the middle of the lit box.
func _stand_in_lit_zone() -> void:
	_arena.player.global_position = _arena._zones[_arena._active_goal_index].bounds().get_center()


# Reset the pool and bank exactly `seconds` of the lit zone's gain for our own
# mortal, then hand back how much FAVOR landed (whole units only - the fraction
# stays in the pool, the way _check_goals pays it out).
func _gain_for(seconds: float) -> int:
	_arena._zone_pending.clear()
	_arena.rules.local().favor = 0
	_stand_in_lit_zone()
	_arena._check_goals(seconds)
	return _arena.rules.local().favor


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
