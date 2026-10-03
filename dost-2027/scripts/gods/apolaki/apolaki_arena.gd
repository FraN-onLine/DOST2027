class_name ApolakiArena
extends Arena

# APOLAKI - arnis. (scripts/gods/apolaki + scenes/gods/apolaki)
#
# EVERYTHING SHARED LIVES IN THE BASE (scripts/gods/common/arena.gd): the clock,
# the countdown, the mortal, the dialogues, the God's Due menu, the popups and
# the network plumbing. This file is only what makes the game Apolaki's.
#
# A PRIVATE DUEL
#   This is the one arena where the mortals are NOT in the same room. Each player
#   duels their OWN Apolaki on their OWN screen (Apolaki.tscn, driven by
#   apolaki_duelist.gd). His position is never sent anywhere - what travels
#   between mortals is FAVOR, the favors they hold and the effects those favors
#   play out (separate_players).
#
# THE DUEL - three states each, and every outcome falls out of them
#   Apolaki is IDLE (he just chases you), ATTACKING, or DEFENDING. The mortal is
#   IDLE, ATTACKing, or DEFENDING. That is the whole game.
#   ATTACK (LEFT MOUSE) - the mortal plays its "hit-arnis" clip; the strike lands
#   on frames strike_hit_open_frame..strike_hit_close_frame of it, once per swing:
#   hitting him while he is IDLE or ATTACKING pays strike_favor, hitting his
#   DEFEND costs strike_defend_penalty. Nothing else - all three states covered.
#   DEFEND (RIGHT MOUSE) - the mortal plays its "defend-arnis" clip.
#   HIS SWING (ApolakiDuelist.attack_landed) only reaches a mortal standing
#   inside his area, and only while its frames are live. A mortal who is IDLE or
#   ATTACKing then loses hit_penalty (shoved back, with a sun patch blotting
#   their own screen for hit_patch_time seconds); one who is DEFENDING gains
#   block_favor instead.
#   Both buttons run on their own cooldown, drawn as the two bars on the duel HUD.
#
# SUN PATCHES
#   The Apolaki favors blot part of a mortal's own screen. The host owns the
#   authoritative patch list and mirrors it with every arena tick, so each player
#   only ever sees the patches that fell on themselves.
#
# The arena owns no art: ApolakiArena.tscn holds the sky, the board, the border
# and the duelist (the patch quads are the shared layer in Arena.tscn). This
# script only runs the rules.

@export_category("Arnis")
@export var strike_favor := 200          # hitting him while he IDLES or ATTACKS
@export var strike_defend_penalty := 100 # hitting him while he DEFENDS
@export var block_favor := 100           # a DEFENDING mortal beats his swing
@export var hit_penalty := 80            # an idle / attacking mortal takes his swing
@export var strike_cooldown := 1.0       # seconds between two strikes
@export var strike_hit_open_frame := 3   # the mortal's swing lands from this frame
@export var strike_hit_close_frame := 5  # ...through this one (hit-arnis)
@export var strike_reach_bonus := 26.0   # a strike lands this past his reach
@export var defend_cooldown := 1.0      # seconds before another guard
@export var hit_patch_count := 1         # blots his landed swing leaves on screen
@export var hit_patch_time := 3.0        # seconds each blot stays

@onready var duelist: ApolakiDuelist = get_node_or_null("ArenaField/Apolaki")
@onready var state_label: Label = get_node_or_null("DuelHud/State")
@onready var strike_bar: PanelContainer = get_node_or_null("DuelHud/Bars/StrikeBar")
@onready var defend_bar: PanelContainer = get_node_or_null("DuelHud/Bars/DefendBar")

# The mortal's own clips (authored in Mortal.tscn). The swing lands on one of its
# frames and both clips hand the mortal back to its idle once they run out.
const IDLE_ANIM := &"default"
const STRIKE_ANIM := &"hit-arnis"
const DEFEND_ANIM := &"defend-arnis"

var _strike_cd := 0.0
var _defend_cd := 0.0
var _swinging := false      # a strike clip is running
var _swing_resolved := false # this swing has already landed its one hit
var _guarding := false      # a guard clip is running


func _ready() -> void:
	super._ready()
	if duelist != null:
		duelist.attack_landed.connect(_on_duelist_attack_landed)


# --- ARENA HOOKS (see scripts/gods/common/arena.gd) --------------------------

# The mortals play this one alone: no rival is drawn and no position travels.
func separate_players() -> bool:
	return true


