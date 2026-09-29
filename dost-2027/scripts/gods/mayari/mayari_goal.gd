class_name MayariGoal
extends Node2D

# One of the four favor zones of the patintero arena.
#
# Exacty one zone is a favor zone at a time: that one burns yellow and pays
# FAVOR to whoever stands in it. A zone that is NOT the favor zone shows
# nothing at all - no box, no outline, no label, no glow, it is simply
# invisible.
#
# The box drawn in MayariGoal.tscn (the Fill rect) is the box that pays: its
# size is read back from the scene, so the rectangle the designer drew IS the
# area the mortal has to hold.

@export var rate := 26.0          # FAVOR the zone pays per second while held
@export var favor_amount := 1     # FAVOR banked per whole second
@export var zone_label := "ZONE"  # only ever used in the host's event log

# Always Mayari's yellow - the god colour paints the field, not the zones.
var color := Arena.FAVOR_COLOR
var box_size := Vector2(175.0, 85.0)  # read back from the authored Fill
var held := false
var favor_enabled := false

var _pulse := 0.0

@onready var fill: ColorRect = $Fill


func _ready() -> void:
	color = Arena.FAVOR_COLOR
	sync_authored_size()
	_refresh_visual()


# Read the authored Fill rect back: the drawn box is the box that pays.
func sync_authored_size() -> void:
	if fill != null and fill.size != Vector2.ZERO:
		box_size = fill.size


# Exactly one zone burns at a time; the rest stay invisible and pay nothing.
func set_active(active: bool) -> void:
	favor_enabled = active
	if active:
		_pulse = 0.0
	_refresh_visual()


func bounds() -> Rect2:
	# Exactly the authored Fill rect, wherever the designer put it.
	if fill != null and fill.size != Vector2.ZERO:
		return Rect2(global_position + fill.position, fill.size)
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
	# Not the favor zone: the arena shows nothing there at all.
	fill.visible = favor_enabled
	if not favor_enabled:
		return
	var pulse := 0.5 + 0.5 * sin(_pulse * 3.0)
	fill.color = Color(color.r, color.g, color.b, 0.16 + 0.14 * pulse)
