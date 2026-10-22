extends SceneTree

# Validation: the effect timers in the HUD's top-right column (god_hud.gd, effect_row.tscn,
# Arena.local_effects).
#   * one of our own lasting skills (GodMatch.Mortal.durations) shows as a row - icon, name,
#     seconds left, a bar that shrinks - and is gone the moment it ends
#   * a Pamana's opening window shows too; its charges stay on the badge (no timer)
#   * what has been put on us shows in EMBER, after the buffs: Ligaw na Damo and Tagtuyot (and
#     they travel in the host's snapshot, so a client sees them), Half Vision's blindness, Sun
#     Patches, doubled losses (and they travel in the world tick), Tala's pull, a stun
#   * Langit Lupa adds ALIS, a closed Langit and the tag-back buffer
#   * the note (Kabiyak's other half, Kamalig's granary) is never covered: the effects stack
#     under it, and so does Langit Lupa's TAYA list
# Run: godot --headless --path <project> -s res://tools/effects_check.gd

var _problems := 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _keys(hud: Control) -> Array:
	var keys: Array = []
	for row in hud.effects_box.get_children():
		keys.append((row as EffectRow).key)
	return keys


func _row(hud: Control, key: StringName) -> EffectRow:
	return hud._effect_rows.get(key)


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)
	await _frames(2)
	var network: Node = root.get_node("Network")
	var order: Array[StringName] = [Gods.MAYARI, Gods.MAPULON_IKAPATI, Gods.BATHALA]
	network.rpc_sync_trial_order(order)
	var game: Control = load("res://scenes/Game.tscn").instantiate()
	view.add_child(game)
	await _frames(4)
	var arena: Arena = game.arena
	var hud: Control = arena.hud
	var rules: GodMatch = arena.rules
	var me := rules.local()
	if arena.dialogue.is_active():
		arena.dialogue.close_now()
	_check(hud.effect_source.is_valid() and arena.local_effects().is_empty() and hud.effects_box.get_child_count() == 0,
		"the HUD asks the arena what is running, and a quiet mortal has no rows")

	# --- a lasting skill of ours ---------------------------------------------------------------------
	var half_vision := Gods.favor_by_id(&"half_vision")
	rules.bestow_favor(half_vision)
	rules.use_skill(GodFavor.Slot.E)
	hud._sync_effects()
	var row := _row(hud, &"skill_half_vision")
	_check(row != null and row.name_label.text == arena.effect_name(half_vision) and not row.harmful,
		"a skill that lasts shows as a row, in its own colours (%s)" % (row.name_label.text if row != null else "none"))
	_check(row != null and row.icon.texture != null and row.seconds_label.text == "%.1fs" % half_vision.duration and is_equal_approx(row.bar.value, 1.0),
		"...icon, seconds left (%s) and a full bar" % (row.seconds_label.text if row != null else ""))
	me.durations[half_vision.id] = half_vision.duration * 0.5
	hud._sync_effects()
	_check(row.seconds_label.text == "%.1fs" % (half_vision.duration * 0.5) and is_equal_approx(row.bar.value, 0.5), "...the bar shrinks with the seconds (%.2f)" % row.bar.value)
	me.durations[half_vision.id] = 0.0
	hud._sync_effects()
	_check(not hud._effect_rows.has(&"skill_half_vision") and hud.effects_box.get_child_count() == 0, "...and the row is gone when the effect ends")

	# --- a Pamana's window ------------------------------------------------------------------------------
	var windowed: Pamana = null
	for item in Pamanas.all():
		if item.timing == Pamana.Timing.FIRST_WINDOW:
			windowed = item
	_check(windowed != null, "there is a Pamana with an opening window to show")
	me.pamana_active = windowed.id
	me.pamana_window = windowed.window
	hud._sync_effects()
	var window_row := _row(hud, StringName("pamana_%s" % windowed.id))
	_check(window_row != null and not window_row.harmful and window_row.name_label.text == windowed.display_name.to_upper(),
		"a Pamana's opening window is a row (%s)" % (window_row.name_label.text if window_row != null else "none"))
	me.pamana_window = 0.0
	me.pamana_active = Pamanas.AGIMAT
	me.agimat_charges = 2
	hud._sync_effects()
	_check(hud.effects_box.get_child_count() == 0, "...an Agimat's charges are no timer: nothing on the stack")
	me.pamana_active = &""

	# --- what has been put on us ----------------------------------------------------------------------------
	rules.trial_active = true
	me.weeds_time = 6.0
	me.weeds_caster = 2
	me.drought_time = 4.0
	arena._blind_time = 1.0
	arena._sun_patches[arena._my_id] = [3.0, 1.0]
	arena._double_loss[arena._my_id] = 4.0
	arena._movement_override_caster = 5
	arena._movement_override_time = 2.0
	arena.player.hit(Vector2.LEFT, 1.4, 400.0)
	me.durations[half_vision.id] = 1.2  # a buff of our own beside them, to see the order
	hud._sync_effects()
	var wanted := [&"weeds", &"drought", &"blind", &"sun_patches", &"double_loss", &"pulled", &"stun"]
	var all_there := true
	var all_ember := true
	for key in wanted:
		var debuff := _row(hud, key)
		all_there = all_there and debuff != null
		all_ember = all_ember and debuff != null and debuff.harmful and debuff.name_label.get_theme_color("font_color") == UITokens.EMBER \
			and debuff.bar.get_theme_stylebox("fill").bg_color == UITokens.EMBER
	_check(all_there, "weeds, drought, blindness, sun patches, doubled losses, the pull and a stun all show (%s)" % str(_keys(hud)))
	_check(all_ember, "...every one of them in EMBER, name and bar")
	var keys := _keys(hud)
	_check(keys[0] == &"skill_half_vision" and keys.slice(1).all(func(key: StringName) -> bool: return wanted.has(key)),
		"the buff comes first, the debuffs after it (%s)" % str(keys))
	_check(_row(hud, &"sun_patches").name_label.text == "SUN PATCHES" and _row(hud, &"sun_patches").seconds_label.text == "3.0s", "two sun patches are one row, on the longer clock (%s)" % _row(hud, &"sun_patches").seconds_label.text)
	_check(_row(hud, &"pulled").name_label.text == arena.effect_name(Gods.favor_by_id(&"let_us_light_your_way")), "Tala's pull is named for her favor")
	arena._movement_override_caster = arena._my_id
	hud._sync_effects()
	_check(not hud._effect_rows.has(&"pulled"), "...and it is not an effect on the mortal who cast it")
	rules.trial_active = false
	hud._sync_effects()
	_check(not hud._effect_rows.has(&"weeds") and not hud._effect_rows.has(&"drought"), "the Harvest Pair's clocks only run in a trial: no rows between trials")
	rules.trial_active = true

	# --- the note is never covered ------------------------------------------------------------------------------
	me.favors.append(Gods.favor_by_id(&"kabiyak"))
	me.kabiyak = 2
	me.granary = 120
	await _frames(3)
	hud._process(0.016)
	await _frames(2)
	var note: Label = hud.favor_note
	_check(note.visible and note.text.contains("KABIYAK") and note.text.contains("KAMALIG"), "the note is up with both its lines")
	var stack: Rect2 = hud.effects_box.get_global_rect()
	_check(stack.position.y >= note.get_global_rect().end.y - 0.5 and stack.size.y > 0.0,
		"the effects stack under the note, not over it (note ends %.0f, stack starts %.0f)" % [note.get_global_rect().end.y, stack.position.y])
	_check(stack.end.x <= 1152.0 and stack.position.x >= 700.0, "...in the top right corner (%s)" % str(stack))

	# --- a client sees the rivals' effects too ---------------------------------------------------------------------
	var host := GodMatch.new()
	view.add_child(host)
	host.setup_peers(Gods.mayari(), {1: "HOST", 2: "CLIENT"}, 1)
	var client := GodMatch.new()
	view.add_child(client)
	client.setup_peers(Gods.mayari(), {1: "HOST", 2: "CLIENT"}, 2)
	host.cast_tagtuyot(1, Gods.favor_by_id(&"tagtuyot"))  # the target is the other mortal
	host.mortal(2).weeds_time = 6.0
	host.mortal(2).weeds_caster = 1
	client.apply_snapshot(host.snapshot())
	_check(client.mortal(2).drought_time > 0.0 or client.mortal(1).drought_time > 0.0, "the host's snapshot carries the drought")
	_check(is_equal_approx(client.mortal(2).weeds_time, 6.0) and client.mortal(2).weeds_caster == 1, "...and the weeds, with who sent them")
	host.queue_free()
	client.queue_free()
	var tick_state := {"phase": int(Arena.Phase.PLAYING), "double_loss": {arena._my_id: 3.0}}
	arena._double_loss.clear()
	arena._authority = false
	arena._double_loss_seen.clear()
	arena._apply_arena_tick(tick_state)
	_check(float(arena._double_loss_seen.get(arena._my_id, 0.0)) == 3.0 and not arena._double_loss.has(arena._my_id),
		"a client reads doubled losses off the world tick, into its own copy (the rule's stays the host's)")
	hud._sync_effects()
	_check(hud._effect_rows.has(&"double_loss"), "...and shows them")
	arena._authority = true

	# --- Langit Lupa --------------------------------------------------------------------------------------------------
	me.favors.clear()
	game._on_trial_complete()
	await _frames(4)
	game.arena._ready_up()
	await _frames(4)
	var langit := game.arena as LangitLupaArena
	_check(langit != null and langit.god_id == &"mapulon_ikapati", "the run reaches Langit Lupa")
	if langit == null:
		return _finish(game)
	if langit.dialogue.is_active():
		langit.dialogue.close_now()
	langit._phase = Arena.Phase.PLAYING
	langit._swap[langit._my_id] = 1.0
	langit._closed[langit._my_id] = 0
	langit._season_timer = 7.5
	langit._taya = langit._my_id
	langit._tagback = 0.5
	var langit_hud: Control = langit.hud
	langit_hud._sync_effects()
	var alis := _row(langit_hud, &"alis")
	var closed := _row(langit_hud, &"closed")
	var tagback := _row(langit_hud, &"tagback")
	_check(alis != null and closed != null and tagback != null and alis.harmful and closed.harmful and tagback.harmful,
		"Langit Lupa adds ALIS, a closed Langit and the tag-back buffer, in EMBER (%s)" % str(_keys(langit_hud)))
	_check(closed != null and closed.seconds_label.text == "7.5s" and is_equal_approx(closed.bar.value, 7.5 / langit.season_interval),
		"...the closed Langit counts down to the season turning (%s)" % (closed.seconds_label.text if closed != null else ""))
	await _frames(3)
	langit_hud._process(0.016)
	await _frames(2)
	_check(langit.get_node_or_null("LangitHud/TayaList") == null and langit_hud.top_right.get_child_count() > 0,
		"Langit's TAYA list is no longer in the top-right column (it moved into the player panels)")
	_finish(game)


func _finish(game: Control) -> void:
	game.queue_free()
	print("effect timer checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
