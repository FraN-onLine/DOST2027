class_name MayariArena
extends Node2D

# MAYARI - Patintero x King of the Hill.  (scripts/gods/mayari + scenes/gods/mayari)
#
# Two of Mayari's clones hunt you down: one slides along your row, the other
# along your column. FAVOR is gained by PLAYING the game:
#   - hold the corner Mayari is currently lighting        (passive, per second)
#   - cross the field to the far edge and come back       (round trip bonus)
# Getting caught by a clone costs FAVOR.
#
# The arena owns no art: MayariArena.tscn holds the floor, its border and the
# patintero lines, the four goals (MayariGoal.tscn), the two clones
# (MayariClone.tscn) and the mortal (Mortal.tscn). This script only moves those
# nodes around and runs the rules - nothing here draws.
#
# Solo: this scene simulates everything.
# Multiplayer: the HOST is authoritative (clone movement, scoring, FAVOR) and
# broadcasts an arena tick at 10 Hz plus FAVOR snapshots; every client sends its
# mortal's position and mirrors whatever the host sends.

signal trial_complete
signal trial_time_changed(seconds: float)

const HUD_SCENE := preload("res://UI/GodsArena/god_hud.tscn")
const DIALOGUE_SCENE := preload("res://UI/GodsArena/god_dialogue.tscn")
const DUE_MENU_SCENE := preload("res://UI/GodsArena/gods_due_menu.tscn")
const MORTAL_SCENE := preload("res://scenes/gods/common/Mortal.tscn")
const GOAL_SCENE := preload("res://scenes/gods/mayari/MayariGoal.tscn")
const CLONE_SCENE := preload("res://scenes/gods/mayari/MayariClone.tscn")
const TEMP_ICON := preload("res://icon.svg")

@export_category("Identity")
@export var god_id: StringName = &"mayari"
@export var embedded := false
@export var dialogue_prefix := "mayari"
var embedded_rect := Rect2()

@export_category("Trial Tuning")
@export var trial_time := 60.0
@export var countdown_time := 3.0
@export var round_trip_favor := 150
@export var clone_penalty := 50
const INVULN_TIME := 1.2
@export var disruption_interval := 15.0
@export var success_favor := 1000
@export var corner_rate := 26.0
@export var corner_size := Vector2(152, 108)
@export var tracker_speed := 130.0
@export var blessing_time := 8.0
@export var blessing_multiplier := 2.0
@export_range(1, 4, 1) var goal_zone_count := 1
@export_range(0, 3, 1) var active_goal_corner := 3
@export var goal_switch_interval := 12.0
@export var field_rect := Rect2(56.0, 216.0, 1040.0, 360.0)
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
var _phase := Phase.INTRO
var _trial_time := 0.0
var _countdown := 0.0
var _count_shown := -1
var _zone_pending: Dictionary = {}    # mortal id -> fractional FAVOR not banked
var _reached_far: Dictionary = {}     # mortal id -> touched the far edge
var _invuln: Dictionary = {}          # mortal id -> seconds of mercy left
var _disruption_timer := 0.0
var _blind_time := 0.0
var _blind_radius := 0.16
var _blessing_time := 0.0
var _blessing_active := false
var _free_grants := 0
var _results: Dictionary = {}
var _rng := RandomNumberGenerator.new()
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
	_rng.randomize()
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
	rules.skill_used.connect(_on_skill_used)
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

	_apply_field()
	player.set_display_name(_mortal_name(), god.color)
	hud.bind(rules, god)
	hud.set_trial(1, 5)
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
	# The shell owns the embedded rect; standalone runs keep their authored one.
	if not _authority:
		return
	_apply_field()


# --- FIELD LAYOUT -----------------------------------------------------------

