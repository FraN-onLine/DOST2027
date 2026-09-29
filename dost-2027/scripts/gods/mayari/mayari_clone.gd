class_name MayariClone
extends Node2D

# One of Mayari's two clones (MayariArena.tscn authors exactly two: one
# horizontal, one vertical). A clone does one thing - it walks the Line2D named
# "Path" that is its child, end to end and back - and it never leaves that
# line. Touching a mortal costs that mortal FAVOR (MayariArena.gd does the
# scoring).
#
# Every so often a clone stops patrolling and HUNTS: the arena tells it where
# the mortals are, it picks the nearest one and walks its own line towards the
# spot on that line closest to them. Mayari has no other road, so hunting still
# never takes her off the drawn line - it only stops the line from being a safe
# place to stand.
#
# The Path points are OFFSETS from the spot the clone sits on in the scene, so
# the line is drawn around the clone while you edit and stays exactly there
# while you play: the clone slides along it, the line does not travel with it.
# The clone starts on the point of the path nearest to where you parked it, so
# draw the path through that spot and nothing jumps when a round starts.
#
# Art lives in MayariClone.tscn (Path, Icon, Name); this script never draws.

@export var speed := 165.0   # how fast the clone walks its path (units/second)
@export var radius := 18.0   # how near the mortal may come before it counts as a touch

@export_category("Hunt")
@export var hunt_enabled := true    # patrol alone, or stop to hunt now and then
@export var hunt_interval := 8.0    # seconds of patrol between two hunts
@export var hunt_duration := 2.5    # how long one hunt lasts
@export var hunt_speed_mult := 1.3  # how much faster it walks while hunting

var color := Color(0.55, 0.85, 1.0)
var self_moving := true      # clients let the host drive the movement

var _knots := PackedVector2Array()   # the authored route, in world coordinates
var _legs := PackedFloat32Array()    # the length of every segment of it
var _total := 0.0
var _distance := 0.0
var _start_distance := 0.0
var _direction := 1.0
var _pulse := 0.0
var _net_target := Vector2.ZERO
var _has_net_target := false
var _path_origin := Vector2.ZERO
var _targets := PackedVector2Array()  # where the mortals are (host-fed)
var _hunting := false
var _hunt_left := 0.0
var _hunt_timer := 0.0

@onready var path: Line2D = get_node_or_null("Path")
@onready var icon: Sprite2D = get_node_or_null("Icon")
@onready var name_label: Label = get_node_or_null("Name")


func _ready() -> void:
	_read_path()
	_hunt_timer = hunt_interval


# How long the authored path is (0.0 when the clone has no usable path).
func path_length() -> float:
	return _total


# The authored route in world coordinates - handy for tools and tests.
func path_knots() -> PackedVector2Array:
	return _knots.duplicate()


# Is Mayari hunting instead of patrolling right now?
func is_hunting() -> bool:
	return _hunting


# Where the mortals are. The arena says so on every frame it scores; a clone
# that is not allowed to walk itself (a client) ignores it.
func set_targets(positions: PackedVector2Array) -> void:
	_targets = positions


# Mirrored from the host on a client, where the walk is not simulated.
func set_hunting(value: bool) -> void:
	_hunting = value


# Read the authored Line2D once: its points become the fixed route to walk.
func _read_path() -> void:
	_knots = PackedVector2Array()
	_legs = PackedFloat32Array()
	_total = 0.0
	if path == null:
		push_warning("MayariClone: no Line2D child named 'Path' - this clone stays put")
		return
	_path_origin = path.global_position
	for point in path.points:
		_knots.append(path.global_transform * point)
	for index in range(1, _knots.size()):
		var leg := _knots[index - 1].distance_to(_knots[index])
		_legs.append(leg)
		_total += leg
	if _total <= 0.01:
		push_warning("MayariClone: the Path needs two points that are not on top of each other - this clone stays put")
		return
	# Start where the designer parked the clone: the nearest point of the path.
	_distance = _closest_distance(global_position)
	_start_distance = _distance
	global_position = point_at(_distance)


# Back to the start of the path (fired when a round starts).
func restart() -> void:
	# A round always starts the same way: no hunt in progress, and the clone
	# waits a full patrol before it hunts again.
	_hunting = false
	_hunt_left = 0.0
	_hunt_timer = hunt_interval
	if _total <= 0.01:
		return
	_distance = _start_distance
	_direction = 1.0
	global_position = point_at(_distance)


func set_moving(enabled: bool) -> void:
	self_moving = enabled


func sync_position(value: Vector2) -> void:
	# Clients receive positions from the host instead of simulating.
	if not _has_net_target:
		global_position = value  # first sync - snap instead of gliding
		_has_net_target = true
	_net_target = value


