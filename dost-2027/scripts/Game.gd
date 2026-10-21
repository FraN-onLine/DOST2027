extends Control

# Bathala's game shell. The shell owns shared player panels and chooses the
# current trial; each god arena remains a replaceable child controller.
#
# The shell's own panel is a vertical stack - the mortal's name, FAVOR with DUE
# on the row below it, then the E favor bar and the Q favor bar, one per row -
# and one panel per rival mortal hangs underneath it. Game.tscn authors the
# first rival panel so the layout can be seen without a second player.
#
# Both panels only ever grow downwards inside that strip: the rival column is
# sized so every rival of Network.MAX_PLAYERS (three) fits above the bottom of
# the screen, and a lobby name is clipped to its own panel with an ellipsis
# instead of being allowed to widen it. The rival column starts low enough to
# leave room for our own panel's Pamana badge row.
#
# Arena contract (scripts/gods/common/arena.gd): every arena scene is authored in
# screen space exactly as it is played - the scene fills the screen and keeps
# the left Arena.UI_STRIP_WIDTH pixels clear for the panels below. The shell
# therefore just instantiates the arena: it never resizes, scales or re-centres
# it, so every player sees the same authored layout.
#
# One trial = one arena child of ArenaPanel (a full-screen, input-transparent
# Control), which is why the arena's own coordinates are already screen
# coordinates - unless the lobby's CAMERA is FOLLOW PLAYER: then the shell sets
# the arena's follow_camera and a Camera2D on the local mortal moves the world
# under the screen. That is why every panel of the shell lives on HudLayer (a
# CanvasLayer just above the world, below every arena layer) and the backdrop on
# BackLayer (below the world): nothing a camera does can move them.
#
# BETWEEN TWO TRIALS: once a trial has closed (its god's end lines and hand-over
# are spoken) and before the next arena starts, the shell opens the PREPARATION
# AREA (scenes/prep/PrepArea.tscn - an Arena too, so it sits in ArenaPanel the
# same way): late God's Due for the god who just hosted, and the Tindahan's
# Pamana. There is one before Bathala's finale, none after it. When it closes,
# the shell snapshots its match and starts the next trial as before. The run's
# one RandomNumberGenerator for the shop's offers (pamana_rng) lives here.
#
# Every panel (ours and each rival's) wears a small swatch of its player's bandana
# colour beside the name - the colour the host gave them in the lobby, the one on
# their mortal's headband in the arena - and so does each row of the final judgment.
#
# The two favor bars of our own panel show the skill's card (the HUD's SkillCard) while
# the mouse is over them, and the card of a skill just gained pops up beside them - both
# are drawn by the arena's HUD, which this shell only tells where the mouse is.
#
# Each panel also carries a small Pamana badge (icon + name, the effect as its
# tooltip) for the heirloom that mortal carries, from its purchase until it
# expires: seconds left for a FIRST 30s item, the Agimat's charges.
#
# Presentation (UI/theme): every panel is a translucent PanelHud framed in its
# player's god accent; FAVOR is the biggest number on the card and counts up to
# a new value instead of jumping; God's Due is a row of diamond pips; the E and
# Q bars carry their keys as keycaps (rebinding shows here too); the clock is a
# pill at the top that turns EMBER for the last ten seconds - a colour change
# only, never a flash.

const OPPONENT_PANEL_SCENE := preload("res://UI/opponentpanels.tscn")
const PREP_SCENE := preload("res://scenes/prep/PrepArea.tscn")
const OPENING_SCENE := preload("res://scenes/OpeningCutscene.tscn")
const LOW_TIME := 10.0          # seconds left when the clock turns EMBER
const COUNT_RATE := 12.0        # FAVOR count-up speed (fraction of the gap per second)
const MAX_PIPS := 5             # more God's Due than this shows as pips + "+N"

