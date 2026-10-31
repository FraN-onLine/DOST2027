class_name Arena
extends Node2D

# The shared base every god's arena extends (Mayari now, Apolaki and the rest
# later). A god's arena is two files, both in the god's own folder:
#
#   scenes/gods/<god>/<God>Arena.tscn    an INHERITED scene: it takes the shared
#                                        scene (scenes/gods/common/Arena.tscn)
#                                        and only adds the god's own art and
#                                        nodes, and drops the god's own script
#                                        on the root. MayariArena.tscn is
#                                        exactly that.
#   scripts/gods/<god>/<god>_arena.gd    `extends Arena`: only that god's rules.
#
# WHAT THIS BASE OWNS (never copy any of it into a god's arena)
#
#   * UI_STRIP_WIDTH - the left band of the screen the Game shell
#     (scenes/Game.tscn) covers with its panels (your name, FAVOR, DUE, the E/Q
#     favor bars, the other mortals). An arena is therefore authored in screen
#     space, exactly as it will be played: the scene is 1152 x 648 big, the left
#     UI_STRIP_WIDTH pixels stay EMPTY of gameplay art (no floor, no goal, no
#     clone and no mortal starts there - the shared scene keeps a locked
#     "GAME UI AREA" body over the strip so the reservation is visible while
#     editing) and nothing scales, stretches or re-centres the scene at runtime.
#     The shell only instantiates the arena and hands it god_id / embedded /
#     dialogue_prefix. What the designer sees in the arena scene is what every
#     player gets.
#
#   * THE SCREEN'S LAYOUT, right of the strip: a god is WATCHING, so the field is
#     small and low and the god's overseer art stands huge behind and above it.
#     Each arena draws its own Border (the old, hand-fitted field - no shared
#     rectangle) and keeps to these rules:
#       the overseer  is big, behind the HUD, and never moved for a HUD element -
#                     move the element
#       the band      (BandLayer/Band, shared) runs along the bottom of the
#                     screen right of the strip and holds every trial's action
#                     UI in two rows: row 1 (band_state) the trial's live state -
#                     its Status line, Apolaki's duel bars, Mayari's attack bar -
#                     authored as children of BandLayer/Band/Rows/State in the
#                     god's own scene; row 2 the controls hint (hint_label, a
#                     HintStrip: keys as keycaps, BODY text). It may cover the
#                     field's lowest pixels and turns see-through while our
#                     mortal stands under it; it steps aside while a god speaks.
#                     Big announcements (banners, callouts) stay centred.
#     A hit's wash (FlashLayer/ScreenFlash) covers the whole screen; the shade
#     while a god speaks (FieldDim) the world only, so it never dims a HUD.
#
#   * THE BANDANAS: every mortal (the local one, the ghosts, a solo bot) wears the
#     same sprite, and only the bandana tells the players apart: set_bandana() on
#     the mortal, with the colour the host gave that player in the lobby
#     (Network.bandana_of, painted by _paint_bandanas() whenever the roster is
#     republished). The swap lives under the sprite's modulate, so a hit flash, a
#     freeze or Mayari's blitz tint still shows on top of it.
#
#   * THE EFFECT TIMERS: local_effects() lists everything running on THIS screen's
#     mortal - its own lasting skills and a Pamana's opening window (buffs), and what
#     rivals, traps and knocks have put on it: Ligaw na Damo, Drowsy, Rooted, Half Vision's
#     blindness, Sun Patches, boosted losses, Tala's pull, a stun (debuffs). The HUD draws
#     them as a stack in its top-right corner. An arena adds its own through
#     arena_local_effects(); every number comes from where it already lives, so the stack
#     never disagrees with the rule it shows.
#
#   * THE FOLLOW CAMERA (the lobby's CAMERA = FOLLOW PLAYER, follow_camera):
#     off by default, and then nothing above changes - the whole authored field
#     is on screen and world = screen. On, the LOCAL mortal carries a Camera2D
#     (zoomed in, smoothed, held inside the field plus follow_margin, aimed so
#     the mortal stands in the middle of what the UI strip leaves visible). It
#     is only this screen's view: positions, bounds, ghosts, bots and every rule
#     keep the same world coordinates and the host never reads it. What belongs
#     to the screen stays there - every HUD lives on a CanvasLayer (the shell's
#     panels too), a click is taken into the world through the canvas
#     transform (Tala's aim) and the vision mask is placed through
#     get_global_transform_with_canvas(). What the camera hides, an arena
#     lists in edge_targets(): a small arrow on the HUD's edge points at each
#     of them that is out of view.
#
#   * THE ROUND: trial_time (the round clock - 1:30), countdown_time (the
#     "3 - 2 - 1"), the INTRO -> COUNTDOWN -> PLAYING -> RESULTS flow, the clock
#     signal the shell reads, the results panel and the closing dialogue. Every
#     number below is @export, so a god's arena is re-tuned in its own inspector
#     and never in code.
#
#   * THE MORTAL: the spawn (read from the scene), locking it during dialogue,
#     its walking bounds, its name tag, the remote mortals ("ghosts") of the
#     other players, the mercy seconds after a hit and the knockback that
#     follows one - on every peer, host or client (see knock_mortal()).
#
#   * THE FEEL OF A HIT - the field's shake and the screen's wash that answer a
#     landed blow (shake_pixels / flash_time, _shake_screen() / _flash_screen(),
#     reset by _reset_screen_impact()). The HUD never shakes. A knockback
#     flagged `impact` plays it on the victim's screen - here or across the wire.
#
#   * THE DIALOGUE AND THE MENUS: the god's intro lines, the closing lines, the
#     God's Due menu and the handshake that keeps every peer on the same line.
#
#   * FLOATING TEXT: every FAVOR popup, a word over a mortal and a trial's callout
#     is plain outlined text (UI/Popups/favor_popup.tscn) - no frame, no icon: the
#     number at 16 px (24 for 250+) in JADE / EMBER, the reason on a second line at
#     8 px. They live in screen space on the popup layer (POPUP_LAYER: above the
#     blackout, the sun patches and Hanan's bar, below the bottom band) and follow
#     their mortal through the follow camera. Each mortal has a stack - a new popup
#     pushes the older ones up by their real height, at most POPUP_MAX, the oldest
#     fading early - kept inside the screen, clear of the left strip and the band. A
#     rival's are 75% size and opacity. favor_popup() for FAVOR, mortal_popup() for a
#     word, spawn_popup() at a world spot, cast_popup() for a god's E icon, callout()
#     for a trial's "TAYA!" / "TRIP!" (one at a time).
#
#   * THE NETWORK PLUMBING that is identical for every arena: who is
#     authoritative, reporting where our mortal is, mirroring the host's FAVOR
#     snapshot and world tick, the dialogue handshake, and telling a peer when
#     the host just decided its mortal was hit.
#
# WHAT A GOD'S ARENA ADDS (Mayari: four favor zones and two clones)
#
#   * the arena's own scene nodes and art (children of ArenaField, Zones,
#     Clones, Ghosts, Popups...),
#   * collect_units()     - build/refresh them once the field is known,
#   * arena_rules_tick(d) - the per-frame rules of the god's game (host only),
#   * arena_round_reset() - put them back to their authored start each round,
#   * arena_layout_fields() / arena_read_layout() and arena_tick_fields() /
#     arena_read_tick() - the few numbers that travel so every screen shows the
#     same round.
#   FAVOR is never touched directly: call bank_favor() / lose_favor() and the
#   popups, the HUD event line and the God's Due milestones follow from it.
#
# Input every arena can count on (project.godot):
#   move_left/right/up/down  WASD / arrows
#   skill_e / skill_q        the god's two favors
#   attack                   LEFT MOUSE - the mortal's attack (Arnis,
#                            Tumbang Preso). Ignore it while a dialogue or a
#                            menu is open, exactly like the other actions.
#   dash                     SHIFT (and SPACE) - a short burst along the way the
#                            mortal moves. Off unless the arena sets
#                            dash_enabled (Langit Lupa); SPACE is also
#                            advance_dialogue, so it only dashes during play.
#
# The two favor panels are tappable as well as keyed: anyone (the arena's own
# HUD, or the shell's bars in an embedded run) hands them to the arena with
# register_tap_panel(), and Arena._input answers a click on one of them the way
# its key would. The click has to be claimed there - before the GUI ever sees
# it - because the arenas above read their attack from _input, which runs first
# and would otherwise treat a tap on a panel as an attack on the world.
#
# Solo: this scene simulates everything.
# Multiplayer: the HOST is authoritative and is the only clock. It broadcasts
# the round - phase, seconds, the arena's own state at 10 Hz and FAVOR snapshots
# at 5 Hz. Every client sends its mortal's position and mirrors whatever the host
# sends, so all the screens show the same second and the same world.

signal trial_complete
signal trial_time_changed(seconds: float)

const UI_STRIP_WIDTH := 238.0
# Where a god's scene parents its row-1 nodes (see THE SCREEN'S LAYOUT above).
const BAND_STATE := "BandLayer/Band/Rows/State/"
# The band's opacity while our mortal stands under it.
const BAND_SEE_THROUGH := 0.35

# The colour a favor zone glows while a god is lighting it.
const FAVOR_COLOR := Color(1.0, 0.86, 0.25)

const HUD_SCENE := preload("res://UI/GodsArena/god_hud.tscn")
const DIALOGUE_SCENE := preload("res://UI/GodsArena/god_dialogue.tscn")
const DUE_MENU_SCENE := preload("res://UI/GodsArena/gods_due_menu.tscn")
const MORTAL_SCENE := preload("res://scenes/gods/common/Mortal.tscn")
const POPUP_SCENE := preload("res://UI/Popups/favor_popup.tscn")
const TEMP_ICON := preload("res://Assets/Placeholders/god.png")
const SUN_PATCH_ICON := preload("res://Assets/Gods/Apolaki/Sun-Patch.png")

# One-shot effects (spawn_effect): placeholders until real art - swap the file, keep the
# slot (UI/theme/ART_SLOTS.md, "One-shot effects"). `from` -> `to` is the scale over
# `time` seconds; `soft` ones (flashes) are dimmed with Settings "reduce flashing".
const EFFECTS := {
	&"spark": {"texture": preload("res://Assets/Placeholders/fx/hit_spark.png"), "from": 0.25, "to": 0.75, "time": 0.22, "tint": Color(1.0, 0.95, 0.7), "soft": true},
	&"slash": {"texture": preload("res://Assets/Placeholders/fx/hit_slash.png"), "from": 0.55, "to": 0.9, "time": 0.2, "tint": Color(1.0, 1.0, 1.0), "soft": false},
	&"impact": {"texture": preload("res://Assets/Placeholders/fx/impact_ring.png"), "from": 0.15, "to": 0.55, "time": 0.26, "tint": Color(1.0, 0.8, 0.6), "soft": true},
}

# The photo of the current god - taken from the god's .tres icon field (each
# god's .tres carries its own portrait now, so we no longer need a shared icon).
const GOD_PHOTO := TEMP_ICON

# A FAVOR popup: light yellow when FAVOR arrives, light red when it is taken.
const POPUP_GAIN_COLOR := UITokens.JADE    # the design system's gain / loss colours
const POPUP_LOSS_COLOR := UITokens.EMBER
const POPUP_OFFSET := Vector2(0.0, -42.0)   # a mortal known only by its position: its head, in world px
const POPUP_LAYER := 11          # above the blackout (5), Hanan's bar (4) and the sun patches (11, earlier in the tree); below the band (12)
const POPUP_GAP := 2.0           # px between two popups in a mortal's stack
const POPUP_MAX := 3             # popups in a stack; a 4th fades the oldest out early
const POPUP_HEAD_GAP := 4.0      # px between the name tag and the first popup
const POPUP_BIG_MOMENT := 250    # a change this big is drawn at 24 px
const RIVAL_POPUP_LOOK := 0.75   # a rival's popups: this size and opacity
const CALLOUT_TOP := 150.0       # a screen-centred callout's bottom edge, px from the top

const DIALOGUE_TIMEOUT := 20.0
const GUIDANCE_RADIUS := 150.0
# How long a favor blot the host hands us stays up when the favor's own
# patch_duration is not carried across the wire (the favors themselves say 1.5s).
const FAVOR_PATCH_TIME := 1.5
# How long a cast's name stays over the mortal that used it, seconds, and how readable
# its colour is made (the favor's own, lightened until it reads this well on the night
# - a dark favor like Tala's blue would otherwise sink into the grass).
const CAST_TEXT_TIME := 1.6
const CAST_TEXT_CONTRAST := 7.0
# The E skills that reach other mortals: Rest and Refreshed's drowsiness and Down
# to Homeland's root. The host keeps their clocks in GodMatch; each screen plays
# them for its OWN mortal, so only the numbers travel.
const DROWSY_SPEED := 0.5          # a drowsy mortal walks at this share of their speed
const ROOT_SHADOW_BACK := 90.0     # px behind the mortal the dark shadow waits
const ROOT_DRAG_TIME := 0.6        # seconds the shadow drags them back when the root ends
const ROOT_SHADOW_LINGER := 0.2    # a beat at the shadow before the leash fades
const ROOT_SHADOW_SIZE := Vector2(28.0, 10.0)
const ROOT_SHADOW_COLOR := Color(0.05, 0.04, 0.09, 0.72)
const ROOT_TETHER_COLOR := Color(0.1, 0.08, 0.16, 0.85)

enum Phase { INTRO, COUNTDOWN, PLAYING, RESULTS }

@export_category("Identity")
@export var god_id: StringName = &"mayari"
# Set by the Game shell when the arena runs as one of its trials: the shell
# draws the shared panels and the arena hides its duplicates.
@export var embedded := false
@export var dialogue_prefix := "mayari"
@export var next_god_id: StringName = &""
@export var final_trial := false
# Set by the shell: false the first time a god hosts, so the arena knows to speak
# its full intro rather than the short "take your place again" line.
@export var first_visit := true
# FAVOR per God's Due, handed to this arena's GodMatch. The shell sets it from the
# lobby's run settings; a standalone arena keeps the default.
@export var due_step := GodMatch.MILESTONE_STEP

@export_category("Shared Arena Rules")
# The round every arena is played in - 1:30. This is the one clock shared by all
# arenas: edit this number and every arena follows.
@export var trial_time := 90.0
# The "3 - 2 - 1" the mortals wait through before the round starts.
@export var countdown_time := 3.0
# FAVOR the closing lines call a success.
@export var success_favor := 1000
# Mercy seconds after a mortal is hit - it cannot be hit again while it lasts.
@export var invuln_time := 1.2
# Mercy every mortal starts a round with.
@export var spawn_immunity := 1.0

@export_category("Dash")
# Only the arenas that ask for it (Langit Lupa) let the mortal dash.
@export var dash_enabled := false
@export var dash_distance := 110.0
@export var dash_time := 0.15
@export var dash_cooldown := 1.6
# A SPACE pressed this many seconds early (still recharging, stunned, mid-dash)
# is kept and fires the moment the dash is ready, instead of being dropped.
@export var dash_buffer := 0.12

@export_category("Knockback")
# What a hit does to a mortal: no control for this long, shoved at this speed.
@export var knock_stun := 1.3
@export var knock_force := 560.0

@export_category("Screen Impact")
# The weight a landed blow has on the screen it happens on: the FIELD jumps
# (never the HUD, so its labels stay readable) and a wash flashes over it.
# Every arena shares this - a god's arena only says WHEN (see _shake_screen(),
# _flash_screen() and knock_mortal's `impact` flag).
@export var shake_pixels := 7.0       # how far the field jumps on an impact
@export var flash_time := 0.25        # seconds the screen flash fades over
@export var impact_shake_time := 0.3  # seconds a flagged knockback shakes for

@export_category("Follow Camera")
# Set by the shell from the lobby's CAMERA (RunSettings.camera_mode); a standalone
# arena shows the whole field.
@export var follow_camera := false
@export var follow_zoom := 1.6          # how close the camera sits (2D zoom)
@export var follow_margin := 24.0       # world pixels the view may show past the field's border
@export var follow_smoothing := 8.0     # Camera2D.position_smoothing_speed
@export var edge_arrow_size := 14.0     # the off-screen pointers (edge_targets)
@export var edge_arrow_inset := 18.0    # how far inside the visible edge they sit

@export_category("Intro Camera")
# The first "3 - 2 - 1" of a trial opens on the overseeing god (the scene's
# FaceFocus marker), pans across to the field and zooms out onto the arena by GO
# (see THE INTRO SHOT).
@export var intro_zoom := 3.0
@export var intro_hold := 0.2           # seconds still on the face before the pan
@export var intro_pan_share := 0.7      # share of the countdown spent panning; the rest zooms out
@export var intro_face_screen_x := 0.75 # how far across the screen the face sits when the shot opens

@export_category("GO Drop")
# At GO the mortals fall from the sky onto their spawn points (see THE GO DROP).
# Settings > Gameplay > Intro camera turns it off with the intro shot.
@export var drop_enabled := true
@export var drop_time := 1.0            # seconds from GO to control: the fall, the landing, the settle

@export_category("Network")
@export var net_tick_rate := 10.0    # world state broadcasts per second
@export var net_state_rate := 5.0    # FAVOR snapshots per second
@export var layout_repeat := 2.0     # seconds between layout re-broadcasts
# Mortal positions ride their own stream: it is a tiny message and it is what the
# ghosts chase, so it runs far faster than the world tick above. A move of more
# than position_jump pixels (a knockback, a respawn) is sent right away instead
# of waiting for the next beat - a dropped packet must never be the reason a
# rival looks teleported, or is scored against in the wrong place.
@export var position_tick_rate := 20.0
@export var position_jump := 140.0
# How hard a ghost chases the position it was last given, and how far it may be
# behind before it is put where it belongs instead of gliding there.
@export var ghost_smoothing := 14.0
@export var ghost_snap_distance := 160.0

@export_category("FAVOR Popups")
@export var popups_enabled := true
# Small gains are gathered and shown as one popup every `popup_flush` seconds
# (a lit zone pays many times a second - one popup each would be unreadable).
@export var popup_flush := 0.5
# A change of at least this many FAVOR pops at once instead of waiting.
@export var popup_big_delta := 20
# Popups that land on the same mortal this close together merge into one (seconds).
@export var popup_merge_time := 0.3

@export_category("Solo Rivals")
# Without other players the leaderboard and the rivalry rules still need
# somebody to compare against: these stand-in mortals quietly gather FAVOR.
@export var simulate_rivals := true
@export var rival_names: PackedStringArray = PackedStringArray(["MORTAL 2", "MORTAL 3"])

@onready var field_root: ArenaField = $ArenaField
@onready var ghosts_root: Node2D = $Ghosts
@onready var popups_root: Node2D = $Popups
@onready var player: ArenaMortal = $Player
@onready var ui_layer: CanvasLayer = $UILayer
@onready var vision_mask: ColorRect = $VisionLayer/VisionMask
@onready var sun_patch_layer: CanvasLayer = get_node_or_null("Patches")
# The wash a landed hit paints over the whole screen (authored in Arena.tscn -
# this script never builds nodes on the fly).
@onready var hit_flash: ColorRect = get_node_or_null("FlashLayer/ScreenFlash")
# The shade over the world while a god speaks: the field dims, the HUD (every
# CanvasLayer, the shell's panels too) stays as bright as ever.
@onready var field_dim: ColorRect = get_node_or_null("FieldDim")
# The bottom band and its two rows (THE SCREEN'S LAYOUT).
@onready var band: PanelContainer = get_node_or_null("BandLayer/Band")
@onready var band_state: HBoxContainer = get_node_or_null("BandLayer/Band/Rows/State")
@onready var hint_label: HintStrip = get_node_or_null("BandLayer/Band/Rows/Hint")

var god: God
var rules: GodMatch
var hud: Control
var dialogue: Control
var due_menu: Control
var camera: Camera2D = null      # the follow camera (null: the whole field, world = screen)
# How much of the HUD shows (0 hidden, 1 as normal): the intro shot fades it, the
# shell reads it for its own panels and clock.
var hud_alpha := 1.0
var _edge_arrows: Control = null  # draws the off-screen pointers, on the HUD layer

