extends SceneTree

# Validation: the mortals fall from the sky at GO (Arena, THE GO DROP).
#   * before GO (intro, countdown, intro shot) every mortal's visuals are hidden
#     - the local player and the ghosts - while the bodies stay on their spawns
#   * at GO each mortal's drop_offset starts above the view's top edge (the arena's
#     or the follow camera's), the body stays on its spawn the whole drop, and the
#     offset is 0 by drop_time; the order is by peer id and everyone is down by 0.9
#   * the map shakes once, after the last mortal has landed
#   * the player stays locked, the clock stays at the full round and the phase stays
#     the countdown's during the drop; control and the clock begin after it
#   * a mortal that appears mid-drop is not dropped
#   * with drop_enabled off (or Settings > Intro camera off) nothing hides or falls
#     and the round opens at GO as before
#   * Bathala's later rounds drop again, holding the clock and the rules meanwhile
#   * the offset really lifts the sprite and the tag above it (physics frames)
# The arena's clock is stepped by hand (DT), so every number is exact.
# Run: godot --headless --path <project> -s res://tools/go_drop_check.gd

const DT := 0.05
const SCREEN := Vector2(1152.0, 648.0)

var _problems := 0
var _view: SubViewport


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(SCREEN)
	_view.disable_3d = true
	root.add_child(_view)
	var settings: Node = root.get_node("Settings")
	var intro_before: bool = settings.get_value("gameplay", "intro_camera")
	var shake_before: bool = settings.get_value("gameplay", "screen_shake")
	settings.set_value("gameplay", "intro_camera", true)
	settings.set_value("gameplay", "screen_shake", true)

	# --- static view -------------------------------------------------------------------------------
	var arena := await _open("res://scenes/gods/mayari/MayariArena.tscn", false)
	var ghost_low := _add_ghost(arena, 5)
	var ghost_high := _add_ghost(arena, 2)
	var everyone := [arena.player, ghost_high, ghost_low]
	var spawns := {}
	for mortal in everyone:
		spawns[mortal] = mortal.global_position
	_step(arena, DT)
	_check(arena._phase == Arena.Phase.INTRO and _all(everyone, func(m): return m.drop_hidden),
		"during the intro dialogue every mortal's visuals are hidden")
	arena._start_countdown()
	var spawn: Vector2 = arena.player.global_position
	for mortal in everyone:
		spawns[mortal] = mortal.global_position
	_step(arena, DT)
	_check(_all(everyone, func(m): return m.drop_hidden), "...and during the countdown (%d mortals)" % everyone.size())
	_step_for(arena, 1.5)
	_check(_all(everyone, func(m): return m.drop_hidden and m.global_position == spawns[m]) and arena.intro_camera() != null,
		"...and the intro shot, the bodies on their spawns")
	_check(arena.field_root.visible and arena.hud.visible, "the trial's own field and HUD are not hidden")
	await _physics(3)
	_check(arena.player.sprite.self_modulate.a == 0.0 and arena.player.name_tag.self_modulate.a == 0.0
		and arena.player.shadow.self_modulate.a == 0.0, "a hidden mortal draws nothing (sprite, tag, shadow)")
	_run_countdown(arena)
	_check(arena._going and arena.drop_active() and arena._phase == Arena.Phase.COUNTDOWN, "GO starts the drop (the phase stays the countdown's)")
	_check(arena.intro_camera() == null and _view.canvas_transform == Transform2D.IDENTITY, "...on the normal view")
	_check(arena.hud.banner_label.text == "GO!", "...with the GO! banner up")
	var cast: Dictionary = arena._drop_cast
	var ids := cast.keys()
	var delays_ok: bool = cast[ids[0]]["delay"] == 0.0
	var sorted_ids := ids.duplicate()
	sorted_ids.sort()
	for index in range(1, sorted_ids.size()):
		delays_ok = delays_ok and cast[sorted_ids[index]]["delay"] > cast[sorted_ids[index - 1]]["delay"]
		delays_ok = delays_ok and cast[sorted_ids[index]]["delay"] <= 0.12 * arena.drop_time + 0.0001
	_check(delays_ok and sorted_ids.size() == 3, "the stagger runs by peer id, 0-0.12 s (%s)" % str(sorted_ids))
	_step(arena, DT)
	var high := true
	for mortal in everyone:
		high = high and mortal.global_position.y + mortal.drop_offset.y < 0.0
	_check(high, "every mortal starts above the visible top edge (y %.0f, %.0f, %.0f)" % [
		arena.player.global_position.y + arena.player.drop_offset.y, ghost_high.global_position.y + ghost_high.drop_offset.y,
		ghost_low.global_position.y + ghost_low.drop_offset.y])
	_check(_all(everyone, func(m): return not m.drop_hidden and m.drop_shadow < 0.2), "...visible, their shadows small and faint on the ground")
	await _physics(2)
	var mover: ArenaMortal = arena.player
	var feet_y := mover.shadow.position.y
	_check(mover.sprite.position.y < mover._sprite_base_position.y - 100.0 and mover.name_tag.position.y < -100.0,
		"the sprite and the tag are lifted by the offset (sprite %.0f, tag %.0f)" % [mover.sprite.position.y, mover.name_tag.position.y])
	_check(is_equal_approx(mover.shadow.position.y, feet_y), "...while the shadow stays on the ground")

	var trial_full: float = arena.trial_time
	var kept := true
	var locked := true
	var held := true
	var shakes := 0
	var shake_after_landing := true
	var last_shake: float = arena._shake_left
	var accelerating := true
	var previous_step := 0.0
	var steps := 0
	while arena.drop_active() and steps < 100:
		var before: float = arena.player.drop_offset.y
		_step(arena, DT)
		steps += 1
		for mortal in everyone:
			kept = kept and mortal.global_position == spawns[mortal]
		if arena.drop_active():  # (the step that ends the drop is the one that opens the round)
			locked = locked and arena.player.locked
			held = held and arena._trial_time == trial_full and arena._phase != Arena.Phase.PLAYING
		if arena._shake_left > last_shake + 0.0001:
			shakes += 1
			for id in arena._drop_cast.keys():
				shake_after_landing = shake_after_landing and bool(arena._drop_cast[id]["landed"])
		last_shake = arena._shake_left
		var moved: float = arena.player.drop_offset.y - before
		if before < 0.0 and arena.player.drop_offset.y < 0.0:
			accelerating = accelerating and moved >= previous_step - 0.0001  # it falls ever faster
			previous_step = moved
	_check(kept, "the bodies stay on their spawns the whole drop")
	_check(locked, "the player is locked through it")
	_check(held, "the clock holds at the full round (%.1f s) and the phase stays the countdown's" % trial_full)
	_check(shakes == 1 and shake_after_landing, "the map shakes once, after the last landing (%d request)" % shakes)
	_check(_all(everyone, func(m): return m.drop_offset == Vector2.ZERO), "every drop_offset is 0 by drop_time")
	_check(accelerating, "the fall accelerates (ease in)")
	_check(arena._phase == Arena.Phase.PLAYING and not arena.player.locked, "the round opens when it ends: playing, the player unlocked")
	_check(steps <= int(ceil(arena.drop_time / DT)) + 1, "...after %d steps of %.2f s (drop_time %.1f s)" % [steps, DT, arena.drop_time])
	_check(arena._trial_time == trial_full, "...the clock still at the full round at that moment")
	_step_for(arena, 0.5)
	_check(arena._trial_time < trial_full - 0.4, "...and then it runs (%.2f s)" % arena._trial_time)
	_check(_all(everyone, func(m): return not m.drop_hidden and m.drop_offset == Vector2.ZERO), "everyone stands on the field")

	# --- a mortal that arrives mid-round is not dropped ---------------------------------------------
	await _close(arena)
	arena = await _open("res://scenes/gods/mayari/MayariArena.tscn", false)
	arena._start_countdown()
	_run_countdown(arena)
	_step(arena, DT)
	var late := _add_ghost(arena, 9)
	_step(arena, DT)
	_check(not late.drop_hidden and late.drop_offset == Vector2.ZERO, "a mortal that arrives mid-drop is on the field, not dropped")
	await _close(arena)

	# --- follow camera: from above the follow view --------------------------------------------------
	arena = await _open("res://scenes/gods/tala/TalaArena.tscn", true)
	arena._start_countdown()
	_step_for(arena, 1.0)
	_run_countdown(arena)
	_step(arena, DT)
	var follow := arena.camera
	_check(follow != null and _view.get_camera_2d() == follow, "follow: the follow camera is on the mortal at GO")
	if follow != null:
		follow.force_update_scroll()
		var top := follow.get_screen_center_position().y - SCREEN.y * 0.5 / follow.zoom.y
		_check(arena.player.global_position.y + arena.player.drop_offset.y < top,
			"follow: the mortal starts above the top of the follow view (%.0f < %.0f)" % [arena.player.global_position.y + arena.player.drop_offset.y, top])
		_check(arena.player.global_position.y > top and arena.player.global_position.y < top + SCREEN.y / follow.zoom.y,
			"...and lands inside it")
	await _close(arena)

	# --- off: nothing hides, nothing falls ---------------------------------------------------------
	arena = await _open("res://scenes/gods/apolaki/ApolakiArena.tscn", false)
	arena.drop_enabled = false
	arena._start_countdown()
	_step(arena, DT)
	_check(not arena.player.drop_hidden and not arena.drop_active(), "drop_enabled off: the mortal is on the field in the countdown")
	_run_countdown(arena)
	_check(arena._phase == Arena.Phase.PLAYING and not arena.drop_active() and not arena.player.locked,
		"...and play starts at GO as before")
	await _close(arena)
	settings.set_value("gameplay", "intro_camera", false)
	arena = await _open("res://scenes/gods/hanan/HananArena.tscn", false)
	arena._start_countdown()
	_step(arena, DT)
	_check(not arena.player.drop_hidden, "Intro camera off: nothing is hidden in the countdown")
	_run_countdown(arena)
	_check(arena._phase == Arena.Phase.PLAYING and not arena.drop_active(), "...and play starts at GO as before")
	await _close(arena)
	settings.set_value("gameplay", "intro_camera", true)

	# --- Bathala: every GO drops -----------------------------------------------------------------------
	var bathala := await _open("res://scenes/gods/bathala/BathalaArena.tscn", false) as BathalaArena
	bathala._start_countdown()
	_run_countdown(bathala)
	_run_to_playing(bathala)
	_check(bathala._phase == Arena.Phase.PLAYING, "Bathala: the first GO drops, then plays")
	_step_for(bathala, 0.3)
	bathala._start_round()
	_step(bathala, DT)
	_check(bathala.player.drop_hidden, "Bathala: a later round's 3 - 2 - 1 holds the mortals off the field")
	var guard := 0
	while not bathala.drop_active() and guard < 200:
		_step(bathala, DT)
		guard += 1
	_check(bathala.drop_active() and bathala._phase == Arena.Phase.PLAYING, "Bathala: its GO drops them again")
	_step(bathala, DT)
	var clock: float = bathala._trial_time
	_step(bathala, DT)
	_check(bathala.player.drop_offset.y < 0.0 and bathala.player.locked and bathala._trial_time == clock,
		"...locked, the clock held (%.2f s)" % clock)
	_run_to_playing(bathala, true)
	_check(not bathala.drop_active() and bathala.player.drop_offset == Vector2.ZERO and not bathala.player.drop_hidden,
		"...and they stand on the field after it")
	_step_for(bathala, 0.3)
	_check(bathala._trial_time < clock and not bathala.player.locked, "...then the clock runs and the player is free")
	await _close(bathala)

	settings.set_value("gameplay", "intro_camera", intro_before)
	settings.set_value("gameplay", "screen_shake", shake_before)
	print("go drop checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _add_ghost(arena: Arena, id: int) -> ArenaMortal:
	var ghost: ArenaMortal = load("res://scenes/gods/common/Mortal.tscn").instantiate()
	arena.ghosts_root.add_child(ghost)
	ghost.set_lock(true)
	ghost.global_position = arena._start_position + Vector2(40.0 * id, 25.0 * id)
	arena._ghosts[id] = ghost
	return ghost


func _all(mortals: Array, test: Callable) -> bool:
	for mortal in mortals:
		if not test.call(mortal):
			return false
	return true


func _open(path: String, follow: bool) -> Arena:
	var arena: Arena = load(path).instantiate()
	arena.follow_camera = follow
	_view.add_child(arena)
	await _frames(2)
	arena.set_process(false)  # the clock is stepped by hand
	return arena


func _close(arena: Arena) -> void:
	arena.queue_free()
	await _frames(2)
	_view.canvas_transform = Transform2D.IDENTITY


func _physics(count: int) -> void:
	for index in range(count):
		await physics_frame


func _step(arena: Arena, delta: float) -> void:
	arena._process(delta)


func _step_for(arena: Arena, seconds: float) -> void:
	for index in range(int(round(seconds / DT))):
		_step(arena, DT)


# The countdown's 3 - 2 - 1, up to the step that is GO.
func _run_countdown(arena: Arena) -> void:
	var guard := 0
	while arena._countdown > 0.0 and arena._phase == Arena.Phase.COUNTDOWN and guard < 1000:
		_step(arena, DT)
		guard += 1


# Step until the round is on (the host's drop is over), or - for a later round of
# Bathala's, which is on all along - until the drop is.
func _run_to_playing(arena: Arena, drop_only := false) -> void:
	var guard := 0
	while guard < 400:
		if drop_only:
			if not arena.drop_active():
				return
		elif arena._phase == Arena.Phase.PLAYING:
			return
		_step(arena, DT)
		guard += 1


func _check(condition: bool, label: String) -> void:
	if label == "":
		return
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
