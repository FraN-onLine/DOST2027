extends SceneTree

# Validation: Langit Lupa's right-click chant, the one-Langit-at-a-time crumble
# and Ikapati's blitz. The chant starts on `defend` (right click) and never on
# `attack`, even with an old binding that put Defend on left click (which Settings
# migrates back); a runner stepping off a Langit crumbles only that one, and a new
# one forms within about 1 s at a legal spot; a full chant dooms the occupied
# Langit, which crumble after swap_time (not before, even when their runner steps
# off) and form again; the bots re-target when their Langit crumbles; at 30 s left
# the blitz is on and the season turns every 3 s; Ikapati comes back as a second
# Taya if the gods had left, and stays if they are still Taya; her first tag as
# the only Taya makes that runner Taya and she stays; with a mortal Taya her tag
# costs the runner tag_steal and passes nothing; she never leaves in the blitz.
# Run: godot --headless --path <project> -s res://tools/langit_blitz_check.gd

const DT := 0.125  # exact in binary, so the timers land on the beat
const SPOTS: Array[Vector2] = [Vector2(500, 300), Vector2(800, 300), Vector2(800, 450)]
const LUPA := Vector2(650, 380)
const FAR := Vector2(1080, 560)
const SETTINGS_FILE := "user://langit_blitz_settings.cfg"