# The mortal's walking field and its authored spawn (every round starts on the
# spot the designer drew).
var _field := Rect2()
var _start_position := Vector2.ZERO
var _phase := Phase.INTRO
var _trial_time := 0.0
var _countdown := 0.0
var _count_shown := -1
var _invuln: Dictionary = {}          # mortal id -> seconds of mercy left
var _blind_time := 0.0                # seconds of darkness on THIS screen (never the caster's)
var _blind_radius := 0.16
var _free_grants := 0
var _awaiting_grant: StringName = &""  # client: the favor asked of the host, not yet confirmed
var _results: Dictionary = {}
var _gain_pending: Dictionary = {}    # mortal id -> FAVOR gathered, not popped yet
var _gain_timer := 0.0
var _popup_recent: Dictionary = {}    # mortal id -> {node, delta, at}: the FAVOR popup last spawned on them
var popup_layer: CanvasLayer          # the screen-space layer every floating text lives on
var favor_popups_root: Control        # ...and its root (popups_root is the world FX root)
var callout_label: Label              # the callout's text (one pill, reused: see callout())
var _popup_stacks: Dictionary = {}    # mortal id -> Array[FavorPopup], oldest first
var _world_popups: Dictionary = {}    # FavorPopup -> the world spot it hangs over
var _callout_pill: FavorPopup
var _callout_at: Node2D = null        # the mortal it hangs over (null: screen-centred)
var _callout_left := 0.0
var _vision_fade := 1.0               # blindness mask fade-in (see Settings.reduce_flashing)
var _sun_patches: Dictionary = {}     # mortal id -> Array[float] seconds left
var _loss_boost: Dictionary = {}      # mortal id -> seconds of Sibling's Compromise: their losses cost more
# The caster behind each sun patch, kept beside the timers (aligned arrays):
var _sun_patch_sources: Dictionary = {}   # mortal id -> Array[int], caster id per _sun_patches timer (-1 = none)
var _great_pending: Dictionary = {}   # mortal id -> fractional FAVOR
var _victor_claimed: Dictionary = {}  # owner id -> true (once per trial)
var _rivalry_claimed: Dictionary = {} # owner id -> {favor id -> {victim id: true}}
var _sun_patch_rects: Array[TextureRect] = []
# The blots covering THIS screen right now. Each one owns a single rect of the
# shared patch layer that it claimed at random out of the free ones, and it
# takes itself back down when its OWN clock runs out - so a new blot never lands
# on top of one already showing, and the blot that arrived first is not the
# first to go. Entries: {index:int, left:float, favor:bool}.
var _sun_patch_slots: Array[Dictionary] = []
var _base_move_speed := 215.0
var _guidance_time := 0.0
var _movement_override_caster := -1
var _movement_override_time := 0.0
var _loss_boost_seen: Dictionary = {}  # what the host last said about boosted losses (a client's copy, for the HUD)
# Rest and Refreshed / Down to Homeland on THIS screen (see _watch_afflictions).
# A leash per rooted mortal we can see: id -> {shadow: Vector2, tether: Node2D}.
var _root_leashes: Dictionary = {}
# A root that just let go: id -> {shadow, tether, left}. The tether stays for the
# drag home, so every screen sees the mortal pulled back to it.
var _root_pulls: Dictionary = {}
var _drowsy_seen: Dictionary = {}  # mortal id -> still drowsy (so the end is announced once)
# A Little More Structure: Sidapa's rings. One entry per ring that is still
# counting down: {id, caster, at: Vector2, radius, left, total, stun}. Every
# screen draws them; the host's clock judges them.
var _structures: Array[Dictionary] = []
var _structure_nodes: Dictionary = {}  # ring id -> its Node2D on this screen
var _structure_seq := 0
var _dash_cd := 0.0
var _dash_buffered := 0.0  # seconds a too-early SPACE still waits (see dash_buffer)
# The impact currently running on THIS screen: seconds left of the field's
# shake and of the flash, plus the numbers they fade over (see _shake_screen).
var _shake_left := 0.0
var _shake_span := 0.0
var _shake_power := 1.0
var _flash_left := 0.0
var _flash_span := 0.0
var _flash_tint := Color(1, 1, 1, 1)
# The intro shot (see THE INTRO SHOT).
var _intro_camera: Camera2D = null
var _intro_played := false  # once per trial: later rounds (Bathala's) never replay it
var _intro_span := 0.0      # the shot's length: the countdown's
var _intro_left := 0.0
var _intro_hold := 0.0
var _intro_open := Vector2.ZERO     # the camera's centre when the shot opens
var _intro_pan_end := Vector2.ZERO  # ...and where the pan leaves it, over the field
# The GO drop (see THE GO DROP).
var _drop_left := 0.0       # seconds of the drop still to play: the host's clock, the host's word on a client
var _going := false         # the host's countdown has reached GO and is waiting out the drop
var _drop_waiting := false  # the mortals are held off the field until a GO that is not a trial's first
var _drop_cast: Dictionary = {}  # mortal id -> {delay, lift, landed}: who falls, when, from how high
var _drop_shaken := false
var _drop_seen := false     # this GO's drop has begun (so a late word of it cannot begin it again)

# --- multiplayer ---
var _net: Node = null
var _networked := false
var _authority := true
var _my_id := GodMatch.LOCAL_ID
var _mortal_positions: Dictionary = {}  # peer id -> Vector2
var _ghosts: Dictionary = {}            # peer id -> ghost mortal
var _net_tick := 0.0
var _state_tick := 0.0
var _position_tick := 0.0
var _position_publish := 0.0
var _last_reported_position := Vector2.INF
var _last_published_position := Vector2.INF
var _layout_age := 0.0
var _last_banner := ""
var _last_event := ""
# The host's own God's Due words, which stay on the host's screen (see _publish_arena_tick).
var _due_banner := ""
var _due_event := ""
var _dialogue_waiting := false
var _dialogue_wait_id := ""
var _dialogue_wait_time := 0.0


func _ready() -> void:
	god = Gods.by_id(god_id)
	_net = get_node_or_null("/root/Network")
	_networked = _detect_networked()
	_my_id = _detect_my_id()
	_authority = (not _networked) or multiplayer.is_server()

	rules = GodMatch.new()
	rules.name = "GodMatch"
	rules.milestone_step = due_step
	rules.authority = _authority
	add_child(rules)
	if _networked:
		rules.setup_peers(god, _peer_names(), _my_id, false)
	else:
		rules.setup(god, _mortal_name(), Array(rival_names) if simulate_rivals else [], simulate_rivals)
	rules.favor_changed.connect(_on_favor_changed)
	rules.due_earned.connect(_on_due_earned)
	rules.favor_granted.connect(_on_favor_granted)
	rules.notice.connect(_on_notice)
	rules.favor_fired.connect(_on_favor_fired)
	rules.pamana_fired.connect(_on_pamana_fired)
	rules.bato_bato_swapped.connect(_on_bato_bato_swapped)
	rules.skill_used.connect(_on_skill_used)

	hud = HUD_SCENE.instantiate()
	ui_layer.add_child(hud)
	hud.skill_pressed.connect(_use_skill)
	register_tap_panel(GodFavor.Slot.E, hud.bar_e)
	register_tap_panel(GodFavor.Slot.Q, hud.bar_q)
	if embedded:
		hud.get_node("StatsPanel").visible = false
		hud.get_node("TrialPanel").visible = false
		hud.get_node("EventLabel").visible = false
		hud.get_node("BannerLabel").visible = false

	dialogue = DIALOGUE_SCENE.instantiate()
	ui_layer.add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)

	due_menu = DUE_MENU_SCENE.instantiate()
	ui_layer.add_child(due_menu)
	due_menu.favor_chosen.connect(_on_favor_chosen)
	_build_popup_layer()

	# The spawn is authored in the scene - remember it so every round starts from
	# the drawn spot (never from arithmetic on a rect).
	_start_position = player.global_position
	_base_move_speed = player.move_speed
	_build_camera()
	_read_field()
	player.set_display_name(_mortal_name(), tag_color(_my_id))
	hud.bind(rules, god)
	hud.effect_source = local_effects
	rules.announce_gains = not embedded  # an embedded run's shell switches it on once the run's snapshot is in
	_connect_network()
	_sync_ghosts()
	_paint_bandanas()
	_collect_sun_patch_rects()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_start_intro()


func _detect_networked() -> bool:
	# A lone host plays exactly like solo - only real company switches on the
	# network code paths. A client, on the other hand, is never alone: it always
	# follows the host, so it must take the networked path whatever the roster
	# says. The solo path would fake its own mortal as LOCAL_ID, which is 1 - the
	# HOST's peer id - and the client would then mirror the host's FAVOR, name and
	# results as if they were its own.
	if _net == null or not _net.has_multiplayer_peer():
		return false
	if not multiplayer.is_server():
		return true
	return _net.players.size() > 1


func _detect_my_id() -> int:
	if _net != null and _net.has_multiplayer_peer():
		return multiplayer.get_unique_id()
	return GodMatch.LOCAL_ID


func _peer_names() -> Dictionary:
	if _net == null:
		return {}
	return _net.players.duplicate()


func _mortal_name() -> String:
	if _net != null:
		var chosen = _net.get("my_name")
		if chosen != null and str(chosen).strip_edges() != "":
			return str(chosen)
	return "MORTAL"


func _on_viewport_resized() -> void:
	# Nothing in the arena is laid out by code, so a resize only re-shapes the
	# blindness mask (and the follow camera's limits) - the field stays exactly
	# where the designer drew it.
	_fit_camera()
	_apply_vision_mask()


# --- FIELD LAYOUT -----------------------------------------------------------

func _read_field() -> void:
	# The arena scene owns the layout: the field rect is read back from the
	# border line the designer drew (ArenaField.authored_rect), the favor zones,
	# the clones and the mortal keep the positions and sizes they were authored
	# with, and only the rules need a number out of it - the mortal's walking
	# bounds - so every player reads the same authored screen.
	_field = field_root.authored_rect()
	var tint: Color = god.color if god != null else Color.WHITE
	field_root.apply_tint(tint)
	player.bounds = _field
	player.ring_color = UITokens.god_accent(god)
	_fit_camera()
	_apply_vision_mask()
	collect_units()
	if _authority:
		_publish_layout()


# --- FOR ARENAS THAT EXTEND THIS --------------------------------------------
# The hooks a god's arena overrides. All of them are optional: an arena that
# leaves them alone is a walking arena that already has the clock, the dialogue,
# the mortals, the popups and the network.

# Build or refresh the arena's own scene nodes (zones, clones, goals...). Called
# once at start-up and again whenever a layout arrives from the host, so it must
# be safe to call any number of times and must never move authored art.
func collect_units() -> void:
	pass


# One frame of this god's rules, run by the HOST only (a client mirrors the host
# instead). The clock, the mercy seconds, the popups and the end of the trial
# are already handled - this is only what the god's game itself does.
func arena_rules_tick(_delta: float) -> void:
	pass


# Put the arena's own units back to their authored start, while the mortals wait
# through the "3 - 2 - 1".
func arena_round_reset() -> void:
	pass


# The extra numbers the host sends with the layout (which zone is lit...) and
# with every world tick (where the clones walked...), plus the matching readers.
# Both are plain Dictionaries: return {} / ignore what you do not use.
func arena_layout_fields() -> Dictionary:
	return {}


func arena_read_layout(_layout: Dictionary) -> void:
	pass


func arena_tick_fields() -> Dictionary:
	return {}


func arena_read_tick(_state: Dictionary) -> void:
	pass


# A multiplier on this screen's own mortal's walk, on top of the favors and
# Pamana (_update_movement_favors). Each screen applies it to its own mortal, so
# it needs no sync. 1.0: no change.
func arena_speed_scale() -> float:
	return 1.0


func shares_mortal_positions() -> bool:
	return true


# True for a game the gods play with everyone in their OWN copy of the arena
# (Arnis: one duelist per mortal, one mortal per screen): no rival is drawn on
# anybody's field and no position travels - only FAVOR and the favors do. The
# base reads this to keep the field clear and to skip every ghost.
func separate_players() -> bool:
	return false


# --- MULTIPLAYER: layout sync -----------------------------------------------

func _publish_layout() -> void:
	if not _networked or not _authority or _net == null:
		return
	var layout := {"field": _field, "scene": scene_token()}
	layout.merge(arena_layout_fields(), true)
	_net.publish_arena_layout(layout)


func _apply_layout(layout: Dictionary) -> void:
	# Clients play on the host's field so everybody shares the same coordinates,
	# and on the host's arena state. Both read the same authored scene, so the
	# art, the paths and the mortal are already right - only the host's numbers
	# change.
	_field = layout.get("field", _field)
	var tint: Color = god.color if god != null else Color.WHITE
	field_root.apply_tint(tint)
	player.bounds = _field
	_fit_camera()
	collect_units()
	arena_read_layout(layout)


# --- FLOW -------------------------------------------------------------------

func _start_intro() -> void:
	_phase = Phase.INTRO
	player.set_lock(true)
	# A god introduces itself in full the FIRST time it hosts a trial. When the
	# run comes back around (or when the shell hands the field over), only the
	# short "take your place" line is needed - the hand-over itself was already
	# spoken by the god that just closed.
	var lines := _speech(god, god.intro_lines, god.intro_voices) if first_visit else _speech(god, [opening_call()])
	dialogue.show_lines(lines, god.portrait if god.portrait != null else god.icon)


# The one line a god says when it calls a trial it has already introduced.
func opening_call() -> String:
	if not god.intro_lines.is_empty():
		return "Take your place. %s watches again." % god.display_name
	return "%s calls the next trial." % god.display_name


func _start_countdown() -> void:
	_phase = Phase.COUNTDOWN
	_countdown = countdown_time
	_count_shown = -1
	_reset_drop()
	_clear_roots()
	_clear_structures()
	player.set_lock(true)
	# The full round is already on the clock while the mortals wait through the
	# 3 - 2 - 1, and the host broadcasts it, so every screen shows the round
	# length here.
	_trial_time = trial_time
	trial_time_changed.emit(_trial_time)
	hud.set_time_left(_trial_time)
	# Back to the spot the designer drew the mortal on, and the arena's own units
	# back to their authored start, so every round begins the same way.
	player.global_position = _start_position
	if camera != null:
		camera.reset_smoothing()  # a new round cuts to the spawn, it does not pan there
	arena_round_reset()
	_reset_screen_impact()  # and the screen itself starts the round at rest
	_begin_intro_shot()


# GO. With the drop the mortals fall for drop_time first - still locked, the clock
# and the rules held, the phase still the countdown's, so nothing that waits for
# PLAYING runs - and _start_trial opens the round when they have landed.
func _go() -> void:
	if not begin_drop():
		_start_trial()
		return
	_going = true
	_end_intro_shot()  # the view is the normal one from GO, whatever is left of the shot
	_show_banner("GO!", god.color, 1.0)


# `show_go` is false when the drop already showed the banner.
func _start_trial(show_go := true) -> void:
	_phase = Phase.PLAYING
	_going = false
	_reset_drop()
	_end_intro_shot()  # GO is never late: whatever is left of the shot is cut
	_trial_time = trial_time
	trial_time_changed.emit(_trial_time)
	_invuln.clear()
	_gain_pending.clear()
	_gain_timer = 0.0
	set_mortal_invuln(_my_id, spawn_immunity)
	_blind_time = 0.0
	_sun_patches.clear()
	_sun_patch_sources.clear()
	clear_sun_patches()
	_loss_boost.clear()
	_great_pending.clear()
	_victor_claimed.clear()
	_rivalry_claimed.clear()
	# Everyone is back at the start: the first position of the round is a jump,
	# so it goes out at once instead of after a beat of the stale spawn point.
	_last_reported_position = Vector2.INF
	_last_published_position = Vector2.INF
	_position_tick = 0.0
	_position_publish = 0.0
	_refresh_sun_patches()
	player.set_lock(false)
	rules.trial_active = true
	if _authority:
		rules.begin_trial()  # First Light pays whoever starts the trial in last place
	if show_go:
		_show_banner("GO!", god.color, 1.0)
	hud.set_time_left(_trial_time)


func _process(delta: float) -> void:
	_tick_drop(delta)
	_tick_flow(delta)
	_tick_world(delta)


# The flow of a trial: the dialogue handshake and the phase clock. A screen that
# runs no trial (the Playground) ticks only the world below.
func _tick_flow(delta: float) -> void:
	if _authority and _networked and not _dialogue_waiting:
		var waiting_kind := "intro" if _phase == Phase.INTRO else "results" if _phase == Phase.RESULTS else ""
		var waiting_id := _dialogue_token(waiting_kind) if waiting_kind != "" else ""
		if waiting_id != "" and _net.dialogue_finished_count(waiting_id) > 0:
			_dialogue_waiting = true
			_dialogue_wait_id = waiting_id
			_dialogue_wait_time = 0.0
	if _dialogue_waiting:
		_dialogue_wait_time += delta
		if _authority and (_dialogue_wait_time >= DIALOGUE_TIMEOUT or _dialogue_all_ready()):
			_release_dialogue()
	match _phase:
		Phase.COUNTDOWN:
			# The host counts; a client never runs a clock of its own.
			if _authority and _going:
				if not drop_active():
					_start_trial(false)  # they have landed: the round, the clock and the rules begin
			elif _authority:
				_countdown -= delta
				var shown := int(ceil(maxf(0.0, _countdown)))
				if shown != _count_shown:
					_count_shown = shown
					if shown > 0:
						_show_banner(str(shown), god.color, 1.0)
				if _countdown <= 0.0:
					_go()
		Phase.PLAYING:
			if _authority:
				_tick_trial(delta)
			else:
				_client_tick(delta)
	# The host is the clock: it broadcasts the round it just advanced - phase,
	# seconds, where the mortals are, where the arena's own units walked - so
	# every client shows the same second and the same world.


# What every screen plays every frame, whatever the phase: the host's tick, the
# popups, the arena's own clocks, the ghosts, the movement favors and the HUD.
func _tick_world(delta: float) -> void:
	if _authority and _networked and _phase != Phase.INTRO:
		_publish_net_tick(delta)
	_flush_favor_popups(delta)
	_tick_sun_patch_slots(delta)
	_apply_blindness(delta)
	_move_ghosts(delta)
	_tick_structures(delta)
	_update_movement_favors(delta)
	_watch_afflictions(delta)
	_watch_local_pamana()
	_tick_shake(delta)
	_tick_flash(delta)
	_tick_intro_shot(delta)
	_tick_field_dim()
	_tick_band()
	_dash_cd = maxf(0.0, _dash_cd - delta)
	if _dash_buffered > 0.0:
		_dash_buffered = maxf(0.0, _dash_buffered - delta)
		if try_dash():  # every refusal still applies: it only fires once one would
			_dash_buffered = 0.0


func _tick_trial(delta: float) -> void:
	# The shared part of one round: the clock runs down, the mercy seconds burn
	# off, and the arena's own rules get their frame. Not while the mortals are still
	# falling from the sky at a GO (a later round's, Bathala's): nobody loses playing time.
	if drop_active():
		return
	_trial_time -= delta
	rules.time_left = _trial_time  # Panahon ng Anihan's harvest window reads it
	trial_time_changed.emit(_trial_time)
	hud.set_time_left(_trial_time)
	_tick_invuln(delta)
	_tick_sun_favors(delta)
	arena_rules_tick(delta)
	if _trial_time <= 0.0:
		_end_trial()


func _client_tick(delta: float) -> void:
	# Clients only report where their mortal is - the host keeps score.
	if not shares_mortal_positions() or _net == null or not _net.has_multiplayer_peer():
		return
	_position_tick -= delta
	var here := player.global_position
	# A knockback or a respawn must not wait for the next beat: a jump is sent
	# straight away, so a lost packet can never stretch a shove into a teleport.
	var jumped := _last_reported_position == Vector2.INF or here.distance_to(_last_reported_position) >= position_jump
	if _position_tick > 0.0 and not jumped:
		return
	_position_tick = 1.0 / maxf(1.0, position_tick_rate)
	_last_reported_position = here
	_net.rpc_id(1, "report_mortal_position", here)