@onready var own_panel: PanelContainer = $HudLayer/TopLeft
@onready var own_name_label: Label = $HudLayer/TopLeft/VBoxContainer/Header/NameLabel
@onready var own_icon_frame: PanelContainer = $HudLayer/TopLeft/VBoxContainer/Header/IconFrame
@onready var own_god_icon: TextureRect = $HudLayer/TopLeft/VBoxContainer/Header/IconFrame/GodIcon
@onready var favor_label: Label = $HudLayer/TopLeft/VBoxContainer/StatsRow/FavorBox/FavorValue
@onready var due_label: Label = $HudLayer/TopLeft/VBoxContainer/StatsRow/DueBox/DueRow/DueValue
@onready var due_pips: HBoxContainer = $HudLayer/TopLeft/VBoxContainer/StatsRow/DueBox/DueRow/DuePips
@onready var e_bar: ProgressBar = $HudLayer/TopLeft/VBoxContainer/ERow/EBar
@onready var q_bar: ProgressBar = $HudLayer/TopLeft/VBoxContainer/QRow/QBar
@onready var pamana_row: HBoxContainer = $HudLayer/TopLeft/VBoxContainer/PamanaRow
@onready var pamana_icon: TextureRect = $HudLayer/TopLeft/VBoxContainer/PamanaRow/PamanaIcon
@onready var pamana_label: Label = $HudLayer/TopLeft/VBoxContainer/PamanaRow/PamanaLabel
@onready var other_players_vbox: VBoxContainer = $HudLayer/OtherPlayersPanel/Margin/VBox
@onready var opponent_placeholder: Control = $HudLayer/OtherPlayersPanel/Margin/VBox/OpponentPlaceholder
@onready var timer_label: Label = $HudLayer/TrialTimer
@onready var finale_panel: PanelContainer = $HudLayer/FinalePanel
@onready var finale_summary: VBoxContainer = $HudLayer/FinalePanel/Margin/VBox/Summary

var arena: Node = null
var rules: GodMatch = null
var trial_order: Array[God] = []
var trial_index := 0
var run_snapshot := {}
var other_player_panels := {}
var _own_bandana: BandanaSwatch = null  # the swatch beside our own name
var _visited_gods: Dictionary = {}   # god id -> true (its intro is spoken once)
var _favor_target := 0               # the FAVOR the card is counting toward
var _favor_shown := 0.0              # the FAVOR the card shows this frame
var _pips_shown := -1                # God's Due drawn as pips (-1: not drawn yet)
# The Tindahan's offers are rolled from this, once per run (Game is the run).
var pamana_rng := RandomNumberGenerator.new()


func _ready() -> void:
	pamana_rng.randomize()
	_build_hud()
	# A name is live data: the lobby's UPDATE NAME can land at any time, and so can
	# a join or a leave, so the panels follow the roster instead of being written
	# once at start-up.
	for bar_slot in [[e_bar, GodFavor.Slot.E], [q_bar, GodFavor.Slot.Q]]:
		bar_slot[0].mouse_entered.connect(_on_skill_bar_hover.bind(bar_slot[1], true))
		bar_slot[0].mouse_exited.connect(_on_skill_bar_hover.bind(bar_slot[1], false))
	Network.player_list_updated.connect(_on_player_list_updated)
	Network.player_name_changed.connect(_on_player_name_changed)
	Network.player_god_icon_changed.connect(_on_player_god_icon_changed)
	if _build_trial_order():
		_begin_run()
	else:
		# A client never draws its own run: until the host answers, there is no
		# trial to open. Every player walks the same sequence of gods.
		timer_label.text = "WAITING FOR HOST"
		Network.trial_order_changed.connect(_on_host_trial_order_received, CONNECT_ONE_SHOT)
		Network.rpc_id(1, "request_trial_order")


