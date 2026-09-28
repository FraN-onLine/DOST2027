class_name MayariArena
extends GodArena

# MAYARI - patintero, and nothing else yet.  (scripts/gods/mayari + scenes/gods/mayari)
#
# One arena, four favor zones, exactly TWO Mayaris and one minute thirty:
#   * The four goals are the favor zones. Only the ONE Mayari is lighting burns
#     - yellow - and only that one pays: every other zone draws nothing at all
#     and is invisible on screen.
#   * The two clones (one horizontal, one vertical, authored in
#     MayariArena.tscn) walk the Line2D path drawn on each of them and never
#     leave it.
#   * Every so often a clone stops patrolling and hunts the nearest mortal: it
#     still walks its own line, it just walks it towards whoever is closest.
#   * A clone touching a mortal costs that mortal FAVOR.
#   * Standing in the lit zone banks FAVOR until the clock runs out
#     (GodArena.trial_time - the 1:30 shared by every arena).
# That is the whole game. Everything else comes later, in due time.
#
# The arena owns no art: MayariArena.tscn holds the backdrop, the field, its
# border and the patintero lines, the four favor zones (MayariGoal.tscn), the
# two clones (MayariClone.tscn) and the mortal (Mortal.tscn). The scene is
# authored in screen space for real play (see scripts/gods/god_arena.gd): the
# left strip stays empty for the Game shell's panels, and the drawn border IS
# the field. This script only runs the rules - nothing here draws and nothing
# here re-lays-out the scene, so the editor layout is the played one.
#
# Solo: this scene simulates everything.
# Multiplayer: the HOST is authoritative and is the only clock. It broadcasts
# the round - phase, seconds, the lit zone, where the clones have walked and
# where the mortals are - at 10 Hz, plus FAVOR snapshots at 5 Hz. Every client
# sends its mortal's position and mirrors whatever the host sends, so all the
# screens show the same second, the same lit zone and the same two Mayaris.

signal trial_complete
signal trial_time_changed(seconds: float)

const HUD_SCENE := preload("res://UI/GodsArena/god_hud.tscn")
const DIALOGUE_SCENE := preload("res://UI/GodsArena/god_dialogue.tscn")
const DUE_MENU_SCENE := preload("res://UI/GodsArena/gods_due_menu.tscn")
const MORTAL_SCENE := preload("res://scenes/gods/common/Mortal.tscn")
const TEMP_ICON := preload("res://icon.svg")

@export_category("Identity")
@export var god_id: StringName = &"mayari"
# Set by the Game shell when the arena runs as one of its trials: the shell
# draws the shared panels and the arena hides its duplicates.
@export var embedded := false
@export var dialogue_prefix := "mayari"

# The round clock (1:30) and the countdown are NOT declared here: they come
# from the shared arena base - GodArena.trial_time / GodArena.countdown_time -
# which is the one place every arena's time is edited.
@export_category("Trial Rules")
@export var favor_rate := 26.0                 # FAVOR banked per second in the lit zone
@export var clone_penalty := 50                # FAVOR lost when a clone touches a mortal
const INVULN_TIME := 1.2                       # mercy seconds after a touch
@export_range(0, 3, 1) var starting_zone := 3  # the zone Mayari lights first
@export var goal_switch_interval := 12.0       # seconds before the light moves on
@export var success_favor := 1000              # FAVOR the closing lines call a success
const NET_TICK_RATE := 10.0
const NET_STATE_RATE := 5.0
const LAYOUT_REPEAT := 2.0

# Solo-only placeholders so the leaderboard and rivalry rules have rivals.
const SIMULATE_RIVALS := true
const RIVAL_MORTALS := ["MORTAL 2", "MORTAL 3"]

enum Phase { INTRO, COUNTDOWN, PLAYING, RESULTS }

@onready var field_root: MayariArenaField = $ArenaField
@onready var zones_root: Node2D = $Zones
@onready var clones_root: Node2D = $Clones
@onready var ghosts_root: Node2D = $Ghosts
@onready var player: ArenaMortal = $Player
@onready var ui_layer: CanvasLayer = $UILayer
@onready var vision_mask: ColorRect = $VisionLayer/VisionMask

