extends SceneTree

# Validation: the lobby's CAMERA = FOLLOW PLAYER, through the real Game shell,
# solo, in every trial of a run (Mayari, Tala, Apolaki, Hanan, Langit Lupa,
# Bathala's Agawan Base) and in the preparation area between them:
#   * the local mortal carries the one current Camera2D, at follow_zoom
#   * the view never shows past the field (plus follow_margin) right of the UI
#     strip, a field smaller than the view is centred in it, and the mortal
#     stands in the middle of what the strip leaves visible
#   * every HUD - the shell's panels, the God's Due menu, the dialogue, the
#     arena's own labels - is on a CanvasLayer and stays where it was authored
#   * Half Vision's mask is centred on the mortal's SCREEN position and grows
#     with the zoom
#   * Tala's slipper flies at the WORLD spot under the mouse
#   * an edge target out of view gets an arrow on the visible border, one in
#     view does not
#   * when the run is over the screen is back to world = screen
# and WHOLE ARENA (the default) builds no camera at all.
# Run: godot --headless --path <project> -s res://tools/follow_camera_check.gd

const SCREEN := Vector2(1152.0, 648.0)
const HUD_FIELDS := ["status_label", "hint_label", "callout_label", "attack_bar", "rules_card",
	"next_label", "ready_label", "shop", "bar"]

var _problems := 0
var _view: SubViewport


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _watchdog() -> void:
	await create_timer(120.0).timeout
	printerr("follow_camera_check: timed out")
	quit(1)


