extends Node2D

@export var embedded := false
var embedded_rect := Rect2()
signal trial_complete

# MAYARI - Patintero x King of the Hill.
#
# Two of Mayari's clones hunt you down: one slides along your row, the other
# along your column. FAVOR is gained by PLAYING the game:
#   - hold one of the four glowing corners of her field  (passive, per second)
#   - cross the field to the far edge and come back      (round trip bonus)
# Getting caught by a clone costs FAVOR.
#
# Solo: this scene simulates everything.
# Multiplayer: the HOST is authoritative (clone movement, scoring, FAVOR) and
# broadcasts an arena tick at 10 Hz plus FAVOR snapshots; every client sends its
# mortal's position and mirrors whatever the host sends.

const HUD_SCENE := preload("res://UI/GodsArena/god_hud.tscn")
const DIALOGUE_SCENE := preload("res://UI/GodsArena/god_dialogue.tscn")
const DUE_MENU_SCENE := preload("res://UI/GodsArena/gods_due_menu.tscn")
const PLAYER_SCRIPT := preload("res://scripts/arena/arena_player.gd")
const CLONE_SCRIPT := preload("res://scripts/arena/mayari_clone.gd")
const ZONE_SCRIPT := preload("res://scripts/arena/capture_zone.gd")
const TEMP_ICON := preload("res://icon.svg")

const TRIAL_TIME := 60.0
const COUNTDOWN_TIME := 3.0
const ROUND_TRIP_FAVOR := 150
const CLONE_PENALTY := 50
const INVULN_TIME := 1.2
const DISRUPTION_INTERVAL := 15.0
const SUCCESS_FAVOR := 1000
const CORNER_RATE := 26.0
const CORNER_SIZE := Vector2(152, 108)
const TRACKER_SPEED := 130.0
const BLESSING_TIME := 8.0
const BLESSING_MULTIPLIER := 2.0
const NET_TICK_RATE := 10.0
const NET_STATE_RATE := 5.0
const LAYOUT_REPEAT := 2.0

# Solo-only placeholders so the leaderboard and rivalry rules have rivals.
const SIMULATE_RIVALS := true
const RIVAL_MORTALS := ["MORTAL 2", "MORTAL 3"]

enum Phase { INTRO, COUNTDOWN, PLAYING, RESULTS }

@onready var zones_root: Node2D = $Zones
@onready var clones_root: Node2D = $Clones
@onready var ghosts_root: Node2D = $Ghosts
@onready var player: CharacterBody2D = $Player
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
var _last_view_size := Vector2.ZERO
var _rng := RandomNumberGenerator.new()

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


func _ready() -> void:
	_rng.randomize()
	god = Gods.mayari()
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

	dialogue = DIALOGUE_SCENE.instantiate()
	ui_layer.add_child(dialogue)
	dialogue.finished.connect(_on_dialogue_finished)

	due_menu = DUE_MENU_SCENE.instantiate()
	ui_layer.add_child(due_menu)
	due_menu.favor_chosen.connect(_on_favor_chosen)

	_build_field()
	hud.bind(rules, god)
	hud.set_trial(1, 5)
	_connect_network()
	_sync_ghosts()
	if _networked:
		player.set_display_name(_mortal_name(), god.color)
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
	# The host owns the field rect (it is broadcast to every client), so only
	# the authority rebuilds on resize.
	if not _authority:
		return
	var view := get_viewport_rect().size
	if view == _last_view_size:
		return
	_build_field()



# --- FIELD LAYOUT -----------------------------------------------------------

