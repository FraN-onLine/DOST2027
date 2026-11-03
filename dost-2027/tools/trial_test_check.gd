extends SceneTree

# Validation: THE PLAYGROUND'S SOLO TRIAL TEST, through the real TrialTest scene.
#   * it instantiates the chosen god's arena standalone - embedded off, so the
#     arena's own HUD/dialogue/results run - with the lobby's clock and Due step
#   * first_visit is false (one opening line) and final_trial is true (no hand-over
#     to a god that is not coming)
#   * the round plays: intro -> 3 - 2 - 1 -> PLAYING, with the mortal unlocked
#   * when the results are up it starts the return countdown and its hint says so;
#     the RETURN button and Esc are wired to walk back to the Playground
#   * a game with bots (Langit Lupa) fields them: solo, simmed rivals are replaced
#     by the arena's own bot bodies
# Run: godot --headless --path <project> -s res://tools/trial_test_check.gd

const DT := 0.125

var _problems := 0
var _checks := 0
var _network: Node = null


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	_network = root.get_node("Network")
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)
	await _frames(2)

	_network.set_run_settings({"trial_time": 120.0, "due_step": 1500})
	_check(float(_network.run_settings.trial_time) == 120.0, "the lobby's 120s clock is what the test should run")

	# --- SIDAPA: A STANDALONE PIKO TEST ------------------------------------------------
	var global := root.get_node("Global")
	global.test_god_id = &"sidapa"
	var trial: Node = load("res://scenes/prep/TrialTest.tscn").instantiate()
	view.add_child(trial)
	await _frames(4)
	_check(trial.arena != null and trial.arena is Arena, "the wrapper builds the chosen god's arena")
	var arena: Arena = trial.arena
	if arena == null:
		return _finish()
	_check(arena.god_id == &"sidapa", "it is Sidapa's arena (%s)" % arena.god_id)
	_check(not arena.embedded, "it runs standalone, with the arena's own HUD")
	_check(not arena.first_visit, "the god speaks one short line, not the full intro")
	_check(arena.final_trial, "no hand-over: the test is a trial of its own")
	_check(arena.simulate_rivals, "the game's solo stand-in rivals are there")
	_check(not arena.follow_camera, "the whole arena is in view")
	_check(is_equal_approx(arena.trial_time, 120.0), "...and the lobby's clock reached it (%ds)" % int(arena.trial_time))
	_check(arena.due_step == 1500, "...as did the God's Due step (%d)" % arena.due_step)
	_check(arena.dialogue_prefix == "test_sidapa", "it has its own dialogue token (%s)" % arena.dialogue_prefix)
	_check(trial.hint_label.text == "PIKO TEST - ESC RETURNS", "the overlay names the game (%s)" % trial.hint_label.text)
	_check(trial.PLAYGROUND_SCENE == "res://scenes/prep/Playground.tscn", "it knows where to return")
	_check(trial.return_button.visible and trial.return_button.text == "RETURN", "there is a RETURN button")
	var returns := false
	for connection in trial.return_button.pressed.get_connections():
		if (connection["callable"] as Callable).get_method() == "_finish":
			returns = true
	_check(returns, "...wired to walk back to the Playground")

	trial.set_process(false)
	arena.set_process(false)
	arena.player.set_physics_process(false)

	# --- THE ROUND RUNS ---------------------------------------------------------------
	_check(arena._phase == Arena.Phase.INTRO and arena.dialogue.is_active(), "it opens on the god's line")
	arena.dialogue.close_now()
	await _frames(1)
	_check(arena._phase == Arena.Phase.COUNTDOWN, "...which releases into the 3 - 2 - 1")
	arena._start_trial(false)
	_check(arena._phase == Arena.Phase.PLAYING and arena.rules.trial_active, "...and into a real round")
	_check(not arena.player.locked, "the mortal may walk")
	_check(is_equal_approx(arena._trial_time, 120.0), "the round runs on the lobby's clock (%ds)" % int(arena._trial_time))

	# --- RESULTS, THEN THE WAY HOME ----------------------------------------------------
	arena.rules.local().favor = 1200
	arena._end_trial()
	_check(arena._phase == Arena.Phase.RESULTS, "the trial ends into its results")
	_check(arena.dialogue.is_active(), "the god says its closing lines first")
	arena.dialogue.close_now()
	await _frames(1)
	_check(arena.hud.results_panel.visible, "...then the results panel is up")
	_check(trial._results_ready(), "the wrapper sees the results are ready")

	trial._process(0.1)
	_check(trial._return_left > 9.0, "the return countdown started (%.1fs)" % trial._return_left)
	_check(trial.hint_label.text.begins_with("RETURNING TO THE PLAYGROUND IN"), "the overlay counts down (%s)" % trial.hint_label.text)
	_check(arena.hud.results_hint.text.contains("ESC - PLAYGROUND"), "the results hint offers Esc (%s)" % arena.hud.results_hint.text)
	trial._process(9.0)
	_check(not trial._leaving and trial._return_left > 0.0, "...and it has not left early (%.1fs left)" % trial._return_left)
	trial.queue_free()
	await _frames(2)

	# --- A GAME WITH BOTS: LANGIT LUPA ---------------------------------------------------
	global.test_god_id = &"mapulon_ikapati"
	var langit: Node = load("res://scenes/prep/TrialTest.tscn").instantiate()
	view.add_child(langit)
	await _frames(4)
	var field: Arena = langit.arena
	_check(field != null and field.god_id == &"mapulon_ikapati", "Langit Lupa can be tested too")
	if field != null:
		_check(field.get("_bots") != null, "its arena keeps the bot roster")
		if field.get("_bots") != null:
			_check((field._bots as Dictionary).size() > 0, "its solo bots are on the field (%d)" % (field._bots as Dictionary).size())
		_check(not field.rules.simulate_rivals, "...and they gather FAVOR instead of the invisible rivals")
	langit.queue_free()
	await _frames(2)

	_network.set_run_settings(RunSettings.defaults().to_dict())
	_finish()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1


func _finish() -> void:
	print("trial test checks: %d check(s), %d problem(s)" % [_checks, _problems])
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)
