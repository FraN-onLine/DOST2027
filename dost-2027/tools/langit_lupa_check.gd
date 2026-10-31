extends SceneTree

# Validation: Mapulon & Ikapati's Langit Lupa. The field is sized for the mortals
# playing (and a client draws the host's). At GO the gods are the Taya: their tag
# hands Taya to that mortal and moves no FAVOR, they leave after it, they keep no
# time, pay no drain and earn nothing from a chant, they never stand on a Langit,
# the safety valve hunts the richest runner on the Lupa (and re-picks when that
# mortal leaves), and their state rides the arena tick. With god_starts_as_taya
# off the rhyme picks the richest mortal as Taya (ties random); mortals + 1 Langit, shared by any number of runners for
# as long as they like; the Taya's chant roots it and blocks tags, breaks on a
# wrong key or a missed beat, and on ALIS! closes each runner's Langit to them
# only, shoves off whoever stays and pays the Taya; the host ignores chant
# messages that are not the Taya's or out of order; the Taya is never safe and is
# pushed off a Langit; crossings, close calls and streaks pay; a tag moves
# tag_steal; tagged_mercy stops a tag-back; seasons move every Langit (clear of
# the UI strip and the Taya) and reopen them; Time as Taya, its drain and the
# payout (shown in the results' bonus); the 60s round; the dash (only here); and
# the earthquakes (25-45 s apart, 3 s of shaking with the walk keys inverted,
# mirrored from the host).
# Run: godot --headless --path <project> -s res://tools/langit_lupa_check.gd

const DT := 0.25  # exact in binary, so four steps are exactly one second
const FAR := Vector2(1080, 560)

