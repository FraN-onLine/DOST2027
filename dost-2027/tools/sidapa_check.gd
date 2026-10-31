extends SceneTree

# Validation: Sidapa's Piko. The stone is thrown with a loaded throw (aim, hold,
# release; a flight that lands on no tile costs 50 and bounces back), the lap hops
# the snake in order skipping the stone's tile, a clean hop pays 100 (200 for the
# turn tile that ends the way out), a wrong tile or no tile costs 100, the stone
# itself costs 200, the way back collects it for 250, tile 10 always turns the lap
# and never takes a stone, the lap then hops home and throws again; during the
# blitz the over-head count runs (12 s, 1.5 s a hop, a 3 s stun when it empties)
# and the arrow is faster (+20 a hop), and outside the blitz there is no count. The
# court is authored in the scene (Pad + Tile1..10, draggable), the whole field is
# shared by every mortal and the map sits where the other arenas put it. Then
# Sidapa's seven favors: the E ring, the Q window, First Cleanse, Departure,
# Lifeline, Guilty Pleasure and Time Is Now.
# Run: godot --headless --path <project> -s res://tools/sidapa_check.gd

const DT := 1.0 / 60.0

# Arena.Stage, local so the check never needs the new class in Godot's cache.
const THROW := 0
const FLIGHT := 1
const AIM := 2
const HOP := 3

const TURN_TILE := 10

# The court's layout, read back out of the scene before the run (the designer may
# drag a tile anywhere; the checks follow the drawn court, not a copy of it).
var CENTERS: Array[Vector2] = []
var TURN := Vector2.ZERO
var PAD := Vector2.ZERO

