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
#   * THE DIALOGUE AND THE MENUS: the god's intro lines, the closing lines, the
#     God's Due menu and the handshake that keeps every peer on the same line.
#
#   * FAVOR POPUPS: the light yellow "+41 FAVOR" that floats off a mortal's head
#     while a zone pays, and the same popup in its loss colour when something
#     takes FAVOR away (UI/Popups/favor_popup.tscn, spawn_popup()/favor_popup()).
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
#
# Solo: this scene simulates everything.
# Multiplayer: the HOST is authoritative and is the only clock. It broadcasts
# the round - phase, seconds, the arena's own state at 10 Hz and FAVOR snapshots
# at 5 Hz. Every client sends its mortal's position and mirrors whatever the host
# sends, so all the screens show the same second and the same world.

signal trial_complete
signal trial_time_changed(seconds: float)

const UI_STRIP_WIDTH := 238.0

# The colour a favor zone glows while a god is lighting it.
const FAVOR_COLOR := Color(1.0, 0.86, 0.25)

const HUD_SCENE := preload("res://UI/GodsArena/god_hud.tscn")
const DIALOGUE_SCENE := preload("res://UI/GodsArena/god_dialogue.tscn")
const DUE_MENU_SCENE := preload("res://UI/GodsArena/gods_due_menu.tscn")
const MORTAL_SCENE := preload("res://scenes/gods/common/Mortal.tscn")
const POPUP_SCENE := preload("res://UI/Popups/favor_popup.tscn")
const TEMP_ICON := preload("res://icon.svg")

# A FAVOR popup: light yellow when FAVOR arrives, light red when it is taken.
const POPUP_GAIN_COLOR := Color(1.0, 0.96, 0.62)
const POPUP_LOSS_COLOR := Color(1.0, 0.55, 0.45)
const POPUP_OFFSET := Vector2(0.0, -42.0)   # above the mortal's head

const DIALOGUE_TIMEOUT := 20.0

enum Phase { INTRO, COUNTDOWN, PLAYING, RESULTS }

@export_category("Identity")
@export var god_id: StringName = &"mayari"
# Set by the Game shell when the arena runs as one of its trials: the shell
# draws the shared panels and the arena hides its duplicates.
@export var embedded := false
@export var dialogue_prefix := "mayari"

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

@export_category("Knockback")
# What a hit does to a mortal: no control for this long, shoved at this speed.
@export var knock_stun := 1.3
@export var knock_force := 560.0

@export_category("Network")
@export var net_tick_rate := 10.0    # world state broadcasts per second
@export var net_state_rate := 5.0    # FAVOR snapshots per second
@export var layout_repeat := 2.0     # seconds between layout re-broadcasts

@export_category("FAVOR Popups")
@export var popups_enabled := true
# Small gains are gathered and shown as one popup every `popup_flush` seconds
# (a lit zone pays many times a second - one popup each would be unreadable).
@export var popup_flush := 0.5
# A change of at least this many FAVOR pops at once instead of waiting.
@export var popup_big_delta := 20

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

var god: God
var rules: GodMatch
var hud: Control
var dialogue: Control
var due_menu: Control

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
var _results: Dictionary = {}
var _gain_pending: Dictionary = {}    # mortal id -> FAVOR gathered, not popped yet
var _gain_timer := 0.0

