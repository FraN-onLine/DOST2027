extends SceneTree

# Validation: Mayari's attack (the `attack` action) throws a growing shockwave
# that shoves the OTHER mortals a little way away, on a 1.2s cooldown.
# Run: godot --headless --path <project> -s res://tools/shock_check.gd

const SHOCK_SCENE := "res://scenes/gods/mayari/Shockwave.tscn"

var _arena


# Stands in for the Network autoload so the host's hit messages can be watched.
class FakeNet:
	extends Node
	var hits: Array = []
	var players := {1: "ME", 2: "RIVAL"}
	var mortal_positions := {}
	func has_multiplayer_peer() -> bool:
		return true
	func send_arena_hit(peer_id: int, hit: Dictionary) -> void:
		hits.append({"peer": peer_id, "hit": hit})
	func send_arena_shock(_caster_id: int, _origin: Vector2) -> void:
		pass
	func publish_god_state(_state: Dictionary) -> void:
		pass
	func publish_arena_state(_state: Dictionary) -> void:
		pass
	func publish_arena_layout(_layout: Dictionary) -> void:
		pass
	func dialogue_finished_count(_id: String) -> int:
		return 0
	func report_dialogue_finished(_id: String) -> void:
		pass
	func release_dialogue(_id: String) -> void:
		pass


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	get_root().add_child(view)

	_arena = load("res://scenes/gods/mayari/MayariArena.tscn").instantiate()
	view.add_child(_arena)
	await _frames(3)

	var problems := 0
	if not ResourceLoader.exists(SHOCK_SCENE):
		printerr("shock_check: the shockwave scene is missing")
		problems += 1

	# Push the arena into PLAYING and pretend a rival stands just beside us.
	var guard := 0
	while _arena.dialogue.is_active() and guard < 40:
		_arena.dialogue.advance()
		guard += 1
	_arena._phase = Arena.Phase.PLAYING
	_arena.player.set_lock(false)
	_arena._invuln.clear()
	var fake := FakeNet.new()
	_arena.add_child(fake)
	_arena._net = fake
	_arena._networked = true
	_arena._authority = true
	_arena.rules.ensure_mortal(2, "RIVAL")
	var origin: Vector2 = _arena.player.global_position
	_arena._mortal_positions[2] = origin + Vector2(40.0, 0.0)

	# First attack: route an actual left click through the arena input callback.
	var attack_click := InputEventMouseButton.new()
	attack_click.button_index = MOUSE_BUTTON_LEFT
	attack_click.pressed = true
	_arena._input(attack_click)
	print("attack: waves=%d born_radius=%.1f cooldown=%.2f visuals=%d" % [
		_arena._shocks.size(), float(_arena._shocks[0]["radius"]) if _arena._shocks.size() > 0 else -1.0,
		_arena._shock_cd, _arena.shocks_root.get_child_count()])
	if _arena._shocks.size() != 1:
		printerr("shock_check: the attack did not start a wave")
		problems += 1
	if not is_equal_approx(_arena._shock_cd, _arena.shock_cooldown):
		printerr("shock_check: the attack did not start its cooldown")
		problems += 1
	if _arena.shocks_root.get_child_count() != 1:
		printerr("shock_check: the attack did not spawn a wave visual")
		problems += 1

	# A second attack while cooling is refused.
	_arena._try_shockwave()
	if _arena._shocks.size() != 1:
		printerr("shock_check: the attack fired again while cooling")
		problems += 1

	# The wave GROWS: the rival 40px away is only shoved once the ring reaches it.
	var grew := false
	var shock: Dictionary = _arena._shocks[0]
	var visual: MayariShockwave = shock["wave"]
	var before := visual.reach()
	var contact_distance: float = origin.distance_to(_arena._mortal_positions[2]) - _arena.player.radius
	var previous_radius := before
	var hit_radius := -1.0
	for i in range(60):
		previous_radius = float(shock["radius"])
		_arena._tick_shocks(0.02)
		if fake.hits.size() > 0:
			hit_radius = float(shock["radius"])
			break
		if _arena._shocks.is_empty():
			break
	if fake.hits.size() > 0:
		grew = true
	print("grow: hits=%d dir=%s | visual scale after=%s" % [
		fake.hits.size(),
		str(fake.hits[0]["hit"]["direction"]) if fake.hits.size() > 0 else "-",
		str(_arena.shocks_root.get_child(0).scale) if _arena.shocks_root.get_child_count() > 0 else "-"])
	if not is_equal_approx(before, visual.base_radius * visual.start_scale):
		problems += 1
		printerr("shock_check: the wave must be born tiny and grow from there")
	if not (previous_radius < contact_distance and hit_radius >= contact_distance):
		problems += 1
		printerr("shock_check: knockback must happen on the first animated frame of body contact")
	if not grew:
		printerr("shock_check: the growing wave never shoved the nearby rival")
		problems += 1
	elif (fake.hits[0]["hit"]["direction"] as Vector2).x <= 0.0:
		printerr("shock_check: the shove must push the rival AWAY from the caster")
		problems += 1
	if fake.hits.size() > 1:
		printerr("shock_check: the wave shoved the same rival more than once")
		problems += 1

	# The wave is gone once it is full.
	for i in range(60):
		_arena._tick_shocks(0.02)
	print("after full growth: waves=%d" % _arena._shocks.size())
	if not _arena._shocks.is_empty():
		printerr("shock_check: the wave overstayed its reach")
		problems += 1

	if problems == 0:
		print("shockwave: 0 problem(s)")
	else:
		printerr("shockwave: %d problem(s)" % problems)
	print("--- DONE ---")
	quit(1 if problems > 0 else 0)
