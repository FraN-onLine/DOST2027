class_name AgawanGod
extends Node2D

# One of Bathala's gods in AGAWAN BASE - Apolaki, Tala, Mayari, Hanan - or
# Bathala himself, circling the base he guards. (scripts/gods/bathala)
#
# A god does one of these each frame, in this order of priority:
#   * FROZEN  while frozen a god stands still, cannot tag and slowly thaws on its
#             own (freeze_time) - or at once when a live god touches it, or when
#             Hanan's dawn pulse reaches it. A mortal's swing never thaws a god.
#   * WATCH   Bathala circles his base and never leaves the ring. While a mortal
#             holds his base he turns and walks straight at the holder
#             (watcher_speed x faster) until the hold breaks.
#   * DEFEND  the defensive gods (Tala, Hanan) stay near Bathala's base and chase
#             any mortal within defend_wake of it.
#   * ATTACK  the offensive gods (Apolaki, Mayari) push into the mortals' base and
#             try to hold it (the arena counts the hold). They chase a mortal only
#             when one is within chase_radius and off its safe base, and fall back
#             to defend only when a mortal is inside or near BATHALA's base
#             (attack_switch).
#
# EVERY GOD PLAYS LIKE THEIR OWN TRIAL (one signature trait each):
#   * Apolaki, the lunge (Arnis): every lunge_interval seconds of a chase he
#     winds up for lunge_windup (a flash and a line on the ground), then dashes
#     lunge_distance toward his target. Fast, but readable and dodgeable.
#   * Mayari, the moonlight (Patintero): moon_speed x slower, moon_reach x the
#     tag reach (a faint circle shows it), and she guards the lane - she steps
#     into a mortal's row instead of chasing it.
#   * Tala's star throw and Hanan's dawn pulse are rules, so the arena runs them
#     (BathalaArena); this node only draws Hanan's pulse ring.
#
# Touching a mortal freezes it - the BathalaArena owns that rule and every other
# rule; this node only walks, decides a goal moment to moment and draws itself.
#
# The art lives in AgawanGod.tscn (Icon, Ring, Reach, Pulse, Lunge, Name, Timer).
# Host-driven only: the host moves every god, the clients mirror the pose and
# the trait state through the arena's tick fields (see bathala_arena.gd).

enum Role { ATTACK, DEFEND }

const ROLE_COLOR := {
	"apolaki": Color(1.0, 0.55, 0.2),
	"mayari": Color(0.55, 0.85, 1.0),
	"tala": Color(0.7, 0.8, 1.0),
	"hanan": Color(1.0, 0.62, 0.55),
	"bathala": Color(0.30, 0.31, 0.36),
}

@export var move_speed := 150.0        # how fast the god walks (the mortal runs 215)
@export var tag_radius := 24.0         # how close before a touch counts as a tag
@export var guard_radius := 90.0       # how far Bathala circles his base
@export var defend_wake := 210.0       # a mortal this close to Bathala's base wakes a defender
@export var attack_switch := 170.0     # a mortal this close to Bathala's base pulls an attacker back
@export var chase_radius := 140.0      # an attacker only chases a mortal this close to it
@export var decision_interval := 0.5   # seconds between wander re-rolls (not every frame)

@export_category("Apolaki - the lunge")
@export var lunge_interval := 4.0      # seconds between lunges while chasing (0 = off)
@export var lunge_windup := 0.4        # the readable flash before the dash
@export var lunge_distance := 140.0    # how far the dash carries him
@export var lunge_time := 0.15         # how long the dash takes

@export_category("Mayari - the moonlight")
@export var moon_speed := 0.85         # her walk, as a share of move_speed (1 = off)
@export var moon_reach := 1.5          # her tag reach, as a multiple of tag_radius (1 = off)

@export_category("Bathala - the watcher")
@export var watcher_speed := 1.2       # his walk at a holder, as a multiple of move_speed (0 = off)
@export var god_freeze_time := 10.0    # seconds a frozen god stays frozen (mortals: 5s)

var god_id: StringName = &""
var role: Role = Role.ATTACK
var base_center := Vector2.ZERO       # Bathala's base (the one every god defends)
var target_center := Vector2.ZERO     # the mortals' base (the one attackers raid)
var safe_radius := 46.0               # a mortal this close to target_center is on its safe base
var circle_phase := 0.0               # where around his base Bathala stands
var circle_dir := 1.0

