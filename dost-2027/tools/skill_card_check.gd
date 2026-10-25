extends SceneTree

# Validation: the E / Q skill cards (UI/GodsArena/skill_card.tscn, god_hud.gd).
#   * a skill taken from a God's Due, a boon or a god's gift announces itself
#     (GodMatch.skill_gained, with the skill it replaced) - a passive favor does not,
#     and neither does a favor the mortal arrived at the trial with
#   * the popup card shows the key, the icon, the name, the one-line description, the
#     cooldown and REPLACES <old skill>; two gains at once queue; it closes after
#     popup_seconds, on a click on it, or on the skill's own key - and a click on it is
#     never an attack
#   * the same card shows as info while the mouse is over a skill bar and, for both
#     skills, while skill_info (Tab) is held
#   * skill_info is a rebindable action
#   * a cast puts the god's E icon over the mortal that used it (an E skill), or the
#     skill's name (a Q skill), on its own screen and on a rival's
# Run: godot --headless --path <project> -s res://tools/skill_card_check.gd

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
	await _frames(2)
	var network: Node = root.get_node("Network")
	var settings: Node = root.get_node("Settings")

	# --- the key ---------------------------------------------------------------------------------
	_check(InputMap.has_action("skill_info") and Settings.ACTIONS.has("skill_info"), "skill_info is an action the Controls tab can rebind")
	var event := InputMap.action_get_events("skill_info")
	_check(not event.is_empty() and event[0] is InputEventKey and (event[0] as InputEventKey).physical_keycode == KEY_TAB, "...and it is Tab by default")

	# --- the match announces a skill -----------------------------------------------------------
	var mayari := Gods.mayari()
	# Two E skills (Mayari's Half Vision and Tala's Let Us Light Your Way), a Q skill
	# and a passive: nothing here asks for another favor first.
	var e_one := Gods.favor_by_id(&"half_vision")
	var e_two := Gods.favor_by_id(&"let_us_light_your_way")
	var q_one := Gods.favor_by_id(&"siblings_compromise")
	var passive := Gods.favor_by_id(&"waning_moon")
	_check(e_one != null and e_two != null and q_one != null and passive != null
		and e_one.slot == GodFavor.Slot.E and e_two.slot == GodFavor.Slot.E and q_one.slot == GodFavor.Slot.Q and not passive.is_skill(),
		"two E skills, a Q skill and a passive to test with")
	var rules := GodMatch.new()
	root.add_child(rules)
	rules.setup(mayari, "ME")
	var gains: Array = []
	rules.skill_gained.connect(func(id: int, favor: GodFavor, replaced: GodFavor) -> void: gains.append([id, favor, replaced]))
	rules.bestow_favor(e_one)
	_check(gains.size() == 1 and gains[0][1] == e_one and gains[0][2] == null, "a skill into an empty slot is announced, replacing nothing")
	rules.bestow_favor(e_two)
	_check(gains.size() == 2 and gains[1][1] == e_two and gains[1][2] == e_one, "a skill that takes a slot names the skill it replaced")
	rules.bestow_favor(passive)
	_check(gains.size() == 2, "a passive favor is not a skill: no announcement")
	# A client reads it off the host's snapshot - but only once the shell says what it arrived with is in.
	var host := GodMatch.new()
	root.add_child(host)
	host.setup_peers(mayari, {1: "HOST", 2: "CLIENT"}, 1)
	var client := GodMatch.new()
	root.add_child(client)
	client.setup_peers(mayari, {1: "HOST", 2: "CLIENT"}, 2)
	host.bestow_favor(e_one, 2)
	var seen: Array = []
	client.skill_gained.connect(func(id: int, favor: GodFavor, replaced: GodFavor) -> void: seen.append([id, favor, replaced]))
	client.apply_snapshot(host.snapshot())
	_check(seen.is_empty() and client.mortal(2).has_favor(e_one.id), "what a mortal arrives with (a snapshot before announce_gains) is not announced")
	client.announce_gains = true
	host.bestow_favor(e_two, 2)
	client.apply_snapshot(host.snapshot())
	_check(seen.size() == 1 and seen[0][0] == 2 and seen[0][1] == e_two and seen[0][2] == e_one, "after that, a client announces the skill a snapshot brings, with what it replaced")
	client.apply_snapshot(host.snapshot())
	_check(seen.size() == 1, "...once: the same snapshot again says nothing")
	rules.queue_free()
	host.queue_free()
	client.queue_free()

	# --- the card on the HUD ----------------------------------------------------------------------
	var hud: Control = load("res://UI/GodsArena/god_hud.tscn").instantiate()
	view.add_child(hud)
	await _frames(2)
	var shown_match := GodMatch.new()
	view.add_child(shown_match)
	shown_match.setup(mayari, "ME")
	hud.bind(shown_match, mayari)
	shown_match.announce_gains = true
	await _frames(2)
	shown_match.bestow_favor(e_one)
	shown_match.bestow_favor(q_one)
	await _frames(2)
	var popup: SkillCard = hud._popup
	_check(popup != null and popup.favor == e_one and hud._popup_queue.size() == 1, "a gained skill pops up, and a second gain at once waits its turn")
	_check(popup.name_label.text == e_one.display_name.to_upper() and popup.desc_label.text == e_one.description,
		"the card names the skill and says what it does (%s)" % popup.name_label.text)
	_check(popup.key_label.text == UITokens.key_text(&"skill_e"), "...under the key the player has bound (%s)" % popup.key_label.text)
	_check(popup.cooldown_label.text.begins_with("COOLDOWN %d" % ceili(shown_match.skill_cooldown(GodFavor.Slot.E))) or e_one.cooldown <= 0.0,
		"...with its cooldown (%s)" % popup.cooldown_label.text)
	_check(not popup.replaces_label.visible, "...and no REPLACES when the slot was empty")
	_check(popup.mouse_filter == Control.MOUSE_FILTER_STOP and hud.card_stack.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"only the card takes the mouse: the stack and the HUD let it through")
	var outside := Vector2(900, 500)
	_check(not hud.click_skill_popup(outside) and hud._popup == popup, "a click elsewhere does not close it")
	_check(hud.click_skill_popup(popup.get_global_rect().get_center()) and hud._popup != popup and hud._popup != null and hud._popup.favor == q_one,
		"a click on it closes it, and the queued one comes up (%s)" % hud._popup.name_label.text)
	hud._unhandled_input(_key_press(&"skill_e"))
	_check(hud._popup != null, "the key of ANOTHER skill does not close it")
	hud._unhandled_input(_key_press(&"skill_q"))
	_check(hud._popup == null, "the skill's own key closes it")
	shown_match.bestow_favor(e_two)
	await _frames(2)
	_check(hud._popup != null and hud._popup.replaces_label.visible and hud._popup.replaces_label.text == "REPLACES %s" % e_one.display_name.to_upper(),
		"a skill that took a slot says REPLACES <old skill> (%s)" % hud._popup.replaces_label.text)
	hud._tick_skill_cards(hud.popup_seconds - 0.5)
	_check(hud._popup != null, "it is still up just before its time")
	hud._tick_skill_cards(1.0)
	_check(hud._popup == null and hud.card_stack.get_child_count() == 0, "it closes by itself after %.0f seconds" % hud.popup_seconds)

	# Hover over a bar, and the held key: the same card, no mouse of its own.
	hud.set_hover_slot(GodFavor.Slot.E)
	hud._tick_skill_cards(0.016)
	var info: SkillCard = hud._info_cards.get(GodFavor.Slot.E)
	_check(info != null and info.favor == e_two and info.name_label.text == e_two.display_name.to_upper() and info.desc_label.text == e_two.description,
		"the mouse over the E bar shows its card (%s)" % (info.name_label.text if info != null else "none"))
	_check(info != null and info.mouse_filter == Control.MOUSE_FILTER_IGNORE and not info.hint_label.visible, "...a tooltip: it takes no mouse and has no dismiss hint")
	hud.set_hover_slot(-1)
	hud._tick_skill_cards(0.016)
	_check(hud._info_cards.is_empty(), "...gone when the mouse leaves")
	Input.action_press("skill_info")
	hud._tick_skill_cards(0.016)
	_check(hud._info_cards.size() == 2 and hud._info_cards.has(GodFavor.Slot.Q), "holding skill_info shows both skills")
	Input.action_release("skill_info")
	hud._tick_skill_cards(0.016)
	_check(hud._info_cards.is_empty(), "...and letting go hides them")
	hud.queue_free()
	shown_match.queue_free()
	await _frames(2)

	# --- in the real run: what the mortal carries in is no gain; a click on the card is no attack ---------
	var order: Array[StringName] = [Gods.MAYARI, Gods.BATHALA]
	network.rpc_sync_trial_order(order)
	var game: Control = load("res://scenes/Game.tscn").instantiate()
	game.run_snapshot = {1: {"name": "MORTAL", "favor": 100, "due": 0, "favors": [str(e_one.id), str(q_one.id)]}}
	view.add_child(game)
	await _frames(4)
	var arena: Arena = game.arena
	_check(arena != null and game.rules.local().has_favor(e_one.id), "the run's carried favors are in the match")
	_check(arena.hud._popup == null and arena.hud._popup_queue.is_empty(), "...and they pop up nothing")
	arena.rules.bestow_favor(e_two)
	await _frames(2)
	_check(arena.hud._popup != null and arena.hud._popup.favor == e_two, "a skill gained during the trial pops up beside the shell's bars")
	var card_at: Rect2 = arena.hud._popup.get_global_rect()
	_check(card_at.position.x >= Arena.UI_STRIP_WIDTH and card_at.end.x < 1152.0 and card_at.position.y > 46.0,
		"...at the side of the field, clear of the strip and the clock (%s)" % str(card_at))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = card_at.get_center()
	if arena.dialogue.is_active():
		arena.dialogue.close_now()
	arena._phase = Arena.Phase.PLAYING
	arena.player.set_lock(false)
	arena._shock_cd = 0.0
	arena._input(click)
	_check(arena.hud._popup == null and arena._shock_cd == 0.0, "a click on the card closes it and is not Mayari's attack")
	arena._input(click)
	_check(arena._shock_cd > 0.0, "...while the same click with no card there is the attack")
	# The shell's bar: hovering it asks the HUD for the card.
	game._on_skill_bar_hover(GodFavor.Slot.E, true)
	arena.hud._tick_skill_cards(0.016)
	_check(arena.hud._info_cards.has(GodFavor.Slot.E), "the mouse over the shell's E bar shows the card")
	game._on_skill_bar_hover(GodFavor.Slot.E, false)
	arena.hud._tick_skill_cards(0.016)

	# --- a cast is seen over the mortal -------------------------------------------------------------
	var cast := arena.rules.use_skill(GodFavor.Slot.E)
	var icon_popup: FavorPopup = null
	for child in arena.favor_popups_root.get_children():
		if child is FavorPopup and (child as FavorPopup).icon.visible:
			icon_popup = child
	_check(cast != null and icon_popup != null and icon_popup.icon.texture == Arena.e_icon(cast.god_id)
		and not icon_popup.number_label.visible and not arena.player.floating_text.visible,
		"an E cast pops the god's E icon over our mortal, not a name")
	await _frames(2)
	var head_y: float = arena.player.get_global_transform_with_canvas().origin.y
	_check(icon_popup != null and icon_popup.get_global_rect().end.y < head_y - 40.0, "...above their head")
	# A rival's ghost, on a client screen: the host's message names the caster.
	var ghost: ArenaMortal = Arena.MORTAL_SCENE.instantiate()
	arena.ghosts_root.add_child(ghost)
	await _frames(1)
	arena._ghosts[2] = ghost
	arena._authority = false
	arena._on_arena_cast_received(2, q_one.id)
	_check(ghost.floating_text.visible and ghost.floating_text.text == q_one.display_name.to_upper(), "a rival's cast is shown over their ghost on our screen (%s)" % ghost.floating_text.text)
	var tint := ghost.floating_text.modulate
	_check(tint.is_equal_approx(UITokens.readable_on_dark(q_one.color, UITokens.NIGHT_900, Arena.CAST_TEXT_CONTRAST)) or tint.a < 1.0, "...in the favor's colour")
	arena._authority = true
	game.queue_free()
	await _frames(2)
	network.trial_order_ids.clear()

	print("skill card checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


# A press of whatever key the player has bound to `action`.
func _key_press(action: StringName) -> InputEventKey:
	var bound := InputMap.action_get_events(action)[0].duplicate() as InputEventKey
	bound.pressed = true
	return bound


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
