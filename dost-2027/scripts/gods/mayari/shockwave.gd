class_name MayariShockwave
extends Node2D

# The little shockwave a mortal's attack throws out around itself in the
# patintero arena (MayariArena.gd spawns it, one per cast, on every screen).
#
# It is purely a VISUAL: the growing area that actually shoves the other mortals
# is computed by the arena's rules, and this scene only grows and fades to match
# it. Nothing here draws - the art lives in Shockwave.tscn:
#
#   Ring - a Line2D circle drawn at `base_radius`, scaled up as the wave grows.
#   Icon - a Sprite2D carrying the Godot placeholder (res://icon.svg), the same
#          stand-in every god and favor uses until real art arrives.
#
# The whole node scales from `start_scale` to `max_scale` over `expand_time`, so
# the wave starts really small and swells to its full size and area.

@export var base_radius := 100.0    # the radius Ring is drawn at in the scene
@export var max_scale := 1.3        # full size = base_radius * max_scale
@export var start_scale := 0.05     # where the wave is born
@export var expand_time := 0.45     # seconds from born to full size

@onready var ring: Line2D = get_node_or_null("Ring")
@onready var icon: Sprite2D = get_node_or_null("Icon")

var _age := 0.0


func _ready() -> void:
	scale = Vector2.ONE * start_scale
	modulate.a = 0.9


func _process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / maxf(0.01, expand_time), 0.0, 1.0)
	# Ease out: the wave leaps out of the mortal and settles as it reaches full.
	var eased := 1.0 - pow(1.0 - t, 3.0)
	scale = Vector2.ONE * lerpf(start_scale, max_scale, eased)
	modulate.a = 0.9 * (1.0 - t)
	if t >= 1.0:
		queue_free()


# How much of the field this wave covers, in world units - the arena uses the
# same number for the shove it applies, so the hitbox and the art stay together.
func reach() -> float:
	return base_radius * max_scale