var frozen := false                   # true while tagged / thawing
var freeze_left := 0.0

# Set by the arena every frame (host) or tick (client).
var speed_mult := 1.0                 # Bathala grows wary: every god gets faster
var watch_target := Vector2.INF       # Bathala: the mortal holding his base, if any
var pulse_radius := 120.0             # Hanan: how far her dawn pulse reaches
var pulse_flash := 0.0                # Hanan: seconds left showing the pulse ring

# Apolaki's lunge (mirrored to the clients).
var windup := 0.0                     # seconds left in the wind-up
var lunge_left := 0.0                 # seconds left in the dash
var lunge_dir := Vector2.ZERO

var _think := 0.0
var _wander := Vector2.ZERO
var _pulse := 0.0
var _lunge_cd := 0.0
var _chasing := false                 # the goal this frame is a mortal

@onready var icon: Sprite2D = get_node_or_null("Icon")
@onready var ring: Line2D = get_node_or_null("Ring")
@onready var reach_ring: Line2D = get_node_or_null("Reach")
@onready var pulse_ring: Line2D = get_node_or_null("Pulse")
@onready var lunge_line: Line2D = get_node_or_null("Lunge")
@onready var name_label: Label = get_node_or_null("Name")
@onready var timer_label: Label = get_node_or_null("Timer")


func _ready() -> void:
	_lunge_cd = lunge_interval
	_refresh_visual()


func god_color() -> Color:
	return ROLE_COLOR.get(str(god_id), Color.WHITE)


# The base this god protects, the mortals' base it raids, and how big a base is.
func set_stage(own_base: Vector2, enemy_base: Vector2, base_radius := 46.0) -> void:
	base_center = own_base
	target_center = enemy_base
	safe_radius = base_radius


# How close a touch has to be to tag a mortal: Mayari's moonlight reaches further.
func reach() -> float:
	return tag_radius * (moon_reach if god_id == &"mayari" else 1.0)


func speed() -> float:
	var walk := move_speed * speed_mult
	if god_id == &"mayari":
		walk *= moon_speed
	if god_id == &"bathala" and watch_target != Vector2.INF and watcher_speed > 0.0:
		walk *= watcher_speed
	return walk


# A mortal's swing: the god freezes for `seconds`, and a lunge in progress stops.
func freeze_for(seconds: float) -> void:
	frozen = true
	freeze_left = maxf(0.0, seconds)
	windup = 0.0
	lunge_left = 0.0


# A live god's touch (or Hanan's dawn) thaws a frozen god at once.
func unfreeze() -> void:
	frozen = false
	freeze_left = 0.0


# Back to the start of a round: no freeze, no lunge half-way through.
func reset_round() -> void:
	unfreeze()
	windup = 0.0
	lunge_left = 0.0
	pulse_flash = 0.0
	watch_target = Vector2.INF
	_lunge_cd = lunge_interval


# Hanan's dawn: show the ring of light for `seconds`.
func show_pulse(seconds: float) -> void:
	pulse_flash = seconds


# Where this god wants to walk this frame. `mortals` holds the positions of the
# mortals that can still be tagged (the frozen ones are left out).
func _desired_position(mortals: Array) -> Vector2:
	_chasing = false
	if god_id == &"bathala":
		if watch_target != Vector2.INF and watcher_speed > 0.0:
			return _within_ring(watch_target)
		return _circle_point(base_center)
	if _wander == Vector2.ZERO:
		_wander = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 40.0
	var raider := _nearest(mortals, base_center)
	if role == Role.DEFEND:
		if raider != Vector2.INF and raider.distance_to(base_center) < defend_wake:
			_chasing = true
			return raider
		return base_center + _wander
	# An attacker drops back only for a mortal at Bathala's base...
	if raider != Vector2.INF and raider.distance_to(base_center) < attack_switch:
		_chasing = true
		return raider
	# ...chases one only when it is close and off its safe base...
	var near := _nearest(mortals, global_position)
	if near != Vector2.INF and near.distance_to(global_position) < chase_radius \
			and near.distance_to(target_center) > safe_radius:
		if god_id == &"mayari":
			return Vector2(global_position.x, near.y)  # she guards the lane instead
		_chasing = true
		return near
	# ...and otherwise pushes into the mortals' base and holds it.
	return target_center + _wander * 0.5