func _on_host_trial_order_received(_ids: Array) -> void:
	if _build_trial_order():
		_begin_run()
		return
	# Something else about the order changed (the run itself has not arrived
	# yet): keep waiting - never improvise a run a client would not share.
	Network.trial_order_changed.connect(_on_host_trial_order_received, CONNECT_ONE_SHOT)
	Network.rpc_id(1, "request_trial_order")


# The run opens with the story cutscene (once, when the lobby's START brought us
# here and OPENING is not SKIP), then the first god's trial.
func _begin_run() -> void:
	var play: bool = Network.opening_pending and Network.run_settings.opening_cutscene == RunSettings.OPENING_FULL
	Network.opening_pending = false
	if play:
		var cutscene: Node = OPENING_SCENE.instantiate()
		# The host decides in multiplayer: only it may skip, and its skip skips for all.
		cutscene.can_skip = not Network.has_multiplayer_peer() or multiplayer.is_server()
		add_child(cutscene)
		cutscene.play()
		await cutscene.finished
		cutscene.queue_free()
	_start_current_trial()


func _build_hud() -> void:
	var my_id := multiplayer.get_unique_id()
	own_name_label.text = str(Network.players.get(my_id, Network.my_name if Network.my_name != "" else "Mortal"))
	_set_own_god_icon(Network.player_icons.get(my_id, Network.my_god_icon_id))
	if _own_bandana == null:
		_own_bandana = BandanaSwatch.mark(0)
		var header := own_name_label.get_parent()
		header.add_child(_own_bandana)
		header.move_child(_own_bandana, own_name_label.get_index())
	_own_bandana.setup(Network.bandana_of(my_id))
	$HudLayer/TopLeft/VBoxContainer/StatsRow/FavorBox/FavorCaption.text = "FAVOR"
	$HudLayer/TopLeft/VBoxContainer/StatsRow/DueBox/DueCaption.text = "GOD'S DUE"
	# Recognition over recall: the keys as the player bound them.
	$HudLayer/TopLeft/VBoxContainer/ERow/EKey.text = UITokens.key_text(&"skill_e")
	$HudLayer/TopLeft/VBoxContainer/QRow/QKey.text = UITokens.key_text(&"skill_q")
	_show_due_pips(0)
	_build_other_player_panels()


func _build_other_player_panels() -> void:
	for panel in other_player_panels.values():
		if is_instance_valid(panel):
			panel.queue_free()
	other_player_panels.clear()
	var my_id := multiplayer.get_unique_id()
	for peer_id in Network.players.keys():
		var id := int(peer_id)
		if id == my_id:
			continue
		var panel := OPPONENT_PANEL_SCENE.instantiate()
		other_players_vbox.add_child(panel)
		panel.setup(id, str(Network.players[peer_id]), 0, 0)
		panel.set_god_icon(StringName(str(Network.player_icons.get(peer_id, &"mayari"))))
		panel.set_bandana(Network.bandana_of(id))
		other_player_panels[id] = panel
	# OpponentPlaceholder is the panel authored in Game.tscn: it previews the
	# layout while you are alone and steps aside for the first real rival.
	opponent_placeholder.visible = other_player_panels.is_empty()
	_refresh_opponent_display()


func _refresh_opponent_display() -> void:
	# The column stays on screen in every trial. A game the gods have everyone
	# play on their own field (Arnis) puts no rival ON the board - Apolaki is
	# local to each player - but the roster is still who else is in the run, so
	# it is always shown.
	$HudLayer/OtherPlayersPanel.visible = true


func _on_player_list_updated(_players: Dictionary) -> void:
	# The roster changed (a rival joined or left): rebuild the column, which also
	# repaints every name in it.
	_build_hud()


func _on_player_name_changed(peer_id: int, name: String) -> void:
	var clean := name.strip_edges()
	if clean.is_empty():
		return
	if peer_id == multiplayer.get_unique_id():
		own_name_label.text = clean
		return
	var panel = other_player_panels.get(peer_id)
	if panel != null and is_instance_valid(panel):
		panel.set_name_text(clean)


