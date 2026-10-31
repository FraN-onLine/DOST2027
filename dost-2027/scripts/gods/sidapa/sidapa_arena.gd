class_name SidapaArena
extends Arena

# SIDAPA - Piko. (scripts/gods/sidapa + scenes/gods/sidapa)
#
# EVERYTHING SHARED LIVES IN THE BASE (scripts/gods/common/arena.gd): the clock,
# the countdown, the mortal, the dialogues, the God's Due menu, the popups and the
# network plumbing. This file is only what makes the game Sidapa's.
#
# ONE COURT, EVERYONE ON IT
#   Every mortal plays the same Piko court and sees every rival on it (no
#   separate_players). Each mortal stands on the pad at their own spot, throws
#   their own stone and runs their own lap, and every reward and penalty goes
#   through score_favor(), so a client asks the host and the host banks it.
#
# THE COURT
#   Ten numbered tiles in a snake: 1-2-3 down the left column, 4-5-6 up the
#   middle, 7-8-9 down the right one, and the start pad beside tile 1. Tile 10 is
#   the TURN tile at the end of the snake - no stone ever lands there (a throw at
#   it is a miss) because it is where the lap turns around. The snake exists so
#   the hop arrow can be honest: every hop on the way out points into the right
#   half of the circle (north -> east -> south) and every hop on the way back into
#   the left half (south -> west -> north). The court is AUTHORED in the scene
#   (ArenaField/Pad and Tile1..Tile10): drag a tile and the game plays there.
#
# STONES
#   A thrown stone rests on its tile in the colour of the mortal who threw it, and
#   leaves the court the moment it is picked up (it is in hand). Every screen draws
#   every rival's stone too: a client reports its stone's tile to the host, the host
#   carries the whole set out on the world tick.
#
# A LAP
#   THROW   Aim with the mouse. The dotted arc and the reticle show where the
#           stone will come down (gold over a tile); HOLD LEFT CLICK to load the
#           throw - the bar under the mortal gets longer, farther - and RELEASE to
#           throw it, tumbang preso style. The stone flies, and landing on a tile
#           starts the lap; a throw that misses every tile costs stone_miss_penalty
#           and the stone bounces back for another try.
#   AIM     The arrow bobs across the leg's half of the circle. HOLD LEFT CLICK to
#           load the skipping bar (it fills to the top and slips back down while the
#           button stays down); release to hop in the arrow's direction, as far as
#           the bar says. The gauge paints the window that comes down on the next
#           tile. Land anywhere else and the lap restarts from the throw.
#   HOP     A short arc to the spot the release picked (snapped to the tile when it
#           is close enough). The landing is judged on arrival.
#
#   ORDER   The way out is 1..10 skipping the tile under the stone. Landing on any
#           other tile - including the stone's, which is "picking it up early" -
#           costs a penalty and restarts the throw. Every clean hop pays hop_reward,
#           the last one on the way out (the turn tile) pays end_reward instead.
#   BACK    The arrow flips to the left and the way back is 9..1 (all the tiles
#           below the turn): the stone's tile is landed on to PICK IT UP
#           (pickup_reward), and every other clean hop on the way back pays
#           hop_reward. If the stone landed on 9 it is collected first thing on the
#           way back. Once the mortal lands on 1 they hop back to the start pad and
#           the next lap opens with a throw.
#
#   HEAD COUNT (BLITZ ONLY)  When the blitz opens, a 12 s count appears over the
#           mortal's head (head_time). Every clean hop adds head_bonus back, never
#           past head_time. When it runs out the mortal is stunned (through
#           request_stun, so Sidapa's own favors see it) and the lap restarts from
#           the throw. It pauses while stunned, while the dialogue or the God's Due
#           menu is open, and it does not run during a throw or a hop. Outside the
#           blitz there is no count at all.
#
#   BLITZ  The last blitz_time seconds: the arrow sweeps blitz_arrow_scale times
#          faster and every clean hop pays blitz_hop_bonus more. The field pulses in
#          Sidapa's colour and the HUD says so, like Hanan's blitz.
#
# Every number is an @export - tune it in the inspector.

const CLEAN_COLOR := Color(0.7, 1.0, 0.8)
const LOSS_COLOR := Color(1.0, 0.5, 0.45)
const PICKUP_COLOR := Color(1.0, 0.84, 0.36)

enum Stage { THROW, FLIGHT, AIM, HOP }

