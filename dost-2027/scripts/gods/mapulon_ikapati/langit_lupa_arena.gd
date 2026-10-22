class_name LangitLupaArena
extends Arena

# MAPULON & IKAPATI - Langit Lupa. (scripts/gods/mapulon_ikapati +
# scenes/gods/mapulon_ikapati)
#
# EVERYTHING SHARED LIVES IN THE BASE (scripts/gods/common/arena.gd): the clock,
# the countdown, the mortal, the dialogues, the God's Due menu, the popups and the
# network plumbing. This file is only what makes the game the Harvest Pair's.
#
# A SHARED FIELD (like Mayari's): every mortal runs on the same field and sees the
# others. The host runs the rules from the positions it has; the clients mirror
# them through arena_tick_fields() and only draw.
#
# THE PLAYGROUND GAME
#   The Taya ("it") can only tag on the LUPA - the ground. A LANGIT (a raised
#   spot) is safe for every runner standing on it, as many as fit, for as long as
#   they like. The pressure is the Taya's chant: when it yells ALIS! everyone on a
#   Langit has to jump down and race across the Lupa to ANOTHER one. The fun is
#   the dare of the crossing.
#
# THE TAYA
#   The countdown is the counting rhyme ("LANGIT... LUPA... IMPYERNO!") and at GO
#   the GODS are Taya: one host-run body for Mapulon & Ikapati (GOD_TAYA), so the
#   pair play in their own arena and no mortal starts behind. It plays by the
#   Taya's rules - tags only on the Lupa, never stands on a Langit, chants
#   (god_chant_success, god_chant_beat) - with the solo bots' chase-and-chant AI
#   at god_speed. It is not a GodMatch mortal: no FAVOR, no drain, no time as
#   Taya, no place in the payout. Its tag moves no FAVOR: that mortal is simply
#   the Taya from then on, and the gods leave the field ("Ikaw na!", a fade over
#   god_leave_time) - they never stay as an extra hunter.
#   SAFETY VALVE: after god_taya_max_time seconds without a tag the gods pick the
#   runner with the most FAVOR on the Lupa (the nearest of a tie; anyone, if all
#   are safe) and hunt only them at god_hunt_speed. A round that ends with the
#   gods still Taya pays by the mortals' times as usual (all zero: a tie).
#   god_starts_as_taya = false brings back the old rule: the rhyme lands on the
#   mortal with the most FAVOR (ties: random).
#   Between mortals the Taya passes on a touch (tag_radius) to any runner on the
#   Lupa; the new Taya cannot tag for tagback_immunity seconds (its marker blinks)
#   and the runner who just passed it on cannot be tagged back for tagged_mercy
#   seconds. A tag moves tag_steal FAVOR from the runner to the Taya; every second
#   as Taya costs taya_drain FAVOR. The Taya can never stand on a Langit: walking
#   into one pushes it back to the edge.
#   Network: the gods' position, fade and hunted runner ride the arena tick; the
#   chant rides the same chant fields as a mortal Taya's. Clients only draw them.
#
# THE FIELD
#   Sized for the mortals playing (field_size_2p / _3p / _4p), centred where the
#   Border is drawn: the host picks it when the arena loads and again at the
#   countdown, and sends it with the layout; every screen redraws the Border.
#
# LANGIT
#   langit_count() spots: one more than there are mortals, so every runner can be
#   safe at once. A runner is safe while inside a Langit's rect grown by
#   langit_safe_margin. Every season_interval seconds the season turns: the Langit
#   shake for shift_warning seconds ("THE LANGIT CRUMBLE!"), crumble - whoever
#   stood on them drops onto the Lupa - and reappear somewhere new: clear of the UI
#   strip, never on top of each other, at least taya_clearance from the Taya and
#   langit_spacing from each other (the spacing gives way first on a crowded field).
#
# THE CHANT (RIGHT CLICK, the `defend` action, while chant_cooldown is ready)
#   The Taya is rooted - no moving, no tagging, no dash - and chant_length key
#   prompts appear over its head, one per word of the rhyme ("LANGIT", "LUPA",
#   "IMPYERNO", "SAKSAK PUSO", "ALIS!"), each a direction (W/A/S/D or the arrows).
#   Press them in order, chant_beat seconds each. A wrong key or a missed beat
#   breaks the chant: the Taya stumbles (chant_fail_stun, still rooted) and the
#   cooldown starts anyway. A full chant yells ALIS!: every runner on a Langit
#   gets swap_time seconds to step off (a shrinking ring, "ALIS NA!"), that Langit
#   is closed to them until the season turns (greyed and locked on their screen),
#   and anyone still on it is shoved off (shove_force, away from the Taya). The
#   Taya is paid chant_favor for each runner it forced off. Everyone sees the
#   words light up over the Taya; only the Taya sees the keys.
#   Network: the chant is played on the Taya's own machine, which reports start,
#   each step and the result to the host (Network.request_langit_chant). The host
#   only acts on messages from the current Taya, in order, with the cooldown ready.
#
# FAVOR DURING PLAY
#   Reaching a Langit that is not the one you last left pays crossing_favor, plus
#   streak_step for every crossing in a row without being tagged (up to
#   streak_cap), plus close_call_bonus when the Taya came within close_call_radius
#   on the way. All of it goes through bank_favor / lose_favor on the host, so
#   every gain modifier, Kabiyak and the popups see it.
#
# THE PAYOUT
#   When the clock runs out the pair pays by least time as Taya: payout_best for
#   first place down to payout_worst for last, evenly spread. Times within
#   tie_window seconds share the better payout. It shows in the results' bonus.
#
# FIRST VISIT: a three-line rules card through the countdown, a chant tip the
# first time you are Taya, and a faint arrow to the nearest open Langit for the
# first guide_time seconds.
#
# SOLO: two small bots take the simulated rivals' places - they sit on a Langit,
# run when a chant reaches its fourth word, hop now and then for the crossing
# FAVOR, and chase (or chant) when they are it.
#
# THE GODS' LOOK: the god body is a mortal body with its mortal sprite hidden and
# the pair's own look on it - Ikapati's overseer sprite (IkapatiOverseer-Sheet.png,
# playing as an idle loop) standing god_height tall (about 1.5 mortals) with her
# feet where a mortal's are, flipped to face where they walk, over a ring of the
# pair's accent on the ground and under the usual name tag and Taya marker (both
# lifted above her head). God-Taya.png replaces her when it exists. At GO the
# banner says MAPULON & IKAPATI ARE TAYA! on every screen, the body pops in
# (god_puff_time), and the overseer standing in the scene's ArenaField is hidden
# for as long as the god body is on the field, so there is never a second Ikapati.
#
# The art is drop-in (see Assets/Gods/MapulonIkapati/README.md; the gods' body is
# God-Taya.png): each file is used
# when it exists and the placeholder stays when it does not. Every number is an
# @export - tune it in the inspector. The dash itself lives in the base (Dash).

const ART_DIR := "res://Assets/Gods/MapulonIkapati/"
const SCREEN_SIZE := Vector2(1152.0, 648.0)  # the authored arena (see arena.gd)
const SAFE_COLOR := Color(0.7, 1, 0.8)
const TAYA_COLOR := Color(1, 0.5, 0.45)
# One word per chant prompt (the scene's ChantRow holds one slot for each).
const CHANT_WORDS: Array[String] = ["LANGIT", "LUPA", "IMPYERNO", "SAKSAK PUSO", "ALIS!"]
# The countdown's beats, one per second, before the pointer lands on the Taya.
const RHYME: Array[String] = ["LANGIT...", "LUPA...", "IMPYERNO!"]
# A prompt's direction, clockwise from up (the arrow is turned a quarter per step).
const MOVE_ACTIONS: Array[StringName] = [&"move_up", &"move_right", &"move_down", &"move_left"]
# The Taya id while Mapulon & Ikapati are it (-1 is "no Taya"; mortals are >= 1).
const GOD_TAYA := -2
# The gods' look (see THE GODS' LOOK): the overseer sheet's frames, the figure's
# height inside a frame (the sheet cuts her off at the waist, so the frame's bottom
# is her "feet"), and a mortal's height and the line its feet stand on, measured
# from the mortal's position (lam-ang.png at Mortal.tscn's scale; the feet are
# Mortal.tscn's Shadow line).
const GOD_SHEET := "IkapatiOverseer-Sheet.png"
const GOD_FRAME := Vector2i(130, 99)
const GOD_ART_HEIGHT := 88.0
const MORTAL_HEIGHT := 78.0
const MORTAL_FEET := 17.0
const RULES_LUPA_GODS := "LUPA: the Taya can tag you here. Mapulon & Ikapati are Taya first!"