# --- multiplayer ---
var _net: Node = null
var _networked := false
var _authority := true
var _my_id := GodMatch.LOCAL_ID
var _mortal_positions: Dictionary = {}  # peer id -> Vector2
var _ghosts: Dictionary = {}            # peer id -> ghost mortal
var _net_tick := 0.0
var _state_tick := 0.0
var _layout_age := 0.0
var _last_banner := ""
var _last_event := ""
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
	add_child(rules)
	if _networked:
		rules.setup_peers(god, _peer_names(), _my_id, false)
	else:
		rules.setup(god, _mortal_name(), Array(rival_names) if simulate_rivals else [], simulate_rivals)
	rules.favor_changed.connect(_on_favor_changed)
	rules.due_earned.connect(_on_due_earned)
	rules.notice.connect(_on_notice)

	hud = HUD_SCENE.instantiate()
	ui_layer.add_child(hud)
	if embedded:
		hud.get_node("StatsPanel").visible = false
		hud.get_node("LeaderPanel").visible = false
		hud.get_node("TrialPanel").visible = false
		hud.get_node("EventLabel").visible = false
		hud.get_node("BannerLabel").visible = false

	dialogue = DIALOGUE_SCENE.instantiate()
	ui_layer.add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)

	due_menu = DUE_MENU_SCENE.instantiate()
	ui_layer.add_child(due_menu)
	due_menu.favor_chosen.connect(_on_favor_chosen)

	# The spawn is authored in the scene - remember it so every round starts from
	# the drawn spot (never from arithmetic on a rect).
	_start_position = player.global_position
	_read_field()
	player.set_display_name(_mortal_name(), god.color)
	hud.bind(rules, god)
	_connect_network()
	_sync_ghosts()
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
	# blindness mask - the field stays exactly where the designer drew it.
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
	player.ring_color = tint
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


# --- MULTIPLAYER: layout sync -----------------------------------------------

func _publish_layout() -> void:
	if not _networked or not _authority or _net == null:
		return
	var layout := {"field": _field}
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
	collect_units()
	arena_read_layout(layout)


# --- FLOW -------------------------------------------------------------------

func _start_intro() -> void:
	_phase = Phase.INTRO
	player.set_lock(true)
	dialogue.show_lines(_speech(god, god.intro_lines), TEMP_ICON)


func _start_countdown() -> void:
	_phase = Phase.COUNTDOWN
	_countdown = countdown_time
	_count_shown = -1
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
	arena_round_reset()


func _start_trial() -> void:
	_phase = Phase.PLAYING
	_trial_time = trial_time
	trial_time_changed.emit(_trial_time)
	_invuln.clear()
	_gain_pending.clear()
	_gain_timer = 0.0
	set_mortal_invuln(_my_id, spawn_immunity)
	_blind_time = 0.0
	player.set_lock(false)
	rules.trial_active = true
	_show_banner("GO!", god.color, 1.0)
	hud.set_time_left(_trial_time)


func _process(delta: float) -> void:
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
			if _authority:
				_countdown -= delta
				var shown := int(ceil(maxf(0.0, _countdown)))
				if shown != _count_shown:
					_count_shown = shown
					if shown > 0:
						_show_banner(str(shown), god.color, 1.0)
				if _countdown <= 0.0:
					_start_trial()
		Phase.PLAYING:
			if _authority:
				_tick_trial(delta)
			else:
				_client_tick(delta)
	# The host is the clock: it broadcasts the round it just advanced - phase,
	# seconds, where the mortals are, where the arena's own units walked - so
	# every client shows the same second and the same world.
	if _authority and _networked and _phase != Phase.INTRO:
		_publish_net_tick(delta)
	_flush_favor_popups(delta)
	_apply_blindness(delta)
	_move_ghosts(delta)


func _tick_trial(delta: float) -> void:
	# The shared part of one round: the clock runs down, the mercy seconds burn
	# off, and the arena's own rules get their frame.
	_trial_time -= delta
	trial_time_changed.emit(_trial_time)
	hud.set_time_left(_trial_time)
	_tick_invuln(delta)
	arena_rules_tick(delta)
	if _trial_time <= 0.0:
		_end_trial()