@export_category("Piko")
@export var head_time := 12.0            # seconds on the over-head count before the stun
@export var head_bonus := 1.5            # seconds a clean hop gives back
@export var head_stun := 3.0             # the stun a spent head count leaves
@export var arrow_speed := 60.0          # degrees/second the aiming arrow sweeps
@export var blitz_time := 30.0           # the last seconds of the shared clock
@export var blitz_arrow_scale := 1.5     # how much faster the arrow bobs in the blitz
@export var blitz_hop_bonus := 20        # extra FAVOR on every clean hop in the blitz
@export var hop_min := 70.0              # pixels the shortest loaded hop carries
@export var hop_max := 290.0             # ...and the longest
@export var hop_time := 0.38             # seconds the leap arc takes
@export var hop_height := 46.0           # pixels the arc rises at its top
@export var charge_time := 1.1           # seconds the bar takes from empty to full
@export var land_snap := 62.0            # how close to a tile a landing must be to count
@export var start_hop_time := 0.3        # the little hop back to the pad after a lap
@export var spawn_spacing := 36.0        # px between mortals waiting on the pad

@export_category("Piko Throw")
@export var throw_min := 90.0            # pixels the shortest throw carries
@export var throw_max := 460.0           # ...and the longest
@export var throw_charge_time := 0.9     # seconds the power bar takes from empty to full
@export var throw_time := 0.45           # seconds the stone is in the air
@export var throw_height := 96.0         # pixels the throw arc rises at its top

@export_category("Piko Payouts")
@export var stone_miss_penalty := 50     # a throw that lands on no tile
@export var wrong_tile_penalty := 100    # a hop onto nothing, or onto the wrong tile
@export var stone_penalty := 200         # landing on your own stone on the way out
@export var hop_reward := 100            # each clean hop
@export var end_reward := 200            # the last hop of the way out
@export var pickup_reward := 250         # landing on the stone on the way back

@onready var board = get_node_or_null("ArenaField/Board")
@onready var arrow = get_node_or_null("Arrow")
@onready var gauge = get_node_or_null("Gauge")
@onready var throw_aim = get_node_or_null("ThrowAim")
@onready var head_label: Label = get_node_or_null("BarLayer/Head")
@onready var status_label: Label = get_node_or_null(BAND_STATE + "Status")
@onready var blitz_glow: Sprite2D = get_node_or_null("ArenaBG/BlitzGlow")

# The court, read off the authored nodes (see piko_board.gd).
var tiles: Array[Vector2] = []
var start := Vector2.ZERO
var tile_size := 84.0

var _stage := Stage.THROW
var _stone := 0             # the tile the mortal's stone sits on (0: no stone)
var _targets: Array[int] = []
var _step := 0              # index into _targets of the tile the next hop must find
var _leg_return := false    # false: the way out (right half), true: the way back (left)
var _pickup := false        # the stone is in hand again
var _current := 0           # the tile the mortal stands on (0: the start pad)
var _laps := 0

var _arrow_angle := -PI * 0.5
var _arrow_dir := 1.0
var _charging := false
var _charge := 0.0
var _charge_dir := 1.0

var _aim_world := Vector2.ZERO   # where the mouse points, in world coordinates
var _throw_loading := false
var _throw_charge := 0.0
var _throw_dir := 1.0
var _flight_from := Vector2.ZERO
var _flight_to := Vector2.ZERO
var _flight_left := 0.0
var _flight_total := 1.0
var _flight_returning := false

var _hop_from := Vector2.ZERO
var _hop_to := Vector2.ZERO
var _hop_left := 0.0
var _hop_total := 0.0
var _hop_tile := 0
var _home_hop := false

var _head_left := 12.0
var _stun_wait := 0.0       # ignore input for a beat while the host's stun travels back
var _was_stunned := false

var _blitz := false
var _blitz_phase := 0.0

var _stones_seen: Dictionary = {}   # client: mortal id -> the tile their stone rests on (0: none)
var _last_reported_stone := -1      # the tile we last told the host about


func _ready() -> void:
	_head_left = head_time
	super._ready()
	if board != null:
		tiles.assign(board.centers)
		start = board.start
		tile_size = board.tile_size
	_aim_world = start + Vector2(throw_max * 0.6, 0.0)
	if throw_aim != null:
		throw_aim.visible = false


# --- ARENA HOOKS (see scripts/gods/common/arena.gd) --------------------------

