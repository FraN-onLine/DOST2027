class_name Playground
extends PrepArea

# THE PLAYGROUND - PAHINGA, OPENED TO EVERY GOD.
#
# The same camp as the preparation area (scripts/prep/prep_area.gd): the fire, the
# shared field, the mortals' walk. Instead of the one altar of the god who just
# hosted, there is an altar of EVERY god - authored under Camp in Playground.tscn,
# three above the fire, two beside it and three below - each one giving that god's
# favors for free (Gods.all() - Bathala's too). A DUMMY rival, also authored there
# under Ghosts, stands off to the left to aim them at. Nothing is timed and nothing
# closes: walk up to an altar, press F, take a blessing, then E / Q to try it; walk
# to the fire and left click to play any god's game on its own. Esc (or LEAVE)
# walks out to the menu.
#
# WHY IT STILL EXTENDS THE PREP AREA: it inherits the camp's scene, its fire, its
# altar art and its network plumbing; it runs no rest at all - no clock, no READY,
# no Tindahan, no trial end - and keeps the phase PLAYING so the favors, their
# cooldowns, the per-second passives (It's Kinda Tabu), the winds of Anitun Tabu's
# E (which shove the dummy, never their own caster), the afflictions (a stolen
# drowsiness, a dragged root) and the skill bars all behave exactly as they do in
# a trial.
#
# THE DUMMY: solo rules still create the rival when the scene asks for it
# (simulate_rivals = true in Playground.tscn). We turn the FAVOR ticker off and
# give that rival a body: a locked ghost, registered where every rule already
# looks for a rival (mortal_node, rules.mortals, the position map). So a skill
# that reaches "every other mortal" reaches it - and the 3-2-1, the stars and the
# root leash are drawn on its head the same way they are on a player's.

const DUMMY_ID := 2
const DUMMY_BANDANA := 6  # orange, so it never reads as our own mortal
# How close the mortal may press before the dummy is shoved along: the two
# capsules touch at 40 px, so a little past that keeps the push going while the
# walk holds into it.
const DUMMY_PUSH_GAP := 44.0
const ALTAR_REACH := 120.0
# How close to the fire a left click opens the game list. The mortal spawns across
# the field from it, so they walk up to it - and the click never fights an altar
# (those are F), so standing by one is no obstacle.
const CAMPFIRE_REACH := 110.0
const TRIAL_TEST_SCENE := "res://scenes/prep/TrialTest.tscn"

@onready var leave_button: Button = get_node_or_null("PrepHud/LeaveButton") as Button
@onready var campfire: Node2D = get_node_or_null("Camp/Campfire") as Node2D
# Untyped on purpose: the menu is a scene script, not a class the headless checks
# must know before the project imports it.
@onready var game_menu = get_node_or_null("GameTestLayer/GameTestMenu")

var _altars: Dictionary = {}  # Node2D -> God (the altar's own list)
var _menu_god: God = null     # the altar whose menu is open / was last open
var _last_near: Node2D = null
var _last_fire_near := false


# --- OPENING ---------------------------------------------------------------------

# The base already built the rules, the HUD, the camp and the mortal. Open the
# playground at once: no dialogue, no countdown, no rest, no clock.
func _start_intro() -> void:
	_phase = Phase.PLAYING
	rules.simulate_rivals = false  # the dummy is a target, not a rival gathering FAVOR
	rules.trial_active = false     # no per-trial harvest/pamana ticker here
	rules.passives_live = true     # ...but per-second passives (It's Kinda Tabu) do run
	rules.time_left = INF          # nor any "last seconds" passive
	player.clear_trial_state()
	player.set_lock(false)
	popups_enabled = true
	_collect_altars()
	_spawn_dummy()
	_style_hud()
	due_menu.boon_chosen.connect(_on_boon_chosen)
	if leave_button != null:
		leave_button.pressed.connect(_leave)
	if game_menu != null:
		game_menu.test_requested.connect(_launch_test)
		game_menu.closed.connect(_on_game_menu_closed)
	_show_banner("PLAYGROUND", UITokens.GOLD, 2.0)
	_log("Stand by an altar and press %s for its blessings." % key_cap(&"due_menu"), UITokens.MUTED)
	_log("Left click the campfire to test any game.", UITokens.MUTED)