@export_category("Langit Lupa")
@export var fixed_trial_time := 60.0     # the round length here (0 = the lobby's)
@export var tag_radius := 26.0           # how close the Taya must get to tag
@export var tagback_immunity := 1.0      # seconds a new Taya cannot tag
@export var tagged_mercy := 1.0          # seconds the old Taya cannot be tagged back
@export var tag_steal := 60              # FAVOR a tag moves from the runner to the Taya
@export var taya_clearance := 100.0      # no Langit lands this close to the Taya
@export var taya_drain := 10             # FAVOR per second as Taya
@export var payout_best := 600           # least time as Taya
@export var payout_worst := 100          # most time as Taya
@export var tie_window := 0.25           # Taya times this close are a tie
@export var langit_size := Vector2(96.0, 60.0)
@export var langit_safe_margin := 6.0    # standing on the edge still counts
@export var langit_spacing := 120.0      # least distance between two Langit centres
@export var langit_fade_in := 0.3        # seconds a new Langit takes to appear

@export_category("Field")
# The field's size for 2, 3 and 4 mortals, centred where the Border is drawn. A 0
# keeps the drawn Border's width or height (the art decides the strip's height).
@export var field_size_2p := Vector2(560.0, 0.0)
@export var field_size_3p := Vector2(640.0, 0.0)
@export var field_size_4p := Vector2(720.0, 0.0)

@export_category("Seasons")
@export var season_interval := 12.0      # seconds between two crumbles
@export var shift_warning := 1.0         # seconds of shaking before a crumble

@export_category("Chant")
@export var chant_cooldown := 5.0
@export var chant_length := 5            # prompts per chant (at most one per word)
@export var chant_beat := 0.8            # seconds for each prompt
@export var chant_fail_stun := 0.6       # a broken chant: the Taya stumbles, still rooted
@export var chant_timeout := 1.0         # host: network slack before a silent chant breaks
@export var broken_show_time := 1.0      # seconds a broken word stays red
@export var swap_time := 1.5             # seconds to step off after ALIS
@export var shove_force := 260.0         # pushing a runner off a closed Langit
@export var shove_stun := 0.25           # each shove; repeated until they are off
@export var chant_favor := 25            # paid to the Taya per runner forced off

@export_category("Crossing FAVOR")
@export var crossing_favor := 40
@export var close_call_bonus := 40
@export var close_call_radius := 90.0
@export var streak_step := 10
@export var streak_cap := 50

@export_category("First Visit")
@export var guide_time := 10.0           # seconds the arrow to the nearest Langit shows
@export var taya_tip_time := 4.0

@export_category("Solo Bots")
@export var bot_speed := 175.0           # solo bots (the player walks 215)
@export var bot_reaction_max := 0.4      # a bot reacts to a chant 0.1 - this many seconds late
@export var bot_dare_chance := 0.08      # per second on a Langit: hop to another for FAVOR
@export var bot_dash_radius := 75.0      # a bot dashes when the Taya is this close
@export var bot_flee_radius := 140.0     # a bot veers away from a Taya this close
@export var bot_chant_success := 0.7
@export var bot_chant_beat := 0.5        # seconds per prompt when a bot chants

@export_category("God Taya")
@export var god_starts_as_taya := true   # false: the mortal with the most FAVOR starts as Taya
@export var god_speed := 175.0           # the gods' walk (the player walks 215)
@export var god_chant_success := 0.7
@export var god_chant_beat := 0.5        # seconds per prompt when the gods chant
@export var god_taya_max_time := 15.0    # seconds without a tag before the gods hunt one runner
@export var god_hunt_speed := 230.0      # their walk while hunting
@export var god_leave_time := 0.8        # seconds the gods take to fade out after their tag
@export var god_tag_line := "MAPULON: \"IKAW NA!\""
@export var god_height := 87.0           # px the god body stands (a mortal is 78)
@export var god_puff_time := 0.35        # seconds the god body takes to pop in at GO

@onready var langits_root: Node2D = get_node_or_null("ArenaField/Langits")
@onready var taya_marker: Node2D = get_node_or_null("TayaMarker")
@onready var taya_sprite: Sprite2D = get_node_or_null("TayaMarker/Sprite")
@onready var taya_ring: Node2D = get_node_or_null("TayaMarker/Ring")
@onready var chant_row: Node2D = get_node_or_null("TayaMarker/ChantRow")
@onready var swap_ring: Node2D = get_node_or_null("SwapRing")
@onready var guide: Line2D = get_node_or_null("Guide")
@onready var overseer: Sprite2D = get_node_or_null("ArenaField/Overseer")
@onready var god_overseer: AnimatedSprite2D = get_node_or_null("ArenaField/GodOverSeer")
@onready var background: Sprite2D = get_node_or_null("Background")
@onready var bots_root: Node2D = get_node_or_null("Bots")
@onready var taya_list: Label = get_node_or_null("LangitHud/TayaList")
@onready var status_label: Label = get_node_or_null("LangitHud/Status")
@onready var callout_label: Label = get_node_or_null("LangitHud/Callout")
@onready var hint_label: Label = get_node_or_null("LangitHud/Hint")
@onready var rules_card: Control = get_node_or_null("LangitHud/RulesCard")
@onready var taya_tip: Control = get_node_or_null("LangitHud/TayaTip")

var _drawn := Rect2()                 # the Border as the scene draws it
var _taya := -1
var _tagback := 0.0
var _taya_time: Dictionary = {}      # mortal id -> seconds spent as Taya
var _drain_pending: Dictionary = {}  # mortal id -> FAVOR owed, banked once a second
var _drain_tick := 1.0
var _langits: Array[Vector2] = []    # Langit centres
var _season := 0                     # how many layouts the field has had
var _season_timer := 0.0             # seconds to the next crumble
var _shown_season := -1              # the last layout drawn on this screen
var _fade := 1.0
# The chant as the host keeps it (and every screen draws it):
var _chanting := false
var _chant_step := 0                 # words hit so far
var _chant_broken := -1              # the word a broken chant broke on (-1 = none)
var _broken_time := 0.0
var _chant_cd := 0.0
var _chant_idle := 0.0               # host: seconds since the Taya's last chant message
var _root_left := 0.0                # host: the stumble after a broken chant
# The chant as the Taya's own machine plays it:
var _my_chant: Array[int] = []       # one direction per word (an index into MOVE_ACTIONS)
var _my_step := 0
var _my_chanting := false
var _beat_left := 0.0
var _my_stumble := 0.0
var _rooted := false
# The runners:
var _swap: Dictionary = {}           # id -> seconds left to step off after ALIS
var _closed: Dictionary = {}         # id -> the Langit closed to them until the season turns
var _shoving: Dictionary = {}        # host: id -> seconds to the next shove off a closed Langit
var _on: Dictionary = {}             # host: id -> the Langit they stand on (-1 = the Lupa)
var _last_left: Dictionary = {}      # host: id -> the Langit they last stepped off
var _close_call: Dictionary = {}     # host: id -> the Taya came close on this crossing
var _streak: Dictionary = {}         # id -> crossings in a row without a tag
# Solo bots:
var _bots: Dictionary = {}           # mortal id -> ArenaMortal
var _bot_goal: Dictionary = {}       # id -> the Langit it runs for
var _bot_react: Dictionary = {}      # id -> seconds before it leaves its Langit
var _bot_dash: Dictionary = {}       # id -> dash cooldown left
var _bot_chant: Dictionary = {}      # the bot Taya's chant: {left, fail_at}
var _callout_time := 0.0
var _taya_tip_left := 0.0
var _taya_tip_done := false
var _paid := false
# The gods as Taya (host-run; clients mirror _god_at, _god_leave and _god_hunt):
var _god_body: ArenaMortal
var _god_at := Vector2.INF           # where the gods stand (INF: off the field)
var _god_time := 0.0                 # host: seconds the gods have been Taya
var _god_hunt := -1                  # the runner the safety valve hunts (-1: none)
var _god_leave := 0.0                # seconds left of the fade after their tag
var _god_said := false               # this screen showed their line over the body
var _god_look: Node2D                # the pair's look on the body (the puff scales it)
var _god_art: Node2D                 # ...its picture, flipped to the way they walk
var _god_lift := 0.0                 # px the name tag and the Taya marker sit above a mortal's