# The court is drawn from the scene, so there is nothing to build; re-read it in
# case the host's layout landed with the artists' edits.
func collect_units() -> void:
	if board != null:
		board.rebind()
		tiles.assign(board.centers)
		start = board.start
		tile_size = board.tile_size


func arena_round_reset() -> void:
	_stage = Stage.THROW
	_stone = 0
	_targets.clear()
	_step = 0
	_leg_return = false
	_pickup = false
	_current = 0
	_laps = 0
	_charging = false
	_charge = 0.0
	_charge_dir = 1.0
	_throw_loading = false
	_throw_charge = 0.0
	_throw_dir = 1.0
	_flight_left = 0.0
	_aim_world = _pad_point() + Vector2(throw_max * 0.6, 0.0)
	_hop_left = 0.0
	_home_hop = false
	_head_left = head_time
	_stun_wait = 0.0
	_was_stunned = false
	_blitz = false
	_blitz_phase = 0.0
	_stones_seen.clear()
	_last_reported_stone = -1
	if _networked and _authority and _net != null:
		_net.piko_stones.clear()
	player.scale = Vector2.ONE
	player.global_position = _pad_point()
	player.set_lock(true)
	if blitz_glow != null:
		blitz_glow.visible = false
	if arrow != null:
		arrow.visible = false
		arrow.active = false
	if gauge != null:
		gauge.visible = false
		gauge.active = false
	if throw_aim != null:
		throw_aim.visible = false
		throw_aim.active = false
		throw_aim.flying = false
	if head_label != null:
		head_label.visible = false
	if board != null:
		board.set_state(0, 0, 0, true, false)


func arena_local_effects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _blitz and _phase == Phase.PLAYING and not player.is_stunned() and _head_left > 0.0 and _head_left <= 4.0:
		out.append(effect(&"piko_head", "HEAD %ds" % ceili(_head_left), null, LOSS_COLOR, _head_left, head_time, true))
	return out


# --- FRAME -------------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	_tick_piko(delta)
	_refresh_hud()


func _tick_piko(delta: float) -> void:
	_update_blitz(delta)
	var stunned := player.is_stunned()
	if stunned and not _was_stunned:
		# A stun from any side - the head count, a rival's ring - drops the lap
		# where it stands and gives the count a fresh start for when they wake.
		_was_stunned = true
		_head_left = head_time
		if _stage != Stage.THROW:
			_reset_to_throw()
	elif not stunned and _was_stunned:
		_was_stunned = false
	if _phase != Phase.PLAYING:
		_leave_lap()
		return
	_stun_wait = maxf(0.0, _stun_wait - delta)
	if stunned:
		_sync_nodes()
		return
	if dialogue.is_active() or due_menu.is_open():
		_sync_nodes()
		return
	match _stage:
		Stage.THROW:
			_tick_head(delta)
			_tick_throw(delta)
		Stage.FLIGHT:
			_tick_flight(delta)
		Stage.AIM:
			_tick_head(delta)
			_tick_arrow(delta)
			_tick_charge(delta)
		Stage.HOP:
			_tick_hop(delta)
	_sync_nodes()


# --- THE HEAD COUNT (blitz only) ---------------------------------------------

func _tick_head(delta: float) -> void:
	if not _blitz:
		return
	_head_left -= delta
	if _head_left > 0.0:
		return
	_head_left = head_time
	_reset_to_throw()
	_stun_wait = 0.8
	var length := request_stun(head_stun)
	if length > 0.0:
		_show_banner("THE HEAD COUNT IS SPENT - STUNNED", LOSS_COLOR, 1.5)
		_set_callout("STUNNED %ds" % ceili(length), LOSS_COLOR, 1.5)
	else:
		_set_callout("CLEANSED", CLEAN_COLOR, 1.0)


# --- THROW (tumbang preso) ---------------------------------------------------

func _input(event: InputEvent) -> void:
	# A click on one of the favor panels is the HUD's answer, not a throw or a load.
	if super._tap_panel_click(event):
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _phase != Phase.PLAYING or dialogue.is_active() or due_menu.is_open():
		return
	if _stun_wait > 0.0 or player.is_stunned():
		return
	if event.pressed:
		if _stage == Stage.THROW:
			_begin_throw()
		elif _stage == Stage.AIM:
			_begin_charge()
	else:
		# The release is a stage of its own: the hold that loaded the throw (or
		# the hop) is what lets go here.
		if _stage == Stage.THROW and _throw_loading:
			_release_throw()
		elif _stage == Stage.AIM and _charging:
			_release_hop()