func _run() -> void:
	_watchdog()
	_view = SubViewport.new()
	_view.size = Vector2i(SCREEN)
	_view.disable_3d = true
	root.add_child(_view)
	await _frames(2)
	var network: Node = root.get_node("Network")
	var before: Dictionary = network.run_settings.to_dict()

	# --- WHOLE ARENA: no camera, world = screen ----------------------------------------
	network.run_settings.camera_mode = RunSettings.CAMERA_ARENA
	var order: Array[StringName] = [Gods.MAYARI, Gods.BATHALA]
	network.rpc_sync_trial_order(order)
	var game: Control = load("res://scenes/Game.tscn").instantiate()
	_view.add_child(game)
	await _frames(4)
	_check(game.arena != null and game.arena.camera == null and _view.get_camera_2d() == null,
		"WHOLE ARENA builds no camera")
	_check(_view.canvas_transform == Transform2D.IDENTITY, "...and the world is the screen")
	game.queue_free()
	await _frames(2)

	# --- FOLLOW PLAYER: every trial and the rests between them -------------------------
	network.run_settings.camera_mode = RunSettings.CAMERA_FOLLOW
	order = [Gods.MAYARI, Gods.TALA, Gods.APOLAKI, Gods.HANAN, Gods.MAPULON_IKAPATI, Gods.BATHALA]
	network.rpc_sync_trial_order(order)
	game = load("res://scenes/Game.tscn").instantiate()
	_view.add_child(game)
	await _frames(4)
	var panel_spot: Vector2 = game.own_panel.get_global_transform_with_canvas().origin
	for index in range(order.size()):
		var arena: Arena = game.arena
		_check(arena != null and arena.god_id == order[index], "the run reaches %s" % order[index])
		if arena == null:
			break
		arena._start_countdown()
		arena._start_trial()
		await _check_arena(arena, game, panel_spot, str(order[index]))
		if arena is TalaArena:
			await _check_tala_aim(arena)
		if index == order.size() - 1:
			break
		game._on_trial_complete()
		await _frames(4)
		var prep := game.arena as PrepArea
		_check(prep != null, "a rest follows %s" % order[index])
		if prep == null:
			break
		await _check_arena(prep, game, panel_spot, "the rest after %s" % order[index])
		if index == 0:
			await _check_prep_arrows(prep)
		prep._ready_up()
		await _frames(4)

	# --- after the run: the screen is the screen again -----------------------------------
	game._on_trial_complete()
	await _frames(4)
	_check(game.arena == null and game.finale_panel.visible, "the run ends on the finale")
	_check(_view.get_camera_2d() == null and _view.canvas_transform == Transform2D.IDENTITY,
		"with the last arena gone, world = screen again")
	_check(game.finale_panel.get_global_transform_with_canvas().origin.is_equal_approx(game.finale_panel.global_position),
		"the finale panel sits where it was authored")
	game.queue_free()
	await _frames(2)
	network.trial_order_ids.clear()
	network.run_settings = RunSettings.from_dict(before)
	print("follow camera checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _check_arena(arena: Arena, game: Control, panel_spot: Vector2, label: String) -> void:
	var camera := arena.camera
	_check(camera != null and _view.get_camera_2d() == camera and camera.get_parent() == arena.player,
		"%s: the local mortal carries the current camera" % label)
	if camera == null:
		return
	_check(camera.zoom.is_equal_approx(Vector2.ONE * arena.follow_zoom), "%s: at follow_zoom (%s)" % [label, str(camera.zoom)])
	var field: Rect2 = arena._field
	var held := field.grow(arena.follow_margin + 1.0)

	# The mortal in the middle of the field: in the middle of the visible screen too
	# (wherever the field is big enough to let the camera centre on them).
	arena.player.global_position = field.get_center()
	await _settle(camera)
	var visible := _visible_world()
	var screen_at := arena.player.get_global_transform_with_canvas().origin
	var expected := _expected_screen(arena)
	var middle := Vector2((Arena.UI_STRIP_WIDTH + SCREEN.x) * 0.5, SCREEN.y * 0.5)
	var roomy_x := field.size.x + 2.0 * arena.follow_margin > visible.size.x
	var roomy_y := field.size.y + 2.0 * arena.follow_margin > visible.size.y
	# Where an arena keeps its mortal off the field's centre (Tala's throwing
	# side, Apolaki's duel spot) the limits may hold the camera back: the model
	# below says where the mortal must be drawn, and it is the middle whenever
	# the limits let it.
	_check(screen_at.distance_to(expected) < 2.0,
		"%s: the mortal is drawn where the camera aims (%s, expected %s, the middle is %s)" % [label, str(screen_at), str(expected), str(middle)])
	_check(not (roomy_x and roomy_y) or expected.distance_to(middle) < 2.0 or arena.player.global_position.distance_to(field.get_center()) > 1.0,
		"%s: at the field's centre the mortal stands in the middle of the view right of the strip" % label)

	# Pushed into each corner, the view stays on the field (+ margin).
	var inside := true
	for corner in [field.position, Vector2(field.end.x, field.position.y), field.end, Vector2(field.position.x, field.end.y)]:
		arena.player.global_position = corner
		await _settle(camera)
		visible = _visible_world()
		if roomy_x and (visible.position.x < held.position.x or visible.end.x > held.end.x):
			inside = false
		if roomy_y and (visible.position.y < held.position.y or visible.end.y > held.end.y):
			inside = false
	_check(inside, "%s: the view never shows past the field + margin (field %s)" % [label, str(field)])
	# A field smaller than the view sits in the middle of it (an even border).
	arena.player.global_position = field.get_center()
	await _settle(camera)
	visible = _visible_world()
	_check((roomy_x or absf(visible.get_center().x - field.get_center().x) < 2.0)
		and (roomy_y or absf(visible.get_center().y - field.get_center().y) < 2.0),
		"%s: a field smaller than the view is centred in it (view %s)" % [label, str(visible)])

	# Every HUD on a CanvasLayer, and the shell's panel exactly where it was.
	var huds: Array = [arena.hud, arena.dialogue, arena.due_menu, game.own_panel, game.timer_label, game.other_players_vbox]
	for field_name in HUD_FIELDS:
		var node = arena.get(field_name)
		if node is CanvasItem:
			huds.append(node)
	var layered := true
	for node in huds:
		if node is CanvasItem and (node as CanvasItem).get_canvas_layer_node() == null:
			layered = false
			printerr("  not on a CanvasLayer: %s" % (node as Node).get_path())
	_check(layered, "%s: every HUD is on a CanvasLayer (%d checked)" % [label, huds.size()])
	_check(game.own_panel.get_global_transform_with_canvas().origin.is_equal_approx(panel_spot),
		"%s: the shell's panel has not moved" % label)

	# Half Vision: the mask follows the mortal on SCREEN and grows with the zoom.
	arena.player.global_position = field.get_center() + Vector2(field.size.x * 0.3, 0.0)
	await _settle(camera)
	arena._blind_radius = 0.16
	arena._blind_time = 1.0
	arena._apply_blindness(0.016)
	var material := arena.vision_mask.material as ShaderMaterial
	var mortal_screen := arena.player.get_global_transform_with_canvas().origin
	var centre: Vector2 = material.get_shader_parameter("center")
	_check(centre.is_equal_approx(mortal_screen / arena.vision_mask.size) and is_equal_approx(float(material.get_shader_parameter("radius")), 0.16 * arena.follow_zoom),
		"%s: Half Vision is centred on the mortal's screen position (%s vs %s)" % [label, str(centre), str(mortal_screen / arena.vision_mask.size)])
	arena._blind_time = 0.0
	arena._apply_blindness(0.016)

	# Edge arrows: exactly the targets out of view, each on the visible border.
	var shown := Rect2(Vector2(Arena.UI_STRIP_WIDTH, 0.0), SCREEN - Vector2(Arena.UI_STRIP_WIDTH, 0.0)).grow(-arena.edge_arrow_inset)
	var out_of_view := 0
	for target in arena.edge_targets():
		if is_instance_valid(target) and (target as Node2D).is_visible_in_tree() \
				and not shown.has_point((target as Node2D).get_global_transform_with_canvas().origin):
			out_of_view += 1
	var arrows := arena.edge_arrows()
	var on_border := true
	for arrow in arrows:
		on_border = on_border and shown.grow(1.0).has_point(arrow["tip"])
	_check(arrows.size() == out_of_view and on_border,
		"%s: one arrow per target out of view (%d targets, %d out, %d arrows)" % [label, arena.edge_targets().size(), out_of_view, arrows.size()])


# A click is on the SCREEN, a throw is aimed in the WORLD: with the camera moved
# away from the authored view, the slipper must still fly at the clicked spot.
func _check_tala_aim(tala: TalaArena) -> void:
	if tala.dialogue.is_active():
		tala.dialogue.close_now()
	tala.player.global_position = Vector2(tala._shoot_x - 60.0, tala._field.get_center().y)
	await _settle(tala.camera)
	tala._local_mode = "ready"
	tala._modes[tala._my_id] = "ready"
	var aim_at := tala.player.global_position + Vector2(220.0, -90.0)
	var on_screen: Vector2 = _view.canvas_transform * aim_at
	_check(not on_screen.is_equal_approx(aim_at), "tala: the camera has moved the world off the screen's coordinates")
	var move := InputEventMouseMotion.new()
	move.position = on_screen
	move.global_position = on_screen
	_view.push_input(move)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = on_screen
	click.global_position = on_screen
	_view.push_input(click)
	var slipper: Dictionary = tala._slippers.get(tala._my_id, {})
	var wanted := (aim_at - tala.player.global_position).normalized()
	_check(not slipper.is_empty() and (slipper["direction"] as Vector2).distance_to(wanted) < 0.02,
		"tala: a click throws at the world spot under the mouse (%s, wanted %s)" % [str(slipper.get("direction")), str(wanted)])


# The rest's altar and stall are far apart: standing at one, the other is pointed at.
func _check_prep_arrows(prep: PrepArea) -> void:
	prep.player.global_position = prep.get_node("Camp/Altar").global_position
	await _settle(prep.camera)
	var pointed: Array = prep.edge_arrows().map(func(arrow: Dictionary) -> Node: return arrow["node"])
	_check(pointed == [prep.stall], "at the altar, an arrow points at the stall off to the right")
	if not pointed.is_empty():
		_check((prep.edge_arrows()[0]["way"] as Vector2).x > 0.9, "...and it points right")


# Where the local mortal should be drawn: the camera aims half the strip (in world
# pixels) left of the mortal, whatever the mortal's scale, and the limits clamp the
# screen rect it shows (a 1152 x 648 screen at follow_zoom).
func _expected_screen(arena: Arena) -> Vector2:
	var camera := arena.camera
	var half := SCREEN * 0.5 / camera.zoom
	var aim: Vector2 = (camera.get_parent() as Node2D).global_position + Vector2(-Arena.UI_STRIP_WIDTH * 0.5 / camera.zoom.x, 0.0)
	var centre := Vector2(
		clampf(aim.x, camera.limit_left + half.x, maxf(camera.limit_left + half.x, camera.limit_right - half.x)),
		clampf(aim.y, camera.limit_top + half.y, maxf(camera.limit_top + half.y, camera.limit_bottom - half.y)))
	return (arena.player.global_position - centre) * camera.zoom + SCREEN * 0.5


# A few frames for the arena to run, then the camera cut straight to its aim - an
# arena that walks the mortal on its own (Hanan's run-up, Apolaki's duel) would
# otherwise be measured mid-pan.
func _settle(camera: Camera2D) -> void:
	camera.reset_smoothing()
	await _frames(2)
	camera.reset_smoothing()
	camera.force_update_scroll()


# The piece of the world on screen right of the UI strip.
func _visible_world() -> Rect2:
	var to_world := _view.canvas_transform.affine_inverse()
	var top_left: Vector2 = to_world * Vector2(Arena.UI_STRIP_WIDTH, 0.0)
	var bottom_right: Vector2 = to_world * SCREEN
	return Rect2(top_left, bottom_right - top_left)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
