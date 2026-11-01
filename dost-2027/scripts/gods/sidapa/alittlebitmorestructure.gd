class_name ALittleBitMoreStructure
extends Node2D

# Sidapa's ring (scenes/gods/sidapa/ALittleBitMoreStructure.tscn). The arena
# only says how wide it is, what color it wears and how long is left; the fill,
# the rim, the wormhole and the count all live here so the look is editable
# without touching the rules.

@export var radius := 130.0
@export var tint := Color(0.62, 0.45, 0.95)
@export var swirl_speed := 0.9

@onready var fill: Polygon2D = $Fill
@onready var ring: Line2D = $Ring
@onready var wormhole: AnimatedSprite2D = $AnimatedSprite2D
@onready var area: Area2D = $Area2D
@onready var timer_label: Label = get_node_or_null("Timer Label")

var _exploding := false
var _time := 0.0


func _ready() -> void:
	_apply_radius()
	if wormhole != null and wormhole.sprite_frames != null and wormhole.sprite_frames.has_animation(&"default"):
		wormhole.play(&"default")


func setup(new_radius: float, color: Color) -> void:
	radius = maxf(1.0, new_radius)
	tint = color
	_apply_radius()


# The countdown over the ring: the whole seconds left, going red at the last one.
func set_remaining(left: float, urgent := false) -> void:
	if timer_label == null:
		return
	timer_label.text = str(maxi(1, int(ceil(left))))
	timer_label.add_theme_color_override("font_color", Color(0.88, 0.38, 0.31) if urgent else tint)


func set_pulse(alpha: float) -> void:
	if ring != null:
		ring.modulate.a = alpha


func is_exploding() -> bool:
	return _exploding


# The count ran out: the wormhole bursts and the whole ring tears itself apart.
# It frees itself when the burst is done, so the arena only has to forget it.
func explode() -> void:
	if _exploding:
		return
	_exploding = true
	if wormhole != null and wormhole.sprite_frames != null and wormhole.sprite_frames.has_animation(&"explode"):
		wormhole.play(&"explode")
	var tween := create_tween()
	for part in [fill, ring]:
		if part != null:
			tween.tween_property(part, "modulate:a", 0.0, 0.45)
	if timer_label != null:
		tween.tween_property(timer_label, "modulate:a", 0.0, 0.25)
	tween.tween_interval(0.35)
	tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	if _exploding:
		return
	_time += delta
	if wormhole != null and wormhole.animation == &"default":
		wormhole.rotation += delta * swirl_speed


func _apply_radius() -> void:
	if fill != null:
		fill.polygon = _circle(radius, 32)
		fill.color = Color(tint.r, tint.g, tint.b, 0.13)
	if ring != null:
		ring.points = _circle(radius, 48)
		ring.default_color = tint
	if area != null:
		var shape_node := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape_node != null:
			var circle := shape_node.shape as CircleShape2D
			if circle != null:
				circle.radius = radius
	if wormhole != null:
		wormhole.scale = Vector2.ONE * (radius / 64.0)
	if timer_label != null:
		timer_label.position = Vector2(-24.0, -radius - 28.0)
		timer_label.size = Vector2(48.0, 24.0)


func _circle(circle_radius: float, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		points.append(Vector2(cos(angle) * circle_radius, sin(angle) * circle_radius))
	return points