func _begin_throw() -> void:
	_throw_loading = true
	_throw_charge = 0.0
	_throw_dir = 1.0


# Held, the power bar fills all the way, slips back down, and comes up again - the
# same honesty as the hop bar, in the other direction.
func _tick_throw(delta: float) -> void:
	_aim_world = get_global_mouse_position()
	if not _throw_loading:
		return
	_throw_charge += _throw_dir * delta / maxf(0.05, throw_charge_time)
	if _throw_charge >= 1.0:
		_throw_charge = 1.0
		_throw_dir = -1.0
	elif _throw_charge <= 0.0:
		_throw_charge = 0.0
		_throw_dir = 1.0


# Where the loaded stone would come down: the aim's direction, the charge's reach.
func _throw_target() -> Vector2:
	var way := _aim_world - player.global_position
	if way.length_squared() < 1.0:
		way = Vector2.RIGHT
	way = way.normalized()
	var point := player.global_position + way * lerpf(throw_min, throw_max, _throw_charge)
	return _inside_field(point)


func _release_throw() -> void:
	_throw_loading = false
	_launch_stone(_throw_target())


# A direct throw at a world point (the tests' door, and the loaded throw's last
# step). The stone flies; _tick_flight judges where it comes down.
func _throw_at(world: Vector2) -> void:
	_throw_loading = false
	_launch_stone(_inside_field(world))


func _launch_stone(target: Vector2) -> void:
	_flight_from = player.global_position + Vector2(0.0, -18.0)
	_flight_to = target
	_flight_left = throw_time
	_flight_total = throw_time
	_flight_returning = false
	_stage = Stage.FLIGHT
	player.set_lock(true)
	var way := target - player.global_position
	if absf(way.x) > 1.0:
		player.facing = 1 if way.x >= 0.0 else -1
		player._apply_facing()


func _tick_flight(delta: float) -> void:
	_flight_left -= delta
	if _flight_left > 0.0:
		return
	if _flight_returning:
		_reset_to_throw()
		_set_callout("THROW AGAIN", god.color, 0.8)
		return
	var landed := _tile_under(_flight_to)
	var tile := 0 if landed == tiles.size() else landed
	if tile == 0:
		score_favor(-stone_miss_penalty, "Piko - missed throw")
		var text := "-%d  MISSED THE TILES" % stone_miss_penalty
		if landed == tiles.size():
			text = "-%d  THE TURN TILE TAKES NO STONE" % stone_miss_penalty
		_set_callout(text, LOSS_COLOR, 1.2)
		_shake_screen(impact_shake_time, 0.4)
		# The stone bounces off the ground and comes back to the hand: it is not
		# the board's stone until it lands on a tile.
		_flight_returning = true
		_flight_from = _flight_to
		_flight_to = player.global_position + Vector2(-26.0, -18.0)
		_flight_left = throw_time * 0.55
		_flight_total = _flight_left
		return
	_stone = tile
	player.global_position = _pad_point()
	player.set_lock(true)
	_begin_lap()


func _begin_lap() -> void:
	_targets.clear()
	# Every tile on the way out, the turn tile included, but never the stone's:
	# a stone on 9 waits for the way back.
	for tile in range(1, tiles.size() + 1):
		if tile != _stone:
			_targets.append(tile)
	_step = 0
	_leg_return = false
	_pickup = false
	_current = 0
	_stage = Stage.AIM
	_charging = false
	_charge = 0.0
	_charge_dir = 1.0
	_throw_loading = false
	_throw_charge = 0.0
	_arrow_angle = _sweep_low()
	_arrow_dir = 1.0
	_show_banner("STONE ON %d" % _stone, god.color, 1.2)
	_set_callout("STONE ON %d - LOAD AND LEAP" % _stone, god.color, 1.0)


func _tile_under(world: Vector2) -> int:
	var half := Vector2(tile_size, tile_size) * 0.5
	for index in range(tiles.size()):
		var rect := Rect2(tiles[index] - half, Vector2(tile_size, tile_size))
		if rect.has_point(world):
			return index + 1
	return 0


# The tile a stone may rest on: the turn tile ends the snake, it never holds one.
func _stone_tile_under(world: Vector2) -> int:
	var tile := _tile_under(world)
	return 0 if tile == tiles.size() else tile


