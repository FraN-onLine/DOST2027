class_name ApolakiDuelist
extends Node2D

# Apolaki as a mortal meets him in ARNIS - one of him per screen, because the
# duel is personal: every player fights their OWN Apolaki, and the only things
# that travel between players are FAVOR and the favors themselves
# (see scripts/gods/apolaki/apolaki_arena.gd).
#
# THREE states, and that is the whole duel. IDLE is the hub: he walks toward
# the mortal and watches. From there he either swings (ATTACK) or raises his
# stick (DEFEND), then goes back to IDLE. He keeps walking whichever state he
# is in - a swing or a guard never freezes him in place.
#
#   the mortal strikes him -> IDLE or ATTACK pays the mortal, DEFEND costs them
#   his swing lands        -> the mortal IDLE or ATTACKing pays, DEFENDING gains
#
# The arena owns the FAVOR. This script owns his three states, his walk, which
# way he faces, and the frame window his swing is live on - and it announces a
# swing that actually connected (inside his area) so the arena can score it.
#
# Art lives in Apolaki.tscn: Icon (an AnimatedSprite2D whose frames carry the
# states) and Name. This script never draws. The three clips are the whole
# tell: "default" is him watching, "hit" draws the ring that winds a swing up -
# that ring IS the telegraph - and "defend" raises the stick.
#
# WHAT A BLOW DOES TO HIM - the duel has no shared hitbox, so the weight of a
# landed strike is built right here: hit_from() shoves him away from the blow
# (knock_force, decayed to a stop), lights him up for hit_flash_time and reels
# him for hit_stagger_time - while he reels he walks nowhere and picks no new
# move, but the shove and the flare keep running so the hit stays readable.
# The flare follows the Reduce flashing option (a steady tint, never a strobe -
# the same rule the mortal's own glow follows in scripts/gods/common/mortal.gd).
# The field shaking around him belongs to the arena (apolaki_arena.gd).

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
@export var attack_hit_open_frame := 5   # his swing is live from this frame...
@export var attack_hit_close_frame := 8  # ...through this one of the clip
@export var idle_time := 0.7        # how long he watches before his next move
@export var attack_time := 1.0      # how long one swing lasts (its clip plays out)
@export var defend_time := 1.6      # how long a guard holds
@export var defend_chance := 0.35   # how often his next move is a guard
# The sheet is drawn facing LEFT, so he is mirrored when the mortal stands to
# his right. Flip this if a new sheet is drawn the other way round.
@export var art_facing := -1
# WHAT A LANDED STRIKE DOES TO HIM - the other half of the duel's weight (his
# own swing on the mortal is scored in apolaki_arena.gd).
@export var knock_force := 380.0      # how hard a landed strike shoves him
@export var knock_stop := 1500.0      # px/s the shove sheds every second
@export var hit_flash_time := 0.3     # seconds his flare stays up
@export var hit_stagger_time := 0.18  # seconds he reels after a landed strike

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
var _knock_velocity := Vector2.ZERO  # the shove a landed strike gave him
var _hit_flash := 0.0               # seconds of flare left
var _stagger := 0.0                 # seconds he still reels for

@onready var icon: AnimatedSprite2D = get_node_or_null("Icon")
@onready var name_label: Label = get_node_or_null("Name")


func _ready() -> void:
	_rng.randomize()
	_origin = position
	_enter(State.IDLE)


# Back to the spot he was parked on, watching, as a round begins - with the
# shove, the flare and the reel all spent.
func restart() -> void:
	global_position = _origin
	target = _origin
	_knock_velocity = Vector2.ZERO
	_hit_flash = 0.0
	_stagger = 0.0
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


# --- WHAT A LANDED STRIKE DOES TO HIM ----------------------------------------
# A blow landed on him comes from `from_position`: he is shoved away from it,
# flares up and reels - the same weight ArenaMortal.hit gives the mortal on the
# other side of the duel. `force` of 0 keeps his own knock_force, so a clash on
# his guard can brace him back softer than a clean hit without a second rule.
func hit_from(from_position: Vector2, force := 0.0) -> void:
	var shove := global_position - from_position
	if shove.length() < 0.01:
		shove = Vector2.LEFT
	_knock_velocity = shove.normalized() * (knock_force if force <= 0.0 else force)
	_hit_flash = hit_flash_time
	_stagger = hit_stagger_time


