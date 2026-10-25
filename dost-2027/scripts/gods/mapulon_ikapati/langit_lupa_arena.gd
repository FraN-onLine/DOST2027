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
#   god_leave_time) - until THE BLITZ, they never stay as an extra hunter.
#   SAFETY VALVE: after god_taya_max_time seconds without a tag the gods pick the
#   runner with the most FAVOR on the Lupa (the nearest of a tie; anyone, if all
#   are safe) and hunt only them at god_hunt_speed. A round that ends with the
#   gods still Taya pays by the mortals' times as usual (all zero: a tie).
#   god_starts_as_taya = false brings back the old rule: the rhyme lands on the
#   mortal with the most FAVOR (ties: random).
#   The Taya walks taya_speed_bonus (10%) faster - the player, a bot and the gods
#   as THE Taya (not Ikapati as the blitz's second Taya); the dash is unchanged.
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
#   The scene's Border (ArenaField/Border) is the field, as in every other arena:
#   the base reads it (authored_rect), the host sends it with the layout so clients
#   agree, and nothing here resizes or redraws it. It is the same for 2, 3 and 4
#   mortals; only the number of Langit grows with the roster (langit_count).
#
# LANGIT
#   langit_count() spots: one more than there are mortals, so every runner can be
#   safe at once. A Langit is one of the two prefabs (scenes/gods/mapulon_ikapati,
#   Langit1.tscn / Langit2.tscn): a stone pillar whose art spawns out of rubble
#   (pillar1 or pillar2 played backwards) and falls back into rubble when it
#   crumbles (played forwards). Its SafeArea hitbox is the safe zone, exactly as
#   authored - the player standing inside it is safe, and stepping up to one plays
#   the mortal's jump clip hop_lead px before the hitbox. Every season_interval
#   seconds the season turns: the Langit shake for shift_warning seconds ("THE
#   LANGIT CRUMBLE!"), crumble - whoever stood on them drops onto the Lupa - and
#   reappear somewhere new: clear of the UI strip, never on top of each other, at
#   least taya_clearance from the Taya (both Tayas in the blitz) and
#   langit_spacing from each other (the spacing gives way first on a crowded field).
#   ONE LANGIT AT A TIME: each slot holds one Langit with an id (a new one every
#   time it forms), a state and a timer (_cloud_id / _cloud_state / _cloud_timer,
#   host-run, sent in the tick; clients only draw them): SOLID -> CRUMBLING
#   (crumble_time of falling, still safe) -> GONE (reform_delay, nobody is safe on
#   it) -> FORMING (langit_fade_in, safe, rising at a fresh legal spot) -> SOLID.
#   THE LANGIT'S LIFE: the first time a runner (never a Taya) is on a SOLID Langit it
#   starts a cloud_life countdown (_cloud_burn). It never resets or pauses - not when
#   the runner steps off, not when others step on. It shakes and reddens as it runs
#   out; at 0 it crumbles under anyone still on it, and a new one forms elsewhere
#   about reform_delay + crumble_time later. Stepping off crumbles nothing. Only that
#   slot moves; a season turn moves them all (and a season or ALIS crumble that comes
#   first wins).
#   A SOLID Langit with a timer is doomed by an ALIS (below). _closed and _last_left
#   hold Langit ids, so a Langit that formed again in the same slot is a new one.
#
# THE CHANT (RIGHT CLICK, the `defend` action, while chant_cooldown is ready;
# never on `attack`, even with an old saved binding that put both on one button)
#   The Taya is rooted - no moving, no tagging, no dash - and chant_length key
#   prompts appear over its head, one per word of the rhyme ("LANGIT", "LUPA",
#   "IMPYERNO", "SAKSAK PUSO", "ALIS!"), each a direction (W/A/S/D or the arrows).
#   Press them in order, chant_beat seconds each. A wrong key or a missed beat
#   breaks the chant: the Taya stumbles (chant_fail_stun, still rooted) and the
#   cooldown starts anyway. A full chant yells ALIS!: every runner on a Langit
#   gets swap_time seconds to step off (a shrinking ring, "ALIS NA!"), that Langit
#   is closed to them (greyed and locked on their screen), and anyone still on it
#   is shoved off (shove_force, away from the Taya). Every Langit someone stood on
#   is DOOMED: it stays (stepping off does not crumble it early) for the
#   swap_time window, then crumbles (crumble_time) - whoever is still on it drops
#   to the Lupa - and forms again elsewhere reform_delay later. So with the
#   defaults: ALIS at 0 s, the crumble starts at 1.5 s, the Langit is gone at
#   1.9 s and its new one forms at 2.4 s (solid by 2.7 s). ALIS! means change
#   places: the Langit you were on will not be there to come back to. The Taya is
#   paid chant_favor for each runner it forced off. Everyone sees the words light
#   up over the Taya; only the Taya sees the keys.
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
# THE BLITZ (the last langit_blitz_time seconds)
#   The host starts it from the shared clock and sends the flag in the tick; every
#   screen shows one "BLITZ!" banner in Ikapati's colour, a BLITZ effect timer and
#   BLITZ in the band. Until the end:
#   - IKAPATI PLAYS. She ENTERS AS A TAYA: if the gods are still Taya they simply
#     stay; if they already left, she comes back (the IkapatiTaya body fading in at
#     a spot on the Lupa clear of taya_clearance from the mortal Taya) as a SECOND
#     TAYA with her own TAYA marker. As the second Taya she chases the nearest runner
#     on the Lupa with the god chase AI and chants by the god rules (god_chant_beat,
#     god_chant_success) - her own chant, beside the mortal Taya's, shown on her own
#     marker - and her ALIS dooms Langit like any. Her safety-valve hunt is off.
#   - HER FIRST TAG (as THE Taya or the second one, _god_tag) leaves ONE TAYA AT A
#     TIME for the rest of the blitz: the runner loses tag_steal FAVOR (to nobody -
#     she earns none), their streak ends, and they are the Taya through set_taya
#     (tagback_immunity, YOU ARE TAYA, TIME AS TAYA, a chant in progress cancelled).
#     A mortal Taya there was is a runner again with tagged_mercy. Ikapati BECOMES A
#     RUNNER (_god_runs; "IKAPATI IS RUNNING"): her marker hides, she does not fade
#     out or go back to her post (_gods_leave is skipped in the blitz).
#   - AS A RUNNER she plays the solo bots' runner AI (_run_god: Langit to Langit,
#     fleeing the Taya, dashing), safe inside a SafeArea and taggable on the Lupa.
#     She obeys ALIS (swap_time, closed Langit, the shove), drops when a pillar
#     crumbles, and starts a Langit's cloud_life like any runner (mortal_position
#     and _runner_entries know her as GOD_TAYA). She earns nothing: no crossing
#     pay, streak or close call. She hops onto a Langit (IkapatiTaya.hop, no clip).
#   - THE TAYA TAGGING HER on the Lupa (a player or a bot Taya; both chase her)
#     makes her the Taya again ("IKAPATI IS TAYA"): the god chase AI, the god chant,
#     tagback_immunity and no more; the tagger is a runner with tagged_mercy and
#     gains nothing (she has no FAVOR). Her next tag passes it on and she runs again.
#     Bot runners flee her only while she holds the Taya. She never drains, keeps
#     no TIME AS TAYA and is in no payout, result or panel row.
#   - The season turns every blitz_season_interval seconds (the shake shortened to
#     blitz_shift_warning); the clock to the next turn is cut to it at the start.
#   Network: her position, fade, chant step, role (god_runs; the Taya is `taya`) and
#   the blitz flag ride the tick; clients draw her TAYA marker (in her colour) only
#   while she is a Taya, and a running Ikapati like any runner.
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
# THE GODS' LOOK: the god body is its own scene (IkapatiTaya.tscn, ikapati_taya.gd):
# a mortal body with its mortal sprite hidden and the pair's look authored on it -
# an AnimatedSprite2D (clips idle / chasing, the Godot placeholder until the art
# lands) standing god_height tall (a mortal's height) with its feet where a
# mortal's are, flipped to face where they walk, over a ring of the pair's accent
# on the ground and under the usual name tag and Taya marker (both lifted above its
# head). This file only tells it what the gods are doing (_draw_god). At GO the
# banner says MAPULON & IKAPATI ARE TAYA! on every screen, the body pops in
# (god_puff_time), and the overseer standing in the scene's ArenaField is hidden
# for as long as the god body is on the field, so there is never a second Ikapati.
#
# The rest of the art is drop-in (see Assets/Gods/MapulonIkapati/README.md): each
# file is used when it exists and the placeholder stays when it does not. Every
# number is an @export - tune it in the inspector. The dash itself lives in the
# base (Dash); here the scene shortens it to dash_distance 77 (the base's is 110).

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
# The gods' body as Taya (see THE GODS' LOOK).
const GOD_TAYA_SCENE := preload("res://scenes/gods/mapulon_ikapati/IkapatiTaya.tscn")
# The two sky platforms (scenes/gods/mapulon_ikapati): one pillar clip each. Their
# SafeArea hitboxes are the safe zone (both authored alike), the clip spawns
# backwards and crumbles forwards, and the host picks one per slot.
const LANGIT_SCENES: Array[PackedScene] = [
	preload("res://scenes/gods/mapulon_ikapati/Langit1.tscn"),
	preload("res://scenes/gods/mapulon_ikapati/Langit2.tscn"),
]
const RULES_LUPA_GODS := "LUPA: the Taya can tag you here. Mapulon & Ikapati are Taya first!"
# One slot's Langit (see ONE LANGIT AT A TIME).
enum Cloud { SOLID, CRUMBLING, GONE, FORMING }

