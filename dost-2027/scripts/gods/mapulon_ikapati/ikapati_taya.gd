class_name IkapatiTaya
extends ArenaMortal

# MAPULON & IKAPATI AS TAYA (scenes/gods/mapulon_ikapati/IkapatiTaya.tscn): the gods'
# body on Langit Lupa's field while they are the Taya. It is a mortal body - the
# arena moves it like a ghost (host-run, mirrored on every client) - wearing the
# pair's own look, authored in the scene: the mortal sprite stays hidden, GodLook
# sits on a mortal's feet line (the pop-in grows it from there) and holds the
# accent ring and Art, an AnimatedSprite2D whose clips idle / walk / chant / tag
# live in one SpriteFrames. Every clip is the Godot placeholder until the art lands:
# drop the frames into the same clips and nothing else changes. Art stands
# god_height tall with its feet on GodLook's origin, whatever the frame size; the
# name tag and the floating line ride above its head (`lift`).
#
# The arena only says what the gods are doing - play_state(), set_facing(),
# appear() and leave() - and keeps every rule (langit_lupa_arena.gd).

const MORTAL_HEIGHT := 78.0  # a mortal's height, px (lam-ang.png at Mortal.tscn's scale)

@export var god_id: StringName = &"mapulon_ikapati"
@export var god_height := 87.0    # px the gods stand (the arena hands in its own)
@export var figure_height := 0.0  # px of a frame the figure fills (0: the whole frame)

@onready var look: Node2D = $GodLook
@onready var ring: Line2D = $GodLook/GodRing
@onready var art: AnimatedSprite2D = $GodLook/Art

var lift := 0.0  # px the name tag (and the arena's Taya marker) sit above a mortal's


func _ready() -> void:
	super._ready()
	set_lock(true)  # moved by the arena, never by input
	lift = maxf(0.0, god_height - MORTAL_HEIGHT)
	name_tag.position.y -= lift
	floating_text.position.y -= lift
	var god := Gods.by_id(god_id)
	if god != null:
		set_display_name(god.display_name, UITokens.god_text(god))
		ring_color = UITokens.god_accent(god)
		ring.default_color = ring_color
	play_state(&"idle")


# idle, walk, chant or tag.
func play_state(state: StringName) -> void:
	if art.sprite_frames == null or not art.sprite_frames.has_animation(state):
		return
	if art.animation != state or not art.is_playing():
		art.play(state)
	_stand()


func set_facing(way: int) -> void:
	art.flip_h = way < 0


# The pop-in at GO: the look grows from the feet with a little overshoot.
func appear(seconds: float) -> void:
	look.scale = Vector2.ONE * 0.2
	create_tween().tween_property(look, "scale", Vector2.ONE, seconds) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Their tag: the tag clip and their line over the body (the arena fades the body).
func leave(line: String, tint: Color, seconds: float) -> void:
	play_state(&"tag")
	show_floating_text(line, tint, seconds)


# god_height tall, feet on GodLook's origin, from the frame actually showing.
func _stand() -> void:
	var frame := art.sprite_frames.get_frame_texture(art.animation, art.frame)
	if frame == null:
		return
	var tall := float(frame.get_height())
	art.scale = Vector2.ONE * (god_height / (figure_height if figure_height > 0.0 else tall))
	art.position.y = -tall * 0.5 * art.scale.y