# True while a landed strike is still reeling him (the arena's state label and
# any future tells can read it).
func is_reeling() -> bool:
	return _stagger > 0.0


# The shove itself. He is a plain node, not a body, so his knockback is his own
# to run: it moves him every frame and sheds speed until it stops, kept inside
# the field the same way his walk is.
func _tick_knockback(delta: float) -> void:
	if _knock_velocity.length() < 1.0:
		_knock_velocity = Vector2.ZERO
		return
	global_position += _knock_velocity * delta
	_knock_velocity = _knock_velocity.move_toward(Vector2.ZERO, knock_stop * delta)
	if bounds.has_area():
		global_position = global_position.clamp(bounds.position, bounds.end)


# Player comfort options live in the Settings autoload and are looked up by
# path, so scripts loaded before the autoloads exist (the tools/ checks) still
# compile - the same trick Arena.reduce_flashing uses.
func _reduce_flashing() -> bool:
	var settings := get_node_or_null("/root/Settings")
	return settings != null and bool(settings.call("reduce_flashing"))


func _process(delta: float) -> void:
	_pulse += delta
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta)
	if not frozen:
		# The shove runs through the reel: he is flung back even while he is
		# still recovering from the blow.
		_tick_knockback(delta)
		if _stagger > 0.0:
			# REELING: no walk, no new move and no swing window until it passes,
			# so a landed strike visibly interrupts him for a moment.
			_stagger = maxf(0.0, _stagger - delta)
		else:
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
# attack clip, and only while the mortal stands inside his area (the duelist
# checks that itself, so the arena is only told about real hits).
# The window stays open for ALL of those frames: a swing is only spent once it
# actually connects, so a mortal who was a step too far away on one live frame
# and closes the distance on the next still gets hit. (Spending the swing on the
# first live frame it saw - whether or not the mortal was in reach - is what let
# his stick pass through a mortal now and then with nothing to show for it.)
# If the window closes without the mortal ever stepping inside his area, the
# swing simply missed.
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
	if in_reach(target):
		_hit_resolved = true
		attack_landed.emit()


func _move(delta: float) -> void:
	# He walks through every state: a swing and a guard no longer plant him, so
	# he keeps closing the distance (or backing off) for the whole clip - he can
	# swing on the move and guard on the move.
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
	_face_target()
	var pulse := 0.5 + 0.5 * sin(_pulse * (10.0 if state == State.ATTACK else 4.0))
	if icon != null:
		match state:
			State.ATTACK:
				icon.modulate = Color(1.0, 0.82, 0.55, 1.0)
			State.DEFEND:
				icon.modulate = Color(color.r, color.g, color.b, 1.0)
			_:
				icon.modulate = Color(1, 1, 1, 1)
		# A landed strike flares on top of the state tint and fades out over
		# hit_flash_time. Under Reduce flashing the flare is a steady, softer
		# ember tint for the whole window instead of a white one that pulses
		# down - the hit still reads, nothing strobes.
		if _hit_flash > 0.0:
			if _reduce_flashing():
				icon.modulate = icon.modulate.lerp(Color(1.0, 0.45, 0.35), 0.4)
			else:
				var strength := clampf(_hit_flash / maxf(hit_flash_time, 0.001), 0.0, 1.0)
				icon.modulate = icon.modulate.lerp(Color(1.0, 1.0, 1.0), strength)
	if name_label != null:
		name_label.text = "APOLAKI"
		name_label.modulate = Color(1, 1, 1, 0.55 + 0.4 * pulse)


# HE TURNS TO WHOMEVER HE IS DUELLING: the sprite mirrors whenever the mortal
# stands on the side the art is not drawn for, so his stick always points at
# whoever he is stalking (the same facing rule the mortal itself follows, see
# scripts/gods/common/mortal.gd). The name tag never flips.
func _face_target() -> void:
	if icon == null:
		return
	var toward := target.x - global_position.x
	if absf(toward) < 0.5:
		return  # straight above / below: keep facing whatever he faced before
	icon.flip_h = (1 if toward > 0.0 else -1) != art_facing
