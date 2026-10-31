class_name ArenaMortal
extends CharacterBody2D

# The mortal a player controls inside a god's arena.
# WASD / arrow keys move it (the project's move_* actions). An arena can lock
# movement during dialogue and shove the mortal around when a god or a clone
# interrupts them.
#
# Every visual lives in Mortal.tscn (Shadow, Dust, Afterimages, Glow, Sprite,
# StunStars, NameTag, FloatingStatus, and the Steps / Whoosh sound slots) - this script
# never draws and never builds nodes on the fly. (The one thing it gives each
# mortal is its own copy of the Sprite's bandana material, below.) Sprite is an
# AnimatedSprite2D and carries the authored clips (the idle, the walk, plus the
# arnis strike and guard): an arena plays them and reads the running frame back,
# so the body holds the art while the arena keeps the rules.
#
# BANDANA: every mortal wears the same sprite, so what tells the players apart is
# the colour of the bandana - the headband and its two tails - and of the vest.
# The Sprite carries bandana_swap.gdshader, which turns the three reds the art
# draws both in into the player's colour and two darker steps of it
# (UITokens.art_shades), touching nothing else, and set_bandana() gives the mortal
# its own material so each one keeps its own. The defend-arnis clip is still the
# old sheet with the old reds, so the shader's `legacy` switch follows the clip. It sits UNDER the node's modulate, so every hit flash, freeze or
# fade an arena puts on a mortal still shows on top of it.
#
# FACING: the authored art faces right, so a move to the left mirrors the sprite
# (AnimatedSprite2D.flip_h) and slides the attack area + standing collision to
# the mirror side of the mortal (their authored x offsets are multiplied by
# `facing`). The facing is read from whatever is actually moving the mortal this
# frame - player input, a forced move, a knockback, or, for a remote ghost the
# arena glides towards its last reported position, the distance travelled - so
# every ArenaMortal (the local player and every ghost) turns to face its motion.
#
# FEEL: the player's own walk speeds up and slows down (accel / turn_accel /
# friction) instead of jumping between 0 and move_speed - but only free walking:
# a stun, a forced move, a dash and a lock still set the velocity outright, on
# the frame they happen. move_speed stays the cap. Everything else is LOOK, and
# it is read from the motion this screen actually saw (the distance travelled
# each physics frame), never from input or the network - so the local player,
# every ghost the arena glides around, a bot and a shoved mortal all walk, lean,
# hop and kick up dust the same way, and nothing new is ever sent. The look only
# ever touches the Sprite (and the Shadow under it), on top of the position and
# scale authored in Mortal.tscn: the root node's scale, rotation and modulate
# belong to the arenas (Hanan's crouch scales it, flashes and fades modulate it).
# The feet stand on y = Shadow.position.y (the bottom of the body collision), so
# every squash and lean pivots there and the mortal never leaves the ground.

@export var move_speed := 215.0

@export_group("Feel")
@export var accel := 3200.0         # px/s² towards the held direction: full speed in ~4 frames
@export var turn_accel := 4800.0    # ...when the held direction turns back more than ~100°
@export var friction := 2600.0      # px/s² to a stop with nothing held: ~5 frames
@export var stride := 30.0          # px walked per footfall (faster walk = quicker steps)
@export var hop_height := 2.5       # px of hop per step at full speed
@export var idle_bob := 1.0         # px of breathing while standing
@export var lean_degrees := 5.0     # tilt towards the way it walks, at full speed
@export var squash := 0.05          # the hop's stretch / squash (scale fraction)
@export var hit_stop := 0.06        # s the sprite freezes on a hit (only with screen shake on)
@export var stun_star_orbit := Vector2(16.0, 5.0)  # px: how wide / deep the stars circle the head
@export var stun_star_speed := 7.0  # rad/s
# A mortal nobody here steers (a ghost, a bot) "dashed" when it was seen going
# this many times move_speed. Ghosts can't hear a dash, only see it - and the
# glide they get (Arena.ghost_smoothing) shows a 733 px/s dash at ~575 px/s, a
# 560 px/s knockback at ~380 and the fastest favoured walk at ~375, so 2.2
# (473 px/s) sits between them.
@export var dash_detect_ratio := 2.2

@export_group("Sounds")
@export var step_sounds: Array[AudioStream] = []
@export var dash_sound: AudioStream
@export var land_sound: AudioStream  # the thud of coming down from the sky at GO (skipped when empty)

