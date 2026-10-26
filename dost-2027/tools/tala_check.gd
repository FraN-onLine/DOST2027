extends SceneTree

# Run: godot --headless --path <project> -s res://tools/tala_check.gd

var _arena: TalaArena
var _problems := 0


# Tala on her route, up at the field's top edge - clear of a throw from the line
# (read from the field, so it holds whatever size the arena is drawn at).
func _tala_clear() -> Vector2:
	return Vector2(_arena.tala.global_position.x, _arena._field.position.y + 10.0)


# A spot behind the shooting line, level with the gap between two cans: a throw
# straight right from here misses every can.
func _lane() -> Vector2:
	var gap := (_arena._cans[0].global_position.y + _arena._cans[1].global_position.y) * 0.5
	return Vector2(_arena._shoot_x - 100.0, gap)


func _initialize() -> void:
	_run()


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)
	_arena = load("res://scenes/gods/tala/TalaArena.tscn").instantiate()
	view.add_child(_arena)
	await process_frame
	await process_frame
	if _arena.tala == null or _arena._cans.size() != 3:
		printerr("FAIL: Tala scene needs Tala and three cans")
		quit(1)
		return
	while _arena.dialogue.is_active():
		_arena.dialogue.advance()
	_arena._phase = Arena.Phase.PLAYING
	_arena._end_intro_shot()  # straight to play: no countdown, so no intro shot either
	_arena.player.set_lock(false)
	_arena.player.global_position = _lane()
	_arena._update_local_bounds()

	# --- Tala walks the route drawn for her in the scene ------------------------
	# The path is read from ArenaField/TalaPath in world space, so moving or
	# reshaping that Line2D in the editor moves Tala with it.
	_check(_arena._tala_knots.size() >= 2 and _arena._tala_length > 0.0,
		"Tala reads the TalaPath drawn in the scene")
	var route_start: Vector2 = _arena.tala.global_position
	_check(_gap_to_route(route_start) <= 1.0, "Tala stands on her route at the start of the round")
	for step in range(30):
		_arena._move_tala(1.0 / 60.0)
	_check(_gap_to_route(_arena.tala.global_position) <= 1.0, "Tala stays on her route while she walks")
	_check(_arena.tala.global_position.distance_to(route_start) > 10.0,
		"Tala actually walks it (%.1f px in half a second)" % _arena.tala.global_position.distance_to(route_start))
	_arena._tala_distance = _arena._tala_length
	_arena._move_tala(0.0)
	var last_knot: Vector2 = _arena._tala_knots[_arena._tala_knots.size() - 1]
	_check(_arena.tala.global_position.distance_to(last_knot) <= 1.0, "the end of the route is the end of the path")
	_arena._move_tala(1.0 / 60.0)
	_check(_arena._tala_dir == -1.0, "Tala turns round at the end of the route")
	_arena._tala_distance = 0.0
	_arena._place_tala()
	_check(_arena.arena_tick_fields().has("tala_distance"),
		"the host tells clients how far along the route Tala is")
	_arena.arena_read_tick({"tala_distance": _arena._tala_length * 0.5, "tala_direction": 1.0})
	_check(_gap_to_route(_arena.tala.global_position) <= 1.0, "a client puts Tala on the same route")

	for can in _arena._cans:
		can.visible = false
	_arena._cans[1].visible = true
	_arena.tala.global_position = _tala_clear()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = _arena._cans[1].global_position
	_arena._input(click)
	for index in range(100):
		_arena._move_slippers(0.02)
		if _arena._modes.get(_arena._my_id) == "ready":
			break
	_check(_arena.rules.local().favor == _arena.can_favor, "hitting a can grants can_favor (%d) FAVOR" % _arena.can_favor)
	_check(_arena._modes.get(_arena._my_id) == "ready", "a can hit returns the player to ready state")

	_arena.rules.local().favor = 500
	_arena._cans[1].visible = false
	_arena._modes[_arena._my_id] = "ready"
	_arena._local_mode = "ready"
	_arena._start_throw(_arena._my_id, Vector2.RIGHT)
	for index in range(100):
		_arena._move_slippers(0.02)
		if _arena._modes.get(_arena._my_id) == "retrieve":
			break
	_check(_arena._modes.get(_arena._my_id) == "retrieve", "a miss leaves the slipper to retrieve")
	_arena._update_local_bounds()
	_check(_arena.player.bounds.end.x > _arena._shoot_x, "only the thrower's barrier opens for retrieval")
	var slipper_pos: Vector2 = _arena._slippers[_arena._my_id]["position"]
	_arena.player.global_position = slipper_pos
	_arena._check_pickups()
	_check(_arena._modes.get(_arena._my_id) == "return", "picking up the slipper requires a return to the line")
	_arena.player.global_position.x = _arena._shoot_x - _arena.player.radius
	_arena._check_pickups()
	_arena._update_local_bounds()
	_check(_arena._modes.get(_arena._my_id) == "ready", "returning to the line restores throwing")
	_check(is_equal_approx(_arena.player.bounds.end.x, _arena._shoot_x), "the barrier closes again at the shooting line")

	_arena.player.global_position = _lane()
	_arena.rules.local().favor = 500
	_arena._modes[_arena._my_id] = "ready"
	_arena._local_mode = "ready"
	_arena.tala.global_position = _lane() + Vector2(30, 0)
	_arena._start_throw(_arena._my_id, Vector2.RIGHT)
	_arena._move_slippers(0.02)
	_check(_arena.rules.local().favor == 400, "Tala catching a slipper costs 100 FAVOR")
	_check(_arena._modes.get(_arena._my_id) == "retrieve", "Tala drops the caught slipper by her area")

	# --- RUNNING INTO TALA HERSELF ----------------------------------------------
	# She keeps walking her route whatever you do; standing in it is no
	# different from her grabbing your slipper: FAVOR lost, shoved back.
	_arena._invuln.clear()
	_arena.player.global_position = _lane()
	_arena.player._knockback = Vector2.ZERO
	_arena.rules.local().favor = 500
	_arena.tala.global_position = _arena.player.global_position
	_arena._check_tala_touch()
	_check(_arena.rules.local().favor == 500 - _arena.tala_penalty, "walking into Tala costs 100 FAVOR")
	_check(_arena.player._knockback != Vector2.ZERO, "walking into Tala shoves the mortal back")
	_check(_arena._invuln.has(_arena._my_id), "the mercy seconds start when Tala touches you")
	_arena._check_tala_touch()
	_check(_arena.rules.local().favor == 500 - _arena.tala_penalty,
		"the mercy seconds keep her from charging the same mortal twice")
	_arena._invuln.clear()

	# --- SHE CUTS A SLIPPER OFF FROM HER OWN BEAT ------------------------------
	# With her chance forced high, a throw makes her hurry along her route to
	# the spot where the slipper's path crosses it - she never steps off the
	# TalaPath, she anticipates the throw from it.
	_arena._end_seek()  # a stray intercept left over from an earlier throw's roll
	_arena._seek_cd = 0.0
	_arena.seek_chance = 1.0
	_arena._tala_seek = Vector2.INF
	for can in _arena._cans:  # keep the throw's line clear of the cans
		can.visible = false
	_arena._tala_distance = 0.0
	_arena._place_tala()
	var block_at: Vector2 = _arena._point_on_tala_path(60.0)
	var slipper_from: Vector2 = block_at + Vector2(-560.0, 0.0)
	_arena.player.global_position = slipper_from
	_arena._modes[_arena._my_id] = "ready"
	_arena._local_mode = "ready"
	_arena._start_throw(_arena._my_id, (block_at - slipper_from).normalized())
	_check(_arena._seeking, "a thrown slipper makes her hurry along her beat to cut it off")
	_check(_arena.arena_tick_fields().get("tala_seek") == _arena.tala.global_position,
		"the host tells every screen where she stands while cutting one off")
	var distance_before := _arena._tala_distance
	var left_the_route := false
	for step in range(240):
		_arena._move_tala(1.0 / 60.0)
		_arena._move_slippers(1.0 / 60.0)
		if _gap_to_route(_arena.tala.global_position) > 1.0:
			left_the_route = true
		if str(_arena._slippers.get(_arena._my_id, {}).get("state", "")) != "flying":
			break
	_check(not left_the_route, "she stays on the TalaPath the whole time")
	_check(_arena._tala_distance > distance_before, "and hurries along it toward the slipper's path")
	_check(_arena.tala.global_position.distance_to(block_at) < 150.0,
		"and plants herself near where the slipper crosses her beat")
	# A catch DROPS the slipper where she stood; a slipper that flew past her
	# would drop out at the far barrier instead.
	var caught: Dictionary = _arena._slippers.get(_arena._my_id, {})
	_check(str(caught.get("state", "")) == "dropped",
		"and she is standing in its path when it arrives")
	# The slipper is dealt with: the intercept ends and the patrol carries on
	# from wherever along the route that left her.
	_arena._move_tala(1.0 / 60.0)
	_check(not _arena._seeking, "she goes back to her beat once the slipper is gone")
	_check(_gap_to_route(_arena.tala.global_position) <= 1.0,
		"and she carries on along the route from where the intercept left her")
	# With her chance spent, the very next throw leaves her walking her route.
	_arena.seek_chance = 0.0
	_arena._seek_cd = 0.0
	_arena._start_throw(2, Vector2.RIGHT, Vector2(500, 300))
	_check(not _arena._seeking, "with no chance rolled she stays on her route")
	_arena._slippers.clear()
	_arena._modes.erase(2)
	_arena.seek_chance = 0.45
	# A client puts her exactly where the host says she stands, and back on the
	# route the moment the host says the intercept is over. The rest of the
	# world travels with that same tick, so nothing else on screen changes.
	var mirror: Dictionary = _arena.arena_tick_fields()
	mirror["tala_seek"] = Vector2(500, 300)
	_arena.arena_read_tick(mirror)
	_check(_arena.tala.global_position == Vector2(500, 300),
		"a client puts her where the host says she stands")
	mirror["tala_seek"] = Vector2.INF
	_arena.arena_read_tick(mirror)
	_check(_gap_to_route(_arena.tala.global_position) <= 1.0,
		"and back on her route when the host says the intercept is over")

	_arena.tala.global_position = _tala_clear()
	_arena.player.global_position = _lane()  # a throw that meets no can
	_arena._local_mode = "ready"
	_arena._modes[_arena._my_id] = "ready"
	_arena.slipper_range = 2000.0
	_arena._start_throw(_arena._my_id, Vector2.RIGHT)
	for index in range(100):
		_arena._move_slippers(0.02)
		if _arena._modes.get(_arena._my_id) == "retrieve":
			break
	var border_landing: Vector2 = _arena._slippers[_arena._my_id]["position"]
	_check(is_equal_approx(border_landing.x, _arena._field.end.x), "a missed slipper stops at the authored arena barrier")
	_arena.slipper_range = 850.0

	var bountiful_e: GodFavor = _arena.god.get_favor(&"the_bountiful_e")
	var light_way: GodFavor = _arena.god.get_favor(&"let_us_light_your_way")
	_check(is_equal_approx(light_way.duration, 1.25), "Let Us Light Your Way pulls for .25s longer")
	_arena.rules.bestow_favor(light_way)
	_arena.rules.bestow_favor(bountiful_e)
	_check(is_equal_approx(_arena.rules.skill_cooldown(GodFavor.Slot.E), 27.0), "Bountiful E reduces cooldown by 10%")
	var shining: GodFavor = _arena.god.get_favor(&"the_shining")
	_arena.rules.bestow_favor(shining)
	_arena._update_movement_favors(0.016)
	_check(is_equal_approx(_arena.player.move_speed, 236.5), "The Shining increases movement speed by 10%")
	var guidance: GodFavor = _arena.god.get_favor(&"the_guidance")
	_arena.rules.bestow_favor(guidance)
	_arena._mortal_positions[2] = _arena.player.global_position + Vector2(100, 0)
	_arena._update_movement_favors(0.016)
	_check(is_equal_approx(_arena.player.move_speed, 354.75), "Guidance adds 50% speed near another mortal")
	_arena.player._forced_move_direction = Vector2.ZERO
	_arena._start_movement_override(2, 1.0)
	_arena._update_movement_favors(0.016)
	_check(_arena.player._forced_move_direction == Vector2.RIGHT, "Let Us Light Your Way redirects movement toward its caster")

	var unbothered: GodFavor = _arena.god.get_favor(&"unswerved_unbothered")
	_arena.rules.bestow_favor(unbothered)
	_arena.rules.use_skill(GodFavor.Slot.Q)
	_arena._sun_patches[_arena._my_id] = [5.0]
	_arena._blind_time = 5.0
	_arena._apply_skill_effect(unbothered, _arena._my_id)
	_check(not _arena._sun_patches.has(_arena._my_id) and _arena._blind_time == 0.0, "Unswerved clears active Sun Patches and Vision Block")
	_arena._add_sun_patches(_arena._my_id, 1, 1.5)
	_check(not _arena._sun_patches.has(_arena._my_id), "Unswerved prevents Sun Patches for its duration")

	# --- THE LAST LIGHT: Tala's dusk pays better --------------------------------
	var last_light: GodFavor = _arena.god.get_favor(&"last_light")
	_check(last_light != null and not last_light.is_skill(), "Tala bestows The Last Light as a passive")
	_check(_arena.rules.bestow_favor(last_light), "...and a mortal can take it")
	var me := _arena.rules.local()
	var before := me.favor
	_arena.rules.time_left = 40.0
	_arena.rules.add_favor(100, "check")
	_check(me.favor - before == 100, "outside the last 30 seconds FAVOR is unchanged (%d)" % (me.favor - before))
	before = me.favor
	_arena.rules.time_left = 30.0
	_arena.rules.add_favor(100, "check")
	_check(me.favor - before == 115, "the last 30 seconds yield 15%% more FAVOR (%d)" % (me.favor - before))
	# The leftover fraction carries over, so a run of small gains gets its 15% too.
	before = me.favor
	_arena.rules.add_favor(10, "check")
	_arena.rules.add_favor(10, "check")
	_check(me.favor - before == 23, "a run of small gains carries the fraction (20 -> 23)")
	before = me.favor
	_arena.rules.time_left = INF
	_arena.rules.add_favor(100, "check")
	_check(me.favor - before == 100, "payouts once the trial is over are not the last light (%d)" % (me.favor - before))

	print("Tala checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1


# How far a point sits from the route Tala walks (0.0 = standing on it).
func _gap_to_route(point: Vector2) -> float:
	var knots: PackedVector2Array = _arena._tala_knots
	if knots.size() < 2:
		return INF
	var gap := INF
	for index in range(1, knots.size()):
		var a := knots[index - 1]
		var b := knots[index]
		var segment := b - a
		var length_squared := segment.length_squared()
		var t := 0.0 if length_squared <= 0.0001 else clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
		gap = minf(gap, point.distance_to(a + segment * t))
	return gap