func _style_hud() -> void:
	hud.event_label.visible = true
	hud.event_label.offset_left = Arena.UI_STRIP_WIDTH + 4.0
	hud.event_label.offset_top = -80.0
	hud.event_label.offset_bottom = -56.0
	hud.banner_label.offset_top = 96.0
	hud.banner_label.offset_bottom = 144.0
	hud.get_node("TrialPanel").visible = false
	hud.god_label.text = "PLAYGROUND"
	hud.god_label.add_theme_color_override("font_color", UITokens.GOLD)
	hud.game_label.text = "EVERY GOD'S BLESSINGS"
	next_label.visible = true
	next_label.add_theme_color_override("font_color", UITokens.GOLD)
	next_label.text = "PLAYGROUND - STAND BY AN ALTAR"
	ready_label.visible = false
	stall.visible = false
	hint_label.text = "%s WALK   %s GAME TESTS   %s BLESSING   %s %s FAVOR   [ESC] LEAVE" % [
		key_cap(&"move_left"), key_cap(&"attack"), key_cap(&"due_menu"),
		key_cap(&"skill_e"), key_cap(&"skill_q")]


# The altars are authored under Camp in Playground.tscn, each naming its god in
# `god_id` metadata. This only paints them from the god resources and remembers
# whose each one is - move or retune an altar in the scene, never here.
func _collect_altars() -> void:
	var camp := get_node("Camp") as Node2D
	_altars.clear()
	for child in camp.get_children():
		var god_id := StringName(str(child.get_meta("god_id", "")))
		if god_id == &"":
			continue
		var altar_god := Gods.by_id(god_id)
		if altar_god == null or altar_god.id != god_id:
			continue
		_paint_altar(child as Node2D, altar_god)
		_altars[child] = altar_god


func _paint_altar(altar: Node2D, altar_god: God) -> void:
	var icon := altar.get_node("GodIcon") as Sprite2D
	var name_label := altar.get_node("Name") as Label
	var hint := altar.get_node("Hint") as Label
	if altar_god.icon != null:
		icon.texture = altar_god.icon
		icon.scale = Vector2.ONE * ALTAR_ICON_SIZE / maxf(1.0, float(altar_god.icon.get_width()))
	name_label.text = "ALTAR OF %s" % altar_god.display_name
	name_label.add_theme_color_override("font_color", UITokens.god_text(altar_god))
	hint.text = "%s - BLESSING" % key_cap(&"due_menu")
	hint.add_theme_color_override("font_color", UITokens.MUTED)


# The dummy: the rival the rules already made (id 2) gets the body authored under
# Ghosts in Playground.tscn, where every rule looks for a rival.
func _spawn_dummy() -> void:
	var dummy: ArenaMortal = ghosts_root.get_node_or_null("Dummy") as ArenaMortal
	if dummy == null:
		dummy = MORTAL_SCENE.instantiate() as ArenaMortal
		ghosts_root.add_child(dummy)
	dummy.set_lock(true)
	dummy.ring_color = UITokens.EMBER
	dummy.set_bandana(DUMMY_BANDANA)
	var tint := UITokens.readable_on_dark(UITokens.bandana_color(DUMMY_BANDANA), UITokens.NIGHT_900)
	dummy.set_tag_color(tint)
	dummy.set_display_name("DUMMY", tint)
	_ghosts[DUMMY_ID] = dummy
	_mortal_positions[DUMMY_ID] = dummy.global_position
	rules.local().favor = 1000
	if rules.mortal(DUMMY_ID) != null:
		rules.mortal(DUMMY_ID).favor = 1000


# --- THE ALTARS -------------------------------------------------------------------

# The altar the mortal stands by (null when none is within reach).
func _nearest_altar() -> Node2D:
	var best: Node2D = null
	var best_distance := ALTAR_REACH
	for altar in _altars.keys():
		var distance := player.global_position.distance_to((altar as Node2D).global_position)
		if distance <= best_distance:
			best_distance = distance
			best = altar
	return best


func _near_fire() -> bool:
	return campfire != null and player.global_position.distance_to(campfire.global_position) <= CAMPFIRE_REACH