func _tick_invuln(delta: float) -> void:
	for id in _invuln.keys():
		_invuln[id] = maxf(0.0, float(_invuln[id]) - delta)


func _publish_net_tick(delta: float) -> void:
	if not _networked or _net == null:
		return
	_layout_age += delta
	if _layout_age >= layout_repeat:
		_layout_age = 0.0
		_publish_layout()
	_net_tick -= delta
	if _net_tick <= 0.0:
		_net_tick = 1.0 / net_tick_rate
		_publish_arena_tick()
	_publish_positions(delta)
	_state_tick -= delta
	if _state_tick <= 0.0:
		_state_tick = 1.0 / net_state_rate
		_publish_god_state()


# The fast position stream: the host collects what every client reported and
# sends the whole roster back on its own, much quicker than the world tick. This
# is what keeps a rival's ghost - and the host's own scoring - on the mark.
func _publish_positions(delta: float) -> void:
	if _net == null or not _authority or not shares_mortal_positions():
		return
	_position_publish -= delta
	var here := player.global_position
	var jumped := _last_published_position == Vector2.INF or here.distance_to(_last_published_position) >= position_jump
	if _position_publish > 0.0 and not jumped:
		return
	_position_publish = 1.0 / maxf(1.0, position_tick_rate)
	_last_published_position = here
	_mortal_positions[_my_id] = here
	var reported: Dictionary = _net.mortal_positions
	for id in reported.keys():
		_mortal_positions[int(id)] = reported[id]
	_net.publish_mortal_positions(_mortal_positions)


# --- MORTALS / SCORING ------------------------------------------------------

# Where a mortal stands, as far as this peer knows. Vector2.INF when it has
# never been reported.
func mortal_position(mortal_id: int) -> Vector2:
	if mortal_id == _my_id:
		return player.global_position
	return _mortal_positions.get(mortal_id, Vector2.INF)


# Every mortal the host scores: us plus every remote peer whose position is
# known. Solo: just us (the simulated rivals are not on the field).
func mortal_entries() -> Array:
	var entries: Array = []
	for id in rules.mortals.keys():
		var position := mortal_position(int(id))
		if position == Vector2.INF:
			continue
		entries.append({"id": int(id), "pos": position})
	return entries


# A line a trial puts in a player's panel on the shell's left strip (yours and every
# rival's), or {} for none: {"text": String, "tint": Color}. Game reads it each frame
# for every mortal.
func panel_row(_mortal_id: int) -> Dictionary:
	return {}


# A small line a trial puts at the top of the rivals' column ("" for none).
func strip_note() -> String:
	return ""


func mortal_label(mortal_id: int) -> String:
	var mortal := rules.mortal(mortal_id)
	return mortal.display_name if mortal != null else "Mortal"


# FAVOR earned: the arena's only way in (a lit zone, a god's gift, a bonus).
# Everything else follows from it - the HUD total, the God's Due milestones, the
# popup, the mirror to the other players.
func bank_favor(amount: int, reason: String, mortal_id := -1) -> int:
	if rules == null or amount == 0:
		return 0
	return rules.add_favor(amount, reason, mortal_id)


# FAVOR taken away. The amount actually lost comes back (the rules cap it at
# what the mortal holds, and a shield - loss_immunity - takes nothing at all).
# `drain` marks a loss that ticks a little at a time (GodMatch.lose_favor).
func lose_favor(amount: int, reason: String, mortal_id := -1, drain := false) -> int:
	if rules == null or amount <= 0:
		return 0
	var target_id := rules.local_id if mortal_id < 0 else mortal_id
	var adjusted := amount
	if float(_loss_boost.get(target_id, 0.0)) > 0.0:
		adjusted = int(round(float(amount) * (1.0 + loss_boost_share())))
	return rules.lose_favor(adjusted, reason, target_id, drain)


# How much larger a FAVOR loss gets while Apolaki's sun patches mark a mortal.
func loss_boost_share() -> float:
	var sun := Gods.favor_by_id(&"siblings_compromise_sun")
	return sun.param("loss_boost", 0.1) if sun != null else 0.1


# The arena's one way to say "this mortal just earned (or lost) FAVOR", for the
# games a peer resolves on its own: a private duel (Arnis) or a slipper that
# landed (Tumbang Preso). Only the host ever changes a mortal's FAVOR, so a
# client asks it and the next snapshot brings the number back.
func score_favor(amount: int, reason: String) -> void:
	if amount == 0:
		return
	if _authority:
		if amount > 0:
			bank_favor(amount, reason, _my_id)
		else:
			lose_favor(-amount, reason, _my_id)
		_publish_god_state()
		return
	if _net != null and _net.has_multiplayer_peer():
		_net.rpc_id(1, "request_arena_score", amount, reason, scene_token())


func _on_arena_score_requested(peer_id: int, amount: int, reason: String) -> void:
	if not _authority:
		return
	if amount > 0:
		bank_favor(amount, reason, peer_id)
	else:
		lose_favor(-amount, reason, peer_id)


# The arena's one way to say "my mortal is stunned now", for the games a peer
# judges on its own (Piko's head countdown running out). Every stun goes through
# the rules, so Sidapa's favors see it wherever it came from.
func request_stun(seconds: float, source_id := -1) -> float:
	if seconds <= 0.0:
		return 0.0
	if _authority:
		var length := rules.stun_mortal(_my_id, seconds, source_id)
		if length > 0.0:
			_publish_god_state()
		return length
	var predicted := _predict_stun(seconds)
	if predicted > 0.0 and _net != null and _net.has_multiplayer_peer():
		_net.rpc_id(1, "request_arena_stun", seconds, source_id, scene_token())
	return predicted


# What the client can work out before the host says it: its own cleanse and
# departure, nothing that depends on another mortal's window.
func _predict_stun(seconds: float) -> float:
	var m := rules.local()
	if m == null:
		return seconds
	var cleanse: GodFavor = m.favor_by_id(&"first_cleanse")
	if cleanse != null and not m.first_cleanse_used:
		return 0.0
	var departure: GodFavor = m.favor_by_id(&"departure_is_not_now")
	if departure != null:
		seconds *= 1.0 - departure.param("stun_reduction", 0.15)
	return seconds


func _on_arena_stun_requested(peer_id: int, seconds: float, source_id: int) -> void:
	if not _authority:
		return
	var length := rules.stun_mortal(peer_id, seconds, source_id)
	if length > 0.0:
		announce_stun(peer_id, length)
	_publish_god_state()


# Mercy seconds: a mortal that was just hit cannot be hit again until they run
# out. Whatever hit it decides for how long.
func set_mortal_invuln(mortal_id: int, seconds: float) -> void:
	_invuln[mortal_id] = maxf(float(_invuln.get(mortal_id, 0.0)), seconds)


func is_mortal_invulnerable(mortal_id: int) -> bool:
	return float(_invuln.get(mortal_id, 0.0)) > 0.0


# --- KNOCKBACK --------------------------------------------------------------

# Shove a mortal away from whatever just hit it (the thing that hit it stands at
# `from_position`). Leave `stun`/`force` at 0 to use the arena's exported
# knock_stun / knock_force.
# `impact` asks for the screen answer as well: the field shakes and the screen
# flashes on the VICTIM's screen - here when that is ours, or across the wire
# in _on_arena_hit_received when the host scores somebody else's mortal.
#
# Our own mortal is ours to move, so this is where it is shoved. A rival's
# mortal is simulated on the rival's machine: the host only reports the hit and
# the owner does the shoving (_on_arena_hit_received below), so a client feels
# every hit the host scores, not just the ones it scored on itself.
func knock_mortal(mortal_id: int, from_position: Vector2, stun := 0.0, force := 0.0, impact := false) -> void:
	if mortal_id == _my_id:
		var shove := player.global_position - from_position
		if shove.length() < 0.01:
			shove = Vector2.LEFT
		var seconds := knock_stun if stun <= 0.0 else stun
		if _authority:
			# Every stun is announced to the rules: Sidapa's favors watch them.
			seconds = rules.stun_mortal(mortal_id, seconds)
		announce_hit(mortal_id, player.global_position, shove, seconds)
		_apply_knockback(shove, seconds, force, seconds <= 0.0)
		if impact:
			_impact_hit()
		return
	if not (_authority and _networked and _net != null):
		return
	var position := mortal_position(mortal_id)
	if position == Vector2.INF:
		return
	var direction := position - from_position
	if direction.length() < 0.01:
		direction = Vector2.LEFT
	var remote_seconds := knock_stun if stun <= 0.0 else stun
	remote_seconds = rules.stun_mortal(mortal_id, remote_seconds) if _authority else remote_seconds
	announce_hit(mortal_id, position, direction, remote_seconds)
	_net.send_arena_hit(mortal_id, {
		"direction": direction.normalized(),
		"stun": remote_seconds,
		"no_stun": remote_seconds <= 0.0,
		"force": knock_force if force <= 0.0 else force,
		"impact": impact,
	})


func _apply_knockback(direction: Vector2, stun := 0.0, force := 0.0, no_stun := false) -> void:
	if player == null or not is_instance_valid(player):
		return
	if no_stun:
		player.shove(direction, knock_force if force <= 0.0 else force)
		return
	player.hit(direction, knock_stun if stun <= 0.0 else stun, knock_force if force <= 0.0 else force)


func _on_arena_hit_received(hit: Dictionary) -> void:
	if _authority:
		return
	# The host decided OUR mortal was hit: shove it here, where it is simulated.
	# The direction comes with the hit; the FAVOR that was taken arrives with the
	# next FAVOR snapshot, like every other change.
	var direction: Vector2 = hit.get("direction", Vector2.LEFT)
	if direction.length() < 0.01:
		direction = Vector2.LEFT
	_apply_knockback(direction, float(hit.get("stun", 0.0)), float(hit.get("force", 0.0)), bool(hit.get("no_stun", false)))
	# The host also asked for the screen answer (knock_mortal's `impact` flag):
	# this is where a hit scored on OUR mortal shakes OUR field.
	if bool(hit.get("impact", false)):
		_impact_hit()


# --- THE FEEL OF A HIT ----------------------------------------------------------
# The weight a landed blow has on the screen it lands on: the FIELD jumps - the
# HUD never moves, so its labels stay readable (the same rule as Hanan's Over the
# Moon) - and a wash flashes over the field (never the HUD). Both comfort options in Settings
# hold: screen shake off means no shake at all, reduce flashing halves the wash
# so it reads as a wash, not a strobe. Every arena owns this - Apolaki calls the
# two entry points directly for each of the duel's four outcomes, and a
# knockback flagged `impact` plays it wherever the victim's screen is.

# Start a shake of `seconds` at `power` x shake_pixels. A new impact may extend
# the one already running, never cut it short.
func _shake_screen(seconds: float, power := 1.0) -> void:
	if seconds <= 0.0 or not screen_shake_allowed():
		return
	_shake_left = maxf(_shake_left, seconds)
	_shake_span = maxf(_shake_span, _shake_left)
	_shake_power = maxf(_shake_power, power)


# Every frame of the shake: a random offset that dies down over its span and
# settles exactly back on rest (so nothing is left drifting afterwards).
func _tick_shake(delta: float) -> void:
	if field_root == null:
		return
	if _shake_left <= 0.0:
		if field_root.position != Vector2.ZERO:
			field_root.position = Vector2.ZERO
		return
	_shake_left = maxf(0.0, _shake_left - delta)
	var ratio := 1.0 if _shake_span <= 0.0 else clampf(_shake_left / _shake_span, 0.0, 1.0)
	var amplitude := shake_pixels * _shake_power * ratio
	field_root.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amplitude
	if _shake_left <= 0.0:
		field_root.position = Vector2.ZERO
		_shake_span = 0.0
		_shake_power = 1.0


# Flash the screen in `tint`, peaking at `peak` alpha and fading over flash_time.
# Under reduce flashing the peak is halved, so it reads as a wash, not a strobe.
func _flash_screen(tint: Color, peak: float) -> void:
	if peak <= 0.0:
		return
	var alpha := peak * (0.5 if reduce_flashing() else 1.0)
	_flash_tint = Color(tint.r, tint.g, tint.b, alpha)
	_flash_left = flash_time
	_flash_span = flash_time
	if hit_flash != null:
		hit_flash.color = _flash_tint
		hit_flash.visible = true


# The world dims while a god speaks (the dialogue box itself sits on its own layer,
# above everything; the HUD is never dimmed).
func _tick_field_dim() -> void:
	if field_dim != null:
		field_dim.visible = dialogue != null and dialogue.is_active()


# The bottom band steps aside for the dialogue box (both sit at the bottom) and is
# see-through while our mortal's feet are under it, so the field it covers stays
# readable.
func _tick_band() -> void:
	if band == null:
		return
	band.visible = not dialogue.is_active()
	var under := band.get_global_rect().grow(8.0).has_point(player.get_global_transform_with_canvas().origin)
	band.modulate.a = (BAND_SEE_THROUGH if under else 1.0) * hud_alpha


func _tick_flash(delta: float) -> void:
	if hit_flash == null:
		return
	if _flash_left <= 0.0:
		if hit_flash.visible:
			hit_flash.visible = false
		return
	_flash_left = maxf(0.0, _flash_left - delta)
	var ratio := 1.0 if _flash_span <= 0.0 else clampf(_flash_left / _flash_span, 0.0, 1.0)
	hit_flash.color = Color(_flash_tint.r, _flash_tint.g, _flash_tint.b, _flash_tint.a * ratio)
	if _flash_left <= 0.0:
		hit_flash.visible = false


# The generic "you were hit" answer: what a knockback flagged `impact` plays on
# the victim's screen. The same weight as taking Apolaki's swing - a hard shake
# and a red wash.
func _impact_hit() -> void:
	_shake_screen(impact_shake_time, 1.25)
	_flash_screen(Color(1.0, 0.32, 0.28), 0.4)


# A new round starts with the screen at rest - no shake mid-flight and no wash
# left over from the last blow. Called from the round flow and by any arena that
# resets itself by hand.
func _reset_screen_impact() -> void:
	_shake_left = 0.0
	_shake_span = 0.0
	_shake_power = 1.0
	_flash_left = 0.0
	_flash_span = 0.0
	if field_root != null:
		field_root.position = Vector2.ZERO
	if hit_flash != null:
		hit_flash.visible = false


# --- FAVOR POPUPS -----------------------------------------------------------

func _build_popup_layer() -> void:
	popup_layer = CanvasLayer.new()
	popup_layer.name = "PopupLayer"
	popup_layer.layer = POPUP_LAYER
	add_child(popup_layer)  # after Patches in the tree: drawn over them on the same layer
	favor_popups_root = Control.new()
	favor_popups_root.name = "FavorPopups"
	favor_popups_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	favor_popups_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_layer.add_child(favor_popups_root)
	_callout_pill = POPUP_SCENE.instantiate()
	_callout_pill.name = "Callout"
	_callout_pill.keep = true
	favor_popups_root.add_child(_callout_pill)
	_callout_pill.hide_now()
	callout_label = _callout_pill.number_label


func _new_popup() -> FavorPopup:
	var popup: FavorPopup = POPUP_SCENE.instantiate()
	favor_popups_root.add_child(popup)
	favor_popups_root.move_child(_callout_pill, -1)  # the callout stays on top
	return popup


# A word or number hanging over a world spot (no stack of its own).
func spawn_popup(text: String, tint: Color, origin: Vector2) -> FavorPopup:
	if favor_popups_root == null or origin == Vector2.INF:
		return null
	var popup := _new_popup()
	popup.show_text(text, tint, "", false, reduce_flashing())
	_world_popups[popup] = origin
	return popup


# A word over a mortal ("TAGGED", "STUNNED"), in its stack like a FAVOR popup.
func mortal_popup(mortal_id: int, text: String, tint: Color, reason := "") -> FavorPopup:
	if favor_popups_root == null:
		return null
	var popup := _new_popup()
	popup.show_text(text, tint, reason, false, reduce_flashing())
	_push_popup(mortal_id, popup)
	return popup


# A god's E icon over the mortal who cast it, in the same stack as their FAVOR popups.
func cast_popup(mortal_id: int, icon_texture: Texture2D, tint: Color) -> FavorPopup:
	if favor_popups_root == null or icon_texture == null:
		return null
	var popup := _new_popup()
	popup.show_icon(icon_texture, tint, reduce_flashing())
	_push_popup(mortal_id, popup)
	return popup


# "+250 FAVOR" over a mortal - JADE - or "-120 FAVOR" in EMBER when N is negative;
# `reason`, when given, on the line under it. 250 or more is drawn big.
#
# Two popups landing on the same mortal within popup_merge_time are one popup: a
# second gain (or loss) adds its number to the one already up (a small bump shows
# it moved). A change the other way round is a row of its own in the stack.
func favor_popup(mortal_id: int, delta: int, reason := "") -> FavorPopup:
	if delta == 0 or favor_popups_root == null:
		return null
	var now := Time.get_ticks_msec()
	var tint := POPUP_GAIN_COLOR if delta > 0 else POPUP_LOSS_COLOR
	var recent: Dictionary = _popup_recent.get(mortal_id, {})
	if not recent.is_empty() and is_instance_valid(recent["node"]) and not (recent["node"] as FavorPopup).is_going() \
			and now - int(recent["at"]) <= int(popup_merge_time * 1000.0) and signi(int(recent["delta"])) == signi(delta):
		recent["delta"] = int(recent["delta"]) + delta
		var merged: FavorPopup = recent["node"]
		merged.relabel(_favor_number(int(recent["delta"])), tint)
		return merged
	var popup := _new_popup()
	popup.show_text(_favor_number(delta), tint, reason, absi(delta) >= POPUP_BIG_MOMENT, reduce_flashing(), delta < 0)
	_push_popup(mortal_id, popup)
	_popup_recent[mortal_id] = {"node": popup, "delta": delta, "at": now}
	return popup


func _favor_number(delta: int) -> String:
	return "%s%d FAVOR" % ["+" if delta > 0 else "", delta]


# Into `mortal_id`'s stack (newest last): a rival's at RIVAL_POPUP_LOOK, and a
# stack past POPUP_MAX fades its oldest out early.
func _push_popup(mortal_id: int, popup: FavorPopup) -> void:
	if mortal_id != _my_id:
		popup.base_scale = RIVAL_POPUP_LOOK
		popup.base_alpha = RIVAL_POPUP_LOOK
	var stack: Array = _popup_stacks.get(mortal_id, [])
	stack.append(popup)
	_popup_stacks[mortal_id] = stack
	var live := stack.filter(func(each) -> bool: return is_instance_valid(each) and not each.is_going())
	if live.size() > POPUP_MAX:
		(live[0] as FavorPopup).retire()


# A trial's callout ("READY...", "TAYA!", "TRIP!") in the same pill at 24 px, over
# `at` (our own mortal when null) above its popups - or screen-centred near the top
# with `centered`. One at a time: the same text again only keeps it up, a new text
# repaints it in place; seconds <= 0 (or no text) lets it go.
func callout(text: String, tint: Color, seconds: float, at: Node2D = null, centered := false) -> void:
	if _callout_pill == null:
		return
	if text == "" or seconds <= 0.0:
		_callout_left = 0.0
		if _callout_pill.visible and not _callout_pill.is_going():
			_callout_pill.expire()
		return
	_callout_at = null if centered else (at if at != null else player)
	_callout_left = seconds
	if _callout_pill.visible and not _callout_pill.is_going():
		if _callout_pill.number_text() != text:
			_callout_pill.repaint(text, tint)
		return
	_callout_pill.show_text(text, tint, "", true, reduce_flashing())
	_callout_pill.persistent = true


# Where a mortal's popups come off: our own mortal's head, or the ghost of a
# rival. Vector2.INF when we do not know where that mortal is.
func popup_origin(mortal_id: int) -> Vector2:
	var body := popup_body(mortal_id)
	if body != null:
		return body.global_position + POPUP_OFFSET
	var known := mortal_position(mortal_id)
	return Vector2.INF if known == Vector2.INF else known + POPUP_OFFSET