func hits(point: Vector2, extra_radius := 0.0) -> bool:
	return global_position.distance_to(point) <= radius + extra_radius


# The world position `distance` units along the authored path.
func point_at(distance: float) -> Vector2:
	if _knots.is_empty():
		return global_position
	var left := distance
	for index in range(_legs.size()):
		var leg := _legs[index]
		var last := index == _legs.size() - 1
		if left <= leg or last:
			var ratio := 0.0 if leg <= 0.0 else clampf(left / leg, 0.0, 1.0)
			return _knots[index].lerp(_knots[index + 1], ratio)
		left -= leg
	return _knots[_knots.size() - 1]


# How far along the path the point nearest to `from` sits.
func _closest_distance(from: Vector2) -> float:
	var best := 0.0
	var best_gap := INF
	var walked := 0.0
	for index in range(_legs.size()):
		var knot := _knots[index]
		var next := _knots[index + 1]
		var leg := _legs[index]
		var ratio := 0.0
		if leg > 0.0:
			ratio = clampf((from - knot).dot(next - knot) / (leg * leg), 0.0, 1.0)
		var gap := from.distance_to(knot.lerp(next, ratio))
		if gap < best_gap:
			best_gap = gap
			best = walked + leg * ratio
		walked += leg
	return best


func _process(delta: float) -> void:
	_pulse += delta
	if self_moving:
		_tick_hunt(delta)
		_walk(delta)
	elif _has_net_target:
		# Host-driven clone: glide towards the position we were given.
		global_position = global_position.lerp(_net_target, clampf(delta * 14.0, 0.0, 1.0))
	_pin_path()
	_refresh_visual()


# Patrol, hunt, patrol: at most one hunt at a time and always back to the patrol.
func _tick_hunt(delta: float) -> void:
	if _hunting:
		_hunt_left = maxf(0.0, _hunt_left - delta)
		if _hunt_left <= 0.0:
			_hunting = false
			_hunt_timer = hunt_interval
		return
	if not hunt_enabled:
		return
	_hunt_timer = maxf(0.0, _hunt_timer - delta)
	if _hunt_timer > 0.0 or _targets.is_empty():
		return
	_hunting = true
	_hunt_left = hunt_duration


func _walk(delta: float) -> void:
	if _total <= 0.01:
		return
	if _hunting and not _targets.is_empty():
		# Mayari has no road but the one drawn on her: a hunt is the nearest
		# mortal's spot ON that line, so she can never leave it.
		var prey := _closest_distance(_closest_target())
		if absf(prey - _distance) > 0.5:
			_direction = 1.0 if prey > _distance else -1.0
		_distance = move_toward(_distance, prey, speed * hunt_speed_mult * delta)
		global_position = point_at(_distance)
		return
	# Walk the line to its end, then walk it back: no leaving the path, ever.
	_distance += speed * delta * _direction
	if _distance >= _total:
		_distance = _total - (_distance - _total)
		_direction = -1.0
	elif _distance <= 0.0:
		_distance = -_distance
		_direction = 1.0
	_distance = clampf(_distance, 0.0, _total)
	global_position = point_at(_distance)


# The mortal standing nearest to Mayari.
func _closest_target() -> Vector2:
	var nearest := _targets[0]
	var gap := global_position.distance_squared_to(nearest)
	for index in range(1, _targets.size()):
		var candidate: Vector2 = _targets[index]
		var candidate_gap := global_position.distance_squared_to(candidate)
		if candidate_gap < gap:
			gap = candidate_gap
			nearest = candidate
	return nearest


func _pin_path() -> void:
	# Path is a child of the clone, so it would travel with it: hold the drawn
	# line on the spot the designer authored while the clone walks it.
	if path != null:
		path.global_position = _path_origin


func _refresh_visual() -> void:
	# Hunting burns brighter and pulses faster - the only warning a mortal gets.
	# Mayari herself stays solid: the breathe used to drop her to 70% opacity,
	# which read as "slightly transparent" rather than "alive". She now only ever
	# pulses between nearly solid and fully solid, and a hunt takes her to full.
	var pulse := 0.5 + 0.5 * sin(_pulse * (7.0 if _hunting else 4.0))
	if icon != null:
		var alpha := 1.0 if _hunting else 0.92 + 0.08 * pulse
		icon.modulate = Color(color.r, color.g, color.b, alpha)
	if name_label != null:
		name_label.text = "MAYARI"
		name_label.modulate = Color(1, 1, 1, 0.5 + 0.4 * pulse)
	if path != null:
		var line_alpha := 0.5 if _hunting else 0.22
		path.default_color = Color(color.r, color.g, color.b, line_alpha * (0.6 + 0.6 * pulse))
