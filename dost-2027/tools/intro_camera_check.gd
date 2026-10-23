extends SceneTree

# Validation: the countdown's intro shot (Arena, THE INTRO SHOT).
#   * WHOLE ARENA: at the countdown's start a camera of the shot's own is current,
#     at intro_zoom, on the scene's FaceFocus; the HUD (and the bottom band) is
#     hidden, mid pull-out it is on its way back; at GO there is no camera and
#     the screen is world = screen again, the last frame of the shot already on it
#   * FOLLOW PLAYER: at GO the follow camera is current, at follow_zoom, framing
#     the mortal exactly where the shot landed
#   * a countdown shorter than the shot squeezes it; GO is never late
#   * Bathala's later rounds (and any second countdown) skip the shot
#   * with Settings > Intro camera off there is no shot at all
# The arena's clock is stepped by hand (DT), so every number is exact.
# Run: godot --headless --path <project> -s res://tools/intro_camera_check.gd

const DT := 0.05
const SCREEN := Vector2(1152.0, 648.0)

var _problems := 0
var _view: SubViewport


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(SCREEN)
	_view.disable_3d = true
	root.add_child(_view)
	var settings: Node = root.get_node("Settings")
	var setting_before: bool = settings.get_value("gameplay", "intro_camera")
	settings.set_value("gameplay", "intro_camera", true)

	# --- WHOLE ARENA ----------------------------------------------------------------
	var arena := await _open("res://scenes/gods/mayari/MayariArena.tscn", false)
	var focus := arena.get_node_or_null("FaceFocus") as Marker2D
	_check(focus != null, "the arena scene has a FaceFocus marker")
	arena._start_countdown()
	var shot := arena.intro_camera()
	_check(shot != null and _view.get_camera_2d() == shot, "the countdown opens on the shot's own camera")
	if shot == null or focus == null:
		_finish(settings, setting_before)
		return
	_check(shot.zoom.is_equal_approx(Vector2.ONE * arena.intro_zoom) and shot.global_position.is_equal_approx(focus.global_position),
		"...at intro_zoom (%s), on the god's face (%s)" % [str(shot.zoom), str(shot.global_position)])
	_check(not shot.limit_enabled, "...with no limits clamping the close-up")
	_step(arena, DT)
	_check(arena.hud_alpha == 0.0 and arena.band.modulate.a == 0.0, "the HUD and the bottom band are hidden on the face")
	_check(arena.player.locked, "the mortal stays locked")
	_step_to(arena, arena.countdown_time * 0.5 + arena.intro_hold * 0.5)
	_check(shot.zoom.x > 1.0 and shot.zoom.x < arena.intro_zoom and arena.hud_alpha > 0.0 and arena.hud_alpha < 1.0,
		"mid pull-out: zoom %.2f between 1 and %.1f, HUD fading in (%.2f)" % [shot.zoom.x, arena.intro_zoom, arena.hud_alpha])
	var last := _run_to_go(arena)
	_check(last.position.distance_to(SCREEN * 0.5) < 2.0 and absf(last.size.x - 1.0) < 0.01,
		"the shot's last frame is already the whole screen (%s)" % str(last))
	_check(arena._phase == Arena.Phase.PLAYING and _view.get_camera_2d() == null and not is_instance_valid(shot),
		"at GO the shot's camera is gone")
	_check(_view.canvas_transform == Transform2D.IDENTITY and arena.hud_alpha == 1.0 and arena.band.modulate.a == 1.0,
		"...the view is exactly the static one, the HUD all back")
	arena._start_countdown()
	_check(arena.intro_camera() == null, "a second countdown of the same trial has no shot")
	await _close(arena)

	# --- FOLLOW PLAYER --------------------------------------------------------------
	arena = await _open("res://scenes/gods/tala/TalaArena.tscn", true)
	arena._start_countdown()
	_check(arena.intro_camera() != null and _view.get_camera_2d() == arena.intro_camera(), "follow: the shot takes the view from the follow camera")
	_check(arena.edge_arrows().is_empty(), "follow: no edge arrows during the shot")
	var target := arena.intro_target()
	last = _run_to_go(arena)
	var follow := arena.camera
	_check(follow != null and _view.get_camera_2d() == follow and follow.zoom.is_equal_approx(Vector2.ONE * arena.follow_zoom),
		"follow: at GO the follow camera is current at follow_zoom")
	if follow != null:
		follow.force_update_scroll()
		_check(follow.get_screen_center_position().distance_to(target.position) < 1.0,
			"follow: it frames the mortal where the shot landed (%s vs %s)" % [str(follow.get_screen_center_position()), str(target.position)])
		_check(last.position.distance_to(target.position) < 2.0 and absf(last.size.x - arena.follow_zoom) < 0.01,
			"follow: the shot's last frame is already that view (%s)" % str(last))
	await _close(arena)

	# --- a short countdown squeezes the shot, GO stays on time ----------------------
	arena = await _open("res://scenes/gods/hanan/HananArena.tscn", false, 0.5)
	arena._start_countdown()
	_check(arena.intro_camera() != null and is_equal_approx(arena._intro_hold, 0.25), "a 0.5s countdown holds the face 0.25s")
	_step_to(arena, 0.5 - DT * 0.5)
	_check(arena._phase == Arena.Phase.COUNTDOWN, "...still counting just before 0.5s")
	_step(arena, DT)
	_check(arena._phase == Arena.Phase.PLAYING and arena.intro_camera() == null, "...and GO comes at 0.5s, the shot cut")
	await _close(arena)

	# --- Bathala: the shot opens the trial, never a later round ---------------------
	var bathala := await _open("res://scenes/gods/bathala/BathalaArena.tscn", false) as BathalaArena
	bathala._start_countdown()
	_check(bathala.intro_camera() != null, "Bathala: the first countdown has the shot")
	_run_to_go(bathala)
	bathala._start_round()
	_check(bathala.intro_camera() == null and _view.get_camera_2d() == null, "Bathala: a later round's 3 - 2 - 1 skips it")
	await _close(bathala)

	# --- the setting off: no shot ---------------------------------------------------
	settings.set_value("gameplay", "intro_camera", false)
	arena = await _open("res://scenes/gods/apolaki/ApolakiArena.tscn", false)
	arena._start_countdown()
	_step(arena, DT)
	_check(arena.intro_camera() == null and _view.get_camera_2d() == null and arena.hud_alpha == 1.0,
		"Intro camera off: the countdown is as before")
	await _close(arena)
	_finish(settings, setting_before)