# The body a mortal's popups hang over: ours, a rival's ghost, or a solo bot.
func popup_body(mortal_id: int) -> Node2D:
	if mortal_id == _my_id:
		return player
	if _ghosts.has(mortal_id) and is_instance_valid(_ghosts[mortal_id]):
		return _ghosts[mortal_id]
	var bots = get("_bots")
	if bots is Dictionary and bots.has(mortal_id) and is_instance_valid(bots[mortal_id]):
		return bots[mortal_id]
	return null


# The screen point just above a mortal's name tag (Vector2.INF: unknown).
func _popup_head(mortal_id: int) -> Vector2:
	var body := popup_body(mortal_id)
	if body == null:
		var known := popup_origin(mortal_id)
		return Vector2.INF if known == Vector2.INF else get_viewport().get_canvas_transform() * known
	var at := body.get_global_transform_with_canvas().origin
	var tag = body.get("name_tag")
	var top := at.y - 52.0
	if tag is Control and (tag as Control).is_visible_in_tree():
		top = minf(top, (tag as Control).get_global_transform_with_canvas().origin.y)
	return Vector2(at.x, top - POPUP_HEAD_GAP)


# Every frame: each stack over its mortal (newest at the bottom, the older ones
# pushed up by their real height), the world popups over their spots, the callout
# above its mortal's stack - all inside the screen, clear of the left strip and the
# bottom band.
func _layout_popups(delta: float) -> void:
	if favor_popups_root == null:
		return
	var view := get_viewport_rect().size
	var low := view.y
	if band != null and band.is_visible_in_tree():
		low = minf(low, band.get_global_rect().position.y)
	var tops := {}
	for id in _popup_stacks.keys():
		var stack: Array = (_popup_stacks[id] as Array).filter(func(each) -> bool: return is_instance_valid(each))
		if stack.is_empty():
			_popup_stacks.erase(id)
			continue
		_popup_stacks[id] = stack
		var head := _popup_head(int(id))
		if head == Vector2.INF:
			continue
		var total := 0.0
		for popup in stack:
			total += (popup as FavorPopup).stack_height() + POPUP_GAP
		var y := clampf(head.y, 4.0 + total, low - 4.0)
		for index in range(stack.size() - 1, -1, -1):
			var popup: FavorPopup = stack[index]
			popup.place(Vector2(_popup_x(head.x, popup, view), y))
			y -= popup.stack_height() + POPUP_GAP
		tops[int(id)] = y
	for popup in _world_popups.keys():
		if not is_instance_valid(popup):
			_world_popups.erase(popup)
			continue
		var spot: Vector2 = get_viewport().get_canvas_transform() * (_world_popups[popup] as Vector2)
		popup.place(Vector2(_popup_x(spot.x, popup, view), clampf(spot.y, 4.0 + popup.stack_height(), low - 4.0)))
	if _callout_pill != null and _callout_pill.visible:
		if _callout_left > 0.0:
			_callout_left -= delta
			if _callout_left <= 0.0:
				_callout_pill.expire()
		var spot := Vector2((view.x + UI_STRIP_WIDTH) * 0.5, CALLOUT_TOP)
		if _callout_at != null and is_instance_valid(_callout_at):
			var owner_id := _my_id if _callout_at == player else -1
			for id in _popup_stacks.keys():
				if popup_body(int(id)) == _callout_at:
					owner_id = int(id)
			var head := _popup_head(owner_id)
			if head == Vector2.INF:
				var at := _callout_at.get_global_transform_with_canvas().origin
				head = Vector2(at.x, at.y - 56.0)
			spot = Vector2(head.x, float(tops.get(owner_id, head.y)))
		var x := _popup_x(spot.x, _callout_pill, view)
		var avoid := callout_keep_out()
		var half := _callout_pill.size.x * 0.5
		if avoid.has_area() and x + half > avoid.position.x and x - half < avoid.end.x and spot.y > avoid.position.y:
			spot.y = avoid.position.y - 2.0  # (Hanan's bar: the callout sits above it)
		spot.y = clampf(spot.y, 4.0 + _callout_pill.stack_height(), low - 4.0)
		_callout_pill.place(Vector2(x, spot.y))


# A screen rect the callout must sit above (a trial's own gauge); none by default.
func callout_keep_out() -> Rect2:
	return Rect2()


# A popup's centre x, nudged inside the screen and clear of the left strip.
func _popup_x(x: float, popup: FavorPopup, view: Vector2) -> float:
	var half := popup.size.x * popup.base_scale * 0.5
	return clampf(x, UI_STRIP_WIDTH + 4.0 + half, maxf(UI_STRIP_WIDTH + 4.0 + half, view.x - 4.0 - half))


# Small gains are gathered and shown as one popup: a lit zone pays many times a
# second, so one popup per credit would be unreadable. Losses and big gains
# never wait (see _on_favor_changed).
func _flush_favor_popups(delta: float) -> void:
	_layout_popups(delta)  # (every arena's frame comes through here, the rest's too)
	if not popups_enabled or _gain_pending.is_empty():
		return
	_gain_timer -= delta
	if _gain_timer > 0.0:
		return
	_gain_timer = popup_flush
	for id in _gain_pending.keys():
		var gained := int(_gain_pending[id])
		_gain_pending.erase(id)
		if gained != 0:
			favor_popup(int(id), gained)


# --- DIALOGUE / RESULTS -----------------------------------------------------

func _speech(speaker: God, lines: Array, voices: Array = []) -> Array:
	var out: Array = []
	var beside: Texture2D = null
	for i in lines.size():
		var text := str(lines[i])
		# "[Bathala looks toward Ines.]" is a stage direction, never shown: from here
		# on Ines's small portrait stands beside the speaker's photo. Any other
		# direction (e.g. [FADE TO SCOREBOARD.]) is staged by the shell, not here.
		if text.begins_with("[") and text.ends_with("]"):
			if text.contains("Ines"):
				beside = Cutscene.placeholder(Cutscene.NEUTRAL_SPEAKERS["INES"])
			continue
		var entry := speaker.entry_for(text)
		if beside != null:
			entry["beside"] = beside
		if i < voices.size() and voices[i] is AudioStream:
			entry["voice"] = voices[i]
		out.append(entry)
	return out


func _speech_transition(speaker: God, next_id: StringName, next_name: String) -> Array:
	return _speech(speaker, speaker.transition_to(next_id, next_name), speaker.transition_voices_for(next_id))


func _on_dialogue_finished() -> void:
	match _phase:
		Phase.INTRO:
			_wait_for_dialogue("intro")
		Phase.RESULTS:
			_wait_for_dialogue("results")
		_:
			pass


func _dialogue_token(kind: String) -> String:
	return "%s_%s" % [dialogue_prefix, kind]


func _wait_for_dialogue(kind: String) -> void:
	var token := _dialogue_token(kind)
	var already_waiting := _dialogue_waiting and _dialogue_wait_id == token
	_dialogue_wait_id = token
	_dialogue_waiting = true
	if not already_waiting:
		_dialogue_wait_time = 0.0
	if not _networked:
		_release_dialogue()
		return
	_net.report_dialogue_finished(_dialogue_wait_id)


func _dialogue_all_ready() -> bool:
	return _net != null and _net.dialogue_finished_count(_dialogue_wait_id) >= _net.players.size()


func _release_dialogue() -> void:
	if not _dialogue_waiting:
		return
	_dialogue_waiting = false
	if _authority and _networked:
		_net.release_dialogue(_dialogue_wait_id)
		return
	_continue_dialogue()


func _on_dialogue_released(dialogue_id: String) -> void:
	if dialogue_id != _dialogue_wait_id:
		return
	_dialogue_waiting = false
	_continue_dialogue()


func _continue_dialogue() -> void:
	if _dialogue_wait_id.ends_with("_intro"):
		if _authority:
			_start_countdown()
		else:
			# A client runs no countdown of its own: it waits for the host's
			# ticks to walk it through the 3 - 2 - 1 and into the trial.
			_phase = Phase.COUNTDOWN
			_begin_intro_shot()
		return
	if embedded and not final_trial:
		trial_complete.emit()
		return
	hud.show_results(_results, "THE GODS HAVE SPOKEN" if embedded else "TRIAL COMPLETE")
	hud.set_results_hint("SPACE - FINISH RUN      ESC - LEAVE" if embedded else "SPACE - PLAY AGAIN      ESC - LEAVE")


func _end_trial() -> void:
	_phase = Phase.RESULTS
	_end_intro_shot()
	_reset_drop()
	_clear_roots()
	_clear_structures()
	player.set_lock(true)
	_blind_time = 0.0
	_gain_pending.clear()
	_gain_timer = 0.0
	if due_menu.is_open():
		due_menu.close()
	# The host settles the end-of-trial favors (Favorable Outcome) and shares
	# the numbers; clients already mirrored them from the last snapshot.
	if _authority:
		_results = rules.end_trial()
		_publish_god_state()
	else:
		_results = _results_from_mirror()
	_show_closing_lines()


func _results_from_mirror() -> Dictionary:
	var out := {}
	for id in rules.mortals.keys():
		var mortal := rules.mortal(int(id))
		if mortal == null:
			continue
		out[mortal.id] = {
			"name": mortal.display_name,
			"favor": mortal.favor,
			"due": mortal.due,
			"bonus": 0,
			"is_local": mortal.is_local,
		}
	return out


func _show_closing_lines() -> void:
	var lines: Array = []
	lines.append_array(_speech(god, god.trial_end_lines, god.trial_end_voices))
	if final_trial:
		# Only Bathala's closing trial judges the run - a god's own trial never
		# declares a winner, it just hands the field on. His own ending (trial_end_lines)
		# is spoken first and leads straight into the results.
		var mine := local_favor()
		var success := mine >= success_favor
		if success:
			lines.append_array(_speech(god, god.success_lines, god.success_voices))
		else:
			lines.append_array(_speech(god, god.failure_lines, god.failure_voices))
	else:
		if god.trial_end_lines.is_empty():
			lines.append({"speaker": god.display_name, "color": god.color, "text": "The trial is complete. Your Favor carries onward.", "portrait": god.portrait if god.portrait != null else god.icon})

	# The hand-over: what THIS god says about the god that follows it. Every
	# combination lives in the god's own transition_lines, keyed by the next
	# god's id, so nothing here needs to know who can follow whom.
	var next_god: God = Gods.by_id(next_god_id) if next_god_id != &"" else Gods.next_god(god.id)
	_free_grants = 0
	if next_god != null and next_god.id != god.id:  # nobody follows Bathala: the scoreboard does
		lines.append_array(_speech_transition(god, next_god.id, next_god.display_name))
	dialogue.show_lines(lines, god.portrait if god.portrait != null else god.icon)


# Kept for the older "a god with no arena introduces itself" path.
func _opening_line(god_ref: God) -> String:
	if not god_ref.intro_lines.is_empty():
		return str(god_ref.intro_lines[0])
	return "%s is watching your next trial." % god_ref.display_name


func _due_note() -> String:
	var mortal := rules.local()
	if mortal == null or mortal.due <= 0:
		return "No God's Due yet."
	return "You hold %d God's Due." % mortal.due


func local_favor() -> int:
	var mortal := rules.local()
	return mortal.favor if mortal != null else 0


# --- SKILLS / MENUS ---------------------------------------------------------

func _use_skill(slot: int) -> void:
	var bound: GodFavor = rules.skill_favor(slot)
	if not _authority:
		# Only the host runs the rules - ask it, and show feedback right away.
		if bound == null:
			_log("No favor sits in your %s slot - press F to spend a God's Due" % _slot_key(slot), Color(0.8, 0.8, 0.85))
			return
		if not rules.is_skill_ready(slot):
			_log("%s is still recharging" % bound.display_name, Color(0.8, 0.8, 0.85))
			return
		var mortal := rules.local()
		if mortal != null:
			# Predict the cooldown the host will set - none at all when the
			# Kampilan recharges this first cast - so the bar does not flash.
			mortal.cooldowns[bound.id] = 0.0 if mortal.kampilan_ready else rules.skill_cooldown(slot)
			mortal.kampilan_ready = false
		if _net != null and _net.has_multiplayer_peer():
			_net.rpc_id(1, "request_god_skill", slot, scene_token())
		_skill_feedback(bound)
		return

	var favor: GodFavor = rules.use_skill(slot)
	if favor == null:
		if bound == null:
			_log("No favor sits in your %s slot - press F to spend a God's Due" % _slot_key(slot), Color(0.8, 0.8, 0.85))
		else:
			_log("%s is still recharging" % bound.display_name, Color(0.8, 0.8, 0.85))
		return
	_skill_feedback(favor)
	_publish_god_state()


# A short burst along the way the mortal is moving (or facing, standing still).
# Our own mortal is ours to move on every peer, so no host round trip is needed:
# the new position travels like any other step. Returns true when it dashed.
func try_dash() -> bool:
	if not dash_enabled or _phase != Phase.PLAYING or _dash_cd > 0.0 or player.locked or player.is_stunned():
		return false
	if dialogue.is_active() or due_menu.is_open():
		return false
	_dash_cd = dash_cooldown
	player.dash(Input.get_vector("move_left", "move_right", "move_up", "move_down"), dash_distance, dash_time)
	return true


func dash_cooldown_left() -> float:
	return _dash_cd


func _slot_key(slot: int) -> String:
	return "E" if slot == GodFavor.Slot.E else "Q"


func _skill_feedback(favor: GodFavor) -> void:
	_show_banner(favor.display_name.to_upper(), favor.color, 1.4)
	_log("%s activated" % favor.display_name, favor.color)
	_apply_skill_effect(favor, _my_id)


# The world effect of a skill, played for every mortal EXCEPT the one that cast
# it. `caster_id` is the peer whose screen must stay clear: our own id when we
# pressed the key ourselves, the sender's id when the host is running a remote
# player's cast. The host also tells the clients - a screen can only be darkened
# on the machine that draws it.
func _apply_skill_effect(favor: GodFavor, caster_id: int) -> void:
	if favor == null:
		return
	if favor.id == &"half_vision":
		var radius := favor.param("vision_radius", 0.16)
		var duration := maxf(0.0, favor.duration)
		if caster_id == _my_id:
			_log("Half Vision - everyone else sees only a circle around them", favor.color)
		else:
			_blind_radius = radius
			_blind_time = maxf(_blind_time, _morning_cap(duration))
			_log("Half Vision - you see only a circle around your mortal", favor.color)
		if _authority and _networked and _net != null:
			_net.send_arena_blind(caster_id, radius, duration)
	elif favor.id == &"siblings_compromise_sun" and _authority:
		var duration := maxf(0.0, favor.duration)
		for mortal in rules.mortals.values():
			if mortal.id == caster_id:
				continue
			_loss_boost[mortal.id] = maxf(float(_loss_boost.get(mortal.id, 0.0)), duration)
			_add_sun_patches(mortal.id, 7, duration, caster_id)
		_publish_god_state()
	elif favor.id == &"let_us_light_your_way":
		# A Little More Control stretches the Tranced pull too.
		var duration := maxf(0.0, favor.duration) + rules.control_bonus(caster_id)
		_start_movement_override(caster_id, duration)
		if _authority and _networked and _net != null:
			_net.send_arena_movement_override(caster_id, duration)
	elif favor.id == &"bagong_umaga" and _authority:
		var restored := rules.restore_recent_losses(caster_id, favor.param("lookback", 5.0))
		_log("Bagong Umaga - %s gets back %d FAVOR" % [mortal_label(caster_id), restored], favor.color)
		_publish_god_state()
	elif favor.id == &"rest_and_refreshed" and _authority:
		var reached := rules.cast_rest_and_refreshed(caster_id, favor)
		if reached > 0:
			_log("Rest and Refreshed - every other mortal grows drowsy", favor.color)
		else:
			_log("Rest and Refreshed - no other mortal to reach", favor.color)
		_publish_god_state()
	elif favor.id == &"down_to_homeland" and _authority:
		var reached := rules.cast_down_to_homeland(caster_id, favor)
		if reached > 0:
			_log("Down to Homeland - roots drag every other mortal back", favor.color)
		else:
			_log("Down to Homeland - no other mortal to reach", favor.color)
		_publish_god_state()
	elif favor.id == &"ligaw_na_damo" and _authority:
		rules.cast_ligaw_na_damo(caster_id, favor)
		_log("Ligaw na Damo - weeds grow in every other field, feeding %s" % mortal_label(caster_id), favor.color)
		_publish_god_state()
	elif favor.id == &"unang_ulan" and _authority:
		var holder := rules.mortal(caster_id)
		if holder != null:
			holder.rain_lost = 0
		_log("Unang Ulan - what %s loses now grows back" % mortal_label(caster_id), favor.color)
		_publish_god_state()
	elif favor.id == &"kamalig" and _authority:
		var stored := rules.store_in_granary(caster_id, favor)
		_log("Kamalig - %s stores %d FAVOR in the granary" % [mortal_label(caster_id), stored], favor.color)
		_publish_god_state()
	elif favor.id == &"unswerved_unbothered":
		var mortal := rules.mortal(caster_id)
		if mortal == null:
			return
		_erase_sun_patches(caster_id)
		if caster_id == _my_id:
			_blind_time = 0.0
			_refresh_sun_patches()
		if _authority:
			_publish_god_state()
	elif favor.id == &"a_little_more_structure" and _authority:
		_open_structure(caster_id, favor)
		if caster_id == _my_id:
			_log("A Little More Structure - every mortal has %ds to step inside the ring" % int(ceil(favor.param("countdown", 3.0))), favor.color)
		_publish_god_state()
	elif favor.id == &"a_little_more_control" and _authority:
		rules.begin_control(caster_id, favor)
		if caster_id == _my_id:
			_log("A Little More Control - roots, stuns and trances on rivals last %ds longer" % int(ceil(favor.param("extra_time", 1.0))), favor.color)
		_publish_god_state()


# A duration of 0 means "stop now" (the host's word that the pull is over).
func _start_movement_override(caster_id: int, duration: float) -> void:
	if duration <= 0.0:
		if caster_id == _movement_override_caster:
			_movement_override_time = 0.0
		return
	_movement_override_caster = caster_id
	_movement_override_time = maxf(_movement_override_time, duration)


func _on_movement_override_received(caster_id: int, duration: float) -> void:
	if caster_id == _my_id:
		return
	_start_movement_override(caster_id, duration)


# --- A LITTLE MORE STRUCTURE: THE RING ------------------------------------------
# Sidapa opens a ring where the caster stands and every mortal gets a few seconds
# to step inside it; whoever is still outside when the count reaches zero is
# stunned. The host keeps the clock and judges the field; the ring itself rides
# the arena tick, so it is drawn on every screen.

func _open_structure(caster_id: int, favor: GodFavor) -> void:
	var at := mortal_position(caster_id)
	if at == Vector2.INF:
		at = _field.get_center() if _field.size != Vector2.ZERO else player.global_position
	_structure_seq += 1
	var total := maxf(0.1, favor.param("countdown", 3.0))
	_structures.append({
		"id": _structure_seq,
		"caster": caster_id,
		"at": at,
		"radius": favor.param("radius", 130.0),
		"left": total,
		"total": total,
		"stun": favor.param("stun_time", 3.0),
	})
	_sync_structure_visuals()


func _tick_structures(delta: float) -> void:
	if _structures.is_empty():
		return
	if _authority and _phase == Phase.PLAYING:
		for structure in _structures.duplicate():
			structure["left"] = float(structure["left"]) - delta
			if float(structure["left"]) <= 0.0:
				_expire_structure(structure)
	_sync_structure_visuals()


func _expire_structure(structure: Dictionary) -> void:
	var ring_id := int(structure["id"])
	for index in range(_structures.size()):
		if int(_structures[index]["id"]) == ring_id:
			_structures.remove_at(index)
			break
	var at: Vector2 = structure["at"]
	var radius := float(structure["radius"])
	var caster := int(structure["caster"])
	var seconds := float(structure.get("stun", 3.0))
	for key in rules.mortals.keys():
		var mortal_id := int(key)
		var pos := mortal_position(mortal_id)
		if pos == Vector2.INF:
			# A solo bot has no body to place; in a networked game an unknown
			# rival is simply not ours to judge.
			if _networked:
				continue
		elif pos.distance_to(at) <= radius:
			continue
		var length := rules.stun_mortal(mortal_id, seconds, caster)
		if length > 0.0:
			announce_stun(mortal_id, length)
	_publish_god_state()


