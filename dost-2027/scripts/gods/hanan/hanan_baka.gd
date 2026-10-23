class_name HananBaka
extends Node2D

# HANAN AS THE BAKA (scenes/gods/hanan/HananBaka.tscn): in Luksong Baka the goddess
# herself is what the mortal vaults. Only her look lives here - Art, an
# AnimatedSprite2D with one clip per height in one SpriteFrames:
#   low       crouched low     (level 1, Low Baka)
#   sitting   bent / sitting   (level 2, Sitting Baka)
#   standing  standing tall    (level 3, Standing Baka; High Baka and Over the Moon
#                               stand taller still: standing, stretched per level)
# Every clip is the Godot placeholder until the art lands (cut to a different height
# per clip so the levels read): drop the frames into the same clips, nothing else
# changes. Whatever the frame size, Art stands on the node's origin (her feet).
#
# The arena owns the game: it calls set_level() when the level changes and bump()
# on a trip. Nothing here is read back - the vault's numbers stay the level's.

const CLIPS: Array[StringName] = [&"low", &"sitting", &"standing"]

@export var art_scale := 0.6         # the art's size on the field
@export var taller_per_level := 0.2  # the stretch for each level past Standing Baka
@export var bump_time := 0.25        # the trip's wobble, seconds

@onready var art: AnimatedSprite2D = $Art

var level := 1
var _bump: Tween


func _ready() -> void:
	set_level(level)


# 1 low, 2 sitting, 3+ standing (taller each level past 3).
func set_level(value: int) -> void:
	level = maxi(1, value)
	var clip := CLIPS[mini(level, CLIPS.size()) - 1]
	if art.sprite_frames != null and art.sprite_frames.has_animation(clip):
		art.play(clip)
	var stretch := 1.0 + taller_per_level * maxi(0, level - CLIPS.size())
	art.scale = Vector2(art_scale, art_scale * stretch)
	var frame := art.sprite_frames.get_frame_texture(art.animation, art.frame) if art.sprite_frames != null else null
	art.position.y = -float(frame.get_height()) * 0.5 * art.scale.y if frame != null else 0.0


func clip() -> StringName:
	return art.animation


# A mortal tripped over her: a short squash and wobble, back to rest.
func bump() -> void:
	if _bump != null and _bump.is_valid():
		_bump.kill()
	rotation = 0.0
	_bump = create_tween()
	_bump.tween_property(self, "rotation", 0.12, bump_time * 0.25)
	_bump.tween_property(self, "rotation", -0.08, bump_time * 0.35)
	_bump.tween_property(self, "rotation", 0.0, bump_time * 0.4)