func _build_field() -> void:
	var view := get_viewport_rect().size
	if embedded and embedded_rect.size.x > 0.0 and embedded_rect.size.y > 0.0:
		_field = embedded_rect
		_last_view_size = view
		player.bounds = _field
		player.global_position = Vector2(_field.position.x + 46.0, _field.get_center().y)
		if _authority:
			_spawn_zones()
			_spawn_clones()
			_publish_layout()
		queue_redraw()
		return
	# Leave room for the HUD stats panel up top and the event line at the bottom.
	var top_margin := 180.0
	var bottom_margin := 96.0
	var side_margin := 56.0
	var width := maxf(420.0, view.x - side_margin * 2.0)
	var height := maxf(260.0, view.y - top_margin - bottom_margin)
	_field = Rect2(side_margin, top_margin, width, height)
	_last_view_size = view

	player.bounds = _field
	player.global_position = Vector2(_field.position.x + 46.0, _field.get_center().y)
	vision_mask.visible = false
	var material := vision_mask.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("aspect", view.x / maxf(1.0, view.y))
		material.set_shader_parameter("center", Vector2(0.5, 0.5))
		material.set_shader_parameter("radius", _blind_radius)

	if _authority:
		_spawn_zones()
		_spawn_clones()
		_publish_layout()
	queue_redraw()


func _spawn_zones() -> void:
	# Mayari lights the four corners of her field - hold one to bank FAVOR.
	for zone in _zones:
		if is_instance_valid(zone):
			zone.queue_free()
	_zones.clear()
	var inset := 24.0
	var half := CORNER_SIZE * 0.5
	var corners := [
		Vector2(_field.position.x + inset + half.x, _field.position.y + inset + half.y),
		Vector2(_field.end.x - inset - half.x, _field.position.y + inset + half.y),
		Vector2(_field.position.x + inset + half.x, _field.end.y - inset - half.y),
		Vector2(_field.end.x - inset - half.x, _field.end.y - inset - half.y),
	]
	var labels := ["NW CORNER", "NE CORNER", "SW CORNER", "SE CORNER"]
	for index in range(corners.size()):
		# The embedded Game layout reserves one live corner for the current god.
		# Mayari's arena is the southeast corner in this presentation.
		if embedded and index != 3:
			continue
		_zones.append(_make_zone(corners[index], CORNER_SIZE, CORNER_RATE, labels[index], index == 3))


func _make_zone(center: Vector2, size_value: Vector2, rate: float, label: String, far: bool) -> Node2D:
	var zone: Node2D = ZONE_SCRIPT.new()
	zones_root.add_child(zone)
	zone.setup(center, size_value, rate, god.color, label, far)
	return zone


func _spawn_clones() -> void:
	for clone in _clones:
		if is_instance_valid(clone):
			clone.queue_free()
	_clones.clear()
	# Two of Mayari: one hunts along your row, the other along your column.
	_spawn_tracker(CLONE_SCRIPT.Mode.TRACK_X, Vector2(_field.get_center().x, _field.position.y + _field.size.y * 0.22))
	_spawn_tracker(CLONE_SCRIPT.Mode.TRACK_Y, Vector2(_field.position.x + _field.size.x * 0.32, _field.get_center().y))


func _make_clone() -> Node2D:
	var clone: Node2D = CLONE_SCRIPT.new()
	clones_root.add_child(clone)
	clone.color = god.color
	clone.lane_color = Color(god.color.r, god.color.g, god.color.b, 0.22)
	return clone


func _spawn_tracker(track_mode: int, at: Vector2) -> Node2D:
	var clone := _make_clone()
	var from_value := _field.position.x if track_mode == CLONE_SCRIPT.Mode.TRACK_X else _field.position.y
	var to_value := _field.end.x if track_mode == CLONE_SCRIPT.Mode.TRACK_X else _field.end.y
	clone.setup_tracker(track_mode, at, from_value, to_value)
	clone.track_speed = TRACKER_SPEED + _rng.randf_range(-8.0, 8.0)
	_clones.append(clone)
	return clone


func _spawn_sweeper() -> Node2D:
	# Extra pressure for the "another Mayari" disruption.
	var clone := _make_clone()
	var lane := _rng.randf_range(_field.position.y + 60.0, _field.end.y - 60.0)
	clone.setup_sweep(0, lane, _field.position.x, _field.end.x)
	clone.speed = _rng.randf_range(150.0, 180.0)
	_clones.append(clone)
	return clone