func _clear_structures() -> void:
	_structures.clear()
	for ring_id in _structure_nodes.keys():
		var node: Node2D = _structure_nodes[ring_id]
		if is_instance_valid(node):
			node.queue_free()
	_structure_nodes.clear()


func _structure_wire() -> Array:
	var out: Array = []
	for structure in _structures:
		var at: Vector2 = structure["at"]
		out.append({
			"id": int(structure["id"]),
			"caster": int(structure["caster"]),
			"x": at.x,
			"y": at.y,
			"radius": float(structure["radius"]),
			"left": float(structure["left"]),
			"total": float(structure["total"]),
		})
	return out


func _read_structure_wire(entries: Array) -> void:
	var next: Array[Dictionary] = []
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		next.append({
			"id": int(entry.get("id", 0)),
			"caster": int(entry.get("caster", -1)),
			"at": Vector2(float(entry.get("x", 0.0)), float(entry.get("y", 0.0))),
			"radius": float(entry.get("radius", 130.0)),
			"left": float(entry.get("left", 0.0)),
			"total": maxf(0.001, float(entry.get("total", 3.0))),
			"stun": 3.0,
		})
	_structures = next
	_sync_structure_visuals()


func _structure_tint() -> Color:
	var favor := Gods.favor_by_id(&"a_little_more_structure")
	return favor.color if favor != null else Color(0.62, 0.45, 0.95)


