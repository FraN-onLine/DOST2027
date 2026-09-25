extends Node2D

# One of Mayari's clones sweeping a lane of the arena, patintero style.
# axis 0 -> sweeps left/right along a fixed y, axis 1 -> sweeps up/down along a fixed x.

const ICON := preload("res://icon.svg")

enum Mode { SWEEP, TRACK_X, TRACK_Y }

var mode := Mode.SWEEP
var axis := 0             # lane orientation: 0 = row (horizontal), 1 = column (vertical)
var lane := 0.0           # the coordinate the clone holds on the other axis
var travel_min := 0.0
var travel_max := 0.0
var speed := 165.0        # sweeping speed
var track_speed := 130.0  # chasing speed - mortals are faster, that is the escape
var radius := 18.0
var color := Color(0.55, 0.85, 1.0)
var lane_color := Color(0.55, 0.85, 1.0, 0.22)
var target := Vector2.ZERO  # the mortal this clone is hunting
var self_moving := true     # clients let the host drive the movement

var _direction := 1.0
var _pulse := 0.0
var _surge := 0.0  # seconds of speed surge left
var _net_target := Vector2.ZERO


func setup_sweep(lane_axis: int, lane_coord: float, from_value: float, to_value: float) -> void:
	mode = Mode.SWEEP
	axis = lane_axis
	lane = lane_coord
	travel_min = minf(from_value, to_value)
	travel_max = maxf(from_value, to_value)
	if axis == 0:
		position = Vector2(travel_min, lane)
	else:
		position = Vector2(lane, travel_min)
	queue_redraw()


func setup_tracker(track_mode: int, at: Vector2, min_value: float, max_value: float) -> void:
	# TRACK_X slides along the row it holds, TRACK_Y along its column.
	mode = track_mode
	axis = 0 if mode == Mode.TRACK_X else 1
	travel_min = minf(min_value, max_value)
	travel_max = maxf(max_value, min_value)
	position = at
	lane = at.y if axis == 0 else at.x
	queue_redraw()


func set_moving(enabled: bool) -> void:
	self_moving = enabled


func sync_position(value: Vector2) -> void:
	# Clients receive positions from the host instead of simulating.
	if _net_target == Vector2.ZERO:
		global_position = value  # first sync - snap instead of gliding
	_net_target = value


func current_speed() -> float:
	return speed * (1.65 if _surge > 0.0 else 1.0)


func surge(seconds: float) -> void:
	_surge = maxf(_surge, seconds)


func hits(point: Vector2, extra_radius := 0.0) -> bool:
	return global_position.distance_to(point) <= radius + extra_radius


func _process(delta: float) -> void:
	_surge = maxf(0.0, _surge - delta)
	_pulse += delta
	if not self_moving:
		# Host-driven clone: glide towards the position we were given.
		if _net_target != Vector2.ZERO:
			global_position = global_position.lerp(_net_target, clampf(delta * 14.0, 0.0, 1.0))
		queue_redraw()
		return
	match mode:
		Mode.TRACK_X:
			_chase(true, delta)
		Mode.TRACK_Y:
			_chase(false, delta)
		_:
			_sweep(delta)
	queue_redraw()


func _sweep(delta: float) -> void:
	var step := current_speed() * delta * _direction
	if axis == 0:
		position.x += step
		if position.x <= travel_min or position.x >= travel_max:
			position.x = clampf(position.x, travel_min, travel_max)
			_direction = -_direction
	else:
		position.y += step
		if position.y <= travel_min or position.y >= travel_max:
			position.y = clampf(position.y, travel_min, travel_max)
			_direction = -_direction


func _chase(horizontal: bool, delta: float) -> void:
	# A tracker only moves along one axis, lining itself up with the mortal it
	# hunts - it never leaves its row (TRACK_X) or its column (TRACK_Y).
	var speed_now := track_speed * (1.5 if _surge > 0.0 else 1.0)
	var step := speed_now * delta
	if horizontal:
		var difference := target.x - position.x
		position.x = clampf(position.x + clampf(difference, -step, step), travel_min, travel_max)
		position.y = lane
	else:
		var difference := target.y - position.y
		position.y = clampf(position.y + clampf(difference, -step, step), travel_min, travel_max)
		position.x = lane


func _draw() -> void:
	# The lane Mayari's clone patrols (drawn in local space).
	if axis == 0:
		var from_x := travel_min - position.x
		var to_x := travel_max - position.x
		draw_rect(Rect2(Vector2(from_x, -1.5), Vector2(to_x - from_x, 3.0)), lane_color, true)
	else:
		var from_y := travel_min - position.y
		var to_y := travel_max - position.y
		draw_rect(Rect2(Vector2(-1.5, from_y), Vector2(3.0, to_y - from_y)), lane_color, true)

	var pulse := 0.5 + 0.5 * sin(_pulse * 4.0)
	draw_circle(Vector2.ZERO, radius + 7.0, Color(color.r, color.g, color.b, 0.16 + 0.12 * pulse))
	draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, 0.75))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, Color(1, 1, 1, 0.8), 2.0)
	draw_texture_rect(ICON, Rect2(Vector2(-radius * 0.75, -radius * 0.75), Vector2(radius * 1.5, radius * 1.5)), false, Color(1, 1, 1, 0.85))