func _on_player_god_icon_changed(peer_id: int, god_id: StringName) -> void:
	if peer_id == multiplayer.get_unique_id():
		_set_own_god_icon(god_id)
		return
	var panel = other_player_panels.get(peer_id)
	if panel != null and is_instance_valid(panel):
		panel.set_god_icon(god_id)


func _set_own_god_icon(god_id: StringName) -> void:
	var god := Gods.by_id(god_id)
	if god != null:
		own_god_icon.texture = god.icon
		# The card is framed in the accent of the god the player wears.
		var accent := UITokens.god_accent(god)
		own_panel.add_theme_stylebox_override("panel", UITokens.accent_box(own_panel.get_theme_stylebox("panel", &"PanelHud"), accent))
		own_icon_frame.add_theme_stylebox_override("panel", UITokens.accent_box(own_icon_frame.get_theme_stylebox("panel", &"PanelInset"), accent))


# The run's order comes from exactly one place: the host (Network.start_game
# hands it to every peer before the shell loads). Returns false when a networked
# client is still waiting for it - such a client must never draw one of its own,
# or the players would end up in different gods.
func _build_trial_order() -> bool:
	trial_order.clear()
	if not Network.trial_order_ids.is_empty():
		for god_id in Network.trial_order_ids:
			var god := Gods.by_id(god_id)
			if god != null and god.id == god_id:
				trial_order.append(god)
		if not trial_order.is_empty():
			return true
		# The ids are known but none of them playable: close the run instead of
		# falling back to a private random draw that no other player would share.
		trial_order.append(Gods.bathala())
		return true
	# A client asks the host for the order; the host (or an offline run, where
	# there is no host to ask) draws its own - with the same draw the lobby uses
	# (RunSettings), so the two can never drift apart.
	if Network.has_multiplayer_peer() and not multiplayer.is_server():
		return false
	for god_id in RunSettings.defaults().planned_order():
		trial_order.append(Gods.by_id(god_id))
	return true


func _start_current_trial() -> void:
	var god := trial_order[trial_index]

	# Every god of the trial order ships its own arena scene (res://scenes/gods/
	# <god>/); one that does not (or is not implemented) closes the run instead.
	if not god.implemented or god.arena_scene == "":
		_show_finale()
		return
	var packed: PackedScene = load(god.arena_scene)
	if packed == null:
		push_warning("Cannot load the %s arena (%s)" % [god.display_name, god.arena_scene])
		return
	var arena_instance: Node2D = packed.instantiate()
	arena_instance.god_id = god.id
	# The shell draws the shared panels; the arena keeps its left strip empty for
	# them and owns the rest of the screen exactly as it was authored.
	arena_instance.embedded = true
	# The lobby's run settings, synced to every peer with the order: the round
	# length and the God's Due step are set before the arena enters the tree (its
	# _ready builds the GodMatch from them). Bathala's finale has no arena, so it
	# is never touched.
	var settings: RunSettings = Network.run_settings
	# An arena with a round length of its own (Langit Lupa: 60s) keeps it.
	var fixed = arena_instance.get("fixed_trial_time")
	arena_instance.trial_time = float(fixed) if fixed != null and float(fixed) > 0.0 else settings.trial_time
	arena_instance.due_step = settings.due_step
	# A god's blitz (last-stand) mode follows the lobby's god_blitz_mode (default on).
	# Only arenas that declare `god_blitz_mode` (Mayari, and later others) honor it.
	if arena_instance.get("god_blitz_mode") != null:
		arena_instance.god_blitz_mode = settings.god_blitz_mode
	# A god speaks its full intro only the first time it hosts in this run (FULL),
	# or never (SHORT); either way the dialogue handshake still runs.
	arena_instance.first_visit = settings.intro_mode == RunSettings.INTRO_FULL and not _visited_gods.has(god.id)
	# Only this screen's view (RunSettings.camera_mode): no rule reads it.
	arena_instance.follow_camera = settings.camera_mode == RunSettings.CAMERA_FOLLOW
	_visited_gods[god.id] = true
	arena_instance.dialogue_prefix = "trial_%d" % (trial_index + 1)
	arena_instance.next_god_id = trial_order[trial_index + 1].id if trial_index + 1 < trial_order.size() else &""
	arena_instance.final_trial = false
	$ArenaPanel.add_child(arena_instance)
	arena = arena_instance
	arena.tree_exited.connect(_on_arena_exited.bind(arena_instance))
	arena.trial_complete.connect(_on_trial_complete)
	call_deferred("_on_arena_ready")


