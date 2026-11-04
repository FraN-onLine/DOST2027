extends SceneTree

# Validation for ANITUN TABU: her resource (a hidden visitor), the seven favors
# and Luksong Lubid.
#
#   * the god is registered, hidden, playable and closes on her own arena
#   * an unwanted visitor is only unknown in the rest: the lobby's run plan and
#     the pantheon's transitions name it, the prep's NEXT banner does not
#   * It's Kinda Tabu needs a Q (any god's); Bato Bato can hand Tabu's E and Q over
#   * Must've Been the Wind shrugs off one loss per cast (host rules)
#   * Blow Back returns half of the first loss after 10s, one at a time
#   * A Silent Song takes 10% of each other mortal's first gain, once
#   * Tabu's Delivery Service pays at 10s left, after personal multipliers
#   * All Winds Lead to Tabu raises every share
#   * It's Kinda Tabu pays +8/s with the Q ready, takes -8/s while it recharges
#   * the lubid is held by two animated wind fairies, one at each end
#   * a mortal draws over the lubid while the hop has it in the air
#   * Luksong Lubid is one shared field: positions travel and rivals are drawn
#   * the rope sweeps and pongs, a jump pays 125, the rope costs 75, a gust
#     costs 150; in the blitz the rope sweeps faster; the host's rope and gusts
#     mirror to every screen
#   * a gust only catches in its lift frames (8-10) and only inside its own
#     authored Area2D
#   * gusts keep the 3-4s clock, come 1-2s in the blitz and two at once, each
#     thrown at a mortal picked from the whole field (never always the host),
#     spread wide and spaced so the blitz's pair never overlaps
#   * in the blitz the gales blow on their own (200 a jump, 150 for a mortal
#     holding The West Wind), the wind pushes west and leaves the airborne
#     alone, and a West Wind holder walks through it
#   * the Winds and Gales overlay fades in and out of its own scene
#   * GodMatch keeps the new passives through snapshot / apply_snapshot
# Run: godot --headless --path <project> -s res://tools/tabu_check.gd

const ARENA_SCENE := "res://scenes/gods/anitun_tabu/LuksongLubidArena.tscn"
const WIND_SCENE := "res://scenes/gods/common/WindsAndGales.tscn"
const DT := 1.0 / 60.0

var _problems := 0
var _view: SubViewport


func _initialize() -> void:
	_run()


