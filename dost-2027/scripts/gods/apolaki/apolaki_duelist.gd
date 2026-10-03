class_name ApolakiDuelist
extends Node2D

# Apolaki as a mortal meets him in ARNIS - one of him per screen, because the
# duel is personal: every player fights their OWN Apolaki, and the only things
# that travel between players are FAVOR and the favors themselves
# (see scripts/gods/apolaki/apolaki_arena.gd).
#
# THREE states, and that is the whole duel. IDLE is the hub: he walks toward
# the mortal and watches. From there he either swings (ATTACK) or raises his
# stick (DEFEND), then goes back to IDLE.
#
#   the mortal strikes him -> IDLE or ATTACK pays the mortal, DEFEND costs them
#   his swing lands        -> the mortal IDLE or ATTACKing pays, DEFENDING gains
#
# The arena owns the FAVOR. This script owns his three states, his walk, and the
# frame window his swing is live on - and it announces a swing that actually
# connected (inside his area) so the arena can score it.
#
# Art lives in Apolaki.tscn: Icon (an AnimatedSprite2D whose frames carry the
# states) and Name. This script never draws. The three clips are the whole
# tell: "default" is him watching, "hit" draws the ring that winds a swing up -
# that ring IS the telegraph - and "defend" raises the stick.

signal attack_landed()         # his swing connected - the arena scores it
signal state_changed(new_state: int)

enum State { IDLE, ATTACK, DEFEND }

# The three authored clips. The frames ARE the states, so a state change is a
# clip change.
const ANIM_IDLE := &"default"   # watching / stalking
const ANIM_ATTACK := &"hit"     # the ring - the tell before the swing lands
const ANIM_DEFEND := &"defend"  # the raised-stick guard

@export var speed := 74.0           # how fast he closes the distance
@export var keep_distance := 80.0   # how close he stands while idle
@export var reach := 92.0           # HIS AREA: a swing only lands this close
@export var attack_hit_open_frame := 2   # his swing is live from this frame...
@export var attack_hit_close_frame := 5  # ...through this one of the clip
@export var idle_time := 0.9        # how long he watches before his next move
@export var attack_time := 0.6      # how long one swing lasts
@export var defend_time := 0.9      # how long a guard holds
@export var defend_chance := 0.35   # how often his next move is a guard

var state := State.IDLE
var color := Color(1.0, 0.85, 0.25)
var frozen := true          # the arena unfreezes him only while the trial runs
var target := Vector2.ZERO  # where the mortal stands
var bounds := Rect2()

var _timer := 0.0
var _pulse := 0.0
var _rng := RandomNumberGenerator.new()
var _origin := Vector2.ZERO
var _hit_resolved := false  # this swing has already been offered

@onready var icon: AnimatedSprite2D = get_node_or_null("Icon")
@onready var name_label: Label = get_node_or_null("Name")


func _ready() -> void:
	_rng.randomize()
	_origin = position
	_enter(State.IDLE)


# Back to the spot he was parked on, watching, as a round begins.
func restart() -> void:
	global_position = _origin
	target = _origin
	_enter(State.IDLE)


func set_duel_spawn(value: Vector2) -> void:
	_origin = value
	global_position = value
	target = value


func is_idle() -> bool:
	return state == State.IDLE


func is_attacking() -> bool:
	return state == State.ATTACK


func is_defending() -> bool:
	return state == State.DEFEND


# HIS AREA: the mortal has to be standing this close while his swing is live,
# or the swing misses.
func in_reach(point: Vector2) -> bool:
	return global_position.distance_to(point) <= reach


# The mortal's own reach is a little longer than his, so closing the distance
# is what makes a strike able to land at all.
func in_reach_with_bonus(point: Vector2, bonus: float) -> bool:
	return global_position.distance_to(point) <= reach + bonus


func _process(delta: float) -> void:
	_pulse += delta
	if not frozen:
		_move(delta)
		_advance(delta)
		_tick_attack_window()
	_refresh()


func _advance(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	# IDLE is the hub: he watches, then picks his next move. Every other state is
	# one move and then straight back to IDLE.
	if state == State.IDLE:
		_enter(State.DEFEND if _rng.randf() < defend_chance else State.ATTACK)
	else:
		_enter(State.IDLE)


func _enter(new_state: State) -> void:
	state = new_state
	_hit_resolved = false
	match new_state:
		State.ATTACK:
			_timer = attack_time
		State.DEFEND:
			_timer = defend_time
		_:
			_timer = idle_time
	_play_for_state()
	state_changed.emit(int(new_state))


# Which clip a state shows: he watches, the ring winds a swing up, the raised
# stick is his guard.
func _play_for_state() -> void:
	if icon == null or icon.sprite_frames == null:
		return
	var anim := ANIM_IDLE
	match state:
		State.ATTACK:
			anim = ANIM_ATTACK
		State.DEFEND:
			anim = ANIM_DEFEND
	if icon.animation != anim:
		icon.play(anim)


# HIS SWING: live on frames attack_hit_open_frame..attack_hit_close_frame of the
# attack clip, once per swing, and only while the mortal stands inside his area
# (the duelist checks that itself, so the arena is only told about real hits).
# A clip too short to reach the window would mean a swing that can never land,
# so in that case the whole clip counts as live.
func _tick_attack_window() -> void:
	if state != State.ATTACK or _hit_resolved or icon == null or icon.sprite_frames == null:
		return
	var frames := icon.sprite_frames.get_frame_count(icon.animation)
	var open := attack_hit_open_frame
	var close := attack_hit_close_frame
	if frames <= attack_hit_close_frame:
		open = 0
		close = maxi(frames - 1, 0)
	var frame := icon.frame
	if frame < open or frame > close:
		return
	_hit_resolved = true
	if in_reach(target):
		attack_landed.emit()


func _move(delta: float) -> void:
	# Idle is the only chase: a swing and a guard both plant him where he is.
	if state != State.IDLE:
		return
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
	# The frames carry the states; only a swing and a guard take a tint so they
	# read at a glance, and the name breathes with the beat.
	var pulse := 0.5 + 0.5 * sin(_pulse * (10.0 if state == State.ATTACK else 4.0))
	if icon != null:
		match state:
			State.ATTACK:
				icon.modulate = Color(1.0, 0.82, 0.55, 1.0)
			State.DEFEND:
				icon.modulate = Color(color.r, color.g, color.b, 1.0)
			_:
				icon.modulate = Color(1, 1, 1, 1)
	if name_label != null:
		name_label.text = "APOLAKI"
		name_label.modulate = Color(1, 1, 1, 0.55 + 0.4 * pulse)