func _game_menu_open() -> bool:
	return game_menu != null and game_menu.is_open()


# The campfire opens the game list: every god's game, playable on its own.
func _open_game_menu() -> void:
	if game_menu == null or _game_menu_open():
		return
	if due_menu.is_open():
		due_menu.close()
	player.set_lock(true)
	game_menu.open()


func _on_game_menu_closed() -> void:
	if player != null:
		player.set_lock(false)


# The list asked for one god's trial: hand the god over and let the wrapper run
# it. The Playground is rebuilt (fresh favor, fresh dummy) when the test returns.
func _launch_test(god_id: StringName) -> void:
	if god_id == &"":
		return
	Global.test_god_id = god_id
	get_tree().change_scene_to_file(TRIAL_TEST_SCENE)


# The base's God's Due menu as an altar: the nearest god's whole list, free.
func _toggle_due_menu() -> void:
	if due_menu.is_open():
		due_menu.close()
		return
	var altar := _nearest_altar()
	if altar == null:
		_log("Stand by an altar to ask for its blessings.", UITokens.FAINT)
		return
	_menu_god = _altars[altar] as God
	due_menu.open(_menu_god, rules, 0, false, 0, 0, true)


func _on_boon_chosen(favor: GodFavor) -> void:
	if favor == null or _menu_god == null or _menu_god.get_favor(favor.id) != favor:
		return
	if not rules.bestow_favor(favor):
		_log("%s already belongs to you" % favor.display_name, UITokens.FAINT)
		return
	_announce_grant(favor)
	if _authority and _networked:
		_publish_god_state()


# Bathala's two sacrifices resolve in GodMatch and borrow the sisters' curses;
# the shared arena leaves them to Bathala's own arena, so the playground - which
# hosts any god - plays them here. Everything else is the shared behavior.
func _apply_skill_effect(favor: GodFavor, caster_id: int) -> void:
	if favor == null:
		return
	if favor.id == &"half_vision_sacrifice" and _authority:
		var target_id := rules.cast_half_vision(caster_id, favor)
		if target_id < 0:
			_log("Blindside - no other mortal to reach", favor.color)
		elif caster_id == _my_id:
			_log("Blindside - %s loses half its FAVOR" % mortal_label(target_id), favor.color)
		else:
			_blind_time = maxf(_blind_time, favor.duration)
		_publish_god_state()
		return
	if favor.id == &"siblings_compromise_bathala" and _authority:
		rules.cast_siblings_compromise(caster_id, favor)
		_publish_god_state()
		return
	super._apply_skill_effect(favor, caster_id)


# Bathala's two instant curses ("Our Partnership Ends Here"): the match has paid
# the cost and marked the curse, but only Bathala's own arena plays them - the
# Playground hosts every god, so it darkens the field or sears it here.
func _on_favor_fired(player_id: int, favor: GodFavor, text: String) -> void:
	super._on_favor_fired(player_id, favor, text)
	if not _authority or favor == null:
		return
	if favor.id == &"our_partnership_ends_mayari":
		var dark := maxf(0.0, favor.duration if favor.duration > 0.0 else favor.param("blind_duration", 10.0))
		if player_id == _my_id:
			_log("The field goes dark for everyone else", favor.color)
		else:
			_blind_time = maxf(_blind_time, dark)
			_log("Mayari's curse - you see only a circle around your mortal", favor.color)
	elif favor.id == &"our_partnership_ends_apolaki":
		var duration := float(favor.param("sun_duration", 10.0))
		var count := int(favor.param("sun_count", 4.0))
		for other in rules.mortals.values():
			if other.id != player_id:
				_add_sun_patches(other.id, count, duration, player_id)
		_publish_god_state()


# The follow camera's arrows (the lobby's camera is off in a solo playground, but
# a screen that turns it on should still point at what there is to visit).
func edge_targets() -> Array:
	return _altars.keys()