func _ready() -> void:
	if fixed_trial_time > 0.0:
		trial_time = fixed_trial_time
	super._ready()
	# The TAYA list lives in the HUD's top-right column, under the effect timers, so the
	# two never cover each other whichever has rows.
	if taya_list != null and hud != null:
		taya_list.reparent(hud.top_right, false)
		taya_list.custom_minimum_size.x = 250.0
		taya_list.size_flags_horizontal = Control.SIZE_SHRINK_END
	_spawn_bots()
	_spawn_god()
	var lupa_rule := get_node_or_null("LangitHud/RulesCard/Lines/Lupa") as Label
	if lupa_rule != null and god_starts_as_taya:
		lupa_rule.text = RULES_LUPA_GODS


# --- THE FIELD ----------------------------------------------------------------

# The base reads the drawn Border; the host then sizes the field for the mortals
# playing and sends it on with the layout, so every screen walks the same field.
func _read_field() -> void:
	super._read_field()
	if _authority:
		_size_field()


func field_size_for(mortals: int) -> Vector2:
	if mortals <= 2:
		return field_size_2p
	return field_size_3p if mortals == 3 else field_size_4p


func _size_field() -> void:
	if not _drawn.has_area():
		_drawn = field_root.authored_rect()  # once: the Border is redrawn below
	var wanted := field_size_for(rules.mortals.size())
	var size := Vector2(wanted.x if wanted.x > 0.0 else _drawn.size.x, wanted.y if wanted.y > 0.0 else _drawn.size.y)
	_field = Rect2(_drawn.get_center() - size * 0.5, size)
	_draw_border()
	player.bounds = _field
	_fit_camera()
	_publish_layout()


# The Border line is redrawn around the field (it may be scaled in the scene, so
# the corners go through its own transform).
func _draw_border() -> void:
	var line := field_root.border
	if line == null:
		return
	var points := PackedVector2Array()
	for corner in [_field.position, Vector2(_field.end.x, _field.position.y), _field.end, Vector2(_field.position.x, _field.end.y), _field.position]:
		points.append(line.to_local(corner))
	line.points = points


# --- ARENA HOOKS (see scripts/gods/common/arena.gd) --------------------------

func collect_units() -> void:
	_apply_art()


# The effect timers (Arena.local_effects) this game adds: the ALIS clock when we are told
# to change places, the closed Langit we cannot stand on until the season turns, and the
# tag-back buffer of a new Taya.
func arena_local_effects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _phase != Phase.PLAYING:
		return out
	var swapping := swap_left(_my_id)
	if swapping > 0.0:
		out.append(effect(&"alis", "ALIS - CHANGE PLACES", null, UITokens.EMBER, swapping, swap_time, true))
	if _closed.has(_my_id) and _season_timer > 0.0:
		out.append(effect(&"closed", "YOUR LANGIT IS CLOSED", null, UITokens.EMBER, _season_timer, season_interval, true))
	if _taya == _my_id and _tagback > 0.0:
		out.append(effect(&"tagback", "CANNOT TAG YET", null, UITokens.EMBER, _tagback, tagback_immunity, true))
	return out


# The follow camera's edge arrow: the Taya (its marker is shown only while there
# is one, and on our own head when it is us - then it is never out of view).
func edge_targets() -> Array:
	return [taya_marker] if taya_marker != null else []


func arena_round_reset() -> void:
	if _authority:
		_size_field()  # the roster may have changed during the intro
	_taya = -1
	_tagback = 0.0
	_taya_time.clear()
	_drain_pending.clear()
	_drain_tick = 1.0
	_paid = false
	_season_timer = season_interval
	_reset_chant()
	_chant_cd = 0.0
	_my_chanting = false
	_my_stumble = 0.0
	_rooted = false  # the base keeps the mortal locked through the countdown
	_god_at = Vector2.INF
	_god_time = 0.0
	_god_hunt = -1
	_god_leave = 0.0
	for runners in [_swap, _closed, _shoving, _on, _last_left, _close_call, _streak, _bot_goal, _bot_react, _bot_chant]:
		runners.clear()
	if _authority:
		_place_langits()
	for id in _bots.keys():
		_bots[id].global_position = _bot_start(int(id))
		_mortal_positions[int(id)] = _bots[id].global_position


func arena_rules_tick(delta: float) -> void:
	_move_bots(delta)
	_move_god(delta)
	_tick_season(delta)
	if _taya == -1 or (_taya != GOD_TAYA and rules.mortal(_taya) == null):
		_choose_taya(_highest_favor_ids())
	_tick_chant(delta)
	_tick_swaps(delta)
	_tick_crossings()
	_tagback = maxf(0.0, _tagback - delta)
	if _taya >= 0:  # the gods keep no time and pay no drain
		_taya_time[_taya] = float(_taya_time.get(_taya, 0.0)) + delta
		_drain_pending[_taya] = float(_drain_pending.get(_taya, 0.0)) + float(taya_drain) * delta
	if _taya != -1:
		_check_tag()
	_drain_tick -= delta
	if _drain_tick <= 0.0:
		_drain_tick += 1.0
		_bank_drain()


func arena_tick_fields() -> Dictionary:
	return {
		"taya": _taya,
		"tagback": _tagback,
		"taya_time": _taya_time.duplicate(),
		"langits": _langits.duplicate(),
		"season": _season,
		"season_left": _season_timer,
		"chanting": _chanting,
		"chant_step": _chant_step,
		"chant_broken": _chant_broken,
		"chant_cd": _chant_cd,
		"swap": _swap.duplicate(),
		"closed": _closed.duplicate(),
		"streak": _streak.duplicate(),
		"god_at": _god_at,
		"god_leave": _god_leave,
		"god_hunt": _god_hunt,
	}


func arena_read_layout(_layout: Dictionary) -> void:
	_draw_border()  # the host's field (the base already took _field and the bounds)


func arena_read_tick(state: Dictionary) -> void:
	var previous := _taya
	_taya = int(state.get("taya", _taya))
	_tagback = float(state.get("tagback", _tagback))
	_taya_time = state.get("taya_time", _taya_time).duplicate()
	_season_timer = float(state.get("season_left", _season_timer))
	var langits: Array = state.get("langits", [])
	_langits.clear()
	for spot in langits:
		_langits.append(spot)
	_season = int(state.get("season", _season))
	_chanting = bool(state.get("chanting", _chanting))
	_chant_step = int(state.get("chant_step", _chant_step))
	_chant_broken = int(state.get("chant_broken", _chant_broken))
	_chant_cd = float(state.get("chant_cd", _chant_cd))
	_swap = state.get("swap", _swap).duplicate()
	_closed = state.get("closed", _closed).duplicate()
	_streak = state.get("streak", _streak).duplicate()
	_god_at = state.get("god_at", _god_at)
	_god_leave = float(state.get("god_leave", _god_leave))
	_god_hunt = int(state.get("god_hunt", _god_hunt))
	if _taya != previous:
		_announce_taya(_taya)


# The countdown is the counting rhyme: the base's "3", "2", "1" become its beats.
func _show_banner(text: String, color: Color, duration := 2.0) -> void:
	if _phase == Phase.COUNTDOWN and text.is_valid_int():
		text = RHYME[clampi(int(round(countdown_time)) - int(text), 0, RHYME.size() - 1)]
	super._show_banner(text, color, duration)


# At GO the rhyme's pointer lands on the gods (or, with god_starts_as_taya off,
# on the mortal with the most FAVOR - read once begin_trial() has paid First
# Light, so it is the real one).
func _start_trial() -> void:
	super._start_trial()
	if not _authority:
		return
	if god_starts_as_taya:
		_gods_take_taya()
	else:
		_choose_taya(_highest_favor_ids())
	if _taya >= 0:  # (the gods' own banner comes with _announce_taya, on every screen)
		_show_banner("TAYA: %s!" % taya_label().to_upper(), god.color, 1.4)


# The payout is banked BEFORE the base settles the trial (rules.end_trial()
# writes the results), so it shows in this trial's standings - and it is added to
# the results' bonus column afterwards, so it can be seen there too.
func _end_trial() -> void:
	var settling := _phase == Phase.PLAYING
	if _authority and not _paid and settling:
		_paid = true
		rules.time_left = INF  # a payout is never Panahon ng Anihan's harvest
		_bank_drain(true)
		pay_out()
	super._end_trial()
	if settling:
		var paid := payouts()
		for id in paid.keys():
			if _results.has(id):
				_results[id]["bonus"] = int(_results[id].get("bonus", 0)) + int(paid[id])