func _client_tick(delta: float) -> void:
	# Clients only report where their mortal is - the host keeps score.
	_net_tick -= delta
	if _net_tick > 0.0:
		return
	_net_tick = 1.0 / net_tick_rate
	if _net != null and _net.has_multiplayer_peer():
		_net.rpc_id(1, "report_mortal_position", player.global_position)


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
	_state_tick -= delta
	if _state_tick <= 0.0:
		_state_tick = 1.0 / net_state_rate
		_publish_god_state()


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
func lose_favor(amount: int, reason: String, mortal_id := -1) -> int:
	if rules == null or amount <= 0:
		return 0
	return rules.lose_favor(amount, reason, mortal_id)


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
#
# Our own mortal is ours to move, so this is where it is shoved. A rival's
# mortal is simulated on the rival's machine: the host only reports the hit and
# the owner does the shoving (_on_arena_hit_received below), so a client feels
# every hit the host scores, not just the ones it scored on itself.
func knock_mortal(mortal_id: int, from_position: Vector2, stun := 0.0, force := 0.0) -> void:
	if mortal_id == _my_id:
		var shove := player.global_position - from_position
		if shove.length() < 0.01:
			shove = Vector2.LEFT
		_apply_knockback(shove, stun, force)
		return
	if not (_authority and _networked and _net != null):
		return
	var position := mortal_position(mortal_id)
	if position == Vector2.INF:
		return
	var direction := position - from_position
	if direction.length() < 0.01:
		direction = Vector2.LEFT
	_net.send_arena_hit(mortal_id, {
		"direction": direction.normalized(),
		"stun": knock_stun if stun <= 0.0 else stun,
		"force": knock_force if force <= 0.0 else force,
	})


func _apply_knockback(direction: Vector2, stun := 0.0, force := 0.0) -> void:
	if player == null or not is_instance_valid(player):
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
	_apply_knockback(direction, float(hit.get("stun", 0.0)), float(hit.get("force", 0.0)))


# --- FAVOR POPUPS -----------------------------------------------------------

# A popup at `origin`: the scene draws it, the arena only says what and where.
# `icon_texture` is optional - hand one in and the popup carries the little
# image next to the number (UI/Popups/favor_popup.tscn).
func spawn_popup(text: String, tint: Color, origin: Vector2, icon_texture: Texture2D = null) -> Node2D:
	if popups_root == null or origin == Vector2.INF:
		return null
	var popup: Node2D = POPUP_SCENE.instantiate()
	popups_root.add_child(popup)
	# A small side-step, so two popups landing at once stay readable.
	popup.global_position = origin + Vector2(randf_range(-7.0, 7.0), 0.0)
	popup.show_favor(text, tint, icon_texture)
	return popup


# "+N FAVOR" over a mortal's head - light yellow - or the same popup in the loss
# colour when N is negative. `reason` is only put in the text when given.
func favor_popup(mortal_id: int, delta: int, reason := "") -> Node2D:
	if delta == 0:
		return null
	var suffix := "" if reason == "" else "   %s" % reason
	var text := "%s%d FAVOR%s" % ["+" if delta > 0 else "", delta, suffix]
	var tint := POPUP_GAIN_COLOR if delta > 0 else POPUP_LOSS_COLOR
	return spawn_popup(text, tint, popup_origin(mortal_id))


# Where a mortal's popups come off: our own mortal's head, or the ghost of a
# rival. Vector2.INF when we do not know where that mortal is.
func popup_origin(mortal_id: int) -> Vector2:
	if mortal_id == _my_id:
		return player.global_position + POPUP_OFFSET
	if _ghosts.has(mortal_id) and is_instance_valid(_ghosts[mortal_id]):
		return (_ghosts[mortal_id] as Node2D).global_position + POPUP_OFFSET
	var known := mortal_position(mortal_id)
	return Vector2.INF if known == Vector2.INF else known + POPUP_OFFSET


# Small gains are gathered and shown as one popup: a lit zone pays many times a
# second, so one popup per credit would be unreadable. Losses and big gains
# never wait (see _on_favor_changed).
func _flush_favor_popups(delta: float) -> void:
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

func _speech(speaker: God, lines: Array) -> Array:
	var out: Array = []
	for line in lines:
		out.append({"speaker": speaker.display_name, "color": speaker.color, "text": str(line)})
	return out


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
		return
	hud.show_results(_results, "TRIAL COMPLETE")
	if _free_grants > 0:
		hud.set_results_hint("F - CLAIM YOUR FREE FAVOR      SPACE - PLAY AGAIN      ESC - LEAVE")
	else:
		hud.set_results_hint("SPACE - PLAY AGAIN      ESC - LEAVE")