func _run() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(1152, 648)
	_view.disable_3d = true
	root.add_child(_view)
	await process_frame

	# --- the god -------------------------------------------------------------------------
	var god := Gods.by_id(&"anitun_tabu")
	_check(god != null and god.display_name == "ANITUN TABU" and god.game_name == "LUKSONG LUBID",
		"Anitun Tabu is in the registry, with Luksong Lubid")
	_check(Gods.all().size() == 8, "the registry holds eight gods (%d)" % Gods.all().size())
	_check(god != null and god.hidden_visitor, "she is an unwanted visitor")
	_check(RunSettings.playable_ids().has(&"anitun_tabu"), "...but plays like any other god")
	_check(god != null and god.favors.size() == 7, "she bestows seven favors")
	_check(god != null and god.arena_scene == ARENA_SCENE, "her arena is the Luksong scene")
	_check(god != null and god.intro_lines.size() > 0 and god.trial_end_lines.size() > 0, "she speaks her own intro and ending")

	var favor_ids: Array = god.favors.map(func(favor: GodFavor) -> String: return str(favor.id))
	_check(favor_ids == ["the_west_wind", "mustve_been_the_wind", "blow_back", "a_silent_song",
		"tabus_delivery_service", "its_kinda_tabu", "all_winds_lead_to_tabu"],
		"the seven favors are the designed ones (%s)" % str(favor_ids))
	var west := Gods.favor_by_id(&"the_west_wind")
	var shield := Gods.favor_by_id(&"mustve_been_the_wind")
	var back := Gods.favor_by_id(&"blow_back")
	var song := Gods.favor_by_id(&"a_silent_song")
	var delivery := Gods.favor_by_id(&"tabus_delivery_service")
	var kinda := Gods.favor_by_id(&"its_kinda_tabu")
	var all_winds := Gods.favor_by_id(&"all_winds_lead_to_tabu")
	_check(west.slot == GodFavor.Slot.E and west.cooldown == 30.0 and is_equal_approx(west.param("speed_boost", 0.0), 0.1),
		"The West Wind is the E, 30s, +10% on a recast")
	_check(shield.slot == GodFavor.Slot.Q and shield.cooldown == 10.0 and shield.param("shields", 0.0) == 1.0,
		"Must've Been the Wind is the Q, 10s, one shrug")
	_check(back.slot == GodFavor.Slot.PASSIVE and is_equal_approx(back.param("return_share", 0.0), 0.5)
		and is_equal_approx(back.param("delay", 0.0), 10.0), "Blow Back returns 50% after 10s")
	_check(song.slot == GodFavor.Slot.PASSIVE and is_equal_approx(song.param("share", 0.0), 0.1),
		"A Silent Song shares 10%")
	_check(delivery.slot == GodFavor.Slot.PASSIVE and delivery.param("gift", 0.0) == 100.0
		and is_equal_approx(delivery.param("at_time", 0.0), 10.0), "Tabu's Delivery Service sends 100 at 10s")
	_check(kinda.slot == GodFavor.Slot.PASSIVE and is_equal_approx(kinda.param("per_second", 0.0), 8.0)
		and is_equal_approx(kinda.param("speed", 0.0), 0.05), "It's Kinda Tabu pays 8 a second and 5% speed")
	_check(all_winds.slot == GodFavor.Slot.PASSIVE and is_equal_approx(all_winds.param("blow_back", 0.0), 1.0)
		and is_equal_approx(all_winds.param("silent_song", 0.0), 0.75) and is_equal_approx(all_winds.param("delivery", 0.0), 1.5),
		"All Winds Lead to Tabu names the three new shares")

	# --- the unwanted visitor is named in the plan, unknown in the rest --------------------
	_check(Gods.sidapa().hidden_visitor and Gods.anitun_tabu().hidden_visitor, "Sidapa and Tabu are both unwanted visitors")
	_check(not Gods.mayari().hidden_visitor, "...while the pantheon is not")
	var sensed := god.unknown_force_transition()
	_check(sensed.size() >= 2 and str(sensed[0]).contains("force"), "Tabu's arrival is sensed, not named (%s)" % str(sensed))
	var fallback := Gods.mayari().unknown_force_transition()
	_check(fallback.size() >= 1 and str(fallback[0]).to_lower().contains("unknown force"),
		"a god with no lines of its own still only senses an unknown force (%s)" % str(fallback))

	var plan := RunSettings.defaults()
	plan.order_mode = RunSettings.ORDER_CUSTOM
	plan.custom_order = [&"anitun_tabu", &"sidapa", &"tala", &"mayari"]
	plan.trials = 4
	var line := plan.run_line()
	_check(line.begins_with("Anitun Tabu") and line.contains("Sidapa") and not line.contains("???"),
		"the lobby's run plan names both visitors (%s)" % line)
	plan.custom_order = [&"tala", &"mayari", &"apolaki", &"hanan"]
	_check(plan.run_line().begins_with("Tala") and not plan.run_line().contains("???"),
		"...and names the rest as usual (%s)" % plan.run_line())

	# --- the favors live in the rules --------------------------------------------------------
	var rules := _match()
	var me := rules.mortal(1)
	_check(kinda.requires_slot() == GodFavor.Slot.Q and kinda.requires_favor_id() == &"",
		"It's Kinda Tabu asks for a Q slot, not one named favor")
	_check(not rules.bestow_favor(kinda, 1), "It's Kinda Tabu needs a Q first")
	var other_q := Gods.favor_by_id(&"bagong_umaga")
	_check(other_q != null and other_q.slot == GodFavor.Slot.Q and rules.bestow_favor(other_q, 1)
		and rules.bestow_favor(kinda, 1), "...and another god's Q opens it too")

	# Must've Been the Wind: one shrug per cast.
	rules = _match()
	me = rules.mortal(1)
	rules.bestow_favor(shield, 1)
	_check(rules.use_skill(GodFavor.Slot.Q, 1) != null and me.wind_shield == 1, "the Q arms one shrug")
	me.favor = 500
	var lost := rules.lose_favor(100, "check", 1)
	_check(lost == 0 and me.favor == 500 and me.wind_shield == 0, "the next loss is shrugged off")
	_check(rules.use_skill(GodFavor.Slot.Q, 1) == null, "...and the Q is still recharging")
	lost = rules.lose_favor(100, "check", 1)
	_check(lost == 100 and me.favor == 400, "the loss after it lands as usual")

	# Blow Back: one return at a time.
	rules = _match()
	me = rules.mortal(1)
	rules.bestow_favor(back, 1)
	me.favor = 1000
	rules.lose_favor(200, "check", 1)
	_check(me.favor == 800 and me.blow_back_left > 0.0 and me.blow_back_amount == 100,
		"a 200 loss owes 100 back")
	rules.lose_favor(200, "check", 1)
	_check(me.favor == 600 and me.blow_back_amount == 100, "a second loss while one is pending waits its turn")
	rules._tick_mortal(me, 5.0)
	_check(me.favor == 600 and me.blow_back_left > 4.0, "five seconds in, nothing is back yet")
	rules._tick_mortal(me, 5.2)
	_check(me.favor == 700 and me.blow_back_left <= 0.0, "...and ten seconds on, the 100 returns")
	rules.lose_favor(200, "check", 1)
	_check(me.blow_back_amount == 100, "once it is paid, the next loss may queue again")

	# All Winds Lead to Tabu: a full return.
	rules = _match()
	me = rules.mortal(1)
	rules.bestow_favor(back, 1)
	rules.bestow_favor(all_winds, 1)
	me.favor = 1000
	rules.lose_favor(200, "check", 1)
	_check(me.blow_back_amount == 200, "All Winds makes Blow Back return all of it")

	# A Silent Song: the first gain of each other mortal, once each.
	rules = _match(["A", "B"])
	me = rules.mortal(1)
	rules.bestow_favor(song, 1)
	me.favor = 0
	rules.add_favor(100, "check", 2)
	_check(me.favor == 10, "a rival's first 100 pays the singer 10")
	rules.add_favor(100, "check", 2)
	_check(me.favor == 10, "...but only the first one")
	rules.add_favor(50, "check", 3)
	_check(me.favor == 15, "another mortal's first gain pays too")
	rules = _match(["A", "B"])
	me = rules.mortal(1)
	rules.bestow_favor(song, 1)
	rules.bestow_favor(all_winds, 1)
	me.favor = 0
	rules.add_favor(100, "check", 2)
	_check(me.favor == 75, "All Winds raises A Silent Song to 75%")

	# Tabu's Delivery Service: at 10s left, after each mortal's own multipliers.
	rules = _match(["A", "B"])
	me = rules.mortal(1)
	rules.bestow_favor(delivery, 1)
	rules.bestow_favor(Gods.favor_by_id(&"full_moon"), 2)
	me.favor = 0
	rules.time_left = 11.0
	rules._tick_mortal(me, DT)
	_check(me.favor == 0 and not me.delivery_done, "above 10s the gift waits")
	rules.time_left = 9.5
	rules._tick_mortal(me, DT)
	_check(rules.mortal(2).favor == 110 and rules.mortal(3).favor == 100,
		"100 each, raised by Full Moon (%d, %d)" % [rules.mortal(2).favor, rules.mortal(3).favor])
	_check(me.favor == 210 and me.delivery_done, "the sender keeps every FAVOR it really handed out (%d)" % me.favor)
	rules._tick_mortal(me, DT)
	_check(me.favor == 210, "...once per trial")
	rules = _match(["A", "B"])
	me = rules.mortal(1)
	rules.bestow_favor(delivery, 1)
	rules.bestow_favor(all_winds, 1)
	me.favor = 0
	rules.time_left = 9.0
	rules._tick_mortal(me, DT)
	_check(me.favor == 300, "All Winds raises the delivery to 150%% (%d)" % me.favor)

	# It's Kinda Tabu: the Q's readiness pays or takes.
	rules = _match()
	me = rules.mortal(1)
	rules.bestow_favor(shield, 1)
	rules.bestow_favor(kinda, 1)
	rules.trial_active = true
	me.favor = 0
	rules._tick_mortal(me, 2.0)
	_check(me.favor == 16, "a ready Q pays 8 a second (%d)" % me.favor)
	me.favor = 100
	rules.use_skill(GodFavor.Slot.Q, 1)
	rules._tick_mortal(me, 1.0)
	_check(me.favor == 92, "a recharging Q costs 8 a second (%d)" % me.favor)
	me.favor = 4
	rules._tick_mortal(me, 1.0)
	_check(me.favor == 0, "...and never takes more than it has")

	# Bato Bato can hand her skills over.
	rules = _match()
	me = rules.mortal(1)
	rules.bestow_favor(Gods.favor_by_id(&"half_vision"), 1)
	var pool := rules.bato_bato_pool(me, GodFavor.Slot.E)
	var pool_ids: Array = pool.map(func(favor: GodFavor) -> StringName: return favor.id)
	_check(pool_ids.has(&"the_west_wind"), "Bato Bato's E pool holds The West Wind")
	rules.bestow_favor(Gods.favor_by_id(&"siblings_compromise"), 1)
	var q_pool := rules.bato_bato_pool(me, GodFavor.Slot.Q)
	var q_pool_ids: Array = q_pool.map(func(favor: GodFavor) -> StringName: return favor.id)
	_check(q_pool_ids.has(&"mustve_been_the_wind"), "...and its Q pool holds Must've Been the Wind")

	# The snapshot carries the new passives.
	me.wind_shield = 2
	me.blow_back_left = 4.0
	me.blow_back_amount = 50
	me.delivery_done = true
	var snap := rules.snapshot()
	var other := GodMatch.new()
	_view.add_child(other)
	other.setup(Gods.anitun_tabu(), "ME", ["A"])
	other.apply_snapshot(snap)
	var mirrored := other.mortal(1)
	_check(mirrored.wind_shield == 2 and is_equal_approx(mirrored.blow_back_left, 4.0) and mirrored.delivery_done,
		"the snapshot carries the shield, the return and the delivery")
	other.queue_free()

	# --- the overlay's own scene -------------------------------------------------------------
	var overlay = load(WIND_SCENE).instantiate()
	_view.add_child(overlay)
	await process_frame
	_check(not overlay.visible, "the gale is hidden until called")
	overlay.set_active(true)
	overlay._process(1.0)
	_check(overlay.visible and overlay.gale.modulate.a > 0.5, "it fades in over the screen")
	overlay.set_active(false)
	overlay._process(1.0)
	_check(not overlay.visible, "...and fades out of it")
	overlay.queue_free()
	await process_frame

	# --- Luksong Lubid -----------------------------------------------------------------------
	var arena = load(ARENA_SCENE).instantiate()
	_view.add_child(arena)
	await process_frame
	await process_frame
	_check(arena.god != null and arena.god.id == &"anitun_tabu", "the arena wears its god")
	_check(not arena.separate_players() and arena.shares_mortal_positions() and arena.nearby_movement_favors_enabled(),
		"Luksong is played on one shared field, like Patintero")
	_check(arena.edge_targets().is_empty(), "there is no rival to point an edge arrow at")
	_check(arena.lubid != null and arena.bursts_root != null and arena.state_label != null,
		"the authored rope, the gusts' root and the band label all exist")
	_check(arena.lubid.rope != null and arena.lubid.shine != null and arena.lubid.hitbox != null,
		"the rope is the Lubid scene, with its line, shine and hitbox")

	var guard := 0
	while arena.dialogue.is_active() and guard < 40:
		arena.dialogue.advance()
		guard += 1
	arena._phase = Arena.Phase.PLAYING
	arena._end_intro_shot()
	arena._trial_time = 120.0
	arena.arena_round_reset()
	arena._phase = Arena.Phase.PLAYING
	arena.player.set_lock(false)
	arena._invuln.clear()
	arena.rules.local().favors.clear()

	var field: Rect2 = arena._field
	_check(field.size != Vector2.ZERO, "the field is read from the border (%s)" % str(field))
	var low: float = field.position.x + arena.rope_margin
	var high: float = field.end.x - arena.rope_margin
	_check(is_equal_approx(arena._rope_x, high), "the rope starts at the right wall")
	_check(is_equal_approx(arena.lubid.length, field.size.y), "it hangs the full height of the field")
	arena._rope_x = low + 1.0
	arena._rope_dir = -1.0
	arena._tick_rope(0.1)
	_check(is_equal_approx(arena._rope_x, low) and arena._rope_dir > 0.0, "it pongs off the left wall")
	arena._rope_x = high - 1.0
	arena._rope_dir = 1.0
	arena._tick_rope(0.1)
	_check(is_equal_approx(arena._rope_x, high) and arena._rope_dir < 0.0, "...and off the right")
	arena.lubid._phase = 1.0
	arena.lubid._rebuild()
	_check(arena.lubid.sway_offset() != 0.0, "the rope sways as it hangs")

	var fairy_top := arena.lubid.get_node_or_null("FairyTop") as AnimatedSprite2D
	var fairy_bottom := arena.lubid.get_node_or_null("FairyBottom") as AnimatedSprite2D
	_check(fairy_top != null and fairy_bottom != null and fairy_top.is_playing() and fairy_bottom.is_playing(),
		"two wind fairies animate on the lubid")
	var fairy_frame: Texture2D = fairy_top.sprite_frames.get_frame_texture(&"default", 0) if fairy_top != null else null
	_check(fairy_top != null and fairy_top.sprite_frames.get_frame_count(&"default") == 4
		and fairy_frame != null and fairy_frame.get_width() == 48,
		"...on a four-frame loop of the wind fairy art")
	var rope_tip: Vector2 = arena.lubid.rope.points[arena.lubid.rope.points.size() - 1]
	_check(fairy_top != null and fairy_top.position.y < 0.0
		and is_equal_approx(fairy_bottom.position.y, arena.lubid.length + arena.lubid.fairy_hold)
		and absf(fairy_bottom.position.x - rope_tip.x) < 0.001,
		"...holding its two ends, the bottom one swaying with it")

	# Crossing, airborne: 125. (The pong above may have caught the mortal.)
	await _settle(arena)
	arena._invuln.clear()
	arena.rules.local().favor = 0
	arena._jump_left = 0.0
	arena._try_jump()
	_check(arena._jump_left > 0.0 and arena.mortal_airborne(), "ATTACK lifts the mortal into the hop")
	var rope_z: int = arena.field_root.z_index + arena.lubid.z_index
	_check(arena.player.z_index > rope_z, "the hop draws the mortal over the lubid (%d > %d)" % [arena.player.z_index, rope_z])
	arena._tick_jump(DT)
	_check(arena.player.drop_offset.y < 0.0, "the hop lifts the figure off the ground")
	arena._cross_guard = 0.0
	arena._prev_rel = 4.0
	arena._rope_x = arena.player.global_position.x - 2.0
	arena._rope_dir = 1.0
	arena._tick_rope(0.001)
	_check(arena.rules.local().favor == 125,
		"clearing the rope in the air pays 125 (%d)" % arena.rules.local().favor)
	arena._tick_jump(arena.jump_time)
	_check(arena.player.drop_offset == Vector2.ZERO and not arena.mortal_airborne(), "...and it lands again")
	_check(arena.player.z_index == arena._player_z, "...back under the lubid's draw order")

	# Crossing on the ground: 75 and a shove.
	await _settle(arena)
	arena._invuln.clear()
	arena.rules.local().favor = 1000
	arena._jump_left = 0.0
	arena._cross_guard = 0.0
	arena._prev_rel = 4.0
	arena._rope_x = arena.player.global_position.x - 2.0
	arena._rope_dir = 1.0
	arena._tick_rope(0.001)
	_check(arena.rules.local().favor == 925, "the rope catching you on the ground costs 75")
	_check(arena.is_mortal_invulnerable(arena._my_id), "...and grants mercy seconds")
	arena._cross_guard = 0.0
	arena._prev_rel = 4.0
	arena._rope_x = arena.player.global_position.x - 2.0
	arena._tick_rope(0.001)
	_check(arena.rules.local().favor == 925, "no second hit while the mercy runs")

	# The lubid sweeps faster while the gales blow.
	arena._invuln.clear()
	arena.player.global_position = Vector2(field.position.x + 40.0, field.get_center().y)
	arena._cross_guard = 1.0
	arena._trial_time = 60.0
	arena._rope_x = field.get_center().x
	arena._rope_dir = 1.0
	arena._prev_rel = arena._rope_x - arena.player.global_position.x
	var calm_from: float = arena._rope_x
	arena._tick_rope(0.1)
	var calm_step: float = arena._rope_x - calm_from
	arena._trial_time = arena.blitz_time
	arena._rope_x = field.get_center().x
	arena._rope_dir = 1.0
	arena._prev_rel = arena._rope_x - arena.player.global_position.x
	var blitz_from: float = arena._rope_x
	arena._tick_rope(0.1)
	var blitz_step: float = arena._rope_x - blitz_from
	_check(blitz_step > calm_step * 1.2,
		"in the blitz the lubid sweeps faster (%.0f vs %.0f px/s)" % [blitz_step * 10.0, calm_step * 10.0])
	arena._trial_time = 60.0
	arena._cross_guard = 0.0

	# A gust: 150, and the air is above it.
	await _settle(arena)
	arena._invuln.clear()
	arena.rules.local().favor = 1000
	arena._clear_bursts()
	arena._burst_timer = 0.0
	arena._tick_bursts(0.01)
	_check(arena._bursts.size() == 1, "a gust swells on or around the mortal")
	var burst_z: int = arena.field_root.z_index + arena.bursts_root.z_index
	_check(arena.player.z_index > burst_z,
		"the mortal draws over the wind burst (%d > %d)" % [arena.player.z_index, burst_z])
	var gust = arena._bursts[0]["node"]
	gust.global_position = arena.player.global_position
	gust.anim.frame = 7
	_check(not gust.catches(arena.player.global_position, arena.player.radius),
		"a gust is harmless while it wells up (frame 7)")
	gust.anim.frame = 8
	_check(gust.catches(arena.player.global_position, arena.player.radius),
		"the lift catches from frame 8")
	gust.anim.frame = 10
	_check(gust.catches(arena.player.global_position, arena.player.radius),
		"...and through frame 10")
	gust.anim.frame = 11
	_check(not gust.catches(arena.player.global_position, arena.player.radius),
		"...then lets go at frame 11")
	gust.anim.frame = 9
	gust.global_position = arena.player.global_position + Vector2(120.0, 0.0)
	_check(not gust.catches(arena.player.global_position, arena.player.radius),
		"outside the gust's own Area2D nothing is caught")
	gust.global_position = arena.player.global_position
	arena._tick_bursts(0.01)
	_check(arena.rules.local().favor == 850, "standing in the lift costs 150")
	_check(bool(arena._bursts[0]["hit"]) if not arena._bursts.is_empty() else true, "...once")
	await _settle(arena)
	arena._invuln.clear()
	arena.rules.local().favor = 1000
	arena._clear_bursts()
	arena._burst_timer = 0.0
	arena._tick_bursts(0.01)
	gust = arena._bursts[0]["node"]
	gust.global_position = arena.player.global_position
	gust.anim.frame = 9
	arena._jump_left = 0.3
	arena._tick_bursts(0.01)
	_check(arena.rules.local().favor == 1000, "a mortal in the air is above the gust")
	arena._jump_left = 0.0
	arena._clear_bursts()

	# The gust clock: 3-4s, two seconds sooner again in the blitz.
	_check(is_equal_approx(arena.burst_min_time, 3.0) and is_equal_approx(arena.burst_max_time, 4.0),
		"gusts come every 3-4s")
	arena._trial_time = 60.0
	var in_range := true
	for roll in range(60):
		var wait: float = arena._roll_burst_time()
		if wait < arena.burst_min_time - 0.001 or wait > arena.burst_max_time + 0.001:
			in_range = false
	_check(in_range, "...and every roll stays inside that range")
	arena._trial_time = arena.blitz_time
	var blitz_range := true
	for roll in range(60):
		var wait: float = arena._roll_burst_time()
		if wait < arena.burst_min_time - arena.BLITZ_BURST_CUT - 0.001 \
				or wait > arena.burst_max_time - arena.BLITZ_BURST_CUT + 0.001:
			blitz_range = false
	_check(blitz_range, "in the blitz they come two seconds sooner again (1-2s)")
	_check(is_equal_approx(arena.burst_spawn_radius, 140.0),
		"a gust spreads over a wide patch of the field")

	# Solo, the blitz's pair still lands apart: their areas never touch.
	arena.player.global_position = field.get_center()
	arena._trial_time = arena.blitz_time
	arena._clear_bursts()
	arena._burst_seq = 0
	arena._spawn_burst_cycle()
	var solo_spots: Array = []
	for burst in arena._bursts:
		solo_spots.append((burst["node"] as WindBurst).global_position)
	var solo_gap := 0.0
	if solo_spots.size() == 2:
		solo_gap = (solo_spots[0] as Vector2).distance_to(solo_spots[1] as Vector2)
	_check(solo_spots.size() == 2 and solo_gap >= arena.BLITZ_BURST_GAP,
		"in solo the blitz's two gusts stay a gust apart (%.0f px)" % solo_gap)
	arena._clear_bursts()

	# The gusts scatter across the whole field: two at once in the blitz, each
	# aimed at a different mortal, not both at the host.
	var rival := GodMatch.Mortal.new()
	rival.id = 2
	rival.display_name = "RIVAL"
	arena.rules.mortals[2] = rival
	var rival_spot := Vector2(field.end.x - 80.0, field.end.y - 80.0)
	arena._mortal_positions[2] = rival_spot
	arena.burst_spawn_radius = 0.0
	arena._clear_bursts()
	arena._burst_seq = 0
	arena._rope_x = field.position.x + 100.0
	arena._trial_time = arena.blitz_time
	arena._spawn_burst_cycle()
	var host_spots: Array = []
	for burst in arena._bursts:
		host_spots.append((burst["node"] as WindBurst).global_position)
	_check(host_spots.size() == 2, "in the blitz two gusts rise at once (%d)" % host_spots.size())
	_check(host_spots.has(rival_spot) and host_spots.has(arena.player.global_position),
		"they are thrown at two different mortals, not both at the host")
	var wire: Dictionary = arena.arena_tick_fields()
	_check(wire.has("rope_x") and is_equal_approx(float(wire["rope_x"]), arena._rope_x)
		and (wire["bursts"] as Array).size() == 2,
		"the host puts its rope and gusts on the wire")
	arena._clear_bursts()
	arena._rope_x = 0.0
	arena.arena_read_tick(wire)
	_check(is_equal_approx(arena._rope_x, float(wire["rope_x"])), "a client takes the host's rope")
	_check(arena._bursts.size() == 2, "...and builds the host's gusts")
	var client_spots: Array = []
	for burst in arena._bursts:
		client_spots.append((burst["node"] as WindBurst).global_position)
	_check(client_spots == host_spots, "...where the host says they swell")
	arena._clear_bursts()
	arena.rules.mortals.erase(2)
	arena._mortal_positions.erase(2)
	arena.burst_spawn_radius = 140.0
	arena._rope_x = high

	# The blitz: the gales blow on their own.
	arena._phase = Arena.Phase.PLAYING
	arena._trial_time = 31.0
	arena._tick_blitz()
	_check(not arena._in_blitz() and not arena._blitz_announced, "with 31s left the gales are quiet")
	arena._trial_time = 30.0
	arena._tick_blitz()
	_check(arena._in_blitz() and arena._blitz_announced, "at 30s the blitz is on")
	_check(arena.wind_forced() and arena.wind_active(), "...and the gales of yesterday blow by themselves")
	arena._tick_wind(DT)
	_check(arena.player.wind_drag.x < 0.0, "the wind drags the walking mortal west (%s)" % str(arena.player.wind_drag))
	_check(arena.arena_local_effects().size() == 1 and arena.arena_local_effects()[0].get("harmful", false),
		"the field warns that the gales push west")
	_check(arena.winds != null and arena.winds.visible, "the full-screen gale is playing")

	arena._invuln.clear()
	arena.rules.local().favor = 1000
	arena._jump_left = 0.3
	arena._cross_guard = 0.0
	arena._prev_rel = 4.0
	arena._rope_x = arena.player.global_position.x - 2.0
	arena._rope_dir = 1.0
	arena._tick_rope(0.001)
	_check(arena.rules.local().favor == 1200, "in the blitz a jump pays 200")
	arena._jump_left = 0.0

	# The West Wind: its own gale_immunity clause, and a smaller blitz jump.
	_check(west.gale_immunity(), "The West Wind carries its gale_immunity clause")
	_check(arena.rules.bestow_favor(west, arena._my_id), "the mortal can hold The West Wind")
	arena._tick_wind(DT)
	_check(arena.player.wind_drag == Vector2.ZERO, "its holder walks through the gales untouched")
	_check(arena.wind_push.x < 0.0, "...while the gales still push the rest of the field west (%s)" % str(arena.wind_push))
	_check(arena.arena_local_effects().size() == 1 and not arena.arena_local_effects()[0].get("harmful", false),
		"...and the field says so")
	arena._invuln.clear()
	arena.rules.local().favor = 1000
	arena._jump_left = 0.3
	arena._cross_guard = 0.0
	arena._prev_rel = 4.0
	arena._rope_x = arena.player.global_position.x - 2.0
	arena._rope_dir = 1.0
	arena._tick_rope(0.001)
	_check(arena.rules.local().favor == 1150, "a jump by an immune mortal pays 150 in the blitz")
	arena._jump_left = 0.0
	arena._trial_time = 999.0
	arena._tick_wind(DT)
	_check(not arena.wind_active() and arena.player.wind_drag == Vector2.ZERO, "out of the blitz the gales stop")

	# It's Kinda Tabu's speed, in the arena.
	arena.rules.local().favors.clear()
	arena._update_movement_favors(0.0)
	var base_speed: float = arena.player.move_speed
	arena.rules.bestow_favor(shield, arena._my_id)
	arena.rules.bestow_favor(kinda, arena._my_id)
	arena._update_movement_favors(0.0)
	_check(is_equal_approx(arena.player.move_speed, base_speed * 1.05),
		"a ready Q gives It's Kinda Tabu's 5%% speed (%s)" % str(arena.player.move_speed))
	arena.rules.use_skill(GodFavor.Slot.Q, arena._my_id)
	arena._update_movement_favors(0.0)
	_check(is_equal_approx(arena.player.move_speed, base_speed * 0.95),
		"...and a recharging Q takes it (%s)" % str(arena.player.move_speed))

	# The E casts the gales; a recast while they blow is a tailwind instead.
	arena._wind_time = 0.0
	arena._wind_boost.clear()
	arena._apply_skill_effect(west, arena._my_id)
	_check(arena._wind_time > 0.0 and arena.wind_active(), "The West Wind sets the gales on the field")
	arena._apply_skill_effect(west, arena._my_id)
	_check(arena._wind_boost.has(arena._my_id), "...and a cast while they already blow gives the caster a tailwind")

	arena.queue_free()
	await process_frame

	print("Anitun Tabu checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


# A match with Anitun Tabu hosting: the local mortal and the named rivals.
func _match(rivals: Array = ["A"]) -> GodMatch:
	var rules := GodMatch.new()
	_view.add_child(rules)
	rules.setup(Gods.anitun_tabu(), "ME", rivals)
	rules.trial_active = true
	rules.begin_trial()
	return rules


# Let the popups and shakes the last hit spawned settle before the next one.
func _settle(arena) -> void:
	arena._tick_shake(1.0)
	arena._tick_flash(1.0)
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