func _circle_points(radius: float, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	return points


func _make_structure_node(radius: float) -> Node2D:
	var tint := _structure_tint()
	var node := Node2D.new()
	node.name = "Structure"
	node.z_index = 2
	add_child(node)
	var fill := Polygon2D.new()
	fill.name = "Fill"
	fill.color = Color(tint.r, tint.g, tint.b, 0.13)
	fill.polygon = _circle_points(radius, 32)
	node.add_child(fill)
	var ring := Line2D.new()
	ring.name = "Ring"
	ring.width = 3.0
	ring.closed = true
	ring.default_color = tint
	ring.points = _circle_points(radius, 48)
	node.add_child(ring)
	var count := Label.new()
	count.name = "Count"
	count.theme_type_variation = &"WorldValue"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.size = Vector2(48.0, 24.0)
	count.position = Vector2(-24.0, -radius - 24.0)
	count.add_theme_color_override("font_color", tint)
	node.add_child(count)
	return node


func _sync_structure_visuals() -> void:
	var tint := _structure_tint()
	var alive := {}
	for structure in _structures:
		var ring_id := int(structure["id"])
		alive[ring_id] = true
		var node: Node2D = _structure_nodes.get(ring_id)
		if node == null or not is_instance_valid(node):
			node = _make_structure_node(float(structure["radius"]))
			_structure_nodes[ring_id] = node
		node.global_position = structure["at"]
		var left := float(structure["left"])
		var count := node.get_node_or_null("Count") as Label
		if count != null:
			count.text = str(maxi(1, int(ceil(left))))
			count.add_theme_color_override("font_color", Color(0.88, 0.38, 0.31) if left <= 1.0 else tint)
		var ring := node.get_node_or_null("Ring") as Line2D
		if ring != null:
			ring.modulate.a = 1.0 if reduce_flashing() else 0.74 + 0.26 * sin(Time.get_ticks_msec() * 0.008)
	for ring_id in _structure_nodes.keys().duplicate():
		if alive.has(int(ring_id)):
			continue
		var node: Node2D = _structure_nodes[ring_id]
		if is_instance_valid(node):
			node.queue_free()
		_structure_nodes.erase(ring_id)


func _erase_sun_patches(mortal_id: int) -> void:
	_sun_patches.erase(mortal_id)
	_sun_patch_sources.erase(mortal_id)


func nearby_movement_favors_enabled() -> bool:
	return true


func _update_movement_favors(delta: float) -> void:
	var mortal := rules.local()
	if mortal == null:
		return
	var speed := _base_move_speed
	if mortal.has_favor(&"the_shining"):
		speed *= 1.1
	if mortal.has_favor(&"the_guidance") and nearby_movement_favors_enabled():
		var nearby := false
		for entry in mortal_entries():
			if int(entry["id"]) != _my_id and player.global_position.distance_to(entry["pos"]) <= GUIDANCE_RADIUS:
				nearby = true
				break
		if nearby:
			_guidance_time = 1.0
		else:
			_guidance_time = maxf(0.0, _guidance_time - delta)
		if _guidance_time > 0.0:
			speed *= 1.5
	else:
		_guidance_time = 0.0
	# Banton Burial Cloth: faster for the first seconds of the trial.
	if rules.pamana_in_window(mortal, Pamanas.BANTON_CLOTH):
		speed *= Pamanas.by_id(Pamanas.BANTON_CLOTH).param("speed_multiplier", 1.15)
	# Rest and Refreshed: a drowsy mortal drags their feet.
	if mortal.drowsy_time > 0.0:
		speed *= DROWSY_SPEED
	player.move_speed = speed * arena_speed_scale()

	if _movement_override_time > 0.0:
		_movement_override_time = maxf(0.0, _movement_override_time - delta)
		if _movement_override_caster != _my_id:
			var target := mortal_position(_movement_override_caster)
			if target != Vector2.INF:
				player.force_movement(target - player.global_position, 0.08)
		_pull_solo_ghosts(delta)


# Tala's pull on a body no peer is reporting (the Playground's dummy): step it
# toward the caster here, keeping the rules' copy with it so the ghost glide
# cannot pull it back. Networked ghosts are pulled by their own screens.
func _pull_solo_ghosts(delta: float) -> void:
	if _networked:
		return
	var caster := popup_body(_movement_override_caster)
	if caster == null:
		return
	for id in _ghosts.keys():
		if int(id) == _movement_override_caster:
			continue
		var ghost := _ghosts[id] as ArenaMortal
		if ghost == null or not is_instance_valid(ghost):
			continue
		var to_caster := caster.global_position - ghost.global_position
		if to_caster.length() < 1.0:
			continue
		ghost.global_position += to_caster.normalized() * minf(ghost.move_speed * delta, to_caster.length())
		_mortal_positions[int(id)] = ghost.global_position


# --- THE E SKILLS' AFFLICTIONS ON OUR OWN MORTAL -------------------------------
# Rest and Refreshed: the small 3-2-1 over every drowsy mortal's head while the
# drowsiness runs, then the usual stun stars (the host announces the end once, so
# every screen gets them). The clocks are the host's; this only reads them.
func _watch_drowsy() -> void:
	for id in rules.mortals.keys():
		var mortal: GodMatch.Mortal = rules.mortal(int(id))
		var body := mortal_node(int(id))
		if mortal == null or body == null:
			continue
		if mortal.drowsy_time > 0.0:
			body.show_drowsy_count(int(ceil(mortal.drowsy_time)))
			_drowsy_seen[int(id)] = true
			continue
		body.clear_drowsy_count()
		if _drowsy_seen.erase(int(id)) and _authority and mortal.stun_time > 0.0:
			announce_stun(int(id), mortal.stun_time)


# What Rest and Refreshed and Down to Homeland leave on a mortal. The host keeps
# the clocks (GodMatch._tick_afflictions) and every screen reads them: a drowsy
# mortal walks slower and the drowsiness ends in a stun; a rooted one keeps
# walking with a dark shadow dragging behind them, and when the root's clock runs
# out it pulls them back to where it was planted.
func _watch_afflictions(delta := 0.0) -> void:
	if player == null or rules == null:
		return
	_watch_drowsy()
	_watch_roots(delta)
	_watch_weeds()
	_watch_tranced()
	_watch_statuses()
	var mortal := rules.local()
	if mortal == null:
		return
	if mortal.stun_time > 0.0:
		player.stun(mortal.stun_time)


# Every rooted mortal we can see carries their own leash - ours, a rival's ghost,
# a solo arena's bot (through watch_root) - so a root is never only its victim's
# screen's business. The leash does not hold them: they walk while it lasts, the
# tether stretching as they go, and when its clock runs out OUR mortal is dragged
# back to the shadow while the tether stays up for the pull. A ghost's return
# arrives in the positions the host sends, and its tether follows it home.
func _watch_roots(delta := 0.0) -> void:
	for id in rules.mortals.keys():
		var body := mortal_node(int(id))
		if body != null:
			var mortal := rules.mortal(int(id))
			watch_root(int(id), body, mortal != null and mortal.rooted_time > 0.0)
	for id in _root_leashes.keys():
		if not rules.mortals.has(id):
			watch_root(int(id), null, false)
	_watch_root_pulls(delta)


# The leash for one body: plant the shadow the first frame its root shows, let
# the tether follow it while the clock runs, and keep it up for the drag home
# when the clock runs out. `body` is null when it leaves the screen, which only
# puts the shadow away.
func watch_root(mortal_id: int, body: ArenaMortal, rooted_now: bool) -> void:
	var leash: Dictionary = _root_leashes.get(mortal_id, {})
	if rooted_now and body != null and leash.is_empty():
		var shadow := body.global_position + Vector2(-body.facing * ROOT_SHADOW_BACK, 0.0)
		if _field.size != Vector2.ZERO:
			var inset := Vector2(ROOT_SHADOW_SIZE.x, ROOT_SHADOW_SIZE.y)
			shadow = shadow.clamp(_field.position + inset, _field.end - inset)
		var tether := _make_root_tether(body.global_position + Vector2(0.0, -6.0), shadow)
		leash = {"shadow": shadow, "tether": tether}
		_root_leashes[mortal_id] = leash
	elif not rooted_now and not leash.is_empty():
		_root_leashes.erase(mortal_id)
		# Our own mortal is dragged by its physics; a solo screen's dummy has no
		# peer behind it, so _watch_root_pulls walks it home. A networked ghost is
		# dragged by its own screen and follows through the positions it reports.
		if body != null and _phase == Phase.PLAYING:
			_root_pulls[mortal_id] = {
				"shadow": leash["shadow"],
				"tether": leash["tether"],
				"left": ROOT_DRAG_TIME,
				"hold": ROOT_SHADOW_LINGER,
			}
			if mortal_id == _my_id:
				body.return_to(leash["shadow"], ROOT_DRAG_TIME)
		else:
			_fade_root_tether(leash["tether"])
		return
	if body != null and not leash.is_empty():
		_set_tether_points(leash["tether"], body.global_position + Vector2(0.0, -6.0), leash["shadow"])


# The tether stays taut through the drag back, the shadow holds a beat once the
# mortal lands on it, and only then do both fade.
func _watch_root_pulls(delta: float) -> void:
	for id in _root_pulls.keys().duplicate():
		var pull: Dictionary = _root_pulls[id]
		var body := popup_body(int(id))
		var mortal_body := body as ArenaMortal
		# A stun holds the mortal where it stands: the leash and its clock wait,
		# so the pull is never cut short by a shove landing mid-drag.
		var paused: bool = mortal_body != null and mortal_body.is_stunned()
		if mortal_body != null and int(id) != _my_id and not _networked and not paused:
			var left := float(pull["left"])
			if left > 0.0:
				var to_shadow: Vector2 = pull["shadow"] - body.global_position
				body.global_position += to_shadow * minf(1.0, delta / maxf(left, 0.001))
				_mortal_positions[int(id)] = body.global_position
		if body != null:
			_set_tether_points(pull["tether"], body.global_position + Vector2(0.0, -6.0), pull["shadow"])
		if paused:
			continue
		if float(pull["left"]) > 0.0:
			pull["left"] = maxf(0.0, float(pull["left"]) - delta)
			if float(pull["left"]) <= 0.0 and mortal_body != null and int(id) != _my_id and not _networked:
				mortal_body.global_position = pull["shadow"]
				_mortal_positions[int(id)] = mortal_body.global_position
		else:
			pull["hold"] = maxf(0.0, float(pull["hold"]) - delta)
			if float(pull["hold"]) <= 0.0:
				_root_pulls.erase(id)
				_fade_root_tether(pull["tether"])


# Ligaw na Damo: the weed clump at the feet of every weeded mortal, ours and theirs.
func _watch_weeds() -> void:
	for id in rules.mortals.keys():
		var body := popup_body(int(id))
		var mortal := rules.mortal(int(id))
		if body != null:
			body.set_weeded(mortal != null and mortal.weeds_time > 0.0)


# Tala's Let Us Light Your Way: the sparkles over every mortal it is pulling
# (all of them but the caster), on every screen that hears the host's clock.
func _watch_tranced() -> void:
	var pulling := _movement_override_time > 0.0
	for id in rules.mortals.keys():
		var body := popup_body(int(id))
		if body != null:
			body.set_tranced(pulling and int(id) != _movement_override_caster)


# The word over the head: ROOTED while the leash holds (and through its drag),
# WEEDED while Ligaw na Damo does.
func _watch_statuses() -> void:
	var weeds := Gods.favor_by_id(&"ligaw_na_damo")
	for id in rules.mortals.keys():
		var body := popup_body(int(id))
		var mortal := rules.mortal(int(id))
		if body == null or mortal == null:
			continue
		var rooted := mortal.rooted_time > 0.0 or _root_pulls.has(int(id))
		var weeded := mortal.weeds_time > 0.0
		if rooted and weeded:
			body.set_status("ROOTED + WEEDED", UITokens.EMBER)
		elif rooted:
			body.set_status("ROOTED", UITokens.EMBER)
		elif weeded:
			body.set_status("WEEDED", weeds.color if weeds != null else UITokens.EMBER)
		else:
			body.set_status("")


# A trial starting or ending leaves no leash behind.
func _clear_roots() -> void:
	for leash in _root_leashes.values():
		_fade_root_tether(leash["tether"])
	_root_leashes.clear()
	for pull in _root_pulls.values():
		_fade_root_tether(pull["tether"])
	_root_pulls.clear()


# The shadow's body: a tether line and a flattened dark ellipse, in the world
# under the mortals. Built once per root, then only the line moves.
func _make_root_tether(at: Vector2, shadow: Vector2) -> Node2D:
	var tether := Node2D.new()
	tether.name = "RootTether"
	tether.top_level = true
	tether.z_index = 2
	add_child(tether)
	var line := Line2D.new()
	line.name = "Line"
	line.width = 3.0
	line.default_color = ROOT_TETHER_COLOR
	tether.add_child(line)
	var shade := Polygon2D.new()
	shade.name = "Shadow"
	shade.color = ROOT_SHADOW_COLOR
	var ellipse := PackedVector2Array()
	for index in range(20):
		var angle := TAU * float(index) / 20.0
		ellipse.append(Vector2(cos(angle) * ROOT_SHADOW_SIZE.x, sin(angle) * ROOT_SHADOW_SIZE.y))
	shade.polygon = ellipse
	shade.position = shadow
	tether.add_child(shade)
	_set_tether_points(tether, at, shadow)
	return tether


func _set_tether_points(tether: Node2D, at: Vector2, shadow: Vector2) -> void:
	var line := tether.get_node_or_null("Line") as Line2D
	if line != null:
		line.points = PackedVector2Array([at, shadow])


func _fade_root_tether(tether: Node2D) -> void:
	if tether == null or not is_instance_valid(tether):
		return
	var tween := create_tween()
	tween.tween_property(tether, "modulate:a", 0.0, ROOT_DRAG_TIME)
	tween.tween_callback(tether.queue_free)


func _collect_sun_patch_rects() -> void:
	_sun_patch_rects.clear()
	if sun_patch_layer == null:
		return
	for child in sun_patch_layer.get_children():
		if child is TextureRect:
			_sun_patch_rects.append(child)
	_refresh_sun_patches()


# --- THE BLOTS ON THIS SCREEN --------------------------------------------------
# A blot is not a slot in a list: it is a rect that happened to be free when it
# arrived, plus a clock of its own. That is what makes them independent - they do
# not fill rect 0, 1, 2 and then empty from the front, they scatter over the
# free rects and each one goes down when its own time is up.

# Show one sun patch for `seconds`. It claims a rect at random out of the free
# ones (a rect already showing is never reused) and returns false when every
# rect is busy.
func show_sun_patch(seconds: float, from_favor := false) -> bool:
	if seconds <= 0.0 or _sun_patch_rects.is_empty():
		return false
	var index := _claim_sun_patch_rect()
	if index < 0:
		return false
	_sun_patch_slots.append({"index": index, "left": seconds, "favor": from_favor})
	_sun_patch_rects[index].visible = true
	_fade_in_patch(_sun_patch_rects[index])
	return true


# Player comfort options live in the Settings autoload. They are looked up by
# path, not by name, so scripts that load an arena before the autoloads exist
# (the tools/ checks) still compile.
func reduce_flashing() -> bool:
	var settings := get_node_or_null("/root/Settings")
	return settings != null and bool(settings.call("reduce_flashing"))


func screen_shake_allowed() -> bool:
	var settings := get_node_or_null("/root/Settings")
	return settings == null or bool(settings.call("screen_shake_enabled"))


func intro_camera_allowed() -> bool:
	var settings := get_node_or_null("/root/Settings")
	return settings == null or bool(settings.call("intro_camera_enabled"))


# With "reduce flashing" on a patch fades in over 0.3s; it covers the same area
# for the same time either way.
func _fade_in_patch(rect: TextureRect) -> void:
	if not rect.has_meta("base_alpha"):
		rect.set_meta("base_alpha", rect.modulate.a)
	var alpha: float = rect.get_meta("base_alpha")
	rect.modulate.a = alpha
	if reduce_flashing():
		rect.modulate.a = 0.0
		create_tween().tween_property(rect, "modulate:a", alpha, 0.3)


func active_sun_patches() -> int:
	return _sun_patch_slots.size()


# How long the nth blot on this screen has left (0.0 when there is none).
func sun_patch_time_left(slot: int) -> float:
	if slot < 0 or slot >= _sun_patch_slots.size():
		return 0.0
	return float(_sun_patch_slots[slot]["left"])


# Which rect the nth blot is using (-1 when there is none).
func sun_patch_rect_at(slot: int) -> int:
	if slot < 0 or slot >= _sun_patch_slots.size():
		return -1
	return int(_sun_patch_slots[slot]["index"])


func clear_sun_patches() -> void:
	for rect in _sun_patch_rects:
		rect.visible = false
	_sun_patch_slots.clear()


# Every blot runs its own clock, on every machine: what is drawn on this screen
# belongs to this screen, whichever player decided that it should be here.
func _tick_sun_patch_slots(delta: float) -> void:
	if _sun_patch_slots.is_empty():
		return
	var at := _sun_patch_slots.size() - 1
	while at >= 0:
		var slot: Dictionary = _sun_patch_slots[at]
		var left := float(slot["left"]) - delta
		if left <= 0.0:
			_release_sun_patch_slot(at)
		else:
			slot["left"] = left
		at -= 1


# Any rect that is free right now.
func _claim_sun_patch_rect() -> int:
	var taken := {}
	for slot in _sun_patch_slots:
		taken[int(slot["index"])] = true
	var free: Array[int] = []
	for index in range(_sun_patch_rects.size()):
		if not taken.has(index):
			free.append(index)
	if free.is_empty():
		return -1
	return free[randi() % free.size()]


func _release_sun_patch_slot(at: int) -> void:
	var index := int(_sun_patch_slots[at]["index"])
	_sun_patch_slots.remove_at(at)
	if index < _sun_patch_rects.size():
		_sun_patch_rects[index].visible = false


# The favor blots are the host's data, so this mirrors how many of them are aimed
# at us into blots of our own: a rise claims a free rect at random, a fall gives
# back the newest one (that is the one the host just erased), and every other
# blot on screen is left strictly alone.
func _refresh_sun_patches() -> void:
	var favor_count := (_sun_patches.get(_my_id, []) as Array).size()
	var held := 0
	for slot in _sun_patch_slots:
		if bool(slot.get("favor", false)):
			held += 1
	while held < favor_count:
		if not show_sun_patch(FAVOR_PATCH_TIME, true):
			break
		held += 1
	while held > favor_count:
		var at := -1
		for index in range(_sun_patch_slots.size() - 1, -1, -1):
			if bool(_sun_patch_slots[index].get("favor", false)):
				at = index
				break
		if at < 0:
			break
		_release_sun_patch_slot(at)
		held -= 1


func _favor_duration(mortal: GodMatch.Mortal, favor_id: StringName, fallback: float) -> float:
	var favor: GodFavor = mortal.favor_by_id(favor_id)
	return fallback if favor == null else maxf(0.0, favor.param("patch_duration", fallback))


func _on_sun_favor_changed(player_id: int, delta: int) -> void:
	if not _authority or delta >= 0:
		return
	var victim := rules.mortal(player_id)
	if victim == null or victim.duration_left(&"unswerved_unbothered") > 0.0:
		return
	for owner in rules.mortals.values():
		if owner.id != player_id and owner.has_favor(&"the_sun_god"):
			_add_sun_patches(player_id, 1, _favor_duration(owner, &"the_sun_god", 1.5))
	if victim.has_favor(&"the_ruler"):
		var opponents: Array[int] = []
		for other in rules.mortals.values():
			if other.id != player_id:
				opponents.append(other.id)
		if not opponents.is_empty():
			opponents.shuffle()
			_add_sun_patches(opponents[0], 1, _favor_duration(victim, &"the_ruler", 1.5))


func _add_sun_patches(mortal_id: int, count: int, duration: float, source := -1) -> void:
	if count <= 0 or duration <= 0.0:
		return
	var mortal := rules.mortal(mortal_id)
	if mortal != null and mortal.duration_left(&"unswerved_unbothered") > 0.0:
		return
	var timers: Array = _sun_patches.get(mortal_id, [])
	var sources: Array = _sun_patch_sources.get(mortal_id, [])
	sources.resize(timers.size())  # an entry the host made without a source reads as -1
	for index in range(sources.size()):
		if sources[index] == null:
			sources[index] = -1
	for index in range(count):
		timers.append(duration)
		sources.append(source)
	_sun_patches[mortal_id] = timers
	_sun_patch_sources[mortal_id] = sources
	# A blot aimed at US is drawn here, right now: it claims a rect at random out
	# of the free ones and comes down on its own clock. Blots aimed at somebody
	# else stay host-side data and travel in the arena tick.
	if mortal_id == _my_id:
		for index in range(count):
			show_sun_patch(duration, true)
	_refresh_sun_patches()
	_check_victor_threshold(mortal_id)


func _check_victor_threshold(victim_id: int) -> void:
	var timers: Array = _sun_patches.get(victim_id, [])
	var victim := rules.mortal(victim_id)
	if victim == null or timers.size() < 5 or victim.has_favor(&"the_victor"):
		return
	for owner in rules.mortals.values():
		if owner.id == victim_id or not owner.has_favor(&"the_victor") or _victor_claimed.has(owner.id):
			continue
		_victor_claimed[owner.id] = true
		var victor: GodFavor = owner.favor_by_id(&"the_victor")
		lose_favor(int(victor.param("penalty", 200.0)), "The Victor", victim_id)
		_log("The Victor took FAVOR from %s" % victim.display_name, god.color)


func _tick_sun_favors(delta: float) -> void:
	if not _authority:
		return
	for mortal_id in _sun_patches.keys().duplicate():
		var active: Array = []
		var active_sources: Array = []
		var sources: Array = _sun_patch_sources.get(mortal_id, [])
		var timers: Array = _sun_patches[mortal_id]
		for index in range(timers.size()):
			var remaining := maxf(0.0, float(timers[index]) - delta)
			if remaining > 0.0:
				active.append(remaining)
				active_sources.append(int(sources[index]) if index < sources.size() else -1)
		if active.is_empty():
			_erase_sun_patches(mortal_id)
		else:
			_sun_patches[mortal_id] = active
			_sun_patch_sources[mortal_id] = active_sources
	for mortal_id in _loss_boost.keys().duplicate():
		var remaining := maxf(0.0, float(_loss_boost[mortal_id]) - delta)
		if remaining <= 0.0:
			_loss_boost.erase(mortal_id)
		else:
			_loss_boost[mortal_id] = remaining
	_refresh_sun_patches()
	_tick_the_great(delta)
	_tick_siblings_rivalry()


func _tick_the_great(delta: float) -> void:
	if _sun_patches.is_empty():
		return
	for mortal in rules.mortals.values():
		if not mortal.has_favor(&"the_great"):
			continue
		var favor: GodFavor = mortal.favor_by_id(&"the_great")
		var pending: float = float(_great_pending.get(mortal.id, 0.0)) + favor.param("favor_per_sec", 2.0) * delta
		while pending >= 1.0:
			pending -= 1.0
			bank_favor(1, "The Great", mortal.id)
		_great_pending[mortal.id] = pending


# Sibling's Rivalry, both halves. The number is the same in both, only the
# direction changes: APOLAKI's fires when the owner pulls that far AHEAD of a
# rival (the sun blots the rival's screen out), MAYARI's when the owner falls
# that far BEHIND one (the moon takes their light instead). Either way it is the
# RIVAL's screen that goes dark, once per rival and once per trial.
func _tick_siblings_rivalry() -> void:
	for owner in rules.mortals.values():
		_rivalry_blind_rivals(owner, &"siblings_rivalry", "ahead_by", false)
		_rivalry_blind_rivals(owner, &"siblings_rivalry_moon", "behind_by", true)


func _rivalry_blind_rivals(owner: GodMatch.Mortal, favor_id: StringName, threshold_key: String, owner_is_behind: bool) -> void:
	if not owner.has_favor(favor_id):
		return
	var favor: GodFavor = owner.favor_by_id(favor_id)
	if favor == null:
		return
	var lead := int(favor.param(threshold_key, 1000.0))
	var per_favor: Dictionary = _rivalry_claimed.get(owner.id, {})
	var claims: Dictionary = per_favor.get(favor_id, {})
	for rival in rules.mortals.values():
		if rival.id == owner.id or claims.has(rival.id):
			continue
		var gap: int = rival.favor - owner.favor
		var reached: bool = (gap <= -lead) if not owner_is_behind else (gap >= lead)
		if not reached:
			continue
		claims[rival.id] = true
		per_favor[favor_id] = claims
		_rivalry_claimed[owner.id] = per_favor
		var block_time := maxf(0.0, favor.duration)
		if favor.god_id == Gods.MAYARI:
			block_time = _morning_cap_for(rival, block_time)
		_add_sun_patches(rival.id, 4, block_time)


# Another mortal cast Half Vision: darken THIS screen (unless we are the caster).
func _on_arena_blind_received(caster_id: int, radius: float, duration: float) -> void:
	if _authority or caster_id == _my_id or duration <= 0.0:
		return
	var mortal := rules.local()
	if mortal != null and mortal.duration_left(&"unswerved_unbothered") > 0.0:
		return
	_blind_radius = radius
	_blind_time = maxf(_blind_time, _morning_cap(duration))
	_log("Half Vision - you see only a circle around your mortal", god.color)


# Morning Chases the Night: a Mayari vision block on a holder lasts at most
# blind_cap seconds, and every block cut short pays bonus FAVOR. These two answer
# for the mortal on THIS screen (the +bonus is asked of the host through
# score_favor) or for any mortal the host names.
func _morning_cap(seconds: float) -> float:
	var capped := _morning_cap_for(rules.local(), seconds, false)
	var perk: GodFavor = rules.local().favor_by_id(&"morning_chases_the_night") if rules.local() != null else null
	if perk != null and capped < seconds:
		score_favor(int(perk.param("bonus", 50.0)), perk.display_name)
	return capped


# Host side: the capped length of a block aimed at `target`, paying the bonus
# straight into their FAVOR when the cap really shortened it.
func _morning_cap_for(target: GodMatch.Mortal, seconds: float, pay := true) -> float:
	var perk: GodFavor = target.favor_by_id(&"morning_chases_the_night") if target != null else null
	if perk == null:
		return seconds
	var cap := perk.param("blind_cap", 0.5)
	if seconds <= cap:
		return seconds
	if _authority and pay:
		bank_favor(int(perk.param("bonus", 50.0)), perk.display_name, target.id)
	return cap


func _toggle_due_menu() -> void:
	if due_menu.is_open():
		due_menu.close()
		return
	due_menu.open(god, rules, _free_grants, not _authority)


func _on_favor_chosen(favor: GodFavor, free_grants_left: int) -> void:
	if _authority:
		_free_grants = free_grants_left
		_publish_god_state()
	else:
		# Ask the host. GRANTED waits for the snapshot that carries the favor
		# (_on_favor_granted), so a host refusal never shows it.
		if _free_grants > 0:
			_free_grants -= 1
		_awaiting_grant = favor.id
		if _net != null and _net.has_multiplayer_peer():
			_net.rpc_id(1, "request_god_grant", favor.id, scene_token())
		return
	_announce_grant(favor)


func _on_favor_granted(player_id: int, favor: GodFavor) -> void:
	if _authority or player_id != rules.local_id or favor.id != _awaiting_grant:
		return
	_awaiting_grant = &""
	_announce_grant(favor)


func _announce_grant(favor: GodFavor) -> void:
	_show_banner("%s GRANTED" % favor.display_name.to_upper(), favor.color, 1.6)
	_log("%s now belongs to you" % favor.display_name, favor.color)


# --- HUD HELPERS ------------------------------------------------------------

# --- THE HINT BAND ------------------------------------------------------------
# Every arena's controls hint is a HintStrip in the band under the field: keys in
# [brackets] become keycaps, read from the player's bindings so a rebinding shows.

func key_cap(action: StringName) -> String:
	return "[%s]" % UITokens.key_text(action)


# The tail every trial's hint ends with: the two favors and God's Due.
func favor_keys_hint() -> String:
	return "%s %s FAVORS   %s GOD'S DUE" % [key_cap(&"skill_e"), key_cap(&"skill_q"), key_cap(&"due_menu")]


func _show_banner(text: String, color: Color, duration := 2.0) -> void:
	if hud != null:
		hud.show_banner(text, color, duration)


func _log(text: String, color: Color) -> void:
	if hud != null:
		hud.log_event(text, color)


# --- NETWORK ----------------------------------------------------------------

# This arena's scene token (see Network.scene_token): its dialogue prefix and its
# god, the same on every screen ("trial_2:tala", "prep_1:apolaki").
func scene_token() -> String:
	return "%s:%s" % [dialogue_prefix, god_id]


func _connect_network() -> void:
	if _net == null:
		return
	if _networked and "scene_token" in _net:
		_net.scene_token = scene_token()
	# A name is local data first: this machine's own mortal can be renamed (the
	# lobby's UPDATE NAME) with or without company, so the tag above it follows
	# either way. The roster is live too: a client often builds its arena before
	# the first list arrives, and a rival can join mid-trial.
	if _net.has_signal("player_name_changed"):
		_net.connect("player_name_changed", _on_player_name_changed)
	if _net.has_signal("player_list_updated"):
		_net.connect("player_list_updated", _on_player_list_updated)
	if not _networked:
		return
	_net.god_state_received.connect(_on_god_state_received)
	_net.arena_state_received.connect(_on_arena_state_received)
	_net.arena_layout_received.connect(_on_arena_layout_received)
	if _net.has_signal("mortal_positions_received"):
		_net.connect("mortal_positions_received", _on_mortal_positions_received)
	if _net.has_signal("arena_hit_received"):
		_net.connect("arena_hit_received", _on_arena_hit_received)
	if _net.has_signal("arena_blind_received"):
		_net.connect("arena_blind_received", _on_arena_blind_received)
	if _net.has_signal("arena_fx_received"):
		_net.connect("arena_fx_received", _on_arena_fx_received)
	if _net.has_signal("arena_movement_override_received"):
		_net.connect("arena_movement_override_received", _on_movement_override_received)
	_net.player_left.connect(_on_peer_left)
	if _net.has_signal("arena_cast_received"):
		_net.connect("arena_cast_received", _on_arena_cast_received)
	if _net.has_signal("dialogue_released"):
		_net.connect("dialogue_released", _on_dialogue_released)
	if _authority:
		_net.god_favor_requested.connect(_on_god_favor_requested)
		_net.god_skill_requested.connect(_on_god_skill_requested)
		_net.god_grant_requested.connect(_on_god_grant_requested)
		if _net.has_signal("arena_score_requested"):
			_net.connect("arena_score_requested", _on_arena_score_requested)
		if _net.has_signal("arena_stun_requested"):
			_net.connect("arena_stun_requested", _on_arena_stun_requested)
	else:
		_net.rpc_id(1, "request_god_state")


func _on_player_list_updated(_players: Dictionary) -> void:
	# The roster can arrive after this arena was built (a client always races the
	# first list) and it can change mid-trial, so the rivals on the field are
	# built from it every time instead of once at start-up. The colours ride with it.
	_sync_ghosts()
	_paint_bandanas()


func _on_player_name_changed(peer_id: int, name: String) -> void:
	# A name is live data, not something a scene can bake in: the lobby's UPDATE
	# NAME can land at any time, so repaint the tag over that mortal, its ghost
	# and its match entry (the results and the dialogue read the entry).
	var clean := name.strip_edges()
	if clean.is_empty():
		return
	var mortal := rules.mortal(peer_id)
	if mortal != null:
		mortal.display_name = clean
	if peer_id == _my_id:
		player.set_display_name(clean, tag_color(peer_id))
	elif _ghosts.has(peer_id) and is_instance_valid(_ghosts[peer_id]):
		_ghosts[peer_id].set_display_name(clean, tag_color(peer_id))


func _sync_ghosts() -> void:
	if separate_players():
		# A private game draws no rivals anywhere: drop anything that slipped in
		# (the field must stay clear on every screen).
		for id in _ghosts.keys().duplicate():
			if is_instance_valid(_ghosts[id]):
				_ghosts[id].queue_free()
			_ghosts.erase(id)
		return
	if _net == null or not _networked:
		return
	var names: Dictionary = _net.players
	for pid in names.keys():
		var id := int(pid)
		if id == _my_id or _ghosts.has(id):
			continue
		var ghost: ArenaMortal = MORTAL_SCENE.instantiate()
		ghosts_root.add_child(ghost)
		ghost.set_lock(true)
		ghost.ring_color = UITokens.god_accent(god)
		ghost.set_display_name(str(names[pid]), tag_color(id))
		ghost.set_bandana(bandana_of(id))
		_ghosts[id] = ghost
	for id in _ghosts.keys().duplicate():
		if not names.has(int(id)):
			_ghosts[id].queue_free()
			_ghosts.erase(id)


# The bandana colour (an index into UITokens.BANDANA_COLORS) a mortal wears: the
# one the host gave that player in the lobby, or - a solo rival, a bot - a free one.
func bandana_of(mortal_id: int) -> int:
	return _net.bandana_of(mortal_id) if _net != null and _net.has_method("bandana_of") else 0


# The colour of a mortal's name tag: gold over this screen's own mortal, and the
# player's bandana over everyone else, so a tag always matches the headband under it.
func tag_color(mortal_id: int) -> Color:
	if mortal_id == _my_id:
		return UITokens.GOLD
	return UITokens.readable_on_dark(UITokens.bandana_color(bandana_of(mortal_id)), UITokens.NIGHT_900)


# Put every mortal on this field in the colour its player holds (the headband and
# the name tag). Safe to call as often as the roster is republished.
func _paint_bandanas() -> void:
	if player != null:
		player.set_bandana(bandana_of(_my_id))
		player.set_tag_color(tag_color(_my_id))
	for id in _ghosts.keys():
		if is_instance_valid(_ghosts[id]):
			(_ghosts[id] as ArenaMortal).set_bandana(bandana_of(int(id)))
			(_ghosts[id] as ArenaMortal).set_tag_color(tag_color(int(id)))


func _move_ghosts(delta: float) -> void:
	# Remote mortals glide towards whatever position the host last reported.
	var weight := clampf(delta * ghost_smoothing, 0.0, 1.0)
	for id in _ghosts.keys():
		var ghost: Node2D = _ghosts[id]
		if not is_instance_valid(ghost) or not _mortal_positions.has(int(id)):
			continue
		var target: Vector2 = _mortal_positions[int(id)]
		# A knockback or a respawn is a jump, not a walk: gliding it across the
		# field would look like the rival is swimming through the arena, so a
		# long way behind is simply put where it belongs.
		if ghost.global_position.distance_to(target) >= ghost_snap_distance:
			ghost.global_position = target
			continue
		ghost.global_position = ghost.global_position.lerp(target, weight)


func _publish_god_state() -> void:
	if _net == null or not _networked or not _authority:
		return
	_net.publish_god_state(rules.snapshot(), scene_token())


func _publish_arena_tick() -> void:
	if _net == null or not _authority:
		return
	if shares_mortal_positions():
		_mortal_positions[_my_id] = player.global_position
		var reported: Dictionary = _net.mortal_positions
		for id in reported.keys():
			_mortal_positions[int(id)] = reported[id]
	# Everything every arena broadcasts, plus whatever the god's own arena adds.
	# God's Due is the host's own news: its banner and event line stay on this
	# screen and never ride the tick to a client.
	var banner_text: String = hud.banner_label.text if hud.banner_label.visible else ""
	if banner_text == _due_banner:
		banner_text = ""
	var event_text: String = hud.event_label.text
	if event_text == _due_event:
		event_text = ""
	var state := {
		"scene": scene_token(),
		"phase": int(_phase),
		"trial_time": _trial_time,
		"drop_left": _drop_left,
		"mortals": _mortal_positions.duplicate() if shares_mortal_positions() else {},
		"banner": banner_text,
		"banner_color": hud.banner_label.get_theme_color("font_color"),
		"event": event_text,
		"event_color": hud.event_label.get_theme_color("font_color"),
		"sun_patches": _sun_patches.duplicate(true),
		"loss_boost": _loss_boost.duplicate(),
		"structures": _structure_wire(),
	}
	state.merge(arena_tick_fields(), true)
	_net.publish_arena_state(state)


func _on_arena_layout_received(layout: Dictionary) -> void:
	if _authority:
		return
	_apply_layout(layout)
	_sync_ghosts()


func _on_arena_state_received(state: Dictionary) -> void:
	if _authority:
		return
	_apply_arena_tick(state)


# The fast position stream, merged into what we know: a message that only
# carries some of the roster must never wipe the rest of it.
func _on_mortal_positions_received(positions: Dictionary) -> void:
	if _authority:
		return
	for id in positions.keys():
		_mortal_positions[int(id)] = positions[id]


func _apply_arena_tick(state: Dictionary) -> void:
	# Another scene's tick (a late one from the trial before, an early one from
	# the rest after) is never this arena's: Network drops it on arrival, and this
	# guards a tick handed in any other way.
	if str(state.get("scene", scene_token())) != scene_token():
		return
	# The host's round, mirrored: the same second on the clock, where the mortals
	# are and whatever the god's own arena put on the wire.
	var remote_phase := int(state.get("phase", int(_phase)))
	_trial_time = float(state.get("trial_time", _trial_time))
	# The shell's clock (Game.gd) reads this signal - without it a client's clock
	# would sit still while the host's runs.
	trial_time_changed.emit(_trial_time)
	hud.set_time_left(_trial_time)
	_read_drop(float(state.get("drop_left", 0.0)))

	var mortals: Dictionary = state.get("mortals", {})
	_mortal_positions.clear()
	for id in mortals.keys():
		_mortal_positions[int(id)] = mortals[id]
	_sun_patches = state.get("sun_patches", {}).duplicate(true)
	_loss_boost_seen = state.get("loss_boost", {}).duplicate()
	_read_structure_wire(state.get("structures", []))
	var local_mortal := rules.local()
	if local_mortal != null and local_mortal.duration_left(&"unswerved_unbothered") > 0.0:
		_erase_sun_patches(_my_id)
		_blind_time = 0.0
	_refresh_sun_patches()
	arena_read_tick(state)

	# Follow the host through the trial phases.
	if remote_phase == int(Phase.RESULTS) and _phase != Phase.RESULTS:
		_end_trial()
	elif remote_phase == int(Phase.PLAYING) and _phase != Phase.PLAYING and _phase != Phase.RESULTS:
		_enter_playing()
	elif remote_phase == int(Phase.COUNTDOWN) and _phase == Phase.INTRO:
		_phase = Phase.COUNTDOWN
		_begin_intro_shot()

	# Mirror the god's announcements.
	var banner := str(state.get("banner", ""))
	if banner != "" and banner != _last_banner:
		_last_banner = banner
		_show_banner(banner, state.get("banner_color", god.color), 1.2)
	var event := str(state.get("event", ""))
	if event != "" and event != _last_event:
		_last_event = event
		_log(event, state.get("event_color", god.color))


# A client's copy of the step into the trial: the host's tick drives it, so the
# dialogue is put away and the mortal may move.
func _enter_playing() -> void:
	_phase = Phase.PLAYING
	_end_intro_shot()
	_reset_drop()  # the host's drop is over (its phase says so): everyone stands on their spawn
	if dialogue.is_active():
		dialogue.close_now()
	player.set_lock(false)
	rules.trial_active = true


func _on_god_state_received(state: Dictionary) -> void:
	if _authority:
		return
	rules.apply_snapshot(state)


func _on_god_favor_requested(peer_id: int, amount: int, reason: String) -> void:
	bank_favor(amount, reason, peer_id)
	_publish_god_state()


func _on_god_skill_requested(peer_id: int, slot: int) -> void:
	var favor: GodFavor = rules.use_skill(slot, peer_id)
	if favor == null:
		return
	if peer_id == _my_id:
		_skill_feedback(favor)
	else:
		_log("%s used %s" % [mortal_label(peer_id), favor.display_name], favor.color)
		# A remote cast plays out on our screens too - every screen but the
		# caster's, which is why it runs with the sender's id.
		_apply_skill_effect(favor, peer_id)
	_publish_god_state()


func _on_god_grant_requested(peer_id: int, favor_id: StringName) -> void:
	var favor := god.get_favor(favor_id)
	if favor != null and rules.grant_favor(favor, peer_id):
		_publish_god_state()


func _on_peer_left(peer_id: int) -> void:
	if not _networked:
		return
	rules.remove_mortal(peer_id)
	_mortal_positions.erase(peer_id)
	_ghosts.erase(peer_id)
	_sync_ghosts()
	if _authority:
		_publish_god_state()


# --- MATCH SIGNALS ----------------------------------------------------------

func _on_favor_changed(player_id: int, _total: int, delta: int, reason: String) -> void:
	if reason == GodMatch.PURCHASE_REASON:
		# FAVOR spent at the Tindahan: not a loss, so no sun patch, no red popup.
		return
	if reason == GodMatch.TRANSFER_REASON:
		# Kamalig moving FAVOR in or out of the granary: not a loss, so no sun
		# patch, no red popup - just say where it went.
		if player_id == rules.local_id and delta != 0:
			_log("%s %d FAVOR   (Kamalig)" % ["stored" if delta < 0 else "returned", absi(delta)], Color(0.56, 0.78, 0.33))
		return
	_on_sun_favor_changed(player_id, delta)
	if delta == 0:
		return
	if player_id == rules.local_id:
		# Our own FAVOR: the popup off our own head, plus the event line for the
		# swings worth reading.
		if popups_enabled:
			if delta > 0 and delta < popup_big_delta:
				# A trickle (a lit zone pays many times a second): gather it and
				# show one popup instead of one per credit.
				_gain_pending[player_id] = int(_gain_pending.get(player_id, 0)) + delta
			else:
				favor_popup(player_id, delta)
		if absi(delta) >= 10:
			var color := Color(0.7, 1, 0.8) if delta > 0 else Color(1, 0.5, 0.45)
			_log("%s%d FAVOR   (%s)" % ["+" if delta > 0 else "", delta, reason], color)
		return
	# A rival's mortal: their own screen shows their popup, and a real loss (a
	# clone catching them) also reads over their ghost here.
	if popups_enabled and delta <= -popup_big_delta:
		favor_popup(player_id, delta)


func _on_due_earned(player_id: int, _due: int, milestone: int) -> void:
	if player_id != rules.local_id:
		return
	_due_banner = "%d FAVOR - GOD'S DUE EARNED" % milestone
	_due_event = "You reached %d FAVOR - one God's Due is yours (press F to spend it)" % milestone
	_show_banner(_due_banner, Color(1, 0.9, 0.45), 2.2)
	_log(_due_event, Color(1, 0.9, 0.45))


# A favor of Hanan's fired on the host: say so, in the favor's colour. Banners are
# for our own mortal; the event line is mirrored to every client by the arena tick.
func _on_favor_fired(player_id: int, favor: GodFavor, text: String) -> void:
	_log(text, favor.color)
	if player_id == _my_id:
		_show_banner(favor.display_name.to_upper(), favor.color, 1.4)


# A Pamana did something on the host: the event line for everyone, the banner for
# its owner. A client sees its own item's banners through _watch_local_pamana.
func _on_pamana_fired(player_id: int, pamana: Pamana, text: String) -> void:
	var line := text if player_id == _my_id else "%s: %s" % [mortal_label(player_id), text]
	_log(line, pamana.color)
	if player_id == _my_id:
		_show_banner(text, UICards.pamana_edge(pamana), 1.6)


# Bato Bato sa Langit: the host names whose blessing caught the mortal, over their
# head on every screen, in that god's colour.
func _on_bato_bato_swapped(player_id: int, favor: GodFavor) -> void:
	_bato_bato_popup(player_id, favor)
	_send_fx({"kind": "bato", "id": player_id, "favor": str(favor.id)})


func _bato_bato_popup(player_id: int, favor: GodFavor) -> FavorPopup:
	if favor == null:
		return null
	var god := Gods.by_id(favor.god_id)
	var tint := UITokens.god_accent(god)
	var reason := favor.display_name.to_upper()
	if god != null:
		reason = "%s - %s" % [god.display_name.to_upper(), reason]
	return mortal_popup(player_id, "SI %s AY NATAMAAN!" % mortal_label(player_id).to_upper(), tint, reason)


# Client: the host's Pamana banners are only for the host's own mortal, so a
# client reads its item's moments off the snapshots instead - it woke, the Agimat
# spent a charge, the Kampilan recharged, Surigao Gold paid.
var _pamana_seen := {}


func _watch_local_pamana() -> void:
	var m := rules.local() if rules != null else null
	if _authority or m == null:
		return
	var now := {"active": m.pamana_active, "agimat": m.agimat_charges, "kampilan": m.kampilan_ready, "surigao": m.surigao_early}
	var before := _pamana_seen
	_pamana_seen = now
	if before.is_empty():
		return
	var text := ""
	var item: Pamana = null
	if now["active"] != &"" and now["active"] != before["active"]:
		item = Pamanas.by_id(now["active"])
		text = "%s AWAKENS" % item.display_name.to_upper() if item != null else ""
	elif now["active"] == Pamanas.AGIMAT and int(now["agimat"]) < int(before["agimat"]):
		item = Pamanas.by_id(Pamanas.AGIMAT)
		text = "AGIMAT - LOSS CANCELLED (%d LEFT)" % int(now["agimat"])
	elif now["active"] == Pamanas.KAMPILAN and before["kampilan"] and not now["kampilan"]:
		item = Pamanas.by_id(Pamanas.KAMPILAN)
		text = "KAMPILAN - SKILL RECHARGED"
	elif int(before["surigao"]) > 0 and int(now["surigao"]) <= 0:
		item = Pamanas.by_id(Pamanas.SURIGAO_GOLD)
		text = "SURIGAO GOLD - GOD'S DUE ARRIVES EARLY"
	if item != null and text != "":
		_show_banner(text, UICards.pamana_edge(item), 1.6)


func _on_notice(text: String) -> void:
	_log(text, Color(0.85, 0.85, 0.9))


# --- EFFECT TIMERS --------------------------------------------------------------
# One entry per running effect, for the HUD's stack: {key, name, icon, color, left,
# total, harmful}. `total` is how long the effect lasts when that is known (0: the HUD
# measures the bar against the longest it has seen it run).

func effect(key: StringName, label: String, icon: Texture2D, color: Color, left: float, total := 0.0, harmful := false) -> Dictionary:
	return {"key": key, "name": label, "icon": icon, "color": color, "left": left, "total": total, "harmful": harmful}


# An effect named after a favor: its name, icon and colour.
func favor_effect(key: StringName, favor_id: StringName, left: float, total := 0.0, harmful := false) -> Dictionary:
	var favor := Gods.favor_by_id(favor_id)
	if favor == null:
		return effect(key, str(favor_id).to_upper(), null, UITokens.EMBER, left, total, harmful)
	return effect(key, effect_name(favor), favor.icon, favor.color, left, total if total > 0.0 else favor.duration, harmful)


# A favor's name for a row: upper case, without the "(Mapulon)" a favor's name can carry
# for the Almanac - the row is narrow and the icon says whose it is.
func effect_name(favor: GodFavor) -> String:
	return favor.display_name.split(" (")[0].to_upper()


func local_effects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mortal := rules.local() if rules != null else null
	if mortal == null:
		return out
	# Buffs: our own skills that are still running...
	for favor_id in mortal.durations.keys():
		var favor := mortal.favor_by_id(favor_id)
		var left := mortal.duration_left(favor_id)
		if favor != null and left > 0.0:
			out.append(effect(StringName("skill_%s" % favor_id), effect_name(favor), favor.icon, favor.color, left, favor.duration))
	# ...and a Pamana's opening window (its charges and "spent" stay on the badge: no timer).
	var pamana := Pamanas.by_id(mortal.pamana_active)
	if pamana != null and pamana.timing == Pamana.Timing.FIRST_WINDOW and mortal.pamana_window > 0.0:
		out.append(effect(StringName("pamana_%s" % pamana.id), pamana.display_name.to_upper(), pamana.icon, UICards.pamana_edge(pamana), mortal.pamana_window, pamana.window))
	# Debuffs: what has been put on us.
	if mortal.drowsy_time > 0.0:
		out.append(effect(&"drowsy", "DROWSY", e_icon(Gods.HANAN), UITokens.EMBER, mortal.drowsy_time, 0.0, true))
	if mortal.rooted_time > 0.0:
		out.append(effect(&"rooted", "ROOTED", e_icon(Gods.MAPULON_IKAPATI), UITokens.EMBER, mortal.rooted_time, 0.0, true))
	if rules.trial_active:  # the Harvest Pair's clocks only run in a trial
		if mortal.weeds_time > 0.0:
			out.append(favor_effect(&"weeds", &"ligaw_na_damo", mortal.weeds_time, 0.0, true))
	if _blind_time > 0.0:
		out.append(favor_effect(&"blind", &"half_vision", _blind_time, 0.0, true))
	var patches: Array = _sun_patches.get(_my_id, [])
	if not patches.is_empty():
		var longest := 0.0
		for seconds in patches:
			longest = maxf(longest, float(seconds))
		out.append(effect(&"sun_patches", "SUN PATCHES" if patches.size() > 1 else "SUN PATCH", SUN_PATCH_ICON, UITokens.EMBER, longest, 0.0, true))
	var boosted := float((_loss_boost if _authority else _loss_boost_seen).get(_my_id, 0.0))
	if boosted > 0.0:
		out.append(effect(&"loss_boost", "LOSS +%d%%" % int(round(loss_boost_share() * 100.0)), Gods.favor_by_id(&"siblings_compromise_sun").icon, UITokens.EMBER, boosted, 0.0, true))
	if _movement_override_time > 0.0 and _movement_override_caster != _my_id:
		out.append(favor_effect(&"pulled", &"let_us_light_your_way", _movement_override_time, 0.0, true))
	if mortal.control_time > 0.0:
		out.append(favor_effect(&"control", &"a_little_more_control", mortal.control_time, 0.0))
	if player != null and player.stun_left() > 0.0:
		out.append(effect(&"stun", "STUNNED", null, UITokens.EMBER, player.stun_left(), 0.0, true))
	out.append_array(arena_local_effects())
	return out


# A god's arena lists its own effects here (Langit Lupa: ALIS, a closed Langit).
func arena_local_effects() -> Array[Dictionary]:
	return []


# --- A CAST, SEEN BY EVERYONE ---------------------------------------------------
# The host sees every skill any mortal uses (GodMatch.skill_used) and shows what was
# used over that mortal's head on every screen, so a rival learns what just happened
# to them. An E skill flies its god's E icon; anything else its name, in the
# favor's colour, rising and fading like the mortal's other floating text.

# Each god's E art, in its own Assets folder (32 x 32).
const E_ICONS := {
	Gods.MAYARI: "res://Assets/Gods/Mayari/Mayari-E-PopUP.png",
	Gods.APOLAKI: "res://Assets/Gods/Apolaki/Apolaki-E-PopUp.png",
	Gods.TALA: "res://Assets/Gods/Tala/Tala-E-PopUp.png",
	Gods.HANAN: "res://Assets/Gods/Hanan/Hanan-E-PopUp.png",
	Gods.MAPULON_IKAPATI: "res://Assets/Gods/MapulonIkapati/Mapulon-Popup-E.png",
	Gods.SIDAPA: "res://Assets/Gods/Sidapa/Sidapa-E-PopUp.png",
	Gods.BATHALA: "res://Assets/Gods/Bathala/Bathala-Popup-E.png",
}


static func e_icon(god_id: StringName) -> Texture2D:
	var path := String(E_ICONS.get(god_id, ""))
	return load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null


func _on_skill_used(player_id: int, favor: GodFavor) -> void:
	_show_cast(player_id, favor)
	if _authority and _networked and _net != null:
		_net.send_arena_cast(player_id, favor.id)


func _on_arena_cast_received(caster_id: int, favor_id: StringName) -> void:
	if _authority:
		return
	var favor := Gods.favor_by_id(favor_id)
	if favor != null:
		_show_cast(caster_id, favor)


func _show_cast(mortal_id: int, favor: GodFavor) -> void:
	if favor.slot == GodFavor.Slot.E:
		var icon := e_icon(favor.god_id)
		if icon != null:
			cast_popup(mortal_id, icon, Color.WHITE)
			return
	var body := mortal_node(mortal_id)
	if body != null:
		body.show_floating_text(favor.display_name.to_upper(), UITokens.readable_on_dark(favor.color, UITokens.NIGHT_900, CAST_TEXT_CONTRAST), CAST_TEXT_TIME)


# --- ONE-SHOT EFFECTS ---------------------------------------------------------

# A one-shot sprite at a world position that grows and fades on its own (EFFECTS);
# `angle` turns it (the slash lies along the blow). Returns it, or null for an
# unknown name or an arena without a popup layer.
func spawn_effect(effect: StringName, at: Vector2, angle := 0.0) -> Sprite2D:
	var spec: Dictionary = EFFECTS.get(effect, {})
	if spec.is_empty() or popups_root == null or at == Vector2.INF:
		return null
	var sprite := Sprite2D.new()
	sprite.texture = spec["texture"]
	sprite.rotation = angle
	sprite.scale = Vector2.ONE * float(spec["from"])
	var tint: Color = spec["tint"]
	tint.a = 0.5 if bool(spec["soft"]) and reduce_flashing() else 1.0
	sprite.modulate = tint
	popups_root.add_child(sprite)
	sprite.global_position = at
	var tween := sprite.create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2.ONE * float(spec["to"]), float(spec["time"]))
	tween.tween_property(sprite, "modulate:a", 0.0, float(spec["time"]))
	tween.chain().tween_callback(sprite.queue_free)
	return sprite


