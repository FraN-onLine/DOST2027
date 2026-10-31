extends Node2D

# Sidapa's charge meter (SidapaArena.tscn -> Gauge). A small bar under the
# mortal's feet: the arena feeds it the loaded power and the window that lands on
# the tile the arrow is meant to find, and this node only draws. The fill is the
# charge itself; the pale band is where the next leap will come down on the right
# tile, so the bar reads as "load until the marker is in the band".

var active := false
var charge := 0.0
var target := -1.0   # the charge that reaches the next tile (-1: no target)
var band := 0.1      # half-width of the window around `target`
var accent := Color(0.62, 0.45, 0.95)
var blitz := false
var size := Vector2(80.0, 12.0)

var _pulse := 0.0


func _process(delta: float) -> void:
	if not active:
		return
	_pulse += delta * (6.0 if blitz else 4.0)
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var track := Rect2(Vector2.ZERO, size)
	draw_rect(track, Color(0.04, 0.05, 0.10, 0.8))
	var filled := size.x * clampf(charge, 0.0, 1.0)
	draw_rect(Rect2(0.0, 0.0, filled, size.y), Color(accent.r, accent.g, accent.b, 0.75))
	if target >= 0.0:
		var low := clampf(target - band, 0.0, 1.0)
		var high := clampf(target + band, 0.0, 1.0)
		draw_rect(Rect2(size.x * low, 1.0, maxf(1.0, size.x * (high - low)), size.y - 2.0),
			Color(1.0, 0.84, 0.36, 0.26))
	draw_rect(track, Color(accent.r, accent.g, accent.b, 0.9), false, 2.0)
	var mark := size.x * clampf(charge, 0.0, 1.0)
	var glow := 1.0 if blitz else 0.7 + 0.3 * (sin(_pulse) * 0.5 + 0.5)
	draw_line(Vector2(mark, -4.0), Vector2(mark, size.y + 4.0), Color(1.0, 1.0, 1.0, glow), 2.0, true)
