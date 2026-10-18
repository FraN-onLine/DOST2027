@tool
class_name OrnamentFrame
extends Control

# The one ornament of the design system: a thin double rule with a small diamond
# stud at each corner, after banig weaving and okir carving. Drawn on the pixel
# grid with draw_rect only (no texture, no gradient, no blur), tinted by `color`
# - a god's accent on an Almanac frame, gold on the title lockup.
#
# Lay it over a panel (full-rect anchors); it never takes the mouse. With
# `rule_only` it draws a single horizontal rule with a centre diamond instead -
# the line under the title.

@export var color := UITokens.GOLD:
	set(value):
		color = value
		queue_redraw()
@export var inset := 4:
	set(value):
		inset = value
		queue_redraw()
@export var rule_only := false:
	set(value):
		rule_only = value
		queue_redraw()

const STUD := [1, 3, 5, 7, 5, 3, 1]  # a 7 px diamond, one row at a time


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if rule_only:
		_draw_rule()
		return
	var outer := Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2).abs()
	if outer.size.x < 24 or outer.size.y < 24:
		return
	_frame(outer, 2, color)
	_frame(outer.grow(-5), 1, Color(color, color.a * 0.6))
	for corner in [outer.position, Vector2(outer.end.x, outer.position.y),
			Vector2(outer.position.x, outer.end.y), outer.end]:
		_stud(corner)


func _draw_rule() -> void:
	var mid := floorf(size.y * 0.5)
	var half := floorf(size.x * 0.5)
	draw_rect(Rect2(0, mid - 3, size.x, 1), Color(color, color.a * 0.6))
	draw_rect(Rect2(0, mid + 2, size.x, 1), Color(color, color.a * 0.6))
	draw_rect(Rect2(0, mid - 1, half - 8, 2), color)
	draw_rect(Rect2(half + 8, mid - 1, size.x - half - 8, 2), color)
	_stud(Vector2(half, mid))


func _frame(rect: Rect2, width: int, tint: Color) -> void:
	rect = Rect2(rect.position.floor(), rect.size.floor())
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, width)), tint)
	draw_rect(Rect2(rect.position.x, rect.end.y - width, rect.size.x, width), tint)
	draw_rect(Rect2(rect.position.x, rect.position.y, width, rect.size.y), tint)
	draw_rect(Rect2(rect.end.x - width, rect.position.y, width, rect.size.y), tint)


# A diamond centred on `at`, with a dark pip in the middle so it reads as a
# stud, not a blob.
func _stud(at: Vector2) -> void:
	at = at.floor()
	for row in STUD.size():
		var width: int = STUD[row]
		draw_rect(Rect2(at.x - (width - 1) * 0.5, at.y - 3 + row, width, 1), color)
	draw_rect(Rect2(at.x, at.y, 1, 1), UITokens.NIGHT_900)
