class_name WindBurst
extends Node2D

# A gust of Anitun Tabu's wind (scenes/gods/anitun_tabu/WindBurst.tscn). The
# authored clip is the whole of it: the wind wells up, frames 8-10 are the lift
# that catches a mortal, and frame 12 is the empty tail. The Area2D under the
# animation is the patch of ground that lift reaches - it is the hitbox, tuned
# in the scene, not in code. The arena pays the penalty - this only plays and
# answers.

@export var hit_first_frame := 8
@export var hit_last_frame := 10

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var hit_shape: CollisionShape2D = $Area2D/CollisionShape2D

var _playing := false


func play() -> void:
	_playing = true
	visible = true
	anim.frame = 0
	anim.frame_progress = 0.0
	anim.play(&"default")


func is_playing() -> bool:
	return _playing


# Only the lift catches: the frames the mortal is actually being thrown.
func is_hit_window() -> bool:
	return _playing and anim.frame >= hit_first_frame and anim.frame <= hit_last_frame


func is_finished() -> bool:
	return not _playing


# Whether a body standing at `at` is inside the authored Area2D. The capsule is
# tested in its own space, so the Area2D's offset and scale in the scene decide
# both the spot and the reach.
func catches(at: Vector2, body_radius := 0.0) -> bool:
	if not is_hit_window() or hit_shape == null:
		return false
	var capsule := hit_shape.shape as CapsuleShape2D
	if capsule == null:
		return false
	var xform := hit_shape.global_transform
	var local := xform.affine_inverse() * at
	var half := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
	var nearest := Vector2(0.0, clampf(local.y, -half, half))
	var reach := capsule.radius + body_radius / maxf(xform.get_scale().x, 0.001)
	return local.distance_to(nearest) <= reach


func _process(_delta: float) -> void:
	if _playing and not anim.is_playing():
		_playing = false
		visible = false