func _on_peer_left(peer_id: int) -> void:
	super._on_peer_left(peer_id)
	if _authority and peer_id == _taya:
		_choose_taya(_highest_favor_ids())  # set_taya cancels the chant it left behind


# Tag is a game of touching: the other mortals are not solid here, or two bodies
# (24px each) would hold the Taya further off than tag_radius and nobody could
# ever be caught.
func _sync_ghosts() -> void:
	super._sync_ghosts()
	for ghost in _ghosts.values():
		_ghostly(ghost)


func _ghostly(mortal: ArenaMortal) -> void:
	if is_instance_valid(mortal):
		mortal.collision_layer = 0
		mortal.collision_mask = 0


func _connect_network() -> void:
	super._connect_network()
	if _networked and _authority and _net.has_signal("langit_chant_requested"):
		_net.connect("langit_chant_requested", _on_chant_message)


# --- THE TAYA ----------------------------------------------------------------

# Every mortal tied for the most FAVOR (Kamalig's store does not count).
func _highest_favor_ids() -> Array[int]:
	var best: Array[int] = []
	var top := -1
	for m in rules.mortals.values():
		if m.favor > top:
			top = m.favor
			best = [m.id]
		elif m.favor == top:
			best.append(m.id)
	return best


func _choose_taya(candidates: Array[int]) -> void:
	if candidates.is_empty():
		_taya = -1
		return
	set_taya(candidates[randi() % candidates.size()])


# Taya passes to `mortal_id`, who cannot tag for tagback_immunity seconds; the
# runner who passed it on cannot be tagged back for tagged_mercy seconds. A chant
# in progress is cancelled (only a disconnect can change the Taya mid-chant).
# When it passes from the gods, they leave the field.
func set_taya(mortal_id: int) -> void:
	var old := _taya
	if old == GOD_TAYA and mortal_id != GOD_TAYA:
		_gods_leave()
	_taya = mortal_id
	_tagback = tagback_immunity
	_reset_chant()
	_bot_chant.clear()
	_swap.erase(mortal_id)
	_shoving.erase(mortal_id)
	_on[mortal_id] = -1
	if old >= 0 and old != mortal_id:
		_on[old] = -1
		_last_left[old] = -1
		set_mortal_invuln(old, tagged_mercy)
	_announce_taya(mortal_id)


func _announce_taya(mortal_id: int) -> void:
	if mortal_id == GOD_TAYA:
		_log("%s are the Taya" % god.display_name, god.color)
		_show_banner("%s ARE TAYA!" % god.display_name.to_upper(), god.color, 1.4)
		return
	if mortal_id < 0:
		return
	if mortal_id == _my_id:
		_set_callout("TAYA!", TAYA_COLOR, 1.2)
		_show_banner("YOU ARE TAYA", god.color, 1.0)
		if first_visit and not _taya_tip_done:
			_taya_tip_done = true
			_taya_tip_left = taya_tip_time
	_log("%s is the Taya" % mortal_label(mortal_id), god.color)


func taya_id() -> int:
	return _taya


# Where the Taya stands - the gods' body or a mortal (Vector2.INF: unknown).
func taya_position() -> Vector2:
	return _god_at if _taya == GOD_TAYA else mortal_position(_taya)


func taya_label() -> String:
	return god.display_name if _taya == GOD_TAYA else mortal_label(_taya)


func _check_tag() -> void:
	if _tagback > 0.0 or _chanting or _root_left > 0.0:
		return
	var from := taya_position()
	if from == Vector2.INF:
		return
	for entry in mortal_entries():
		var id := int(entry["id"])
		if id == _taya or is_safe(id) or is_mortal_invulnerable(id):
			continue
		if _taya == GOD_TAYA and _god_hunt >= 0 and id != _god_hunt:
			continue  # the hunt is for one runner only
		if from.distance_to(entry["pos"]) <= tag_radius:
			_tag(id)
			return


# The Taya's catch: tag_steal FAVOR from the runner (what was really lost) goes
# to the Taya, the runner's streak ends, and they are it.
func _tag(mortal_id: int) -> void:
	var catcher := _taya
	if catcher == GOD_TAYA:
		# Nobody to give tag_steal to: the runner is simply the Taya from now on
		# (and set_taya sends the gods off the field).
		_streak[mortal_id] = 0
		set_taya(mortal_id)
		return
	var lost := lose_favor(tag_steal, "Tagged", mortal_id)
	if lost > 0:
		bank_favor(lost, "Taya's catch", catcher)
	_streak[mortal_id] = 0
	set_taya(mortal_id)


# FAVOR drained while Taya, banked through lose_favor once a second (so Waning
# Moon, The Unmoving, Bagong Umaga and Apolaki's favors all see it). It is a
# DRAIN: The Agimat lets it through instead of spending a charge a second.
func _bank_drain(everything := false) -> void:
	for id in _drain_pending.keys():
		var owed := float(_drain_pending[id])
		var amount := int(owed)
		if amount <= 0 and not everything:
			continue
		_drain_pending[id] = owed - float(amount)
		if amount > 0 and rules.mortal(int(id)) != null:
			lose_favor(amount, "Taya", int(id), true)


func taya_seconds(mortal_id: int) -> float:
	return float(_taya_time.get(mortal_id, 0.0))


# The Taya can never stand on a Langit: anything inside one is put back on the
# nearest edge.
func _push_out(at: Vector2) -> Vector2:
	for index in range(_langits.size()):
		var rect := langit_rect(index)
		if not rect.has_point(at):
			continue
		var gaps := [at.x - rect.position.x, rect.end.x - at.x, at.y - rect.position.y, rect.end.y - at.y]
		match gaps.find(gaps.min()):
			0: at.x = rect.position.x - 0.5
			1: at.x = rect.end.x + 0.5
			2: at.y = rect.position.y - 0.5
			_: at.y = rect.end.y + 0.5
	return at


# --- THE CHANT ---------------------------------------------------------------

func _reset_chant() -> void:
	_chanting = false
	_chant_step = 0
	_chant_broken = -1
	_broken_time = 0.0
	_chant_idle = 0.0
	_root_left = 0.0


# The Taya's own machine: may it start a chant right now?
func can_chant() -> bool:
	return _phase == Phase.PLAYING and _taya == _my_id and not _my_chanting and _my_stumble <= 0.0 \
		and not _chanting and _chant_cd <= 0.0 and not is_crumbling() \
		and not dialogue.is_active() and not due_menu.is_open()


func start_chant() -> bool:
	if not can_chant():
		return false
	_my_chant.clear()
	for index in range(chant_length):
		_my_chant.append(randi() % MOVE_ACTIONS.size())
	_my_step = 0
	_beat_left = chant_beat
	_my_chanting = true
	_set_rooted(true)
	_send_chant("start", 0)
	return true


# One prompt answered: `direction` is an index into MOVE_ACTIONS.
func chant_key(direction: int) -> void:
	if not _my_chanting:
		return
	if direction != _my_chant[_my_step]:
		_break_my_chant()
		return
	_my_step += 1
	_beat_left = chant_beat
	_send_chant("step", _my_step)
	if _my_step >= _my_chant.size():
		_my_chanting = false
		_set_rooted(false)
		_send_chant("result", 1)


func _break_my_chant() -> void:
	_my_chanting = false
	_my_stumble = chant_fail_stun
	_send_chant("result", 0)


func _send_chant(kind: String, value: int) -> void:
	if _authority:
		_on_chant_message(_my_id, kind, value)
	elif _net != null and _net.has_multiplayer_peer():
		_net.rpc_id(1, "request_langit_chant", kind, value)


# Every frame on every machine: the Taya's own chant - its beat clock and its
# root. Nobody else's mortal is ever locked from here.
func _tick_my_chant(delta: float) -> void:
	if _phase != Phase.PLAYING or _taya != _my_id:
		_my_chanting = false
		_my_stumble = 0.0
		if _phase == Phase.PLAYING:
			_set_rooted(false)
		else:
			_rooted = false  # the base owns the lock outside of play
		return
	if _my_chanting:
		_beat_left -= delta
		if _beat_left <= 0.0:
			_break_my_chant()
	else:
		_my_stumble = maxf(0.0, _my_stumble - delta)
	_set_rooted(_my_chanting or _my_stumble > 0.0)