func shares_mortal_positions() -> bool:
	return false


# The Guidance reads "another mortal is nearby" - there is no other mortal on
# this field, so the favor simply never lights up here (it says as much itself).
func nearby_movement_favors_enabled() -> bool:
	return false


func collect_units() -> void:
	# One Apolaki per screen - the same authored node on every peer. He is told
	# where the mortal is every frame (arena_rules_tick); nothing about him is
	# ever put on the wire.
	if duelist == null:
		return
	duelist.color = god.color
	duelist.target = player.global_position


func arena_round_reset() -> void:
	_strike_cd = 0.0
	_defend_cd = 0.0
	_swinging = false
	_swing_resolved = false
	_guarding = false
	clear_sun_patches()
	player.play_animation(IDLE_ANIM)
	if duelist != null:
		duelist.restart()


func arena_rules_tick(_delta: float) -> void:
	# The duel is PRIVATE and therefore personal clockwork, not host scoring: it
	# all runs in _process below, on every peer. Kept so the base's hook has an
	# explicit (empty) answer here.
	pass


func _process(delta: float) -> void:
	super._process(delta)
	# Every peer runs its OWN Apolaki, so his states, his walk and both cooldowns
	# all tick here, on every screen - not just the host's. The FAVOR they pay is
	# still the host's to decide (score_favor).
	_strike_cd = maxf(0.0, _strike_cd - delta)
	_defend_cd = maxf(0.0, _defend_cd - delta)
	# The swing and the guard are driven by the mortal's own clips: the frame the
	# sprite is on decides when the strike lands, and a finished clip returns the
	# mortal to its idle. Runs on every screen, like the rest of the duel.
	_tick_actions()
	_refresh_bars()
	if duelist == null:
		return
	duelist.frozen = _phase != Phase.PLAYING
	duelist.target = player.global_position
	_refresh_state_label()


# --- INPUT -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# The duel's two mouse buttons are read in _input() below. The shell draws a
	# full-screen Control over the arena, and a GUI mouse event never reaches
	# _unhandled_input - so this stays only for the base's keyboard shortcuts
	# (E/Q favors, the God's Due menu, ESC, R).
	super._unhandled_input(event)


func _input(event: InputEvent) -> void:
	# ATTACK / DEFEND are mouse buttons, so they have to be caught before the GUI
	# consumes them (Mayari and Tala read their attack the same way). Only during
	# PLAYING: a dialogue, the God's Due menu or the countdown keep the mortal
	# still.
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if _phase != Phase.PLAYING or player.locked or dialogue.is_active() or due_menu.is_open():
		return
	if event.is_action_pressed("attack"):
		_try_strike()
	elif event.is_action_pressed("defend"):
		_try_defend()
	else:
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


# Pressing attack starts the swing. The strike itself does not resolve here: it
# waits for the clip to reach its hit frames (_tick_actions watches the frame),
# so the swing reads as a swing and the hit lands where the art says it should.
func _try_strike() -> void:
	if _strike_cd > 0.0:
		_log("Strike recharging  (%.1fs)" % _strike_cd, god.color)
		return
	if duelist == null:
		return
	_strike_cd = strike_cooldown
	_swinging = true
	_swing_resolved = false
	_guarding = false
	player.play_animation(STRIKE_ANIM)


# The strike's hit window: "the hit opens at frame 3 and closes at frame 5" of
# the hit-arnis clip (strike_hit_open_frame / strike_hit_close_frame).
func _strike_frame_in_window(frame: int) -> bool:
	return frame >= strike_hit_open_frame and frame <= strike_hit_close_frame


# One frame of the two action clips. The swing resolves exactly once, on the
# first frame inside its window; either clip hands the mortal back to its idle
# once it has played out.
func _tick_actions() -> void:
	if _swinging:
		if not _swing_resolved and _strike_frame_in_window(player.animation_frame()):
			_swing_resolved = true
			_resolve_strike()
		if not player.is_animation_playing(STRIKE_ANIM):
			_swinging = false
			player.play_animation(IDLE_ANIM)
	elif _guarding:
		if not player.is_animation_playing(DEFEND_ANIM):
			_guarding = false
			player.play_animation(IDLE_ANIM)


# The mortal's own three states. They are exactly what its clips are running:
# a strike clip means ATTACKING, a guard clip means DEFENDING, nothing running
# means IDLE. His swing reads these two.
func _player_is_attacking() -> bool:
	return _swinging