@export_category("Langit Lupa")
@export var fixed_trial_time := 60.0     # the round length here (0 = the lobby's)
@export var tag_radius := 26.0           # how close the Taya must get to tag
@export var tagback_immunity := 1.0      # seconds a new Taya cannot tag
@export var taya_speed_bonus := 1.10     # the Taya walks this much faster (player, bot Taya, Ikapati as THE Taya)
@export var tagged_mercy := 1.0          # seconds the old Taya cannot be tagged back
@export var tag_steal := 60              # FAVOR a tag moves from the runner to the Taya
@export var taya_clearance := 100.0      # no Langit lands this close to the Taya
@export var taya_drain := 10             # FAVOR per second as Taya
@export var payout_best := 600           # least time as Taya
@export var payout_worst := 100          # most time as Taya
@export var tie_window := 0.25           # Taya times this close are a tie
@export var langit_spacing := 140.0      # least distance between two Langit centres
@export var langit_fade_in := 0.3        # seconds a new Langit takes to rise
@export var hop_lead := 20.0             # px before a Langit's safe zone that starts the jump clip

@export_category("Seasons")
@export var season_interval := 12.0      # seconds between two crumbles
@export var shift_warning := 1.0         # seconds of shaking before a crumble
@export var crumble_time := 0.4          # one Langit's shake once its life (or its ALIS window) is over
@export var cloud_life := 5.0            # seconds a Langit lasts once a runner first steps on it
@export var bot_unsafe_life := 1.5       # solo bots treat a Langit with less life left than this as unsafe
@export var reform_delay := 0.5          # seconds a crumbled Langit is gone before it forms again elsewhere

@export_category("Blitz")
@export var langit_blitz_time := 30.0    # the last seconds: Ikapati hunts too, the seasons race
@export var blitz_season_interval := 3.0
@export var blitz_shift_warning := 0.6

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
@export var god_height := 78.0           # px the god body stands (a mortal is 78)
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
@onready var status_label: Label = get_node_or_null(BAND_STATE + "Status")
@onready var rules_card: Control = get_node_or_null("LangitHud/RulesCard")
@onready var taya_tip: Control = get_node_or_null("LangitHud/TayaTip")

var _taya := -1
var _tagback := 0.0
var _taya_time: Dictionary = {}      # mortal id -> seconds spent as Taya
var _drain_pending: Dictionary = {}  # mortal id -> FAVOR owed, banked once a second
var _drain_tick := 1.0
var _langits: Array[Vector2] = []    # Langit centres, one per slot
var _cloud_id: Array[int] = []       # each slot's Langit (a new id every time one forms)
var _cloud_state: Array[int] = []    # each slot's Cloud
var _cloud_timer: Array[float] = []  # seconds left in that state (SOLID: to its ALIS crumble, 0 = none)
var _cloud_burn: Array[float] = []   # seconds of cloud_life left once a runner stepped on it (-1 = nobody has)
var _cloud_anim: Array[int] = []     # each slot's pillar scene (0 = Langit1, 1 = Langit2), host-picked
var _cloud_look: Array[int] = []     # the cloud id whose animation is on the slot's node
var _cloud_phase: Array[int] = []    # 0 hidden, 1 rising (backwards), 2 standing, 3 falling (forwards)
var _langit_box := Rect2(-48.0, -30.0, 96.0, 60.0)  # the prefab's safe hitbox, local to its root
var _jump_on := -1                   # the Langit the player is stepping onto (for the jump clip)
var _next_cloud := 0                 # host: the next Langit id
var _season := 0                     # how many layouts the field has had
var _season_timer := 0.0             # seconds to the next crumble
var _blitz := false                  # the last langit_blitz_time seconds (host-decided, mirrored)
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
var _closed: Dictionary = {}         # id -> the Langit id closed to them (until it crumbles or the season turns)
var _shoving: Dictionary = {}        # host: id -> seconds to the next shove off a closed Langit
var _on: Dictionary = {}             # host: id -> the slot they stand on (-1 = the Lupa)
var _last_left: Dictionary = {}      # host: id -> the Langit id they last stepped off
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
var _god_body: IkapatiTaya
var _god_at := Vector2.INF           # where the gods stand (INF: off the field)
var _god_time := 0.0                 # host: seconds the gods have been Taya
var _god_hunt := -1                  # the runner the safety valve hunts (-1: none)
var _god_leave := 0.0                # seconds left of the fade after their tag
var _god_said := false               # this screen showed their line over the body
var _god_lift := 0.0                 # px the name tag and the Taya marker sit above a mortal's
var _god_fade := 1.0                 # this screen: the body's fade-in, 0 -> 1 over god_puff_time
# Ikapati's own chant as the blitz's second Taya (host-run; clients mirror _god_step):
var _god_step := -1                  # words hit (-1: not chanting)
var _god_beat := 0.0                 # host: seconds to her next word
var _god_fail_at := -1               # host: the word her chant breaks on (-1: it holds)
var _god_root := 0.0                 # host: her stumble after a broken chant
var _god_chant_cd := 0.0
var _god_marker: Node2D              # her TAYA marker in the blitz (a copy of TayaMarker, in her colour)
var _god_runs := false               # the blitz: Ikapati passed the Taya on and plays as a runner (host-run, mirrored)
var _god_dash := Vector2.ZERO        # host: her dash (or a shove off a closed Langit) as a runner, px/s
var _god_dash_left := 0.0
var _god_jump_on := -1               # this screen: the Langit she is stepping onto (for her hop)


func _ready() -> void:
	if fixed_trial_time > 0.0:
		trial_time = fixed_trial_time
	_read_langit_box()
	_decorate_langits()
	super._ready()
	_spawn_bots()
	_spawn_god()
	var lupa_rule := get_node_or_null("LangitHud/RulesCard/Lines/Lupa") as Label
	if lupa_rule != null and god_starts_as_taya:
		lupa_rule.text = RULES_LUPA_GODS


# --- ARENA HOOKS (see scripts/gods/common/arena.gd) --------------------------

func collect_units() -> void:
	_apply_art()


# The Taya walks taya_speed_bonus faster (each screen, its own mortal).
func arena_speed_scale() -> float:
	return taya_speed_bonus if _taya == _my_id and _phase == Phase.PLAYING else 1.0


# The effect timers (Arena.local_effects) this game adds: the blitz, the ALIS clock when
# we are told to change places, the closed Langit we cannot stand on until it crumbles
# (or the season turns), and the tag-back buffer of a new Taya.
func arena_local_effects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _phase != Phase.PLAYING:
		return out
	if _blitz:
		out.append(effect(&"blitz", "BLITZ - IKAPATI RUNS TOO" if _god_runs else "BLITZ - IKAPATI HUNTS TOO", null, UITokens.god_accent(god), maxf(0.0, _trial_time), langit_blitz_time, true))
	var swapping := swap_left(_my_id)
	if swapping > 0.0:
		out.append(effect(&"alis", "ALIS - CHANGE PLACES", null, UITokens.EMBER, swapping, swap_time, true))
	if _closed.has(_my_id) and _season_timer > 0.0:
		var life := _cloud_life(_slot_of(int(_closed[_my_id])))
		if life < _season_timer:
			out.append(effect(&"closed", "YOUR LANGIT IS CLOSED", null, UITokens.EMBER, life, swap_time + crumble_time, true))
		else:
			out.append(effect(&"closed", "YOUR LANGIT IS CLOSED", null, UITokens.EMBER, _season_timer, season_length(), true))
	if _taya == _my_id and _tagback > 0.0:
		out.append(effect(&"tagback", "CANNOT TAG YET", null, UITokens.EMBER, _tagback, tagback_immunity, true))
	return out