# --- MULTIPLAYER: layout + field sync ---------------------------------------

func _clone_definition(clone: Node2D) -> Dictionary:
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


func _clone_from_definition(definition: Dictionary) -> void:
	var clone := _make_clone()
	var mode := int(definition.get("mode", 0))
	var min_value := float(definition.get("min", _field.position.y))
	var max_value := float(definition.get("max", _field.end.y))
	if mode == CLONE_SCRIPT.Mode.SWEEP:
		clone.setup_sweep(int(definition.get("axis", 0)), float(definition.get("lane", 0.0)), min_value, max_value)
	else:
		clone.setup_tracker(mode, definition.get("pos", Vector2.ZERO), min_value, max_value)
	clone.speed = float(definition.get("speed", 165.0))
	clone.track_speed = float(definition.get("track_speed", TRACKER_SPEED))
	clone.set_moving(false)  # the host owns clone movement
	_clones.append(clone)


func _publish_layout() -> void:
	if not _networked or not _authority or _net == null:
		return
	var zones: Array = []
	for zone in _zones:
		if is_instance_valid(zone):
			zones.append({
				"pos": zone.global_position,
				"size": zone.box_size,
				"rate": float(zone.base_rate),
				"label": str(zone.zone_label),
			})
	var clones: Array = []
	for clone in _clones:
		if is_instance_valid(clone):
			clones.append(_clone_definition(clone))
	_net.publish_arena_layout({"field": _field, "zones": zones, "clones": clones})


func _apply_layout(layout: Dictionary) -> void:
	# Clients play on the host's field so everybody shares the same coordinates.
	_field = layout.get("field", _field)
	player.bounds = _field
	for zone in _zones:
		if is_instance_valid(zone):
			zone.queue_free()
	_zones.clear()
	for definition in layout.get("zones", []):
		var zone := _make_zone(
			definition.get("pos", Vector2.ZERO),
			definition.get("size", CORNER_SIZE),
			float(definition.get("rate", CORNER_RATE)),
			str(definition.get("label", "CORNER")),
			false)
		_zones.append(zone)
	for clone in _clones:
		if is_instance_valid(clone):
			clone.queue_free()
	_clones.clear()
	for definition in layout.get("clones", []):
		_clone_from_definition(definition)
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.03, 0.04, 0.08, 1), true)
	if _field.size == Vector2.ZERO:
		return
	var tint := god.color if god != null else Color.WHITE
	draw_rect(_field, Color(0.05, 0.07, 0.13, 1), true)
	draw_rect(_field, Color(tint.r, tint.g, tint.b, 0.35), false, 3.0)
	# The mortal's starting line and the middle of the field (round trips).
	var start_x := _field.position.x + 46.0
	draw_line(Vector2(start_x, _field.position.y), Vector2(start_x, _field.end.y), Color(1, 1, 1, 0.22), 2.0)
	var mid_x := _field.get_center().x
	draw_line(Vector2(mid_x, _field.position.y), Vector2(mid_x, _field.end.y), Color(1, 1, 1, 0.08), 2.0)


# --- FLOW -------------------------------------------------------------------

func _start_intro() -> void:
	_phase = Phase.INTRO
	player.set_lock(true)
	dialogue.show_lines(_speech(god, god.intro_lines), TEMP_ICON)


func _start_countdown() -> void:
	_phase = Phase.COUNTDOWN
	_countdown = COUNTDOWN_TIME
	_count_shown = -1
	player.set_lock(true)
	player.global_position = Vector2(_field.position.x + 46.0, _field.get_center().y)