func _inside_field(point: Vector2) -> Vector2:
	if _field.size == Vector2.ZERO:
		return point
	var inset := Vector2(12.0, 12.0)
	return point.clamp(_field.position + inset, _field.end - inset)


# Where this mortal waits on the pad. A shared trial puts every mortal on the
# same pad, so they line up side by side in peer order (every screen agrees on
# the order), centred on the slab the designer drew.
func _pad_point() -> Vector2:
	return start + Vector2(_slot_shift(), 0.0)


func _slot_shift() -> float:
	var ids: Array = [_my_id]
	if _net != null and _networked:
		ids = _net.players.keys().duplicate()
		ids.sort()
	var rank := ids.find(_my_id)
	if rank < 0:
		return 0.0
	return (float(rank) - float(ids.size() - 1) * 0.5) * spawn_spacing


# --- AIM / HOP ---------------------------------------------------------------

func _tick_arrow(delta: float) -> void:
	var speed := deg_to_rad(arrow_speed) * (blitz_arrow_scale if _blitz else 1.0)
	_arrow_angle += _arrow_dir * speed * delta
	var low := _sweep_low()
	var high := _sweep_high()
	if _arrow_angle >= high:
		_arrow_angle = high
		_arrow_dir = -1.0
	elif _arrow_angle <= low:
		_arrow_angle = low
		_arrow_dir = 1.0


func _begin_charge() -> void:
	_charging = true
	_charge = 0.0
	_charge_dir = 1.0


# The skipping bar: held, it fills all the way, slips back down, and comes up again.
func _tick_charge(delta: float) -> void:
	if not _charging:
		return
	_charge += _charge_dir * delta / maxf(0.05, charge_time)
	if _charge >= 1.0:
		_charge = 1.0
		_charge_dir = -1.0
	elif _charge <= 0.0:
		_charge = 0.0
		_charge_dir = 1.0


func _release_hop() -> void:
	_charging = false
	var way := Vector2.from_angle(_arrow_angle)
	var distance := lerpf(hop_min, hop_max, _charge)
	var landing := player.global_position + way * distance
	var tile := _nearest_tile(landing)
	var to := landing
	if tile > 0:
		to = tiles[tile - 1]
	if _field.size != Vector2.ZERO:
		to = to.clamp(_field.position + Vector2(16.0, 16.0), _field.end - Vector2(16.0, 16.0))
	_hop_tile = tile
	_hop_from = player.global_position
	_hop_to = to
	_hop_left = hop_time
	_hop_total = hop_time
	_home_hop = false
	_stage = Stage.HOP
	player.facing = 1 if way.x >= 0.0 else -1
	player._apply_facing()
	player.scale = Vector2(1.0, 0.9)
	player.set_lock(true)


func _nearest_tile(point: Vector2) -> int:
	var best := 0
	var best_distance := land_snap
	for index in range(tiles.size()):
		var distance := point.distance_to(tiles[index])
		if distance <= best_distance:
			best_distance = distance
			best = index + 1
	return best


func _tick_hop(delta: float) -> void:
	_hop_left -= delta
	var across := clampf(1.0 - _hop_left / maxf(0.01, _hop_total), 0.0, 1.0)
	player.global_position = _hop_from.lerp(_hop_to, across) + Vector2(0.0, -sin(across * PI) * hop_height)
	if across < 1.0:
		return
	player.scale = Vector2.ONE
	_land()


func _land() -> void:
	if _home_hop:
		_home_hop = false
		player.global_position = _pad_point()
		_reset_to_throw(false)
		_set_callout("THROW AGAIN", god.color, 0.8)
		return
	if _hop_tile == 0:
		_fail("OFF THE TILES", wrong_tile_penalty)
		return
	var expected := _expected_tile()
	if not _leg_return and _hop_tile == _stone and expected != _hop_tile:
		_fail("YOU PICKED UP THE STONE", stone_penalty)
		return
	if _hop_tile != expected:
		_fail("WRONG TILE", wrong_tile_penalty)
		return
	_clean_landing(_hop_tile)