# The follow camera's edge arrow: the Taya and, in the blitz, Ikapati (a marker is
# shown only while it has someone to sit on, and on our own head when it is us).
func edge_targets() -> Array:
	return [taya_marker, _god_marker].filter(func(marker) -> bool: return marker != null)


func arena_round_reset() -> void:
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
	_blitz = false
	_god_runs = false
	_god_dash_left = 0.0
	_reset_god_chant()
	for runners in [_swap, _closed, _shoving, _on, _last_left, _close_call, _streak, _bot_goal, _bot_react, _bot_chant]:
		runners.clear()
	if _authority:
		_place_langits()
	for id in _bots.keys():
		_bots[id].global_position = _bot_start(int(id))
		_mortal_positions[int(id)] = _bots[id].global_position


func arena_rules_tick(delta: float) -> void:
	if not _blitz and _trial_time <= langit_blitz_time:
		_start_blitz()
	_move_bots(delta)
	_move_god(delta)
	_tick_season(delta)
	_tick_clouds(delta)
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
	if second_taya():
		_check_god_tag()
	_drain_tick -= delta
	if _drain_tick <= 0.0:
		_drain_tick += 1.0
		_bank_drain()


func arena_tick_fields() -> Dictionary:
	var fields := {
		"taya": _taya,
		"tagback": _tagback,
		"taya_time": _taya_time.duplicate(),
		"langits": _langits.duplicate(),
		"cloud_id": _cloud_id.duplicate(),
		"cloud_state": _cloud_state.duplicate(),
		"cloud_timer": _cloud_timer.duplicate(),
		"cloud_burn": _cloud_burn.duplicate(),
		"cloud_anim": _cloud_anim.duplicate(),
		"blitz": _blitz,
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
		"god_step": _god_step,
		"god_runs": _god_runs,  # her role: the Taya is `taya`, else the second Taya or a runner
	}
	# The host's own YOU ARE TAYA is not every screen's (each announces its Taya from
	# the tick), or a client would read it over IKAPATI IS RUNNING.
	if hud != null and hud.banner_label.text == "YOU ARE TAYA":
		fields["banner"] = ""
	return fields


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
	_cloud_id.assign(state.get("cloud_id", _cloud_id))
	_cloud_state.assign(state.get("cloud_state", _cloud_state))
	_cloud_timer.assign(state.get("cloud_timer", _cloud_timer))
	_cloud_burn.assign(state.get("cloud_burn", _cloud_burn))
	_cloud_anim.assign(state.get("cloud_anim", _cloud_anim))
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
	_god_step = int(state.get("god_step", _god_step))
	var runs := bool(state.get("god_runs", _god_runs))
	var blitz := bool(state.get("blitz", _blitz))
	if blitz and not _blitz:
		_announce_blitz()
	_blitz = blitz
	if _taya != previous:
		_announce_taya(_taya)
	if runs and not _god_runs:
		_god_runs = true
		_announce_god_runs()
	_god_runs = runs


# The countdown is the counting rhyme: the base's "3", "2", "1" become its beats.
func _show_banner(text: String, color: Color, duration := 2.0) -> void:
	if _phase == Phase.COUNTDOWN and text.is_valid_int():
		text = RHYME[clampi(int(round(countdown_time)) - int(text), 0, RHYME.size() - 1)]
	super._show_banner(text, color, duration)


# At GO the rhyme's pointer lands on the gods (or, with god_starts_as_taya off,
# on the mortal with the most FAVOR - read once begin_trial() has paid First
# Light, so it is the real one).
func _start_trial(show_go := true) -> void:
	super._start_trial(show_go)
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
# When it passes from the gods, they leave the field - except in the blitz, where
# Ikapati stays on (as a runner, see _god_tag). GOD_TAYA here is the blitz's runner
# Ikapati, tagged: she is the Taya again.
func set_taya(mortal_id: int) -> void:
	var old := _taya
	if old == GOD_TAYA and mortal_id != GOD_TAYA and not _blitz:
		_gods_leave()
	if mortal_id == GOD_TAYA:
		_god_runs = false
		_god_dash_left = 0.0
		_god_hunt = -1
		_reset_god_chant()
	_taya = mortal_id
	_tagback = tagback_immunity
	_reset_chant()
	_bot_chant.clear()
	_swap.erase(mortal_id)
	_shoving.erase(mortal_id)
	_on[mortal_id] = -1
	if old != -1 and old != mortal_id:  # (Ikapati too, when she passes it on in the blitz)
		_on[old] = -1
		_last_left[old] = -1
		set_mortal_invuln(old, tagged_mercy)
	_announce_taya(mortal_id)


func _announce_taya(mortal_id: int) -> void:
	if mortal_id == GOD_TAYA:
		if _blitz:
			_log("Ikapati is the Taya", UITokens.god_accent(god))
			_show_banner("IKAPATI IS TAYA", UITokens.god_accent(god), 1.4)
			return
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


# Every screen: Ikapati passed the Taya on in the blitz and runs. The runner she
# tagged keeps their own YOU ARE TAYA banner.
func _announce_god_runs() -> void:
	_log("Ikapati is running", UITokens.god_accent(god))
	if _taya != _my_id:
		_show_banner("IKAPATI IS RUNNING", UITokens.god_accent(god), 1.2)


func taya_id() -> int:
	return _taya


# Where the Taya stands - the gods' body or a mortal (Vector2.INF: unknown).
func taya_position() -> Vector2:
	return mortal_position(_taya)


# GOD_TAYA stands where her body does, so the runner helpers (is_safe, _swap, the
# crossings) work for her when she runs in the blitz.
func mortal_position(mortal_id: int) -> Vector2:
	return _god_at if mortal_id == GOD_TAYA else super.mortal_position(mortal_id)


# Every runner a Taya can chase: the mortals and, while she runs in the blitz, Ikapati.
func _runner_entries() -> Array:
	var entries := mortal_entries()
	if _god_runs and _god_at != Vector2.INF:
		entries.append({"id": GOD_TAYA, "pos": _god_at})
	return entries


func taya_label() -> String:
	return god.display_name if _taya == GOD_TAYA else mortal_label(_taya)


func _check_tag() -> void:
	if _tagback > 0.0 or _chanting or _root_left > 0.0:
		return
	var from := taya_position()
	if from == Vector2.INF:
		return
	for entry in _runner_entries():
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
	if catcher == GOD_TAYA and _blitz:
		_god_tag(mortal_id)  # she passes it on and runs
		return
	if mortal_id == GOD_TAYA:
		# Ikapati caught on the Lupa: she has no FAVOR to steal, so the catcher gains
		# nothing - she is simply the Taya again (and the catcher a runner, with mercy).
		_log("%s tags Ikapati" % mortal_label(catcher), UITokens.god_accent(god))
		set_taya(GOD_TAYA)
		return
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


# TIME AS TAYA, in each player's panel on the left strip: their time as `M:SS`, the
# Taya's row in the Taya colour, and - once anyone has held it - the least time (the
# one that pays most; ties within tie_window share it) in gold with a #1.
func panel_row(mortal_id: int) -> Dictionary:
	if rules == null or rules.mortal(mortal_id) == null:
		return {}
	var seconds := taya_seconds(mortal_id)
	var best := INF
	for id in rules.mortals.keys():
		best = minf(best, taya_seconds(int(id)))
	var text := "TAYA %d:%02d" % [int(seconds / 60.0), int(seconds) % 60]
	var tint := UITokens.IVORY
	if best > 0.0 or seconds > 0.0:
		if seconds - best <= tie_window:
			text += "  #1"
			tint = UITokens.GOLD
	if mortal_id == _taya:
		tint = TAYA_COLOR
	return {"text": text, "tint": tint}