func _on_arena_ready() -> void:
	if arena == null or not is_instance_valid(arena):
		return
	_refresh_opponent_display()
	rules = arena.rules
	if rules == null:
		return
	rules.favor_changed.connect(_on_favor_changed)
	rules.due_changed.connect(_on_due_changed)
	if arena.has_signal("trial_time_changed"):
		arena.trial_time_changed.connect(_on_trial_time_changed)
	# The clock starts at the arena's own round length (Arena.trial_time) and
	# the shell - not the arena - is what knows which trial this is and how many
	# the run holds.
	var round_length = arena.get("trial_time")
	if round_length != null:
		_on_trial_time_changed(float(round_length))
	var arena_hud = arena.get("hud")
	if arena_hud != null and not (arena is PrepArea):  # the rest is not a trial
		arena_hud.set_trial(trial_index + 1, trial_order.size())
	# The shell's two favor bars are the ones on screen in an embedded run, so
	# they answer a click the way E and Q do - the arena claims the tap before
	# its world-attack handlers can see the mouse.
	arena.register_tap_panel(GodFavor.Slot.E, e_bar)
	arena.register_tap_panel(GodFavor.Slot.Q, q_bar)
	if not run_snapshot.is_empty():
		rules.apply_snapshot(run_snapshot)
	# From here on a skill that appears is a gain worth a popup; what the mortal carried
	# in (just loaded) is not.
	rules.announce_gains = true
	_refresh_local_stats()
	if arena is PrepArea:
		# Only now do the mortals hold their favors - the offers are filtered by them.
		arena.open_prep()


# The mouse is over (or left) one of our favor bars: the arena's HUD shows that skill's card.
func _on_skill_bar_hover(slot: int, on: bool) -> void:
	var arena_hud = arena.get("hud") if arena != null and is_instance_valid(arena) else null
	if arena_hud != null:
		arena_hud.set_hover_slot(slot if on else -1)


func _on_trial_time_changed(seconds: float) -> void:
	var clamped := maxf(0.0, seconds)
	timer_label.text = "%d:%02d" % [int(clamped / 60.0), int(clamped) % 60]
	if arena is PrepArea:
		timer_label.text = "PAHINGA " + timer_label.text  # the rest between two trials
	if clamped <= LOW_TIME:
		timer_label.add_theme_color_override("font_color", UITokens.readable_on_dark(UITokens.EMBER, UITokens.NIGHT_900))
	else:
		timer_label.remove_theme_color_override("font_color")


func _process(delta: float) -> void:
	_refresh_local_stats()
	if rules != null:
		_update_panel_stats()
		_show_pamana_badge(rules.local())
	_count_favor(delta)


# FAVOR ticks toward its new value over a few frames instead of jumping, so a
# gain or a loss reads as movement. It always lands exactly on the real value.
func _count_favor(delta: float) -> void:
	var gap := _favor_target - _favor_shown
	if absf(gap) < 0.5:
		_favor_shown = _favor_target
	else:
		_favor_shown += gap * minf(1.0, delta * COUNT_RATE)
	favor_label.text = str(roundi(_favor_shown))