func _clean_landing(tile: int) -> void:
	var last := _step == _targets.size() - 1
	var amount := hop_reward
	var reason := "Piko leap"
	var text := "CLEAN"
	if _leg_return:
		if tile == _stone and not _pickup:
			_pickup = true
			amount = pickup_reward
			reason = "Piko - picked up the stone"
			text = "PICKED IT UP!"
		elif last:
			text = "LAST TILE"
	elif last:
		# The way out ends on the turn tile: landing there flips the lap back.
		amount = end_reward
		reason = "Piko - reached the turn"
		text = "THE TURN!"
	if _blitz:
		amount += blitz_hop_bonus
	score_favor(amount, reason)
	if _blitz:
		_head_left = minf(head_time, _head_left + head_bonus)
	_current = tile
	_step += 1
	_set_callout("+%d  %s" % [amount, text], CLEAN_COLOR, 1.0)
	if _step >= _targets.size():
		_finish_leg()
	else:
		_begin_aim()


func _begin_aim() -> void:
	_stage = Stage.AIM
	_charging = false
	_charge = 0.0
	_charge_dir = 1.0
	_arrow_angle = _sweep_low()
	_arrow_dir = 1.0
	player.scale = Vector2.ONE
	player.set_lock(true)


func _finish_leg() -> void:
	if _leg_return:
		_lap_complete()
		return
	_leg_return = true
	_targets.clear()
	for tile in range(tiles.size() - 1, 0, -1):
		_targets.append(tile)
	_step = 0
	_show_banner("TURN BACK!", god.color, 1.2)
	_set_callout("TURN BACK - PICK UP YOUR STONE", PICKUP_COLOR, 1.5)
	_begin_aim()


func _lap_complete() -> void:
	_laps += 1
	_show_banner("PIKO!", god.color, 1.5)
	_log("Piko! The stone is in hand - back to the start.", god.color)
	_hop_from = player.global_position
	_hop_to = _pad_point()
	_hop_left = start_hop_time
	_hop_total = start_hop_time
	_hop_tile = 0
	_home_hop = true
	_stage = Stage.HOP
	player.set_lock(true)


func _fail(text: String, amount: int) -> void:
	score_favor(-amount, "Piko - " + text.to_lower())
	_set_callout("-%d  %s" % [amount, text], LOSS_COLOR, 1.3)
	_shake_screen(impact_shake_time, 0.5)
	_reset_to_throw()


# Back to the top of a lap: the stone is thrown again, so it is gone from the board
# and the mortal waits on the start pad. The head count is left alone.
func _reset_to_throw(snap := true, unlock := true) -> void:
	_stage = Stage.THROW
	_stone = 0
	_targets.clear()
	_step = 0
	_leg_return = false
	_pickup = false
	_current = 0
	_charging = false
	_charge = 0.0
	_charge_dir = 1.0
	_throw_loading = false
	_throw_charge = 0.0
	_throw_dir = 1.0
	_flight_left = 0.0
	_aim_world = _pad_point() + Vector2(throw_max * 0.6, 0.0)
	_hop_left = 0.0
	_home_hop = false
	player.scale = Vector2.ONE
	if snap:
		player.global_position = _pad_point()
	if unlock:
		player.set_lock(false)


# The round is over (or has not started): put the board to rest without moving or
# unlocking the mortal - the base owns that.
func _leave_lap() -> void:
	_stage = Stage.THROW
	_stone = 0
	_targets.clear()
	_step = 0
	_leg_return = false
	_pickup = false
	_current = 0
	_charging = false
	_charge = 0.0
	_throw_loading = false
	_throw_charge = 0.0
	_flight_left = 0.0
	_hop_left = 0.0
	_home_hop = false
	player.scale = Vector2.ONE
	if arrow != null:
		arrow.visible = false
		arrow.active = false
	if gauge != null:
		gauge.visible = false
		gauge.active = false
	if throw_aim != null:
		throw_aim.visible = false
		throw_aim.active = false
		throw_aim.flying = false
	if head_label != null:
		head_label.visible = false
	if board != null:
		board.set_state(0, 0, 0, true, false)
	_report_stone()


func _expected_tile() -> int:
	if _stage == Stage.THROW or _stage == Stage.FLIGHT or _step >= _targets.size():
		return 0
	return _targets[_step]


func _sweep_low() -> float:
	return PI * 0.5 if _leg_return else -PI * 0.5


func _sweep_high() -> float:
	return PI * 1.5 if _leg_return else PI * 0.5


# --- THE BLITZ ---------------------------------------------------------------