var locked := false
# THE DROP AT GO (the arena's, see Arena THE GO DROP): look only, like everything
# below FEEL. The body never moves - it waits on its spawn point - while the sprite
# and what rides above it (name tag, glow, stars) are lifted by drop_offset, so a
# mortal can fall from the sky onto the spot the physics already put it on.
# drop_hidden draws nothing of the mortal at all (before GO), and drop_shadow is how
# much of its shadow shows while it falls (0 small and faint, 1 as always).
var drop_offset := Vector2.ZERO
var drop_hidden := false
var blink_left := 0.0  # seconds of white blink left (an arena's grace seconds; read off its mirrored timer, so every screen flickers in step)
var drop_shadow := 1.0
var bounds := Rect2()
var ring_color := Color(1, 0.95, 0.8)
var radius := 13.0
# Langit Lupa's earthquakes: the walk keys drive the mortal the other way. The
# arena sets it each frame; a dash or a shove is the arena's own move and is not
# inverted.
var movement_inverted := false
# Which of UITokens.BANDANA_COLORS this mortal's bandana wears (0 = the drawn red).
var bandana_index := 0

# Which way the mortal faces: 1 = right (the way the art is drawn), -1 = left.
var facing := 1

# The afflictions' own look, driven by the arena from replicated state: the
# Weeded clump at the feet, Tala's Tranced sparkles overhead, and a word over
# the head for whichever is on (ROOTED / WEEDED).
var _weeded_on := false
var _tranced_on := false

var _stun := 0.0
# Seconds the stars still circle the head. Look only: hit() sets it with the stun, and
# an arena sets it (show_stun) for a mortal it can't hit() here - a ghost - or one that
# is stumbling without being shoved (a broken chant).
var _stun_fx := 0.0
var _stun_angle := 0.0
# Rest and Refreshed's small 3-2-1 over the head while the drowsiness lasts.
var drowsy_count: Label = null
var _drowsy_shown := -1
var _knockback := Vector2.ZERO
var _forced_move_time := 0.0
var _forced_move_direction := Vector2.ZERO
var _return_target := Vector2.ZERO
var _return_time := 0.0
var _dash_time := 0.0
var _dash_velocity := Vector2.ZERO
var _bob := 0.0
var _flash := 0.0
var _floating_time := 0.0
var _floating_velocity := Vector2.ZERO
# True while the move keys are the ones driving this mortal (its own walk).
var _moving := false
# True once the move keys have driven this mortal at all: it is this screen's own
# player (ghosts and bots stay locked for life). Its sounds play at full volume.
var _player_driven := false

# Where the combat pieces sit in the authored scene; the facing mirrors their x
# offsets (and their scale, so a non-symmetric shape would mirror too).
var _area_offset_x := 0.0
var _collision_offset_x := 0.0
var _last_position := Vector2.ZERO

# The look (see FEEL). The authored Sprite/Shadow placement everything rides on:
var _sprite_base_position := Vector2.ZERO
var _sprite_base_scale := Vector2.ONE
var _shadow_base_scale := Vector2.ONE
var _feet_y := 0.0
# What this screen saw the mortal do (px/s, smoothed), and how far into its stride.
var _visual_velocity := Vector2.ZERO
var _step_phase := 0.0
var _steps_taken := 0
var _walking := false
var _top_ratio := 0.0
var _walk_weight := 1.0
# The springs and pops, each 1 -> 0 (or a small angle settling back to 0).
var _lean := 0.0
var _kick := 0.0
var _kick_velocity := 0.0
var _pop := 0.0
var _turn := 0.0
var _hit_squash := 0.0
var _hit_direction := Vector2.ZERO
var _hit_flash := 0.0
var _hit_stop := 0.0
var _dash_stretch := 0.0
var _land := 0.0  # the squash of coming down, 1 -> 0
var _lifted := Vector2.ZERO  # how far drop_offset has already carried the parts above the sprite
var _dash_direction := Vector2.RIGHT
var _seen_dash := false
# The dash trail: how long it still drops afterimages, and when the next one is due.
var _trail_time := 0.0
var _trail_gap := 0.0
var _trail_next := 0
var _trail_spots: Array[Transform2D] = []

