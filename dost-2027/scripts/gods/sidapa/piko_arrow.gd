extends Node2D

# Sidapa's aiming arrow (SidapaArena.tscn -> Arrow). The arena owns the sweep -
# which half of the circle the leg allows, how fast it bobs and where it points -
# and hands it over every frame; this node only draws. The half is drawn as a
# faint arc so the mortal can read the whole swing at a glance, and the arrow
# itself rides it: north to south on the right on the way out, south to north on
# the left on the way back.

var active := false
var heading := -PI * 0.5
var sweep_from := -PI * 0.5
var sweep_to := PI * 0.5
var color := Color(0.62, 0.45, 0.95)
var calm := false
var radius := 62.0

var _pulse := 0.0


func _process(delta: float) -> void:
	if not active:
		return
	_pulse += delta * 4.0
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var breathe := 0.55 if calm else 0.4 + 0.2 * (sin(_pulse) * 0.5 + 0.5)
	draw_arc(Vector2.ZERO, radius, sweep_from, sweep_to, 48,
		Color(color.r, color.g, color.b, breathe * 0.55), 2.0, true)
	# The two ends of the half: the limits of this leg's swing.
	for angle in [sweep_from, sweep_to]:
		var end := Vector2.from_angle(angle)
		draw_line(end * (radius - 8.0), end * (radius + 8.0),
			Color(color.r, color.g, color.b, 0.55), 2.0, true)
	var way := Vector2.from_angle(heading)
	var tail := way * (radius - 26.0)
	var shoulder := way * (radius - 8.0)
	var tip := way * (radius + 6.0)
	var side := way.orthogonal() * 9.0
	draw_line(tail, shoulder, Color(color.r, color.g, color.b, 0.9), 3.0, true)
	draw_colored_polygon(PackedVector2Array([tip, shoulder + side, shoulder - side]), color)
	# A dot at the pivot, so the arc never reads as a loose stroke.
	draw_circle(Vector2.ZERO, 3.0, Color(color.r, color.g, color.b, 0.7))
