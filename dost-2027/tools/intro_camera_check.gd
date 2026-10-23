extends SceneTree

# Validation: the countdown's intro shot (Arena, THE INTRO SHOT).
#   * OPEN: a camera of the shot's own is current at intro_zoom with the scene's
#     FaceFocus about intro_face_screen_x (75%) across the screen, in all six trials;
#     the HUD (and the bottom band) is hidden
#   * PAN: through intro_pan_share of the countdown the zoom is exactly intro_zoom
#     and the camera only moves left, ending over the field
#   * REVEAL: only then does the zoom change (out, never back in), the HUD fades
#     in, and the view never shows past the arena's drawn area
#   * WHOLE ARENA: at GO there is no camera and the screen is world = screen again,
#     the last frame of the shot already on it
#   * FOLLOW PLAYER: at GO the follow camera is current, at follow_zoom, framing
#     the mortal exactly where the shot landed
#   * a countdown shorter than the shot squeezes it; GO is never late
#   * Bathala's later rounds (and any second countdown) skip the shot
#   * with Settings > Intro camera off there is no shot at all
# The arena's clock is stepped by hand (DT), so every number is exact.
# Run: godot --headless --path <project> -s res://tools/intro_camera_check.gd

const DT := 0.05
const SCREEN := Vector2(1152.0, 648.0)
const TRIALS := ["mayari/MayariArena", "tala/TalaArena", "apolaki/ApolakiArena", "hanan/HananArena",
	"mapulon_ikapati/LangitLupaArena", "bathala/BathalaArena"]

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

	# --- OPEN: the face sits 75% across, in every trial -------------------------------
	for path in TRIALS:
		var each := await _open("res://scenes/gods/%s.tscn" % path, false)
		var spot := each.get_node_or_null("FaceFocus") as Marker2D
		each._start_countdown()
		var opening := each.intro_camera()
		if opening == null or spot == null:
			_check(false, "%s: the countdown opens on the shot" % path)
		else:
			var across := ((spot.global_position.x - opening.global_position.x) * opening.zoom.x + SCREEN.x * 0.5) / SCREEN.x
			_check(opening.zoom.is_equal_approx(Vector2.ONE * each.intro_zoom) and absf(across - each.intro_face_screen_x) < 0.01,
				"%s: opens at intro_zoom %.1f with the face %.0f%% across" % [path, each.intro_zoom, across * 100.0])
		await _close(each)

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
	_check(not shot.limit_enabled, "...with no limits clamping the close-up")
	_check(arena.intro_pan_share == 0.7 and arena.intro_face_screen_x == 0.75 and arena.intro_hold == 0.2,
		"the tuning exports default to 0.7 / 0.75 / 0.2 s")
	var start_at := shot.global_position
	_step(arena, DT)
	_check(arena.hud_alpha == 0.0 and arena.band.modulate.a == 0.0, "the HUD and the bottom band are hidden on the face")
	_check(arena.player.locked, "the mortal stays locked")
	var frames := _record(arena)
	var pan_end: float = arena.countdown_time * arena.intro_pan_share
	var pan_ok := true
	var left_ok := true
	var reveal_ok := true
	var inside_ok := true
	var hud_ok := true
	var zoom_changed_at := -1.0
	var pan_moved := 0.0
	var before := {"at": start_at, "zoom": arena.intro_zoom}
	for frame in frames:
		if frame.zoom < arena.intro_zoom - 0.0001 and zoom_changed_at < 0.0:
			zoom_changed_at = frame.elapsed
		if frame.elapsed < pan_end - 0.0001:
			pan_ok = pan_ok and frame.zoom == arena.intro_zoom
			left_ok = left_ok and frame.at.x <= before.at.x + 0.0001
			hud_ok = hud_ok and frame.hud == 0.0
			pan_moved += before.at.x - frame.at.x
		else:
			reveal_ok = reveal_ok and frame.zoom <= before.zoom + 0.0001
		var half: Vector2 = SCREEN * 0.5 / frame.zoom
		inside_ok = inside_ok and frame.at.x - half.x >= -0.01 and frame.at.x + half.x <= SCREEN.x + 0.01 \
			and frame.at.y - half.y >= -0.01 and frame.at.y + half.y <= SCREEN.y + 0.01
		before = frame
	_check(pan_ok, "during the pan the zoom stays exactly intro_zoom")
	_check(left_ok and pan_moved > 50.0, "...while the camera only moves left (%.0f px)" % pan_moved)
	_check(hud_ok, "...and the HUD stays hidden")
	_check(zoom_changed_at >= pan_end - 0.0001, "the zoom only changes in the reveal (first at %.2f s, the pan ends at %.2f s)" % [zoom_changed_at, pan_end])
	_check(reveal_ok, "...and it only zooms out")
	_check(inside_ok, "the view never shows past the arena's drawn area")
	var panned: Dictionary = frames.filter(func(f): return f.elapsed < pan_end - 0.0001).back()
	var field_middle: Vector2 = arena._field.get_center()
	_check(absf(panned.at.x - field_middle.x) < SCREEN.x / arena.intro_zoom * 0.5 and panned.at.x < start_at.x,
		"the pan ends over the field's middle (x %.0f, field %.0f)" % [panned.at.x, field_middle.x])
	var mid: Dictionary = frames.filter(func(f): return f.elapsed >= pan_end + (arena.countdown_time - pan_end) * 0.5 - DT).front()
	_check(mid.zoom > 1.0 and mid.zoom < arena.intro_zoom and mid.hud > 0.0 and mid.hud < 1.0,
		"mid reveal: zoom %.2f between 1 and %.1f, HUD fading in (%.2f)" % [mid.zoom, arena.intro_zoom, mid.hud])
	var last: Rect2 = frames.back().rect
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
	last = _record(arena).back().rect
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
	_check(arena.intro_camera() != null and is_equal_approx(arena._intro_hold, 0.5 * arena.intro_pan_share * 0.5),
		"a 0.5s countdown holds the face %.3fs" % arena._intro_hold)
	_step_to(arena, 0.5 - DT * 0.5)
	_check(arena._phase == Arena.Phase.COUNTDOWN, "...still counting just before 0.5s")
	_step(arena, DT)
	_check(arena._going and arena.drop_active() and arena.intro_camera() == null, "...and GO comes at 0.5s, the shot cut (the drop starts)")
	_run_to_go(arena)
	_check(arena._phase == Arena.Phase.PLAYING, "...and the round opens when the drop ends")
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


# Step to GO, recording the shot after every step.
func _record(arena: Arena) -> Array:
	var frames := []
	var guard := 0
	while arena._phase == Arena.Phase.COUNTDOWN and guard < 1000:
		_step(arena, DT)
		var shot := arena.intro_camera()
		if shot != null:
			frames.append({"elapsed": arena._intro_span - arena._intro_left, "at": shot.global_position, "zoom": shot.zoom.x,
				"hud": arena.hud_alpha, "rect": Rect2(shot.global_position, shot.zoom)})
		guard += 1
	return frames


# Step until `seconds` of the countdown have passed.
func _step_to(arena: Arena, seconds: float) -> void:
	var guard := 0
	while arena.countdown_time - arena._countdown < seconds - 0.0001 and guard < 1000:
		_step(arena, DT)
		guard += 1


# Step to GO.
func _run_to_go(arena: Arena) -> void:
	var guard := 0
	while arena._phase == Arena.Phase.COUNTDOWN and guard < 1000:
		_step(arena, DT)
		guard += 1


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
