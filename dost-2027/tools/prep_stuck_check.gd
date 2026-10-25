extends SceneTree

# Validation: a rest (PAHINGA) never gets stuck.
#   * a late tick from the trial that just ended (phase RESULTS, its old scene
#     token) leaves a client's rest unlocked in Phase.INTRO, with no dialogue and
#     its own clock; Network drops it on arrival (is_current_scene)
#   * a tick tagged with the rest's own token still updates it
#   * a rest entered with the mortal stunned, locked, shoved or squashed lets it walk
#   * a client whose release never arrived still follows the host: at once when the
#     host's next trial is on the wire, or once the host's clock has read 0 for
#     client_follow_time (all within 3 s); the host closes release_grace after its
#     release even without the echo
# Run: godot --headless --path <project> -s res://tools/prep_stuck_check.gd

const DT := 0.25

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
	var network: Node = root.get_node("Network")
	var players_before: Dictionary = network.players.duplicate()
	network.players = {1: "HOST", 2: "CLIENT"}

	# --- a client's rest and a stale tick from the trial before ------------------------------
	var client := _rest(view)
	await _frames(2)
	client._networked = true
	client._authority = false
	client._my_id = 2
	client.rules.authority = false
	client.rules.ensure_mortal(2, "CLIENT")
	client.rules.set_local_id(2)
	network.scene_token = client.scene_token()
	_check(client.scene_token() == "prep_1:tala" and client.next_scene_token() == "trial_2:mayari",
		"the rest's token is its prefix and god, and it knows the next trial's (%s -> %s)" % [client.scene_token(), client.next_scene_token()])
	var clock: float = client._trial_time
	_check(not client.player.locked and client._phase == Arena.Phase.INTRO, "(the rest opens unlocked, in INTRO)")
	var stale := {"scene": "trial_1:tala", "phase": int(Arena.Phase.RESULTS), "trial_time": 0.0}
	_check(not network.is_current_scene(str(stale["scene"]), "arena"), "Network drops a tick tagged with the trial before")
	client._apply_arena_tick(stale)
	await _frames(2)
	_check(not client.player.locked and client._phase == Arena.Phase.INTRO and not client.dialogue.is_active(),
		"a stale RESULTS tick leaves the rest unlocked in INTRO with no dialogue (locked %s, phase %d)" % [str(client.player.locked), client._phase])
	_check(is_equal_approx(client._trial_time, clock), "...and keeps its own clock (%.1f)" % client._trial_time)
	client._apply_arena_tick({"phase": int(Arena.Phase.RESULTS), "scene": client.scene_token()})
	client._end_trial()
	client._enter_playing()
	_check(not client.player.locked and client._phase == Arena.Phase.INTRO and not client.dialogue.is_active(),
		"even its own token with a RESULTS phase, or a direct _end_trial, never ends a rest")
	client._apply_arena_tick({"scene": client.scene_token(), "trial_time": 12.5, "ready": [2], "present": [1, 2]})
	_check(is_equal_approx(client._trial_time, 12.5) and client.is_ready(2), "a tick with the rest's own token still updates it (%.1f, ready %s)" % [client._trial_time, str(client._ready_ids)])

	# --- the client follows a host that has left -----------------------------------------------
	var closed := [false]
	client.prep_closed.connect(func() -> void: closed[0] = true)
	network.is_current_scene("trial_2:mayari", "layout")  # the host's next trial on the wire
	_check(closed[0] and client.is_closed(), "a client whose release was lost follows the host's next trial at once")
	var late := _rest(view)
	await _frames(2)
	late._networked = true
	late._authority = false
	late._my_id = 2
	var late_closed := [false]
	late.prep_closed.connect(func() -> void: late_closed[0] = true)
	late._apply_arena_tick({"scene": late.scene_token(), "trial_time": 0.0})
	var waited := 0.0
	while not late_closed[0] and waited < 3.0:
		late._process(DT)
		waited += DT
	_check(late_closed[0] and waited <= 3.0, "...or once the host's clock has read 0 for %.0fs (closed after %.2fs)" % [late.client_follow_time, waited])

	# --- the host closes without its echo -----------------------------------------------------
	var host := _rest(view)
	await _frames(2)
	host._networked = true
	host._release_left = host.release_grace
	var host_closed := [false]
	host.prep_closed.connect(func() -> void: host_closed[0] = true)
	var spent := 0.0
	while not host_closed[0] and spent < 3.0:
		host._process(DT)
		spent += DT
	_check(host_closed[0] and spent <= host.release_grace + DT, "the host closes %.0fs after its release even with no echo (%.2fs)" % [host.release_grace, spent])

	# --- a rest entered with the mortal stuck still lets it walk --------------------------------
	var stuck := _rest(view)
	await _frames(2)
	var body: ArenaMortal = stuck.player
	body.set_lock(true)
	body.stun(3.0)
	body.hit(Vector2.RIGHT, 2.0, 400.0)
	body.force_movement(Vector2.LEFT, 2.0)
	body.drop_offset = Vector2(0, -200)
	body.scale = Vector2(1.0, 0.85)
	stuck.open_prep()
	_check(not body.locked and not body.is_stunned() and body.drop_offset == Vector2.ZERO and body.scale == Vector2.ONE and body._forced_move_time == 0.0,
		"a rest entered with the mortal locked, stunned, shoved, dropped and squashed lets it walk")

	network.players = players_before
	network.scene_token = ""
	print("prep stuck checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _rest(view: SubViewport) -> PrepArea:
	var rest: PrepArea = load("res://scenes/prep/PrepArea.tscn").instantiate()
	rest.god_id = &"tala"
	rest.next_god_id = &"mayari"
	rest.dialogue_prefix = "prep_1"
	view.add_child(rest)
	return rest


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
