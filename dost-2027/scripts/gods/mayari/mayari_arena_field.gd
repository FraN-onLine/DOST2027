class_name MayariArenaField
extends Node2D

# Every visual piece of Mayari's playground lives here as a plain scene node:
# the ground sprite, the patintero border and the start / middle lines.
#
# The scene is authored in screen space (see scripts/gods/god_arena.gd) and this
# node NEVER moves that art: the border the designer drew IS the field, and the
# arena reads it back through authored_rect() to know where the mortals may
# walk. What the designer draws is what the players play.

# Read back from the drawn border by authored_rect(); the value below is only a
# fallback for a scene that has lost its Border line.
var field_rect := Rect2(242.5, 393.71, 910.99, 243.59)

@onready var border: Line2D = $Border


# The bounding box of the authored border line, in screen coordinates.
func authored_rect() -> Rect2:
	if border == null or border.points.size() < 2:
		return field_rect
	var bounds := _line_bounds(border)
	if bounds.size.x > 1.0 and bounds.size.y > 1.0:
		field_rect = bounds
	return field_rect


# The god's colour is the only thing the code paints: the border glows in it.
# Every other pixel (floor, lines, lantern) stays exactly as authored.
func apply_tint(tint: Color) -> void:
	if border != null:
		border.default_color = Color(tint.r, tint.g, tint.b, border.default_color.a)


func _line_bounds(line: Line2D) -> Rect2:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for point in line.points:
		var world := line.to_global(point)
		minimum = minimum.min(world)
		maximum = maximum.max(world)
	return Rect2(minimum, maximum - minimum)