# God's Due as diamond pips (the radio icons of the theme, so the art swap
# covers them), with "+N" once there are more than MAX_PIPS. Zero shows one
# empty pip, so the row never vanishes.
func _show_due_pips(due: int) -> void:
	if due == _pips_shown:
		return
	_pips_shown = due
	for child in due_pips.get_children():
		due_pips.remove_child(child)
		child.queue_free()
	var full := due_pips.get_theme_icon(&"radio_checked", &"CheckBox")
	var empty := due_pips.get_theme_icon(&"radio_unchecked", &"CheckBox")
	for index in range(maxi(1, mini(due, MAX_PIPS))):
		var pip := TextureRect.new()
		pip.texture = full if due > 0 else empty
		pip.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		due_pips.add_child(pip)
	due_label.visible = due > MAX_PIPS
	due_pips.tooltip_text = "%d God's Due" % due


func _refresh_local_stats() -> void:
	if rules == null:
		return
	var mortal := rules.local()
	if mortal == null:
		return
	_favor_target = mortal.favor
	due_label.text = "+%d" % (mortal.due - MAX_PIPS) if mortal.due > MAX_PIPS else str(mortal.due)
	_show_due_pips(mortal.due)


func _update_panel_stats() -> void:
	var mortal := rules.local()
	if mortal == null:
		return
	_update_skill_bar(e_bar, GodFavor.Slot.E, mortal)
	_update_skill_bar(q_bar, GodFavor.Slot.Q, mortal)
	for id in other_player_panels.keys():
		var other := rules.mortal(int(id))
		if other == null:
			continue
		other_player_panels[id].update_stats(other.favor, other.due)
		other_player_panels[id].update_skill_bar(rules, other)
		other_player_panels[id].update_pamana(other)


func _update_skill_bar(bar: ProgressBar, slot: int, mortal: GodMatch.Mortal) -> void:
	var favor := mortal.favor_in_slot(slot)
	if favor == null:
		bar.value = 0.0
		return
	var ratio := rules.skill_cooldown_ratio(slot, mortal.id)
	bar.value = ratio * 100.0
	bar.modulate = favor.color


# The Pamana a mortal carries, as a small badge: the first item's icon, every
# item's name (with its seconds or charges) and the effect as the tooltip.
func _show_pamana_badge(mortal: GodMatch.Mortal) -> void:
	var badges := GodMatch.pamana_badges(mortal)
	pamana_row.visible = not badges.is_empty()
	if badges.is_empty():
		return
	var first: Pamana = badges[0]["pamana"]
	pamana_icon.texture = first.icon
	pamana_icon.modulate = UICards.pamana_edge(first)
	var texts: Array[String] = []
	var tips: Array[String] = []
	for badge in badges:
		texts.append(str(badge["text"]))
		tips.append("%s: %s" % [(badge["pamana"] as Pamana).display_name, (badge["pamana"] as Pamana).effect])
	pamana_label.text = "  ".join(texts)
	pamana_row.tooltip_text = "\n".join(tips)


func _on_favor_changed(_player_id: int, _favor: int, _delta: int, _reason: String) -> void:
	_refresh_local_stats()


func _on_due_changed(_player_id: int, _due: int) -> void:
	_refresh_local_stats()


func _on_trial_complete() -> void:
	if rules != null:
		# Everything the mortal carries - FAVOR, God's Due and the favors - rides into the next trial.
		run_snapshot = rules.snapshot()
	trial_index += 1
	if trial_index >= trial_order.size():
		# The run is over (Bathala's final trial has just closed): clear the field
		# and hand it to the scoreboard, which fades in out of black (Bathala's
		# closing ends on [FADE TO SCOREBOARD.]).
		if arena != null and is_instance_valid(arena):
			arena.queue_free()
		arena = null
		rules = null
		_show_finale()
		_fade_in_from_black()
		return
	var next_god: God = trial_order[trial_index]
	if arena != null and is_instance_valid(arena):
		arena.queue_free()
	arena = null
	rules = null
	if next_god.arena_scene == "" or not next_god.implemented:
		_show_finale()
	else:
		# A rest between the two trials - there is always a next one here, so
		# there is one right before Bathala's finale and never one after it.
		_start_prep()


