extends SceneTree

# Validation: the shared floating text (UI/Popups/favor_popup.gd, Arena.favor_popup).
#   * a gain and a loss on one mortal in the same frame are two rows whose rects do
#     not overlap; plain outlined text, no icon and no box - +250 FAVOR at 24 px
#     (250+) with the reason on its own line, -120 FAVOR at 16 px
#   * they sit on the popup layer above Mayari's blackout and Apolaki's sun patches,
#     stay visible with the blackout on, and keep inside the screen, clear of the
#     left strip and the bottom band
#   * a stack holds at most POPUP_MAX: a 4th fades the oldest out early
#   * a rival's popups are 75% size and opacity
#   * the callout is one popup that keeps up with the same text and repaints a new one
# Run: godot --headless --path <project> -s res://tools/popup_check.gd

var _problems := 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _arena(view: SubViewport, path: String) -> Arena:
	var arena: Arena = load(path).instantiate()
	view.add_child(arena)
	await _frames(2)
	while arena.dialogue.is_active():
		arena.dialogue.advance()
	arena._phase = Arena.Phase.PLAYING
	arena._end_intro_shot()
	arena._trial_time = 999.0
	return arena


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)

	# --- a gain and a loss at once (Mayari's Patintero, then its blackout) ---------------------
	var arena := await _arena(view, "res://scenes/gods/mayari/MayariArena.tscn")
	var gain: FavorPopup = arena.favor_popup(arena._my_id, 250)
	var loss: FavorPopup = arena.favor_popup(arena._my_id, -120, "Tagged")
	await create_timer(FavorPopup.POP_TIME + 0.1).timeout  # past the pop-in's overshoot (real time: headless frames run fast)
	var a := gain.get_global_rect()
	var b := loss.get_global_rect()
	_check(gain != loss and a.has_area() and b.has_area() and not a.intersects(b), "a gain and a loss in the same frame are two rows that do not overlap (%s / %s)" % [str(a), str(b)])
	_check(gain.number_text() == "+250 FAVOR" and gain.number_label.get_theme_font_size("font_size") == 24
		and not gain.icon.visible and gain.get_node_or_null("Rows/Row/Coin") == null and gain.get_theme_stylebox("panel") is StyleBoxEmpty,
		"a 250+ gain is plain text: +250 FAVOR at 24 px, no icon and no box")
	_check(loss.number_text() == "-120 FAVOR" and loss.reason_label.visible and loss.reason_label.text == "Tagged" and loss.number_label.get_theme_font_size("font_size") == 16,
		"the loss is -120 FAVOR at 16 px with its reason on a second line")
	var band_top: float = arena.band.get_global_rect().position.y
	_check(a.position.x >= Arena.UI_STRIP_WIDTH and b.position.x >= Arena.UI_STRIP_WIDTH and a.end.y <= band_top and b.end.y <= band_top and a.position.y >= 0.0,
		"both keep inside the screen, clear of the left strip and the bottom band")
	var head_y: float = arena.player.get_global_transform_with_canvas().origin.y
	_check(maxf(a.end.y, b.end.y) < head_y - 40.0, "they sit above the mortal's head and name tag")
	var vision: CanvasLayer = arena.get_node("VisionLayer")
	var patches: CanvasLayer = arena.get_node("Patches")
	_check(arena.popup_layer.layer > vision.layer and arena.popup_layer.layer >= patches.layer and arena.popup_layer.get_index() > patches.get_index()
		and arena.popup_layer.layer < arena.band.get_canvas_layer_node().layer,
		"the popup layer (%d) is above the blackout (%d) and the sun patches (%d), below the band" % [arena.popup_layer.layer, vision.layer, patches.layer])
	arena._blind_time = 5.0
	var blind := arena.favor_popup(arena._my_id, -50, "Caught")
	await create_timer(FavorPopup.POP_TIME + 0.1).timeout
	_check(vision.visible and is_instance_valid(blind) and blind.is_visible_in_tree() and blind.modulate.a > 0.9 and blind.get_canvas_layer_node() == arena.popup_layer,
		"with the blackout on, a popup is still drawn over it (alpha %.2f)" % (blind.modulate.a if is_instance_valid(blind) else 0.0))
	# --- at most POPUP_MAX in a stack -------------------------------------------------------------
	var made: Array = []
	for index in range(Arena.POPUP_MAX + 2):
		made.append(arena.mortal_popup(arena._my_id, "WORD %d" % index, UITokens.GOLD))
	var live := made.filter(func(each) -> bool: return is_instance_valid(each) and not each.is_going())
	_check(live.size() == Arena.POPUP_MAX and (made[0] as FavorPopup).is_going(), "a stack shows at most %d: the oldest fades out early (%d live)" % [Arena.POPUP_MAX, live.size()])
	# --- the callout ------------------------------------------------------------------------------
	arena.callout("TAYA!", UITokens.EMBER, 1.0)
	await _frames(2)
	_check(arena.callout_label.visible and arena.callout_label.text == "TAYA!", "the callout shows its text over the field")
	arena.callout("ALIS NA!", UITokens.EMBER, 1.0)
	_check(arena.callout_label.text == "ALIS NA!" and arena._callout_pill.visible, "a new callout repaints the one pill")
	arena.callout("", Color.WHITE, 0.0)
	await create_timer(FavorPopup.FADE_TIME + 0.3).timeout
	_check(not arena.callout_label.visible, "...and it goes when let go")
	arena.queue_free()
	await _frames(2)

	# --- a rival's popups (Langit Lupa's solo bots) ---------------------------------------------------
	var langit := await _arena(view, "res://scenes/gods/mapulon_ikapati/LangitLupaArena.tscn")
	await _frames(4)
	var mine := langit.favor_popup(1, 40)
	var theirs := langit.favor_popup(2, 40)
	await create_timer(FavorPopup.POP_TIME + 0.1).timeout
	_check(is_equal_approx(theirs.base_scale, Arena.RIVAL_POPUP_LOOK) and is_equal_approx(mine.base_scale, 1.0) and theirs.modulate.a < mine.modulate.a,
		"a rival's popup is 75% size and opacity, ours full")
	var bot: Node2D = langit._bots[2]
	_check(absf(theirs.get_global_rect().get_center().x - bot.get_global_transform_with_canvas().origin.x) < 40.0, "...and it hangs over that rival")

	print("popup checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
