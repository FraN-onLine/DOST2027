extends SceneTree

# Validation: the Game shell picks each trial's god arena and runs it embedded
# inside the right-hand play area. Also checks that only the lit goal pays.
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
	print("field=%s | shell panel=%s | match=%s" % [
		str(arena._field), str(_shell._arena_rect()), str(arena._field == _shell._arena_rect())])
	print("goals=%d clones=%d lit_index=%d lit_flags=%s" % [
		arena._zones.size(), arena._clones.size(), arena._active_goal_index,
		str(arena._zones.map(func(z): return z.favor_enabled))])
	var lit: MayariGoal = arena._zones[arena._active_goal_index]
	print("lit goal art: title='%s' favor='%s' fill=%s" % [lit.title.text, lit.favor_label.text, str(lit.fill.color)])
	print("mortal: bounds=%s start=%s name='%s'" % [
		str(arena.player.bounds), str(arena.player.global_position), arena.player.name_tag.text])
	print("shell HUD: name='%s' favor='%s' due='%s'" % [
		_shell.own_name_label.text, _shell.favor_label.text, _shell.due_label.text])

	# Push the trial to PLAYING, then let Mayari move her light.
	var guard := 0
	while arena.dialogue.is_active() and guard < 60:
		arena.dialogue.advance()
		guard += 1
	arena._countdown = 0.001
	await _frames(3)
	print("phase=%d (2=PLAYING)" % arena._phase)
	var before: int = arena._active_goal_index
	arena._goal_switch_timer = 0.0
	arena._tick_trial(0.016)
	print("Mayari's light moved: %d -> %d | lit_flags=%s" % [
		before, arena._active_goal_index, str(arena._zones.map(func(z): return z.favor_enabled))])

	# Standing in the lit corner must bank FAVOR; a dim corner must pay nothing.
	arena.disruption_interval = 9999.0
	arena._disruption_timer = 9999.0
	arena._invuln[arena._my_id] = 9999.0
	var lit_now: MayariGoal = arena._zones[arena._active_goal_index]
	arena.player.global_position = lit_now.global_position
	var lit_before: int = arena.rules.local().favor
	for i in range(120):
		arena._tick_trial(1.0 / 60.0)
	print("holding the lit %s for 2s -> +%d FAVOR" % [lit_now.zone_label, arena.rules.local().favor - lit_before])
	var dim: MayariGoal = null
	for zone in arena._zones:
		if not zone.favor_enabled:
			dim = zone
			break
	arena.player.global_position = dim.global_position
	var dim_before: int = arena.rules.local().favor
	for i in range(120):
		arena._tick_trial(1.0 / 60.0)
	print("holding the dim %s for 2s -> +%d FAVOR" % [dim.zone_label, arena.rules.local().favor - dim_before])
	print("--- DONE ---")
	quit()
