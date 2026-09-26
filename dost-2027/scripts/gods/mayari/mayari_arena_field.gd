class_name MayariArenaField
extends Node2D

# Every visual piece of Mayari's playground lives here as a plain scene node:
# the ground sprite, the floor tint, the patintero border and the start / middle
# lines. The arena only moves them when the field rect changes, which happens
# once per layout - and every frame of gameplay is drawn by these nodes, never
# by code.

const TEXTURE_SIZE := Vector2(128.0, 128.0)
const START_OFFSET := 46.0

# Cached copy of the field the arena asked for. MayariArena.field_rect is the
# single source of truth - this node only moves its own art to match it.
var field_rect := Rect2(56.0, 216.0, 1040.0, 360.0)

@onready var backdrop: Sprite2D = $Backdrop
@onready var floor_tint: ColorRect = $FloorTint
@onready var border: Line2D = $Border
@onready var start_line: Line2D = $StartLine
@onready var mid_line: Line2D = $MidLine


func set_field(rect: Rect2, tint: Color) -> void:
	field_rect = rect
	if backdrop == null:
		return
	backdrop.position = to_local(rect.get_center())
	backdrop.scale = Vector2(maxf(rect.size.x, 1.0) / TEXTURE_SIZE.x, maxf(rect.size.y, 1.0) / TEXTURE_SIZE.y)
	floor_tint.position = to_local(rect.position)
	floor_tint.size = rect.size
	border.points = _border_points(rect)
	border.default_color = Color(tint.r, tint.g, tint.b, 0.75)
	var start_x := rect.position.x + START_OFFSET
	start_line.position = Vector2.ZERO
	start_line.points = PackedVector2Array([
		to_local(Vector2(start_x, rect.position.y)),
		to_local(Vector2(start_x, rect.end.y)),
	])
	mid_line.position = Vector2.ZERO
	mid_line.points = PackedVector2Array([
		to_local(Vector2(rect.get_center().x, rect.position.y)),
		to_local(Vector2(rect.get_center().x, rect.end.y)),
	])


func start_line_x() -> float:
	return field_rect.position.x + START_OFFSET


func _border_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		to_local(rect.position),
		to_local(Vector2(rect.end.x, rect.position.y)),
		to_local(rect.end),
		to_local(Vector2(rect.position.x, rect.end.y)),
		to_local(rect.position),
	])