func strip_note() -> String:
	if _taya == GOD_TAYA:
		return "IKAPATI IS TAYA" if _blitz else "%s ARE TAYA" % god.display_name.to_upper()
	if _god_runs:
		return "BLITZ: IKAPATI IS RUNNING"
	return "BLITZ: IKAPATI IS TAYA TOO" if second_taya() else ""


# The Taya can never stand on a Langit: anything inside one is put back on the
# nearest edge.
func _push_out(at: Vector2) -> Vector2:
	for index in range(_langits.size()):
		var rect := langit_rect(index)
		if _cloud_state[index] == Cloud.GONE or not rect.has_point(at):
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
		_net.rpc_id(1, "request_langit_chant", kind, value, scene_token())


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
	announce_stun(_taya, chant_fail_stun)  # the Taya stumbles: stars over their head
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


# ALIS! Everyone on a Langit must change places, and every Langit they stood on
# crumbles once the swap_time window is over. `caller` is the Taya who chanted
# (GOD_TAYA for Ikapati, also as the blitz's second Taya).
func _yell_alis(caller := _taya) -> void:
	var forced := 0
	for entry in _runner_entries():
		var id := int(entry["id"])
		if id == _taya:
			continue
		var index := langit_index_at(id, entry["pos"])
		if index < 0:
			continue
		_swap[id] = swap_time
		_closed[id] = _cloud_id[index]
		_doom(index)
		forced += 1
	if forced > 0 and caller >= 0:  # the gods are not paid
		bank_favor(chant_favor * forced, "Chant", caller)
	var who := god.display_name if caller == GOD_TAYA else mortal_label(caller)
	_log("%s yells ALIS! - %d must change places" % [who, forced], god.color)


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
		var slot := _slot_of(int(_closed.get(id, -1)))
		if at == Vector2.INF or not _inside(slot, at):
			_shoving.erase(id)
			continue
		var wait := float(_shoving[id]) - delta
		if wait <= 0.0:
			_shove(int(id), from if from != Vector2.INF else _langits[slot])
			wait = shove_stun
		_shoving[id] = wait


func _shove(mortal_id: int, from: Vector2) -> void:
	if mortal_id == GOD_TAYA:  # Ikapati the runner: pushed along her own dash
		_god_dash = (_god_at - from).normalized() * shove_force
		_god_dash_left = shove_stun
	elif _bots.has(mortal_id):
		var bot: ArenaMortal = _bots[mortal_id]
		hit_effects(bot.global_position, bot.global_position - from)
		bot.hit(bot.global_position - from, shove_stun, shove_force)
	else:
		knock_mortal(mortal_id, from, shove_stun, shove_force)


# --- CROSSINGS -----------------------------------------------------------------

# Host, every frame: who reached a Langit (the first runner on it starts its life
# clock), who stepped off one, and whether a Taya came close on the way. Ikapati
# running in the blitz lights a Langit like anyone but is never paid.
func _tick_crossings() -> void:
	var hunters := _hunter_spots()
	for entry in _runner_entries():
		var id := int(entry["id"])
		if id == _taya:
			continue
		var pos: Vector2 = entry["pos"]
		var at := langit_index_at(id, pos)
		var was := int(_on.get(id, -1))
		var near := hunters.any(func(hunter: Vector2) -> bool: return pos.distance_to(hunter) <= close_call_radius)
		_light_cloud(at)
		if at == was:
			if at < 0 and near:
				_close_call[id] = true
			continue
		_on[id] = at
		if was >= 0 and was < _langits.size():
			_last_left[id] = _cloud_id[was]
			_close_call[id] = near
		if at >= 0 and id != GOD_TAYA and _cloud_id[at] != int(_last_left.get(id, -1)):
			_pay_crossing(id)


# A runner is on Langit `index`: the first one starts its cloud_life clock.
func _light_cloud(index: int) -> void:
	if index >= 0 and _cloud_burn[index] < 0.0 and _cloud_state[index] in [Cloud.SOLID, Cloud.FORMING]:
		_cloud_burn[index] = cloud_life


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


func season_length() -> float:
	return blitz_season_interval if _blitz else season_interval


func _tick_season(delta: float) -> void:
	_season_timer -= delta
	if _season_timer <= 0.0:
		_season_timer += season_length()
		_turn_season()


# Mapulon turns the season: the Langit crumble (everyone on them drops onto the
# Lupa), every closed Langit opens again, and they reappear somewhere new.
func _turn_season() -> void:
	for runners in [_swap, _closed, _shoving, _on, _last_left, _close_call, _bot_goal]:
		runners.clear()
	_place_langits()


func is_crumbling() -> bool:
	return _phase == Phase.PLAYING and _season_timer <= (blitz_shift_warning if _blitz else shift_warning)


# New spots for every Langit: inside the field and clear of the UI strip, not on
# top of each other, never within taya_clearance of a Taya and langit_spacing
# apart, so a crossing is a real distance. In play they fade in (FORMING); a
# countdown's layout is simply there.
func _place_langits() -> void:
	var before := _langits.duplicate()
	_clear_clouds()
	var area := _langit_area()
	var forming := _phase == Phase.PLAYING
	for index in range(langit_count(rules.mortals.size())):
		_add_cloud(_find_spot(area), Cloud.FORMING if forming else Cloud.SOLID, langit_fade_in if forming else 0.0)
	if not before.is_empty() and _langits == before:
		_move_one_cloud()  # a new season must not land on exactly the old field
	_season += 1
	if _authority and _networked:
		_publish_arena_tick()


# The grid is finite, so a random draw can give the same layout twice: move one
# Langit to a free spot when that happens.
func _move_one_cloud() -> void:
	var spots := _langit_spots(_langit_area())
	var hunters := _hunter_spots()
	for relax in range(3):
		for spot in spots:
			if _langits.has(spot) or not _langit_spot_ok(spot, hunters, relax, 0):
				continue
			_langits[0] = spot
			_cloud_look[0] = -1
			_cloud_phase[0] = 0
			return
	for spot in spots:
		if not _langits.has(spot):
			_langits[0] = spot
			_cloud_look[0] = -1
			_cloud_phase[0] = 0
			return


func _clear_clouds() -> void:
	for slots in [_langits, _cloud_id, _cloud_state, _cloud_timer, _cloud_burn, _cloud_anim, _cloud_look, _cloud_phase]:
		slots.clear()


func _add_cloud(spot: Vector2, state := Cloud.SOLID, timer := 0.0) -> void:
	_langits.append(spot)
	_cloud_id.append(_next_cloud)
	_next_cloud += 1
	_cloud_state.append(state)
	_cloud_timer.append(timer)
	_cloud_burn.append(-1.0)
	_cloud_anim.append(randi() % 2)
	_cloud_look.append(-1)
	_cloud_phase.append(0)