func _end_trial() -> void:
	_phase = Phase.RESULTS
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
	var mine := local_favor()
	var lines: Array = []
	var success := mine >= success_favor
	lines.append_array(_speech(god, god.success_lines if success else god.failure_lines))

	# God to the succeeding God, then the succeeding God to you.
	var next_god := Gods.next_god(god.id)
	_free_grants = 0
	if next_god != null:
		lines.append({
			"speaker": god.display_name, "color": god.color,
			"text": "%s, take the field." % next_god.display_name,
		})
		lines.append({
			"speaker": next_god.display_name, "color": next_god.color,
			"text": _opening_line(next_god),
		})
		lines.append({
			"speaker": next_god.display_name, "color": next_god.color,
			"text": "You gathered %d FAVOR in %s's game. %s" % [mine, god.display_name, _due_note()],
		})
		var mortal := rules.local()
		if mortal != null and mortal.due <= 0:
			# A god intervening between trials - a free favor.
			_free_grants = 1
			lines.append({
				"speaker": next_god.display_name, "color": next_god.color,
				"text": "You hold no God's Due. Take one favor of mine - press F.",
			})
	dialogue.show_lines(lines, TEMP_ICON)


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
			mortal.cooldowns[bound.id] = bound.cooldown
		if _net != null and _net.has_multiplayer_peer():
			_net.rpc_id(1, "request_god_skill", slot)
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
	if favor.id != &"half_vision":
		return
	var radius := favor.param("vision_radius", 0.16)
	var duration := maxf(0.0, favor.duration)
	if caster_id == _my_id:
		# The caster keeps both eyes: Half Vision blinds the OTHER mortals only.
		_log("Half Vision - everyone else sees only a circle around them", favor.color)
	else:
		_blind_radius = radius
		_blind_time = maxf(_blind_time, duration)
		_log("Half Vision - you see only a circle around your mortal", favor.color)
	if _authority and _networked and _net != null:
		_net.send_arena_blind(caster_id, radius, duration)


# Another mortal cast Half Vision: darken THIS screen (unless we are the caster).
func _on_arena_blind_received(caster_id: int, radius: float, duration: float) -> void:
	if _authority or caster_id == _my_id or duration <= 0.0:
		return
	_blind_radius = radius
	_blind_time = maxf(_blind_time, duration)
	_log("Half Vision - you see only a circle around your mortal", god.color)


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
		# Ask the host - the next FAVOR snapshot updates our favor list.
		if _free_grants > 0:
			_free_grants -= 1
		if _net != null and _net.has_multiplayer_peer():
			_net.rpc_id(1, "request_god_grant", favor.id)
	_show_banner("%s GRANTED" % favor.display_name.to_upper(), favor.color, 1.6)
	_log("%s now belongs to you" % favor.display_name, favor.color)


# --- HUD HELPERS ------------------------------------------------------------

func _show_banner(text: String, color: Color, duration := 2.0) -> void:
	if hud != null:
		hud.show_banner(text, color, duration)


func _log(text: String, color: Color) -> void:
	if hud != null:
		hud.log_event(text, color)


# --- NETWORK ----------------------------------------------------------------

func _connect_network() -> void:
	if _net == null:
		return
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
	if _net.has_signal("arena_hit_received"):
		_net.connect("arena_hit_received", _on_arena_hit_received)
	if _net.has_signal("arena_blind_received"):
		_net.connect("arena_blind_received", _on_arena_blind_received)
	_net.player_left.connect(_on_peer_left)
	if _net.has_signal("dialogue_released"):
		_net.connect("dialogue_released", _on_dialogue_released)
	if _authority:
		_net.god_favor_requested.connect(_on_god_favor_requested)
		_net.god_skill_requested.connect(_on_god_skill_requested)
		_net.god_grant_requested.connect(_on_god_grant_requested)
	else:
		_net.rpc_id(1, "request_god_state")


func _on_player_list_updated(_players: Dictionary) -> void:
	# The roster can arrive after this arena was built (a client always races the
	# first list) and it can change mid-trial, so the rivals on the field are
	# built from it every time instead of once at start-up.
	_sync_ghosts()


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
		player.set_display_name(clean, god.color)
	elif _ghosts.has(peer_id) and is_instance_valid(_ghosts[peer_id]):
		_ghosts[peer_id].set_display_name(clean, god.color)