func _apply_field() -> void:
	# One rect drives the whole arena: the floor art, the lines, the four goals,
	# both clones and the mortal's bounds. Embedded runs follow the shell panel.
	if embedded and embedded_rect.size.x > 0.0 and embedded_rect.size.y > 0.0:
		_field = embedded_rect
	else:
		_field = field_rect
	var tint: Color = god.color if god != null else Color.WHITE
	field_root.set_field(_field, tint)
	player.bounds = _field
	player.ring_color = tint
	player.global_position = Vector2(_field.position.x + MayariArenaField.START_OFFSET, _field.get_center().y)
	_apply_vision_mask()
	if _authority:
		_configure_goals()
		_configure_clones()
		_publish_layout()


# The shell calls this when its arena panel changes size.
func refresh_field() -> void:
	if _authority:
		_apply_field()


func _corner_centers() -> Array:
	var inset := 24.0
	var half := corner_size * 0.5
	return [
		Vector2(_field.position.x + inset + half.x, _field.position.y + inset + half.y),
		Vector2(_field.end.x - inset - half.x, _field.position.y + inset + half.y),
		Vector2(_field.position.x + inset + half.x, _field.end.y - inset - half.y),
		Vector2(_field.end.x - inset - half.x, _field.end.y - inset - half.y),
	]


func _configure_goals() -> void:
	# The four corner goals are scene nodes; Mayari only lights one at a time.
	_zones.clear()
	var corners := _corner_centers()
	var goals := zones_root.get_children()
	_active_goal_index = clampi(active_goal_corner, 0, maxi(0, goals.size() - 1))
	for index in range(goals.size()):
		var goal: MayariGoal = goals[index]
		goal.position = corners[index]
		goal.box_size = corner_size
		goal.color = god.color
		goal.is_far = index >= 2
		goal.set_rate(corner_rate)
		goal.set_active(index == _active_goal_index)
		goal.visible = true
		_zones.append(goal)
	_goal_switch_timer = goal_switch_interval


func _configure_clones() -> void:
	# The two regular Mayaris are authored scene nodes; extra sweepers come from
	# MayariClone.tscn when a disruption calls for them.
	var horizontal_at := Vector2(_field.get_center().x, _field.position.y + _field.size.y * 0.22)
	var vertical_at := Vector2(_field.position.x + _field.size.x * 0.32, _field.get_center().y)
	for clone in _clones:
		if is_instance_valid(clone) and clone.has_meta("dynamic"):
			clone.queue_free()
	_clones.clear()
	var authored: Array = []
	for node in clones_root.get_children():
		if not node.has_meta("dynamic"):
			authored.append(node)
	if authored.size() >= 2:
		_configure_tracker(authored[0], MayariClone.Mode.TRACK_X, horizontal_at)
		_configure_tracker(authored[1], MayariClone.Mode.TRACK_Y, vertical_at)
		authored[0].visible = true
		authored[1].visible = true
		_clones.append(authored[0])
		_clones.append(authored[1])
		return
	_spawn_tracker(MayariClone.Mode.TRACK_X, horizontal_at)
	_spawn_tracker(MayariClone.Mode.TRACK_Y, vertical_at)


func _configure_tracker(clone: MayariClone, track_mode: int, at: Vector2) -> void:
	clone.color = god.color
	clone.lane_color = Color(god.color.r, god.color.g, god.color.b, 0.22)
	var from_value := _field.position.x if track_mode == MayariClone.Mode.TRACK_X else _field.position.y
	var to_value := _field.end.x if track_mode == MayariClone.Mode.TRACK_X else _field.end.y
	clone.setup_tracker(track_mode, at, from_value, to_value)
	clone.track_speed = tracker_speed
	clone.set_moving(_authority)


func _make_clone(sweep_lane := 0.0) -> MayariClone:
	var clone: MayariClone = CLONE_SCENE.instantiate()
	clone.set_meta("dynamic", true)
	clones_root.add_child(clone)
	clone.color = god.color
	clone.lane_color = Color(god.color.r, god.color.g, god.color.b, 0.22)
	clone.setup_sweep(0, sweep_lane, _field.position.x, _field.end.x)
	clone.speed = _rng.randf_range(150.0, 180.0)
	return clone


