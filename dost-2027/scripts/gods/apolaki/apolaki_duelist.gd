class_name ApolakiDuelist
extends Node2D

# Apolaki as a mortal meets him in ARNIS - one of him per screen, because the
# duel is personal: every player fights their OWN Apolaki, and the only things
# that travel between players are FAVOR and the favors themselves
# (see scripts/gods/apolaki/apolaki_arena.gd).
#
# He stalks, guards and lunges. He is OPEN for a moment (his blind spot) and
# that is when a strike lands clean; strike into his GUARD and you pay for it.
# A mortal blocks his lunge by pressing defend within the window the arena
# watches - the duelist only announces that the lunge landed.
#
# Art lives in Apolaki.tscn: Icon (the Godot placeholder), Name and Telegraph
# (the warning that a lunge is winding up). This script never draws.

signal lunge()                 # the strike just landed - the arena resolves it
signal state_changed(new_state: int)

enum State { NEUTRAL, OPEN, GUARD, WINDUP, STRIKE, RECOVER }

@export var speed := 74.0          # how fast he closes the distance
@export var keep_distance := 94.0  # how close he wants to stand
@export var reach := 92.0          # how near a strike has to be to connect
@export var open_time := 0.7       # the blind-spot window
@export var guard_time := 0.95     # how long a guard holds
@export var neutral_time := 0.8    # how long he just watches
@export var windup_time := 0.55    # the telegraph before a lunge
@export var recover_time := 0.7    # how long he is spent after a lunge/hit
@export var open_chance := 0.42    # weight of a blind spot in the cycle

var state := State.NEUTRAL
var color := Color(1.0, 0.85, 0.25)
var frozen := true          # the arena unfreezes him only while the trial runs
var target := Vector2.ZERO  # where the mortal stands
var bounds := Rect2()

var _timer := 0.0
var _pulse := 0.0
var _rng := RandomNumberGenerator.new()
var _origin := Vector2.ZERO

@onready var icon: Sprite2D = get_node_or_null("Icon")
@onready var name_label: Label = get_node_or_null("Name")
@onready var telegraph: Sprite2D = get_node_or_null("Telegraph")


func _ready() -> void:
	_rng.randomize()
	_origin = position
	_enter(State.NEUTRAL)


# Back to the spot he was parked on, watching, as a round begins.
func restart() -> void:
	global_position = _origin
	target = _origin
	_enter(State.NEUTRAL)


func set_duel_spawn(value: Vector2) -> void:
	_origin = value
	global_position = value
	target = value


func is_open() -> bool:
	return state == State.OPEN


func is_guarding() -> bool:
	return state == State.GUARD


func in_reach(point: Vector2) -> bool:
	return global_position.distance_to(point) <= reach


# Hit while open or just watching: he is knocked back a step and spends a moment
# recovering, so a clean strike cannot be chained into another one.
func flinch() -> void:
	_enter(State.RECOVER)


func _process(delta: float) -> void:
	_pulse += delta
	if not frozen:
		_move(delta)
		_advance(delta)
	_refresh()


func _advance(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	match state:
		State.WINDUP:
			_enter(State.STRIKE)
			lunge.emit()
		State.STRIKE, State.RECOVER:
			_enter(State.NEUTRAL)
		_:
			_pick()


func _pick() -> void:
	var roll := _rng.randf()
	if roll < open_chance:
		_enter(State.OPEN)
	elif roll < open_chance + 0.32:
		_enter(State.GUARD)
	else:
		_enter(State.WINDUP)


func _enter(new_state: State) -> void:
	state = new_state
	match new_state:
		State.OPEN:
			_timer = open_time
		State.GUARD:
			_timer = guard_time
		State.WINDUP:
			_timer = windup_time
		State.STRIKE:
			_timer = 0.22
		State.RECOVER:
			_timer = recover_time
		_:
			_timer = neutral_time
	state_changed.emit(int(new_state))


func _move(delta: float) -> void:
	var to_target := target - global_position
	var distance := to_target.length()
	if distance < 0.01:
		return
	var direction := to_target / distance
	if distance > keep_distance + 6.0:
		global_position += direction * speed * delta
	elif distance < keep_distance - 14.0:
		global_position -= direction * speed * 0.7 * delta
	if bounds.has_area():
		global_position = global_position.clamp(bounds.position, bounds.end)


func _refresh() -> void:
	# Open burns bright and steady (a blind spot); a wind-up flashes a warning;
	# a guard is a solid, cooler gold.
	var pulse := 0.5 + 0.5 * sin(_pulse * (10.0 if state == State.WINDUP else 4.0))
	if icon != null:
		match state:
			State.OPEN:
				icon.modulate = Color(1.0, 0.98, 0.75, 1.0)
			State.WINDUP:
				icon.modulate = Color(1.0, 0.9, 0.45, 1.0)
			State.GUARD:
				icon.modulate = Color(color.r, color.g, color.b, 0.95)
			_:
				icon.modulate = Color(color.r, color.g, color.b, 0.85)
	if telegraph != null:
		telegraph.visible = state == State.WINDUP or state == State.OPEN
		if state == State.WINDUP:
			telegraph.modulate = Color(1.0, 0.45, 0.25, 0.25 + 0.35 * pulse)
		else:
			telegraph.modulate = Color(1.0, 0.95, 0.6, 0.18 + 0.18 * pulse)
	if name_label != null:
		name_label.text = "APOLAKI"
		name_label.modulate = Color(1, 1, 1, 0.55 + 0.4 * pulse)