func _sync_ghosts() -> void:
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
		ghost.ring_color = god.color
		ghost.set_display_name(str(names[pid]), god.color)
		_ghosts[id] = ghost
	for id in _ghosts.keys().duplicate():
		if not names.has(int(id)):
			_ghosts[id].queue_free()
			_ghosts.erase(id)


func _move_ghosts(delta: float) -> void:
	# Remote mortals glide towards whatever position the host last reported.
	var weight := clampf(delta * 12.0, 0.0, 1.0)
	for id in _ghosts.keys():
		var ghost: Node2D = _ghosts[id]
		if not is_instance_valid(ghost) or not _mortal_positions.has(int(id)):
			continue
		ghost.global_position = ghost.global_position.lerp(_mortal_positions[int(id)], weight)


func _publish_god_state() -> void:
	if _net == null or not _networked or not _authority:
		return
	_net.publish_god_state(rules.snapshot())


func _publish_arena_tick() -> void:
	if _net == null or not _authority:
		return
	_mortal_positions[_my_id] = player.global_position
	var reported: Dictionary = _net.mortal_positions
	for id in reported.keys():
		_mortal_positions[int(id)] = reported[id]
	# Everything every arena broadcasts, plus whatever the god's own arena adds.
	var state := {
		"phase": int(_phase),
		"trial_time": _trial_time,
		"mortals": _mortal_positions.duplicate(),
		"banner": hud.banner_label.text if hud.banner_label.visible else "",
		"banner_color": hud.banner_label.get_theme_color("font_color"),
		"event": hud.event_label.text,
		"event_color": hud.event_label.get_theme_color("font_color"),
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


func _apply_arena_tick(state: Dictionary) -> void:
	# The host's round, mirrored: the same second on the clock, where the mortals
	# are and whatever the god's own arena put on the wire.
	var remote_phase := int(state.get("phase", int(_phase)))
	_trial_time = float(state.get("trial_time", _trial_time))
	# The shell's clock (Game.gd) reads this signal - without it a client's clock
	# would sit still while the host's runs.
	trial_time_changed.emit(_trial_time)
	hud.set_time_left(_trial_time)

	var mortals: Dictionary = state.get("mortals", {})
	_mortal_positions.clear()
	for id in mortals.keys():
		_mortal_positions[int(id)] = mortals[id]
	arena_read_tick(state)

	# Follow the host through the trial phases.
	if remote_phase == int(Phase.RESULTS) and _phase != Phase.RESULTS:
		_end_trial()
	elif remote_phase == int(Phase.PLAYING) and _phase != Phase.PLAYING and _phase != Phase.RESULTS:
		_enter_playing()
	elif remote_phase == int(Phase.COUNTDOWN) and _phase == Phase.INTRO:
		_phase = Phase.COUNTDOWN

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
	_show_banner("%d FAVOR - GOD'S DUE EARNED" % milestone, Color(1, 0.9, 0.45), 2.2)
	_log("You reached %d FAVOR - one God's Due is yours (press F to spend it)" % milestone, Color(1, 0.9, 0.45))


func _on_notice(text: String) -> void:
	_log(text, Color(0.85, 0.85, 0.9))


# --- BLINDNESS / INPUT ------------------------------------------------------

func _apply_vision_mask() -> void:
	var material := vision_mask.material as ShaderMaterial
	if material == null:
		return
	var view := get_viewport_rect().size
	material.set_shader_parameter("aspect", view.x / maxf(1.0, view.y))
	material.set_shader_parameter("radius", _blind_radius)
	vision_mask.visible = false


func _apply_blindness(delta: float) -> void:
	_blind_time = maxf(0.0, _blind_time - delta)
	var active := _blind_time > 0.0
	if vision_mask.visible != active:
		vision_mask.visible = active
	if not active:
		return
	var material := vision_mask.material as ShaderMaterial
	if material == null:
		return
	var view := vision_mask.size
	var mortal_pos := player.global_position
	material.set_shader_parameter("center", Vector2(mortal_pos.x / maxf(1.0, view.x), mortal_pos.y / maxf(1.0, view.y)))
	material.set_shader_parameter("radius", _blind_radius)


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