var god: God
var rules: GodMatch
var hud: Control
var dialogue: Control
var due_menu: Control

var _zones: Array = []
var _clones: Array = []
var _ghosts: Dictionary = {}          # peer id -> ghost mortal
var _field := Rect2()
# The mortal's authored spawn: every round of the trial starts here.
var _start_position := Vector2.ZERO
var _phase := Phase.INTRO
var _trial_time := 0.0
var _countdown := 0.0
var _count_shown := -1
var _zone_pending: Dictionary = {}    # mortal id -> fractional FAVOR not banked
var _invuln: Dictionary = {}          # mortal id -> seconds of mercy left
var _blind_time := 0.0                # Half Vision favor only
var _blind_radius := 0.16
var _free_grants := 0
var _results: Dictionary = {}
var _active_goal_index := 3
var _goal_switch_timer := 0.0

# --- multiplayer ---
var _net: Node = null
var _networked := false
var _authority := true
var _my_id := GodMatch.LOCAL_ID
var _mortal_positions: Dictionary = {}  # peer id -> Vector2
var _net_tick := 0.0
var _state_tick := 0.0
var _layout_age := 0.0
var _last_banner := ""
var _last_event := ""
var _dialogue_waiting := false
var _dialogue_wait_id := ""
var _dialogue_wait_time := 0.0
const DIALOGUE_TIMEOUT := 20.0


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
		rules.setup(god, _mortal_name(), RIVAL_MORTALS if SIMULATE_RIVALS else [], SIMULATE_RIVALS)
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
	_apply_field()
	player.set_display_name(_mortal_name(), god.color)
	hud.bind(rules, god)
	_connect_network()
	_sync_ghosts()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_start_intro()


func _detect_networked() -> bool:
	# A lone host plays exactly like solo - only real company switches on the
	# network code paths.
	if _net == null or not _net.has_multiplayer_peer():
		return false
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

func _apply_field() -> void:
	# The scene owns the layout (see scripts/gods/god_arena.gd): the field rect is
	# read back from the border line the designer drew, and the favor zones, the
	# clones and the mortal keep the positions and sizes they were authored with.
	# Only the rules need a number out of it - the mortal's walking bounds - so
	# every player reads the same authored screen.
	_field = field_root.authored_rect()
	var tint: Color = god.color if god != null else Color.WHITE
	field_root.apply_tint(tint)
	player.bounds = _field
	player.ring_color = tint
	_apply_vision_mask()
	# Both lists are built on EVERY peer: the zones and the clones are the
	# authored scene nodes, so each screen already has the same boxes and the
	# same two Mayaris. Only the lit one and the walked positions travel.
	_collect_zones()
	_collect_clones()
	if _authority:
		_light_zone(starting_zone)
		_publish_layout()


func _collect_zones() -> void:
	# The four goals are authored scene nodes and they are only ever lit: their
	# place and their box size come from the scene, so the boxes drawn in the
	# editor are the boxes the mortals hold. Started dark - whoever is
	# authoritative lights one in _light_zone().
	_zones.clear()
	for node in zones_root.get_children():
		var zone: MayariGoal = node
		zone.sync_authored_size()
		zone.rate = favor_rate
		zone.set_active(false)
		_zones.append(zone)
	_goal_switch_timer = goal_switch_interval


# Exactly one zone burns at a time: Mayari lights one and every other zone goes
# dark - invisible and paying nothing.
func _light_zone(index: int) -> void:
	if _zones.is_empty():
		return
	_active_goal_index = clampi(index, 0, _zones.size() - 1)
	for i in range(_zones.size()):
		_zones[i].set_active(i == _active_goal_index)


func _collect_clones() -> void:
	# Exactly TWO Mayaris, both authored in the scene: one horizontal, one
	# vertical. Each one walks the Line2D path drawn on it (MayariClone.gd), so
	# there is nothing to lay out here - only the colour the clones burn in and
	# which side is allowed to move them.
	_clones.clear()
	for node in clones_root.get_children():
		var clone: MayariClone = node
		clone.color = god.color
		clone.set_moving(_authority)
		_clones.append(clone)
	if _clones.size() != 2:
		push_warning("MayariArena: the arena wants exactly 2 authored clones, found %d" % _clones.size())