# Where an attack lands: a ring and a spark on the target and a slash along the blow.
func hit_effects(at: Vector2, direction: Vector2) -> void:
	spawn_effect(&"impact", at)
	spawn_effect(&"spark", at)
	spawn_effect(&"slash", at, direction.angle())


# The stars over a mortal's head for `seconds` - ours, a rival's ghost or a bot.
func show_stun(mortal_id: int, seconds: float) -> void:
	var body := mortal_node(mortal_id)
	if body != null and seconds > 0.0:
		body.show_stun(seconds)


# What the host shows for a hit it scored, here and on every other screen.
func announce_hit(mortal_id: int, at: Vector2, direction: Vector2, stun_seconds: float) -> void:
	hit_effects(at, direction)
	show_stun(mortal_id, stun_seconds)
	_send_fx({"kind": "hit", "id": mortal_id, "at": at, "dir": direction, "stun": stun_seconds})


# A mortal stumbling without being shoved (a broken chant): the stars, everywhere.
func announce_stun(mortal_id: int, seconds: float) -> void:
	show_stun(mortal_id, seconds)
	_send_fx({"kind": "stun", "id": mortal_id, "stun": seconds})


func _send_fx(fx: Dictionary) -> void:
	if separate_players():
		return  # a private duel (Apolaki's) is nobody else's to watch
	if _authority and _networked and _net != null and _net.has_method("send_arena_fx"):
		_net.send_arena_fx(fx)


func _on_arena_fx_received(fx: Dictionary) -> void:
	if _authority or separate_players():
		return
	var id := int(fx.get("id", -1))
	var kind := str(fx.get("kind", ""))
	if kind == "bato":
		_bato_bato_popup(id, Gods.favor_by_id(StringName(str(fx.get("favor", "")))))
		return
	if kind == "hit":
		hit_effects(fx.get("at", Vector2.INF), fx.get("dir", Vector2.RIGHT))
		if id == _my_id:
			return  # our own hit() already put the stars over our head
	show_stun(id, float(fx.get("stun", 0.0)))


# The body of a mortal on this screen: our own, or a rival's ghost (null when unknown).
func mortal_node(mortal_id: int) -> ArenaMortal:
	if mortal_id == _my_id:
		return player
	if _ghosts.has(mortal_id) and is_instance_valid(_ghosts[mortal_id]):
		return _ghosts[mortal_id]
	return null


# --- BLINDNESS / INPUT ------------------------------------------------------

func _apply_vision_mask() -> void:
	var material := vision_mask.material as ShaderMaterial
	if material == null:
		return
	var view := get_viewport_rect().size
	material.set_shader_parameter("aspect", view.x / maxf(1.0, view.y))
	material.set_shader_parameter("radius", _blind_radius * view_zoom())
	vision_mask.visible = false


func _apply_blindness(delta: float) -> void:
	var mortal := rules.local() if rules != null else null
	if mortal != null and mortal.duration_left(&"unswerved_unbothered") > 0.0:
		_blind_time = 0.0
		_erase_sun_patches(_my_id)
		_refresh_sun_patches()
	_blind_time = maxf(0.0, _blind_time - delta)
	var active := _blind_time > 0.0
	if vision_mask.visible != active:
		vision_mask.visible = active
		_vision_fade = 0.0 if reduce_flashing() else 1.0  # same coverage, just not a pop
	if not active:
		return
	var material := vision_mask.material as ShaderMaterial
	if material == null:
		return
	_vision_fade = minf(1.0, _vision_fade + delta / 0.3)
	material.set_shader_parameter("fade", _vision_fade)
	# The mask is drawn in screen space: the mortal's SCREEN position (the same as
	# its world position without the follow camera), and a circle round the same
	# piece of the world - the camera's zoom draws it bigger on screen.
	var view := vision_mask.size
	var mortal_pos := player.get_global_transform_with_canvas().origin
	material.set_shader_parameter("center", Vector2(mortal_pos.x / maxf(1.0, view.x), mortal_pos.y / maxf(1.0, view.y)))
	material.set_shader_parameter("radius", _blind_radius * view_zoom())


# --- FOLLOW CAMERA ------------------------------------------------------------
# Only built when the shell asks for it (follow_camera). It hangs on the local
# mortal, so it follows them with no code of its own; its LIMITS keep the view
# inside the field (plus follow_margin), and the UI strip is allowed for on the
# left. The aim point sits left of the mortal by half the strip: a node position
# rather than Camera2D.offset, because the offset is applied after the limits
# and could show past them.

func _build_camera() -> void:
	if not follow_camera or player == null:
		return
	camera = Camera2D.new()
	camera.name = "FollowCamera"
	camera.zoom = Vector2.ONE * follow_zoom
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = follow_smoothing
	player.add_child(camera)
	# Set in world pixels: a mortal can be drawn scaled up (Apolaki's duelist size),
	# and a local offset would scale with it.
	camera.global_position = player.global_position + Vector2(-UI_STRIP_WIDTH * 0.5 / follow_zoom, 0.0)
	# The arena this one replaces is freed at the end of the frame and its camera
	# may still hold the view: take it now.
	camera.make_current()
	camera.reset_smoothing()  # start on the mortal, not panning in from the origin
	_build_edge_arrows()


