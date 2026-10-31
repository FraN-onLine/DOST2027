extends Node2D

# Sidapa's throw (SidapaArena.tscn -> ThrowAim). Drawn in world coordinates: the
# arena owns the numbers (where the mortal stands, how loaded the throw is, where
# the stone will come down) and this node only paints.
#
# AIMING  A dotted arc from the mortal's hand to the landing spot, and a reticle
#         on that spot. The reticle turns gold over a tile and shows its number,
#         so a throw is read before it leaves the hand.
# FLYING  The stone itself along the same arc.

const FONT := preload("res://Assets/fonts/Minecraftia-UI.ttf")
const STONE_FILL := Color(0.72, 0.68, 0.60)
const GOLD := Color(1.0, 0.84, 0.36)

var active := false        # the throw is being aimed
var flying := false        # the stone is in the air
var from := Vector2.ZERO   # the hand
var to := Vector2.ZERO     # where the stone will land
var power := 0.0           # 0..1 loaded
var on_tile := false       # the landing spot is a tile
var tile := 0              # ...and its number
var flight_from := Vector2.ZERO
var flight_to := Vector2.ZERO
var flight_t := 0.0        # 0..1 across the flight
var height := 90.0
var accent := Color(0.62, 0.45, 0.95)

var _pulse := 0.0


func _process(delta: float) -> void:
	if not (active or flying):
		return
	_pulse += delta * 4.0
	queue_redraw()


func _draw() -> void:
	if flying:
		_draw_flight()
	if active:
		_draw_aim()


func _draw_aim() -> void:
	var span := from.distance_to(to)
	if span < 1.0:
		return
	var lift := height * (0.55 + 0.45 * clampf(power, 0.0, 1.0))
	var steps := 22
	for index in range(1, steps):
		if index % 2 == 0:
			continue
		var t := float(index) / float(steps)
		var point := _arc(from, to, lift, t)
		var fade := 0.45 + 0.5 * t
		draw_circle(point, 3.2, Color(accent.r, accent.g, accent.b, fade))
	var tint := GOLD if on_tile else Color(1.0, 1.0, 1.0, 0.55)
	var glow := 0.85 if on_tile else 0.6
	draw_arc(to, 20.0, 0.0, TAU, 28, Color(tint.r, tint.g, tint.b, glow), 2.0, true)
	draw_arc(to, 13.0 + 2.0 * sin(_pulse), 0.0, TAU, 24, Color(tint.r, tint.g, tint.b, glow * 0.5), 1.0, true)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var way := Vector2.from_angle(angle)
		draw_line(to + way * 24.0, to + way * 31.0, Color(tint.r, tint.g, tint.b, glow), 2.0, true)
	if tile > 0:
		var font_size := 16
		draw_string(FONT, to + Vector2(-60.0, -34.0), "TILE %d" % tile,
			HORIZONTAL_ALIGNMENT_CENTER, 120.0, font_size, Color(GOLD.r, GOLD.g, GOLD.b, 0.95))
	# The stone, still in the hand.
	_draw_stone_at(from, 1.0)


func _draw_flight() -> void:
	var t := clampf(flight_t, 0.0, 1.0)
	var ground := flight_from.lerp(flight_to, t)
	var point := _arc(flight_from, flight_to, height * 0.9, t)
	var shadow := 0.35 * (1.0 - absf(t * 2.0 - 1.0) * 0.5)
	draw_circle(ground, 7.0, Color(0.0, 0.0, 0.0, shadow))
	_draw_stone_at(point, 1.0)


func _arc(a: Vector2, b: Vector2, lift: float, t: float) -> Vector2:
	return a.lerp(b, t) + Vector2(0.0, -sin(t * PI) * lift)


func _draw_stone_at(at: Vector2, scale: float) -> void:
	var body := PackedVector2Array([
		at + Vector2(-9.0, 2.0) * scale, at + Vector2(-6.0, -6.0) * scale, at + Vector2(2.0, -9.0) * scale,
		at + Vector2(8.0, -4.0) * scale, at + Vector2(9.0, 4.0) * scale, at + Vector2(3.0, 9.0) * scale,
		at + Vector2(-5.0, 8.0) * scale, at + Vector2(-10.0, 5.0) * scale,
	])
	draw_colored_polygon(body, STONE_FILL)
	draw_arc(at, 13.0 * scale, 0.0, TAU, 20, Color(GOLD.r, GOLD.g, GOLD.b, 0.5), 2.0, true)