const ANIM_WALK := &"walk"
const LEGACY_CLIPS: Array[StringName] = [&"defend-arnis"]  # still on Lamang-Sheet.png
const TURN_DOT := -0.17          # cos(100°): input this far from the velocity turns back
const JUMP := 48.0               # px in one physics frame: a respawn or a snap, not a walk
const VISUAL_SMOOTHING := 18.0
const STUN_FX_MIN := 0.3         # a 0.2s stun still shows its stars long enough to read
const TRAIL_TIME := 0.15         # the dash's length: one afterimage per TRAIL_GAP of it
const TRAIL_GAP := 0.04
const TRAIL_LIFE := 0.25
const OTHER_VOLUME_DB := -8.0    # a ghost's or bot's sounds, under the player's own
const KICK_STIFFNESS := 900.0    # the stop's lean overshoot: ~0.15s to settle
const KICK_DAMPING := 21.0
const LAND_TIME := 0.1           # the landing squash, seconds
const LAND_SQUASH := 0.3         # ...and how flat it gets (scale fraction)
const DROP_SHADOW_SMALL := 0.35  # the shadow's size when the mortal is still high

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var glow: Sprite2D = $Glow
@onready var shadow: Sprite2D = $Shadow
@onready var dust: CPUParticles2D = $Dust
@onready var afterimages: Node2D = $Afterimages
@onready var stun_stars: Node2D = $StunStars
@onready var steps: AudioStreamPlayer2D = $Steps
@onready var whoosh: AudioStreamPlayer2D = $Whoosh
@onready var name_tag: Label = $NameTag
@onready var floating_text: Label = $FloatingStatus
@onready var status_tag: Label = $StatusTag
@onready var tranced_sprite: AnimatedSprite2D = $Tranced
@onready var weeded_sprite: AnimatedSprite2D = $Weeded
@onready var damage_area: Area2D = get_node("Arnis-Damage-Area")
@onready var body_collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	# Read the authored offsets back and mirror them from the very first frame,
	# so a scene that places the strike area off-centre keeps working flipped.
	_area_offset_x = damage_area.position.x if damage_area != null else 0.0
	_collision_offset_x = body_collision.position.x if body_collision != null else 0.0
	_last_position = global_position
	if sprite != null:
		_sprite_base_position = sprite.position
		_sprite_base_scale = sprite.scale
	if shadow != null:
		_shadow_base_scale = shadow.scale
		_feet_y = shadow.position.y
	for index in range(afterimages.get_child_count() if afterimages != null else 0):
		_trail_spots.append(Transform2D.IDENTITY)
	_apply_facing()
	set_bandana(bandana_index)  # its own material, from the first frame
	if sprite != null:
		sprite.animation_changed.connect(_on_animation_changed)
		_on_animation_changed()
	_build_drowsy_count()


# Put the player's bandana (and cloak) colour on this mortal (and only this one: the material
# is copied the first time, so mortals never share a colour by accident).
func set_bandana(index: int) -> void:
	bandana_index = posmod(index, UITokens.BANDANA_COLORS.size())
	if sprite == null or not (sprite.material is ShaderMaterial):
		return
	if not sprite.material.has_meta("own_bandana"):
		sprite.material = sprite.material.duplicate()
		sprite.material.set_meta("own_bandana", true)
	var swap := sprite.material as ShaderMaterial
	var shades := UITokens.art_shades(bandana_index)
	swap.set_shader_parameter("shade_light", shades[0])
	swap.set_shader_parameter("shade_mid", shades[1])
	swap.set_shader_parameter("shade_dark", shades[2])
	swap.set_shader_parameter("bandana_color", UITokens.bandana_color(bandana_index))
	swap.set_shader_parameter("bandana_shadow", UITokens.bandana_shadow(bandana_index))
	var cloak := UITokens.cloak_shades(bandana_index)
	swap.set_shader_parameter("cloak_color", cloak[0])
	swap.set_shader_parameter("cloak_mid", cloak[1])
	swap.set_shader_parameter("cloak_dark", cloak[2])


# The clips still drawn on the old sheet, in the old reds (see bandana_swap.gdshader).
func _on_animation_changed() -> void:
	if sprite.material is ShaderMaterial:
		(sprite.material as ShaderMaterial).set_shader_parameter("legacy", sprite.animation in LEGACY_CLIPS)


func is_stunned() -> bool:
	return _stun > 0.0


# Seconds of stun left (the HUD's effect timers show them).
func stun_left() -> float:
	return _stun


# The shove itself, then how it lands on this screen: the sprite squashes from
# the side it was hit on and flashes white (through its own self_modulate, so it
# stacks with the arena's modulate and the bandana swap), and - with screen shake
# on - freezes for a beat. The freeze holds only the sprite's pose; the body
# keeps flying, so nothing here can drift from what the other screens see.
func hit(direction: Vector2, stun_time := 1.4, force := 420.0) -> void:
	_stun = maxf(_stun, stun_time)
	show_stun(stun_time)
	_knockback = direction.normalized() * force
	_flash = 0.35
	_hit_direction = direction.normalized()
	_hit_squash = 1.0
	_hit_flash = 1.0
	if _setting("screen_shake_enabled"):
		_hit_stop = hit_stop


# The stars over the head for `seconds` (at least STUN_FX_MIN); nothing moves.
func show_stun(seconds: float) -> void:
	_stun_fx = maxf(_stun_fx, maxf(seconds, STUN_FX_MIN))


# The stop itself, without a new shove or flash: an authoritative timer (the
# arena's tick) holding the mortal for `seconds`.
func stun(seconds: float) -> void:
	_stun = maxf(_stun, seconds)
	show_stun(seconds)


# The shove alone, for a hit whose stun was cancelled (The First Cleanse): the
# body still flies, nothing holds it.
func shove(direction: Vector2, force: float) -> void:
	_knockback = direction.normalized() * force
	_flash = 0.35
	_hit_direction = direction.normalized()
	_hit_squash = 1.0
	_hit_flash = 1.0


func force_movement(direction: Vector2, duration: float) -> void:
	_forced_move_direction = direction.normalized()
	_forced_move_time = maxf(_forced_move_time, duration)