func _spawn_tracker(track_mode: int, at: Vector2) -> MayariClone:
	var clone := _make_clone()
	var from_value := _field.position.x if track_mode == MayariClone.Mode.TRACK_X else _field.position.y
	var to_value := _field.end.x if track_mode == MayariClone.Mode.TRACK_X else _field.end.y
	clone.setup_tracker(track_mode, at, from_value, to_value)
	clone.track_speed = tracker_speed + _rng.randf_range(-8.0, 8.0)
	_clones.append(clone)
	return clone


func _spawn_sweeper() -> MayariClone:
	# Extra pressure for the "another Mayari" disruption.
	var lane := _rng.randf_range(_field.position.y + 60.0, _field.end.y - 60.0)
	var clone := _make_clone(lane)
	_clones.append(clone)
	return clone


# --- MULTIPLAYER: layout sync -----------------------------------------------

func _zone_definition(zone: MayariGoal) -> Dictionary:
	return {
		"pos": zone.global_position,
		"size": zone.box_size,
		"rate": float(zone.base_rate),
		"favor_amount": int(zone.favor_amount),
		"label": str(zone.zone_label),
		"favor_enabled": zone.favor_enabled,
	}


func _clone_definition(clone: MayariClone) -> Dictionary:
	return {
		"mode": int(clone.mode),
		"axis": int(clone.axis),
		"lane": float(clone.lane),
		"min": float(clone.travel_min),
		"max": float(clone.travel_max),
		"speed": float(clone.speed),
		"track_speed": float(clone.track_speed),
		"pos": clone.global_position,
	}


func _publish_layout() -> void:
	if not _networked or not _authority or _net == null:
		return
	var zones: Array = []
	for zone in _zones:
		if is_instance_valid(zone):
			zones.append(_zone_definition(zone))
	var clones: Array = []
	for clone in _clones:
		if is_instance_valid(clone):
			clones.append(_clone_definition(clone))
	_net.publish_arena_layout({
		"field": _field,
		"active_goal": _active_goal_index,
		"zones": zones,
		"clones": clones,
	})


func _apply_layout(layout: Dictionary) -> void:
	# Clients play on the host's field so everybody shares the same coordinates.
	_field = layout.get("field", _field)
	var tint: Color = god.color if god != null else Color.WHITE
	field_root.set_field(_field, tint)
	player.bounds = _field
	_active_goal_index = int(layout.get("active_goal", _active_goal_index))
	var definitions: Array = layout.get("zones", [])
	for index in range(mini(definitions.size(), _zones.size())):
		var zone: MayariGoal = _zones[index]
		var definition: Dictionary = definitions[index]
		zone.position = definition.get("pos", zone.position)
		zone.box_size = definition.get("size", zone.box_size)
		zone.zone_label = str(definition.get("label", zone.zone_label))
		zone.favor_amount = int(definition.get("favor_amount", zone.favor_amount))
		zone.set_rate(float(definition.get("rate", zone.base_rate)))
		zone.set_active(bool(definition.get("favor_enabled", index == _active_goal_index)))
	for clone in _clones:
		if is_instance_valid(clone) and clone.has_meta("dynamic"):
			clone.queue_free()
	_clones.clear()
	var authored: Array = []
	for node in clones_root.get_children():
		if not node.has_meta("dynamic"):
			authored.append(node)
	var clone_definitions: Array = layout.get("clones", [])
	for index in range(clone_definitions.size()):
		var definition: Dictionary = clone_definitions[index]
		if index < authored.size():
			var tracker: MayariClone = authored[index]
			var mode := int(definition.get("mode", MayariClone.Mode.TRACK_X))
			_configure_tracker(tracker, mode, definition.get("pos", Vector2.ZERO))
			tracker.set_moving(false)
			_clones.append(tracker)
		else:
			_clone_from_definition(definition)