var _arena
var _problems := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)
	_arena = load("res://scenes/gods/sidapa/SidapaArena.tscn").instantiate()
	view.add_child(_arena)
	await process_frame
	await process_frame
	_read_court()

	# --- the god and the court ---------------------------------------------------------
	_check(_arena.god != null and _arena.god.id == &"sidapa" and _arena.god.game_name == "PIKO",
		"Sidapa's arena is Piko")
	_check(_arena.god.favors.size() == 7, "Sidapa bestows seven favors")
	_check(not _arena.separate_players() and _arena.shares_mortal_positions(),
		"one shared court, and every position travels (the E ring judges rivals)")
	_check(_arena.nearby_movement_favors_enabled(), "...so the Guidance finds the rivals beside you")
	_check(_arena.board != null and _arena.tiles.size() == TURN_TILE and _arena.board.centers.size() == TURN_TILE,
		"the board reads ten tiles")
	_check(_arena.start.is_equal_approx(PAD), "the board puts the pad where the scene draws it")
	_check(_arena.arrow != null and _arena.gauge != null and _arena.throw_aim != null and _arena.head_label != null,
		"the hop arrow, the loading bar, the throw aim and the head count all exist")

	# The court is AUTHORED out of scenes: every tile is a PikoTile instance, free
	# to drag and number in the inspector, with its chalk sprite and number label
	# in the scene itself (the background is a real, editable Sprite2D). The pale
	# stone of the backdrop is covered by the court panel.
	var instanced := true
	var numbered := true
	var drawn := true
	for index in range(CENTERS.size()):
		var tile: Node2D = _arena.get_node_or_null("ArenaField/Tile%d" % (index + 1))
		instanced = instanced and tile != null and tile.scene_file_path.ends_with("PikoTile.tscn")
		numbered = numbered and tile != null and int(tile.get("number")) == index + 1
		var art: Sprite2D = null
		var ink: Label = null
		if tile != null:
			art = tile.get_node_or_null("Background") as Sprite2D
			ink = tile.get_node_or_null("Number") as Label
		drawn = drawn and art != null and art.texture != null \
			and art.texture.resource_path.ends_with("piko_tile_chalk.png") \
			and ink != null and ink.text == str(index + 1)
	_check(instanced, "every tile is a PikoTile scene instance")
	_check(numbered, "...with its number typed in the inspector")
	_check(drawn, "...and a chalk Sprite2D plus its number label in the scene")
	var turn_tile: Node2D = _arena.get_node_or_null("ArenaField/Tile%d" % TURN_TILE)
	var turn_caption: Label = null
	if turn_tile != null:
		turn_caption = turn_tile.get_node_or_null("Caption") as Label
	_check(turn_tile != null and turn_tile.scene_file_path.ends_with("PikoTile.tscn")
			and int(turn_tile.get("number")) == TURN_TILE and bool(turn_tile.get("turn"))
			and turn_caption != null and turn_caption.visible and turn_caption.text == "TURN",
		"tile 10 is the authored turn tile at the end of the snake")
	var pad: Node2D = _arena.get_node_or_null("ArenaField/Pad")
	var pad_art: Sprite2D = null
	var pad_caption: Label = null
	if pad != null:
		pad_art = pad.get_node_or_null("Background") as Sprite2D
		pad_caption = pad.get_node_or_null("Caption") as Label
	_check(pad != null and pad.scene_file_path.ends_with("PikoPad.tscn") and bool(pad.get("pad"))
			and pad_art != null and pad_art.texture != null \
			and pad_art.texture.resource_path.ends_with("piko_pad_chalk.png") \
			and pad_caption != null and pad_caption.visible and pad_caption.text == "START",
		"the start pad is a PikoPad scene instance with its chalk slab and caption")
	var court: Control = _arena.get_node_or_null("ArenaField/Court") as Control
	_check(court != null and court.visible and court.get_index() == 0,
		"the asphalt court is drawn under everything else")
	var court_rect := Rect2(court.position if court != null else Vector2.ZERO,
		court.size if court != null else Vector2.ZERO)
	var covered := court_rect.encloses(Rect2(Vector2(235.0, 390.0), Vector2(856.0, 209.0)))
	for center in CENTERS:
		covered = covered and court_rect.has_point(center)
	covered = covered and court_rect.has_point(TURN)
	_check(covered and court_rect.has_point(PAD),
		"the court covers the backdrop's stone and holds every tile (%s)" % str(court_rect))
	var arena_bg: Node2D = _arena.get_node("ArenaBG")
	_check((arena_bg as Node2D).position.is_equal_approx(Vector2(944.0, 92.0)),
		"the map sits where every other arena puts it (%s)" % str((arena_bg as Node2D).position))

	var field: Rect2 = _arena._field
	var inside := true
	for center in CENTERS:
		inside = inside and field.has_point(center)
	inside = inside and field.has_point(TURN)
	_check(inside and field.has_point(PAD), "every tile and the start pad sit inside the authored border")
	_arena.collect_units()
	_arena.collect_units()
	_check(_arena.board.centers.size() == TURN_TILE, "collect_units is idempotent (the layout repeats it every 2 s)")

	var guard := 0
	while _arena.dialogue.is_active() and guard < 40:
		_arena.dialogue.advance()
		guard += 1
	_arena._phase = Arena.Phase.PLAYING
	_arena._end_intro_shot()
	_arena._trial_time = 999.0
	_arena.arena_round_reset()
	_arena._phase = Arena.Phase.PLAYING
	_check(_arena._stage == THROW and _arena.player.locked, "a round opens on the throw, the mortal held on the pad")

	# --- the throw ------------------------------------------------------------------------
	_arena._sync_nodes()
	_check(_arena.gauge.visible and _arena.throw_aim.visible and _arena.throw_aim.active,
		"the loading bar and the aim arc show while the stone is in hand")
	_check(_arena.throw_aim.tile == 0 or _arena.throw_aim.on_tile,
		"the reticle reads the tile it is over")
	_check(not _arena.throw_aim.flying and _arena.gauge.target == -1.0,
		"the throw's bar has no hop window on it")

	_arena.rules.local().favor = 500
	_arena._throw_at(Vector2(1050.0, 300.0))
	_check(_arena._stage == FLIGHT, "a throw leaves the hand (the stone is in the air)")
	_land_throw()
	_check(_arena.rules.local().favor == 450, "a throw that lands on no tile costs 50 FAVOR")
	_check(_arena._stage == THROW and _arena._stone == 0, "...and the stone comes back to the hand")

	# Tile 10 ends the snake: a stone may never rest there, so the reticle offers
	# no target and a throw at it bounces off like any other miss.
	_arena.rules.local().favor = 500
	_arena.player.global_position = CENTERS[8]
	_arena._aim_world = TURN
	_arena._throw_charge = _throw_charge_for(_arena.player.global_position, TURN)
	_arena._sync_nodes()
	_check(_arena._throw_target().is_equal_approx(TURN) and _arena.throw_aim.tile == 0
			and not _arena.throw_aim.on_tile,
		"the reticle does not offer the turn tile as a stone target")
	_arena._throw_at(TURN)
	_land_throw()
	_check(_arena.rules.local().favor == 450 and _arena._stage == THROW and _arena._stone == 0,
		"a stone thrown at the turn tile bounces back (it never rests there)")

	# Aimed and loaded: the reticle's distance is the charge's reach.
	_arena.rules.local().favor = 500
	_arena._aim_world = CENTERS[3]
	_arena._throw_charge = _throw_charge_for(_arena.player.global_position, CENTERS[3])
	_arena._release_throw()
	_check(_arena._throw_target().is_equal_approx(CENTERS[3]),
		"the loaded throw comes down on the spot the reticle showed (%s)" % str(_arena._throw_target()))
	_land_throw()
	_check(_arena._stone == 4 and _arena._stage == AIM, "a stone on tile 4 starts the lap")
	_check(_arena.player.global_position.is_equal_approx(PAD) and _arena.player.locked,
		"the mortal waits on the start pad, movement locked")
	_check(str(_arena._targets) == "[1, 2, 3, 5, 6, 7, 8, 9, 10]", "the way out skips the stone's tile (%s)" % str(_arena._targets))
	_check(_arena._expected_tile() == 1 and _arena._sweep_low() < 0.0,
		"the first hop expects tile 1, in the right half of the circle")
	await process_frame
	_check(_arena.arrow.visible and _arena.gauge.visible and not _arena.head_label.visible,
		"the arrow and the bar show while aiming - no head count outside the blitz")
	_check(not _arena.throw_aim.visible, "...and the throw's arc is put away")
	_check(_arena.board.stone_tile == 4 and _arena.board.next_tile == 1 and _arena.board.current_tile == 0,
		"the board marks the stone and the next tile")
	_check(_tile_art(1).self_modulate != Color.WHITE and _tile_art(4).self_modulate != Color.WHITE,
		"the chalk sprites take the next tile's colour and the stone's warmth")
	_check(_tile_art(2).self_modulate == Color.WHITE, "...while the plain tiles stay chalk white")
	_check(not _arena.status_label.text.contains("HEAD"),
		"the band leaves the head count off outside the blitz (%s)" % _arena.status_label.text)
	_check(_arena.status_label.text.contains("STONE 4") and _arena.status_label.text.contains("OUT - TILE 1"),
		"the band reads the stone and the next tile (%s)" % _arena.status_label.text)

	# --- the skipping bar maps to the tile -------------------------------------------------
	_arena._head_left = 5.0
	_arena._arrow_angle = (CENTERS[0] - _arena.player.global_position).angle()
	_arena._charge = _charge_for(_arena.player.global_position, CENTERS[0])
	_arena._release_hop()
	_check(_arena._stage == HOP and _arena._hop_tile == 1,
		"the bar's charge lands the hop on the tile it asks for (tile %d)" % _arena._hop_tile)
	_arena._tick_hop(1.0)
	_check(_arena.rules.local().favor == 600, "a clean hop pays 100")
	_check(is_equal_approx(_arena._head_left, 5.0), "outside the blitz a clean hop leaves the count alone")
	_check(_arena._stage == AIM and _arena._expected_tile() == 2, "the next hop expects tile 2")

	# --- the rest of the way out, then the way back ---------------------------------------
	var hops := 0
	while _arena._stage == AIM and not _arena._leg_return and hops < 20:
		_hop_direct(_arena._expected_tile())
		hops += 1
	_check(hops == 8 and _arena._leg_return and _arena._stage == AIM,
		"eight more hops end the way out on the turn tile")
	_check(_arena._current == TURN_TILE, "...on tile 10")
	_check(_arena.rules.local().favor == 1500, "the turn tile pays 200 (%d)" % _arena.rules.local().favor)
	_check(str(_arena._targets) == "[9, 8, 7, 6, 5, 4, 3, 2, 1]", "the way back is every tile below the turn, stone included")
	_check(_arena._sweep_low() > 0.0 and _arena._sweep_high() > PI, "the arrow flips to the left side")
	_check(_arena.callout_label.text.contains("TURN BACK"), "...and the callout says to turn back")
	hops = 0
	while _arena._stage == AIM and hops < 20:
		_hop_direct(_arena._expected_tile())
		hops += 1
	_check(hops == 9, "nine hops to walk the way back")
	_check(_arena._laps == 1 and _arena._stage == HOP and _arena._home_hop, "landing on tile 1 closes the lap and hops home")
	_check(_arena.rules.local().favor == 2550, "the way back pays 100 a hop and 250 for the stone (%d)" % _arena.rules.local().favor)
	_arena._tick_hop(1.0)
	_check(_arena._stage == THROW and not _arena.player.locked and _arena.player.global_position.is_equal_approx(PAD),
		"back on the pad, free to throw again")

	# --- failures ------------------------------------------------------------------------
	_arena.rules.local().favor = 500
	_arena._throw_at(CENTERS[1])
	_land_throw()
	_hop_direct(1)
	_hop_direct(2)
	_check(_arena.rules.local().favor == 400, "landing on your own stone on the way out costs 200")
	_check(_arena._stage == THROW and _arena._stone == 0, "...and the lap restarts from the throw")

	_arena.rules.local().favor = 500
	_arena._throw_at(CENTERS[5])
	_land_throw()
	_hop_direct(3)
	_check(_arena.rules.local().favor == 400 and _arena._stage == THROW,
		"landing on the wrong tile costs 100 and restarts the throw")

	_arena.rules.local().favor = 500
	_arena._throw_at(CENTERS[0])
	_land_throw()
	_hop_off()
	_check(_arena.rules.local().favor == 400 and _arena._stage == THROW,
		"a hop that lands on no tile costs 100")

	# --- a stone on 9 waits for the way back -----------------------------------------------
	_arena.rules.local().favor = 500
	_arena._throw_at(CENTERS[8])
	_land_throw()
	_check(str(_arena._targets) == "[1, 2, 3, 4, 5, 6, 7, 8, 10]",
		"a stone on 9 is skipped on the way out and left for the way back")
	_check(_arena._targets.has(TURN_TILE) and not _arena._targets.has(9),
		"...while the turn tile is always on the way out")
	# The way back opens on tile 9: the first hop picks the stone up.
	_arena._targets.clear()
	for tile in range(TURN_TILE - 1, 0, -1):
		_arena._targets.append(tile)
	_arena._step = 0
	_arena._stone = 9
	_arena._leg_return = true
	_arena._current = TURN_TILE
	_arena._stage = AIM
	_arena.player.global_position = TURN
	_hop_direct(9)
	_check(_arena.rules.local().favor == 750 and _arena._pickup and _arena._stage == AIM,
		"the way back's first hop collects the stone on 9 for 250")
	_check(str(_arena._targets) == "[9, 8, 7, 6, 5, 4, 3, 2, 1]", "...with the full way back")

	# --- the head count (blitz only) -------------------------------------------------------
	_arena._reset_to_throw()
	_arena.rules.local().favors.clear()
	_arena.rules.local().first_cleanse_used = false
	_arena.rules.local().stun_time = 0.0
	_arena._was_stunned = false
	_arena._blitz = false
	_arena._head_left = 5.0
	_arena._tick_head(1.0)
	_check(is_equal_approx(_arena._head_left, 5.0) and is_equal_approx(_arena.rules.local().stun_time, 0.0),
		"outside the blitz the head count does not run")
	_arena._blitz = true
	_arena._head_left = 0.4
	_arena._tick_head(0.5)
	_check(_arena._stage == THROW and _arena._stone == 0 and is_equal_approx(_arena._head_left, _arena.head_time),
		"a spent head count restarts the lap with a fresh 12 s")
	_check(is_equal_approx(_arena.rules.local().stun_time, 3.0), "...and stuns for 3 s")
	_arena._watch_afflictions(DT)
	_check(_arena.player.is_stunned(), "the rules' stun reaches the mortal's body")
	_arena.player._stun = 0.0
	_arena.rules.local().stun_time = 0.0

	_arena._throw_at(CENTERS[3])
	_arena._was_stunned = false
	_arena.player.stun(2.0)
	_arena._tick_piko(DT)
	_check(_arena._was_stunned and _arena._stage == THROW and _arena._stone == 0,
		"a stun from any side drops the lap where it stands")
	_arena.player._stun = 0.0
	_arena.rules.local().stun_time = 0.0
	_arena._tick_piko(DT)
	_check(not _arena._was_stunned, "...and the count resumes when they wake")

	# --- the blitz -------------------------------------------------------------------------
	_arena._reset_to_throw()
	_arena._trial_time = 31.0
	_arena._update_blitz(DT)
	_check(not _arena._blitz and not _arena.blitz_glow.visible, "with 31 s left there is no blitz yet")
	_arena._trial_time = 30.0
	_arena._update_blitz(DT)
	_check(_arena._blitz and _arena.blitz_glow.visible, "at 30 s left the blitz is on and the field pulses")
	_check(is_equal_approx(_arena._head_left, _arena.head_time), "the blitz opens the head count at 12 s")
	_arena._sync_nodes()
	_check(_arena.head_label.visible and _arena.head_label.text == "12s",
		"the count sits over the mortal's head in the blitz")
	_arena._arrow_angle = 0.0
	_arena._arrow_dir = 1.0
	_arena._tick_arrow(1.0)
	_check(is_equal_approx(_arena._arrow_angle, PI * 0.5), "in the blitz the arrow sweeps 1.5x faster")
	_arena.rules.local().favor = 500
	_arena._throw_at(CENTERS[3])
	_land_throw()
	_arena._head_left = 5.0
	_hop_direct(1)
	_check(_arena.rules.local().favor == 620, "every clean hop pays 20 more in the blitz")
	_check(is_equal_approx(_arena._head_left, 6.5), "a clean hop feeds the head count 1.5 s in the blitz")
	_arena._blitz = false
	_arena._arrow_angle = 0.0
	_arena._arrow_dir = 1.0
	_arena._tick_arrow(1.0)
	_check(is_equal_approx(_arena._arrow_angle, deg_to_rad(60.0)), "...and the normal sweep is 60 degrees a second")
	_arena._trial_time = 999.0
	_arena._update_blitz(DT)
	_check(not _arena._blitz and not _arena.blitz_glow.visible, "the blitz ends with the trial clock")
	_arena._sync_nodes()
	_check(not _arena.head_label.visible, "...and the head count leaves the field")
	_arena._reset_to_throw()

	# --- the head effect timer --------------------------------------------------------------
	_arena._blitz = true
	_arena._stage = AIM
	_arena._head_left = 3.0
	_arena.player._stun = 0.0
	_check(_arena.arena_local_effects().size() == 1, "under 4 s the head count shows on the field")
	_arena._head_left = 7.0
	_check(_arena.arena_local_effects().is_empty(), "above 4 s it stays quiet")
	_arena._blitz = false
	_arena._head_left = _arena.head_time

	# --- the favors ---------------------------------------------------------------------
	_arena.rules.local().favors.clear()
	_arena.rules.local().first_cleanse_used = false
	_arena.rules.local().stun_time = 0.0
	_arena._was_stunned = false
	_arena.player._stun = 0.0

	# The First Cleanse: the first stun of the trial never lands.
	_arena.rules.bestow_favor(Gods.favor_by_id(&"first_cleanse"))
	_arena._blitz = true
	_arena._head_left = 0.1
	_arena._tick_head(0.2)
	_check(_arena.rules.local().stun_time == 0.0 and _arena.callout_label.text == "CLEANSED",
		"First Cleanse cancels the head count's stun")
	_arena.rules.local().favors.clear()
	_arena.rules.local().first_cleanse_used = false

	# Departure Is Not Now: 15% shorter.
	_arena.rules.bestow_favor(Gods.favor_by_id(&"departure_is_not_now"))
	_arena._head_left = 0.1
	_arena._tick_head(0.2)
	_check(is_equal_approx(_arena.rules.local().stun_time, 2.55),
		"Departure makes a 3 s stun 15%% shorter (%.2f)" % _arena.rules.local().stun_time)
	_arena.rules.local().favors.clear()
	_arena.rules.local().stun_time = 0.0
	_arena._blitz = false

	# Guilty Pleasure: FAVOR lost while stunned costs less.
	_arena.rules.bestow_favor(Gods.favor_by_id(&"guilty_pleasure"))
	_arena.rules.local().favor = 1000
	_arena.rules.local().stun_time = 3.0
	_arena.score_favor(-100, "check loss")
	_check(_arena.rules.local().favor == 980, "Guilty Pleasure makes a 100 loss cost 20 while stunned")
	_arena.rules.local().stun_time = 0.0
	_arena.score_favor(-100, "check loss")
	_check(_arena.rules.local().favor == 880, "...and the full 100 once the stun is over")
	_arena.rules.local().favors.clear()

	# A Little More Structure: the ring.
	_arena.player.global_position = Vector2(620.0, 450.0)
	_arena._apply_skill_effect(Gods.favor_by_id(&"a_little_more_structure"), _arena._my_id)
	_check(_arena._structures.size() == 1 and _arena._structure_nodes.size() == 1,
		"E opens a ring where the caster stands, and draws it")
	_arena._tick_structures(2.9)
	_check(_arena._structures.size() == 1 and _arena.rules.local().stun_time == 0.0,
		"inside the ring the countdown runs harmlessly")
	_arena.player.global_position = Vector2(770.0, 450.0)
	_arena._tick_structures(0.2)
	_check(_arena._structures.is_empty(), "the ring closes when the count ends")
	_check(is_equal_approx(_arena.rules.local().stun_time, 3.0), "a mortal still outside is stunned for 3 s")
	_check(is_equal_approx(_arena.rules.mortal(2).stun_time, 3.0), "and every rival who could not step in is judged too")

	# A Little More Control: the Q window.
	_arena.rules.bestow_favor(Gods.favor_by_id(&"a_little_more_control"))
	_arena._apply_skill_effect(Gods.favor_by_id(&"a_little_more_control"), _arena._my_id)
	_check(is_equal_approx(_arena.rules.control_bonus(_arena._my_id), 1.0),
		"Q opens a window that lengthens the control they hand out")
	_check(is_equal_approx(_arena.rules.stun_mortal(2, 3.0, _arena._my_id), 4.0),
		"a stun on a rival lasts 1 s longer")
	_check(is_equal_approx(_arena.rules.stun_mortal(1, 3.0, _arena._my_id), 3.0),
		"...but your own stuns are not stretched")
	_arena.rules.mortal(2).rooted_time = 0.0
	_arena.rules.cast_down_to_homeland(_arena._my_id, Gods.favor_by_id(&"down_to_homeland"))
	_check(is_equal_approx(_arena.rules.mortal(2).rooted_time, 4.0),
		"...and so does a root, 3 s + 1 s")

	# Lifeline: someone else's stun pays.
	var rules := GodMatch.new()
	view.add_child(rules)
	rules.setup(Gods.sidapa(), "ME", ["A", "B"])
	rules.bestow_favor(Gods.favor_by_id(&"lifeline"))
	rules.mortal(1).favor = 0
	_check(is_equal_approx(rules.stun_mortal(2, 3.0), 3.0), "a rival's stun lands")
	_check(rules.mortal(1).favor == 30, "Lifeline pays 30 FAVOR to the mortal who watched")
	rules.queue_free()

	# Time Is Now: every stun is worth FAVOR when the trial closes.
	rules = GodMatch.new()
	view.add_child(rules)
	rules.setup(Gods.sidapa(), "ME", [])
	rules.bestow_favor(Gods.favor_by_id(&"time_is_now"))
	rules.mortal(1).favor = 0
	rules.stun_mortal(1, 1.0)
	rules.stun_mortal(1, 1.0)
	_check(rules.mortal(1).stun_records == 2, "every stun is recorded")
	rules.end_trial()
	_check(rules.mortal(1).favor == 100, "Time Is Now pays 50 for each at the end of the trial")
	rules.queue_free()

	print("Sidapa arena checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


# A tile's chalk sprite.
func _tile_art(tile: int) -> Sprite2D:
	var node: Node2D = _arena.get_node("ArenaField/Tile%d" % tile) as Node2D
	return node.get_node("Background") as Sprite2D


# Read the drawn court out of the arena before the run: the checks follow the
# scenes, so a designer's drag or a re-numbered tile is what gets played.
func _read_court() -> void:
	for index in range(TURN_TILE):
		var tile: Node2D = _arena.get_node("ArenaField/Tile%d" % (index + 1)) as Node2D
		CENTERS.append(tile.global_position)
	TURN = CENTERS[TURN_TILE - 1]
	PAD = (_arena.get_node("ArenaField/Pad") as Node2D).global_position


# The charge the skipping bar needs to carry from `from` onto `to`.
func _charge_for(from: Vector2, to: Vector2) -> float:
	return clampf((from.distance_to(to) - _arena.hop_min) / maxf(1.0, _arena.hop_max - _arena.hop_min), 0.0, 1.0)


# The charge the loaded throw needs to reach `to` from `from`.
func _throw_charge_for(from: Vector2, to: Vector2) -> float:
	return clampf((from.distance_to(to) - _arena.throw_min) / maxf(1.0, _arena.throw_max - _arena.throw_min), 0.0, 1.0)


# Let the thrown stone finish its flight (a miss bounces back: a second flight).
func _land_throw() -> void:
	var guard := 0
	while _arena._stage == FLIGHT and guard < 10:
		_arena._tick_flight(1.0)
		guard += 1


# Land the current hop on `tile` at once (no arc to wait for).
func _hop_direct(tile: int) -> void:
	_arena._hop_tile = tile
	_arena._hop_from = _arena.player.global_position
	_arena._hop_to = _center(tile)
	_arena._hop_left = 0.0
	_arena._hop_total = 1.0
	_arena._home_hop = false
	_arena._stage = HOP
	_arena._tick_hop(1.0)


func _center(tile: int) -> Vector2:
	return CENTERS[tile - 1] if tile <= CENTERS.size() else TURN


func _hop_off() -> void:
	_arena._hop_tile = 0
	_arena._hop_from = _arena.player.global_position
	_arena._hop_to = _arena.player.global_position + Vector2(0.0, -80.0)
	_arena._hop_left = 0.0
	_arena._hop_total = 1.0
	_arena._home_hop = false
	_arena._stage = HOP
	_arena._tick_hop(1.0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
