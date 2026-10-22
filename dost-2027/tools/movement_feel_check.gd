extends SceneTree

# Validation: how the mortal moves and how that reads (scripts/gods/common/mortal.gd's
# FEEL and LOOK, Mortal.tscn, Arena.dash_buffer).
#   * the player's walk reaches move_speed within 6 physics frames and never goes
#     past it, and stops within 8 once the keys are let go
#   * set_lock(true) stops the mortal on the frame it is called; a stun's shove
#     takes over from the walk at once
#   * a dash hands back to the walk at move_speed, the way it went
#   * held against the arena's bounds, the walk holds no speed into the edge
#   * a minute of walking leaves the root node's scale, rotation and modulate as
#     the arenas set them (only the Sprite moves)
#   * a ghost the arena only ever places (global_position) still steps, walks and
#     turns to face where it goes
#   * the clip: idle standing, walk moving; an action clip wins and, once played
#     out (or on play_locomotion()), the mortal goes back to what it is doing; a
#     stun or a locked player shows the idle; the legacy palette follows defend-arnis
#   * a stunned mortal (or a ghost shown stunned) has three stars over its head
#   * a SPACE pressed while the dash recharges fires once it is ready, inside the
#     buffer; one pressed too early to make it is dropped
# Run: godot --headless --path <project> -s res://tools/movement_feel_check.gd

const MORTAL := preload("res://scenes/gods/common/Mortal.tscn")

var _problems := 0


func _initialize() -> void:
	_run()