func _set_rooted(value: bool) -> void:
	if value == _rooted:
		return
	_rooted = value
	player.set_lock(value)


# Host: the Taya's chant, word by word. Anything not from the current Taya, out
# of order, or with the cooldown still running is ignored.
func _on_chant_message(sender: int, kind: String, value: int) -> void:
	if not _authority or sender != _taya or _phase != Phase.PLAYING:
		return
	match kind:
		"start":
			if _chanting or _chant_cd > 0.0 or _root_left > 0.0 or is_crumbling():
				return
			_reset_chant()
			_chanting = true
		"step":
			if _chanting and value == _chant_step + 1 and value <= chant_length:
				_chant_step = value
				_chant_idle = 0.0
		"result":
			if not _chanting:
				return
			if value == 1 and _chant_step >= chant_length:
				_chanting = false
				_chant_cd = chant_cooldown
				_yell_alis()
			else:
				_break_chant()  # a broken chant, or a "success" that skipped words


func _break_chant() -> void:
	_chanting = false
	_chant_broken = _chant_step
	_broken_time = broken_show_time
	_root_left = chant_fail_stun
	_chant_cd = chant_cooldown


func _tick_chant(delta: float) -> void:
	_chant_cd = maxf(0.0, _chant_cd - delta)
	_root_left = maxf(0.0, _root_left - delta)
	_broken_time = maxf(0.0, _broken_time - delta)
	if _broken_time <= 0.0:
		_chant_broken = -1
	if _chanting:
		# A Taya that went quiet (a lost peer, a frozen window) breaks its chant.
		_chant_idle += delta
		if _chant_idle > chant_beat + chant_timeout:
			_break_chant()


# ALIS! Everyone on a Langit must change places.
func _yell_alis() -> void:
	var forced := 0
	for entry in mortal_entries():
		var id := int(entry["id"])
		if id == _taya:
			continue
		var index := langit_index_at(id, entry["pos"])
		if index < 0:
			continue
		_swap[id] = swap_time
		_closed[id] = index
		forced += 1
	if forced > 0 and _taya >= 0:  # the gods are not paid
		bank_favor(chant_favor * forced, "Chant", _taya)
	_log("%s yells ALIS! - %d must change places" % [taya_label(), forced], god.color)


func swap_left(mortal_id: int) -> float:
	return float(_swap.get(mortal_id, 0.0))


# The swap clocks run down; whoever is still on their closed Langit afterwards is
# shoved off, again and again, until they are on the Lupa.
func _tick_swaps(delta: float) -> void:
	for id in _swap.keys():
		var left := float(_swap[id]) - delta
		if left > 0.0:
			_swap[id] = left
		else:
			_swap.erase(id)
			_shoving[id] = 0.0
	var from := taya_position()
	for id in _shoving.keys():
		var at := mortal_position(int(id))
		if at == Vector2.INF or not _inside(int(_closed.get(id, -1)), at):
			_shoving.erase(id)
			continue
		var wait := float(_shoving[id]) - delta
		if wait <= 0.0:
			_shove(int(id), from if from != Vector2.INF else _langits[int(_closed[id])])
			wait = shove_stun
		_shoving[id] = wait


func _shove(mortal_id: int, from: Vector2) -> void:
	if _bots.has(mortal_id):
		var bot: ArenaMortal = _bots[mortal_id]
		bot.hit(bot.global_position - from, shove_stun, shove_force)
	else:
		knock_mortal(mortal_id, from, shove_stun, shove_force)


# --- CROSSINGS -----------------------------------------------------------------

# Host, every frame: who stepped off a Langit, who reached one, and whether the
# Taya came close on the way.
func _tick_crossings() -> void:
	var taya_at := taya_position()
	for entry in mortal_entries():
		var id := int(entry["id"])
		if id == _taya:
			continue
		var pos: Vector2 = entry["pos"]
		var at := langit_index_at(id, pos)
		var was := int(_on.get(id, -1))
		var near := taya_at != Vector2.INF and pos.distance_to(taya_at) <= close_call_radius
		if at == was:
			if at < 0 and near:
				_close_call[id] = true
			continue
		_on[id] = at
		if was >= 0:
			_last_left[id] = was
			_close_call[id] = near
		if at >= 0 and at != int(_last_left.get(id, -1)):
			_pay_crossing(id)


func _pay_crossing(mortal_id: int) -> void:
	var streak := int(_streak.get(mortal_id, 0))
	bank_favor(crossing_favor + mini(streak * streak_step, streak_cap), "Crossing", mortal_id)
	if bool(_close_call.get(mortal_id, false)):
		bank_favor(close_call_bonus, "Close call", mortal_id)
	_streak[mortal_id] = streak + 1
	_close_call[mortal_id] = false


func streak_of(mortal_id: int) -> int:
	return int(_streak.get(mortal_id, 0))


# --- THE PAYOUT --------------------------------------------------------------

# What each mortal is paid, by least time as Taya. Returns {id: FAVOR}.
func payouts() -> Dictionary:
	var ids: Array = rules.mortals.keys()
	ids.sort_custom(func(a, b): return taya_seconds(int(a)) < taya_seconds(int(b)))
	var out := {}
	var steps := maxi(1, ids.size() - 1)
	var place := 0
	for index in range(ids.size()):
		if index > 0 and taya_seconds(int(ids[index])) - taya_seconds(int(ids[place])) > tie_window:
			place = index
		var amount := payout_best
		if ids.size() > 1:
			amount = int(round(lerpf(float(payout_best), float(payout_worst), float(place) / float(steps))))
		out[int(ids[index])] = amount
	return out


func pay_out() -> void:
	var paid := payouts()
	for id in paid.keys():
		bank_favor(int(paid[id]), "Langit Lupa payout", int(id))
	_log("The Harvest Pair pays out - least time as Taya earns the most", god.color)


# --- LANGIT ------------------------------------------------------------------

# How many Langit the field holds: one more than there are mortals.
func langit_count(mortals: int) -> int:
	return mortals + 1


func _tick_season(delta: float) -> void:
	_season_timer -= delta
	if _season_timer <= 0.0:
		_season_timer += season_interval
		_turn_season()


# Mapulon turns the season: the Langit crumble (everyone on them drops onto the
# Lupa), every closed Langit opens again, and they reappear somewhere new.
func _turn_season() -> void:
	for runners in [_swap, _closed, _shoving, _on, _last_left, _close_call, _bot_goal]:
		runners.clear()
	_place_langits()


func is_crumbling() -> bool:
	return _phase == Phase.PLAYING and _season_timer <= shift_warning


# New spots for every Langit: inside the field and clear of the UI strip, not on
# top of each other, never within taya_clearance of the Taya and langit_spacing
# apart, so a crossing is a real distance.
func _place_langits() -> void:
	_langits.clear()
	var half := langit_size * 0.5
	var area := Rect2(_field.position + half, _field.size - langit_size)
	var left := maxf(area.position.x, UI_STRIP_WIDTH + half.x)
	area = Rect2(left, area.position.y, area.end.x - left, area.size.y)
	var taya_at := taya_position()
	for index in range(langit_count(rules.mortals.size())):
		_langits.append(_find_spot(area, taya_at))
	_season += 1
	if _authority and _networked:
		_publish_arena_tick()


# 80 tries with every rule; on a crowded field langit_spacing gives way first,
# then the Taya's clearance. The UI strip (the area itself) and the overlap rule
# never do.
func _find_spot(area: Rect2, taya_at: Vector2) -> Vector2:
	var spot := area.get_center()
	for relax in range(3):
		for attempt in range(80):
			spot = Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
			if _langit_spot_ok(spot, taya_at, relax):
				return spot
	return spot


func _langit_spot_ok(spot: Vector2, taya_at: Vector2, relax := 0) -> bool:
	if relax < 2 and taya_at != Vector2.INF and spot.distance_to(taya_at) < taya_clearance:
		return false
	for other in _langits:
		if absf(spot.x - other.x) < langit_size.x + 8.0 and absf(spot.y - other.y) < langit_size.y + 8.0:
			return false
		if relax < 1 and spot.distance_to(other) < langit_spacing:
			return false
	return true


func langit_rect(index: int) -> Rect2:
	return Rect2(_langits[index] - langit_size * 0.5, langit_size)


func _inside(index: int, at: Vector2) -> bool:
	return index >= 0 and index < _langits.size() and langit_rect(index).grow(langit_safe_margin).has_point(at)


