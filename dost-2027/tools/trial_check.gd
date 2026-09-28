extends SceneTree

# Validation: the Game shell picks each trial's god arena and runs it embedded.
# The arena keeps the authored screen layout (the shell never resizes it), the
# left strip stays clear for the panels, only the lit favor zone pays, exactly
# two Mayaris walk their authored Line2D paths, and the round clock is the one
# shared by every arena (GodArena.trial_time = 1:30).
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
		arena.trial_time, arena.countdown_time, str(GodArena.FAVOR_COLOR)])
	if not is_equal_approx(arena.trial_time, 90.0):
		printerr("trial_check: trial_time is not 1:30")
	# The shell must not resize or re-centre an arena: the scene is authored in
	# screen space, so the running field IS the border the designer drew, and the
	# left GodArena.UI_STRIP_WIDTH pixels stay clear for the shared panels.
	var authored: Rect2 = arena.field_root.authored_rect()
	print("arena transform: pos=%s scale=%s (untouched scene values)" % [
		str(arena.position), str(arena.scale)])
	print("field=%s | authored border=%s | identical=%s" % [
		str(arena._field), str(authored), str(arena._field == authored)])
	print("left strip clear: %s (field starts at x=%.0f, strip is %.0f wide)" % [
		str(authored.position.x >= GodArena.UI_STRIP_WIDTH),
		authored.position.x, GodArena.UI_STRIP_WIDTH])
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
		lit.zone_label, str(lit.fill.color), str(GodArena.FAVOR_COLOR), str(drawn)])
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
	print("--- DONE ---")
	quit()
