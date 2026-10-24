extends SceneTree

# Validation: the Agawan Base balance pass.
#   * every live god pulses every 5s, throwing the players' expanding wave, and
#     thaws the frozen gods within 90 (Hanan's dawn reaches 120); a frozen god
#     never pulses; mortals are never touched
#   * a mortal's attack is one shockwave per 2.5s; the waves are 65 (mortal) and 18 (god)
#   * nobody can be frozen on their own base, by any source, and a refused freeze
#     pops SAFE
#   * a mortal or god that just thawed cannot be frozen for 1s, however it thawed
#   * the pulse timers, the immunities and the SAFE popups travel in the tick
# Run: godot --headless --path <project> -s res://tools/agawan_balance_check.gd

const DT := 0.125  # exact in binary, so eight steps are exactly one second
const FIELD := Vector2(640, 340)  # the common field, away from both bases

var _arena: BathalaArena
var _rules: GodMatch
var _problems := 0


func _initialize() -> void:
	_run()


# The drawn height of the character art alone: the used rect of the current frame
# (no transparent padding) times the sprite's on-screen scale.
func _art_height(sprite: AnimatedSprite2D) -> float:
	var frame := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	return frame.get_image().get_used_rect().size.y * absf(sprite.global_scale.y)


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
	_arena._phase = Arena.Phase.PLAYING
	_arena._trial_time = 90.0
	_arena.player.set_lock(false)

	# --- the new numbers ---------------------------------------------------------
	_check(is_equal_approx(_arena.ally_pulse_interval, 5.0) and is_equal_approx(_arena.ally_pulse_radius, 90.0),
		"every god pulses every 5s, 90 px wide")
	_check(is_equal_approx(_arena.dawn_radius, 120.0), "Hanan's dawn keeps its bigger 120 px ring")
	_check(is_equal_approx(_arena.attack_cooldown, 2.5), "the mortal's attack recharges in 2.5s")
	_check(is_equal_approx(_arena.shock_radius, 65.0), "the mortal's shockwave is 65 px")
	_check(is_equal_approx(_god(&"apolaki").shock_radius, 18.0), "a god's shockwave is 18 px")
	_check(is_equal_approx(_arena.thaw_immunity, 1.0), "a thaw buys 1s of immunity")

	# --- every god stands as tall as a mortal (visual only) -----------------------
	var mortal_height := _art_height(_arena.player.get_node("Sprite") as AnimatedSprite2D)
	for god_id in _arena.roster_ids():
		var tall := _art_height(_god(StringName(god_id)).icon)
		_check(absf(tall - mortal_height) <= mortal_height * 0.1,
			"%s's art stands %.0f px, a mortal's %.0f px (within 10%%)" % [god_id, tall, mortal_height])

	# --- the pulse: the nearest live ally thaws a frozen god ----------------------
	_fresh_round()
	var apolaki := _god(&"apolaki")
	var tala := _god(&"tala")
	var bathala := _god(&"bathala")
	var stamps := {}
	for stamp in _arena._pulse_timers:
		stamps[snappedf(stamp, 0.001)] = true
	_check(stamps.size() == _arena._gods.size(), "each god's first pulse is staggered by its index (%s)" % str(_arena._pulse_timers))
	apolaki.global_position = FIELD
	apolaki.freeze_for(30.0)
	tala.global_position = FIELD + Vector2(70, 0)
	_tick(24)
	_check(apolaki.is_frozen(), "before the pulse is due the frozen god is still frozen")
	var steps := 24
	while apolaki.is_frozen() and steps < 40:
		_tick(1)
		steps += 1
	_check(not apolaki.is_frozen(), "a frozen god thaws within 5s of a live ally pulsing 70 px away (%.2fs)" % (steps * DT))
	_check(tala.pulses_released > 0, "...and the ally's pulse is counted for the clients")
	_check(is_equal_approx(apolaki.immune_left, 1.0), "...and it comes out immune")

	# --- a god's pulse is the same expanding ring a mortal throws --------------------
	_fresh_round()
	tala = _god(&"tala")
	for god_node in _arena._gods:
		if god_node != tala:
			god_node.freeze_for(30.0)
	tala.global_position = FIELD
	var pulses_before := tala.pulses_released
	var pulse_waves_before := _arena.shocks_root.get_child_count()
	var pulse_steps := 0
	while tala.pulses_released == pulses_before and pulse_steps < 41:
		_tick(1)
		pulse_steps += 1
	_check(tala.pulses_released == pulses_before + 1, "a live god's pulse is counted for the clients")
	_check(_arena.shocks_root.get_child_count() == pulse_waves_before + 1, "the pulse throws one expanding ring")
	if _arena.shocks_root.get_child_count() > pulse_waves_before:
		var pulse_wave: MayariShockwave = _arena.shocks_root.get_child(_arena.shocks_root.get_child_count() - 1)
		_check(is_equal_approx(pulse_wave.max_scale * pulse_wave.base_radius, tala.pulse_radius),
			"the pulse ring grows to the god's pulse reach, not the mortal's 65 px")

	# The client draws the pulse from the host's count too.
	var pulse_tick: Dictionary = _arena.arena_tick_fields()
	_arena.arena_read_tick(pulse_tick)  # first tick after a rebuild: adopt, do not replay
	var client_pulses_before := _arena.shocks_root.get_child_count()
	var tala_state: Dictionary = pulse_tick["gods"][_arena._gods.find(tala)]
	tala_state["pulse"] = tala.pulses_released + 1
	_arena.arena_read_tick(pulse_tick)
	_check(_arena.shocks_root.get_child_count() == client_pulses_before + 1,
		"a client draws the god's pulse from the tick")

	_fresh_round()
	apolaki.global_position = FIELD
	apolaki.freeze_for(30.0)
	tala.global_position = FIELD + Vector2(70, 0)
	tala.freeze_for(30.0)
	_tick(64)
	_check(apolaki.is_frozen() and tala.is_frozen(), "a frozen ally never thaws a frozen ally")
	_check(is_equal_approx(_arena._pulse_timers[1], 5.0 * 2.0 / 3.0), "a frozen god's pulse timer waits (%.2f)" % _arena._pulse_timers[1])

	_fresh_round()
	_arena._frozen_mortals[2] = 30.0
	_arena._mortal_positions[2] = FIELD
	apolaki.global_position = FIELD + Vector2(20, 0)
	tala.global_position = FIELD + Vector2(0, 20)
	bathala.global_position = FIELD + Vector2(-20, 0)
	_tick(48)
	_check(_arena._is_frozen(2) and not _arena._is_frozen(1), "the pulse never thaws (or freezes) a mortal")
	_arena._frozen_mortals.clear()

	# --- Hanan reaches 120, the others 90 ------------------------------------------
	_arena._build_gods(BathalaArena.roster_for(4))
	_fresh_round()
	var hanan := _god(&"hanan")
	var mayari := _god(&"mayari")
	tala = _god(&"tala")
	_check(is_equal_approx(hanan.pulse_radius, 120.0) and is_equal_approx(tala.pulse_radius, 90.0) and is_equal_approx(_god(&"bathala").pulse_radius, 90.0),
		"Hanan's ring is 120, everyone else's 90")
	mayari.global_position = FIELD
	mayari.freeze_for(30.0)
	hanan.global_position = FIELD + Vector2(100, 0)
	_tick(41)
	_check(not mayari.is_frozen(), "Hanan's pulse reaches a frozen god 100 px away")
	_fresh_round()
	mayari.global_position = FIELD
	mayari.freeze_for(30.0)
	tala.global_position = FIELD + Vector2(100, 0)
	_tick(41)
	_check(mayari.is_frozen(), "Tala's pulse does not reach 100 px")
	tala.global_position = FIELD + Vector2(80, 0)
	_tick(41)
	_check(not mayari.is_frozen(), "...but reaches 80 px")

	# --- the mortal's attack: one shockwave per 2.5s -----------------------------------
	_fresh_round()
	_arena._shocks.clear()
	_arena._shock_cd = 0.0
	_arena.player.global_position = FIELD
	_arena._try_attack()
	_check(_arena._shocks.size() == 1 and is_equal_approx(_arena._shock_cd, 2.5), "an attack starts a 2.5s recharge")
	var wave: MayariShockwave = _arena._shocks[0]["wave"]
	_check(is_equal_approx(wave.max_scale * wave.base_radius, 65.0), "the drawn wave grows to 65 px (%.1f)" % (wave.max_scale * wave.base_radius))
	_arena._process(2.4)
	var before: int = _arena._shocks.size()
	_arena._try_attack()
	_check(_arena._shocks.size() == before and is_equal_approx(_arena._shock_cd, 0.1), "a second attack within 2.5s is refused (recharge left %.1fs)" % _arena._shock_cd)
	_arena._process(0.2)
	_arena._try_attack()
	_check(is_equal_approx(_arena._shock_cd, 2.5) and not _arena._shocks.is_empty(), "...and one after 2.5s works")
	_arena._refresh_hud(0.0)
	_check(_arena.status_label != null and _arena.status_label.text.contains("ATTACK 2.5s"), "the bottom band counts the recharge (%s)" % (_arena.status_label.text if _arena.status_label != null else "-"))
	for shock in _arena._shocks:
		if is_instance_valid(shock["wave"]):
			shock["wave"].queue_free()
	_arena._shocks.clear()

	# --- the waves' hit areas ------------------------------------------------------------
	_fresh_round()
	apolaki = _god(&"apolaki")
	tala = _god(&"tala")
	apolaki.global_position = FIELD + Vector2(70, 0)
	tala.global_position = FIELD + Vector2(0, 100)
	_arena._start_shock(FIELD, 1, _arena._spawn_shockwave(FIELD))
	for step in range(8):
		_arena._tick_shocks(0.25)
	_check(apolaki.is_frozen() and not tala.is_frozen(), "the mortal's wave freezes a god 70 px out and misses one 100 px out")
	_fresh_round()
	apolaki.global_position = FIELD
	tala.global_position = FIELD + Vector2(30, 0)
	_arena._resolve_god_shock(apolaki, 0)
	_check(tala.is_frozen(), "a god's wave freezes a god 30 px away")
	_fresh_round()
	apolaki.global_position = FIELD
	tala.global_position = FIELD + Vector2(45, 0)
	_arena._resolve_god_shock(apolaki, 0)
	_check(not tala.is_frozen(), "...but not one 45 px away")

	# --- a god's wave is drawn like a mortal's ---------------------------------------
	_fresh_round()
	apolaki.global_position = FIELD
	tala.global_position = FIELD + Vector2(15, 0)
	var waves_before := _arena.shocks_root.get_child_count()
	var released_before := apolaki.shocks_released
	_arena._tick_god_shocks(DT)
	var waves_after := _arena.shocks_root.get_child_count()
	_check(tala.is_frozen() and waves_after > waves_before,
		"a released god wave throws the same expanding ring a mortal's swing does")
	var god_wave: MayariShockwave = _arena.shocks_root.get_child(waves_after - 1)
	_check(is_equal_approx(god_wave.max_scale * god_wave.base_radius, apolaki.shock_radius + 18.0),
		"the god's ring grows to its freeze reach, not the mortal's 65 px")
	_check(apolaki.shocks_released == released_before + 1, "the release is counted for the clients")

	# The client mirrors the host's count into the same ring.
	var tick_state: Dictionary = _arena.arena_tick_fields()
	_arena.arena_read_tick(tick_state)
	var client_before := _arena.shocks_root.get_child_count()
	var god_state: Dictionary = tick_state["gods"][0]
	god_state["shock"] = apolaki.shocks_released + 1
	_arena.arena_read_tick(tick_state)
	_check(_arena.shocks_root.get_child_count() == client_before + 1,
		"a client draws the god's wave from the tick")

	# --- nobody is frozen on their own base ---------------------------------------------------
	_fresh_round()
	var safe_base: Vector2 = _arena._bathala_base + Vector2(10, 0)
	tala.global_position = safe_base
	_arena._freeze_god(1, 5.0, 1)
	_check(not tala.is_frozen(), "a god cannot be frozen directly inside Bathala's base")
	_check(_arena._safe_flash.has("g1"), "...and SAFE is claimed over it")
	_arena._refresh_safe()
	_check(_arena._safe_shown.has("g1"), "...and popped on this screen")
	_set_favor(0, 0, 0)
	_arena._start_shock(safe_base, 1, _arena._spawn_shockwave(safe_base))
	for step in range(8):
		_arena._tick_shocks(0.25)
	_check(not tala.is_frozen() and _mine() == 0, "a mortal's shockwave leaves a god in Bathala's base alone, and pays nothing")
	apolaki.global_position = safe_base + Vector2(-10, 0)
	_arena._resolve_god_shock(apolaki, 0)
	_check(not tala.is_frozen(), "a god's shockwave leaves it alone too")
	tala.global_position = _arena._my_base + Vector2(10, 0)
	_arena._freeze_god(1, 5.0, 1)
	_check(tala.is_frozen(), "...while a god on the mortals' base can be frozen")

	_fresh_round()
	_arena._mortal_positions[2] = _arena._my_base + Vector2(8, 0)
	_arena._freeze_mortal(2, FIELD)
	_check(not _arena._is_frozen(2) and _arena._safe_flash.has(2), "a mortal cannot be frozen directly inside its own base, and gets SAFE")
	mayari = _god(&"mayari")
	for god_node in [_god(&"apolaki"), mayari, _god(&"bathala")]:
		god_node.global_position = _arena._mortal_positions[2] + Vector2(20, 0)
		_arena._tag_mortals_from(god_node)
	_check(not _arena._is_frozen(2), "no god's touch (Apolaki's lunge, Mayari's reach, Bathala's) freezes it there")
	_arena._stars.append({"pos": _arena._mortal_positions[2], "vel": Vector2.ZERO, "left": 3.0})
	_arena._tick_stars(DT)
	_check(not _arena._is_frozen(2), "Tala's star does not freeze it there")
	_arena._mortal_positions[2] = _arena._my_base + Vector2(200, 0)
	_arena._freeze_mortal(2, FIELD)
	_check(_arena._is_frozen(2), "...but it freezes off the base")

	# --- one second of immunity after every thaw ---------------------------------------------------
	_fresh_round()
	_arena._mortal_positions[2] = FIELD
	_arena._frozen_mortals[2] = 0.05
	_arena._tick_frozen_mortals(0.1)
	_check(not _arena._is_frozen(2) and _arena._thaw_immune.has(2), "a mortal thawing on its own gets immunity")
	_arena._freeze_mortal(2, FIELD)
	_check(not _arena._is_frozen(2), "...and cannot be frozen straight away")
	_arena._tick_immunity(0.95)
	_arena._freeze_mortal(2, FIELD)
	_check(not _arena._is_frozen(2), "...still not at 0.95s")
	_arena._tick_immunity(0.1)
	_arena._freeze_mortal(2, FIELD)
	_check(_arena._is_frozen(2), "...but it can be at 1.05s")
	_arena._frozen_mortals.clear()
	_arena._thaw_immune.clear()
	_arena._safe_flash.clear()
	_arena._frozen_mortals[2] = 5.0
	_arena._start_shock(FIELD, 1, _arena._spawn_shockwave(FIELD))
	_arena._tick_shocks(0.5)
	_check(not _arena._is_frozen(2) and float(_arena._thaw_immune.get(2, 0.0)) > 0.9, "a teammate's swing thaws with the same immunity")

	for how in ["touch", "pulse", "shockwave", "own timer"]:
		_fresh_round()
		apolaki = _god(&"apolaki")
		tala = _god(&"tala")
		tala.global_position = FIELD + Vector2(300, 0)
		apolaki.global_position = FIELD
		apolaki.freeze_for(30.0)
		match how:
			"touch":
				tala.global_position = FIELD + Vector2(20, 0)
				_arena._thaw_gods_near(tala)
			"pulse":
				tala.global_position = FIELD + Vector2(70, 0)
				var waited := 0
				while apolaki.is_frozen() and waited < 41:
					_tick(1)
					waited += 1
			"shockwave":
				mayari = _god(&"mayari")
				mayari.global_position = FIELD + Vector2(10, 0)
				apolaki.unfreeze()
				apolaki.freeze_for(30.0)
				# a same-role god's shockwave thaws (Apolaki and Mayari both attack)
				_arena._resolve_god_shock(mayari, 2)
			"own timer":
				apolaki.freeze_left = 0.05
				apolaki.step(0.1, [])
		_check(not apolaki.is_frozen() and is_equal_approx(apolaki.immune_left, 1.0), "a god thawed by %s is immune (%.2fs)" % [how, apolaki.immune_left])
		_arena._freeze_god(0, 5.0, 1)
		_check(not apolaki.is_frozen(), "...and cannot be frozen straight away")
		apolaki.immune_left = 0.05
		apolaki.step(0.1, [])
		_arena._freeze_god(0, 5.0, 1)
		_check(apolaki.is_frozen(), "...but can be once the second is up")

	# --- the blink is read off the timer, so every screen flickers in step ----------------------------------
	var on := 0
	var off := 0
	apolaki.immune_left = 1.0
	for step in range(100):
		apolaki.immune_left = 1.0 - step * 0.01
		if apolaki.blinking():
			on += 1
		else:
			off += 1
	_check(on > 20 and off > 20, "a thawed god blinks through its second (%d on, %d off)" % [on, off])
	_arena._thaw_immune[1] = 0.95
	_arena._refresh_blinks()
	_check(_arena.player.blink_left > 0.9, "a thawed mortal's body is handed the timer to blink by")

	# --- the tick carries the pulses, the immunities and the SAFE popups ------------------------------------
	_fresh_round()
	_arena._thaw_immune[2] = 0.6
	_arena._flash_safe(2)
	_arena._flash_safe("g1")
	_god(&"tala").immune_left = 0.4
	var timers: Array = _arena._pulse_timers.duplicate()
	var state: Dictionary = _arena.arena_tick_fields()
	_arena._thaw_immune.clear()
	_arena._safe_flash.clear()
	_arena._pulse_timers.clear()
	_god(&"tala").immune_left = 0.0
	_arena.arena_read_tick(state)
	_check(is_equal_approx(float(_arena._thaw_immune.get(2, 0.0)), 0.6), "a mortal's immunity rides the tick")
	_check(is_equal_approx(_god(&"tala").immune_left, 0.4), "a god's immunity rides the tick")
	_check(_arena._safe_flash.has(2) and _arena._safe_flash.has("g1"), "the SAFE popups ride the tick")
	_check(_arena._pulse_timers == timers, "every god's pulse timer rides the tick")

	print("Agawan balance checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _god(id: StringName) -> AgawanGod:
	return _arena._god_by_id(id)


# A clean round with every god held still and parked off the field, so a test only
# meets the gods it puts somewhere. Tala's star stays off unless a test turns it on.
func _fresh_round() -> void:
	_arena.star_interval = 0.0
	_arena.arena_round_reset()
	_arena._invuln.clear()
	_arena._mortal_positions.clear()
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


func _mine() -> int:
	return _rules.local().favor


func _set_favor(mine: int, rival: int, rival_two: int) -> void:
	_rules.mortal(1).favor = mine
	_rules.mortal(2).favor = rival
	_rules.mortal(3).favor = rival_two


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