# Dragged straight back to a spot over `duration` (Down to Homeland's shadow),
# however far the mortal wandered: the pace follows the distance left, and it
# stops dead on arrival instead of sliding past.
func return_to(target: Vector2, duration: float) -> void:
	_return_target = target
	_return_time = maxf(0.01, duration)


# A quick burst of `distance` pixels over `time` seconds along `direction`, or
# the way the mortal faces when it is zero (standing still). Walls and the
# arena's bounds still stop it. When it runs out the mortal carries on at
# move_speed the same way, so the dash flows back into the walk.
func dash(direction: Vector2, distance: float, time: float) -> void:
	var way := direction.normalized() if direction.length() > 0.01 else Vector2(facing, 0.0)
	_dash_time = maxf(0.01, time)
	_dash_velocity = way * distance / _dash_time
	_start_dash_look(way)


func is_dashing() -> bool:
	return _dash_time > 0.0


# Everything a trial can leave on a mortal - a stun and its stars, a shove, a
# forced walk, a dash, a drop from the sky, a squash - gone, and it may walk.
func clear_trial_state() -> void:
	_stun = 0.0
	_stun_fx = 0.0
	_knockback = Vector2.ZERO
	_forced_move_time = 0.0
	_return_time = 0.0
	_dash_time = 0.0
	_dash_velocity = Vector2.ZERO
	drop_offset = Vector2.ZERO
	drop_hidden = false
	drop_shadow = 1.0
	blink_left = 0.0
	scale = Vector2.ONE
	velocity = Vector2.ZERO
	clear_drowsy_count()
	set_weeded(false)
	set_tranced(false)
	set_status("")
	set_lock(false)


func set_lock(value: bool) -> void:
	locked = value
	if locked:
		velocity = Vector2.ZERO


# Name tag for networked mortals (ghosts and the local player). The tag is the
# WorldLabel 8 px font at scale 1 with a 1 px dark rim; the arena picks the tint
# (Arena.tag_color: gold for this screen's mortal, the bandana for everyone else).
func set_display_name(text: String, tint := Color(1, 1, 1, 0.85)) -> void:
	if name_tag == null:
		return
	name_tag.text = text
	name_tag.add_theme_color_override("font_color", tint)
	name_tag.visible = text != ""


func set_tag_color(tint: Color) -> void:
	if name_tag != null:
		name_tag.add_theme_color_override("font_color", tint)


# Ligaw na Damo: the weed clump at the feet, for as long as the weeds hold.
func set_weeded(active: bool) -> void:
	var was := _weeded_on
	_weeded_on = active
	if weeded_sprite == null:
		return
	weeded_sprite.visible = active
	if active and (not was or not weeded_sprite.is_playing()):
		weeded_sprite.play()


# Tala's Let Us Light Your Way: the tranced sparkles over the head.
func set_tranced(active: bool) -> void:
	var was := _tranced_on
	_tranced_on = active
	if tranced_sprite == null:
		return
	tranced_sprite.visible = active
	if active and (not was or not tranced_sprite.is_playing()):
		tranced_sprite.play()


# A word over the head for an affliction (ROOTED, WEEDED); empty hides it.
func set_status(text: String, tint := Color.WHITE) -> void:
	if status_tag == null:
		return
	status_tag.text = text
	status_tag.visible = text != ""
	if text != "":
		status_tag.add_theme_color_override("font_color", tint)


func show_floating_text(text: String, tint := Color.WHITE, duration := 2.2) -> void:
	if floating_text == null:
		return
	floating_text.text = text
	floating_text.modulate = tint
	floating_text.visible = true
	_floating_time = duration
	_floating_velocity = Vector2(0.0, -18.0)


# Rest and Refreshed: the small 3, 2, 1 over the head while the drowsiness runs,
# in the same EMBER as the HUD's DROWSY row. The drowsiness ends in the usual
# stun stars (the arena announces that).
func _build_drowsy_count() -> void:
	drowsy_count = Label.new()
	drowsy_count.name = "DrowsyCount"
	drowsy_count.theme_type_variation = &"WorldValue"
	drowsy_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drowsy_count.position = Vector2(-20.0, -116.0)
	drowsy_count.size = Vector2(40.0, 20.0)
	drowsy_count.pivot_offset = Vector2(20.0, 10.0)
	drowsy_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drowsy_count.z_index = 3
	drowsy_count.visible = false
	drowsy_count.add_theme_color_override("font_color", UITokens.EMBER)
	add_child(drowsy_count)


func show_drowsy_count(seconds: int) -> void:
	if drowsy_count == null or seconds <= 0:
		return
	if seconds != _drowsy_shown:
		_drowsy_shown = seconds
		drowsy_count.text = str(seconds)
		drowsy_count.scale = Vector2.ONE * 1.4
		var tween := create_tween()
		tween.tween_property(drowsy_count, "scale", Vector2.ONE, 0.18)
	drowsy_count.visible = true


