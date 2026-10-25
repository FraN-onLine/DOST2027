extends SceneTree

# Validation: Tala's blitz (the last blitz_duration seconds of the trial).
#   * no blitz during the intro or the countdown
#   * in blitz a second Tala exists, is visible, wears Tala's frames, and keeps
#     walking its own beat: the route mirrored, in a lane in front of her, so the
#     two cross mid-route going opposite ways and it is never at Tala + an offset
#   * the field pulses gold through BlitzGlow alone - Tala, the cans, the field
#     root and the mortal are never tinted
#   * a can pays round(can_favor * blitz_can_multiplier)
#   * a slipper caught by EITHER Tala, and walking into EITHER, stuns the mortal
#   * a round reset removes the double and hides the glow
# Run: godot --headless --path <project> -s res://tools/tala_blitz_check.gd

var _arena: TalaArena
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
	_arena = load("res://scenes/gods/tala/TalaArena.tscn").instantiate()
	view.add_child(_arena)
	await _frames(2)
	while _arena.dialogue.is_active():
		_arena.dialogue.advance()

	# --- no blitz before the round is on ---------------------------------------
	for phase in [Arena.Phase.INTRO, Arena.Phase.COUNTDOWN]:
		_arena._phase = phase
		_arena._trial_time = 0.0
		await _frames(3)
		_check(not _arena._blitz and _arena._second_tala == null and not _arena.blitz_glow.visible,
			"no blitz during phase %d" % phase)

	# --- blitz begins ------------------------------------------------------------
	_arena._phase = Arena.Phase.PLAYING
	_arena.player.set_lock(false)
	_arena._trial_time = 25.0
	await _frames(3)
	var double: AnimatedSprite2D = _arena._second_tala
	_check(_arena._blitz and double != null, "at 25 s left blitz is on and the second Tala exists")
	if double == null:
		quit(1)
		return
	_check(double.visible and double.sprite_frames != null and double.sprite_frames == (_arena.tala as AnimatedSprite2D).sprite_frames,
		"the double is visible and wears Tala's frames")
	_check(double.scale == _arena.tala.scale, "...at Tala's scale")
	var tala_from: Vector2 = _arena.tala.global_position
	var double_from := double.global_position
	await _frames(90)
	var tala_went: Vector2 = _arena.tala.global_position - tala_from
	var double_went := double.global_position - double_from
	_check(tala_went.length() > 20.0 and double_went.length() > 20.0 and tala_went.y * double_went.y < 0.0,
		"after 1.5 s Tala and the double have moved opposite ways along the route (%s / %s)" % [tala_went, double_went])
	var lane_side := signf(_arena._shoot_x - _arena.tala.global_position.x)
	_check(absf(double.global_position.distance_to(_arena._point_on_tala_path(_arena._tala_length - _arena._tala_distance)) - _arena.blitz_double_lane) < 1.0
		and signf(double.global_position.x - _arena.tala.global_position.x) == lane_side,
		"...the double on the mirrored spot of the route, a lane toward the throwing line")
	_check(double.global_position.distance_to(_arena.tala.global_position + Vector2(_arena.blitz_double_lane * lane_side, 0.0)) > 20.0,
		"...and not at Tala + the lane (it walks its own beat)")
	_check(double.flip_h == (_arena.tala as AnimatedSprite2D).flip_h, "...and keeps the original's facing, never flipping as it walks")
	_check(_arena._trial_time > 0.0 and _arena._blitz, "...and blitz is still on")

	# Tala cutting a slipper off does not move the double with her: it walks on at its own pace.
	var beat_before: float = _arena._double_distance
	_arena._tala_seek = _arena.tala.global_position + Vector2(0.0, 40.0)
	_arena._tala_distance = clampf(_arena._tala_distance + 80.0, 0.0, _arena._tala_length)  # she hurries
	_arena._place_second_tala(0.1)
	_check(absf(_arena._double_distance - beat_before) <= _arena.tala_speed * 0.1 + 0.01,
		"while Tala intercepts the double keeps its own pace (%.1f px in 0.1 s)" % absf(_arena._double_distance - beat_before))
	_arena._tala_seek = Vector2.INF
	_arena._place_second_tala()

	# --- the pulse is the field's alone -----------------------------------------
	var glow: ColorRect = _arena.blitz_glow
	_check(glow.visible and glow.size.is_equal_approx(_arena._field.size), "BlitzGlow shows over the field")
	var first := glow.color.a
	var moved := false
	for index in range(30):
		await process_frame
		moved = moved or not is_equal_approx(glow.color.a, first)
	_check(moved, "the glow's alpha changes from frame to frame")
	var untouched := _arena.tala.modulate == Color.WHITE and double.modulate == Color.WHITE \
		and _arena.field_root.modulate == Color.WHITE and _arena.player.modulate == Color.WHITE \
		and _arena.modulate == Color.WHITE
	for can in _arena._cans:
		untouched = untouched and can.modulate == Color.WHITE
	_check(untouched, "Tala, her double, the cans, the field root and the mortal stay untinted")

	# --- the payout --------------------------------------------------------------
	var me = _arena.rules.local()
	me.favor = 0
	_arena._resolve_can(_arena._my_id, 0)
	_check(me.favor == int(round(_arena.can_favor * _arena.blitz_can_multiplier)),
		"a can pays round(%d * %.2f) = %d in blitz (paid %d)" % [_arena.can_favor, _arena.blitz_can_multiplier,
			int(round(_arena.can_favor * _arena.blitz_can_multiplier)), me.favor])

	# --- the stun (nothing awaits from here, so nothing walks) --------------------
	var lane := Vector2(_arena._shoot_x - 100.0, (_arena._cans[0].global_position.y + _arena._cans[1].global_position.y) * 0.5)
	for index in range(_arena._cans.size()):
		_arena._can_repair[index] = 99.0  # no can in the way
	_arena.tala.global_position = Vector2(lane.x + 400.0, _arena._field.position.y + 5.0)
	double.global_position = lane + Vector2(150.0, 0.0)
	_arena.player.global_position = lane
	_arena.player._stun = 0.0
	_arena._modes[_arena._my_id] = "ready"
	_arena._local_mode = "ready"
	me.favor = 500
	_arena._start_throw(_arena._my_id, Vector2.RIGHT)
	for index in range(100):
		_arena._move_slippers(0.02)
		if _arena._modes.get(_arena._my_id) == "retrieve":
			break
	_check(me.favor == 400, "the double catching a slipper costs 100 FAVOR")
	_check(is_equal_approx(_arena.player._stun, _arena.blitz_stun_time), "...and stuns the thrower for %.1f s (%.2f)" % [_arena.blitz_stun_time, _arena.player._stun])

	# A slipper thrown along the double's lane is caught by the double, not by Tala.
	_arena._slippers.clear()
	_arena.player._stun = 0.0
	_arena._modes[_arena._my_id] = "ready"
	_arena._tala_distance = _arena._tala_length * 0.8   # Tala far down the route, the double high up it
	_arena._place_tala()
	_arena._place_second_tala()
	_arena.player.global_position = Vector2(_arena._shoot_x - 100.0, double.global_position.y)
	me.favor = 500
	var tala_hits_before: int = _arena._tala_hits
	_arena._start_throw(_arena._my_id, Vector2.RIGHT)
	for index in range(100):
		_arena._move_slippers(0.02)
		if _arena._modes.get(_arena._my_id) == "retrieve":
			break
	_check(me.favor == 400 and _arena._tala_hits == tala_hits_before + 1 and is_equal_approx(_arena.player._stun, _arena.blitz_stun_time),
		"a slipper thrown along the double's lane is caught by the double (FAVOR %d, stun %.2f)" % [me.favor, _arena.player._stun])

	_arena._slippers.clear()
	_arena.player._stun = 0.0
	_arena._modes[_arena._my_id] = "ready"
	_arena.player.global_position = lane
	_arena.tala.global_position = lane + Vector2(150.0, 0.0)
	double.global_position = Vector2(lane.x + 400.0, _arena._field.position.y + 5.0)
	_arena._start_throw(_arena._my_id, Vector2.RIGHT)
	for index in range(100):
		_arena._move_slippers(0.02)
		if _arena._modes.get(_arena._my_id) == "retrieve":
			break
	_check(is_equal_approx(_arena.player._stun, _arena.blitz_stun_time), "Tala herself stuns on a catch in blitz too (%.2f)" % _arena.player._stun)

	_arena._invuln.clear()
	_arena.player._stun = 0.0
	_arena.tala.global_position = Vector2(lane.x + 400.0, _arena._field.position.y + 5.0)
	double.global_position = _arena.player.global_position
	me.favor = 500
	_arena._check_tala_touch()
	_check(me.favor == 500 - _arena.tala_penalty, "walking into the double costs 100 FAVOR")
	_check(is_equal_approx(_arena.player._stun, _arena.blitz_stun_time), "...and stuns for %.1f s (%.2f)" % [_arena.blitz_stun_time, _arena.player._stun])

	_arena._invuln.clear()
	_arena.player._stun = 0.0
	double.global_position = Vector2(lane.x + 400.0, _arena._field.position.y + 5.0)
	_arena.tala.global_position = _arena.player.global_position
	_arena._check_tala_touch()
	_check(is_equal_approx(_arena.player._stun, _arena.blitz_stun_time), "walking into Tala herself stuns in blitz (%.2f)" % _arena.player._stun)

	# --- a reset clears it ---------------------------------------------------------
	_arena._trial_time = 60.0  # a new round starts with the full clock
	_arena.arena_round_reset()
	await _frames(2)
	_check(_arena._second_tala == null and not _arena.blitz_glow.visible and not _arena._blitz,
		"a round reset removes the double and hides the glow")
	_check(_arena.get_node_or_null("ArenaField/SecondTala") == null, "...and the double is gone from the field")

	print("Tala blitz checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