# --- MULTIPLAYER: layout sync -----------------------------------------------

func _zone_definition(zone: MayariGoal) -> Dictionary:
	# Local coordinates: every peer owns the same authored scene, so the same
	# child index sits at the same spot on every screen and the same box has the
	# same size. The one thing that is NOT in the scene is which zone Mayari is
	# lighting, so that single bit is all that travels.
	return {"lit": zone.favor_enabled}


func _publish_layout() -> void:
	if not _networked or not _authority or _net == null:
		return
	var zones: Array = []
	for zone in _zones:
		if is_instance_valid(zone):
			zones.append(_zone_definition(zone))
	_net.publish_arena_layout({
		"field": _field,
		"active_goal": _active_goal_index,
		"zones": zones,
	})


func _apply_layout(layout: Dictionary) -> void:
	# Clients play on the host's field so everybody shares the same coordinates,
	# and on the host's light. Both read the same authored scene, so the boxes,
	# the two paths and the mortal are already right - only the lit zone changes.
	_field = layout.get("field", _field)
	var tint: Color = god.color if god != null else Color.WHITE
	field_root.apply_tint(tint)
	player.bounds = _field
	_collect_zones()
	var definitions: Array = layout.get("zones", [])
	for index in range(mini(definitions.size(), _zones.size())):
		var definition: Dictionary = definitions[index]
		var lit := bool(definition.get("lit", definition.get("favor_enabled", false)))
		if lit:
			_active_goal_index = index
		_zones[index].set_active(lit)
	if definitions.is_empty():
		_light_zone(int(layout.get("active_goal", _active_goal_index)))
	# The clones are the authored ones on every peer: a client only mirrors the
	# positions the host sends, it never walks them itself.
	_collect_clones()


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
	# 3 - 2 - 1, and the host broadcasts it, so every screen shows 1:30 here.
	_trial_time = trial_time
	trial_time_changed.emit(_trial_time)
	hud.set_time_left(_trial_time)
	# Back to the spot the designer drew the mortal on, and both Mayaris back to
	# the start of their paths, so every round begins the same way.
	player.global_position = _start_position
	for clone in _clones:
		if is_instance_valid(clone) and clone.self_moving:
			clone.restart()


func _start_trial() -> void:
	_phase = Phase.PLAYING
	_trial_time = trial_time
	trial_time_changed.emit(_trial_time)
	_zone_pending.clear()
	_invuln.clear()
	_invuln[_my_id] = 1.0
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
	# seconds, the lit zone every two seconds, where the clones walked and where
	# the mortals are - so every client shows the same second and the same light.
	if _authority and _networked and _phase != Phase.INTRO:
		_publish_net_tick(delta)
	_apply_blindness(delta)
	_move_ghosts(delta)


func _tick_trial(delta: float) -> void:
	# One round, start to finish: the clock runs down, the light moves on, the
	# lit zone pays and Mayari costs FAVOR to whoever she touches.
	_trial_time -= delta
	trial_time_changed.emit(_trial_time)
	hud.set_time_left(_trial_time)
	_tick_invuln(delta)
	_goal_switch_timer -= delta
	if _goal_switch_timer <= 0.0:
		_advance_active_goal()
	# Where the mortals are, so a clone can decide to hunt the nearest one.
	_feed_clones()
	_check_goals(delta)
	_check_clones()
	if _trial_time <= 0.0:
		_end_trial()


func _client_tick(delta: float) -> void:
	# Clients only report where their mortal is - the host keeps score.
	_net_tick -= delta
	if _net_tick > 0.0:
		return
	_net_tick = 1.0 / NET_TICK_RATE
	if _net != null and _net.has_multiplayer_peer():
		_net.rpc_id(1, "report_mortal_position", player.global_position)


# Mayari moves her light from corner to corner: exactly one goal pays at a time.
func _advance_active_goal() -> void:
	if _zones.is_empty():
		return
	_light_zone((_active_goal_index + 1) % _zones.size())
	_goal_switch_timer = goal_switch_interval
	_log("Mayari's light moves to the %s" % str(_zones[_active_goal_index].zone_label), god.color)
	_publish_layout()