func _player_is_defending() -> bool:
	return _guarding


# The moment the mortal's swing connects. Two outcomes, and they cover all three
# of his states: a hit pays while he is IDLE or ATTACKING and costs on his
# DEFEND. It only reaches him at all inside his reach plus the bonus.
func _resolve_strike() -> void:
	if duelist == null:
		return
	if not duelist.in_reach_with_bonus(player.global_position, strike_reach_bonus):
		_log("Out of reach - close the distance", Color(0.8, 0.8, 0.85))
		return
	if duelist.is_defending():
		score_favor(-strike_defend_penalty, "%s's guard" % god.display_name)
		_log("You struck his guard: -%d FAVOR" % strike_defend_penalty, Color(1, 0.5, 0.45))
	else:
		score_favor(strike_favor, god.display_name)
		_log("Strike landed: +%d FAVOR" % strike_favor, Color(0.7, 1, 0.8))


# Pressing defend plays the guard clip. That clip RUNNING is the mortal's
# defending state, and it is what turns his swing into FAVOR.
func _try_defend() -> void:
	if _defend_cd > 0.0:
		return
	_defend_cd = defend_cooldown
	_guarding = true
	_swinging = false
	player.play_animation(DEFEND_ANIM)


# HIS SWING CONNECTED inside his area. The duelist already checked the distance
# and the frame window, so this only reads what the mortal was doing when it
# arrived: DEFENDING gains, and being IDLE or mid-swing both pay.
func _on_duelist_attack_landed() -> void:
	if _phase != Phase.PLAYING or player.locked:
		return
	if _player_is_defending():
		score_favor(block_favor, "Blocked %s's swing" % god.display_name)
		_log("Blocked! +%d FAVOR" % block_favor, Color(0.7, 1, 0.8))
		return
	if is_mortal_invulnerable(_my_id):
		return
	score_favor(-hit_penalty, "%s's swing" % god.display_name)
	set_mortal_invuln(_my_id, invuln_time)
	if duelist != null:
		knock_mortal(_my_id, duelist.global_position)
	_drop_hit_patch()
	_log("His swing landed: -%d FAVOR" % hit_penalty, Color(1, 0.5, 0.45))


# --- THE SUN PATCHES HIS SWING LEAVES ------------------------------------------
# His landed swing blots part of THIS screen. The blots themselves are the
# shared ones (Arena.show_sun_patch), so a blot he drops and a blot another
# player's favor drops behave the same way: each claims a rect at random out of
# the free ones and takes itself back down on its own clock. Nothing is
# published - the duel is private, so nobody else's screen changes.

func _drop_hit_patch() -> void:
	for _index in range(hit_patch_count):
		show_sun_patch(hit_patch_time)


func _refresh_state_label() -> void:
	if state_label == null or duelist == null:
		return
	var text := "APOLAKI CHASES YOU"
	if _player_is_attacking():
		text = "YOU STRIKE"
	elif _player_is_defending():
		text = "YOU GUARD"
	elif duelist.is_attacking():
		text = "APOLAKI SWINGS - GUARD!"
	elif duelist.is_defending():
		text = "APOLAKI GUARDS - DO NOT STRIKE"
	state_label.text = text


# The two duel bars: the swing and the guard, each refilling over its own
# cooldown so the mortal can see when the next strike or block is ready.
func _refresh_bars() -> void:
	_fill_bar(strike_bar, "LEFT MOUSE  STRIKE", _strike_cd, strike_cooldown, Color(1.0, 0.85, 0.35))
	_fill_bar(defend_bar, "RIGHT MOUSE  DEFEND", _defend_cd, defend_cooldown, Color(0.55, 0.8, 1.0))


func _fill_bar(bar: PanelContainer, caption: String, cooldown: float, total: float, tint: Color) -> void:
	if bar == null:
		return
	var fill: ColorRect = bar.get_node_or_null("Body/Fill")
	var label: Label = bar.get_node_or_null("Body/Text")
	var ratio := 1.0 if total <= 0.0 else clampf(1.0 - cooldown / total, 0.0, 1.0)
	if fill != null:
		fill.anchor_right = ratio
		fill.color = Color(tint.r, tint.g, tint.b, 0.78)
	if label != null:
		if cooldown <= 0.0:
			label.text = "%s  READY" % caption
			label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		else:
			label.text = "%s  %.1fs" % [caption, cooldown]
			label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
