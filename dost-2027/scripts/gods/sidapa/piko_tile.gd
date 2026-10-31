@tool
extends Node2D

# One chalk square of Sidapa's Piko court (PikoTile.tscn / PikoPad.tscn, placed
# in SidapaArena.tscn as ArenaField/Tile1..10 and ArenaField/Pad).
#
# The art lives in the scene: Background is a Sprite2D holding the chalk texture,
# Number and Caption are Labels. The designer owns all of it - swap the texture,
# recolour it with Background's modulate, change the font or the label colour -
# and this script only feeds the labels' text and tints the sprite's
# self_modulate for the state the arena asks for. Nothing is drawn in code.
#
# The arena hands each tile its state once a frame (set_state): the next tile to
# land on glows in Sidapa's colour, the tile the mortal stands on is green, the
# stone's tile is warm, and the turn tile is always warm.

const WARM := Color(1.0, 0.80, 0.42)
const CURRENT := Color(0.62, 1.0, 0.78)

@export var number := 1:
	set(value):
		number = value
		_sync_text()
@export var pad := false:
	set(value):
		pad = value
		_sync_text()
@export var turn := false:
	set(value):
		turn = value
		_sync_text()
@export var tile_size := 84.0
@export var accent := Color(0.62, 0.45, 0.95)

var next := false
var current := false
var stone := false
var blitz := false

var _pulse := 0.0
@onready var background: Sprite2D = get_node_or_null("Background") as Sprite2D
@onready var number_label: Label = get_node_or_null("Number") as Label
@onready var caption: Label = get_node_or_null("Caption") as Label


func _ready() -> void:
	_sync_text()
	_apply()


func set_state(is_next: bool, is_current: bool, has_stone: bool, is_blitz: bool) -> void:
	if next == is_next and current == is_current and stone == has_stone and blitz == is_blitz:
		return
	next = is_next
	current = is_current
	stone = has_stone
	blitz = is_blitz
	_apply()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not next:
		return
	_pulse += delta * (5.0 if blitz else 3.0)
	_apply()


func _sync_text() -> void:
	if not is_node_ready():
		return
	if number_label != null:
		number_label.visible = not pad
		number_label.text = str(number)
	if caption != null:
		caption.visible = pad or turn
		caption.text = "START" if pad else "TURN"


func _apply() -> void:
	if background == null:
		return
	var tint := Color.WHITE
	if turn:
		tint = Color(1.0, 0.92, 0.78)
	if stone:
		tint = WARM
	if current:
		tint = CURRENT
	if next:
		var glow := 0.5 + 0.5 * sin(_pulse)
		tint = accent.lerp(Color.WHITE, 0.35 + 0.35 * glow)
	background.self_modulate = tint
	if number_label != null:
		number_label.self_modulate = tint.lerp(Color.WHITE, 0.45) if (next or current or stone) else Color.WHITE
