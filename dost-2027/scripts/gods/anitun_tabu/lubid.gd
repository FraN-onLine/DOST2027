class_name LuksongLubid
extends Node2D

# The swinging lubid of Luksong Lubid (scenes/gods/anitun_tabu/Lubid.tscn).
# A rope strung from the top of the field to the bottom; the arena slides it
# across the field and the rope sways a little where it hangs. The arena owns
# where the rope is - this only draws it and carries its hitbox. Two wind
# fairies (FairyTop / FairyBottom) hold its ends and swing with it.

@export var width := 7.0
@export var sway := 8.0
@export var sway_speed := 3.0
@export var fairy_hold := 14.0  # px each fairy's body sits past the rope's end

@onready var rope: Line2D = $Rope
@onready var shine: Line2D = $Shine
@onready var hitbox: CollisionShape2D = $Area2D/CollisionShape2D
@onready var fairy_top: AnimatedSprite2D = get_node_or_null("FairyTop")
@onready var fairy_bottom: AnimatedSprite2D = get_node_or_null("FairyBottom")

var length := 0.0
var _phase := 0.0


func place(x: float, y_top: float, y_bottom: float) -> void:
	length = maxf(0.0, y_bottom - y_top)
	position = Vector2(x, y_top)
	if hitbox != null:
		var shape := hitbox.shape as RectangleShape2D
		if shape != null:
			shape.size = Vector2(width + 6.0, length)
		hitbox.position = Vector2(0.0, length * 0.5)
	_rebuild()


# How far the rope itself has strayed this frame - the arena reads it so a hit
# lands where the rope is drawn, not where its base sits.
func sway_offset() -> float:
	return sin(_phase) * sway


func _process(delta: float) -> void:
	_phase += delta * sway_speed
	_rebuild()


func _rebuild() -> void:
	if rope == null:
		return
	var points := PackedVector2Array()
	var segments := 14
	for index in range(segments + 1):
		var t := float(index) / float(segments)
		var point := Vector2.ZERO.lerp(Vector2(0.0, length), t)
		point.x += sin(_phase + t * 2.4) * sway * t
		points.append(point)
	rope.points = points
	if shine != null:
		shine.points = points
	# The two wind fairies hold the ends: the top one hangs above the rope's
	# head, the bottom one trails it by the same share of her body.
	if fairy_top != null:
		fairy_top.position = points[0] + Vector2(0.0, -fairy_hold)
	if fairy_bottom != null:
		fairy_bottom.position = points[points.size() - 1] + Vector2(0.0, fairy_hold)
