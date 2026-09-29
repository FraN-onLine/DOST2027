class_name ArenaField
extends Node2D

# The visual field of a god's arena: whatever the arena draws its playground
# with - the ground sprite, the border, the start and middle lines - as plain
# scene nodes, children of this node.
#
# This node is shared by every arena (see scripts/gods/common/arena.gd): the
# god's own scene adds the art, and this script only reads two things back out
# of it. The scene is authored in screen space, and this node NEVER moves that
# art: the border the designer drew IS the field, and the arena reads it back
# through authored_rect() to know where the mortals may walk. What the designer
# draws is what the players play.
#
# The line the field is measured from must be a Line2D child named "Border";
# any arena that draws its field another way can override authored_rect().

# Read back from the drawn border by authored_rect(); the value below is only a
# fallback for an arena that has lost (or never drawn) its Border line.
var field_rect := Rect2(Arena.UI_STRIP_WIDTH, 0.0, 1152.0 - Arena.UI_STRIP_WIDTH, 648.0)

@onready var border: Line2D = get_node_or_null("Border")


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