func _finish(settings: Node, setting_before: bool) -> void:
	settings.set_value("gameplay", "intro_camera", setting_before)
	print("intro camera checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _open(path: String, follow: bool, countdown := -1.0) -> Arena:
	var arena: Arena = load(path).instantiate()
	arena.follow_camera = follow
	if countdown > 0.0:
		arena.countdown_time = countdown
	_view.add_child(arena)
	await _frames(2)
	if arena.dialogue.is_active():
		arena.dialogue.close_now()
	arena.set_process(false)  # the clock is stepped by hand
	return arena


func _close(arena: Arena) -> void:
	arena.queue_free()
	await _frames(2)
	_view.canvas_transform = Transform2D.IDENTITY


func _step(arena: Arena, delta: float) -> void:
	arena._process(delta)


# Step until `seconds` of the countdown have passed.
func _step_to(arena: Arena, seconds: float) -> void:
	var guard := 0
	while arena.countdown_time - arena._countdown < seconds - 0.0001 and guard < 1000:
		_step(arena, DT)
		guard += 1


# Step to GO; returns the shot's last frame as Rect2(position, Vector2(zoom, zoom)).
func _run_to_go(arena: Arena) -> Rect2:
	var last := Rect2()
	var guard := 0
	while arena._phase == Arena.Phase.COUNTDOWN and guard < 1000:
		var shot := arena.intro_camera()
		if shot != null:
			last = Rect2(shot.global_position, shot.zoom)
		_step(arena, DT)
		guard += 1
	return last


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