# The prefab's SafeArea is the safe zone: read its rectangle once, so the rules
# use exactly the hitbox the pillar was authored with.
func _read_langit_box() -> void:
	var probe: Node = _langit_scene(0).instantiate()
	var shape_node := probe.get_node_or_null("SafeArea/CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		var size := (shape_node.shape as RectangleShape2D).size
		_langit_box = Rect2(shape_node.position - size * 0.5, size)
	probe.free()


# The scene for a slot's pillar, and a decorated instance of it.
func _langit_scene(variant: int) -> PackedScene:
	return LANGIT_SCENES[clampi(variant, 0, LANGIT_SCENES.size() - 1)]


func _langit_node(variant: int) -> Node2D:
	var node: Node2D = _langit_scene(variant).instantiate()
	_decorate_langit(node)
	return node


# The old placeholders' name tag and closed lock are not part of the pillar art,
# so they are added to each prefab instance (once) at start-up.
func _decorate_langits() -> void:
	if langits_root == null:
		return
	for node in langits_root.get_children():
		_decorate_langit(node)


func _decorate_langit(node: Node) -> void:
	if node.get_node_or_null("Name") == null:
		var title := Label.new()
		title.name = "Name"
		title.offset_left = -40.0
		title.offset_top = -11.0
		title.offset_right = 40.0
		title.offset_bottom = 11.0
		title.theme_type_variation = &"WorldLabel"
		title.text = "LANGIT"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_child(title)
	if node.get_node_or_null("Lock") == null:
		var lock := Node2D.new()
		lock.name = "Lock"
		lock.position = Vector2(0.0, -20.0)
		lock.visible = false
		var body := ColorRect.new()
		body.name = "Body"
		body.offset_left = -7.0
		body.offset_top = -3.0
		body.offset_right = 7.0
		body.offset_bottom = 8.0
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.color = Color(0.42, 0.45, 0.55, 1)
		lock.add_child(body)
		var shackle := Line2D.new()
		shackle.name = "Shackle"
		shackle.points = PackedVector2Array([Vector2(-4, -3), Vector2(-4, -8), Vector2(-2, -10), Vector2(2, -10), Vector2(4, -8), Vector2(4, -3)])
		shackle.width = 2.0
		shackle.default_color = Color(0.9490196, 0.9098039, 0.8117647, 1)
		lock.add_child(shackle)
		node.add_child(lock)


# Where a Langit root may land so its whole hitbox stays inside the field and
# clear of the UI strip.
func _langit_area() -> Rect2:
	var area := Rect2(_field.position - _langit_box.position, _field.size - _langit_box.size)
	var left := maxf(area.position.x, UI_STRIP_WIDTH - _langit_box.position.x)
	return Rect2(left, area.position.y, maxf(0.0, area.end.x - left), area.size.y)


# The spots a Langit root may take: as many across as fit, and one more row when
# the hitboxes stack. The lower row is offset half a step so a platform is never
# directly under another (a real crossing, not a stack).
func _langit_spots(area: Rect2) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	if area.size.x < 0.0 or area.size.y < 0.0:
		return spots
	var box := _langit_box.size
	var cols := maxi(1, int(floor(area.size.x / maxf(box.x, 1.0))) + 1)
	var rows := 1
	if area.size.y >= box.y:
		rows = 2
	for row in range(rows):
		var y := area.position.y if row == 0 else area.end.y
		var offset := 0.0
		if row % 2 == 1 and cols > 1:
			offset = area.size.x / float(cols - 1) * 0.5
		for col in range(cols):
			var x := area.position.x
			if cols > 1:
				x += area.size.x * float(col) / float(cols - 1)
			x += offset
			if x > area.end.x + 0.01:
				continue
			spots.append(Vector2(minf(x, area.end.x), y))
	return spots


# A legal spot with every rule; on a crowded field langit_spacing gives way first,
# then the Tayas' clearance. The UI strip (the area itself) and the overlap rule
# never do. `skip` is the slot being re-placed (it is not in its own way).
func _find_spot(area: Rect2, skip := -1) -> Vector2:
	var hunters := _hunter_spots()
	var candidates := _langit_spots(area)
	for relax in range(3):
		var valid: Array[Vector2] = []
		for spot in candidates:
			if _langit_spot_ok(spot, hunters, relax, skip):
				valid.append(spot)
		if not valid.is_empty():
			return valid.pick_random()
	# Nothing legal: the spot farthest from a Taya beats any overlap.
	var best := area.get_center()
	var best_gap := -INF
	for spot in candidates:
		var gap := INF
		for hunter in hunters:
			gap = minf(gap, spot.distance_to(hunter))
		if gap > best_gap:
			best_gap = gap
			best = spot
	return best


func _langit_spot_ok(spot: Vector2, hunters: Array[Vector2], relax := 0, skip := -1) -> bool:
	if relax < 2 and hunters.any(func(hunter: Vector2) -> bool: return spot.distance_to(hunter) < taya_clearance):
		return false
	var here := Rect2(spot + _langit_box.position, _langit_box.size)
	for index in range(_langits.size()):
		if index == skip or _cloud_state[index] == Cloud.GONE:
			continue
		var other := Rect2(_langits[index] + _langit_box.position, _langit_box.size)
		if here.intersects(other):
			return false
		if relax < 1 and spot.distance_to(_langits[index]) < langit_spacing:
			return false
	return true


# --- ONE LANGIT AT A TIME (host-run; see LANGIT) ------------------------------

# Host, every frame of play: each slot's Langit through SOLID (an ALIS's doom
# running out) -> CRUMBLING -> GONE -> FORMING somewhere new -> SOLID.
func _tick_clouds(delta: float) -> void:
	for index in range(_langits.size()):
		var left := _cloud_timer[index] - delta
		if _cloud_burn[index] >= 0.0 and _cloud_state[index] in [Cloud.SOLID, Cloud.FORMING]:
			_cloud_burn[index] = maxf(0.0, _cloud_burn[index] - delta)
			if _cloud_burn[index] <= 0.0:
				_crumble(index)
				continue  # (CRUMBLING takes the crumble_time clock from here)
		match _cloud_state[index]:
			Cloud.SOLID:
				if _cloud_timer[index] > 0.0:
					_cloud_timer[index] = maxf(0.0, left)
					if left <= 0.0:
						_crumble(index)
			Cloud.CRUMBLING:
				_cloud_timer[index] = left
				if left <= 0.0:
					_cloud_gone(index)
			Cloud.GONE:
				_cloud_timer[index] = left
				if left <= 0.0:
					_reform(index)
			Cloud.FORMING:
				_cloud_timer[index] = left
				if left <= 0.0:
					_cloud_state[index] = Cloud.SOLID
					_cloud_timer[index] = 0.0


# A Langit starts to crumble (still safe for crumble_time). One already falling
# or gone is left alone.
func _crumble(index: int) -> void:
	if index < 0 or index >= _langits.size() or _cloud_state[index] in [Cloud.CRUMBLING, Cloud.GONE]:
		return
	_cloud_state[index] = Cloud.CRUMBLING
	_cloud_timer[index] = crumble_time


# ALIS on a Langit: it stays for the swap_time window, then crumbles. A Langit
# already doomed or falling keeps its own clock.
func _doom(index: int) -> void:
	if _cloud_state[index] == Cloud.FORMING or (_cloud_state[index] == Cloud.SOLID and _cloud_timer[index] <= 0.0):
		_cloud_state[index] = Cloud.SOLID
		_cloud_timer[index] = swap_time


func _doomed(index: int) -> bool:
	return _cloud_state[index] == Cloud.SOLID and _cloud_timer[index] > 0.0


# Gone: whoever stood on it is on the Lupa now, and whoever it was closed to is
# free of it.
func _cloud_gone(index: int) -> void:
	_cloud_state[index] = Cloud.GONE
	_cloud_timer[index] = reform_delay
	for id in _closed.keys():
		if int(_closed[id]) == _cloud_id[index]:
			_closed.erase(id)
			_shoving.erase(id)


# A new Langit (a new id) forms in the slot at a fresh legal spot.
func _reform(index: int) -> void:
	var old := _langits[index]
	_langits[index] = _find_spot(_langit_area(), index)
	if _langits[index] == old:
		for spot in _langit_spots(_langit_area()):
			if not _langits.has(spot):
				_langits[index] = spot
				break
	_cloud_id[index] = _next_cloud
	_next_cloud += 1
	_cloud_state[index] = Cloud.FORMING
	_cloud_timer[index] = langit_fade_in
	_cloud_burn[index] = -1.0
	_cloud_anim[index] = randi() % 2
	_cloud_look[index] = -1
	_cloud_phase[index] = 0


# A Langit worth running for: not falling, not doomed, not gone, and (for the bots)
# with more than bot_unsafe_life of its cloud_life left.
func _lasting(index: int) -> bool:
	if _cloud_burn[index] >= 0.0 and _cloud_burn[index] < bot_unsafe_life:
		return false
	return _cloud_state[index] == Cloud.FORMING or (_cloud_state[index] == Cloud.SOLID and _cloud_timer[index] <= 0.0)


# Seconds a Langit has left before it is gone (INF: it is not going anywhere).
func _cloud_life(index: int) -> float:
	if index < 0:
		return 0.0
	var burn := _cloud_burn[index] + crumble_time if _cloud_burn[index] >= 0.0 else INF
	if _doomed(index):
		return minf(_cloud_timer[index] + crumble_time, burn)
	if _cloud_state[index] == Cloud.CRUMBLING:
		return _cloud_timer[index]
	return 0.0 if _cloud_state[index] == Cloud.GONE else burn


# The slot holding Langit `cloud` (-1: it is gone, or never was).
func _slot_of(cloud: int) -> int:
	return _cloud_id.find(cloud) if cloud >= 0 else -1


func langit_rect(index: int) -> Rect2:
	return Rect2(_langits[index] + _langit_box.position, _langit_box.size)


func _inside(index: int, at: Vector2) -> bool:
	return index >= 0 and index < _langits.size() and _cloud_state[index] != Cloud.GONE \
		and langit_rect(index).has_point(at)


# The open Langit `mortal_id` stands on at `at` (-1 = the Lupa). The one closed
# to them after an ALIS, and a gone one, do not count.
func langit_index_at(mortal_id: int, at: Vector2) -> int:
	for index in range(_langits.size()):
		if not is_closed_for(mortal_id, index) and _inside(index, at):
			return index
	return -1


func is_closed_for(mortal_id: int, index: int) -> bool:
	return _closed.has(mortal_id) and index >= 0 and index < _cloud_id.size() and int(_closed[mortal_id]) == _cloud_id[index]


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
	return swap_left(mortal_id) > 0.0 and _inside(_slot_of(int(_closed.get(mortal_id, -1))), at)


# The nearest lasting Langit open to `mortal_id`, other than `skip` (-1 = none).
func _nearest_langit(mortal_id: int, here: Vector2, skip := -1) -> int:
	var best := -1
	for index in range(_langits.size()):
		if index == skip or is_closed_for(mortal_id, index) or not _lasting(index):
			continue
		if best < 0 or here.distance_to(_langits[index]) < here.distance_to(_langits[best]):
			best = index
	return best


# --- SOLO BOTS ---------------------------------------------------------------

# The bots fall from the sky at GO with everyone else.
func drop_mortals() -> Dictionary:
	var all := super.drop_mortals()
	for id in _bots.keys():
		if is_instance_valid(_bots[id]):
			all[int(id)] = _bots[id]
	return all


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
		bot.set_display_name(m.display_name, tag_color(m.id))
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
			here += step.normalized() * bot_speed * (taya_speed_bonus if int(id) == _taya else 1.0) * delta
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
	if goal >= _langits.size() or is_closed_for(id, goal) or goal == on or (goal >= 0 and not _lasting(goal)):
		goal = -1  # (a goal that crumbles is dropped: it picks a new one)
	if goal < 0 and on >= 0:
		# Sitting safe. A chant at its fourth word (or ALIS, or its Langit
		# crumbling) gets it moving after a small reaction delay; now and then it
		# dares a crossing by itself.
		if not _bot_react.has(id):
			var chant := (_chanting and _chant_step >= 3) or _god_step >= 3
			if swap_left(id) > 0.0 or chant or not _lasting(on) or randf() < bot_dare_chance * delta:
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
	for chaser in _hunter_spots():  # the Taya, and Ikapati in the blitz
		if here.distance_to(chaser) >= bot_flee_radius:
			continue
		heading += (here - chaser).normalized() * 1.3
		if here.distance_to(chaser) < bot_dash_radius and float(_bot_dash.get(id, 0.0)) <= 0.0 and heading.length() > 0.01:
			_bot_dash[id] = dash_cooldown
			if _bots.has(id):
				(_bots[id] as ArenaMortal).dash(heading, dash_distance, dash_time)
			else:  # Ikapati the runner moves on _god_at, not her body
				_god_dash = heading.normalized() * dash_distance / maxf(0.01, dash_time)
				_god_dash_left = dash_time
	return heading


# Taya (a bot, or the gods - also as the blitz's second Taya): chase the nearest
# runner on the Lupa - only `only` when it is set (the gods' hunt). When the prey
# is safe, walk up to a Langit (the hunted runner's) and chant.
func _bot_taya_heading(id: int, here: Vector2, only := -1) -> Vector2:
	var prey := Vector2.INF
	for entry in _runner_entries():
		var other := int(entry["id"])
		if other == id or other == _taya or is_safe(other) or is_mortal_invulnerable(other) or (only >= 0 and other != only):
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
	if gap.length() > _langit_box.size.length() * 0.5 + 40.0:
		return gap
	if id == GOD_TAYA and _taya != GOD_TAYA:
		_start_god_chant()  # the second Taya's own chant, beside the mortal Taya's
		return Vector2.ZERO
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

# The gods' body (IkapatiTaya.tscn), standing god_height tall. Hidden until GO.
func _spawn_god() -> void:
	_god_body = GOD_TAYA_SCENE.instantiate()
	_god_body.god_height = god_height
	(bots_root if bots_root != null else self).add_child(_god_body)
	_god_lift = _god_body.lift
	_god_body.visible = false
	# Her own TAYA marker for the blitz: the scene's, in her colour.
	if taya_marker != null:
		_god_marker = taya_marker.duplicate()
		_god_marker.name = "GodTayaMarker"
		_god_marker.visible = false
		taya_marker.add_sibling(_god_marker)


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
# the safety valve fires - never in the blitz), or fade out after their tag.
func _move_god(delta: float) -> void:
	if _god_leave > 0.0:
		_god_leave = maxf(0.0, _god_leave - delta)
		if _god_leave <= 0.0:
			_god_at = Vector2.INF
		return
	if _god_runs and _god_at != Vector2.INF:
		_run_god(delta)
		return
	if not god_hunts():
		return
	_tick_god_chant(delta)
	_god_time += delta
	if _blitz:
		_god_hunt = -1
	else:
		if _god_hunt >= 0 and rules.mortal(_god_hunt) == null:
			_god_hunt = -1  # the hunted runner left the game: pick again
		if _god_hunt < 0 and _god_time >= god_taya_max_time:
			_god_hunt = hunt_target()
	var step := Vector2.ZERO
	if not _god_rooted():
		step = _bot_taya_heading(GOD_TAYA, _god_at, _god_hunt)
	if step.length() > 0.01:
		var walk := god_hunt_speed if _god_hunt >= 0 else god_speed
		if _taya == GOD_TAYA:  # THE Taya walks faster (not as the blitz's second Taya)
			walk *= taya_speed_bonus
		_god_at += step.normalized() * walk * delta
	var body := Vector2.ONE * (_god_body.radius if _god_body != null else 13.0)
	_god_at = _push_out(_god_at).clamp(_field.position + body, _field.end - body)


# Host: Ikapati as a blitz runner - the solo bots' runner AI (Langit to Langit,
# fleeing the Taya, dashing) at god_speed. She may stand on a Langit like any runner.
func _run_god(delta: float) -> void:
	_bot_dash[GOD_TAYA] = maxf(0.0, float(_bot_dash.get(GOD_TAYA, 0.0)) - delta)
	_god_dash_left = maxf(0.0, _god_dash_left - delta)
	var step := _bot_heading(GOD_TAYA, _god_at, delta)
	if step.length() > 0.01:
		_god_at += step.normalized() * god_speed * delta
	if _god_dash_left > 0.0:
		_god_at += _god_dash * delta
	var body := Vector2.ONE * (_god_body.radius if _god_body != null else 13.0)
	var low := Vector2(maxf(_field.position.x, UI_STRIP_WIDTH), _field.position.y)
	_god_at = _god_at.clamp(low + body, _field.end - body)


# The gods' body is on the field and hunting: as THE Taya, or as the blitz's
# second one (not while it fades out, nor while Ikapati runs).
func god_hunts() -> bool:
	return _god_at != Vector2.INF and _god_leave <= 0.0 and (_taya == GOD_TAYA or (_blitz and not _god_runs))


# Ikapati is the blitz's second Taya, beside a mortal one.
func second_taya() -> bool:
	return _blitz and _taya != GOD_TAYA and god_hunts()


# Where the Tayas stand: the Taya, and Ikapati as the second one.
func _hunter_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var at := taya_position()
	if at != Vector2.INF:
		out.append(at)
	if second_taya():
		out.append(_god_at)
	return out


# The gods cannot move or tag while their chant (or its stumble) runs: THE
# Taya's chant when they are it, Ikapati's own as the second Taya.
func _god_rooted() -> bool:
	if _taya == GOD_TAYA:
		return _chanting or _root_left > 0.0
	return _god_step >= 0 or _god_root > 0.0


# --- THE BLITZ ---------------------------------------------------------------

# Host, once, at langit_blitz_time left: the seasons race, and Ikapati hunts too -
# staying if the gods are still Taya, coming back if they left.
func _start_blitz() -> void:
	_blitz = true
	_season_timer = minf(_season_timer, blitz_season_interval)
	_god_hunt = -1
	if _taya != GOD_TAYA:
		_god_leave = 0.0
		_god_runs = false
		_god_at = _god_spot()
		_reset_god_chant()
	_announce_blitz()
	if _networked:
		_publish_arena_tick()


# Every screen, once: one banner in Ikapati's colour.
func _announce_blitz() -> void:
	_show_banner("BLITZ!", UITokens.god_accent(god), 1.4)
	_log("BLITZ! Ikapati hunts too, and the Langit crumble every %ds" % int(blitz_season_interval), UITokens.god_accent(god))


# A spot on the Lupa for Ikapati's return: on the field, off every Langit and
# taya_clearance from the mortal Taya (the farthest of the tries on a crowded field).
func _god_spot() -> Vector2:
	var area := _langit_area()
	var taya_at := taya_position()
	var best := _push_out(area.get_center())
	var best_gap := -1.0
	for attempt in range(80):
		var spot := Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
		if _push_out(spot) != spot:
			continue
		var gap := INF if taya_at == Vector2.INF else spot.distance_to(taya_at)
		if gap >= taya_clearance:
			return spot
		if gap > best_gap:
			best = spot
			best_gap = gap
	return best


# Host: Ikapati's touch as the second Taya. It passes the Taya to the runner (see
# _god_tag); the mortal Taya themselves can never be tagged by her.
func _check_god_tag() -> void:
	if _god_rooted():
		return
	for entry in mortal_entries():
		var id := int(entry["id"])
		if id == _taya or is_safe(id) or is_mortal_invulnerable(id):
			continue
		if _god_at.distance_to(entry["pos"]) <= tag_radius:
			_god_tag(id)
			return


# Her tag in the blitz, as THE Taya or the second one: the runner pays tag_steal (to
# nobody: she earns none) and is the one Taya from now on. set_taya hands the old
# Taya (a mortal, or Ikapati herself) tagged_mercy, stops their clock and cancels
# their chant; the gods do not leave in the blitz - Ikapati becomes a runner.
func _god_tag(mortal_id: int) -> void:
	lose_favor(tag_steal, "Tagged", mortal_id)
	_streak[mortal_id] = 0
	_log("Ikapati tags %s" % mortal_label(mortal_id), UITokens.god_accent(god))
	set_taya(mortal_id)
	_god_runs = true
	_god_hunt = -1
	_reset_god_chant()
	_on[GOD_TAYA] = -1
	_announce_god_runs()


func _reset_god_chant() -> void:
	_god_step = -1
	_god_beat = 0.0
	_god_fail_at = -1
	_god_root = 0.0
	_god_chant_cd = 0.0


# Host: the second Taya starts her own chant (god_chant_success, god_chant_beat),
# under the same rules as any: cooldown ready, not mid-stumble, no crumble warning.
func _start_god_chant() -> void:
	if _god_step >= 0 or _god_chant_cd > 0.0 or _god_root > 0.0 or is_crumbling():
		return
	_god_step = 0
	_god_beat = god_chant_beat
	_god_fail_at = -1 if randf() < god_chant_success else randi() % chant_length


# Host: one word every god_chant_beat; a full chant yells ALIS, a broken one
# stumbles her for chant_fail_stun. Either way the cooldown starts.
func _tick_god_chant(delta: float) -> void:
	_god_chant_cd = maxf(0.0, _god_chant_cd - delta)
	_god_root = maxf(0.0, _god_root - delta)
	if _god_step < 0 or _taya == GOD_TAYA:
		_god_step = -1
		return
	_god_beat -= delta
	if _god_beat > 0.0:
		return
	_god_beat = god_chant_beat
	if _god_step == _god_fail_at:
		_god_step = -1
		_god_root = chant_fail_stun
		_god_chant_cd = chant_cooldown
		return
	_god_step += 1
	if _god_step >= chant_length:
		_god_step = -1
		_god_chant_cd = chant_cooldown
		_yell_alis(GOD_TAYA)


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
	var was := _god_body.global_position if _god_body.visible else Vector2.INF  # popping in is not a step
	if shown and (_authority or not _god_body.visible or _god_body.global_position.distance_to(_god_at) > ghost_snap_distance):
		_god_body.global_position = _god_at
	elif shown:
		_god_body.global_position = _god_body.global_position.lerp(_god_at, minf(1.0, ghost_smoothing * delta))
	if shown and not _god_body.visible:
		_god_body.appear(god_puff_time)
		_god_fade = 0.0
	_god_body.visible = shown
	if god_overseer != null:
		god_overseer.visible = not shown  # one Ikapati at a time
	_god_body.set_facing(_god_body.facing)
	_god_fade = minf(1.0, _god_fade + delta / maxf(0.01, god_puff_time))
	_god_body.modulate.a = _god_leave / maxf(0.01, god_leave_time) if _god_leave > 0.0 else _god_fade
	# Their line over the body too: the tagged mortal's own banner says YOU ARE TAYA.
	# Running in the blitz she hops up onto a Langit (a procedural hop: no jump clip).
	var on := _jump_slot_at(_god_at, GOD_TAYA) if shown and _god_runs else -1
	if on >= 0 and on != _god_jump_on:
		_god_body.hop()
	_god_jump_on = on
	if _god_leave > 0.0 and not _god_said and shown:
		_god_body.leave(god_tag_line, UITokens.god_text(god), god_leave_time + 0.6)
	elif _god_leave <= 0.0:
		var walking := was != Vector2.INF and _god_body.global_position.distance_to(was) > 0.1
		var chanting := (_chanting and _taya == GOD_TAYA) or _god_step >= 0
		_god_body.play_state(&"chant" if chanting else &"chasing" if walking else &"idle")
	_god_said = _god_leave > 0.0


# --- INPUT -------------------------------------------------------------------

# RIGHT CLICK (`defend`) starts the chant and the move keys answer its prompts -
# never `attack` (left click), even if an old binding put both on one button. Read
# in _input like Hanan's left click (the shell's full-screen Control would eat a
# mouse event otherwise); the move keys are free while the Taya is rooted.
func _input(event: InputEvent) -> void:
	if super._tap_panel_click(event):
		return
	if _taya != _my_id or _phase != Phase.PLAYING or dialogue.is_active() or due_menu.is_open():
		return
	if event.is_action_pressed("defend") and not event.is_action_pressed("attack"):
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
	_tick_jump()
	_draw_langits(delta)
	_draw_god(delta)
	_place_marker()
	_place_god_marker()
	_draw_chant()
	_draw_guides()
	_refresh_hud(delta)


# The Langit the player is stepping onto, counted from hop_lead px out so the hop
# clip starts just before the hitbox. The one they are on wins; otherwise the
# nearest open Langit within the lead. -1 = none.
func _jump_slot_at(at: Vector2, id := _my_id) -> int:
	var on := langit_index_at(id, at)
	if on >= 0:
		return on
	var best := -1
	var best_distance := INF
	for index in range(_langits.size()):
		if is_closed_for(id, index) or _cloud_state[index] == Cloud.GONE:
			continue
		var near := langit_rect(index).grow(hop_lead)
		if not near.has_point(at):
			continue
		var distance := at.distance_squared_to(near.get_center())
		if distance < best_distance:
			best = index
			best_distance = distance
	if best >= 0:
		return best
	var closed := int(_closed.get(id, -1))
	if closed >= 0 and swap_left(id) > 0.0 and _inside(_slot_of(closed), at):
		return _slot_of(closed)
	return -1


# Stepping onto a Langit plays the mortal's jump clip: it starts hop_lead pixels
# before the safe zone, so the figure is already hopping when it enters. The Taya
# can never do it (a Langit pushes them off), and staying on the same one never
# restarts it.
func _tick_jump() -> void:
	var on := -1
	if _phase == Phase.PLAYING and _taya != _my_id:
		on = _jump_slot_at(player.global_position)
	if on >= 0 and on != _jump_on:
		player.play_animation(&"jump")
	_jump_on = on


# Langit, one prefab per slot: spawning out of rubble while it forms, standing
# while solid, shaking while it crumbles (all of them at a season's warning, one
# alone after its runner left), hidden while gone, greyed and locked on this
# screen when closed to us. Each slot is drawn from its own state, so one Langit
# changing never redraws the others. A client runs the timers on between two
# ticks; the pillar scene is the host's pick, mirrored in the tick.
func _draw_langits(delta: float) -> void:
	if langits_root == null:
		return
	var nodes := langits_root.get_children()
	while _cloud_look.size() < _langits.size():
		_cloud_look.append(-1)
		_cloud_phase.append(0)
	for index in range(_langits.size()):
		var variant := int(_cloud_anim[index]) if index < _cloud_anim.size() else 0
		if index >= nodes.size():
			var extra := _langit_node(variant)
			langits_root.add_child(extra)
			nodes.append(extra)
			continue
		if nodes[index].scene_file_path != _langit_scene(variant).resource_path:
			var fresh := _langit_node(variant)
			var stale: Node = nodes[index]
			langits_root.remove_child(stale)
			stale.queue_free()
			langits_root.add_child(fresh)
			langits_root.move_child(fresh, index)
			nodes[index] = fresh
			_cloud_look[index] = -1
			_cloud_phase[index] = 0
	var season_shake := is_crumbling()
	for index in range(nodes.size()):
		var node: Node2D = nodes[index]
		var state := _cloud_state[index] if index < _cloud_state.size() else Cloud.GONE
		node.visible = index < _langits.size() and state != Cloud.GONE
		if not node.visible:
			if index < _cloud_phase.size() and _cloud_phase[index] != 0:
				_cloud_phase[index] = 0
				var hidden := node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
				if hidden != null:
					hidden.stop()
			continue
		if not _authority:
			_cloud_timer[index] = maxf(0.0, _cloud_timer[index] - delta)
			if _cloud_burn[index] > 0.0 and state in [Cloud.SOLID, Cloud.FORMING]:
				_cloud_burn[index] = maxf(0.0, _cloud_burn[index] - delta)
		var falling := state == Cloud.CRUMBLING
		var burn := _cloud_burn[index] if state in [Cloud.SOLID, Cloud.FORMING] else -1.0
		var burning := burn >= 0.0
		var shaking := season_shake or falling or (burning and burn <= shift_warning)
		var jitter := Vector2.ZERO
		if shaking and screen_shake_allowed():
			jitter = Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		node.position = _langits[index] + jitter
		var closed := is_closed_for(_my_id, index)
		var shade := 0.5 if closed else 1.0
		var heat := 1.0 - burn / maxf(0.01, cloud_life) if burning else 0.0  # 0 fresh -> 1 about to go
		node.modulate = Color(shade, shade * (1.0 - 0.45 * heat), (shade + 0.05) * (1.0 - 0.6 * heat), 0.55 if shaking else 1.0)
		var title := node.get_node_or_null("Name") as Label
		if title != null:
			title.text = "LANGIT %d" % int(ceil(burn)) if burning else "LANGIT"
		var lock := node.get_node_or_null("Lock") as CanvasItem
		if lock != null:
			lock.visible = closed
		_draw_langit_look(index, node, state, season_shake)


# The pillar's own life, from its scene's clip: backwards while it forms
# (rubble to standing), held standing while solid, forwards when it crumbles.
# Switching off the state rather than restarting every frame keeps it smooth.
func _draw_langit_look(index: int, node: Node2D, state: int, season_shake: bool) -> void:
	var sprite := node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite == null or sprite.sprite_frames == null:
		return
	var variant := int(_cloud_anim[index]) if index < _cloud_anim.size() else 0
	var clip := StringName("pillar%d" % (variant + 1))
	if not sprite.sprite_frames.has_animation(clip):
		return
	var id := _cloud_id[index]
	if _cloud_look[index] != id:
		_cloud_look[index] = id
		_cloud_phase[index] = 0
		sprite.speed_scale = 1.0
		if state == Cloud.FORMING:
			sprite.animation = clip
			sprite.play_backwards(clip)
			sprite.frame = sprite.sprite_frames.get_frame_count(clip) - 1
			_cloud_phase[index] = 1
		elif state == Cloud.CRUMBLING:
			sprite.animation = clip
			sprite.play(clip)
			sprite.frame = 1
			_cloud_phase[index] = 3
		else:
			sprite.stop()
			sprite.animation = clip
			sprite.frame = 0
			_cloud_phase[index] = 2
		return
	match _cloud_phase[index]:
		1:
			if state == Cloud.CRUMBLING or (state == Cloud.SOLID and season_shake):
				sprite.play(clip)
				sprite.frame = 1
				_cloud_phase[index] = 3
			elif not sprite.is_playing():
				sprite.frame = 0
				_cloud_phase[index] = 2
		2:
			if state == Cloud.CRUMBLING or (state == Cloud.SOLID and season_shake):
				sprite.play(clip)
				sprite.frame = 1
				_cloud_phase[index] = 3


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


# The blitz's second TAYA marker, over Ikapati's head in her colour, with her own
# chant words in its ChantRow.
func _place_god_marker() -> void:
	if _god_marker == null:
		return
	_god_marker.visible = second_taya() and _phase == Phase.PLAYING and _god_body != null and _god_body.visible
	if not _god_marker.visible:
		return
	_god_marker.global_position = _god_body.global_position + Vector2(0.0, -_god_lift)
	var ring := _god_marker.get_node_or_null("Ring") as CanvasItem
	if ring != null:
		ring.visible = false  # her own ring is on the ground
	var sprite := _god_marker.get_node_or_null("Sprite") as CanvasItem
	if sprite != null:
		sprite.modulate = UITokens.god_accent(god)
	var tag := _god_marker.get_node_or_null("Tag") as Label
	if tag != null:
		tag.add_theme_color_override("font_color", UITokens.god_text(god))
	var row := _god_marker.get_node_or_null("ChantRow") as Node2D
	if row != null:
		row.visible = _god_step >= 0
		if row.visible:
			_draw_chant_words(row, _god_step, -1, false)


# The rhyme over the Taya's head: a word lights up as each prompt is hit (gold),
# a broken chant shows its word in red. Only the Taya sees the arrows.
func _draw_chant() -> void:
	if chant_row == null:
		return
	chant_row.visible = _chanting or _my_chanting or _chant_broken >= 0
	if not chant_row.visible:
		return
	var mine := _taya == _my_id and _my_chanting
	_draw_chant_words(chant_row, _my_step if mine else _chant_step, _chant_broken, mine)


func _draw_chant_words(row: Node2D, hit: int, broken: int, mine: bool) -> void:
	for index in range(row.get_child_count()):
		var slot := row.get_child(index) as Node2D
		slot.visible = index < chant_length
		var tint := UITokens.FAINT
		if index == broken and not mine:
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

# "TAYA!" over the mortal, in the base's callout pill.
func _set_callout(text: String, tint: Color, seconds: float) -> void:
	_callout_time = seconds
	callout(text, tint, seconds)


func _refresh_hud(delta: float) -> void:
	_callout_time = maxf(0.0, _callout_time - delta)
	_taya_tip_left = maxf(0.0, _taya_tip_left - delta)
	var swapping := swap_left(_my_id)
	# A state's callout is held up frame by frame and lets go a moment after it ends.
	if swapping > 0.0:
		_callout_time = 0.0
		callout("ALIS NA!", TAYA_COLOR, 0.2)
	elif _callout_time > 0.0:
		pass  # a timed callout is still up
	elif is_crumbling():
		callout("THE LANGIT CRUMBLE!", UITokens.god_text(god), 0.2)
	if rules_card != null:
		rules_card.visible = first_visit and _phase == Phase.COUNTDOWN and not drop_active()
		rules_card.modulate.a = hud_alpha
	if taya_tip != null:
		taya_tip.visible = _taya_tip_left > 0.0 and _taya == _my_id
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
		status_label.text = "%s%s     STREAK %d     %s" % ["BLITZ     " if _blitz else "", stance, streak_of(_my_id), dash]
		status_label.add_theme_color_override("font_color", UITokens.readable_on_dark(tint, UITokens.NIGHT_900))
	if hint_label != null:
		if _taya == _my_id:
			var chant := "%s CHANT" % key_cap(&"defend").to_upper() if _chant_cd <= 0.0 else "CHANT IN %ds" % int(ceil(_chant_cd))
			hint_label.text = "TAG RUNNERS ON THE LUPA   %s   %s DASH" % [chant, key_cap(&"dash")]
		else:
			hint_label.text = "REACH A NEW LANGIT   %s DASH   %s" % [key_cap(&"dash"), favor_keys_hint()]