func clear_drowsy_count() -> void:
	_drowsy_shown = -1
	if drowsy_count != null:
		drowsy_count.visible = false
		drowsy_count.scale = Vector2.ONE


# --- ANIMATION ---------------------------------------------------------------
# The clips an arena can play (authored on Sprite in Mortal.tscn). The mortal
# only plays them and reports back the running clip and its frame, so a game can
# open a strike's hit window on one frame and close it on another without the
# body ever knowing the rules. The idle and the walk are the mortal's own: it
# swaps between them as it starts and stops (see _update_look); any other clip an
# arena plays holds until it has played out, then the mortal falls back to the walk
# or the idle by itself (an arena can say so sooner with play_locomotion). A stunned
# mortal, and the player while locked (dialogue, a chant), show the idle.
const ANIM_IDLE := &"default"

# Play an authored clip. An unknown name is ignored, so a mortal in an arena
# that never strikes simply keeps its idle.
func play_animation(anim: StringName) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(anim):
		return
	if sprite.animation == anim and sprite.is_playing():
		return
	sprite.play(anim)


# Back to what the mortal's motion says: the walk while it is moving, the idle
# otherwise. What an arena calls when an action clip is over, so a mortal that
# strikes while running goes back to running.
func play_locomotion() -> void:
	play_animation(ANIM_WALK if _walking and not _held() else ANIM_IDLE)


# Stunned, or the player held still by the arena: shown idle whatever it slides at.
# (Ghosts and bots stay locked for life - their motion decides, not the lock. A
# root does not hold a mortal: Down to Homeland only drags them back at the end.)
func _held() -> bool:
	return is_stunned() or (locked and _player_driven)


func current_animation() -> StringName:
	return sprite.animation if sprite != null else &""


# The frame the clip is showing right now (-1 when there is no sprite).
func animation_frame() -> int:
	return sprite.frame if sprite != null else -1


# True while `anim` (or any clip, when it is left empty) is still running. A
# one-shot clip reports false once it has played out, which is how an arena
# knows to hand the mortal back to its idle.
func is_animation_playing(anim: StringName = &"") -> bool:
	if sprite == null:
		return false
	if anim != &"" and sprite.animation != anim:
		return false
	return sprite.is_playing()


# --- FACING ----------------------------------------------------------------
# The art faces right. Whoever is actually moving the mortal decides the facing:
# an input-driven player has a live velocity; a ghost the arena glides towards
# its last reported position has none - so use the distance travelled when the
# velocity has nothing to say, and when that is too small for one frame (a ghost
# gliding at a walk covers ~3px), the smoothed motion this screen saw. Facing
# only changes on real motion; a mortal that is standing (or shoved straight
# up/down/into a wall) keeps its last direction. A turn squeezes the sprite thin
# for a few frames, so the flip reads as a turn, and a sharp one at speed kicks
# up dust.
func _update_facing() -> void:
	var moved := global_position - _last_position
	_last_position = global_position
	var basis := velocity.x
	if absf(basis) <= 4.0:
		basis = moved.x if absf(moved.x) >= 4.0 else 0.0
	if basis == 0.0 and absf(_visual_velocity.x) >= 20.0:
		basis = _visual_velocity.x
	if basis == 0.0:
		return
	var new_facing := 1 if basis > 0.0 else -1
	if new_facing == facing:
		return
	facing = new_facing
	_apply_facing()
	_turn = 1.0
	if _visual_velocity.length() > move_speed * 0.5:
		_puff(0.6, Vector2(-facing, 0.0))


# Mirror every side-specific piece of the mortal to the current facing: the
# sprite texture, the attack area's offset and scale (so a non-symmetric shape
# truly mirrors) and the standing collision's offset and scale.
func _apply_facing() -> void:
	if sprite != null:
		sprite.flip_h = facing < 0
	if damage_area != null:
		damage_area.position.x = _area_offset_x * facing
		damage_area.scale.x = facing
	if body_collision != null:
		body_collision.position.x = _collision_offset_x * facing
		body_collision.scale.x = facing


