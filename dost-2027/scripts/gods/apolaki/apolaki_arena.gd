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
#   apolaki_duelist.gd): he walks, guards and lunges at that player alone. His
#   position is never sent anywhere - what travels between mortals is FAVOR, the
#   favors they hold and the effects those favors play out (separate_players).
#
# THE DUEL
#   ATTACK (LEFT MOUSE) - strike. Land it while Apolaki is OPEN (his blind spot)
#   for the most FAVOR; a strike while he only watches pays a little; strike into
#   his GUARD and you pay for it.
#   DEFEND (RIGHT MOUSE) - guard. Block his lunge inside the window and you gain
#   FAVOR; take the hit and you lose FAVOR and are shoved back.
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
@export var strike_open_favor := 35       # a clean strike on his blind spot
@export var strike_neutral_favor := 10    # a strike while he only watches
@export var strike_guard_penalty := 25    # striking into his guard
@export var block_favor := 20             # a blocked lunge
@export var hit_penalty := 30             # a lunge that got through
@export var strike_cooldown := 0.45       # seconds between two strikes
@export var strike_reach_bonus := 26.0    # a strike lands this past his reach
@export var defend_window := 0.42         # how long a guard holds
@export var defend_cooldown := 0.7        # seconds before another guard

@onready var duelist: ApolakiDuelist = get_node_or_null("ArenaField/Apolaki")
@onready var state_label: Label = get_node_or_null("DuelHud/State")

var _strike_cd := 0.0
var _defend_time := 0.0    # seconds of guard left (our own, personal)
var _defend_cd := 0.0


func _ready() -> void:
	super._ready()
	if duelist != null:
		duelist.lunge.connect(_on_duelist_lunge)


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
	_defend_time = 0.0
	_defend_cd = 0.0
	if duelist != null:
		duelist.restart()


func arena_rules_tick(_delta: float) -> void:
	# The duel is PRIVATE and therefore personal clockwork, not host scoring: it
	# all runs in _process below, on every peer. Kept so the base's hook has an
	# explicit (empty) answer here.
	pass


func _process(delta: float) -> void:
	super._process(delta)
	# Every peer runs its OWN Apolaki, so his stalking, the strike cooldown and
	# the guard window all tick here, on every screen - not just the host's. The
	# FAVOR they pay is still the host's to decide (score_favor).
	_strike_cd = maxf(0.0, _strike_cd - delta)
	_defend_cd = maxf(0.0, _defend_cd - delta)
	_defend_time = maxf(0.0, _defend_time - delta)
	if duelist == null:
		return
	duelist.frozen = _phase != Phase.PLAYING
	duelist.target = player.global_position
	_refresh_state_label()


# --- INPUT -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	# The duel's own two buttons are the arena's during PLAYING only - a dialogue,
	# the God's Due menu or the countdown all keep the mortal still.
	if _phase != Phase.PLAYING or player.locked:
		return
	if dialogue.is_active() or due_menu.is_open():
		return
	if event.is_action_pressed("attack"):
		_try_strike()
	elif event.is_action_pressed("defend"):
		_try_defend()


func _try_strike() -> void:
	if _strike_cd > 0.0:
		_log("Strike recharging  (%.1fs)" % _strike_cd, god.color)
		return
	if duelist == null:
		return
	_strike_cd = strike_cooldown
	if not duelist.in_reach_with_bonus(player.global_position, strike_reach_bonus):
		_log("Out of reach - close the distance", Color(0.8, 0.8, 0.85))
		return
	if duelist.is_open():
		score_favor(strike_open_favor, "%s - blind spot" % god.display_name)
		duelist.flinch()
		_log("Clean strike! +%d FAVOR" % strike_open_favor, Color(0.7, 1, 0.8))
	elif duelist.is_guarding():
		score_favor(-strike_guard_penalty, "%s's guard" % god.display_name)
		_log("You struck his guard: -%d FAVOR" % strike_guard_penalty, Color(1, 0.5, 0.45))
	else:
		score_favor(strike_neutral_favor, god.display_name)
		duelist.flinch()
		_log("Strike landed: +%d FAVOR" % strike_neutral_favor, Color(0.7, 1, 0.8))


func _try_defend() -> void:
	if _defend_cd > 0.0:
		return
	_defend_cd = defend_cooldown
	_defend_time = defend_window


# Apolaki lunged at US. Inside our guard window and inside his reach the lunge is
# blocked; anything else and it lands.
func _on_duelist_lunge() -> void:
	if _phase != Phase.PLAYING or player.locked or duelist == null:
		return
	if _defend_time > 0.0 and duelist.in_reach(player.global_position):
		score_favor(block_favor, "Blocked %s's lunge" % god.display_name)
		_log("Blocked! +%d FAVOR" % block_favor, Color(0.7, 1, 0.8))
		return
	if is_mortal_invulnerable(_my_id):
		return
	score_favor(-hit_penalty, "%s's lunge" % god.display_name)
	set_mortal_invuln(_my_id, invuln_time)
	knock_mortal(_my_id, duelist.global_position)
	_log("His lunge landed: -%d FAVOR" % hit_penalty, Color(1, 0.5, 0.45))


func _refresh_state_label() -> void:
	if state_label == null or duelist == null:
		return
	var text := "APOLAKI WATCHES"
	if duelist.is_open():
		text = "APOLAKI IS OPEN - STRIKE!"
	elif duelist.is_guarding():
		text = "APOLAKI GUARDS - DO NOT STRIKE"
	elif _defend_time > 0.0:
		text = "YOU GUARD"
	state_label.text = text
