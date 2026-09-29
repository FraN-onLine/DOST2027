extends Node2D

# One FAVOR popup: the light yellow "+41 FAVOR" that floats off a mortal's head
# while a lit zone pays, and the same popup in its loss colour when something
# takes FAVOR away ("-50 FAVOR" when a Mayari clone catches you).
#
# The arena spawns it - Arena.spawn_popup() / Arena.favor_popup(), see
# scripts/gods/common/arena.gd - and never draws anything itself.
#
# Art lives in favor_popup.tscn: an HBoxContainer ("Box") holding
#
#   Icon  - a TextureRect that stays hidden until a texture is handed in, so
#           dropping a .png next to the number (a favor icon, a Mayari mask...)
#           is a one-line change at the call site and no scene editing at all.
#   Label - the number itself, outlined so it reads over the field.
#
# The popup always centres itself on the point it was spawned at (the caller
# spawns it just above a mortal) and then rises while it fades out.

@export var rise_pixels := 34.0   # how far up the popup floats before it is gone
@export var duration := 1.0       # seconds from spawn to gone
@export var pop_in := 0.12        # seconds of the little scale-up at the start

@onready var box: HBoxContainer = $Box
@onready var icon: TextureRect = $Box/Icon
@onready var label: Label = $Box/Label


func _ready() -> void:
	# The box changes width with its text (a "+9" is narrower than a "+412"),
	# so keep it centred on our own origin whenever it is re-laid-out.
	if not box.resized.is_connected(_recenter):
		box.resized.connect(_recenter)
	_recenter()


# Show the popup: `text` as written, `tint` its colour and an optional texture
# for the little image in front of the number.
func show_favor(text: String, tint: Color, icon_texture: Texture2D = null) -> void:
	label.text = text
	label.add_theme_color_override("font_color", tint)
	icon.texture = icon_texture
	icon.visible = icon_texture != null
	_recenter()

	box.scale = Vector2.ONE * 0.7
	var fade_start := duration * 0.35
	var tween := create_tween()
	tween.set_parallel()
	tween.tween_property(self, "position", position + Vector2(0.0, -rise_pixels), duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(box, "scale", Vector2.ONE, pop_in) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, duration - fade_start).set_delay(fade_start)

	await tween.finished
	queue_free()


# Centre the box (and its pivot, so the pop-in grows around the middle) on the
# spot the popup was spawned at.
func _recenter() -> void:
	if box == null:
		return
	box.pivot_offset = box.size * 0.5
	box.position = -box.size * 0.5