func _physics_process(delta: float) -> void:
	var dash_ended := false
	var landed := false
	_moving = false
	if _stun > 0.0:
		_stun = maxf(0.0, _stun - delta)
		velocity = _knockback
		_knockback = _knockback.move_toward(Vector2.ZERO, 1400.0 * delta)
	elif _return_time > 0.0:
		var to_target := _return_target - global_position
		_return_time = maxf(0.0, _return_time - delta)
		if _return_time <= delta or to_target.length() < 2.0:
			velocity = to_target / maxf(delta, 0.001)  # the last step lands it
			_return_time = 0.0
			landed = true
		else:
			velocity = to_target / _return_time
	elif _dash_time > 0.0:
		velocity = _dash_velocity
		_dash_time -= delta
		if _dash_time < 0.001:
			_dash_time = 0.0  # 0.15s at 60 FPS is 9 frames, not a 10th from rounding
			dash_ended = true
	elif _forced_move_time > 0.0:
		_forced_move_time = maxf(0.0, _forced_move_time - delta)
		velocity = _forced_move_direction * move_speed
	elif locked:
		velocity = Vector2.ZERO
	else:
		var walk := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if movement_inverted:
			walk = -walk
		_steer(walk, delta)

	move_and_slide()
	if landed:
		velocity = Vector2.ZERO
	if dash_ended:
		velocity = _dash_velocity.normalized() * move_speed  # flows on into the walk
	if bounds.size != Vector2.ZERO:
		var low := bounds.position.x + radius
		var high := bounds.end.x - radius
		global_position.x = clampf(global_position.x, low, high)
		# Held against the edge, the walk stops pressing into it (so it doesn't
		# build up speed it would spend the moment the key turns away).
		if (global_position.x <= low and velocity.x < 0.0) or (global_position.x >= high and velocity.x > 0.0):
			velocity.x = 0.0
		low = bounds.position.y + radius
		high = bounds.end.y - radius
		global_position.y = clampf(global_position.y, low, high)
		if (global_position.y <= low and velocity.y < 0.0) or (global_position.y >= high and velocity.y > 0.0):
			velocity.y = 0.0

	# What this screen saw: the distance travelled, smoothed into a velocity (a
	# respawn or a ghost's snap is a jump, not a walk, and counts as standing).
	var moved := global_position - _last_position
	if moved.length() >= JUMP:
		moved = Vector2.ZERO
	_visual_velocity = _visual_velocity.lerp(moved / delta, clampf(delta * VISUAL_SMOOTHING, 0.0, 1.0))
	_update_facing()
	_update_look(moved, delta)

	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	_update_stun_stars(delta)
	if glow != null:
		var hit_alpha := 0.35 if _setting("reduce_flashing") else 0.7  # steady tint instead of a bright flash
		var glow_alpha := 0.25 if _flash <= 0.0 else hit_alpha
		glow.modulate = Color(ring_color.r, ring_color.g, ring_color.b, glow_alpha)
	if floating_text != null and floating_text.visible:
		_floating_time = maxf(0.0, _floating_time - delta)
		floating_text.position += _floating_velocity * delta
		floating_text.rotation = sin(Time.get_ticks_msec() * 0.02) * 0.04
		floating_text.modulate.a = clampf(_floating_time, 0.0, 1.0)
		if _floating_time <= 0.0:
			floating_text.visible = false


# Three stars circling the head while _stun_fx runs (the sprite hidden - Langit Lupa's
# gods - hides them too). One ellipse seen from the side: the far ones are smaller.
func _update_stun_stars(delta: float) -> void:
	if stun_stars == null:
		return
	_stun_fx = maxf(0.0, _stun_fx - delta)
	stun_stars.visible = _stun_fx > 0.0 and sprite != null and sprite.visible
	if not stun_stars.visible:
		return
	_stun_angle += delta * stun_star_speed
	for index in range(stun_stars.get_child_count()):
		var star := stun_stars.get_child(index) as Sprite2D
		var angle := _stun_angle + TAU * index / stun_stars.get_child_count()
		star.position = Vector2(cos(angle) * stun_star_orbit.x, sin(angle) * stun_star_orbit.y)
		star.scale = Vector2.ONE * (0.3 + 0.08 * sin(angle))
		star.rotation = angle


# The player's own walk: towards the held direction at `accel` (`turn_accel` when
# it turns back on itself, so a dodge never feels floaty), down to a stop at
# `friction` when nothing is held. Never past move_speed: a speed favour that
# ends slows the mortal on the spot, one that starts takes ~3 frames to reach.
func _steer(input: Vector2, delta: float) -> void:
	_player_driven = true
	_moving = input != Vector2.ZERO
	velocity = velocity.limit_length(move_speed)
	var rate := friction
	if _moving:
		var turning_back := velocity.length() > 1.0 and input.normalized().dot(velocity.normalized()) < TURN_DOT
		rate = turn_accel if turning_back else accel
	velocity = velocity.move_toward(input * move_speed, rate * delta)