func _update_blitz(delta: float) -> void:
	var now := _phase == Phase.PLAYING and _trial_time <= blitz_time
	if now != _blitz:
		_blitz = now
		if _blitz:
			# The count is a blitz rule: it opens with the blitz, at full time.
			_head_left = head_time
			_show_banner("BLITZ! THE ARROW QUICKENS", UITokens.god_accent(god), 2.5)
			_log("BLITZ! The arrow sweeps %.1fx faster and every leap pays +%d FAVOR" % [blitz_arrow_scale, blitz_hop_bonus], UITokens.god_accent(god))
	if blitz_glow == null:
		return
	blitz_glow.visible = _blitz
	if not _blitz:
		return
	blitz_glow.global_position = _field.get_center()
	blitz_glow.scale = _field.size / Vector2(blitz_glow.texture.get_size())
	_blitz_phase += delta * 3.0
	var accent := UITokens.god_accent(god)
	blitz_glow.modulate = Color(accent.r, accent.g, accent.b, 0.12 if reduce_flashing() else 0.08 + 0.2 * (sin(_blitz_phase) * 0.5 + 0.5))


# --- NODES / HUD -------------------------------------------------------------

func _sync_nodes() -> void:
	_report_stone()
	if board != null:
		board.set_state(_local_stone_tile(), _expected_tile(), _current, not _leg_return, _blitz, _stone_entries())
	var accent := UITokens.god_accent(god)
	var calm := reduce_flashing()
	var live: bool = _phase == Phase.PLAYING and not player.is_stunned() and not dialogue.is_active() and not due_menu.is_open()

	var aiming_hop: bool = live and _stage == Stage.AIM
	if arrow != null:
		arrow.visible = aiming_hop
		arrow.active = aiming_hop
		if aiming_hop:
			arrow.global_position = player.global_position + Vector2(0.0, -6.0)
			arrow.heading = _arrow_angle
			arrow.sweep_from = _sweep_low()
			arrow.sweep_to = _sweep_high()
			arrow.color = accent
			arrow.calm = calm

	if throw_aim != null:
		var throwing: bool = live and _stage == Stage.THROW
		var flying: bool = _stage == Stage.FLIGHT and not player.is_stunned()
		throw_aim.visible = throwing or flying
		throw_aim.active = throwing
		throw_aim.flying = flying
		if throw_aim.visible:
			throw_aim.accent = accent
			throw_aim.stone_color = _stone_color(_my_id)
			throw_aim.power = _throw_charge
			throw_aim.height = throw_height
			throw_aim.from = player.global_position + Vector2(0.0, -16.0)
			var landing := _throw_target()
			throw_aim.to = landing
			throw_aim.tile = _stone_tile_under(landing)
			throw_aim.on_tile = throw_aim.tile > 0
			throw_aim.flight_from = _flight_from
			throw_aim.flight_to = _flight_to
			throw_aim.flight_t = 1.0 - _flight_left / maxf(0.01, _flight_total)

	if gauge != null:
		var loading: bool = live and _stage == Stage.THROW
		gauge.visible = aiming_hop or loading
		gauge.active = gauge.visible
		if gauge.visible:
			gauge.global_position = (player.global_position + Vector2(-40.0, 38.0)).round()
			gauge.accent = accent
			gauge.blitz = _blitz
			if aiming_hop:
				gauge.charge = _charge
				gauge.target = _target_charge()
				gauge.band = _charge_band()
			else:
				gauge.charge = _throw_charge
				gauge.target = -1.0
				gauge.band = 0.0

	if head_label != null:
		head_label.visible = _phase == Phase.PLAYING and _blitz
		if head_label.visible:
			head_label.text = "%ds" % ceili(maxf(0.0, _head_left))
			head_label.add_theme_color_override("font_color", LOSS_COLOR if _head_left <= 4.0 else Color(0.88, 0.86, 0.95))
			head_label.reset_size()
			var head := player.get_global_transform_with_canvas().origin
			head_label.position = (head + Vector2(-head_label.size.x * 0.5, -116.0)).round()
			head_label.pivot_offset = head_label.size * 0.5
			var scale_pulse := 1.0
			if _head_left <= 4.0 and not calm:
				scale_pulse = 1.0 + 0.12 * absf(sin(Time.get_ticks_msec() * 0.008))
			head_label.scale = Vector2.ONE * scale_pulse


# --- THE STONES ON THE COURT -----------------------------------------------------
# A stone is on the court while it has landed and not yet been picked up: the
# moment the mortal collects it on the way back it is in their hand, and the board
# stops drawing it. Every mote of the court wears the colour of the mortal who
# threw it, and every screen draws every rival's stone too.

func _local_stone_tile() -> int:
	return 0 if _pickup else _stone


