extends Node2D

# The Piko court (SidapaArena.tscn -> ArenaField/Board).
#
# The ten tiles and the start pad are their own nodes in the scene (Tile1..10 and
# Pad, see piko_tile.gd) - drag them to move the court, type their numbers in the
# inspector. Tile 10 is the turn tile. This node only finds them, tells them what
# is next / current / stone once a frame, and draws every stone on the court.
# Nothing is created at runtime.

const TILE_COUNT := 10
const STONE_FILL := Color(0.72, 0.68, 0.60)

var tiles: Array[Node2D] = []
var centers: Array[Vector2] = []   # tile 1..10 centres, in world coordinates
var start := Vector2.ZERO          # the pad's centre
var tile_size := 84.0

var stone_tile := 0
var next_tile := 0
var current_tile := 0
var forward := true
var blitz := false
var accent := Color(0.62, 0.45, 0.95)
var stones: Array = []             # every stone on the court: [{tile, color}] - ours and the rivals'

var _pulse := 0.0


func _ready() -> void:
	rebind()


# Read the court back out of the scene. Called on ready, and again whenever the
# host publishes a layout (a designer's edit needs no reload).
func rebind() -> void:
	tiles.clear()
	centers.clear()
	var field := get_parent()
	for index in range(TILE_COUNT):
		var tile := field.get_node_or_null("Tile%d" % (index + 1)) as Node2D
		if tile == null:
			push_warning("Piko: ArenaField/Tile%d is missing" % (index + 1))
			continue
		tiles.append(tile)
		centers.append(tile.global_position)
		if index == 0:
			tile_size = float(tile.get("tile_size"))
	var pad := field.get_node_or_null("Pad") as Node2D
	if pad != null:
		start = pad.global_position
	queue_redraw()


func set_state(stone: int, next: int, current: int, forward_leg: bool, blitz_now: bool, stones_now: Array = []) -> void:
	stone_tile = stone
	next_tile = next
	current_tile = current
	forward = forward_leg
	blitz = blitz_now
	stones = stones_now.duplicate()
	if stones.is_empty() and stone > 0:
		stones = [{"tile": stone, "color": STONE_FILL}]
	for index in range(tiles.size()):
		var tile := tiles[index]
		var number := index + 1
		tile.call("set_state", number == next, number == current, number == stone, blitz_now)
		tile.set("accent", accent)
	queue_redraw()


func _process(delta: float) -> void:
	if stones.is_empty():
		return
	_pulse += delta * (5.0 if blitz else 3.0)
	queue_redraw()


func _draw() -> void:
	for entry in stones:
		var tile := int(entry.get("tile", 0))
		if tile < 1 or tile > centers.size():
			continue
		var tint: Color = entry.get("color", STONE_FILL)
		# Down in the corner of the square, so the chalk number stays readable.
		_draw_stone(to_local(centers[tile - 1] + Vector2(22.0, 19.0)), tint)


func _draw_stone(at: Vector2, tint: Color) -> void:
	var body := PackedVector2Array([
		at + Vector2(-9.0, 2.0), at + Vector2(-6.0, -6.0), at + Vector2(2.0, -9.0),
		at + Vector2(8.0, -4.0), at + Vector2(9.0, 4.0), at + Vector2(3.0, 9.0),
		at + Vector2(-5.0, 8.0), at + Vector2(-10.0, 5.0),
	])
	draw_colored_polygon(body, tint)
	var glow := 0.45 + 0.25 * sin(_pulse)
	var ring := tint.lightened(0.45)
	draw_arc(at, 15.0, 0.0, TAU, 24, Color(ring.r, ring.g, ring.b, glow), 2.0, true)
