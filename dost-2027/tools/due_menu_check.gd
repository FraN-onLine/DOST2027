extends SceneTree

# Validation: God's Due menu refuses a pick with no voucher (UI/GodsArena/gods_due_menu.gd).
#   * due 0 and no free grant: _choose() emits nothing and keeps the menu open, locally
#     and as a multiplayer client (_remote)
#   * with a voucher, or a free grant, the pick goes through (the client emits to ask the host)
#   * a client's snapshot that carries a new favor announces it (GodMatch.favor_granted),
#     which is what the arena waits for before showing GRANTED
# Run: godot --headless --path <project> -s res://tools/due_menu_check.gd

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
	await _frames(2)

	var god := Gods.mayari()
	var rules := GodMatch.new()
	root.add_child(rules)
	rules.setup(god, "ME")
	var me := rules.local()

	for remote in [false, true]:
		var label := "client" if remote else "host"
		var menu: Control = load("res://UI/GodsArena/gods_due_menu.tscn").instantiate()
		view.add_child(menu)
		var emitted: Array = []
		menu.favor_chosen.connect(func(favor: GodFavor, left: int) -> void: emitted.append(favor))
		me.due = 0
		menu.open(god, rules, 0, remote)
		_check(menu._shown.size() > 0, "%s: the menu offers favors" % label)
		menu._choose(0)
		_check(emitted.is_empty(), "%s: due 0, no free grant - nothing is chosen" % label)
		_check(menu.is_open(), "%s: ...and the menu stays open" % label)
		me.due = 1
		menu.open(god, rules, 0, remote)
		menu._choose(0)
		_check(emitted.size() == 1, "%s: with a voucher the pick goes through" % label)
		me.due = 0
		menu.open(god, rules, 1, remote)
		menu._choose(0)
		_check(emitted.size() == 2, "%s: a free grant lets it through" % label)
		menu.queue_free()
		me.favors.clear()

	# A snapshot that brings a favor announces it - but only that favor.
	var client := GodMatch.new()
	root.add_child(client)
	client.setup(god, "ME")
	var granted: Array = []
	client.favor_granted.connect(func(id: int, favor: GodFavor) -> void: granted.append(favor.id))
	var favor: GodFavor = god.favors[0]
	var state: Dictionary = {client.local_id: {"name": "ME", "favors": [str(favor.id)]}}
	client.apply_snapshot(state)
	_check(granted == [favor.id], "a snapshot carrying a new favor announces it")
	client.apply_snapshot(state)
	_check(granted.size() == 1, "...once")

	print("due menu checks: %d problem(s)" % _problems)
	quit(1 if _problems > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		_problems += 1
		print("FAIL: ", what)