# The preparation area: hosted by the god whose trial just closed (its altar and
# its God's Due menu), naming the god of the trial to come.
func _start_prep() -> void:
	var host_god: God = trial_order[trial_index - 1]
	var prep: PrepArea = PREP_SCENE.instantiate()
	prep.god_id = host_god.id
	prep.next_god_id = trial_order[trial_index].id
	prep.embedded = true
	prep.due_step = Network.run_settings.due_step
	# The lobby's PREP TIME (RunSettings.prep_time); the scene's own export is
	# only the fallback for a standalone rest.
	prep.prep_time = Network.run_settings.prep_time
	prep.follow_camera = Network.run_settings.camera_mode == RunSettings.CAMERA_FOLLOW
	prep.dialogue_prefix = "prep_%d" % trial_index
	prep.rng = pamana_rng
	$ArenaPanel.add_child(prep)
	arena = prep
	prep.tree_exited.connect(_on_arena_exited.bind(prep))
	prep.prep_closed.connect(_on_prep_closed.bind(prep))
	call_deferred("_on_arena_ready")


# The rest is over: what everyone carries (the purchases included) rides into
# the next trial exactly like the end of a trial's.
func _on_prep_closed(prep: PrepArea) -> void:
	if prep != arena:
		return
	if rules != null:
		run_snapshot = rules.snapshot()
	prep.queue_free()
	arena = null
	rules = null
	_start_current_trial()


func _fade_in_from_black() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)
	add_child(layer)
	var tween := create_tween()
	tween.tween_property(black, "color:a", 0.0, 0.9)
	tween.tween_callback(layer.queue_free)


func _show_finale() -> void:
	$HudLayer/OtherPlayersPanel.visible = true
	finale_panel.visible = true
	UITokens.reveal(finale_panel)
	timer_label.text = "FINAL JUDGMENT"
	timer_label.remove_theme_color_override("font_color")
	var ranked: Array[Dictionary] = []
	for player_id in run_snapshot.keys():
		var entry: Dictionary = run_snapshot[player_id].duplicate(true)
		entry["id"] = int(player_id)
		# The Three Sisters pays out as the final trial begins - before the
		# standings are worked out, so it shows in them.
		entry["sisters"] = GodMatch.three_sisters_bonus(entry.get("favors", []))
		entry["favor"] = int(entry.get("favor", 0)) + int(entry["sisters"])
		ranked.append(entry)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("favor", 0)) > int(b.get("favor", 0)))
	for child in finale_summary.get_children():
		finale_summary.remove_child(child)
		child.queue_free()
	for index in range(ranked.size()):
		var entry: Dictionary = ranked[index]
		var sisters := int(entry.get("sisters", 0))
		var note := "   (+%d The Three Sisters)" % sisters if sisters > 0 else ""
		finale_summary.add_child(BandanaSwatch.player_row(Network.bandana_of(int(entry["id"])),
			"%d.  %s     %d FAVOR     %d DUE%s" % [index + 1, str(entry.get("name", "Mortal")), int(entry.get("favor", 0)), int(entry.get("due", 0)), note]))


# The final judgment as text, one line per player (what the rows say).
func finale_text() -> String:
	var lines: Array[String] = []
	for row in finale_summary.get_children():
		lines.append((row.get_node("Text") as Label).text)
	return "\n".join(lines)


func _on_arena_exited(exited_arena: Node) -> void:
	if arena == exited_arena:
		arena = null
		rules = null


func _unhandled_input(event: InputEvent) -> void:
	if not finale_panel.visible or not event.is_action_pressed("ui_cancel"):
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	var destination := "res://scenes/Lobby.tscn" if Network.has_multiplayer_peer() else "res://scenes/MainMenu.tscn"
	get_tree().change_scene_to_file(destination)