# Where every mortal stands - a clone that is allowed to walk uses it to hunt
# the nearest one (MayariClone.gd). Only the host feeds it: a client's clones
# are driven by the positions the host sends.
func _feed_clones() -> void:
	var mortals := PackedVector2Array()
	for entry in _mortal_entries():
		mortals.append(entry["pos"])
	for clone in _clones:
		if is_instance_valid(clone):
			clone.set_targets(mortals)


func _tick_invuln(delta: float) -> void:
	for id in _invuln.keys():
		_invuln[id] = maxf(0.0, float(_invuln[id]) - delta)


func _publish_net_tick(delta: float) -> void:
	if not _networked or _net == null:
		return
	_layout_age += delta
	if _layout_age >= LAYOUT_REPEAT:
		_layout_age = 0.0
		_publish_layout()
	_net_tick -= delta
	if _net_tick <= 0.0:
		_net_tick = 1.0 / NET_TICK_RATE
		_publish_arena_tick()
	_state_tick -= delta
	if _state_tick <= 0.0:
		_state_tick = 1.0 / NET_STATE_RATE
		_publish_god_state()


# --- SCORING ----------------------------------------------------------------

func _check_goals(delta: float) -> void:
	# Only the lit corner pays; holding it banks FAVOR over time.
	for zone in _zones:
		if is_instance_valid(zone):
			zone.held = false
	for entry in _mortal_entries():
		var mortal_id := int(entry["id"])
		var position: Vector2 = entry["pos"]
		var best: MayariGoal = null
		for zone in _zones:
			if not is_instance_valid(zone):
				continue
			if not zone.favor_enabled or not zone.contains(position):
				continue
			zone.held = true
			if best == null or float(zone.rate) > float(best.rate):
				best = zone
		if best == null:
			continue
		var pending := float(_zone_pending.get(mortal_id, 0.0)) + float(best.rate) * delta
		while pending >= 1.0:
			pending -= 1.0
			rules.add_favor(best.favor_amount, "holding the %s" % str(best.zone_label), mortal_id)
		_zone_pending[mortal_id] = pending


func _check_clones() -> void:
	for entry in _mortal_entries():
		var mortal_id := int(entry["id"])
		if float(_invuln.get(mortal_id, 0.0)) > 0.0:
			continue
		var position: Vector2 = entry["pos"]
		for clone in _clones:
			if not is_instance_valid(clone):
				continue
			if clone.hits(position, player.radius):
				_on_clone_hit(clone, mortal_id, position)
				break


func _on_clone_hit(clone: MayariClone, mortal_id: int, position: Vector2) -> void:
	_invuln[mortal_id] = INVULN_TIME
	var lost := rules.lose_favor(clone_penalty, "Mayari's clone", mortal_id)
	if mortal_id != _my_id:
		if lost > 0:
			_log("%s was caught by a clone  (-%d FAVOR)" % [_mortal_label(mortal_id), lost], Color(1, 0.6, 0.5))
		return
	var knock := position - clone.global_position
	if knock.length() < 0.01:
		knock = Vector2.LEFT
	player.hit(knock, 1.3, 470.0)
	if lost > 0:
		player.show_floating_text("-%d FAVOR" % lost, Color(1, 0.45, 0.4))
		_log("Mayari's clone caught you  (-%d FAVOR)" % lost, Color(1, 0.5, 0.45))
	else:
		_show_banner("FAVOR SHIELDED", god.color, 1.2)
		_log("A clone caught you but your favor held", god.color)


# --- MORTAL LOOKUP ----------------------------------------------------------

func _mortal_entries() -> Array:
	# Every mortal the host scores: us plus every remote peer whose position is
	# known. Solo: just us (the simulated rivals are not on the field).
	var entries: Array = []
	for id in rules.mortals.keys():
		var mortal_id := int(id)
		if mortal_id == _my_id:
			entries.append({"id": mortal_id, "pos": player.global_position})
		elif _mortal_positions.has(mortal_id):
			entries.append({"id": mortal_id, "pos": _mortal_positions[mortal_id]})
	return entries