# The open Langit `mortal_id` stands on at `at` (-1 = the Lupa). The one closed
# to them after an ALIS does not count.
func langit_index_at(mortal_id: int, at: Vector2) -> int:
	var closed := int(_closed.get(mortal_id, -1))
	for index in range(_langits.size()):
		if index != closed and _inside(index, at):
			return index
	return -1


func is_closed_for(mortal_id: int, index: int) -> bool:
	return int(_closed.get(mortal_id, -1)) == index


# Safe: on an open Langit, or still on the closed one while the swap clock runs.
# The Taya never is.
func is_safe(mortal_id: int) -> bool:
	if mortal_id == _taya:
		return false
	var at := mortal_position(mortal_id)
	if at == Vector2.INF:
		return false
	if langit_index_at(mortal_id, at) >= 0:
		return true
	return swap_left(mortal_id) > 0.0 and _inside(int(_closed.get(mortal_id, -1)), at)


# The nearest Langit open to `mortal_id`, other than `skip` (-1 = none).
func _nearest_langit(mortal_id: int, here: Vector2, skip := -1) -> int:
	var best := -1
	for index in range(_langits.size()):
		if index == skip or is_closed_for(mortal_id, index):
			continue
		if best < 0 or here.distance_to(_langits[index]) < here.distance_to(_langits[best]):
			best = index
	return best


# --- SOLO BOTS ---------------------------------------------------------------

func _spawn_bots() -> void:
	if _networked or not simulate_rivals or bots_root == null:
		return
	# The bots earn FAVOR by playing, not by the base's quiet trickle.
	rules.simulate_rivals = false
	for m in rules.mortals.values():
		if m.is_local:
			continue
		var bot: ArenaMortal = MORTAL_SCENE.instantiate()
		bots_root.add_child(bot)
		bot.set_lock(true)  # moved by this script, never by the keyboard
		_ghostly(bot)
		bot.ring_color = god.color
		bot.set_display_name(m.display_name, god.color)
		bot.set_bandana(bandana_of(m.id))  # the free colours, after the player's
		bot.global_position = _bot_start(m.id)
		_bots[m.id] = bot
		_mortal_positions[m.id] = bot.global_position


# Spread over the field: left and right of the middle, top to bottom by id.
func _bot_start(id: int) -> Vector2:
	var x := _field.size.x * 0.28 * (1.0 if id % 2 == 0 else -1.0)
	var y := lerpf(-0.35, 0.35, float(id % 3) / 2.0) * _field.size.y
	return _field.get_center() + Vector2(x, y)


func _move_bots(delta: float) -> void:
	var low := Vector2(maxf(_field.position.x, UI_STRIP_WIDTH), _field.position.y)
	for id in _bots.keys():
		var bot: ArenaMortal = _bots[id]
		_bot_dash[id] = maxf(0.0, float(_bot_dash.get(id, 0.0)) - delta)
		var here := bot.global_position
		var rooted := int(id) == _taya and (_chanting or _root_left > 0.0)
		var step := Vector2.ZERO if rooted else _bot_heading(int(id), here, delta)
		if step.length() > 0.01:
			here += step.normalized() * bot_speed * delta
		if int(id) == _taya:
			here = _push_out(here)
		here = here.clamp(low + Vector2.ONE * bot.radius, _field.end - Vector2.ONE * bot.radius)
		bot.global_position = here
		_mortal_positions[int(id)] = here
	_tick_bot_chant(delta)


func _bot_heading(id: int, here: Vector2, delta: float) -> Vector2:
	if id == _taya:
		return _bot_taya_heading(id, here)
	var on := langit_index_at(id, here)
	var goal := int(_bot_goal.get(id, -1))
	if goal >= _langits.size() or is_closed_for(id, goal) or goal == on:
		goal = -1
	if goal < 0 and on >= 0:
		# Sitting safe. A chant at its fourth word (or ALIS) gets it moving after a
		# small reaction delay; now and then it dares a crossing by itself.
		if not _bot_react.has(id):
			if swap_left(id) > 0.0 or (_chanting and _chant_step >= 3) or randf() < bot_dare_chance * delta:
				_bot_react[id] = randf_range(0.1, bot_reaction_max)
			return Vector2.ZERO
		_bot_react[id] = float(_bot_react[id]) - delta
		if float(_bot_react[id]) > 0.0:
			return Vector2.ZERO
		_bot_react.erase(id)
		goal = _nearest_langit(id, here, on)
	elif goal < 0:
		goal = _nearest_langit(id, here)
	_bot_goal[id] = goal
	var heading := Vector2.ZERO
	if goal >= 0 and not is_crumbling():
		heading = (_langits[goal] - here).normalized()
	var chaser := taya_position()
	if chaser != Vector2.INF and here.distance_to(chaser) < bot_flee_radius:
		heading += (here - chaser).normalized() * 1.3
		if here.distance_to(chaser) < bot_dash_radius and float(_bot_dash.get(id, 0.0)) <= 0.0 and heading.length() > 0.01:
			_bot_dash[id] = dash_cooldown
			(_bots[id] as ArenaMortal).dash(heading, dash_distance, dash_time)
	return heading


# Taya (a bot, or the gods): chase the nearest runner on the Lupa - only `only`
# when it is set (the gods' hunt). When the prey is safe, walk up to a Langit
# (the hunted runner's) and chant.
func _bot_taya_heading(id: int, here: Vector2, only := -1) -> Vector2:
	var prey := Vector2.INF
	for entry in mortal_entries():
		var other := int(entry["id"])
		if other == id or is_safe(other) or is_mortal_invulnerable(other) or (only >= 0 and other != only):
			continue
		if prey == Vector2.INF or here.distance_to(entry["pos"]) < here.distance_to(prey):
			prey = entry["pos"]
	if prey != Vector2.INF:
		return prey - here
	var near := _nearest_langit(id, here)
	var hunted_at := mortal_position(only) if only >= 0 else Vector2.INF
	if hunted_at != Vector2.INF:
		near = _nearest_langit(only, hunted_at)
	if near < 0:
		return Vector2.ZERO
	var gap := _langits[near] - here
	if gap.length() > langit_size.length() * 0.5 + 40.0:
		return gap
	if _bot_chant.is_empty() and not _chanting and _chant_cd <= 0.0 and _root_left <= 0.0 and not is_crumbling():
		var success := god_chant_success if id == GOD_TAYA else bot_chant_success
		_bot_chant = {"left": _bot_beat(), "fail_at": -1 if randf() < success else randi() % chant_length}
		_on_chant_message(id, "start", 0)
	return Vector2.ZERO


# A bot's chant is played here, one prompt every bot_chant_beat seconds, through
# the same host messages a player's chant sends.
func _tick_bot_chant(delta: float) -> void:
	if _bot_chant.is_empty():
		return
	if not _chanting or not (_bots.has(_taya) or _taya == GOD_TAYA):
		_bot_chant.clear()
		return
	_bot_chant["left"] = float(_bot_chant["left"]) - delta
	if float(_bot_chant["left"]) > 0.0:
		return
	_bot_chant["left"] = _bot_beat()
	if _chant_step == int(_bot_chant["fail_at"]):
		_bot_chant.clear()
		_on_chant_message(_taya, "result", 0)
		return
	_on_chant_message(_taya, "step", _chant_step + 1)
	if _chant_step >= chant_length:
		_bot_chant.clear()
		_on_chant_message(_taya, "result", 1)


func _bot_beat() -> float:
	return god_chant_beat if _taya == GOD_TAYA else bot_chant_beat


# --- THE GODS AS TAYA ----------------------------------------------------------

