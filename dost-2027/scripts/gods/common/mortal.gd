class_name ArenaMortal
extends CharacterBody2D

# The mortal a player controls inside a god's arena.
# WASD / arrow keys move it (the project's move_* actions). An arena can lock
# movement during dialogue and shove the mortal around when a god or a clone
# interrupts them.
#
# Every visual lives in Mortal.tscn (Sprite, Glow, NameTag, FloatingStatus) -
# this script never draws and never builds nodes on the fly. Sprite is an
# AnimatedSprite2D and carries the authored clips (the idle walk, plus the arnis
# strike and guard): an arena plays them and reads the running frame back, so the
# body holds the art while the arena keeps the rules.
#
# FACING: the authored art faces right, so a move to the left mirrors the sprite
# (AnimatedSprite2D.flip_h) and slides the attack area + standing collision to
# the mirror side of the mortal (their authored x offsets are multiplied by
# `facing`). The facing is read from whatever is actually moving the mortal this
# frame - player input, a forced move, a knockback, or, for a remote ghost the
# arena glides towards its last reported position, the distance travelled - so
# every ArenaMortal (the local player and every ghost) turns to face its motion.

@export var move_speed := 215.0

var locked := false
var bounds := Rect2()
var ring_color := Color(1, 0.95, 0.8)
var radius := 13.0

# Which way the mortal faces: 1 = right (the way the art is drawn), -1 = left.
var facing := 1

var _stun := 0.0
var _knockback := Vector2.ZERO
var _forced_move_time := 0.0
var _forced_move_direction := Vector2.ZERO
var _dash_time := 0.0
var _dash_velocity := Vector2.ZERO
var _bob := 0.0
var _flash := 0.0
var _floating_time := 0.0
var _floating_velocity := Vector2.ZERO

# Where the combat pieces sit in the authored scene; the facing mirrors their x
# offsets (and their scale, so a non-symmetric shape would mirror too).
var _area_offset_x := 0.0
var _collision_offset_x := 0.0
var _last_position := Vector2.ZERO

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var glow: Sprite2D = $Glow
@onready var name_tag: Label = $NameTag
@onready var floating_text: Label = $FloatingStatus
@onready var damage_area: Area2D = get_node("Arnis-Damage-Area")
@onready var body_collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# Read the authored offsets back and mirror them from the very first frame,
	# so a scene that places the strike area off-centre keeps working flipped.
	_area_offset_x = damage_area.position.x if damage_area != null else 0.0
	_collision_offset_x = body_collision.position.x if body_collision != null else 0.0
	_last_position = global_position
	_apply_facing()


func is_stunned() -> bool:
	return _stun > 0.0


func hit(direction: Vector2, stun_time := 1.4, force := 420.0) -> void:
	_stun = maxf(_stun, stun_time)
	_knockback = direction.normalized() * force
	_flash = 0.35


func force_movement(direction: Vector2, duration: float) -> void:
	_forced_move_direction = direction.normalized()
	_forced_move_time = maxf(_forced_move_time, duration)


# A quick burst of `distance` pixels over `time` seconds along `direction`, or
# the way the mortal faces when it is zero (standing still). Walls and the
# arena's bounds still stop it.
func dash(direction: Vector2, distance: float, time: float) -> void:
	var way := direction.normalized() if direction.length() > 0.01 else Vector2(facing, 0.0)
	_dash_time = maxf(0.01, time)
	_dash_velocity = way * distance / _dash_time


func is_dashing() -> bool:
	return _dash_time > 0.0


func set_lock(value: bool) -> void:
	locked = value
	if locked:
		velocity = Vector2.ZERO


# Name tag for networked mortals (ghosts and the local player).
func set_display_name(text: String, tint := Color(1, 1, 1, 0.85)) -> void:
	if name_tag == null:
		return
	name_tag.text = text
	name_tag.add_theme_color_override("font_color", tint)
	name_tag.visible = text != ""


func show_floating_text(text: String, tint := Color.WHITE, duration := 2.2) -> void:
	if floating_text == null:
		return
	floating_text.text = text
	floating_text.modulate = tint
	floating_text.visible = true
	_floating_time = duration
	_floating_velocity = Vector2(0.0, -18.0)