func _nearest(mortals: Array, from: Vector2) -> Vector2:
	var best := Vector2.INF
	for pos in mortals:
		if best == Vector2.INF or (pos as Vector2).distance_squared_to(from) < best.distance_squared_to(from):
			best = pos
	return best


# A point on the circle Bathala walks around his base - he never leaves the guard.
func _circle_point(center: Vector2) -> Vector2:
	circle_phase += circle_dir * 0.9 * 0.016  # a slow, steady orbit
	return center + Vector2(cos(circle_phase), sin(circle_phase) * 0.55) * guard_radius


# Bathala walks at a holder, but never further from his base than his ring.
func _within_ring(point: Vector2) -> Vector2:
	return base_center + (point - base_center).limit_length(guard_radius)


# The host walks the god here each frame (a client mirrors it through the tick).
func step(delta: float, mortals: Array) -> void:
	_pulse += delta
	pulse_flash = maxf(0.0, pulse_flash - delta)
	if frozen:
		freeze_left = maxf(0.0, freeze_left - delta)
		if freeze_left <= 0.0:
			frozen = false  # thawed on its own
		_refresh_visual()
		return
	# Apolaki's lunge: the dash, then the wind-up before it, each a short state.
	if lunge_left > 0.0:
		lunge_left = maxf(0.0, lunge_left - delta)
		global_position += lunge_dir * (lunge_distance / maxf(0.01, lunge_time)) * delta
		_refresh_visual()
		return
	if windup > 0.0:
		windup = maxf(0.0, windup - delta)
		if windup <= 0.0:
			lunge_left = lunge_time
		_refresh_visual()
		return
	_think -= delta
	if _think <= 0.0:
		_think = decision_interval
		_wander = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 40.0
		if randf() < 0.5:
			circle_dir = -circle_dir
	var goal := _desired_position(mortals)
	_lunge_cd -= delta
	if god_id == &"apolaki" and lunge_interval > 0.0 and _lunge_cd <= 0.0 and _chasing \
			and goal.distance_to(global_position) > 1.0:
		_lunge_cd = lunge_interval
		lunge_dir = (goal - global_position).normalized()
		windup = lunge_windup
		_refresh_visual()
		return
	global_position = global_position.move_toward(goal, speed() * delta)
	_refresh_visual()


# Mirror pose on a client.
func place(at: Vector2) -> void:
	global_position = at


func is_frozen() -> bool:
	return frozen


# A circle of `radius` for the Reach and Pulse lines (their width stays as drawn).
func _circle(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(33):
		var angle := TAU * index / 32.0
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _refresh_visual() -> void:
	var tint := god_color()
	if icon != null:
		# A frozen god dims, a winding-up Apolaki flashes, a hunting god burns a
		# little brighter.
		var alpha := 0.55 if frozen else 0.92 + 0.08 * sin(_pulse * 5.0)
		icon.modulate = Color(1, 1, 1, alpha) if windup > 0.0 and fmod(windup, 0.1) < 0.05 \
			else Color(tint.r, tint.g, tint.b, alpha)
	if ring != null:
		# Bathala's ring carries his gold, so the dark grey still reads on the field.
		var edge := UITokens.GOLD if god_id == &"bathala" else tint
		ring.default_color = Color(edge.r, edge.g, edge.b, 0.5 if god_id != &"bathala" else 0.85)
		ring.visible = not frozen
	if reach_ring != null:
		reach_ring.visible = god_id == &"mayari" and not frozen
		if reach_ring.visible:
			reach_ring.points = _circle(reach())
	if pulse_ring != null:
		pulse_ring.visible = god_id == &"hanan" and pulse_flash > 0.0
		if pulse_ring.visible:
			pulse_ring.points = _circle(pulse_radius)
	if lunge_line != null:
		lunge_line.visible = windup > 0.0
		if lunge_line.visible:
			lunge_line.points = PackedVector2Array([Vector2.ZERO, lunge_dir * lunge_distance])
	if name_label != null:
		name_label.text = str(god_id).to_upper()
		name_label.modulate = Color(1, 1, 1, 0.55 if frozen else 0.75)
	if timer_label != null:
		if frozen:
			timer_label.visible = true
			timer_label.text = "%d" % int(ceil(freeze_left))
			timer_label.add_theme_color_override("font_color", UITokens.EMBER)
		else:
			timer_label.visible = false
