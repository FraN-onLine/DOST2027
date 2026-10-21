extends SceneTree

# Validation for the opening cutscene (scenes/OpeningCutscene.tscn + the Cutscene
# data in resources/opening_cutscene.tres):
#   * the data parses and every speaker and action in it is known
#   * played solo it ends on its own (the fade) and reports finished
#   * a skip (the host's) ends it early; a client cannot skip
#   * RunSettings.opening_cutscene survives to_dict / from_dict and a bad value is put back
# Run: godot --headless --path <project> -s res://tools/opening_check.gd

var _problems := 0
var _finished := false


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if not ok:
		printerr("opening_check: %s" % what)
		_problems += 1


func _run() -> void:
	var scene: PackedScene = load("res://scenes/OpeningCutscene.tscn")
	var data: Cutscene = load("res://resources/opening_cutscene.tres")
	var issues := data.problems(scene.instantiate().ACTIONS)
	_check(issues.is_empty(), "data: %s" % str(issues))
	print("steps: %d" % data.steps.size())

	var settings := RunSettings.from_dict({"opening_cutscene": "loud"})
	settings.validate()
	_check(settings.opening_cutscene == RunSettings.OPENING_FULL, "a bad OPENING is put back to full")
	settings.opening_cutscene = RunSettings.OPENING_SKIP
	_check(RunSettings.from_dict(settings.to_dict()).opening_cutscene == RunSettings.OPENING_SKIP, "OPENING survives to_dict / from_dict")

	# A full solo run: advance every line until it ends by itself.
	var cutscene: Node = scene.instantiate()
	cutscene.finished.connect(func() -> void: _finished = true)
	root.add_child(cutscene)
	await process_frame
	cutscene.play()
	var frames := 0
	while not _finished and frames < 6000:
		await process_frame
		frames += 1
		if frames % 20 == 0 and cutscene.dialogue.is_active():
			cutscene.dialogue.advance()
	_check(_finished, "the cutscene never finished")
	print("played through in %d frames" % frames)
	cutscene.queue_free()
	await process_frame

	# Skipped from the first frames.
	_finished = false
	cutscene = scene.instantiate()
	cutscene.finished.connect(func() -> void: _finished = true)
	root.add_child(cutscene)
	await process_frame
	cutscene.play()
	for i in range(30):
		await process_frame
	cutscene.skip()
	frames = 0
	while not _finished and frames < 200:
		await process_frame
		frames += 1
	_check(_finished and cutscene.skipped, "a skip did not end the cutscene")
	print("skipped, finished %d frames later" % frames)
	cutscene.queue_free()

	# A client cannot skip.
	cutscene = scene.instantiate()
	cutscene.can_skip = false
	root.add_child(cutscene)
	await process_frame
	cutscene.play()
	await process_frame
	cutscene.skip()
	_check(not cutscene.skipped, "a client skipped")
	cutscene.queue_free()

	print("opening check: %d problem(s)" % _problems)
	quit(1 if _problems > 0 else 0)
