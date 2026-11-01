extends Node2D

# Tala's throw hint (TalaArena.tscn -> SlipperArrow), read the way Sidapa's
# piko_arrow reads a Piko throw: a short arrow beside the mortal aimed at the
# cursor. The arena owns when it shows - only while a slipper is in hand and the
# line lets you throw - and hands over the heading every frame; this node only
# draws. Going inactive hides the node outright, so the arrow drawn on the last
# frame before a throw does not stay on screen.

var active := false:
	set(value):
		active = value
		visible = value
		if value:
			queue_redraw()
var heading := 0.0
var color := Color(0.42, 0.68, 1.0)
var radius := 55.0


func _ready() -> void:
	visible = active


func _process(_delta: float) -> void:
	if active:
		queue_redraw()


func _draw() -> void:
	var way := Vector2.from_angle(heading)
	var tail := way * (radius - 24.0)
	var shoulder := way * (radius - 6.0)
	var tip := way * (radius + 10.0)
	var side := way.orthogonal() * 9.0
	draw_line(tail, shoulder, Color(color.r, color.g, color.b, 0.9), 3.0, true)
	draw_colored_polygon(PackedVector2Array([tip, shoulder + side, shoulder - side]), color)
