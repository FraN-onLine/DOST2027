extends CharacterBody2D

# The mortal you control in an arena: WASD / arrow keys to move (the project's
# move_* actions). The arena can lock movement during dialogue and shove the
# mortal around when a god or a clone interrupts them.

@export var move_speed := 215.0

var locked := false
var bounds := Rect2()
var ring_color := Color(1, 0.95, 0.8)
var radius := 13.0

var _stun := 0.0
var _knockback := Vector2.ZERO
var _bob := 0.0
var _flash := 0.0

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	queue_redraw()


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
	var tag := get_node_or_null("NameTag") as Label
	if tag == null:
		tag = Label.new()
		tag.name = "NameTag"
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(tag)
	tag.text = text
	tag.add_theme_font_size_override("font_size", 10)
	tag.add_theme_color_override("font_color", tint)
	tag.position = Vector2(-60.0, -40.0)
	tag.size = Vector2(120.0, 16.0)


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
		queue_redraw()


func _draw() -> void:
	var glow := ring_color
	glow.a = 0.25 if _flash <= 0.0 else 0.7
	draw_circle(Vector2.ZERO, radius + 6.0, glow)
	draw_circle(Vector2.ZERO, radius + 2.0, Color(0.05, 0.06, 0.1, 0.9))
	draw_arc(Vector2.ZERO, radius + 2.0, 0.0, TAU, 24, ring_color, 2.0)