# The colour of a mortal's stone: the bandana they wear, lightened enough to read
# against the dark court.
func _stone_color(mortal_id: int) -> Color:
	return UITokens.bandana_color(bandana_of(mortal_id)).lightened(0.12)


# Every stone this screen can see: its own live one, and every rival's as the host
# last said (the host reads its own report table, a client the world tick).
func _stone_entries() -> Array:
	var by_id := {}
	var mine := _local_stone_tile()
	if mine > 0:
		by_id[_my_id] = mine
	var reported: Dictionary = {}
	if _networked and _net != null:
		reported = _net.piko_stones if _authority else _stones_seen
	for id in reported.keys():
		var tile := int(reported[id])
		if int(id) == _my_id or tile <= 0:
			continue
		by_id[int(id)] = tile
	var out: Array = []
	for id in by_id.keys():
		out.append({"tile": by_id[id], "color": _stone_color(int(id))})
	return out


# A client's stone moves its own lap along: tell the host where it rests whenever
# that changes (0 when it is in the air or in the hand).
func _report_stone() -> void:
	if not _networked or _authority or _net == null or not _net.has_multiplayer_peer():
		return
	var tile := _local_stone_tile()
	if tile == _last_reported_stone:
		return
	_last_reported_stone = tile
	_net.rpc_id(1, "report_piko_stone", tile)


# The host rides every mortal's stone on the world tick, so each screen draws the
# whole court; a client adopts the list it last received.
func arena_tick_fields() -> Dictionary:
	if not _networked or _net == null:
		return {}
	var stones := {_my_id: _local_stone_tile()}
	var reported: Dictionary = _net.piko_stones
	for id in reported.keys():
		stones[int(id)] = int(reported[id])
	return {"piko_stones": stones}


func arena_read_tick(state: Dictionary) -> void:
	var stones: Dictionary = state.get("piko_stones", {})
	_stones_seen.clear()
	for id in stones.keys():
		_stones_seen[int(id)] = int(stones[id])


func _target_charge() -> float:
	var target := _expected_tile()
	if target == 0 or target > tiles.size():
		return -1.0
	var to := tiles[target - 1]
	return clampf((player.global_position.distance_to(to) - hop_min) / maxf(1.0, hop_max - hop_min), 0.0, 1.0)


func _charge_band() -> float:
	return clampf(land_snap / maxf(1.0, hop_max - hop_min), 0.02, 0.5)


func _refresh_hud() -> void:
	if status_label != null:
		var next := _expected_tile()
		var heading := "THROW"
		match _stage:
			Stage.THROW:
				heading = "THROW %d%%" % roundi(_throw_charge * 100.0)
			Stage.FLIGHT:
				heading = "STONE IN THE AIR"
			Stage.AIM, Stage.HOP:
				if _leg_return:
					heading = "BACK - TILE %d" % next
				elif next == tiles.size():
					heading = "TURN - TILE %d" % next
				else:
					heading = "OUT - TILE %d" % next
		var stone := "-" if _stone == 0 else str(_stone)
		var head := ""
		if _blitz:
			head = "   HEAD %ds" % ceili(maxf(0.0, _head_left))
		status_label.text = "LAPS %d   STONE %s   %s%s" % [_laps, stone, heading, head]
		if _blitz:
			status_label.text = "BLITZ   " + status_label.text
	if hint_label != null:
		if player.is_stunned():
			hint_label.text = "STUNNED - THE HEAD COUNT IS PAUSED" if _blitz else "STUNNED"
		elif _stage == Stage.THROW:
			hint_label.text = "AIM AND HOLD %s TO LOAD, RELEASE TO THROW THE STONE   %s" % [
				key_cap(&"attack"), favor_keys_hint()]
		elif _stage == Stage.FLIGHT:
			hint_label.text = "THE STONE IS IN THE AIR...   %s" % favor_keys_hint()
		elif _stage == Stage.AIM:
			var goal := "LAND ON %d" % _expected_tile()
			if not _leg_return and _expected_tile() == tiles.size():
				goal = "LAND ON %d TO TURN BACK" % tiles.size()
			hint_label.text = "HOLD %s TO LOAD, RELEASE TO LEAP   %s   %s" % [
				key_cap(&"attack"), goal, favor_keys_hint()]
		else:
			hint_label.text = "LEAPING...   %s" % favor_keys_hint()


func _set_callout(text: String, tint: Color, seconds: float) -> void:
	callout(text, tint, seconds)