# The gods' body: a mortal body whose own sprite is hidden, wearing the pair's look
# (see THE GODS' LOOK) - God-Taya.png when the art exists, Ikapati's overseer
# sprite otherwise. Hidden until GO.
func _spawn_god() -> void:
	_god_body = MORTAL_SCENE.instantiate()
	(bots_root if bots_root != null else self).add_child(_god_body)
	_god_body.set_lock(true)  # moved by this script on the host, mirrored elsewhere
	_ghostly(_god_body)
	_god_body.ring_color = UITokens.god_accent(god)
	_god_body.sprite.visible = false  # not a mortal: the Lamang sprite stays hidden
	_god_lift = maxf(0.0, god_height - MORTAL_HEIGHT)
	_god_body.set_display_name(god.display_name, UITokens.god_text(god))
	_god_body.name_tag.position.y -= _god_lift  # above their head, not over it
	_god_body.floating_text.position.y -= _god_lift
	# GodLook sits at a mortal's feet, so the puff grows from the ground up.
	_god_look = Node2D.new()
	_god_look.name = "GodLook"
	_god_look.position = Vector2(0.0, MORTAL_FEET)
	_god_body.add_child(_god_look)
	var ring := Line2D.new()  # the pair's accent on the ground, under their feet
	ring.name = "GodRing"
	ring.width = 2.0
	ring.default_color = UITokens.god_accent(god)
	ring.closed = true
	for step in range(24):
		ring.add_point(Vector2.from_angle(TAU * step / 24.0) * Vector2(26.0, 9.0))
	_god_look.add_child(ring)
	var drawn := art("God-Taya.png")
	if drawn != null:
		var still := Sprite2D.new()
		still.texture = drawn
		still.position.y = -MORTAL_FEET  # centred on the body, as the art is drawn
		_god_art = still
	else:
		var sheet := art(GOD_SHEET)
		if sheet != null:
			_god_art = _ikapati_sprite(sheet)
		else:
			var icon := Sprite2D.new()  # no art at all: the god's icon floats over the ring
			icon.texture = god.icon
			icon.scale = Vector2.ONE * (28.0 / maxf(1.0, float(god.icon.get_height())))
			icon.position.y = -god_height
			_god_art = icon
	_god_look.add_child(_god_art)
	_god_body.visible = false


# Ikapati, looping her frames, standing god_height tall with the frame's bottom on
# the look's origin (her "feet").
func _ikapati_sprite(sheet: Texture2D) -> AnimatedSprite2D:
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", 5.0)
	for index in range(maxi(1, sheet.get_width() / GOD_FRAME.x)):
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(Vector2(index * GOD_FRAME.x, 0.0), Vector2(GOD_FRAME))
		frames.add_frame("default", frame)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.scale = Vector2.ONE * (god_height / GOD_ART_HEIGHT)
	sprite.position.y = -GOD_FRAME.y * 0.5 * sprite.scale.y
	sprite.play("default")
	return sprite


# Host: Mapulon & Ikapati are the Taya.
func _gods_take_taya() -> void:
	_taya = GOD_TAYA
	_tagback = tagback_immunity
	_reset_chant()
	_bot_chant.clear()
	_god_time = 0.0
	_god_hunt = -1
	_god_leave = 0.0
	_god_at = _push_out(_field.get_center())
	_announce_taya(GOD_TAYA)


# Host: the gods have tagged someone - they say so and fade off the field.
func _gods_leave() -> void:
	_god_hunt = -1
	_god_leave = god_leave_time
	_show_banner(god_tag_line, god.color, 1.4)
	_log("%s hand the Taya on" % god.display_name, god.color)


# Host, every frame of play: the gods walk (chasing, or hunting one runner once
# the safety valve fires), or fade out after their tag.
func _move_god(delta: float) -> void:
	if _god_leave > 0.0:
		_god_leave = maxf(0.0, _god_leave - delta)
		if _god_leave <= 0.0:
			_god_at = Vector2.INF
		return
	if _taya != GOD_TAYA or _god_at == Vector2.INF:
		return
	_god_time += delta
	if _god_hunt >= 0 and rules.mortal(_god_hunt) == null:
		_god_hunt = -1  # the hunted runner left the game: pick again
	if _god_hunt < 0 and _god_time >= god_taya_max_time:
		_god_hunt = hunt_target()
	var step := Vector2.ZERO
	if not _chanting and _root_left <= 0.0:
		step = _bot_taya_heading(GOD_TAYA, _god_at, _god_hunt)
	if step.length() > 0.01:
		_god_at += step.normalized() * (god_hunt_speed if _god_hunt >= 0 else god_speed) * delta
	var body := Vector2.ONE * (_god_body.radius if _god_body != null else 13.0)
	_god_at = _push_out(_god_at).clamp(_field.position + body, _field.end - body)


# The safety valve's prey: the runner with the most FAVOR on the Lupa, the
# nearest of a tie - or, when everyone is safe, the richest runner anywhere.
func hunt_target() -> int:
	var best := -1
	var best_key := Vector2(-INF, -INF)  # (on the Lupa, FAVOR), then the nearest
	var best_gap := INF
	for entry in mortal_entries():
		var id := int(entry["id"])
		var mortal := rules.mortal(id)
		if mortal == null:
			continue
		var key := Vector2(0.0 if is_safe(id) else 1.0, float(mortal.favor))
		var gap := _god_at.distance_to(entry["pos"])
		if key > best_key or (key == best_key and gap < best_gap):
			best = id
			best_key = key
			best_gap = gap
	return best


func god_hunt_id() -> int:
	return _god_hunt


# Every screen: the gods' body where the host says (a client glides to it).
func _draw_god(delta: float) -> void:
	if _god_body == null:
		return
	var shown := _god_at != Vector2.INF and _phase == Phase.PLAYING
	if shown and (_authority or not _god_body.visible or _god_body.global_position.distance_to(_god_at) > ghost_snap_distance):
		_god_body.global_position = _god_at
	elif shown:
		_god_body.global_position = _god_body.global_position.lerp(_god_at, minf(1.0, ghost_smoothing * delta))
	if shown and not _god_body.visible:
		_puff_god()
	_god_body.visible = shown
	if god_overseer != null:
		god_overseer.visible = not shown  # one Ikapati at a time
	_god_art.set("flip_h", _god_body.facing < 0)
	_god_body.modulate.a = _god_leave / maxf(0.01, god_leave_time) if _god_leave > 0.0 else 1.0
	# Their line over the body too: the tagged mortal's own banner says YOU ARE TAYA.
	if _god_leave > 0.0 and not _god_said and shown:
		_god_body.show_floating_text(god_tag_line, UITokens.god_text(god), god_leave_time + 0.6)
	_god_said = _god_leave > 0.0


# The gods pop in: their look grows from their feet with a little overshoot.
func _puff_god() -> void:
	_god_look.scale = Vector2.ONE * 0.2
	create_tween().tween_property(_god_look, "scale", Vector2.ONE, god_puff_time) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- INPUT -------------------------------------------------------------------

# RIGHT CLICK starts the chant and the move keys answer its prompts. Read in
# _input like Hanan's left click (the shell's full-screen Control would eat a
# mouse event otherwise); the move keys are free while the Taya is rooted.
func _input(event: InputEvent) -> void:
	if super._tap_panel_click(event):
		return
	if _taya != _my_id or _phase != Phase.PLAYING or dialogue.is_active() or due_menu.is_open():
		return
	if event.is_action_pressed("defend"):
		start_chant()
		return
	if not _my_chanting:
		return
	for direction in range(MOVE_ACTIONS.size()):
		if event.is_action_pressed(MOVE_ACTIONS[direction]):
			chant_key(direction)
			return


# --- FRAME -------------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	_tick_my_chant(delta)
	if _taya == _my_id and _phase == Phase.PLAYING:
		player.global_position = _push_out(player.global_position)
	_draw_langits(delta)
	_draw_god(delta)
	_place_marker()
	_draw_chant()
	_draw_guides()
	_refresh_hud(delta)


# Langit: lifted with a shadow, shaking while they crumble, fading in when new,
# greyed and locked on this screen when closed to us.
func _draw_langits(delta: float) -> void:
	if langits_root == null:
		return
	if _shown_season != _season:
		_shown_season = _season
		_fade = 0.0
	_fade = minf(1.0, _fade + delta / maxf(0.01, langit_fade_in))
	var nodes := langits_root.get_children()
	while nodes.size() < _langits.size() and not nodes.is_empty():
		var extra: Node = nodes[0].duplicate()
		langits_root.add_child(extra)
		nodes.append(extra)
	var shaking := is_crumbling()
	for index in range(nodes.size()):
		var node: Node2D = nodes[index]
		node.visible = index < _langits.size()
		if not node.visible:
			continue
		var jitter := Vector2.ZERO
		if shaking and screen_shake_allowed():
			jitter = Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		node.position = _langits[index] + jitter
		var closed := is_closed_for(_my_id, index)
		var shade := 0.5 if closed else 1.0
		node.modulate = Color(shade, shade, shade + 0.05, _fade * (0.55 if shaking else 1.0))
		var lock := node.get_node_or_null("Lock") as CanvasItem
		if lock != null:
			lock.visible = closed
		var crumble := node.get_node_or_null("Crumble") as Sprite2D
		if crumble != null and crumble.texture != null:
			crumble.visible = shaking
			crumble.frame = clampi(int((1.0 - _season_timer / maxf(0.01, shift_warning)) * crumble.hframes), 0, crumble.hframes - 1)