# The gales push the dummy the way they push a rival's body on its own screen:
# the caster holds The West Wind (and its gale_immunity clause), so here the
# dummy is what the wind is seen to move. It stays locked - the rules' copy of
# its position moves with it, or the ghost glide would pull it straight back.
func _drift_dummy(delta: float) -> void:
	var dummy := _ghosts.get(DUMMY_ID) as ArenaMortal
	if dummy == null or not is_instance_valid(dummy) or wind_push == Vector2.ZERO:
		return
	var here := dummy.global_position + wind_push * delta
	if _field.size != Vector2.ZERO:
		var inset := Vector2(dummy.radius, dummy.radius)
		here = here.clamp(_field.position + inset, _field.end - inset)
	dummy.global_position = here
	_mortal_positions[DUMMY_ID] = here


# --- FRAME ------------------------------------------------------------------------

# No trial flow and no rest clock: the world's own frame, the favors that are
# running, and this screen's title / nearest altar.
func _process(delta: float) -> void:
	_tick_fire(delta)
	if _game_menu_open():
		return
	_tick_invuln(delta)
	_tick_sun_favors(delta)
	_tick_world(delta)
	_push_dummy()
	_drift_dummy(delta)
	_refresh_playground_hud()


# The dummy is a body to lean on: walking into it shoves it along the field,
# still locked so it never walks on its own. The rules' copy of its position
# moves with it, or the ghost glide would pull it straight back.
func _push_dummy() -> void:
	var dummy := _ghosts.get(DUMMY_ID) as ArenaMortal
	if dummy == null or not is_instance_valid(dummy) or player == null:
		return
	var away := dummy.global_position - player.global_position
	if away.length() >= DUMMY_PUSH_GAP:
		return
	var way := away.normalized() if away.length() > 0.01 else Vector2(player.facing, 0.0)
	var here := player.global_position + way * DUMMY_PUSH_GAP
	if _field.size != Vector2.ZERO:
		var inset := Vector2(dummy.radius, dummy.radius)
		here = here.clamp(_field.position + inset, _field.end - inset)
	dummy.global_position = here
	_mortal_positions[DUMMY_ID] = here


func _refresh_playground_hud() -> void:
	var near := _nearest_altar()
	var by_fire := _near_fire()
	if near == _last_near and by_fire == _last_fire_near:
		return
	_last_near = near
	_last_fire_near = by_fire
	if near != null:
		var altar_god: God = _altars[near]
		next_label.text = "ALTAR OF %s - %s BLESSING" % [altar_god.display_name.to_upper(), key_cap(&"due_menu")]
		next_label.add_theme_color_override("font_color", UITokens.god_text(altar_god))
		return
	if by_fire:
		next_label.text = "CAMPFIRE - %s TEST A GAME" % key_cap(&"attack")
		next_label.add_theme_color_override("font_color", UITokens.GOLD)
		return
	next_label.text = "PLAYGROUND - STAND BY AN ALTAR"
	next_label.add_theme_color_override("font_color", UITokens.GOLD)


# --- INPUT ------------------------------------------------------------------------

# The skill bars are tappable exactly as in a trial, and a left click at the fire
# opens the game list - even beside an altar, which only listens to F.
func _input(event: InputEvent) -> void:
	if _game_menu_open():
		return
	if _tap_panel_click(event):
		return
	if not (event is InputEventMouseButton) or not event.is_action_pressed("attack"):
		return
	if due_menu.is_open() or not _near_fire():
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	_open_game_menu()


# Only what the playground allows: F at an altar, E / Q for the favors they hold,
# Esc to leave (or to close the altar / the game list first), and R to start over.
func _unhandled_input(event: InputEvent) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	if _game_menu_open():
		if event.is_action_pressed("ui_cancel"):
			viewport.set_input_as_handled()
			game_menu.close()
		return
	if event.is_action_pressed("ui_cancel"):
		viewport.set_input_as_handled()
		if due_menu.is_open():
			due_menu.close()
		else:
			_leave()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		viewport.set_input_as_handled()
		get_tree().reload_current_scene()
		return
	if event.is_action_pressed("due_menu"):
		viewport.set_input_as_handled()
		_toggle_due_menu()
		return
	if due_menu.is_open():
		return
	if event.is_action_pressed("skill_e"):
		_use_skill(GodFavor.Slot.E)
	elif event.is_action_pressed("skill_q"):
		_use_skill(GodFavor.Slot.Q)
