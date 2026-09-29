extends SceneTree

# Validation: the Game shell picks each trial's god arena and runs it embedded.
# The arena keeps the authored screen layout (the shell never resizes it), the
# left strip stays clear for the panels, only the lit favor zone pays, exactly
# two Mayaris walk their authored Line2D paths, and the round clock is the one
# shared by every arena (Arena.trial_time = 1:30).
# Run: godot --headless --path <project> -s res://tools/trial_check.gd

var _shell


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _watchdog() -> void:
	await create_timer(45.0).timeout
	printerr("trial_check: timed out")
	quit()


# How far the point sits from the segment a-b.
func _segment_gap(point: Vector2, a: Vector2, b: Vector2) -> float:
	var length_squared := a.distance_squared_to(b)
	if length_squared <= 0.0:
		return point.distance_to(a)
	var ratio := clampf((point - a).dot(b - a) / length_squared, 0.0, 1.0)
	return point.distance_to(a.lerp(b, ratio))


# How far a clone has strayed from the path it was authored with (0 = on it).
func _off_path(clone: MayariClone) -> float:
	var knots := clone.path_knots()
	var gap := INF
	for index in range(1, knots.size()):
		gap = minf(gap, _segment_gap(clone.global_position, knots[index - 1], knots[index]))
	return gap


