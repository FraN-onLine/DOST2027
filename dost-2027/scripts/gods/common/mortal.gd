class_name ArenaMortal
extends CharacterBody2D

# The mortal a player controls inside a god's arena.
# WASD / arrow keys move it (the project's move_* actions). An arena can lock
# movement during dialogue and shove the mortal around when a god or a clone
# interrupts them.
#
# Every visual lives in Mortal.tscn (Sprite, Glow, NameTag, FloatingStatus) -
# this script never draws and never builds nodes on the fly.

@export var move_speed := 215.0

var locked := false
var bounds := Rect2()
var ring_color := Color(1, 0.95, 0.8)
var radius := 13.0

var _stun := 0.0
var _knockback := Vector2.ZERO
var _bob := 0.0
var _flash := 0.0
var _floating_time := 0.0
var _floating_velocity := Vector2.ZERO

@onready var sprite: Sprite2D = $Sprite
@onready var glow: Sprite2D = $Glow
@onready var name_tag: Label = $NameTag
@onready var floating_text: Label = $FloatingStatus


func is_stunned() -> bool:
	return _stun > 0.0


func hit(direction: Vector2, stun_time := 1.4, force := 420.0) -> void:
	_stun = maxf(_stun, stun_time)
	_knockback = direction.normalized() * force
	_flash = 0.35


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


func _physics_process(delta: float) -> void:
	if _stun > 0.0:
		_stun = maxf(0.0, _stun - delta)
		velocity = _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, 1400.0 * delta)
	elif locked:
		velocity = Vector2.ZERO
	else:
		velocity = Input.get_vector("move_left", "move_right", "move_up", "move_down") * move_speed

	move_and_slide()
	if bounds.size != Vector2.ZERO:
		global_position.x = clampf(global_position.x, bounds.position.x + radius, bounds.end.x - radius)
		global_position.y = clampf(global_position.y, bounds.position.y + radius, bounds.end.y - radius)

	_bob += delta
	if sprite != null:
		sprite.position.y = sin(_bob * 7.0) * 1.5
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	if glow != null:
		var glow_alpha := 0.25 if _flash <= 0.0 else 0.7
		glow.modulate = Color(ring_color.r, ring_color.g, ring_color.b, glow_alpha)
	if floating_text != null and floating_text.visible:
		_floating_time = maxf(0.0, _floating_time - delta)
		floating_text.position += _floating_velocity * delta
		floating_text.rotation = sin(Time.get_ticks_msec() * 0.02) * 0.04
		floating_text.modulate.a = clampf(_floating_time, 0.0, 1.0)
		if _floating_time <= 0.0:
			floating_text.visible = false