# --- LOOK ---------------------------------------------------------------------
# All of it from `moved`, the distance this screen saw the mortal travel this
# physics frame, and _visual_velocity, that smoothed (see FEEL). Nothing here
# touches the velocity or the position.
func _update_look(moved: Vector2, delta: float) -> void:
	if sprite == null:
		return
	_tick_afterimages(delta)
	var shown := sprite.visible  # Langit Lupa's gods wear a mortal body with the sprite hidden
	if shadow != null:
		shadow.visible = shown
	# The affliction art rides with the body (and hides when the body does).
	if tranced_sprite != null:
		tranced_sprite.visible = _tranced_on and shown
	if weeded_sprite != null:
		weeded_sprite.visible = _weeded_on and shown
	_hit_flash = maxf(0.0, _hit_flash - delta / 0.12)
	var peak := 1.6 if _setting("reduce_flashing") else 3.0
	var blink := 0.7 if blink_left > 0.0 and fmod(blink_left, 0.2) < 0.1 else 0.0
	sprite.self_modulate = Color.WHITE.lerp(Color(peak, peak, peak), maxf(_hit_flash, blink))
	_apply_drop_look(delta)
	if _hit_stop > 0.0:
		_hit_stop -= delta
		sprite.speed_scale = 0.0  # the pose and every offset hold; the body moves on
		return

	var cap := maxf(move_speed, 1.0)
	var speed := _visual_velocity.length()
	var ratio := clampf(speed / cap, 0.0, 1.0)
	_bob += delta

	# Its own clips (idle, walk) get the whole procedural walk; an arena's clip
	# (the arnis strike or guard) gets next to none, so its frames read clean.
	var own_clip := sprite.animation == ANIM_IDLE or sprite.animation == ANIM_WALK
	_walk_weight = move_toward(_walk_weight, 1.0 if own_clip else 0.1, delta * 8.0)

	# Starting from rest pops (a squash, a puff); stopping hard from a run kicks
	# the body forward past upright and lets it spring back.
	_top_ratio = maxf(ratio, _top_ratio - delta * 2.0)
	if not _walking and ratio > 0.35:
		_walking = true
		_pop = 1.0
		_puff(0.5, -_visual_velocity.normalized())
	elif _walking and ratio < 0.08:
		_walking = false
		if _top_ratio > 0.6:
			_kick_velocity += facing * deg_to_rad(4.0) * sqrt(KICK_STIFFNESS)
			_puff(0.6, Vector2(facing, 0.0))
	if not own_clip and not sprite.is_playing():
		play_locomotion()  # the action has played out
		own_clip = true
	if own_clip:
		var clip := ANIM_WALK if _walking and not _held() and sprite.sprite_frames.has_animation(ANIM_WALK) else ANIM_IDLE
		if sprite.animation != clip:
			sprite.play(clip)
		sprite.speed_scale = lerpf(1.0, 1.8, ratio)  # quicker steps, a livelier cloak
	else:
		sprite.speed_scale = 1.0

	# The stride: one footfall every `stride` px walked.
	_step_phase += moved.length() * PI / maxf(stride, 1.0)
	if _step_phase >= PI:
		_step_phase = fmod(_step_phase, PI)
		if ratio > 0.3:
			_footfall(ratio)

	# A remote mortal can't say it dashed; seen going this fast, it did.
	if not _player_driven and not is_stunned() and move_speed > 1.0:
		if not _seen_dash and speed > move_speed * dash_detect_ratio:
			_seen_dash = true
			_start_dash_look(_visual_velocity.normalized())
		elif speed < move_speed:
			_seen_dash = false
	if _trail_time > 0.0:
		_trail_time -= delta
		_trail_gap -= delta
		if _trail_gap <= 0.0:
			_trail_gap = TRAIL_GAP
			_drop_afterimage()

	# The springs settle.
	_lean = lerpf(_lean, deg_to_rad(lean_degrees) * clampf(_visual_velocity.x / cap, -1.0, 1.0), clampf(delta * 12.0, 0.0, 1.0))
	_kick_velocity += (-KICK_STIFFNESS * _kick - KICK_DAMPING * _kick_velocity) * delta
	_kick += _kick_velocity * delta
	_pop = maxf(0.0, _pop - delta / 0.15)
	_turn = maxf(0.0, _turn - delta / 0.05)
	_hit_squash = maxf(0.0, _hit_squash - delta / 0.25)
	_dash_stretch = maxf(0.0, _dash_stretch - delta / 0.2)

	var weight := _walk_weight
	var hop := absf(sin(_step_phase)) * hop_height * ratio * weight
	var breathe := sin(_bob * 2.4) * idle_bob * (1.0 - ratio) * weight
	# Stretch on the way up off each step, squash coming down onto the next.
	var bounce := sin(2.0 * _step_phase - 0.5) * squash * ratio * weight
	var sx := (1.0 - bounce + 0.07 * _pop) * (1.0 - 0.3 * _turn) * (1.0 + LAND_SQUASH * _land)
	var sy := (1.0 + bounce - 0.07 * _pop) * (1.0 - LAND_SQUASH * _land)
	# A hit squashes along the side it came from; a dash stretches along its way.
	var across := absf(_hit_direction.x)
	sx *= 1.0 - 0.18 * _hit_squash * across + 0.1 * _hit_squash * (1.0 - across)
	sy *= 1.0 - 0.18 * _hit_squash * (1.0 - across) + 0.1 * _hit_squash * across
	across = absf(_dash_direction.x)
	sx *= 1.0 + _dash_stretch * (0.25 * across - 0.12 * (1.0 - across))
	sy *= 1.0 + _dash_stretch * (0.2 * (1.0 - across) - 0.15 * across)
	var tilt := (_lean + _kick) * weight - _hit_direction.x * 0.2 * _hit_squash

	# Squash and tilt around the feet, then lift the hop off them.
	var reach := (_feet_y - _sprite_base_position.y) * sy
	sprite.scale = _sprite_base_scale * Vector2(sx, sy)
	sprite.rotation = tilt
	sprite.position = _sprite_base_position + Vector2(reach * sin(tilt), _feet_y - _sprite_base_position.y - reach * cos(tilt) - hop + breathe) + drop_offset
	if shadow != null:
		shadow.scale = _shadow_base_scale * (1.0 - 0.2 * hop / maxf(hop_height, 0.01)) * lerpf(DROP_SHADOW_SMALL, 1.0, drop_shadow)


