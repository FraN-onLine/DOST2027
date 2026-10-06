extends SceneTree

# Validation for the gods themselves: they are DATA, every arena runs, and the
# screens the player reads them from (the God's Due menu, the Almanac, the trial
# order) are all built out of that data.
#
# Run: godot --headless --path <project> -s res://tools/god_audit.gd

const ARENAS := [
	"res://scenes/gods/mayari/MayariArena.tscn",
	"res://scenes/gods/apolaki/ApolakiArena.tscn",
	"res://scenes/gods/tala/TalaArena.tscn",
	"res://scenes/gods/hanan/HananArena.tscn",
]


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _run() -> void:
	var problems := 0
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	get_root().add_child(view)

	# --- 1. every god, its favors and its words --------------------------------
	print("--- gods ---")
	for god in Gods.all():
		if god.favors.is_empty() and god.id != Gods.BATHALA:
			printerr("god_audit: %s has no favors" % god.id)
			problems += 1
		if god.icon == null:
			printerr("god_audit: %s has no icon" % god.id)
			problems += 1
		for favor in god.favors:
			if favor.id == &"" or favor.display_name == "":
				printerr("god_audit: a favor of %s is unnamed" % god.id)
				problems += 1
			if Gods.favor_by_id(favor.id) == null:
				printerr("god_audit: %s could not be looked up by id" % favor.id)
				problems += 1
			if favor.requires_god_id() != &"" and Gods.by_id(favor.requires_god_id()) == null:
				printerr("god_audit: %s needs an unknown god %s" % [favor.id, favor.requires_god_id()])
				problems += 1
		for key in god.transition_lines.keys():
			if str(key) == "*":
				continue
			if Gods.by_id(StringName(str(key))) == null:
				printerr("god_audit: %s has a transition to unknown god '%s'" % [god.id, key])
				problems += 1
		print("  %-9s %-9s favors=%d intro=%d end=%d transitions=%d" % [
			str(god.id), god.game_name, god.favors.size(),
			god.intro_lines.size(), god.trial_end_lines.size(), god.transition_lines.size()])

	# --- 2. every arena loads, runs and pays FAVOR ------------------------------
	print("--- arenas ---")
	for path in ARENAS:
		var packed: PackedScene = load(path)
		if packed == null:
			printerr("god_audit: %s will not load" % path)
			problems += 1
			continue
		var arena: Node = packed.instantiate()
		view.add_child(arena)
		await _frames(3)
		var guard := 0
		while arena.dialogue != null and arena.dialogue.is_active() and guard < 40:
			arena.dialogue.advance()
			guard += 1
		arena._phase = Arena.Phase.PLAYING
		arena.player.set_lock(false)
		arena._invuln.clear()
		await _frames(30)
		var favor_before: int = arena.rules.local().favor
		# Every arena answers the hooks the base promises.
		for hook in ["collect_units", "arena_rules_tick", "arena_round_reset",
				"arena_layout_fields", "arena_read_layout", "arena_tick_fields",
				"arena_read_tick", "separate_players"]:
			if not arena.has_method(hook):
				printerr("god_audit: %s is missing %s()" % [path, hook])
				problems += 1
		print("  %-46s god=%-8s playing after 30 frames (favor=%d)" % [
			path.get_file(), str(arena.god.id), favor_before])
		arena.queue_free()
		await _frames(2)

	# --- 3. the trial order the lobby sets ------------------------------------
	print("--- trial order ---")
	var network = get_root().get_node_or_null("Network")
	if network == null:
		printerr("god_audit: the Network autoload is missing")
		problems += 1
	else:
		network.set_run_settings({"trials": 3, "order_mode": "custom", "custom_order": ["tala", "apolaki", "mayari"]})
	var planned: Array = network.planned_trial_order() if network != null else []
	print("  custom order: %s" % str(planned))
	if planned.size() != 4 or StringName(str(planned[3])) != Gods.BATHALA:
		printerr("god_audit: the custom trial order did not close with Bathala")
		problems += 1
	if network != null:
		network.set_run_settings(RunSettings.defaults().to_dict())
		planned = network.planned_trial_order()
	if planned.size() < Gods.TRIALS_MIN + 1:
		printerr("god_audit: the random trial order is too short")
		problems += 1
	print("  random order: %s" % str(planned))
	if StringName(str(planned[planned.size() - 1])) != Gods.BATHALA:
		printerr("god_audit: the random trial order did not close with Bathala")
		problems += 1

	# --- 4. the two screens built out of the data ------------------------------
	print("--- screens ---")
	var almanac: Control = load("res://scenes/Almanac.tscn").instantiate()
	view.add_child(almanac)
	await _frames(3)
	var rows: Node = almanac.get_node("CenterContainer/VBoxContainer/ScrollContainer/FavorList")
	var total_favors := 0
	for god in Gods.all():
		total_favors += god.favors.size()
	# One header + one row per god with favors, so strictly more rows than favors.
	if rows.get_child_count() < total_favors:
		printerr("god_audit: the Almanac lists %d rows for %d favors" % [rows.get_child_count(), total_favors])
		problems += 1
	print("  Almanac: %d rows for %d favors" % [rows.get_child_count(), total_favors])
	almanac.queue_free()
	await _frames(2)

	var menu: Control = load("res://UI/GodsArena/gods_due_menu.tscn").instantiate()
	var match_rules := GodMatch.new()
	match_rules.setup(Gods.mayari(), "ME", [])
	view.add_child(match_rules)
	view.add_child(menu)
	await _frames(2)
	Arena.new().free()
	menu.open(Gods.mayari(), match_rules, 1)
	await _frames(2)
	var due_rows: Node = menu.get_node("SidePanel/Margin/VBox/Rows")
	var row_count := due_rows.get_child_count()
	var has_icon := false
	if row_count > 0 and due_rows.get_child(0) is PanelContainer:
		has_icon = _contains_texture_rect(due_rows.get_child(0))
	print("  God's Due menu: %d rows, icon on the first row: %s" % [row_count, str(has_icon)])
	if row_count <= 0:
		printerr("god_audit: the God's Due menu offered nothing")
		problems += 1
	if not has_icon:
		printerr("god_audit: a favor row has no icon beside its name")
		problems += 1

	if problems == 0:
		print("god audit: 0 problem(s)")
	else:
		printerr("god audit: %d problem(s)" % problems)
	print("--- DONE ---")
	quit(1 if problems > 0 else 0)


func _contains_texture_rect(node: Node) -> bool:
	if node is TextureRect:
		return true
	for child in node.get_children():
		if _contains_texture_rect(child):
			return true
	return false