func _clone_from_definition(definition: Dictionary) -> void:
	var mode := int(definition.get("mode", MayariClone.Mode.SWEEP))
	var min_value := float(definition.get("min", _field.position.y))
	var max_value := float(definition.get("max", _field.end.y))
	var clone: MayariClone = _make_clone(float(definition.get("lane", _field.get_center().y)))
	if mode != MayariClone.Mode.SWEEP:
		clone.setup_tracker(mode, definition.get("pos", Vector2.ZERO), min_value, max_value)
	clone.speed = float(definition.get("speed", 165.0))
	clone.track_speed = float(definition.get("track_speed", tracker_speed))
	clone.set_moving(false)  # the host owns clone movement
	_clones.append(clone)


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
	player.global_position = Vector2(_field.position.x + MayariArenaField.START_OFFSET, _field.get_center().y)


func _start_trial() -> void:
	_phase = Phase.PLAYING
	_trial_time = trial_time
	trial_time_changed.emit(_trial_time)
	_zone_pending.clear()
	_reached_far.clear()
	_invuln.clear()
	_invuln[_my_id] = 1.0
	_blind_time = 0.0
	_disruption_timer = disruption_interval
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
	_apply_blindness(delta)
	_move_ghosts(delta)


func _tick_trial(delta: float) -> void:
	_trial_time -= delta
	trial_time_changed.emit(_trial_time)
	hud.set_time_left(_trial_time)
	_tick_invuln(delta)
	_tick_blessing(delta)
	_goal_switch_timer -= delta
	if _goal_switch_timer <= 0.0:
		_advance_active_goal()
	_update_chasers()
	_disruption_timer -= delta
	if _disruption_timer <= 0.0:
		_disruption_timer = disruption_interval
		_trigger_disruption()
	_check_goals(delta)
	_check_clones()
	_check_round_trip()
	_check_rivalry()
	_publish_net_tick(delta)
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
	_active_goal_index = (_active_goal_index + 1) % _zones.size()
	for index in range(_zones.size()):
		var zone: MayariGoal = _zones[index]
		zone.set_active(index == _active_goal_index)
	_goal_switch_timer = goal_switch_interval
	_log("Mayari's light moves to the %s" % str(_zones[_active_goal_index].zone_label), god.color)
	_publish_layout()


func _tick_invuln(delta: float) -> void:
	for id in _invuln.keys():
		_invuln[id] = maxf(0.0, float(_invuln[id]) - delta)


func _tick_blessing(delta: float) -> void:
	var blessed := _blessing_time > 0.0
	if blessed != _blessing_active:
		_blessing_active = blessed
		_apply_zone_multiplier(blessing_multiplier if blessed else 1.0)
	_blessing_time = maxf(0.0, _blessing_time - delta)


func _apply_zone_multiplier(multiplier: float) -> void:
	for zone in _zones:
		if is_instance_valid(zone):
			zone.set_rate_multiplier(multiplier)
	if _authority:
		_publish_layout()


func _update_chasers() -> void:
	# Mayari's two clones hunt whichever mortal is nearest to them.
	for clone in _clones:
		if not is_instance_valid(clone):
			continue
		if int(clone.mode) == MayariClone.Mode.SWEEP:
			continue
		clone.target = _nearest_mortal_position(clone.global_position)


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


func _check_round_trip() -> void:
	for entry in _mortal_entries():
		var mortal_id := int(entry["id"])
		var position: Vector2 = entry["pos"]
		# Reach the far edge of the field...
		if position.x >= _field.end.x - 90.0:
			_reached_far[mortal_id] = true
		# ...then make it back to the starting line.
		if bool(_reached_far.get(mortal_id, false)) and position.x <= _field.position.x + 60.0:
			_reached_far[mortal_id] = false
			var gained := rules.add_favor(round_trip_favor, "round trip", mortal_id)
			if mortal_id == _my_id:
				_show_banner("ROUND TRIP  +%d FAVOR" % gained, Color(0.7, 1, 0.8), 1.6)
				_log("You crossed the whole field and back  (+%d FAVOR)" % gained, Color(0.7, 1, 0.8))
			else:
				_log("%s crossed the field and back  (+%d FAVOR)" % [_mortal_label(mortal_id), gained], Color(0.7, 1, 0.8))