# Coming down from the sky at GO is over: the squash, the dust at the feet and the
# thud. (The arena calls it the frame drop_offset reaches the ground.)
func land() -> void:
	_land = 1.0
	_puff(1.0, Vector2.ZERO)
	_play_sound(steps, land_sound)


# The drop's share of the look, every frame: nothing drawn while hidden (self_modulate,
# which only this script writes, so no arena's flash or fade is in the way), the
# shadow faint and small until the mortal is near it, and the parts that ride above
# the sprite carried up with it.
func _apply_drop_look(delta: float) -> void:
	_land = maxf(0.0, _land - delta / LAND_TIME)
	var drawn := 0.0 if drop_hidden else 1.0
	sprite.self_modulate.a = drawn
	if shadow != null:
		shadow.self_modulate.a = 0.0 if drop_hidden else drop_shadow
	if name_tag != null:
		name_tag.self_modulate.a = drawn
	if status_tag != null:
		status_tag.self_modulate.a = drawn
	if drowsy_count != null:
		drowsy_count.self_modulate.a = drawn
	if glow != null:
		glow.self_modulate.a = drawn
	if tranced_sprite != null:
		tranced_sprite.self_modulate.a = drawn
	if weeded_sprite != null:
		weeded_sprite.self_modulate.a = drawn
	var lift := drop_offset - _lifted
	if lift == Vector2.ZERO:
		return
	_lifted = drop_offset
	for part in [name_tag, status_tag, floating_text, drowsy_count, glow, stun_stars, tranced_sprite, weeded_sprite]:
		if part != null:
			part.position += lift


func _footfall(ratio: float) -> void:
	_steps_taken += 1
	if ratio > 0.85 and _steps_taken % 2 == 0:
		_puff(0.25, -_visual_velocity.normalized())
	if not step_sounds.is_empty():
		_play_sound(steps, step_sounds.pick_random())


func _start_dash_look(way: Vector2) -> void:
	_dash_direction = way
	_dash_stretch = 1.0
	_trail_time = TRAIL_TIME
	_trail_gap = 0.0
	_puff(1.0, -way)
	_play_sound(whoosh, dash_sound)


# A puff of dust at the feet, thrown towards `away` (and up). One emitter, so a
# new puff restarts it: they are short enough that it never shows.
func _puff(strength: float, away: Vector2) -> void:
	if dust == null or sprite == null or not sprite.visible:
		return
	dust.direction = (away + Vector2.UP * 0.8).normalized()
	dust.initial_velocity_max = 20.0 + 40.0 * strength
	dust.restart()
	dust.emitting = true


# The dash trail: the frame the sprite shows right now, left where it is, tinted
# the player's colour, fading out. The pool is the Afterimages children.
func _drop_afterimage() -> void:
	if afterimages == null or _trail_spots.is_empty() or not sprite.visible or sprite.sprite_frames == null:
		return
	var image := afterimages.get_child(_trail_next) as Sprite2D
	_trail_spots[_trail_next] = sprite.global_transform
	_trail_next = (_trail_next + 1) % _trail_spots.size()
	image.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	image.flip_h = sprite.flip_h
	var tint := UITokens.bandana_color(bandana_index).lightened(0.35)
	image.modulate = Color(tint.r, tint.g, tint.b, 0.55)
	image.visible = true


func _tick_afterimages(delta: float) -> void:
	if afterimages == null:
		return
	for index in range(_trail_spots.size()):
		var image := afterimages.get_child(index) as Sprite2D
		if not image.visible:
			continue
		image.global_transform = _trail_spots[index]  # stays where it was dropped
		image.modulate.a -= delta * 0.55 / TRAIL_LIFE
		if image.modulate.a <= 0.0:
			image.visible = false


func _play_sound(player: AudioStreamPlayer2D, stream: AudioStream) -> void:
	if player == null or stream == null or sprite == null or not sprite.visible:
		return
	player.stream = stream
	player.pitch_scale = randf_range(0.9, 1.1)
	player.volume_db = 0.0 if _player_driven else OTHER_VOLUME_DB
	player.play()


# A Settings toggle (screen_shake_enabled, reduce_flashing), false without the
# autoload - by path so checks compile without it.
func _setting(method: StringName) -> bool:
	if not is_inside_tree():
		return false
	var settings := get_node_or_null("/root/Settings")
	return settings != null and bool(settings.call(method))