# The camera's limits from the field (called again when a host layout arrives or
# the window is resized). The left one reaches further by the strip, so the
# field's left border shows right of the strip, never under it. A field smaller
# than the view in one direction (most trials are wide and flat) gets the spare
# room split evenly on both sides of it, so it sits in the middle of the view
# instead of against one edge.
func _fit_camera() -> void:
	if camera == null:
		return
	var view := get_viewport_rect().size / follow_zoom  # the screen, in world pixels
	var strip := UI_STRIP_WIDTH / follow_zoom
	var held := _field.grow(follow_margin)
	var spare := ((view - Vector2(strip, 0.0)) - held.size).max(Vector2.ZERO) * 0.5
	camera.limit_left = floori(held.position.x - spare.x - strip)
	camera.limit_top = floori(held.position.y - spare.y)
	camera.limit_right = ceili(held.end.x + spare.x)
	camera.limit_bottom = ceili(held.end.y + spare.y)


# How much bigger the world is drawn than it was authored (1.0 without the camera).
func view_zoom() -> float:
	return camera.zoom.y if camera != null else 1.0


func _exit_tree() -> void:
	# A Camera2D that leaves the tree leaves the view where it last put it: give
	# the screen back to whatever comes next (the finale, the lobby) unless the
	# next arena's camera has already taken it.
	if camera == null and _intro_camera == null:
		return
	var viewport := get_viewport()
	if viewport != null and (viewport.get_camera_2d() == null or viewport.get_camera_2d() in [camera, _intro_camera]):
		viewport.canvas_transform = Transform2D.IDENTITY


# What a trial depends on that the follow camera can hide (the Taya, a god that
# moves, a base): an arena returns those nodes here, and each one that is out of
# view gets a small arrow on the edge of the visible screen pointing at it.
# Nothing is drawn without the follow camera - the whole field is on screen then.
func edge_targets() -> Array:
	return []


func _build_edge_arrows() -> void:
	_edge_arrows = Control.new()
	_edge_arrows.name = "EdgeArrows"
	_edge_arrows.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge_arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_arrows.draw.connect(_draw_edge_arrows)
	ui_layer.add_child(_edge_arrows)
	ui_layer.move_child(_edge_arrows, 0)  # under the HUD's menus and the dialogue
	# Redrawn every frame from here: not every arena's _process calls the base's.
	get_tree().process_frame.connect(_edge_arrows.queue_redraw)


# Every edge target that is out of view: where its arrow sits (on the border of
# the visible area - the screen right of the UI strip, inset) and the way it
# points. Public so the checks can read it.
func edge_arrows() -> Array[Dictionary]:
	var arrows: Array[Dictionary] = []
	if camera == null or _edge_arrows == null or _intro_camera != null:
		return arrows
	var view := _edge_arrows.size
	var shown := Rect2(Vector2(UI_STRIP_WIDTH, 0.0), view - Vector2(UI_STRIP_WIDTH, 0.0)).grow(-edge_arrow_inset)
	var centre := shown.get_center()
	var half := shown.size * 0.5
	for target in edge_targets():
		if not is_instance_valid(target) or not (target is Node2D) or not (target as Node2D).is_visible_in_tree():
			continue
		var at := (target as Node2D).get_global_transform_with_canvas().origin
		if shown.has_point(at):
			continue
		var way := (at - centre).normalized()
		var reach := minf(half.x / maxf(absf(way.x), 0.001), half.y / maxf(absf(way.y), 0.001))
		arrows.append({"node": target, "tip": centre + way * reach, "way": way})
	return arrows


func _draw_edge_arrows() -> void:
	var tint := UITokens.god_accent(god) if god != null else UITokens.GOLD
	for arrow in edge_arrows():
		var tip: Vector2 = arrow["tip"]
		var way: Vector2 = arrow["way"]
		var side := way.orthogonal() * edge_arrow_size * 0.6
		var back := tip - way * edge_arrow_size
		var points := PackedVector2Array([tip, back + side, back - side])
		_edge_arrows.draw_colored_polygon(points, tint)
		points.append(tip)
		_edge_arrows.draw_polyline(points, UITokens.NIGHT_900, 2.0)


# --- THE INTRO SHOT -------------------------------------------------------------
# The first "3 - 2 - 1" of a trial is a short cinematic: a Camera2D of its own
# opens at intro_zoom on the watching god's face (the scene's FaceFocus marker),
# the face sitting intro_face_screen_x across the screen. After intro_hold seconds
# it pans left, at that same zoom, from the god across the arena to the field's
# middle (slowly in, then at a steady speed) - intro_pan_share of the countdown -
# and the rest of the count zooms out (easing out) onto the normal view, landing
# exactly on it as the count reaches GO: the screen itself without the follow
# camera (zoom 1, world = screen), the follow camera's own framing of the mortal
# with it. Then the view is handed back: the shot's camera is freed and the screen
# is world = screen again, or the follow camera is made current and cut to its aim.
# The camera's view stays inside the arena's drawn area (the screen at zoom 1), so
# no void shows; a face too near the top is therefore a little above centre.
# The HUD (hud_alpha: the arena's panels, the bottom band, the shell's strip and
# clock) is hidden through the pan and fades in on the zoom-out; the big count stays.
# Every screen plays it on its own from the countdown it already follows - no
# message travels - and only this screen's view moves: the mortals stay locked
# and no rule reads it. A countdown shorter than the shot squeezes the hold and the
# pan into it; GO is never delayed (_start_trial cuts whatever is left).
# Settings > Gameplay > Intro camera turns it off.

const INTRO_EASE_IN := 0.25  # the share of the pan spent speeding up to its steady pace


func _begin_intro_shot() -> void:
	if _intro_played:
		return
	_intro_played = true
	var focus := get_node_or_null("FaceFocus") as Node2D
	if focus == null or countdown_time <= 0.0 or not intro_camera_allowed():
		return
	_intro_span = countdown_time
	_intro_left = countdown_time
	_intro_hold = minf(intro_hold, countdown_time * intro_pan_share * 0.5)
	var view := get_viewport_rect().size
	var face := focus.global_position
	_intro_open = _intro_inside(Vector2(face.x - (intro_face_screen_x - 0.5) * view.x / intro_zoom, face.y))
	_intro_pan_end = _intro_inside(_field.get_center())
	_intro_camera = Camera2D.new()
	_intro_camera.name = "IntroCamera"
	_intro_camera.limit_enabled = false  # the close-up is never clamped to the field
	add_child(_intro_camera)
	_intro_camera.global_position = _intro_open
	_intro_camera.zoom = Vector2.ONE * intro_zoom
	_intro_camera.make_current()
	_set_hud_alpha(0.0)


func _tick_intro_shot(delta: float) -> void:
	if _intro_camera == null:
		return
	_intro_left = maxf(0.0, _intro_left - delta)
	if _intro_left <= 0.0 or _phase != Phase.COUNTDOWN:
		_end_intro_shot()
		return
	var elapsed := _intro_span - _intro_left
	var pan_end := _intro_span * clampf(intro_pan_share, 0.0, 1.0)
	if elapsed < pan_end:
		var run := clampf((elapsed - _intro_hold) / maxf(0.001, pan_end - _intro_hold), 0.0, 1.0)
		_intro_camera.global_position = _intro_open.lerp(_intro_pan_end, _intro_pan_travelled(run))
		_intro_camera.zoom = Vector2.ONE * intro_zoom
		_set_hud_alpha(0.0)
		return
	var out := clampf((elapsed - pan_end) / maxf(0.001, _intro_span - pan_end), 0.0, 1.0)
	var eased := 1.0 - (1.0 - out) * (1.0 - out)  # ease out
	var target := intro_target()
	_intro_camera.global_position = _intro_pan_end.lerp(target.position, eased)
	_intro_camera.zoom = Vector2.ONE * (intro_zoom * pow(target.size.x / intro_zoom, eased))
	_set_hud_alpha(eased)


# How much of the pan is done after `run` (0..1) of its time: it speeds up for
# INTRO_EASE_IN of it, then keeps a steady pace.
func _intro_pan_travelled(run: float) -> float:
	var ease_in := INTRO_EASE_IN
	var whole := 1.0 - ease_in * 0.5
	if run < ease_in:
		return run * run / (2.0 * ease_in) / whole
	return (ease_in * 0.5 + run - ease_in) / whole


# A camera centre moved so its view at intro_zoom stays inside the drawn area.
func _intro_inside(centre: Vector2) -> Vector2:
	var view := get_viewport_rect().size
	var half := view * 0.5 / intro_zoom
	return Vector2(clampf(centre.x, half.x, view.x - half.x), clampf(centre.y, half.y, view.y - half.y))


func _end_intro_shot() -> void:
	if _intro_camera == null:
		return
	_intro_camera.free()
	_intro_camera = null
	if camera != null:
		camera.make_current()
		camera.reset_smoothing()
	else:
		get_viewport().canvas_transform = Transform2D.IDENTITY
	_set_hud_alpha(1.0)


# Where the shot lands, as Rect2(view centre, Vector2(zoom, zoom)): the screen's
# centre at zoom 1, or the follow camera's aim held inside its limits (what it
# shows once it is current and cut there).
func intro_target() -> Rect2:
	var view := get_viewport_rect().size
	if camera == null:
		return Rect2(view * 0.5, Vector2.ONE)
	var half := view * 0.5 / follow_zoom
	var aim := camera.global_position
	var centre := Vector2(
		clampf(aim.x, camera.limit_left + half.x, maxf(camera.limit_left + half.x, camera.limit_right - half.x)),
		clampf(aim.y, camera.limit_top + half.y, maxf(camera.limit_top + half.y, camera.limit_bottom - half.y)))
	return Rect2(centre, Vector2.ONE * follow_zoom)


# The shot's camera while it plays (null otherwise) - for the checks.
func intro_camera() -> Camera2D:
	return _intro_camera


# --- THE GO DROP ----------------------------------------------------------------
# Before GO the mortals are not on the field: through the intro dialogue, the
# "3 - 2 - 1" and the intro shot every mortal on this screen (this one's, the
# ghosts, a solo game's bots) draws nothing, while its body waits on its spawn
# point as ever. At GO they fall from above the top of the view onto those points,
# drop_time seconds in all: each mortal's sprite (and the tag, glow and stars that
# ride over it) is lifted by Mortal.drop_offset, accelerating down to land at about
# 0.9 of the second (staggered by peer id, so every screen casts the same order),
# squashes and puffs dust on landing and settles. The shadow stays on the ground
# all along, growing from small and faint, so everyone can see where they will
# land. Once the last one is down the map shakes once (_shake_screen, so Settings >
# screen shake rules it and only the field moves). The GO banner stays over it.
#
# Look only: no body moves and no position is sent. What it does change is when
# the round starts: the host's phase stays the countdown's through the drop, so the
# mortals stay locked, the clock stays at the full round and nothing that waits for
# PLAYING (the god's rules, the clones, Tala) runs, then _start_trial opens the
# round and everything begins together. Nothing new is sent either - a client
# reads `drop_left` off the host's world tick that already carries the phase and the
# clock, plays the same fall from there and walks into the round when the host says
# PLAYING. A later round's GO (Bathala's) holds its mortals the same way
# (hold_mortals_for_drop) and calls begin_drop itself; there _tick_trial rests
# while the drop lasts. Not in the prep area, not for a mortal that joins mid-round.
# Settings > Gameplay > Intro camera (the one switch for the cinematics) skips it.

const DROP_FALL_SHARE := 0.78   # of drop_time the fall takes, from a mortal's own start
const DROP_STAGGER := 0.12      # of drop_time between the first mortal to fall and the last
const DROP_MARGIN := 100.0      # px a mortal starts above the view's top edge (sprite and tag clear)
const DROP_SHAKE_TIME := 0.25
const DROP_SHAKE_POWER := 0.6


func drop_applies() -> bool:
	return drop_enabled and drop_time > 0.0 and intro_camera_allowed()


func drop_active() -> bool:
	return _drop_left > 0.0


# Every mortal the drop lifts on this screen: id -> mortal. The arenas with bodies
# of their own that a mortal scene wears (Langit Lupa's bots) add them.
func drop_mortals() -> Dictionary:
	var all := {_my_id: player}
	for id in _ghosts.keys():
		if is_instance_valid(_ghosts[id]):
			all[int(id)] = _ghosts[id]
	return all


# A GO that is not the trial's first: the mortals leave the field until it.
func hold_mortals_for_drop() -> void:
	_drop_seen = false
	_drop_waiting = drop_applies()


# The host's GO: the drop begins (false: no drop here, the round starts at once).
func begin_drop() -> bool:
	if not drop_applies():
		return false
	_drop_left = drop_time
	_drop_waiting = false
	_drop_seen = true
	_cast_drop()
	return true


# A client's first sight of the host's drop, and the host's word on how long is left.
func _read_drop(left: float) -> void:
	if _authority or left <= 0.0 or not drop_applies():
		return
	if not _drop_seen:
		_drop_seen = true
		_drop_left = left
		_drop_waiting = false
		_cast_drop()
	elif _drop_left > 0.0 and absf(left - _drop_left) > 0.25:
		_drop_left = left  # drifted: the host's word wins


# Who falls, in what order and from how high: sorted by peer id, so every screen
# agrees; from above whatever this screen shows (the follow camera's view, or the arena).
func _cast_drop() -> void:
	_drop_cast.clear()
	_drop_shaken = false
	var mortals := drop_mortals()
	var ids := mortals.keys()
	ids.sort()
	var top := _view_top()
	for rank in range(ids.size()):
		var mortal: ArenaMortal = mortals[ids[rank]]
		var share := 0.0 if ids.size() < 2 else float(rank) / float(ids.size() - 1)
		_drop_cast[ids[rank]] = {
			"delay": DROP_STAGGER * drop_time * share,
			"lift": maxf(mortal.global_position.y - top + DROP_MARGIN, DROP_MARGIN),
			"landed": false,
		}


# The world y of the view's top edge.
func _view_top() -> float:
	if camera != null and camera.is_inside_tree():
		return camera.get_screen_center_position().y - get_viewport_rect().size.y * 0.5 / camera.zoom.y
	return 0.0


# Every frame: the drop's clock, then what each mortal looks like.
func _tick_drop(delta: float) -> void:
	if _drop_left > 0.0:
		_drop_left = maxf(0.0, _drop_left - delta)
	var applies := drop_applies()
	var dropping := applies and _drop_left > 0.0 and not _drop_cast.is_empty()
	var waiting := applies and not dropping and (_drop_waiting or (not _drop_seen and (_phase == Phase.INTRO or _phase == Phase.COUNTDOWN)))
	var elapsed := drop_time - _drop_left
	var fall := drop_time * DROP_FALL_SHARE
	var down := true
	var mortals := drop_mortals()
	for id in mortals.keys():
		var mortal: ArenaMortal = mortals[id]
		if dropping and _drop_cast.has(id):
			var cast: Dictionary = _drop_cast[id]
			var t := elapsed - float(cast["delay"])
			if t < fall:
				var u := clampf(t / fall, 0.0, 1.0)
				mortal.drop_offset = Vector2(0.0, -float(cast["lift"]) * (1.0 - u * u))  # accelerating: it falls ever faster
				mortal.drop_shadow = u
				mortal.drop_hidden = false
				down = false
				continue
			mortal.drop_offset = Vector2.ZERO
			mortal.drop_shadow = 1.0
			mortal.drop_hidden = false
			if not bool(cast["landed"]):
				cast["landed"] = true
				mortal.land()
			continue
		mortal.drop_offset = Vector2.ZERO
		mortal.drop_shadow = 1.0
		mortal.drop_hidden = waiting
	if dropping and down and not _drop_shaken:
		_drop_shaken = true  # the last one is down: one shake of the map
		_shake_screen(DROP_SHAKE_TIME, DROP_SHAKE_POWER)


# Nothing held, nothing falling: every mortal as it always is.
func _reset_drop() -> void:
	_drop_left = 0.0
	_drop_waiting = false
	_drop_seen = false
	_drop_shaken = false
	_drop_cast.clear()
	for mortal in drop_mortals().values():
		mortal.drop_offset = Vector2.ZERO
		mortal.drop_shadow = 1.0
		mortal.drop_hidden = false


func _set_hud_alpha(alpha: float) -> void:
	hud_alpha = alpha
	if hud == null:
		return
	for part in [^"StatsPanel", ^"TrialPanel", ^"TopRight", ^"EventLabel", ^"SkillCards"]:
		var node := hud.get_node_or_null(part) as CanvasItem
		if node != null:
			node.modulate.a = alpha


# --- TAPPABLE FAVOR PANELS ---------------------------------------------------
# Panels that answer a click the way the slot's key does: the arena's own HUD
# registers its two bars, and an embedded run's shell registers its own (they
# are the ones on screen then). One panel per slot; the last registration wins,
# which is exactly right - the shell's bars replace the HUD's hidden ones.

var _tap_panels: Dictionary = {}   # slot -> Control


func register_tap_panel(slot: int, panel: Control) -> void:
	if panel != null:
		_tap_panels[slot] = panel
	else:
		_tap_panels.erase(slot)


func tap_panel(slot: int) -> Control:
	return _tap_panels.get(slot, null)


func _tap_panel_at(slot: int, point: Vector2) -> bool:
	var panel: Control = tap_panel(slot)
	return panel != null and is_instance_valid(panel) and panel.is_visible_in_tree() \
		and panel.get_global_rect().has_point(point)


func _tap_panel_click(event: InputEvent) -> bool:
	# A click on one of the favor panels is the panel's business, never the
	# world's attack. Every arena's own _input calls this first and stops when
	# it answers: during play only, exactly like the keyboard path, and the
	# click is marked handled so nothing downstream reads it either.
	if not (event is InputEventMouseButton) or not event.pressed:
		return false
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	# A click on the skill popup closes it - and is never a swing, whatever the phase.
	if hud != null and hud.click_skill_popup(event.position):
		var popup_viewport := get_viewport()
		if popup_viewport != null:
			popup_viewport.set_input_as_handled()
		return true
	if _phase != Phase.PLAYING or dialogue.is_active() or due_menu.is_open():
		return false
	for slot in _tap_panels.keys():
		if _tap_panel_at(int(slot), event.position):
			_use_skill(int(slot))
			var viewport := get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	# Keep the viewport handy: some branches below switch/restart the scene and
	# this node (and get_viewport()) would be gone by the time we mark the event.
	var viewport := get_viewport()
	if viewport == null:
		return
	if event.is_action_pressed("ui_cancel"):
		viewport.set_input_as_handled()
		_leave()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		viewport.set_input_as_handled()
		get_tree().reload_current_scene()
		return
	if event.is_action_pressed("due_menu"):
		if _phase != Phase.COUNTDOWN:
			_toggle_due_menu()
		viewport.set_input_as_handled()
		return
	if dialogue.is_active() or due_menu.is_open():
		return
	match _phase:
		Phase.PLAYING:
			if event.is_action_pressed("skill_e"):
				_use_skill(GodFavor.Slot.E)
			elif event.is_action_pressed("skill_q"):
				_use_skill(GodFavor.Slot.Q)
			elif dash_enabled and event.is_action_pressed("dash"):
				# SPACE is also advance_dialogue: during play it only ever dashes.
				viewport.set_input_as_handled()
				if not try_dash() and not player.locked:
					_dash_buffered = dash_buffer
		Phase.RESULTS:
			if event.is_action_pressed("advance_dialogue"):
				viewport.set_input_as_handled()
				# Embedded in the Game shell: hand the run back so it can load the
				# next god's arena. Standalone: just play the trial again.
				if embedded:
					trial_complete.emit()
				else:
					get_tree().reload_current_scene()
		_:
			pass


func _leave() -> void:
	if embedded:
		return
	# In a networked run everyone goes back to the lobby; solo goes to the menu.
	if _networked:
		get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
