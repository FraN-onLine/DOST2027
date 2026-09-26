class_name MayariGoal
extends Node2D

# One of Mayari's corner goals: the glowing box a mortal must hold to bank FAVOR
# "king of the hill" style while her clones sweep the field.
#
# Only the goal Mayari is currently lighting pays out - `set_active()` drives the
# glow/dim look of every piece of art in MayariGoal.tscn (Glow, Fill, Icon,
# Title, Favor, State). Nothing here is drawn in code.

@export var box_size := Vector2(152, 108)
@export var favor_amount := 1
@export var rate := 26.0
@export var base_rate := 26.0
@export var color := Color(0.55, 0.85, 1.0)
@export var zone_label := "GOAL"
@export var is_far := false
@export var favor_enabled := false

var held := false

var _pulse := 0.0

@onready var glow: Sprite2D = $Glow
@onready var fill: ColorRect = $Fill
@onready var icon: Sprite2D = $Icon
@onready var title: Label = $Title
@onready var favor_label: Label = $Favor
@onready var state_label: Label = $State


func _ready() -> void:
	title.text = zone_label
	_refresh_visual()


func setup(center: Vector2, size_value: Vector2, zone_rate: float, zone_color: Color, label_text: String, far: bool) -> void:
	position = center
	box_size = size_value
	color = zone_color
	zone_label = label_text
	is_far = far
	set_rate(zone_rate)
	if title != null:
		title.text = zone_label
	_refresh_visual()


# Mayari can dim or bless the goal she is lighting.
func set_rate(new_rate: float) -> void:
	rate = new_rate
	base_rate = new_rate
	_refresh_visual()


func set_rate_multiplier(multiplier: float) -> void:
	rate = base_rate * multiplier
	_refresh_visual()


# Exactly one corner burns at a time; the rest stay dim and pay nothing.
func set_active(active: bool) -> void:
	favor_enabled = active
	_refresh_visual()


func bounds() -> Rect2:
	return Rect2(global_position - box_size * 0.5, box_size)


func contains(point: Vector2) -> bool:
	return bounds().has_point(point)


func _process(delta: float) -> void:
	if not favor_enabled:
		return
	_pulse += delta
	_refresh_visual()


func _refresh_visual() -> void:
	if fill == null:
		return
	var pulse := 0.5 + 0.5 * sin(_pulse * 3.0 + (1.7 if is_far else 0.0))
	var tint := color
	if favor_enabled:
		fill.color = Color(tint.r, tint.g, tint.b, 0.22 + 0.14 * pulse)
		fill.modulate.a = 1.0
		glow.modulate = Color(tint.r, tint.g, tint.b, 0.22 + 0.16 * pulse)
		icon.modulate = Color(tint.r, tint.g, tint.b, 0.95)
		title.modulate = Color(1, 1, 1, 1)
		state_label.text = "HOLD TO CLAIM"
		state_label.modulate = Color(1, 1, 1, 0.9)
	else:
		fill.color = Color(0.6, 0.65, 0.75, 0.08)
		fill.modulate.a = 0.55
		glow.modulate = Color(tint.r, tint.g, tint.b, 0.07)
		icon.modulate = Color(0.7, 0.75, 0.85, 0.35)
		title.modulate = Color(1, 1, 1, 0.45)
		state_label.text = "DIM"
		state_label.modulate = Color(1, 1, 1, 0.3)
	favor_label.text = "%d FAVOR/s" % int(rate)
	favor_label.modulate = Color(1, 1, 1, 0.9 if favor_enabled else 0.35)