func _physics(count: int) -> void:
	for index in range(count):
		await physics_frame


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)
	var mortal: ArenaMortal = MORTAL.instantiate()
	view.add_child(mortal)
	mortal.global_position = Vector2(500, 300)
	await _physics(2)
	var cap := mortal.move_speed

	# --- speeding up, never past the cap, stopping -------------------------------------------
	Input.action_press("move_right")
	var frames := 0
	var fastest := 0.0
	while frames < 6 and mortal.velocity.length() < cap - 0.01:
		await _physics(1)
		frames += 1
		fastest = maxf(fastest, mortal.velocity.length())
	_check(is_equal_approx(mortal.velocity.length(), cap), "full speed in %d physics frames (6 allowed)" % frames)
	for index in range(30):
		await _physics(1)
		fastest = maxf(fastest, mortal.velocity.length())
	_check(fastest <= cap + 0.01, "...and never past move_speed (%.2f of %.2f)" % [fastest, cap])
	Input.action_release("move_right")
	frames = 0
	while frames < 8 and mortal.velocity.length() > 0.0:
		await _physics(1)
		frames += 1
	_check(mortal.velocity == Vector2.ZERO, "let go, it stops in %d physics frames (8 allowed)" % frames)

	# --- a lock and a stun take over at once --------------------------------------------------
	Input.action_press("move_right")
	await _physics(8)
	mortal.set_lock(true)
	_check(mortal.velocity == Vector2.ZERO, "set_lock(true) stops it on the same frame")
	var held := mortal.global_position
	await _physics(1)
	_check(mortal.global_position == held and mortal.velocity == Vector2.ZERO, "...and it stays put while locked")
	mortal.set_lock(false)
	await _physics(8)
	mortal.hit(Vector2.LEFT, 0.3, 400.0)
	await _physics(1)
	_check(mortal.velocity.x < -380.0, "a stun's shove overrides the walk at once (%.1f)" % mortal.velocity.x)
	Input.action_release("move_right")
	await _physics(30)

	# --- the dash flows back into the walk ----------------------------------------------------
	mortal.dash(Vector2.UP, 110.0, 0.15)
	frames = 0
	while mortal.is_dashing() and frames < 30:
		await _physics(1)
		frames += 1
	_check(is_equal_approx(mortal.velocity.length(), cap) and mortal.velocity.normalized().is_equal_approx(Vector2.UP),
		"a dash hands off at move_speed along its way (%s)" % mortal.velocity)
	await _physics(10)

	# --- the edge of the arena ------------------------------------------------------------------
	mortal.bounds = Rect2(0, 0, 600, 400)
	mortal.global_position = Vector2(560, 200)
	Input.action_press("move_right")
	await _physics(20)
	_check(is_equal_approx(mortal.global_position.x, 600.0 - mortal.radius) and mortal.velocity.x == 0.0,
		"held against the bounds, no speed into the edge (x %.1f, vx %.1f)" % [mortal.global_position.x, mortal.velocity.x])
	Input.action_release("move_right")
	mortal.bounds = Rect2()

	# --- a minute of walking, run straight through ----------------------------------------------
	mortal.scale = Vector2(1.0, 0.85)  # Hanan's crouch owns the root's scale
	var keys: Array[StringName] = [&"move_right", &"move_down", &"move_left", &"move_up"]
	for frame in range(3600):
		if frame % 40 == 0:
			for key in keys:
				Input.action_release(key)
			Input.action_press(keys[(frame / 40) % keys.size()])
		mortal._physics_process(1.0 / 60.0)
	for key in keys:
		Input.action_release(key)
	_check(mortal.scale == Vector2(1.0, 0.85) and mortal.rotation == 0.0 and mortal.modulate == Color.WHITE,
		"a minute of walking leaves the root's scale, rotation and modulate alone")
	_check(mortal._steps_taken > 100, "...and took steps (%d)" % mortal._steps_taken)
	mortal.scale = Vector2.ONE
	mortal.hit(Vector2.RIGHT, 0.2, 100.0)
	_check(mortal.sprite.self_modulate.r > 1.0 or mortal._hit_flash > 0.0, "a hit flashes the sprite even with Glow hidden")

	# --- a ghost, only ever placed --------------------------------------------------------------
	var ghost: ArenaMortal = MORTAL.instantiate()
	view.add_child(ghost)
	ghost.set_lock(true)
	ghost.global_position = Vector2(700, 300)
	await _physics(2)
	for index in range(30):
		ghost.global_position += Vector2(-3.0, 0.0)  # 180 px/s, as Arena._move_ghosts would
		await _physics(1)
	_check(ghost._steps_taken > 0 or ghost._step_phase > 0.0, "a placed ghost walks (phase %.2f, %d steps)" % [ghost._step_phase, ghost._steps_taken])
	_check(ghost.facing == -1 and ghost.sprite.flip_h, "...and faces the way it goes")
	_check(ghost.current_animation() == ArenaMortal.ANIM_WALK, "...playing the walk clip (%s)" % ghost.current_animation())
	_check(not ghost._seen_dash, "...and a walk is not taken for a dash")
	ghost.queue_free()
	mortal.queue_free()
	await _physics(2)

	# --- which clip plays ------------------------------------------------------------------------
	var runner: ArenaMortal = MORTAL.instantiate()
	view.add_child(runner)
	runner.global_position = Vector2(300, 300)
	await _physics(2)
	_check(runner.current_animation() == ArenaMortal.ANIM_IDLE, "standing still plays the idle")
	Input.action_press("move_right")
	await _physics(20)
	_check(runner.current_animation() == ArenaMortal.ANIM_WALK, "walking plays the walk")
	runner.play_animation(&"hit-arnis")
	await _physics(5)
	_check(runner.current_animation() == &"hit-arnis" and runner.is_animation_playing(&"hit-arnis"), "an action clip wins over the walk while it plays")
	await _physics(80)
	_check(runner.current_animation() == ArenaMortal.ANIM_WALK, "...and once it has played out, still holding right, it is walking again (%s)" % runner.current_animation())
	runner.play_animation(&"defend-arnis")
	runner.play_locomotion()
	_check(runner.current_animation() == ArenaMortal.ANIM_WALK, "play_locomotion() after an action on the run goes back to the walk")
	Input.action_release("move_right")
	await _physics(30)
	_check(runner.current_animation() == ArenaMortal.ANIM_IDLE, "let go, back to the idle")
	runner.play_animation(&"hit-arnis")
	runner.play_locomotion()
	_check(runner.current_animation() == ArenaMortal.ANIM_IDLE, "play_locomotion() standing still goes back to the idle")
	Input.action_press("move_right")
	await _physics(20)
	runner.hit(Vector2.LEFT, 0.5, 300.0)
	await _physics(10)  # past the hit's freeze (hit_stop, 0.06s)
	_check(runner.current_animation() == ArenaMortal.ANIM_IDLE, "stunned, it shows the idle however fast it slides")
	await _physics(40)
	_check(runner.current_animation() == ArenaMortal.ANIM_WALK, "...and walks again when the stun ends")
	runner.set_lock(true)
	await _physics(4)
	_check(runner.current_animation() == ArenaMortal.ANIM_IDLE, "the player locked (dialogue, a rooted chant) shows the idle with the keys held")
	runner.set_lock(false)
	Input.action_release("move_right")
	await _physics(10)

	# --- the legacy palette follows the clip -------------------------------------------------------
	var swap := runner.sprite.material as ShaderMaterial
	runner.play_animation(&"defend-arnis")
	var legacy_on: bool = swap.get_shader_parameter("legacy")
	runner.play_locomotion()
	await _physics(1)
	_check(legacy_on and not swap.get_shader_parameter("legacy"), "the old-sheet palette is on for defend-arnis only")

	# --- the stun's stars ---------------------------------------------------------------------------
	_check(not runner.stun_stars.visible, "no stars over a mortal that is not stunned")
	runner.hit(Vector2.RIGHT, 0.5, 100.0)
	await _physics(3)
	_check(runner.stun_stars.visible and runner.stun_stars.get_child_count() == 3, "a stunned mortal has three stars circling its head")
	var star_at: Vector2 = (runner.stun_stars.get_child(0) as Node2D).position
	await _physics(3)
	_check(star_at != (runner.stun_stars.get_child(0) as Node2D).position, "...and they circle")
	await _physics(60)
	_check(not runner.stun_stars.visible and not runner.is_stunned(), "...gone when the stun is over")
	var placed: ArenaMortal = MORTAL.instantiate()
	view.add_child(placed)
	placed.set_lock(true)
	placed.global_position = Vector2(500, 300)
	await _physics(2)
	placed.show_stun(0.5)
	await _physics(4)
	_check(placed.stun_stars.visible and placed.global_position == Vector2(500, 300) and not placed.is_stunned(),
		"a ghost shown stunned gets the stars and is not moved by it")
	placed.queue_free()
	runner.queue_free()
	await _physics(2)

	# --- the dash buffer -----------------------------------------------------------------------
	var arena: Arena = load("res://scenes/gods/mapulon_ikapati/LangitLupaArena.tscn").instantiate()
	view.add_child(arena)
	await _physics(4)
	arena._phase = Arena.Phase.PLAYING
	arena._trial_time = 60.0  # the round must not run out mid-test
	arena.dialogue.close_now()
	arena.player.set_lock(false)
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	arena._dash_cd = 0.05
	arena._unhandled_input(space)
	_check(not arena.player.is_dashing() and arena._dash_buffered > 0.0, "SPACE while recharging is held, not dropped")
	await create_timer(0.1).timeout
	_check(arena.dash_cooldown_left() > 1.0 and arena._dash_buffered == 0.0, "...and dashes once the recharge ends (%.2fs left)" % arena.dash_cooldown_left())
	arena._dash_cd = 0.5
	arena._unhandled_input(space)
	await create_timer(0.2).timeout
	_check(arena._dash_buffered == 0.0 and arena.dash_cooldown_left() < 0.5, "a SPACE pressed too early to make the buffer is dropped")
	arena._dash_cd = 0.0
	arena.dialogue.show_lines([{"speaker": "TEST", "color": Color.WHITE, "text": "A LINE"}])
	arena._unhandled_input(space)
	_check(arena._dash_buffered == 0.0 and arena.dash_cooldown_left() == 0.0, "SPACE in a dialogue is neither used nor kept")
	arena.queue_free()
	await _physics(2)

	print("movement feel checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