func _check_rivalry() -> void:
	var targets := rules.consume_rivalry_triggers()
	for target in targets:
		_show_banner("SIBLING'S RIVALRY", god.color, 2.0)
		_log("%s fell behind - Mayari blots out their screen for 5s" % str(target.display_name), god.color)


func _trigger_disruption() -> void:
	var roll := _rng.randi_range(0, 2)
	match roll:
		0:
			for clone in _clones:
				if is_instance_valid(clone):
					clone.surge(5.0)
			_show_banner("MOONLIGHT RUSH!", god.color, 1.8)
			_log("Mayari's clones speed up for 5s", god.color)
		1:
			_spawn_sweeper()
			_publish_layout()
			_show_banner("ANOTHER MAYARI!", god.color, 1.8)
			_log("Mayari sends in another clone", god.color)
		_:
			_blessing_time = blessing_time
			_show_banner("MOON BLESSING!", god.color, 1.8)
			_log("Her corner glows brighter - double FAVOR for %ds" % int(blessing_time), god.color)


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


func _nearest_mortal_position(from: Vector2) -> Vector2:
	var best := player.global_position
	var best_distance := from.distance_to(best)
	for id in _mortal_positions.keys():
		if int(id) == _my_id:
			continue
		var position: Vector2 = _mortal_positions[id]
		var distance := from.distance_to(position)
		if distance < best_distance:
			best_distance = distance
			best = position
	return best


func _mortal_label(mortal_id: int) -> String:
	var mortal := rules.mortal(mortal_id)
	return mortal.display_name if mortal != null else "Mortal"


# --- DIALOGUE / RESULTS -----------------------------------------------------

func _speech(speaker: God, lines: Array, extra: Array = []) -> Array:
	var out: Array = extra.duplicate()
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
		_start_countdown()
	else:
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
	for clone in _clones:
		if is_instance_valid(clone):
			clones.append(clone.global_position)
	_net.publish_arena_state({
		"phase": int(_phase),
		"trial_time": _trial_time,
		"clones": clones,
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
	var remote_phase := int(state.get("phase", int(_phase)))
	_trial_time = float(state.get("trial_time", _trial_time))
	hud.set_time_left(_trial_time)

	var clone_positions: Array = state.get("clones", [])
	for index in range(mini(clone_positions.size(), _clones.size())):
		var clone = _clones[index]
		if is_instance_valid(clone):
			clone.sync_position(clone_positions[index])

	var mortals: Dictionary = state.get("mortals", {})
	_mortal_positions.clear()
	for id in mortals.keys():
		_mortal_positions[int(id)] = mortals[id]

	# Follow the host through the trial phases.
	if remote_phase == int(Phase.RESULTS) and _phase != Phase.RESULTS:
		_end_trial()
	elif remote_phase == int(Phase.PLAYING) and _phase != Phase.PLAYING and _phase != Phase.RESULTS:
		_phase = Phase.PLAYING
		if dialogue.is_active():
			dialogue.close_now()
		player.set_lock(false)
		rules.trial_active = true

	# Mirror Mayari's announcements.
	var banner := str(state.get("banner", ""))
	if banner != "" and banner != _last_banner:
		_last_banner = banner
		_show_banner(banner, state.get("banner_color", god.color), 1.2)
	var event := str(state.get("event", ""))
	if event != "" and event != _last_event:
		_last_event = event
		_log(event, state.get("event_color", god.color))


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


func _on_skill_used(_player_id: int, _favor: GodFavor) -> void:
	# Hook for the network layer: this is where other mortals learn a skill fired.
	pass


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