var _arena: LangitLupaArena
var _rules: GodMatch
var _problems := 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _run() -> void:
	await _frames(2)  # (Settings is ready)
	_check_binding_migration()
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
	_arena._start_countdown()
	_arena._start_trial()
	_check(_arena._cloud_id.size() == _arena._langits.size() and _arena._cloud_state.size() == _arena._langits.size(),
		"every Langit slot has an id and a state (%d slots)" % _arena._langits.size())

	# --- the chant: right click, never left click ---------------------------------------------
	_reset(1)
	_put(1, LUPA)
	_put(2, FAR)
	_put(3, FAR + Vector2(0, -60))
	var left := _click(MOUSE_BUTTON_LEFT)
	_arena._input(left)
	_check(not _arena._chanting, "LEFT CLICK (attack) does not start the chant")
	_arena._input(_click(MOUSE_BUTTON_RIGHT))
	_check(_arena._chanting, "RIGHT CLICK (defend) starts the chant")
	_reset(1)
	InputMap.action_add_event("defend", left)  # an old binding: Defend on Attack's button too
	_arena._input(left)
	_check(not _arena._chanting, "...and even with Defend bound to left click, a click that is also Attack never chants")
	InputMap.action_erase_event("defend", left)
	_arena._refresh_hud(0.0)
	_check(_arena.hint_label == null or _arena.hint_label.text.contains("[RIGHT CLICK] CHANT"),
		"the Taya's hint says [RIGHT CLICK] CHANT (%s)" % (_arena.hint_label.text if _arena.hint_label != null else ""))

	# --- the bots re-target when their Langit crumbles ------------------------------------------
	_check(_arena._bots.size() == 2, "(solo: two bots)")
	_reset(1)
	_put(1, FAR)
	_put_bot(2, LUPA)
	_arena._bot_goal[2] = 0
	_arena._crumble(0)
	_arena._bot_heading(2, LUPA, DT)
	var goal := int(_arena._bot_goal.get(2, -1))
	_check(goal >= 0 and goal != 0, "a bot running for a Langit that crumbles picks another one (%d)" % goal)
	_reset(1)
	_put(1, FAR)
	_put_bot(2, FAR + Vector2(-40, 0))
	_put_bot(3, SPOTS[1])
	_arena._crumble(1)
	for step in range(8):
		_arena._bot_heading(3, SPOTS[1], DT)
	goal = int(_arena._bot_goal.get(3, -1))
	_check(goal >= 0 and goal != 1, "a bot sitting on a Langit that crumbles runs for another one (%d)" % goal)
	for bot in _arena._bots.values():
		bot.queue_free()
	_arena._bots.clear()

	# --- stepping off crumbles only that Langit ------------------------------------------------
	_reset(3)
	_put(3, FAR)
	_put(1, SPOTS[0])
	_put(2, SPOTS[1])
	_tick(DT)
	var ids: Array[int] = _arena._cloud_id.duplicate()
	_check(_arena.is_safe(1) and _arena.is_safe(2), "(two runners on two Langit)")
	_put(1, LUPA)
	_tick(DT)
	_check(_arena._cloud_state[0] == LangitLupaArena.Cloud.CRUMBLING, "stepping off a Langit crumbles it")
	_check(_arena._cloud_state[1] == LangitLupaArena.Cloud.SOLID and _arena._cloud_state[2] == LangitLupaArena.Cloud.SOLID,
		"...and only that one")
	_arena._draw_langits(0.0)
	_check((_arena.langits_root.get_child(0) as Node2D).visible and (_arena.langits_root.get_child(1) as Node2D).modulate.a == 1.0,
		"...it is still drawn while it shakes, and the others are not touched")
	var formed_at := -1.0
	var gone_seen := false
	var time := 0.0
	while time < 1.5 and formed_at < 0.0:
		_tick(DT)
		time += DT
		gone_seen = gone_seen or _arena._cloud_state[0] == LangitLupaArena.Cloud.GONE
		if _arena._cloud_id[0] != ids[0]:
			formed_at = time
	_check(gone_seen, "it falls (GONE) after its shake")
	_check(formed_at > 0.0 and formed_at <= 1.05, "a new Langit forms in its slot within about 1 s (%.1fs)" % formed_at)
	var area: Rect2 = _arena._langit_area()
	var legal := area.has_point(_arena._langits[0])
	for other in [1, 2]:
		legal = legal and not _arena.langit_rect(0).grow(4.0).intersects(_arena.langit_rect(other))
	_check(legal, "...at a legal spot: on the field, clear of the UI strip, on no other Langit (%s)" % str(_arena._langits[0]))
	_check(_arena._langits[1] == SPOTS[1] and _arena._langits[2] == SPOTS[2] and _arena._cloud_id[1] == ids[1] and _arena._cloud_id[2] == ids[2],
		"the other Langit never moved")
	_check(_arena._season_timer > 900.0, "(no season turned: the slot moved by itself)")

	# --- a full chant dooms the occupied Langit; they crumble after swap_time --------------------
	_reset(3)
	_set_favor(1000, 1000, 1000)
	_put(3, FAR)
	_put(1, SPOTS[0])
	_put(2, SPOTS[1])
	_tick(DT)
	ids = _arena._cloud_id.duplicate()
	_full_chant(3)
	_check(_arena.is_closed_for(1, 0) and int(_arena._closed[1]) == ids[0], "ALIS closes the runner's Langit by its id (%s)" % str(_arena._closed))
	_put(1, LUPA)  # runner 1 steps off at once; runner 2 stays put
	_tick(DT)
	_check(_arena._cloud_state[0] == LangitLupaArena.Cloud.SOLID and _arena._cloud_state[1] == LangitLupaArena.Cloud.SOLID,
		"inside the swap window the doomed Langit stay up (stepping off does not crumble them early)")
	_tick(_arena.swap_time - DT - 0.05)
	_check(_arena._cloud_state[0] == LangitLupaArena.Cloud.SOLID and _arena._cloud_state[1] == LangitLupaArena.Cloud.SOLID,
		"...right up to swap_time")
	_tick(0.1)
	_check(_arena._cloud_state[0] == LangitLupaArena.Cloud.CRUMBLING and _arena._cloud_state[1] == LangitLupaArena.Cloud.CRUMBLING,
		"after swap_time every occupied Langit crumbles")
	_check(_arena._cloud_state[2] == LangitLupaArena.Cloud.SOLID and _arena._cloud_id[2] == ids[2], "...the empty one does not")
	_tick(_arena.crumble_time)
	_check(not _arena.is_safe(2) and _arena._cloud_state[1] == LangitLupaArena.Cloud.GONE, "whoever stayed on one drops to the Lupa when it falls")
	_check(not _arena._closed.has(1), "a closed Langit that fell is no longer anyone's")
	_tick(_arena.reform_delay)
	_check(_arena._cloud_id[0] != ids[0] and _arena._cloud_id[1] != ids[1] and _arena._cloud_state[0] == LangitLupaArena.Cloud.FORMING,
		"...and new ones form right after (reform_delay later)")
	_check(not _arena.is_closed_for(1, 0), "a Langit formed again in the same slot is not locked to its old runner")

	# --- the blitz at 30 s left ----------------------------------------------------------------
	_check(not _arena._blitz and is_equal_approx(_arena.season_length(), _arena.season_interval), "before the blitz the season turns every %ds" % int(_arena.season_interval))
	# the gods left earlier: Ikapati comes back as a second Taya
	_reset(3)
	_set_favor(1000, 1000, 1000)
	_put(3, Vector2(700, 400))
	_put(1, FAR)
	_put(2, SPOTS[1])
	_arena._season_timer = 9.0
	_arena._trial_time = _arena.langit_blitz_time + 0.5
	_tick(DT)
	_check(not _arena._blitz, "no blitz at %.1fs left" % _arena._trial_time)
	_arena._trial_time = _arena.langit_blitz_time
	_tick(DT)
	_check(_arena._blitz, "at %ds left the blitz is on" % int(_arena.langit_blitz_time))
	_check(is_equal_approx(_arena.season_length(), 3.0) and _arena._season_timer <= 3.0,
		"...the season turns every 3 s (%.1fs to the next)" % _arena._season_timer)
	_check(_arena.hud.banner_label.text == "BLITZ!", "...one BLITZ! banner (%s)" % _arena.hud.banner_label.text)
	_check(_arena.second_taya() and _arena.taya_id() == 3 and _arena._god_leave == 0.0,
		"with the gods gone, Ikapati comes back as a second Taya beside the mortal one")
	_check(_arena._god_at.distance_to(_arena.mortal_position(3)) >= _arena.taya_clearance and _arena._push_out(_arena._god_at) == _arena._god_at,
		"...on the Lupa, taya_clearance from the mortal Taya (%s)" % str(_arena._god_at))
	_arena._process(0.0)
	_check(_arena._god_body.visible and _arena._god_body.modulate.a < 1.0, "...her body fades in")
	_check(_arena.taya_marker.visible and _arena._god_marker.visible, "two TAYA markers are drawn")
	_check(_arena.strip_note().contains("BLITZ") and _arena.status_label.text.begins_with("BLITZ"),
		"the strip and the band say BLITZ (%s / %s)" % [_arena.strip_note(), _arena.status_label.text])
	var keys := _arena.arena_local_effects().map(func(entry: Dictionary) -> StringName: return entry["key"])
	_check(keys.has(&"blitz"), "...and a BLITZ effect timer runs (%s)" % str(keys))
	var tick := _arena.arena_tick_fields()
	_check(tick.get("blitz") == true and tick.has("god_at") and tick.has("god_step") and tick.has("cloud_state") and tick.has("cloud_id"),
		"the blitz, Ikapati and every Langit's state ride the tick")
	# her tag passes nothing while a mortal is Taya
	_arena._god_time = 999.0
	_arena._move_god(DT)
	_check(_arena.god_hunt_id() == -1, "her safety-valve hunt is off in the blitz")
	_put(1, _arena._god_at + Vector2(10, 0))
	_set_favor(1000, 1000, 1000)
	_arena._streak[1] = 3
	_arena._check_god_tag()
	_check(_arena.taya_id() == 3, "her tag does not change the Taya")
	_check(_rules.mortal(1).favor == 1000 - _arena.tag_steal and _rules.mortal(3).favor == 1000 and _rules.mortal(2).favor == 1000,
		"...it costs the runner tag_steal, and nobody gains it (%d / %d)" % [_rules.mortal(1).favor, _rules.mortal(3).favor])
	_check(_arena.streak_of(1) == 0, "...and ends their streak")
	_check(_arena._god_leave == 0.0 and _arena.second_taya(), "...and she does not leave")
	_arena._check_god_tag()
	_check(_rules.mortal(1).favor == 1000 - _arena.tag_steal, "tagged_mercy stops her chain-tagging the same runner")
	# her chant dooms the occupied Langit too, and pays nobody
	_reset(3)
	_arena._blitz = true
	_arena._god_at = SPOTS[0] + Vector2(0, 70)
	_put(3, FAR)
	_put(1, SPOTS[0])
	_put(2, SPOTS[1])
	_set_favor(1000, 1000, 1000)
	_arena._bot_taya_heading(LangitLupaArena.GOD_TAYA, _arena._god_at)
	_check(_arena._god_step == 0 and not _arena._chanting, "with every runner safe she chants her own chant (the mortal Taya's stays free)")
	_arena._god_fail_at = -1
	for word in range(_arena.chant_length + 1):
		_arena._tick_god_chant(_arena.god_chant_beat + 0.01)
	_check(is_equal_approx(_arena.swap_left(1), _arena.swap_time) and _arena._doomed(0) and _arena._doomed(1),
		"her ALIS sends them off and dooms their Langit")
	_check(_rules.mortal(3).favor == 1000, "...and the mortal Taya is not paid for her chant")

	# the gods still Taya at 30 s: Ikapati stays; her first tag hands it on and she stays
	_reset(1)
	_set_favor(1000, 1000, 1000)
	_arena._gods_take_taya()
	_arena._god_at = Vector2(650, 450)
	_put(1, FAR)
	_put(2, SPOTS[1])
	_put(3, FAR + Vector2(0, -60))
	_arena._trial_time = _arena.langit_blitz_time
	_tick(0.0)
	_check(_arena._blitz and _arena.taya_id() == LangitLupaArena.GOD_TAYA and _arena._god_at.distance_to(Vector2(650, 450)) < 1.0,
		"with the gods still Taya at 30 s, Ikapati stays where she is, as the Taya")
	_arena._tagback = 0.0
	_put(2, _arena._god_at + Vector2(10, 0))
	_arena._check_tag()
	_check(_arena.taya_id() == 2, "her first tag makes that runner the Taya")
	_check(_arena._god_leave == 0.0 and _arena._god_at != Vector2.INF and _arena.second_taya(), "...and she stays on as the second Taya (no Ikaw na! exit)")
	_arena._move_god(_arena.god_leave_time + 1.0)
	_check(_arena._god_at != Vector2.INF, "...for good")
	# Taya drain is the mortal Taya's only
	_arena._drain_pending.clear()
	_tick(DT)
	_check(_arena._drain_pending.keys() == [2], "the drain runs for the mortal Taya only (%s)" % str(_arena._drain_pending.keys()))
	# a client mirrors the blitz from the tick: one banner
	tick = _arena.arena_tick_fields()
	_arena._blitz = false
	_arena.hud.banner_label.text = ""
	_arena.arena_read_tick(tick)
	_check(_arena._blitz and _arena.hud.banner_label.text == "BLITZ!", "a client reading the tick enters the blitz with the same banner")

	print("Langit Lupa blitz checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


# A saved settings file from an older build with Defend on Attack's button.
func _check_binding_migration() -> void:
	var settings: Node = root.get_node("Settings")
	var saved_path: String = settings.config_path
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "attack", {"type": "mouse", "button": MOUSE_BUTTON_LEFT})
	cfg.set_value("controls", "defend", {"type": "mouse", "button": MOUSE_BUTTON_LEFT})
	cfg.save(SETTINGS_FILE)
	settings.config_path = SETTINGS_FILE
	settings.load_config()
	var defend: InputEvent = settings.primary_event("defend")
	_check(defend is InputEventMouseButton and (defend as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT,
		"a saved Defend on Attack's left click goes back to right click")
	var reread := ConfigFile.new()
	reread.load(SETTINGS_FILE)
	_check(not reread.has_section_key("controls", "defend") and reread.has_section_key("controls", "attack"), "...once: the fixed file is saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	settings.config_path = saved_path
	settings.load_config()


# Three Langit where SPOTS says, `taya` is it, nothing left over, no blitz, and
# the season will not turn by itself.
func _reset(taya: int) -> void:
	_arena._phase = Arena.Phase.PLAYING
	_arena._clear_clouds()
	for spot in SPOTS:
		_arena._add_cloud(spot)
	for runners in [_arena._swap, _arena._closed, _arena._shoving, _arena._on, _arena._last_left, _arena._close_call, _arena._streak, _arena._bot_goal, _arena._bot_react]:
		runners.clear()
	_arena._season_timer = 1000.0
	_arena._trial_time = 50.0
	_arena._blitz = false
	_arena.set_taya(taya)
	_arena._god_at = Vector2.INF
	_arena._god_leave = 0.0
	_arena._god_hunt = -1
	_arena._god_time = 0.0
	_arena._reset_god_chant()
	_arena._bot_chant.clear()
	_arena._tagback = 0.0
	_arena._chant_cd = 0.0
	_arena._invuln.clear()
	_arena._my_chanting = false
	_arena._my_stumble = 0.0
	_arena._set_rooted(false)


func _tick(seconds: float) -> void:
	_arena.arena_rules_tick(seconds)


func _full_chant(taya: int) -> void:
	_arena._on_chant_message(taya, "start", 0)
	for word in range(1, _arena.chant_length + 1):
		_arena._on_chant_message(taya, "step", word)
	_arena._on_chant_message(taya, "result", 1)


func _click(button: MouseButton) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.pressed = true
	click.position = Vector2(700, 300)  # on the field, away from the favor panels
	return click


func _set_favor(mine: int, rival: int, rival_two: int) -> void:
	_rules.mortal(1).favor = mine
	_rules.mortal(2).favor = rival
	_rules.mortal(3).favor = rival_two


func _put(id: int, at: Vector2) -> void:
	if id == _arena._my_id:
		_arena.player.global_position = at
	else:
		_arena._mortal_positions[id] = at


func _put_bot(id: int, at: Vector2) -> void:
	_arena._bots[id].global_position = at
	_arena._mortal_positions[id] = at


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