var _arena: LangitLupaArena
var _rules: GodMatch
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
	_arena = load("res://scenes/gods/mapulon_ikapati/LangitLupaArena.tscn").instantiate()
	view.add_child(_arena)
	await _frames(2)
	_rules = _arena.rules
	var guard := 0
	while _arena.dialogue.is_active() and guard < 40:
		_arena.dialogue.advance()
		guard += 1
	_check(_arena.god.id == Gods.MAPULON_IKAPATI, "the arena belongs to Mapulon & Ikapati")
	_check(not _arena.separate_players() and _arena.shares_mortal_positions(), "Langit Lupa is a shared field")
	_check(is_equal_approx(_arena.trial_time, 60.0), "a standalone round lasts 60s")
	_check(_arena._bots.size() == 2 and not _rules.simulate_rivals, "solo: two bots take the rivals' places (and the quiet FAVOR trickle is off)")

	# --- the field is the scene's Border, whatever the number of mortals -----------------
	var authored: Node = load("res://scenes/gods/mapulon_ikapati/LangitLupaArena.tscn").instantiate()
	var authored_points: PackedVector2Array = (authored.get_node("ArenaField/Border") as Line2D).points
	authored.free()
	var drawn: Rect2 = _arena.field_root.authored_rect()
	_check(_arena._field.is_equal_approx(drawn) and is_equal_approx(_arena._field.size.x, 868.0),
		"the field is the authored Border, 868 px wide (%s)" % str(_arena._field))
	_check(_arena.field_root.border.points == authored_points, "the Border's points are untouched by _ready (%s)" % str(_arena.field_root.border.points))
	_check(_arena.player.bounds == _arena._field, "the mortal walks inside it")
	for count in [2, 4, 3]:
		for id in [2, 3, 4]:
			if id > count and _rules.mortal(id) != null:
				_rules.remove_mortal(id)
		for id in range(2, count + 1):
			_rules.ensure_mortal(id, "MORTAL %d" % id)
		_arena._read_field()
		_check(_arena._field.is_equal_approx(drawn) and _arena.field_root.border.points == authored_points and _arena.langit_count(count) == count + 1,
			"%d mortals play on the same field and the Border stays as drawn (%d Langit)" % [count, _arena.langit_count(count)])
	# a client takes the host's field
	var client_field := Rect2(400, 360, 500, 200)
	_arena._apply_layout({"field": client_field})
	_check(_arena._field == client_field and _arena.player.bounds == client_field and _arena.field_root.border.points == authored_points,
		"a client walks the host's field and does not redraw the Border (%s)" % str(_arena._field))
	_arena._read_field()
	_check(_arena._field.is_equal_approx(drawn), "(back to the authored field)")

	# --- the countdown is the rhyme, and the rules card shows on a first visit ----------
	_arena._start_countdown()
	_check(_arena._langits.size() == 4, "(the countdown lays out the Langit: 3 mortals -> 4)")
	_arena._show_banner("3", Color.WHITE)
	var first: String = _arena.hud.banner_label.text
	_arena._show_banner("2", Color.WHITE)
	var second: String = _arena.hud.banner_label.text
	_arena._show_banner("1", Color.WHITE)
	_check(first == "LANGIT..." and second == "LUPA..." and _arena.hud.banner_label.text == "IMPYERNO!",
		"the 3-2-1 is the rhyme: LANGIT... LUPA... IMPYERNO! (%s / %s / %s)" % [first, second, _arena.hud.banner_label.text])
	_arena._refresh_hud(0.0)
	_check(_arena.rules_card.visible, "the rules card shows through the countdown of a first visit")

	# --- the gods start as Taya ----------------------------------------------------
	_check(_arena.god_starts_as_taya, "by default the gods start as Taya")
	_check((_arena.get_node("LangitHud/RulesCard/Lines/Lupa") as Label).text == LangitLupaArena.RULES_LUPA_GODS,
		"the rules card says Mapulon & Ikapati are Taya first")
	_set_favor(100, 500, 200)
	_arena._start_trial()
	_check(_arena.taya_id() == LangitLupaArena.GOD_TAYA, "at GO Mapulon & Ikapati are the Taya, not a mortal (%d)" % _arena.taya_id())
	_check(_arena.hud.banner_label.text == "MAPULON & IKAPATI ARE TAYA!", "the banner says the gods are Taya (%s)" % _arena.hud.banner_label.text)
	_check(_rules.mortal(LangitLupaArena.GOD_TAYA) == null and _arena._field.has_point(_arena._god_at),
		"the gods stand on the field, but are no GodMatch mortal")
	_arena._process(0.0)
	_check(_arena._god_body.visible and _arena.taya_marker.visible, "their body is drawn, wearing the Taya marker")
	_check(not _arena._god_body.sprite.visible, "the god body's mortal sprite is hidden")
	var body: IkapatiTaya = _arena._god_body
	_check(body.scene_file_path == "res://scenes/gods/mapulon_ikapati/IkapatiTaya.tscn",
		"the god body is the IkapatiTaya scene (%s)" % body.scene_file_path)
	var god_art := body.art
	var clips := god_art.sprite_frames.get_animation_names()
	clips.sort()
	_check(clips == PackedStringArray(["chasing", "idle"]), "...its one SpriteFrames holds idle / chasing (%s)" % str(clips))
	_check(god_art.is_playing() and god_art.animation == &"idle" and god_art.visible, "...standing still it plays idle (%s)" % god_art.animation)
	var stands: float = _arena.god_height
	var frame_height := float(god_art.sprite_frames.get_frame_texture(&"idle", 0).get_height())
	var figure := _figure_height(god_art.sprite_frames.get_frame_texture(&"idle", 0))
	_check(is_equal_approx(stands, IkapatiTaya.MORTAL_HEIGHT) and absf(figure * god_art.scale.y - IkapatiTaya.MORTAL_HEIGHT) <= 4.0,
		"...the drawn figure stands as tall as a mortal (%.0f px; frame padding ignored)" % (figure * god_art.scale.y))
	_check(is_equal_approx(body.look.global_position.y - body.global_position.y, body.shadow.position.y)
		and is_equal_approx(god_art.position.y + frame_height * 0.5 * god_art.scale.y, 0.0),
		"...with its feet on the line a mortal's feet are on")
	_check(body.ring != null and body.ring.default_color == UITokens.god_accent(_arena.god), "...over a ring in the pair's accent")
	_check(not _arena.god_overseer.visible, "the overseer Ikapati is hidden while the god body is on the field")
	_check(body.look.scale.x < 1.0, "the god body pops in (puff: scale %.2f and growing)" % body.look.scale.x)
	_arena._god_body.global_position = _arena._god_at
	_arena._god_body._last_position = _arena._god_at
	_arena._god_body.global_position += Vector2(-20, 0)
	_arena._god_body._update_facing()
	_arena._process(0.0)
	_check(bool(god_art.flip_h), "she turns to face the way they walk (left)")
	_arena._god_at += Vector2(-6, 0)
	_arena._process(0.0)
	_check(god_art.animation == &"chasing", "moving, the body switches to the chasing clip (%s)" % god_art.animation)
	_arena._process(0.0)
	_check(god_art.animation == &"idle", "stopping again, it settles back to idle (%s)" % god_art.animation)
	_arena._chanting = true
	_arena._process(0.0)
	_check(god_art.animation == &"idle", "chanting before a chant clip lands, it falls back to idle (%s)" % god_art.animation)
	_arena._chanting = false
	_check(is_equal_approx(_arena.taya_marker.global_position.y, _arena._god_body.global_position.y - _arena._god_lift),
		"the Taya marker sits above her head, not over it")

	# --- the first Taya, the old rule ------------------------------------------------
	_arena.god_starts_as_taya = false
	_set_favor(100, 500, 200)
	_arena._start_trial()
	_check(_arena.taya_id() == 2, "god_starts_as_taya = false: the mortal with the most FAVOR starts as Taya")
	_check(_arena.hud.banner_label.text == "TAYA: MORTAL 2!", "the rhyme lands on them: \"TAYA: MORTAL 2!\" (%s)" % _arena.hud.banner_label.text)
	_arena._refresh_hud(0.0)
	_check(not _arena.rules_card.visible, "the rules card is gone at GO")
	var seen := {}
	for attempt in range(40):
		_set_favor(100, 500, 500)
		_arena._taya = -1
		_arena._start_trial()
		seen[_arena.taya_id()] = true
	_check(seen.size() == 2 and seen.has(2) and seen.has(3), "a tie for the most FAVOR goes to one of the tied, at random")
	_set_favor(100, 500, 200)
	_rules.mortal(2).granary = 400
	_rules.mortal(2).favor = 150
	_arena._start_trial()
	_check(_arena.taya_id() == 3, "FAVOR stored in Kamalig does not count towards the first Taya")
	_rules.mortal(2).granary = 0

	# --- the Taya walks 10% faster: the player, and a bot Taya --------------------------
	_reset(1, [])
	_arena._update_movement_favors(0.0)
	_check(is_equal_approx(_arena._base_move_speed, 215.0) and is_equal_approx(_arena.player.move_speed, 215.0 * 1.1),
		"the player as Taya walks at 215 x 1.1 (%.1f)" % _arena.player.move_speed)
	_arena.set_taya(2)
	_arena._update_movement_favors(0.0)
	_check(is_equal_approx(_arena.player.move_speed, 215.0), "...and back at 215 once the Taya is passed on (%.1f)" % _arena.player.move_speed)
	_arena._tagback = 0.0
	_arena._invuln.clear()
	var hunter: ArenaMortal = _arena._bots[2]
	hunter.global_position = _arena._field.get_center()
	_put(1, _arena._field.get_center() + Vector2(200, 0))
	_put(3, _arena._field.get_center() + Vector2(0, 200))
	_arena._bots[3].global_position = _arena._field.get_center() + Vector2(0, 200)
	_arena._move_bots(0.1)
	var walked := hunter.global_position.distance_to(_arena._field.get_center())
	_check(is_equal_approx(walked, _arena.bot_speed * 1.1 * 0.1), "a bot Taya gets the same bonus (%.2f px in 0.1 s)" % walked)

	# --- the E afflictions reach the bots too ------------------------------------------
	_reset(2, [])
	_rules.mortal(2).drowsy_time = 2.0
	hunter.global_position = _arena._field.get_center()
	_put(1, _arena._field.get_center() + Vector2(200, 0))
	_arena._bots[3].global_position = _arena._field.get_center() + Vector2(0, 200)
	_arena._move_bots(0.1)
	var drowsy_walked := hunter.global_position.distance_to(_arena._field.get_center())
	_check(is_equal_approx(drowsy_walked, _arena.bot_speed * 1.1 * Arena.DROWSY_SPEED * 0.1),
		"a drowsy bot Taya walks at half speed (%.2f px in 0.1 s)" % drowsy_walked)
	_rules.mortal(2).drowsy_time = 0.0
	_rules.mortal(2).rooted_time = 3.0
	hunter.global_position = _arena._field.get_center()
	_arena._move_bots(0.1)
	var shadow: Vector2 = _arena._bot_root_shadow.get(2, Vector2.INF)
	_check(hunter.global_position.distance_to(_arena._field.get_center()) > 0.01 and _arena._bot_root_tether.has(2)
		and shadow != Vector2.INF, "a rooted bot keeps walking, tethered to its shadow")
	_rules.mortal(2).rooted_time = 0.0
	_arena._move_bots(0.1)
	_check(not _arena._bot_root_tether.has(2) and _arena._bot_root_drag.has(2),
		"when the root lifts, the bot is dragged back towards its shadow")
	var drag_guard := 0
	while _arena._bot_root_drag.has(2) and drag_guard < 20:
		_arena._move_bots(0.1)
		drag_guard += 1
	_check(hunter.global_position.distance_to(shadow) < 1.0,
		"...and arrives on it (%.1f px off)" % hunter.global_position.distance_to(shadow))

	# From here the bots stand where the check puts them.
	for bot in _arena._bots.values():
		bot.queue_free()
	_arena._bots.clear()

	# --- Langit ------------------------------------------------------------------------
	for mortals in [2, 3, 4]:
		_check(_arena.langit_count(mortals) == mortals + 1, "%d mortals -> %d Langit" % [mortals, mortals + 1])
	var spot := Vector2(500, 300)
	var other_spot := Vector2(800, 300)
	_reset(3, [spot, other_spot])
	_put(1, spot + Vector2(-12, 0))
	_put(2, spot + Vector2(12, 5))
	_check(_arena.is_safe(1) and _arena.is_safe(2), "two runners can be safe on the same Langit")
	var edge: Rect2 = _arena.langit_rect(0)
	_put(2, Vector2(edge.end.x - 2.0, edge.get_center().y))
	_check(_arena.is_safe(2), "standing on the edge of the prefab's hitbox still counts")
	_put(2, spot + Vector2(12, 5))
	_put(3, spot + Vector2(0, 50))  # the Taya, right next to them
	for step in range(20):
		_arena.arena_rules_tick(DT)
	_check(_arena.is_safe(1) and _arena.is_safe(2) and _arena.taya_id() == 3, "...and they stay safe there, with no chant, for as long as they like (5s)")
	_put(3, spot)
	_check(not _arena.is_safe(3), "the Taya never counts as safe, even on a Langit")
	var pushed: Vector2 = _arena._push_out(spot + Vector2(10, 4))
	var rect: Rect2 = _arena.langit_rect(0)
	_check(not rect.has_point(pushed) and pushed.distance_to(spot + Vector2(10, 4)) <= rect.size.y * 0.5 + 1.0,
		"a Taya inside a Langit is pushed back out to the nearest edge (%s)" % str(pushed))
	_reset(1, [spot, other_spot])
	_put(1, spot)
	_arena._process(0.0)
	_check(not rect.has_point(_arena.player.global_position), "...on the Taya's own screen, every frame")

	# --- the Langit prefabs: hitbox safe zone, one pillar clip each --------------------------
	var lit: Array = _arena.langits_root.get_children()
	var scenes := ["res://scenes/gods/mapulon_ikapati/Langit1.tscn", "res://scenes/gods/mapulon_ikapati/Langit2.tscn"]
	_check(lit.size() >= 2 and (lit[0] as Node).scene_file_path in scenes,
		"the Langit are the Langit1/Langit2 scenes (%s)" % [(lit[0] as Node).scene_file_path if not lit.is_empty() else "none"])
	var boxes: Array[Rect2] = []
	for path in scenes:
		var probe: Node = (load(path) as PackedScene).instantiate()
		var probe_shape := probe.get_node_or_null("SafeArea/CollisionShape2D") as CollisionShape2D
		boxes.append(Rect2(probe_shape.position - (probe_shape.shape as RectangleShape2D).size * 0.5, (probe_shape.shape as RectangleShape2D).size))
		probe.free()
	_check(boxes[0].is_equal_approx(boxes[1]) and boxes[0].is_equal_approx(_arena._langit_box),
		"both pillars carry the same authored hitbox (%s / %s)" % [str(boxes[0]), str(boxes[1])])
	_check(_arena.langit_rect(0).is_equal_approx(Rect2(_arena._langits[0] + boxes[0].position, boxes[0].size)),
		"the safe zone is the prefab's hitbox, not a code rectangle (%s)" % str(_arena.langit_rect(0)))
	var pillar := (lit[0] as Node).get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var own_clip := StringName("pillar1" if (lit[0] as Node).scene_file_path.ends_with("Langit1.tscn") else "pillar2")
	_check(pillar != null and pillar.sprite_frames.get_animation_names().size() == 1 and pillar.sprite_frames.has_animation(own_clip),
		"...each scene carrying only its own pillar clip (%s)" % own_clip)
	_reset(3, [spot, other_spot])
	_arena._draw_langits(0.0)
	lit = _arena.langits_root.get_children()
	pillar = (lit[0] as Node).get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	_arena._cloud_state[0] = LangitLupaArena.Cloud.FORMING
	_arena._cloud_timer[0] = _arena.langit_fade_in
	_arena._cloud_look[0] = -1
	_arena._draw_langits(0.0)
	_check(pillar.is_playing() and pillar.animation in [&"pillar1", &"pillar2"] and pillar.frame == pillar.sprite_frames.get_frame_count(pillar.animation) - 1,
		"a forming Langit spawns out of rubble, playing its clip backwards (%s, frame %d)" % [pillar.animation, pillar.frame])
	_arena._cloud_state[0] = LangitLupaArena.Cloud.CRUMBLING
	_arena._cloud_timer[0] = _arena.crumble_time
	_arena._draw_langits(0.0)
	_check(pillar.is_playing() and pillar.frame >= 1 and pillar.frame < pillar.sprite_frames.get_frame_count(pillar.animation),
		"a crumble interrupts the rise, falling forwards (%s, frame %d)" % [pillar.animation, pillar.frame])
	_arena._cloud_state[0] = LangitLupaArena.Cloud.SOLID
	_arena._cloud_look[0] = -1
	_arena._draw_langits(0.0)
	_check(not pillar.is_playing() and pillar.frame == 0, "...and a solid Langit settles standing")
	_arena._cloud_state[0] = LangitLupaArena.Cloud.CRUMBLING
	_arena._cloud_timer[0] = _arena.crumble_time
	_arena._draw_langits(0.0)
	_check(pillar.is_playing() and pillar.frame >= 1 and pillar.frame < pillar.sprite_frames.get_frame_count(pillar.animation),
		"a crumbling Langit falls forwards from the standing frame (%s, frame %d)" % [pillar.animation, pillar.frame])
	_arena._cloud_anim[0] = 1
	_arena._cloud_look[0] = -1
	_arena._cloud_state[0] = LangitLupaArena.Cloud.FORMING
	_arena._draw_langits(0.0)
	lit = _arena.langits_root.get_children()
	pillar = (lit[0] as Node).get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	_check((lit[0] as Node).scene_file_path.ends_with("Langit2.tscn") and pillar.animation == &"pillar2",
		"the host's picked variant is the scene played (%s, %s)" % [(lit[0] as Node).scene_file_path, pillar.animation])
	_arena._cloud_anim[0] = 0
	_arena._cloud_look[0] = -1
	_arena._cloud_state[0] = LangitLupaArena.Cloud.SOLID
	_arena._draw_langits(0.0)
	var tick_anim: Dictionary = _arena.arena_tick_fields()
	_check(tick_anim.has("cloud_anim") and (tick_anim["cloud_anim"] as Array)[0] == 0, "the host's variant pick travels in the tick")

	# --- the hop starts just before the safe zone --------------------------------------------
	_reset(3, [spot, other_spot])
	_put(1, Vector2(650, 450))
	_arena._process(0.0)
	var before_jump: StringName = _arena.player.sprite.animation
	var safe: Rect2 = _arena.langit_rect(0)
	var too_far := Vector2(safe.position.x - _arena.hop_lead - 5.0, safe.get_center().y)
	_put(1, too_far)
	_arena._process(0.0)
	_check(not safe.has_point(too_far) and _arena.player.sprite.animation != &"jump",
		"a step outside the hop's lead does not start the jump clip (%s)" % _arena.player.sprite.animation)
	_put(1, Vector2(safe.position.x - _arena.hop_lead * 0.5, safe.get_center().y))
	_arena._process(0.0)
	_check(_arena.player.sprite.animation == &"jump" and before_jump != &"jump" and _arena._jump_on == 0,
		"the hop starts slightly before the hitbox (%s -> %s)" % [before_jump, _arena.player.sprite.animation])
	_put(1, safe.get_center())
	_arena._process(0.0)
	_check(_arena.player.sprite.animation == &"jump" and _arena._jump_on == 0,
		"then entering the hitbox does not restart the hop (%s)" % _arena.player.sprite.animation)

	# --- the chant: rooted, no tags, no dash ----------------------------------------------
	_reset(1, [spot, other_spot])
	_put(1, Vector2(650, 450))
	_put(2, Vector2(660, 450))  # on the Lupa, within reach
	_put(3, FAR)
	_check(_arena.start_chant(), "the Taya can start a chant")
	_check(_arena._chanting and _arena.player.locked, "a chant roots the Taya")
	_arena._check_tag()
	_check(_arena.taya_id() == 1, "a chanting Taya cannot tag")
	_check(not _arena.try_dash(), "...nor dash")
	_check(not _arena.start_chant(), "a second chant cannot start over the first")
	# a wrong key breaks it
	_arena.chant_key((_arena._my_chant[0] + 1) % 4)
	_check(not _arena._chanting and _arena._chant_broken == 0, "a wrong key breaks the chant (on its first word)")
	_check(_arena._chant_cd > 0.0 and is_equal_approx(_arena._chant_cd, _arena.chant_cooldown), "...and the cooldown starts anyway")
	_check(_arena.player.locked and _arena._root_left > 0.0, "the Taya stumbles, still rooted")
	_arena._check_tag()
	_check(_arena.taya_id() == 1, "...and still cannot tag")
	_arena._tick_my_chant(_arena.chant_fail_stun + 0.01)
	_arena._tick_chant(_arena.chant_fail_stun + 0.01)
	_check(not _arena.player.locked, "after the stumble the Taya moves again")
	_check(not _arena.start_chant(), "a chant waits for the cooldown")
	# a missed beat breaks it
	_arena._chant_cd = 0.0
	_check(_arena.start_chant(), "(a new chant once the cooldown is ready)")
	_arena.chant_key(_arena._my_chant[0])
	_check(_arena._chant_step == 1, "a right key lights the next word")
	_arena._tick_my_chant(_arena.chant_beat - 0.1)
	_check(_arena._chanting, "the beat is not missed yet")
	_arena._tick_my_chant(0.2)
	_check(not _arena._chanting and _arena._chant_broken == 1 and _arena._chant_cd > 0.0, "a missed beat breaks it (on the word it was on) and starts the cooldown")
	_arena._tick_my_chant(1.0)
	_arena._tick_chant(1.0)
	# RIGHT CLICK, and never while a dialogue or the God's Due menu is open
	_arena._chant_cd = 0.0
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	_arena.dialogue.show_lines([{"speaker": "TEST", "color": Color.WHITE, "text": "A LINE"}])
	_arena._input(right)
	_check(not _arena._chanting, "RIGHT CLICK does not chant while a dialogue is open")
	_arena.dialogue.close_now()
	_arena._toggle_due_menu()
	_arena._input(right)
	_check(not _arena._chanting, "...nor while the God's Due menu is open")
	_arena.due_menu.close()
	_arena._input(right)
	_check(_arena._chanting, "during play RIGHT CLICK starts the chant")
	for word in range(_arena.chant_length):
		var key := InputEventAction.new()
		key.action = LangitLupaArena.MOVE_ACTIONS[_arena._my_chant[word]]
		key.pressed = true
		_arena._input(key)
	_check(not _arena._chanting and _arena._chant_broken == -1 and _arena._chant_cd > 0.0 and not _arena.player.locked,
		"the move keys answer the prompts: a full chant ends it, unroots the Taya and starts the cooldown")

	# --- the chant from a remote Taya: the host checks every message ---------------------------
	_reset(2, [spot, other_spot])
	_put(2, Vector2(650, 300))     # the Taya, between the two Langit
	_put(1, spot)                  # our mortal sits on Langit 0
	_put(3, Vector2(650, 500))     # on the Lupa
	_set_favor(500, 500, 500)
	_arena._on_chant_message(3, "start", 0)
	_check(not _arena._chanting, "the host ignores a chant from a mortal who is not the Taya")
	_arena._season_timer = _arena.shift_warning * 0.5
	_arena._on_chant_message(2, "start", 0)
	_check(not _arena._chanting, "a chant cannot start during the crumble warning")
	_arena._season_timer = 1000.0
	_arena._on_chant_message(2, "start", 0)
	_check(_arena._chanting, "the Taya's start is accepted")
	_arena._on_chant_message(2, "step", 2)
	_check(_arena._chant_step == 0, "a step out of order is ignored")
	_arena._on_chant_message(3, "step", 1)
	_check(_arena._chant_step == 0, "so is a step from somebody else")
	_arena._on_chant_message(2, "step", 1)
	_arena._on_chant_message(2, "result", 1)
	_check(not _arena._chanting and _arena.swap_left(1) == 0.0 and _arena._chant_cd > 0.0,
		"a \"success\" that skipped words is a broken chant, not an ALIS")
	_arena._chant_cd = 0.0
	_arena._root_left = 0.0
	_arena._on_chant_message(2, "start", 0)
	for word in range(1, _arena.chant_length + 1):
		_arena._on_chant_message(2, "step", word)
	_arena._on_chant_message(2, "result", 1)
	_check(is_equal_approx(_arena.swap_left(1), _arena.swap_time), "ALIS! gives the runner on a Langit swap_time to leave")
	_check(_arena.is_closed_for(1, 0) and not _arena.is_closed_for(3, 0), "their Langit is closed to them, and to nobody else")
	_check(_arena.langit_index_at(3, spot) == 0 and _arena.langit_index_at(1, spot) == -1, "...it still counts for the others")
	_check(_arena.swap_left(3) == 0.0 and not _arena._closed.has(3), "a runner who was on the Lupa is left alone")
	_check(_rules.mortal(2).favor == 500 + _arena.chant_favor, "the Taya is paid chant_favor per runner forced off (%d)" % _rules.mortal(2).favor)
	_check(_arena.is_safe(1), "while the swap clock runs the runner is still safe")
	_arena._on_chant_message(2, "start", 0)
	_check(not _arena._chanting, "the next chant waits for the cooldown")
	_arena._tick_swaps(_arena.swap_time + 0.01)
	_arena._tick_swaps(0.01)
	_check(not _arena.is_safe(1) and _arena.player.is_stunned(), "whoever stays on it after swap_time is shoved off, and no longer safe")
	_put(1, other_spot)
	_check(_arena.is_safe(1), "the other Langit is still open to them")
	_arena._turn_season()
	_check(_arena._closed.is_empty() and _arena._swap.is_empty(), "a season change opens the closed Langit again")

	# --- crossings, close calls, streaks, the catch --------------------------------------------------
	_reset(3, [spot, other_spot])
	_set_favor(1000, 1000, 1000)
	_put(3, FAR)
	_put(1, spot)
	_arena._tick_crossings()
	var favor: int = _rules.mortal(1).favor
	_put(1, Vector2(650, 450))
	_arena._tick_crossings()
	_put(1, spot)
	_arena._tick_crossings()
	_check(_rules.mortal(1).favor == favor, "stepping back onto the Langit you left pays nothing")
	_put(1, Vector2(650, 450))
	_arena._tick_crossings()
	_put(1, other_spot)
	_arena._tick_crossings()
	var streak: int = _arena.streak_of(1)
	_check(_rules.mortal(1).favor == favor + _arena.crossing_favor + (streak - 1) * _arena.streak_step,
		"a crossing to a new Langit pays crossing_favor (+ the streak) (%d)" % (_rules.mortal(1).favor - favor))
	favor = _rules.mortal(1).favor
	_put(1, Vector2(650, 450))
	_arena._tick_crossings()
	_put(3, Vector2(650, 450 + _arena.close_call_radius - 10.0))
	_arena._tick_crossings()
	_put(3, FAR)
	_put(1, spot)
	_arena._tick_crossings()
	_check(_rules.mortal(1).favor == favor + _arena.crossing_favor + streak * _arena.streak_step + _arena.close_call_bonus,
		"a close call on the way adds close_call_bonus, and the streak adds streak_step (%d)" % (_rules.mortal(1).favor - favor))
	_check(_arena.streak_of(1) == streak + 1, "the streak grows with each crossing")
	_arena._streak[1] = 20
	favor = _rules.mortal(1).favor
	_put(1, Vector2(650, 450))
	_arena._tick_crossings()
	_put(1, other_spot)
	_arena._tick_crossings()
	_check(_rules.mortal(1).favor == favor + _arena.crossing_favor + _arena.streak_cap, "the streak bonus stops at streak_cap")
	_put(1, Vector2(650, 450))
	_put(3, Vector2(660, 450))
	_arena._tagback = 0.0
	_arena._invuln.clear()
	var runner_before: int = _rules.mortal(1).favor
	var taya_before: int = _rules.mortal(3).favor
	_arena._check_tag()
	_check(_arena.taya_id() == 1, "a touch on the Lupa passes Taya")
	_check(_arena.streak_of(1) == 0, "being tagged resets the streak")
	_check(_rules.mortal(1).favor == runner_before - _arena.tag_steal and _rules.mortal(3).favor == taya_before + _arena.tag_steal,
		"a tag moves tag_steal FAVOR from the runner to the Taya")
	_check(is_equal_approx(_arena._tagback, _arena.tagback_immunity), "the new Taya gets the tag-back buffer")
	_arena._check_tag()
	_check(_arena.taya_id() == 1, "the new Taya cannot tag straight back")
	_arena._tagback = 0.0
	_arena._check_tag()
	_check(_arena.taya_id() == 1, "and once its buffer is over, tagged_mercy still keeps the old Taya safe")
	_arena._tick_invuln(_arena.tagged_mercy + 0.01)
	_arena._check_tag()
	_check(_arena.taya_id() == 3, "after it, the old Taya can be tagged again")
	_rules.mortal(1).favor = 25
	_rules.mortal(3).favor = 0
	_arena._tagback = 0.0
	_arena._invuln.clear()
	_arena._check_tag()
	_check(_arena.taya_id() == 1 and _rules.mortal(3).favor == 25, "the Taya gets only what the runner really lost (25 of 60)")
	_arena._place_marker()
	_check(_arena.taya_marker.visible, "the Taya wears a marker")

	# --- the gods as Taya ------------------------------------------------------------------
	_reset(1, [spot, other_spot])
	_set_favor(1000, 1000, 1000)
	_arena._gods_take_taya()
	_arena._tagback = 0.0
	_put(1, spot)                   # safe
	_put(2, Vector2(660, 450))      # on the Lupa
	_put(3, FAR)
	_arena._god_at = Vector2(650, 450)
	_arena._check_tag()
	_check(_arena.taya_id() == 2, "the gods' touch on the Lupa makes that mortal the Taya")
	_check(_rules.mortal(1).favor == 1000 and _rules.mortal(2).favor == 1000 and _rules.mortal(3).favor == 1000,
		"a god tag moves no FAVOR")
	_check(is_equal_approx(_arena._tagback, _arena.tagback_immunity), "the new Taya still gets the tag-back buffer")
	_check(_arena._god_leave > 0.0 and _arena.hud.banner_label.text == _arena.god_tag_line,
		"the gods say their line and start to fade (%s)" % _arena.hud.banner_label.text)
	_arena._move_god(_arena.god_leave_time + 0.01)
	_arena._process(0.0)
	_check(_arena._god_at == Vector2.INF and not _arena._god_body.visible, "...then they leave the field")
	_check(_arena.god_overseer.visible, "...and the overseer Ikapati is back where she watches")
	_arena._move_god(1.0)
	_check(_arena._god_at == Vector2.INF and _arena.taya_id() == 2, "they never come back as an extra hunter")
	# a runner on a Langit is safe from the gods too; the gods never stand on one
	_reset(1, [spot, other_spot])
	_arena._gods_take_taya()
	_arena._tagback = 0.0
	_put(2, spot + Vector2(0, 20))
	_put(1, FAR)
	_put(3, FAR)
	_arena._god_at = spot + Vector2(0, 40)
	_arena._check_tag()
	_check(_arena.taya_id() == LangitLupaArena.GOD_TAYA, "a runner on a Langit is safe from the gods")
	_arena._god_at = spot + Vector2(4, 2)
	_arena._move_god(0.01)
	_check(not _arena.langit_rect(0).has_point(_arena._god_at), "the gods are pushed off a Langit like any Taya (%s)" % str(_arena._god_at))
	# no time as Taya, no drain
	_reset(1, [spot, other_spot])
	_set_favor(1000, 1000, 1000)
	_arena._gods_take_taya()
	_arena._god_at = Vector2(400, 380)
	_put(1, Vector2(1080, 380))
	_put(2, FAR)
	_put(3, Vector2(1080, 470))
	_arena._taya_time.clear()
	_arena._drain_pending.clear()
	for step in range(8):
		_arena.arena_rules_tick(DT)
	_check(_arena.taya_id() == LangitLupaArena.GOD_TAYA and _arena._taya_time.is_empty() and _arena._drain_pending.is_empty(),
		"the gods keep no time as Taya and owe no drain")
	_check(_rules.mortal(1).favor == 1000 and _rules.mortal(2).favor == 1000 and _rules.mortal(3).favor == 1000,
		"...and nobody pays for them (2s)")
	_check(_arena._god_at.x > 400.0 + _arena.god_speed * 1.5, "the gods chase at god_speed (%s)" % str(_arena._god_at))
	# the gods' chant: everyone safe -> they walk up to a Langit and chant; ALIS pays nobody
	_reset(1, [spot, other_spot])
	_set_favor(1000, 1000, 1000)
	_arena._gods_take_taya()
	_put(1, spot)
	_put(2, other_spot)
	_put(3, spot + Vector2(10, 0))
	_arena._god_at = spot + Vector2(0, 70)
	_arena._bot_taya_heading(LangitLupaArena.GOD_TAYA, _arena._god_at)
	_check(_arena._chanting and not _arena._bot_chant.is_empty(), "with every runner safe the gods walk to a Langit and chant")
	_arena._bot_chant["fail_at"] = -1
	for word in range(_arena.chant_length + 1):
		_arena._tick_bot_chant(_arena.god_chant_beat + 0.01)
	_check(not _arena._chanting and is_equal_approx(_arena.swap_left(1), _arena.swap_time), "a full chant yells ALIS (one word every god_chant_beat)")
	_check(_rules.mortal(1).favor == 1000 and _rules.mortal(2).favor == 1000, "...and nobody is paid chant_favor for it")
	# the safety valve
	_reset(1, [spot, other_spot])
	_set_favor(300, 900, 500)
	_arena._gods_take_taya()
	_arena._tagback = 0.0
	_put(1, Vector2(450, 450))
	_put(2, Vector2(950, 450))
	_put(3, Vector2(700, 450))
	_arena._god_at = Vector2(650, 380)
	_arena._god_time = _arena.god_taya_max_time - 0.05
	_arena._move_god(0.01)
	_check(_arena.god_hunt_id() == -1, "no hunt before god_taya_max_time")
	_arena._move_god(0.05)
	_check(_arena.god_hunt_id() == 2, "after god_taya_max_time the gods hunt the richest runner on the Lupa (%d)" % _arena.god_hunt_id())
	var from: Vector2 = _arena._god_at
	_arena._move_god(0.1)
	_check(absf(from.distance_to(_arena._god_at) - _arena.god_hunt_speed * _arena.taya_speed_bonus * 0.1) < 0.5 and _arena._god_at.x > from.x,
		"...at god_hunt_speed (with the Taya's bonus), straight at them (%.1f px in 0.1s)" % from.distance_to(_arena._god_at))
	_arena._god_at = Vector2(700, 440)
	_arena._check_tag()
	_check(_arena.taya_id() == LangitLupaArena.GOD_TAYA, "while hunting, the gods tag nobody else")
	_arena._god_at = Vector2(940, 450)
	_arena._check_tag()
	_check(_arena.taya_id() == 2, "...and their tag on the hunted runner hands them the Taya")
	_reset(1, [spot, other_spot])
	_arena._gods_take_taya()
	_put(1, Vector2(450, 450))
	_put(2, spot)                   # the richest, but safe
	_put(3, Vector2(700, 450))
	_arena._god_at = Vector2(650, 380)
	_check(_arena.hunt_target() == 3, "a safe runner (900) is passed over for the richest one on the Lupa (500) (%d)" % _arena.hunt_target())
	_put(1, other_spot)
	_put(3, spot + Vector2(10, 0))
	_check(_arena.hunt_target() == 2, "...and with everyone safe the richest runner anywhere is hunted (%d)" % _arena.hunt_target())
	# a hunted mortal who leaves: the gods pick again
	_put(1, Vector2(450, 450))
	_put(3, Vector2(700, 450))
	_put(2, Vector2(950, 450))
	_arena._god_hunt = 2
	_arena._god_time = _arena.god_taya_max_time + 1.0
	_rules.remove_mortal(2)
	_arena._mortal_positions.erase(2)
	_arena._move_god(0.01)
	_check(_arena.god_hunt_id() == 3, "when the hunted mortal leaves, the gods pick the next one (%d)" % _arena.god_hunt_id())
	_rules.ensure_mortal(2, "MORTAL 2")
	# the network: the gods ride the arena tick, a client only mirrors them
	var tick: Dictionary = _arena.arena_tick_fields()
	_check(tick.get("taya") == LangitLupaArena.GOD_TAYA and tick.has("god_at") and tick.has("god_leave") and tick.has("god_hunt"),
		"the gods' Taya, position, fade and hunt ride the arena tick")
	tick["god_at"] = Vector2(600, 400)
	tick["god_hunt"] = 1
	_arena.arena_read_tick(tick)
	_check(_arena._god_at == Vector2(600, 400) and _arena.god_hunt_id() == 1, "a client mirrors them from the tick")
	# a round that ends with the gods still Taya: a tie on time
	_arena._taya_time.clear()
	var rates := {}
	for amount in _arena.payouts().values():
		rates[amount] = true
	_check(rates.size() == 1 and rates.has(_arena.payout_best), "a round ending with the gods still Taya pays every mortal payout_best (all zero is a tie)")
	_arena._god_at = Vector2.INF

	# --- seasons ------------------------------------------------------------------------------------------
	_reset(1, [])
	_arena._place_langits()
	_arena._season_timer = _arena.season_interval
	var season: int = _arena._season
	var before: Array = _arena._langits.duplicate()
	_arena._tick_season(_arena.season_interval - _arena.shift_warning - 0.25)
	_check(not _arena.is_crumbling(), "no warning before the last shift_warning seconds (%.2fs left)" % _arena._season_timer)
	_arena._tick_season(0.5)
	_check(_arena.is_crumbling(), "...then the Langit shake")
	_arena._tick_season(0.5)
	_check(_arena._season == season, "still the same Langit just before the season turns")
	_arena._tick_season(0.5)
	_check(_arena._season == season + 1 and _arena._langits != before, "every season_interval they crumble and move to new spots")
	var placement_ok := true
	var spaced := 0
	var layouts := 0
	_rules.ensure_mortal(4, "MORTAL 4")
	_arena._read_field()
	_check(is_equal_approx(_arena._field.size.x, 868.0), "four mortals play on the full-width field (%s)" % str(_arena._field.size))
	for attempt in range(60):
		var taya_at := Vector2(randf_range(_arena._field.position.x, _arena._field.end.x), randf_range(_arena._field.position.y, _arena._field.end.y))
		_put(_arena.taya_id(), taya_at)
		_arena._place_langits()
		layouts += 1
		var all_spaced := true
		for index in range(_arena._langits.size()):
			var here: Rect2 = _arena.langit_rect(index)
			if _arena._langits[index].distance_to(taya_at) < _arena.taya_clearance:
				placement_ok = false
			if not _arena._field.encloses(here) or here.position.x < Arena.UI_STRIP_WIDTH:
				placement_ok = false
			for other in range(index + 1, _arena._langits.size()):
				if here.intersects(_arena.langit_rect(other)):
					placement_ok = false
				if _arena._langits[index].distance_to(_arena._langits[other]) < _arena.langit_spacing:
					all_spaced = false
		spaced += int(all_spaced)
	_check(_arena._langits.size() == 5, "with four mortals the field holds five Langit")
	_rules.remove_mortal(4)
	_check(placement_ok, "a Langit never lands near the Taya, off the field, in the UI strip or on another Langit")
	_check(spaced * 10 >= layouts * 9, "...and they are spread langit_spacing apart (%d of %d layouts)" % [spaced, layouts])

	# --- Time as Taya and the drain -------------------------------------------------
	_reset(1, [])
	_set_favor(1000, 1000, 1000)
	_put(1, Vector2(300, 120))
	_put(2, Vector2(1100, 560))
	_put(3, Vector2(700, 560))
	_arena._taya_time.clear()
	_arena._drain_pending.clear()
	_arena._drain_tick = 1.0
	for step in range(2):
		_arena.arena_rules_tick(DT)
	_check(is_equal_approx(_arena.taya_seconds(1), 0.5) and _arena.taya_seconds(2) == 0.0 and _arena.taya_seconds(3) == 0.0,
		"Time as Taya grows only for the Taya")
	_check(_rules.mortal(1).favor == 1000, "the drain is not banked every frame")
	for step in range(2):
		_arena.arena_rules_tick(DT)
	_check(_rules.mortal(1).favor == 990, "it lands once a second: -10 after 1s (%d)" % _rules.mortal(1).favor)
	for step in range(4):
		_arena.arena_rules_tick(DT)
	_check(_rules.mortal(1).favor == 980 and _rules.mortal(2).favor == 1000, "...and again after 2s, on the Taya only")
	_rules.mortal(1).favors.append(Gods.favor_by_id(&"waning_moon"))
	for step in range(4):
		_arena.arena_rules_tick(DT)
	_check(_rules.mortal(1).favor == 975, "it goes through lose_favor, so Waning Moon halves it (%d)" % _rules.mortal(1).favor)
	_rules.mortal(1).favors.clear()

	# --- the payout --------------------------------------------------------------------
	_arena._taya_time = {1: 5.0, 2: 10.0, 3: 20.0}
	var paid: Dictionary = _arena.payouts()
	_check(paid[1] == 600 and paid[2] == 350 and paid[3] == 100, "least time as Taya is paid most: 600 / 350 / 100 (%s)" % str(paid))
	_arena._taya_time = {1: 5.0, 2: 5.2, 3: 20.0}
	paid = _arena.payouts()
	_check(paid[1] == 600 and paid[2] == 600 and paid[3] == 100, "times within 0.25s tie and share the better payout (%s)" % str(paid))
	_rules.ensure_mortal(4, "MORTAL 4")
	_arena._taya_time = {1: 1.0, 2: 2.0, 3: 3.0, 4: 4.0}
	paid = _arena.payouts()
	_check(paid[1] == 600 and paid[2] == 433 and paid[3] == 267 and paid[4] == 100, "four places are spread evenly (%s)" % str(paid))
	_rules.remove_mortal(4)
	_arena._taya_time = {1: 5.0, 2: 10.0, 3: 20.0}
	_set_favor(0, 0, 0)
	var reasons: Array[String] = []
	_rules.favor_changed.connect(func(_id: int, _total: int, _delta: int, reason: String) -> void: reasons.append(reason))
	_arena._end_trial()
	var result: Dictionary = _arena._results.get(1, {})
	_check(_rules.mortal(1).favor == 600 and int(result.get("favor", 0)) == 600, "the payout is banked before the results are written")
	_check(reasons.has("Langit Lupa payout"), "...under the reason \"Langit Lupa payout\"")
	_check(int(result.get("bonus", 0)) == 600 and int(_arena._results.get(3, {}).get("bonus", 0)) == 100,
		"...and it shows in the results' bonus column (%s)" % str(result))

	# --- the 60s round through the game shell --------------------------------------------
	var network: Node = root.get_node("Network")
	network.run_settings = RunSettings.from_dict({"trials": 3, "trial_time": 90.0})
	network.run_settings.validate()
	network.rpc_sync_trial_order([Gods.MAPULON_IKAPATI, Gods.BATHALA])
	var game: Control = load("res://scenes/Game.tscn").instantiate()
	view.add_child(game)
	await _frames(4)
	_check(game.arena != null and is_equal_approx(game.arena.trial_time, 90.0), "the shell gives Langit Lupa the lobby's 90s round")
	_check(game.timer_label.text == "1:30", "the clock shows 1:30 (%s)" % game.timer_label.text)
	# TIME AS TAYA lives in the player panels on the left strip, not in a HUD list.
	var shell_arena: LangitLupaArena = game.arena
	var me: int = game.rules.local().id
	_check(shell_arena.get_node_or_null("LangitHud/TayaList") == null, "there is no TAYA list in the arena's HUD any more")
	shell_arena._taya = -1
	shell_arena._taya_time = {me: 12.0}
	await _frames(2)
	_check(game.own_trial_row.visible and game.own_trial_row.text == "TAYA 0:12", "your panel shows TAYA 0:12 (%s)" % game.own_trial_row.text)
	_check(not game.strip_note.visible, "...and no gods' line while the gods are not Taya")
	for id in game.rules.mortals.keys():
		if int(id) != me:
			shell_arena._taya_time[int(id)] = 75.0
	await _frames(2)
	_check(game.own_trial_row.text == "TAYA 0:12  #1", "the least time is ranked first - it pays most (%s)" % game.own_trial_row.text)
	_check(shell_arena.panel_row(int(game.rules.mortals.keys().filter(func(id): return int(id) != me)[0]))["text"] == "TAYA 1:15",
		"a rival's time rolls over into minutes (1:15)")
	shell_arena._taya = me
	await _frames(2)
	_check(shell_arena.panel_row(me)["tint"] == LangitLupaArena.TAYA_COLOR, "the Taya's row is in the Taya colour")
	shell_arena._taya = LangitLupaArena.GOD_TAYA
	await _frames(2)
	_check(game.strip_note.visible and game.strip_note.text.ends_with("ARE TAYA"), "while the gods are Taya the strip says so (%s)" % game.strip_note.text)
	game.queue_free()
	network.trial_order_ids.clear()
	await _frames(2)

	# --- the dash ----------------------------------------------------------------------------
	for step in range(20):
		await physics_frame  # the shove test's stumble wears off
	_arena._phase = Arena.Phase.PLAYING
	_arena.dialogue.close_now()  # the closing lines of the payout test
	_arena.player.set_lock(false)
	_arena.player.global_position = Vector2(600, 340)
	_arena.player.facing = 1
	_arena._dash_cd = 0.0
	var start := _arena.player.global_position
	_check(_arena.try_dash(), "the mortal can dash")
	for step in range(20):
		await physics_frame
	var moved := _arena.player.global_position.x - start.x
	_check(is_equal_approx(_arena.dash_distance, 77.0), "the dash is 77 px, 30%% shorter than the base's 110 (%.1f)" % _arena.dash_distance)
	_check(moved > 62.0 and moved < 95.0, "a dash covers about 77px (%.1f)" % moved)
	_check(not _arena.try_dash(), "the dash respects its cooldown")
	_check(is_equal_approx(_arena.dash_cooldown, 1.6) and _arena.dash_cooldown_left() > 1.0, "...of 1.6s (%.2fs left)" % _arena.dash_cooldown_left())
	_arena._dash_cd = 0.0
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	_arena.dialogue.show_lines([{"speaker": "TEST", "color": Color.WHITE, "text": "A LINE"}])
	_arena._unhandled_input(space)
	_check(_arena.dash_cooldown_left() == 0.0, "SPACE does not dash while a dialogue is open")
	_arena.dialogue.close_now()
	_arena._toggle_due_menu()
	_check(not _arena.try_dash(), "nor while the God's Due menu is open")
	_arena.due_menu.close()
	_arena._unhandled_input(space)
	_check(_arena.dash_cooldown_left() > 0.0, "during play SPACE dashes")
	var other: Arena = load("res://scenes/gods/mayari/MayariArena.tscn").instantiate()
	view.add_child(other)
	await _frames(2)
	other._phase = Arena.Phase.PLAYING
	other.player.set_lock(false)
	_check(not other.dash_enabled and not other.try_dash(), "the dash is off in other arenas")
	other.queue_free()

	# --- the earthquakes --------------------------------------------------------------------------
	# The host owns the schedule, shakes the field for 3 s and turns every mortal's
	# walk keys around while it lasts; the clock rides the tick so every screen
	# shakes and inverts together.
	_reset(_arena._my_id, [])
	_check(is_equal_approx(_arena.quake_interval_min, 25.0) and is_equal_approx(_arena.quake_interval_max, 45.0)
		and is_equal_approx(_arena.quake_time, 3.0),
		"earthquakes come every 25-45 s and last 3 s")
	_arena._quake_left = 0.0
	_arena._quake_timer = 0.05
	_arena._tick_quake(0.1)
	_check(_arena.quake_active() and is_equal_approx(_arena._quake_left, _arena.quake_time),
		"when the interval runs out the field shakes for the whole quake_time")
	_arena._process(0.0)
	_check(_arena.player.movement_inverted, "...and the walk keys drive the mortal backwards")
	_arena._refresh_hud(0.0)
	_check(_arena.hint_label.text.begins_with("EARTHQUAKE!"), "...and the hint strip says so")
	for index in range(200):
		_arena._tick_quake(1.0 / 60.0)
	_check(not _arena.quake_active()
		and _arena._quake_timer >= _arena.quake_interval_min - 0.001 and _arena._quake_timer <= _arena.quake_interval_max,
		"when it stops the next one is rolled 25-45 s away (%.1f s)" % _arena._quake_timer)
	_arena._process(0.0)
	_check(not _arena.player.movement_inverted, "walking is normal again")
	var quake_tick: Dictionary = _arena.arena_tick_fields()
	_check(quake_tick.has("quake_left"), "the earthquake clock rides the arena tick")
	quake_tick["quake_left"] = 2.5
	_arena._quake_left = 0.0
	_arena.arena_read_tick(quake_tick)
	_check(is_equal_approx(_arena._quake_left, 2.5), "a client shakes on the host's word")
	quake_tick["quake_left"] = 0.0
	_arena.arena_read_tick(quake_tick)
	_check(not _arena.quake_active(), "...and stops when the host does")
	_arena._quake_timer = 1000.0

	# --- the other gods' favors still work here -------------------------------------------------
	_arena._phase = Arena.Phase.PLAYING
	_arena._apply_skill_effect(Gods.favor_by_id(&"half_vision"), 2)
	_check(_arena._blind_time > 0.0, "Mayari's Half Vision darkens this screen")
	_arena._apply_skill_effect(Gods.favor_by_id(&"siblings_compromise_sun"), 2)
	_check((_arena._sun_patches.get(1, []) as Array).size() > 0, "Apolaki's sun patches land")
	_arena._apply_skill_effect(Gods.favor_by_id(&"let_us_light_your_way"), 2)
	_check(_arena._movement_override_caster == 2, "Tala's Let Us Light Your Way pulls towards the caster")
	_set_favor(1000, 0, 0)
	_rules.mortal(1).due = 1
	_check(_rules.grant_favor(Gods.favor_by_id(&"down_to_homeland")), "a favor is granted with a God's Due here")
	_rules.mortal(2).favor = 2000
	_arena._use_skill(GodFavor.Slot.E)
	_check(_rules.mortal(2).rooted_time > 0.0, "E fires it (Down to Homeland roots the others)")

	print("Langit Lupa checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


# A quiet field for one test: `taya` is it (with no buffer), the Langit are
# where the test says, nobody's chant, swap, streak or mercy is left over, and
# the season will not turn by itself.
func _reset(taya: int, langits: Array) -> void:
	_arena._phase = Arena.Phase.PLAYING
	_arena._clear_clouds()
	for spot in langits:
		_arena._add_cloud(spot)
	for runners in [_arena._swap, _arena._closed, _arena._shoving, _arena._on, _arena._last_left, _arena._close_call, _arena._streak]:
		runners.clear()
	_arena._season_timer = 1000.0
	_arena.set_taya(taya)
	_arena._god_at = Vector2.INF
	_arena._god_leave = 0.0
	_arena._god_hunt = -1
	_arena._god_time = 0.0
	_arena._bot_chant.clear()
	_arena._tagback = 0.0
	_arena._chant_cd = 0.0
	_arena._invuln.clear()
	_arena._my_chanting = false
	_arena._my_stumble = 0.0
	_arena._set_rooted(false)


func _set_favor(mine: int, rival: int, rival_two: int) -> void:
	_rules.mortal(1).favor = mine
	_rules.mortal(2).favor = rival
	_rules.mortal(3).favor = rival_two


func _put(id: int, at: Vector2) -> void:
	if id == _arena._my_id:
		_arena.player.global_position = at
	else:
		_arena._mortal_positions[id] = at


# The pixels the figure fills in a frame, top to bottom (frames carry padding).
func _figure_height(texture: Texture2D) -> float:
	var image := texture.get_image()
	var top := image.get_height()
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.05:
				top = mini(top, y)
				bottom = maxi(bottom, y)
	return float(bottom - top + 1) if bottom >= 0 else 0.0


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
