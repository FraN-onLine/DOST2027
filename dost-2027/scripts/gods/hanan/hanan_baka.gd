class_name HananBaka
extends Node2D

# HANAN AS THE BAKA (scenes/gods/hanan/HananBaka.tscn): in Luksong Baka the goddess
# herself is what the mortal vaults. Only her look lives here - Art, an
# AnimatedSprite2D with one clip per height in one SpriteFrames:
#   low       crouched low     (level 1, Low Baka)
#   sitting   bent / sitting   (level 2, Sitting Baka)
#   standing  standing tall    (level 3, Standing Baka; High Baka and Over the Moon
#                               stand taller still: standing, stretched per level)
# Each clip's pose carries the height (the frames stay one size). Art keeps the
# scale authored on it in the scene - she is drawn large on the field - and every
# level past Standing Baka stretches her taller. Whatever the frame size, she
# stands on the node's origin (her feet).
#
# The arena owns the game: it calls set_level() when the level changes and bump()
# on a trip. Nothing here is read back - the vault's numbers stay the level's.

const CLIPS: Array[StringName] = [&"low", &"sitting", &"standing"]

@export var taller_per_level := 0.2  # the stretch for each level past Standing Baka
@export var bump_time := 0.25        # the trip's wobble, seconds

@onready var art: AnimatedSprite2D = $Art

var level := 1
var _base_scale := Vector2.ONE  # Art's authored size; the levels only stretch it taller
var _bump: Tween
var _used: Dictionary = {}  # frame texture -> its painted pixels (screen_rect)


func _ready() -> void:
	_base_scale = art.scale
	set_level(level)


# 1 low, 2 sitting, 3+ standing (taller each level past 3).
func set_level(value: int) -> void:
	level = maxi(1, value)
	var clip := CLIPS[mini(level, CLIPS.size()) - 1]
	if art.sprite_frames != null and art.sprite_frames.has_animation(clip):
		art.play(clip)
	var stretch := 1.0 + taller_per_level * maxi(0, level - CLIPS.size())
	art.scale = Vector2(_base_scale.x, _base_scale.y * stretch)
	var frame := art.sprite_frames.get_frame_texture(art.animation, art.frame) if art.sprite_frames != null else null
	art.position.y = -float(frame.get_height()) * 0.5 * art.scale.y if frame != null else 0.0


func clip() -> StringName:
	return art.animation


# Where her body is drawn on screen (the frame's painted pixels, not its padding),
# so the balance bar can keep clear of her.
func screen_rect() -> Rect2:
	var frame := art.sprite_frames.get_frame_texture(art.animation, art.frame) if art.sprite_frames != null else null
	var xform := art.get_global_transform_with_canvas()
	if frame == null:
		return Rect2(xform.origin, Vector2.ZERO)
	if not _used.has(frame):
		var image := frame.get_image()
		_used[frame] = image.get_used_rect() if image != null else Rect2i(Vector2i.ZERO, Vector2i(frame.get_size()))
	var used: Rect2i = _used[frame]
	var top_left := Vector2(used.position) - (frame.get_size() * 0.5 if art.centered else Vector2.ZERO) + art.offset
	var a := xform * top_left
	var b := xform * (top_left + Vector2(used.size))
	return Rect2(a.min(b), (b - a).abs())


# A mortal tripped over her: a short squash and wobble, back to rest.
func bump() -> void:
	if _bump != null and _bump.is_valid():
		_bump.kill()
	rotation = 0.0
	_bump = create_tween()
	_bump.tween_property(self, "rotation", 0.12, bump_time * 0.25)
	_bump.tween_property(self, "rotation", -0.08, bump_time * 0.35)
	_bump.tween_property(self, "rotation", 0.0, bump_time * 0.4)