func _start_trial() -> void:
	_phase = Phase.PLAYING
	_trial_time = TRIAL_TIME
	_zone_pending.clear()
	_reached_far.clear()
	_invuln.clear()
	_invuln[_my_id] = 1.0
	_blind_time = 0.0
	_disruption_timer = DISRUPTION_INTERVAL
	player.set_lock(false)
	rules.trial_active = true
	_show_banner("GO!", god.color, 1.0)
	hud.set_time_left(_trial_time)


func _process(delta: float) -> void:
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
	hud.set_time_left(_trial_time)
	_tick_invuln(delta)
	_tick_blessing(delta)
	_update_chasers()
	_disruption_timer -= delta
	if _disruption_timer <= 0.0:
		_disruption_timer = DISRUPTION_INTERVAL
		_trigger_disruption()
	_check_zones(delta)
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


func _tick_invuln(delta: float) -> void:
	for id in _invuln.keys():
		_invuln[id] = maxf(0.0, float(_invuln[id]) - delta)


func _tick_blessing(delta: float) -> void:
	var blessed := _blessing_time > 0.0
	if blessed != _blessing_active:
		_blessing_active = blessed
		_apply_zone_multiplier(BLESSING_MULTIPLIER if blessed else 1.0)
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
		if int(clone.mode) == CLONE_SCRIPT.Mode.SWEEP:
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


func _check_zones(delta: float) -> void:
	for zone in _zones:
		if is_instance_valid(zone):
			zone.held = false
	for entry in _mortal_entries():
		var mortal_id := int(entry["id"])
		var position: Vector2 = entry["pos"]
		var best: Node2D = null
		for zone in _zones:
			if not is_instance_valid(zone):
				continue
			if not zone.contains(position):
				continue
			zone.held = true
			if best == null or float(zone.rate) > float(best.rate):
				best = zone
		if best == null:
			continue
		# Passive FAVOR: standing in one of Mayari's corners pays out over time.
		var pending := float(_zone_pending.get(mortal_id, 0.0)) + float(best.rate) * delta
		while pending >= 1.0:
			pending -= 1.0
			rules.add_favor(1, "holding the %s" % str(best.zone_label), mortal_id)
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


func _on_clone_hit(clone: Node2D, mortal_id: int, position: Vector2) -> void:
	_invuln[mortal_id] = INVULN_TIME
	var lost := rules.lose_favor(CLONE_PENALTY, "Mayari's clone", mortal_id)
	if mortal_id != _my_id:
		if lost > 0:
			_log("%s was caught by a clone  (-%d FAVOR)" % [_mortal_label(mortal_id), lost], Color(1, 0.6, 0.5))
		return
	var knock := position - clone.global_position
	if knock.length() < 0.01:
		knock = Vector2.LEFT
	player.hit(knock, 1.3, 470.0)
	if lost > 0:
		_show_banner("-%d FAVOR" % lost, Color(1, 0.45, 0.4), 1.2)
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
			var gained := rules.add_favor(ROUND_TRIP_FAVOR, "round trip", mortal_id)
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
			_blessing_time = BLESSING_TIME
			_show_banner("MOON BLESSING!", god.color, 1.8)
			_log("Her corners glow brighter - double FAVOR for %ds" % int(BLESSING_TIME), god.color)


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
			_start_countdown()
		Phase.RESULTS:
			hud.show_results(_results, "TRIAL COMPLETE")
			if _free_grants > 0:
				hud.set_results_hint("F - CLAIM YOUR FREE FAVOR      SPACE - PLAY AGAIN      ESC - LEAVE")
			else:
				hud.set_results_hint("SPACE - PLAY AGAIN      ESC - LEAVE")
		_:
			pass


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
	var success := mine >= SUCCESS_FAVOR
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
		var ghost: CharacterBody2D = PLAYER_SCRIPT.new()
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
				if embedded:
					trial_complete.emit()
				else:
					get_tree().reload_current_scene()
		_:
			pass


func _leave() -> void:
	# In a networked run everyone goes back to the lobby; solo goes to the menu.
	if _networked:
		get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