func _run() -> void:
	_watchdog()
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	get_root().add_child(view)

	_shell = load("res://scenes/Game.tscn").instantiate()
	view.add_child(_shell)
	await _frames(4)

	var order: Array = []
	for god in _shell.trial_order:
		order.append(str(god.id))
	print("shell trial order: %s" % str(order))
	var arena = _shell.arena
	if arena == null:
		print("NO ARENA LOADED")
		print("--- DONE ---")
		quit()
		return
	print("arena: %s (scene id=%s, embedded=%s)" % [arena.name, str(arena.god_id), str(arena.embedded)])
	# The round clock is the shared arena base: one number for every arena.
	print("shared arena base: trial_time=%.1fs countdown=%.1fs favor_colour=%s" % [
		arena.trial_time, arena.countdown_time, str(Arena.FAVOR_COLOR)])
	if not is_equal_approx(arena.trial_time, 90.0):
		printerr("trial_check: trial_time is not 1:30")
	# The shell must not resize or re-centre an arena: the scene is authored in
	# screen space, so the running field IS the border the designer drew, and the
	# left Arena.UI_STRIP_WIDTH pixels stay clear for the shared panels.
	var authored: Rect2 = arena.field_root.authored_rect()
	print("arena transform: pos=%s scale=%s (untouched scene values)" % [
		str(arena.position), str(arena.scale)])
	print("field=%s | authored border=%s | identical=%s" % [
		str(arena._field), str(authored), str(arena._field == authored)])
	print("left strip clear: %s (field starts at x=%.0f, strip is %.0f wide)" % [
		str(authored.position.x >= Arena.UI_STRIP_WIDTH),
		authored.position.x, Arena.UI_STRIP_WIDTH])
	# WYSIWYG: the favor zones and the spawn must still be where the scene puts them.
	var fresh: Node2D = load("res://scenes/gods/mayari/MayariArena.tscn").instantiate()
	var fresh_zones := fresh.get_node("Zones").get_children()
	var positions_match: bool = fresh_zones.size() == arena._zones.size()
	for index in range(arena._zones.size()):
		if not positions_match:
			break
		if arena._zones[index].position != fresh_zones[index].position:
			positions_match = false
	var spawn_matches: bool = arena._start_position == fresh.get_node("Player").position
	fresh.free()
	print("scene == played layout: zones=%s spawn=%s (player shown at %s)" % [
		str(positions_match), str(spawn_matches), str(arena.player.position)])
	print("zones=%d clones=%d lit_index=%d lit_flags=%s" % [
		arena._zones.size(), arena._clones.size(), arena._active_goal_index,
		str(arena._zones.map(func(z): return z.favor_enabled))])
	# A favor zone draws NOTHING unless it is the lit one - then it burns yellow.
	var drawn: Array = []
	for zone in arena._zones:
		drawn.append(zone.fill.visible)
	var lit: MayariGoal = arena._zones[arena._active_goal_index]
	print("zone art: lit='%s' fill=%s (favor colour %s) | fill.visible per zone=%s" % [
		lit.zone_label, str(lit.fill.color), str(Arena.FAVOR_COLOR), str(drawn)])
	if drawn.count(true) != 1:
		printerr("trial_check: %d zones are drawn - only the favor zone may show" % drawn.count(true))
	# Exactly two Mayaris, each one walking its own authored Line2D path.
	print("clones: %d" % arena._clones.size())
	if arena._clones.size() != 2:
		printerr("trial_check: the arena wants exactly 2 Mayaris")
	for index in range(arena._clones.size()):
		var clone: MayariClone = arena._clones[index]
		var knots := clone.path_knots()
		print("   %s speed=%.0f path_points=%d length=%.0f start=%s end=%s" % [
			clone.name, clone.speed, knots.size(), clone.path_length(),
			str(knots[0]) if knots.size() > 0 else "-",
			str(knots[knots.size() - 1]) if knots.size() > 0 else "-"])
	print("mortal: bounds=%s start=%s name='%s'" % [
		str(arena.player.bounds), str(arena.player.global_position), arena.player.name_tag.text])
	print("shell HUD: name='%s' favor='%s' due='%s' clock='%s'" % [
		_shell.own_name_label.text, _shell.favor_label.text, _shell.due_label.text,
		_shell.timer_label.text])

	# The shell's own panel is a vertical stack - NAME, then FAVOR next to DUE,
	# then one row per favor bar - and the rival panel authored in Game.tscn
	# previews the layout while you are alone.
	var rows := [
		_shell.own_name_label.global_position.y,
		_shell.favor_label.global_position.y,
		_shell.e_bar.global_position.y,
		_shell.q_bar.global_position.y,
	]
	print("shell panel rows (y): name=%.0f favor/due=%.0f E=%.0f Q=%.0f | E bar=%.0fx%.0f" % [
		rows[0], rows[1], rows[2], rows[3], _shell.e_bar.size.x, _shell.e_bar.size.y])
	for index in range(1, rows.size()):
		if rows[index] <= rows[index - 1]:
			printerr("trial_check: the shell panel must stack NAME / FAVOR+DUE / E / Q - row %d is not below row %d" % [
				index, index - 1])
	print("shell rivals: authored '%s' visible=%s while alone | E/Q rows share a line: %s" % [
		_shell.opponent_placeholder.name, str(_shell.opponent_placeholder.visible),
		str(is_equal_approx(rows[2], rows[3]))])
	if not _shell.opponent_placeholder.visible:
		printerr("trial_check: the authored rival panel should stand in while you are alone")
	# A real rival takes the authored panel's slot. The Network autoload is
	# reached through the tree: a -s script cannot name an autoload at compile
	# time (its own script is compiled before the autoloads are registered).
	var network = get_root().get_node_or_null("Network")
	if network == null:
		printerr("trial_check: the Network autoload is missing - cannot hand the slot to a rival")
	else:
		network.players[2] = "RIVAL"
		_shell._build_other_player_panels()
		print("shell rivals: %d live panel(s)=%s named '%s' | authored panel visible=%s (a rival joined)" % [
			_shell.other_player_panels.size(), str(_shell.other_player_panels.keys()),
			str(_shell.other_player_panels[2].name_label.text) if _shell.other_player_panels.has(2) else "-",
			str(_shell.opponent_placeholder.visible)])
		if _shell.opponent_placeholder.visible or _shell.other_player_panels.size() != 1:
			printerr("trial_check: a real rival must replace the authored preview panel")
		network.players.erase(2)
		_shell._build_other_player_panels()

		# A rename is live data: the lobby's UPDATE NAME can land at any time, so
		# the tag over the mortal, the shell's own panel, the match entry behind
		# the results and the rival column all have to follow it.
		network.players[2] = "RIVAL"
		network.players[1] = "MORTAL OLD"
		network.my_name = "MORTAL OLD"
		_shell._build_other_player_panels()
		network.player_name_changed.emit(1, "MORTAL NEW")
		network.player_name_changed.emit(2, "RIVAL RENAMED")
		var rival_panel_name := "-"
		if _shell.other_player_panels.has(2):
			rival_panel_name = str(_shell.other_player_panels[2].name_label.text)
		print("rename: mortal tag '%s' | shell name '%s' | rival panel '%s' | match entry '%s'" % [
			arena.player.name_tag.text, _shell.own_name_label.text,
			rival_panel_name, arena.rules.local().display_name])
		if arena.player.name_tag.text != "MORTAL NEW" or _shell.own_name_label.text != "MORTAL NEW":
			printerr("trial_check: a rename must repaint the name over the mortal and on the shell")
		if arena.rules.local().display_name != "MORTAL NEW":
			printerr("trial_check: the match entry must carry the new name for the results")
		if rival_panel_name != "RIVAL RENAMED":
			printerr("trial_check: a renamed rival must repaint its panel")
		network.players.erase(2)
		network.players.erase(1)
		network.my_name = ""
		_shell._build_other_player_panels()

	# Push the trial to PLAYING, then let Mayari move her light.
	var guard := 0
	while arena.dialogue.is_active() and guard < 60:
		arena.dialogue.advance()
		guard += 1
	arena._countdown = 0.001
	await _frames(3)
	print("phase=%d (2=PLAYING) | shell clock='%s'" % [arena._phase, _shell.timer_label.text])
	var before: int = arena._active_goal_index
	arena._goal_switch_timer = 0.0
	arena._tick_trial(0.016)
	print("Mayari's light moved: %d -> %d | lit_flags=%s" % [
		before, arena._active_goal_index, str(arena._zones.map(func(z): return z.favor_enabled))])

	# A Mayari must walk along the path drawn on her and never leave it, and the
	# line you drew must stay exactly where you drew it.
	var watched: MayariClone = arena._clones[0]
	var start := watched.global_position
	var line_start := watched.path.global_position
	for i in range(40):
		await process_frame
	var walked := watched.global_position
	var line_drift := line_start.distance_to(watched.path.global_position)
	print("clone walk: %s travelled %.1f px of %.0f px path | off_path=%.2f px | drawn line moved %.2f px" % [
		watched.name, start.distance_to(walked), watched.path_length(), _off_path(watched), line_drift])
	if start.distance_to(walked) <= 1.0:
		printerr("trial_check: %s never moved - does its Path Line2D have points?" % watched.name)
	if _off_path(watched) > 1.0:
		printerr("trial_check: %s left its authored path" % watched.name)
	if line_drift > 0.5:
		printerr("trial_check: the path drawn on %s travelled with it" % watched.name)

	# Standing in the lit zone must bank FAVOR; an unlit zone must pay nothing.
	arena._invuln[arena._my_id] = 9999.0
	var lit_now: MayariGoal = arena._zones[arena._active_goal_index]
	arena.player.global_position = lit_now.global_position
	var lit_before: int = arena.rules.local().favor
	for i in range(120):
		arena._tick_trial(1.0 / 60.0)
	print("holding the lit %s for 2s -> +%d FAVOR" % [
		lit_now.zone_label, arena.rules.local().favor - lit_before])
	var dim: MayariGoal = null
	for zone in arena._zones:
		if not zone.favor_enabled:
			dim = zone
			break
	arena.player.global_position = dim.global_position
	var dim_before: int = arena.rules.local().favor
	for i in range(120):
		arena._tick_trial(1.0 / 60.0)
	print("holding the unlit %s for 2s -> +%d FAVOR" % [
		dim.zone_label, arena.rules.local().favor - dim_before])

	# Mayari's E (Half Vision) blinds the OTHER mortals - never the one who cast
	# it. The caster has to keep seeing the field to play, and a screen can only
	# be darkened on the machine that draws it, so the effect is per screen.
	var half: GodFavor = arena.god.get_favor(&"half_vision")
	arena.rules.bestow_favor(half, arena._my_id)
	arena._use_skill(GodFavor.Slot.E)
	await _frames(2)
	print("Half Vision cast by us: darkness=%.2fs mask_visible=%s (the caster keeps both eyes)" % [
		arena._blind_time, str(arena.vision_mask.visible)])
	if arena._blind_time > 0.0 or arena.vision_mask.visible:
		printerr("trial_check: Half Vision blinded the mortal that cast it")
	# The very same favor cast by somebody else closes the mask in on us.
	arena._apply_skill_effect(half, 2)
	await _frames(2)
	print("Half Vision cast by a rival: darkness=%.2fs radius=%.2f mask_visible=%s" % [
		arena._blind_time, arena._blind_radius, str(arena.vision_mask.visible)])
	if arena._blind_time <= 0.0 or not arena.vision_mask.visible:
		printerr("trial_check: Half Vision must blind the other mortals")
	if not is_equal_approx(arena._blind_radius, half.param("vision_radius", 0.16)):
		printerr("trial_check: the mask must use the favor's vision_radius")
	arena._blind_time = 0.0
	await _frames(2)

	# The shared base: Mayari's scene inherits scenes/gods/common/Arena.tscn, so
	# the panels, the mortal, the ghosts, the popup layer, the vision mask and the
	# arena UI layer are authored once and only the god's own nodes are added.
	print("arena nodes: %s" % str(arena.get_children().map(func(c): return c.name)))
	if not (arena is Arena):
		printerr("trial_check: MayariArena.gd must extend the shared Arena base")
	if not (arena.field_root is ArenaField):
		printerr("trial_check: ArenaField must be the shared field script")
	for shared in ["Background", "ArenaField", "Ghosts", "Popups", "Player", "VisionLayer", "UILayer"]:
		if arena.get_node_or_null(shared) == null:
			printerr("trial_check: the shared base node '%s' is missing" % shared)

	# A clone touch: the mortal is shoved away from the clone, and the FAVOR it
	# costs shows as a popup over its own head (light red - a loss).
	arena._invuln.clear()
	arena._gain_pending.clear()
	var hit_clone: MayariClone = arena._clones[0]
	arena.player.global_position = hit_clone.global_position + Vector2(2, 0)
	var favor_before_hit: int = arena.rules.local().favor
	arena._check_clones()
	var shove: Vector2 = arena.player._knockback
	var hit_text := _popup_text(arena)
	print("clone hit: knockback %s (stun %.2f) | FAVOR %d -> %d | popup '%s'" % [
		str(shove), arena.player._stun, favor_before_hit, arena.rules.local().favor, hit_text])
	if shove.length() <= 0.0:
		printerr("trial_check: a Mayari clone touch did not knock the mortal back")
	if not arena._invuln.has(arena._my_id):
		printerr("trial_check: a hit must leave the mortal its mercy seconds")
	if not hit_text.begins_with("-"):
		printerr("trial_check: a FAVOR loss must pop over the mortal as '-N FAVOR'")
	# The shove has to really move the mortal, not just set a velocity.
	var shoved_from: Vector2 = arena.player.global_position
	for i in range(30):
		await process_frame
	print("knockback moved the mortal %.1f px (bounds %s)" % [
		shoved_from.distance_to(arena.player.global_position), str(arena.player.bounds)])

	# A gain pops in the light yellow: big changes at once, small ones gathered
	# over the popup_flush window (a lit zone pays many times a second, so one
	# popup per credit would be unreadable).
	for child in arena.popups_root.get_children():
		child.queue_free()
	await _frames(2)
	arena._gain_timer = 0.0
	arena.bank_favor(arena.popup_big_delta + 5, "trial_check")
	var big_text := _popup_text(arena)
	arena._gain_timer = 0.0
	arena.bank_favor(3, "trial_check")
	arena._flush_favor_popups(1.0)
	var gathered_text := _popup_text(arena)
	print("gain popups: immediate '%s' | gathered '%s' | light yellow=%s" % [
		big_text, gathered_text, str(Arena.POPUP_GAIN_COLOR)])
	if not big_text.begins_with("+"):
		printerr("trial_check: a big gain must pop at once as '+N FAVOR'")
	if gathered_text == big_text:
		printerr("trial_check: a small gain must be gathered and popped on the flush")
	print("--- DONE ---")
	quit()


# The text of the newest FAVOR popup over a mortal ('' when there is none).
func _popup_text(arena) -> String:
	var popups: Array = arena.popups_root.get_children()
	if popups.is_empty():
		return ""
	var label: Label = popups[popups.size() - 1].get_node_or_null("Box/Label")
	return label.text if label != null else ""