func _place_marker() -> void:
	if taya_marker == null:
		return
	var at := taya_position() if _taya != -1 and _phase == Phase.PLAYING else Vector2.INF
	if at != Vector2.INF and _ghosts.has(_taya) and is_instance_valid(_ghosts[_taya]):
		at = (_ghosts[_taya] as Node2D).global_position  # where the rival is drawn
	elif at != Vector2.INF and _taya == GOD_TAYA and _god_body != null:
		at = _god_body.global_position  # where the gods are drawn
	taya_marker.visible = at != Vector2.INF
	if at == Vector2.INF:
		return
	if taya_ring != null:  # the placeholder ring circles a mortal; the gods have their own on the ground
		taya_ring.visible = (taya_sprite == null or not taya_sprite.visible) and _taya != GOD_TAYA
	taya_marker.global_position = at + Vector2(0.0, -_god_lift if _taya == GOD_TAYA else 0.0)  # over the gods' heads
	# The tag-back buffer: the marker blinks while the new Taya cannot tag.
	if _tagback > 0.0:
		taya_marker.modulate.a = 0.35 if int(_tagback * 8.0) % 2 == 0 else 1.0
	else:
		taya_marker.modulate.a = 1.0


# The rhyme over the Taya's head: a word lights up as each prompt is hit (gold),
# a broken chant shows its word in red. Only the Taya sees the arrows.
func _draw_chant() -> void:
	if chant_row == null:
		return
	chant_row.visible = _chanting or _my_chanting or _chant_broken >= 0
	if not chant_row.visible:
		return
	var mine := _taya == _my_id and _my_chanting
	var hit := _my_step if mine else _chant_step
	for index in range(chant_row.get_child_count()):
		var slot := chant_row.get_child(index) as Node2D
		slot.visible = index < chant_length
		var tint := UITokens.FAINT
		if index == _chant_broken and not mine:
			tint = UITokens.EMBER
		elif index < hit:
			tint = UITokens.GOLD
		elif mine and index == hit:
			tint = UITokens.IVORY
		var word := slot.get_node_or_null("Word") as Label
		if word != null:
			word.text = CHANT_WORDS[index % CHANT_WORDS.size()]
			word.add_theme_color_override("font_color", tint)
		var arrow := slot.get_node_or_null("Arrow") as Polygon2D
		if arrow != null:
			arrow.visible = mine and index < _my_chant.size()
			if arrow.visible:
				arrow.rotation = float(_my_chant[index]) * PI * 0.5
				arrow.color = tint


# The shrinking ring under us after an ALIS, and the first visit's arrow to the
# nearest open Langit.
func _draw_guides() -> void:
	var left := swap_left(_my_id)
	if swap_ring != null:
		swap_ring.visible = _phase == Phase.PLAYING and left > 0.0
		if swap_ring.visible:
			swap_ring.global_position = player.global_position
			swap_ring.scale = Vector2.ONE * maxf(0.15, left / maxf(0.01, swap_time))
	if guide == null:
		return
	var target := _nearest_langit(_my_id, player.global_position)
	guide.visible = first_visit and _phase == Phase.PLAYING and trial_time - _trial_time <= guide_time \
		and _taya != _my_id and not is_safe(_my_id) and target >= 0
	if not guide.visible:
		return
	var from := player.global_position
	var tip := _langits[target]
	var back := (from - tip).normalized() * 12.0
	guide.points = PackedVector2Array([from, tip, tip + back.rotated(0.5), tip, tip + back.rotated(-0.5)])


# --- ART ---------------------------------------------------------------------

static func art(file: String) -> Texture2D:
	var path := ART_DIR + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _apply_art() -> void:
	var platform := art("Langit.png")
	var crumble := art("Langit-Crumble.png")
	if langits_root != null:
		for node in langits_root.get_children():
			var sprite := node.get_node_or_null("Sprite") as Sprite2D
			if sprite != null:
				sprite.texture = platform
				sprite.visible = platform != null
			var body := node.get_node_or_null("Body") as ColorRect
			if body != null:
				body.visible = platform == null
			var cracks := node.get_node_or_null("Crumble") as Sprite2D
			if cracks != null:
				cracks.texture = crumble
				cracks.visible = false
				if crumble != null:
					cracks.hframes = maxi(1, int(round(float(crumble.get_width()) / float(maxi(1, crumble.get_height())))))
	var marker := art("Taya-Marker.png")
	if taya_sprite != null:
		taya_sprite.texture = marker
		taya_sprite.visible = marker != null
	var ring := get_node_or_null("TayaMarker/Ring")
	if ring != null:
		ring.visible = marker == null
		(ring as Line2D).default_color = god.color
	var watcher := art("MapulonIkapati-Overseer.png")
	if overseer != null:
		overseer.texture = watcher
		overseer.visible = watcher != null
	var backdrop := art("Arena-Background.png")
	if background != null and backdrop != null:
		background.texture = backdrop
		background.position = SCREEN_SIZE * 0.5
		background.scale = SCREEN_SIZE / backdrop.get_size()


# --- HUD ---------------------------------------------------------------------

func _set_callout(text: String, tint: Color, seconds: float) -> void:
	_callout_time = seconds
	_show_callout(text, tint, seconds > 0.0)


func _show_callout(text: String, tint: Color, shown := true) -> void:
	if callout_label == null:
		return
	callout_label.text = text
	callout_label.add_theme_color_override("font_color", UITokens.readable_on_dark(tint, UITokens.NIGHT_900))
	callout_label.visible = shown


func _refresh_hud(delta: float) -> void:
	_callout_time = maxf(0.0, _callout_time - delta)
	_taya_tip_left = maxf(0.0, _taya_tip_left - delta)
	var swapping := swap_left(_my_id)
	if swapping > 0.0:
		_callout_time = 0.0
		_show_callout("ALIS NA!", TAYA_COLOR)
	elif _callout_time > 0.0:
		pass  # a timed callout is still up
	elif is_crumbling():
		_show_callout("THE LANGIT CRUMBLE!", UITokens.god_text(god))
	elif callout_label != null:
		callout_label.visible = false
	if rules_card != null:
		rules_card.visible = first_visit and _phase == Phase.COUNTDOWN
	if taya_tip != null:
		taya_tip.visible = _taya_tip_left > 0.0 and _taya == _my_id
	if taya_list != null:
		var ids: Array = rules.mortals.keys()
		ids.sort_custom(func(a, b): return taya_seconds(int(a)) < taya_seconds(int(b)))
		var rows: Array[String] = ["TIME AS TAYA"]
		if _taya == GOD_TAYA:
			rows.append("> %s" % god.display_name)
		for id in ids:
			rows.append("%s%s  %.1fs" % ["> " if int(id) == _taya else "", mortal_label(int(id)), taya_seconds(int(id))])
		taya_list.text = "\n".join(rows)
	var taya_at := taya_position()
	if status_label != null:
		var dash := "DASH READY" if dash_cooldown_left() <= 0.0 else "DASH %.1fs" % dash_cooldown_left()
		var stance := "ON THE LUPA"
		var tint := god.color
		if _taya == _my_id:
			stance = "TAYA - CHANTING" if _my_chanting else "TAYA"
			tint = TAYA_COLOR
		elif swapping > 0.0:
			stance = "ALIS NA! %.1fs" % swapping
			tint = TAYA_COLOR
		elif is_safe(_my_id):
			stance = "SAFE"
			tint = SAFE_COLOR
		elif taya_at != Vector2.INF and player.global_position.distance_to(taya_at) <= close_call_radius:
			tint = TAYA_COLOR
		status_label.text = "%s     STREAK %d     %s" % [stance, streak_of(_my_id), dash]
		status_label.add_theme_color_override("font_color", UITokens.readable_on_dark(tint, UITokens.NIGHT_900))
	if hint_label != null:
		if _taya == _my_id:
			var chant := "RIGHT CLICK - CHANT" if _chant_cd <= 0.0 else "CHANT IN %.1fs" % _chant_cd
			hint_label.text = "TAG RUNNERS ON THE LUPA    %s    SHIFT / SPACE - DASH" % chant
		else:
			hint_label.text = "REACH A NEW LANGIT FOR FAVOR    SHIFT / SPACE - DASH    E / Q - FAVORS    F - GOD'S DUE"