func _mortal_label(mortal_id: int) -> String:
	var mortal := rules.mortal(mortal_id)
	return mortal.display_name if mortal != null else "Mortal"


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
	var mine := _local_favor()
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


func _local_favor() -> int:
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
	if favor.id == &"half_vision":
		# Half Vision blinds every other mortal: on their screens the mask closes
		# in. Locally we play the same mask so the cast is visible.
		_blind_time = favor.duration
		_blind_radius = favor.param("vision_radius", 0.16)
		_log("Half Vision - every other mortal sees only a circle around them", favor.color)


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
	if _net == null or not _networked:
		return
	_net.god_state_received.connect(_on_god_state_received)
	_net.arena_state_received.connect(_on_arena_state_received)
	_net.arena_layout_received.connect(_on_arena_layout_received)
	_net.player_left.connect(_on_peer_left)
	if _net.has_signal("dialogue_released"):
		_net.connect("dialogue_released", _on_dialogue_released)
	if _authority:
		_net.god_favor_requested.connect(_on_god_favor_requested)
		_net.god_skill_requested.connect(_on_god_skill_requested)
		_net.god_grant_requested.connect(_on_god_grant_requested)
	else:
		_net.rpc_id(1, "request_god_state")


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
	var clones: Array = []
	var hunts: Array = []
	for clone in _clones:
		if is_instance_valid(clone):
			clones.append(clone.global_position)
			hunts.append(clone.is_hunting())
	_net.publish_arena_state({
		"phase": int(_phase),
		"trial_time": _trial_time,
		"clones": clones,
		"hunts": hunts,
		"mortals": _mortal_positions.duplicate(),
		"banner": hud.banner_label.text if hud.banner_label.visible else "",
		"banner_color": hud.banner_label.get_theme_color("font_color"),
		"event": hud.event_label.text,
		"event_color": hud.event_label.get_theme_color("font_color"),
	})


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
	# The host's round, mirrored: the same second on the clock, the same lit
	# zone, the same two Mayaris walking the same line.
	var remote_phase := int(state.get("phase", int(_phase)))
	_trial_time = float(state.get("trial_time", _trial_time))
	# The shell's clock (Game.gd) reads this signal - without it a client's clock
	# would sit still while the host's runs.
	trial_time_changed.emit(_trial_time)
	hud.set_time_left(_trial_time)

	var clone_positions: Array = state.get("clones", [])
	var hunts: Array = state.get("hunts", [])
	for index in range(mini(clone_positions.size(), _clones.size())):
		var clone = _clones[index]
		if not is_instance_valid(clone):
			continue
		clone.sync_position(clone_positions[index])
		if index < hunts.size():
			clone.set_hunting(bool(hunts[index]))

	var mortals: Dictionary = state.get("mortals", {})
	_mortal_positions.clear()
	for id in mortals.keys():
		_mortal_positions[int(id)] = mortals[id]

	# Follow the host through the trial phases.
	if remote_phase == int(Phase.RESULTS) and _phase != Phase.RESULTS:
		_end_trial()
	elif remote_phase == int(Phase.PLAYING) and _phase != Phase.PLAYING and _phase != Phase.RESULTS:
		_enter_playing()
	elif remote_phase == int(Phase.COUNTDOWN) and _phase == Phase.INTRO:
		_phase = Phase.COUNTDOWN

	# Mirror Mayari's announcements.
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
	rules.add_favor(amount, reason, peer_id)
	_publish_god_state()


func _on_god_skill_requested(peer_id: int, slot: int) -> void:
	var favor: GodFavor = rules.use_skill(slot, peer_id)
	if favor != null and peer_id != _my_id:
		_log("%s used %s" % [_mortal_label(peer_id), favor.display_name], favor.color)
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
	if player_id != rules.local_id or delta == 0:
		return
	# The HUD already shows the running total - only log the meaningful swings.
	if absi(delta) >= 10:
		var color := Color(0.7, 1, 0.8) if delta > 0 else Color(1, 0.5, 0.45)
		_log("%s%d FAVOR   (%s)" % ["+" if delta > 0 else "", delta, reason], color)


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