# --- ANIMATION ---------------------------------------------------------------
# The clips an arena can play (authored on Sprite in Mortal.tscn). The mortal
# only plays them and reports back the running clip and its frame, so a game can
# open a strike's hit window on one frame and close it on another without the
# body ever knowing the rules.

const ANIM_IDLE := &"default"

# Play an authored clip. An unknown name is ignored, so a mortal in an arena
# that never strikes simply keeps its idle.
func play_animation(anim: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(anim):
		return
	if sprite.animation == anim and sprite.is_playing():
		return
	sprite.play(anim)


func current_animation() -> StringName:
	return sprite.animation if sprite != null else &""


# The frame the clip is showing right now (-1 when there is no sprite).
func animation_frame() -> int:
	return sprite.frame if sprite != null else -1


# True while `anim` (or any clip, when it is left empty) is still running. A
# one-shot clip reports false once it has played out, which is how an arena
# knows to hand the mortal back to its idle.
func is_animation_playing(anim: StringName = &"") -> bool:
	if sprite == null:
		return false
	if anim != &"" and sprite.animation != anim:
		return false
	return sprite.is_playing()


# --- FACING ----------------------------------------------------------------
# The art faces right. Whoever is actually moving the mortal decides the facing:
# an input-driven player has a live velocity; a ghost the arena glides towards
# its last reported position has none - so use the distance travelled when the
# velocity has nothing to say. Facing only changes on real motion; a mortal that
# is standing (or shoved straight up/down/into a wall) keeps its last direction.
func _update_facing() -> void:
	var moved := global_position - _last_position
	_last_position = global_position
	var basis := velocity if absf(velocity.x) > 4.0 else moved
	if absf(basis.x) < 4.0:
		return
	var new_facing := 1 if basis.x > 0.0 else -1
	if new_facing == facing:
		return
	facing = new_facing
	_apply_facing()


# Mirror every side-specific piece of the mortal to the current facing: the
# sprite texture, the attack area's offset and scale (so a non-symmetric shape
# truly mirrors) and the standing collision's offset and scale.
func _apply_facing() -> void:
	if sprite != null:
		sprite.flip_h = facing < 0
	if damage_area != null:
		damage_area.position.x = _area_offset_x * facing
		damage_area.scale.x = facing
	if body_collision != null:
		body_collision.position.x = _collision_offset_x * facing
		body_collision.scale.x = facing


func _physics_process(delta: float) -> void:
	if _stun > 0.0:
		_stun = maxf(0.0, _stun - delta)
		velocity = _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, 1400.0 * delta)
	elif _dash_time > 0.0:
		velocity = _dash_velocity
		_dash_time -= delta
		if _dash_time < 0.001:
			_dash_time = 0.0  # 0.15s at 60 FPS is 9 frames, not a 10th from rounding
	elif _forced_move_time > 0.0:
		_forced_move_time = maxf(0.0, _forced_move_time - delta)
		velocity = _forced_move_direction * move_speed
	elif locked:
		velocity = Vector2.ZERO
	else:
		velocity = Input.get_vector("move_left", "move_right", "move_up", "move_down") * move_speed

	move_and_slide()
	if bounds.size != Vector2.ZERO:
		global_position.x = clampf(global_position.x, bounds.position.x + radius, bounds.end.x - radius)
		global_position.y = clampf(global_position.y, bounds.position.y + radius, bounds.end.y - radius)

	_update_facing()

	_bob += delta
	if sprite != null:
		sprite.position.y = sin(_bob * 7.0) * 1.5
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	if glow != null:
		var settings := get_node_or_null("/root/Settings")  # by path so checks compile without the autoload
		var calm: bool = settings != null and bool(settings.call("reduce_flashing"))
		var hit_alpha := 0.35 if calm else 0.7  # steady tint instead of a bright flash
		var glow_alpha := 0.25 if _flash <= 0.0 else hit_alpha
		glow.modulate = Color(ring_color.r, ring_color.g, ring_color.b, glow_alpha)
	if floating_text != null and floating_text.visible:
		_floating_time = maxf(0.0, _floating_time - delta)
		floating_text.position += _floating_velocity * delta
		floating_text.rotation = sin(Time.get_ticks_msec() * 0.02) * 0.04
		floating_text.modulate.a = clampf(_floating_time, 0.0, 1.0)
		if _floating_time <= 0.0:
			floating_text.visible = false
