class_name TalaArena
extends Arena

@export_category("Tumbang Preso")
@export var throw_speed := 720.0
@export var slipper_range := 850.0
@export var can_radius := 28.0
@export var tala_radius := 34.0
@export var tala_speed := 92.0
@export var tala_min_y := 285.0
@export var tala_max_y := 565.0
@export var can_repair_time := 3.0
@export var can_favor := 300
# FAVOR lost two ways: when Tala catches your slipper, and when YOU walk into
# her - running into the guard costs the same as her grabbing your footwear.
@export var tala_penalty := 100

@export_category("Impact")
# The weight of a landed throw and of her touch: the FIELD jumps (never the
# HUD, so its labels stay readable) and a wash flashes over the screen. The
# shake and the wash themselves live in the base arena (scripts/gods/common/
# arena.gd); only the timings are this game's own. Both comfort options in
# Settings hold: screen shake off means no shake at all, reduce flashing halves
# the wash so it reads as a wash, not a strobe.
@export var can_hit_shake_time := 0.12    # YOUR slipper downs a can (a light kick)
@export var tala_hit_shake_time := 0.15    # YOUR slipper reaches Tala (a light kick)

# THE GUARD WHO CUTS YOU OFF. Every so often she hurries along her OWN route to
# meet a slipper in the air: seek_chance is rolled when a slipper is thrown, and
# she walks to the spot of her beat nearest where its path would reach her,
# standing there until it is caught, lands, or seek_time runs out. She never
# leaves the TalaPath - she anticipates the throw from it. One intercept at a
# time, with a cooldown, so she cannot cut off every slipper that flies.
@export var seek_chance := 0.45   # how often a throw makes her hurry to cut it off
@export var seek_speed := 260.0   # how fast she hurries along her route
@export var seek_time := 1.4      # seconds one intercept lasts at most
@export var seek_cooldown := 1.6  # seconds between two intercepts

# Node2D, not Sprite2D: the scene may draw her as a plain Sprite2D or as an
# AnimatedSprite2D (she is animated as of the Tala-Sheet art) - the rules only
# ever read and write where she stands.
@onready var tala: Node2D = get_node_or_null("ArenaField/Tala")
@onready var tala_path: Line2D = get_node_or_null("ArenaField/TalaPath")
@onready var cans_root: Node2D = get_node_or_null("ArenaField/Cans")
@onready var barrier: Line2D = get_node_or_null("ArenaField/Barrier")
@onready var slippers_root: Node2D = get_node_or_null("Slippers")
@onready var status_label: Label = get_node_or_null("TalaHud/Status")
@onready var hint_label: Label = get_node_or_null("TalaHud/Hint")
# Slipper.tscn: the slipper's own scene. `toss` while it flies, `grounded`
# once it lands - type 1 is your own, type 2 a rival's.
const SLIPPER_SCENE := preload("res://scenes/gods/tala/Slipper.tscn")
const SLIPPER_TOSS_SUFFIX := "toss"          # slipper-type-N-toss: the thrown clip
const SLIPPER_GROUNDED_SUFFIX := "grounded"  # slipper-type-N-grounded: the landed one

var _cans: Array[AnimatedSprite2D] = []
var _can_labels: Dictionary = {}   # can index -> the authored INACTIVE tag hanging over it
var _can_hits := 0  # cans downed so far: the host's count, mirrored on the tick
var _seen_can_hits := 0  # can hits this screen has already shaken for
var _can_hit_owner := -1  # who threw the slipper that downed the last can
var _tala_hits := 0  # slippers Tala has caught so far: the host's count, mirrored on the tick
var _seen_tala_hits := 0  # catches this screen has already shaken for
var _tala_hit_owner := -1  # whose slipper Tala caught last
# A downed can keeps its place: it plays `down` instead of `hittable`, darkens,
# and its INACTIVE tag shows until it stands back up.
const CAN_ACTIVE_ANIM := &"hittable"
const CAN_DOWN_ANIM := &"down"
const CAN_INACTIVE_DIM := Color(0.55, 0.55, 0.62)
var _slippers: Dictionary = {}
var _slipper_nodes: Dictionary = {}
var _modes: Dictionary = {}
var _can_repair: Dictionary = {}
var _shoot_x := 465.0
var _tala_dir := 1.0
var _local_mode := "ready"
# Tala walks the Line2D drawn for her in the scene (ArenaField/TalaPath), the
# way Mayari's clones walk theirs: the path IS the route, wherever it is drawn.
var _tala_knots := PackedVector2Array()  # the path's points, in world space
var _tala_length := 0.0                  # how long that route is
var _tala_distance := 0.0                # how far along it Tala stands
var _rng := RandomNumberGenerator.new()
var _seeking := false       # she has hurried along her route to cut a slipper off
var _seek_owner := -1       # whose slipper she is cutting off
var _seek_point := Vector2.INF  # where that slipper's path would reach her
var _seek_distance := 0.0   # the spot of her route this intercept walks to
var _seek_time := 0.0       # seconds left on this intercept
var _seek_cd := 0.0         # seconds before she may intercept again
# The host's word on where she stands while intercepting (the route knows
# nothing about it); Vector2.INF whenever she is simply walking her beat.
var _tala_seek := Vector2.INF


func _ready() -> void:
	super._ready()
	_rng.randomize()
	for id in rules.mortals.keys():
		_modes.get_or_add(int(id), "ready")
	_update_local_bounds()
	_refresh_status()


func _connect_network() -> void:
	super._connect_network()
	if _net != null and _authority and _net.has_signal("tala_throw_requested"):
		_net.tala_throw_requested.connect(_on_throw_requested)


# The follow camera's edge arrow: Tala, who walks her path guarding the cans.
func edge_targets() -> Array:
	return [tala] if tala != null else []


func collect_units() -> void:
	_cans.clear()
	_can_labels.clear()
	if cans_root != null:
		for child in cans_root.get_children():
			if child is AnimatedSprite2D:
				_can_labels[_cans.size()] = child.get_node_or_null("InactiveTag")
				_cans.append(child)
	if barrier != null and barrier.points.size() > 0:
		_shoot_x = barrier.to_global(barrier.points[0]).x
	_read_tala_path()
	for index in range(_cans.size()):
		_can_repair.get_or_add(index, 0.0)
		_refresh_can(index)
	if _authority and rules != null:
		for id in rules.mortals.keys():
			_modes.get_or_add(int(id), "ready")


# The route is read from the scene, in world space, exactly once per round: the
# Line2D may be moved, scaled or have its points edited in the editor and Tala
# still walks where the designer drew her.
func _read_tala_path() -> void:
	_tala_knots = PackedVector2Array()
	_tala_length = 0.0
	if tala_path != null and tala_path.points.size() >= 2:
		for point in tala_path.points:
			_tala_knots.append(tala_path.to_global(point))
		for index in range(1, _tala_knots.size()):
			_tala_length += _tala_knots[index].distance_to(_tala_knots[index - 1])
	_tala_distance = clampf(_tala_distance, 0.0, _tala_length)
	_place_tala()


# The world point a given distance along the route sits on.
func _point_on_tala_path(distance: float) -> Vector2:
	if _tala_knots.size() < 2:
		return tala.global_position if tala != null else Vector2.ZERO
	var left := clampf(distance, 0.0, _tala_length)
	for index in range(1, _tala_knots.size()):
		var segment: float = _tala_knots[index].distance_to(_tala_knots[index - 1])
		if left > segment or index == _tala_knots.size() - 1:
			return _tala_knots[index - 1].lerp(_tala_knots[index], 0.0 if segment <= 0.0 else clampf(left / segment, 0.0, 1.0))
		left -= segment
	return _tala_knots[_tala_knots.size() - 1]


func _place_tala() -> void:
	if tala == null:
		return
	# While she is cutting a slipper off, the host's word is where she stands -
	# the route says nothing about an intercept.
	if _tala_seek != Vector2.INF:
		tala.global_position = _tala_seek
		return
	if _tala_knots.size() < 2:
		return
	# global_position, not `position = to_local(...)`: the sprite's own offset
	# would feed back into the conversion and walk her off the screen.
	tala.global_position = _point_on_tala_path(_tala_distance)


func arena_rules_tick(delta: float) -> void:
	if not _authority:
		return
	_seek_cd = maxf(0.0, _seek_cd - delta)
	_move_tala(delta)
	_move_slippers(delta)
	_check_pickups()
	_check_tala_touch()
	_repair_cans(delta)


func arena_round_reset() -> void:
	_slippers.clear()
	_modes.clear()
	_can_repair.clear()
	_can_hits = 0
	_seen_can_hits = 0
	_can_hit_owner = -1
	_tala_hits = 0
	_seen_tala_hits = 0
	_tala_hit_owner = -1
	_tala_dir = 1.0
	_tala_distance = 0.0
	_seeking = false
	_seek_owner = -1
	_seek_point = Vector2.INF
	_seek_time = 0.0
	_seek_cd = 0.0
	_tala_seek = Vector2.INF
	if tala != null and _tala_knots.size() < 2:
		tala.position.y = (tala_min_y + tala_max_y) * 0.5
	_place_tala()
	for id in rules.mortals.keys():
		_modes[int(id)] = "ready"
	for index in range(_cans.size()):
		_can_repair[index] = 0.0
		_refresh_can(index)
	_reset_screen_impact()  # a new round starts with the screen at rest
	for slipper in _slipper_nodes.values():
		if is_instance_valid(slipper):
			slipper.queue_free()
	_slipper_nodes.clear()
	_local_mode = "ready"
	_update_local_bounds()


# A can is worth hitting while its repair clock reads zero.
func is_can_active(can_index: int) -> bool:
	if can_index < 0 or can_index >= _cans.size():
		return false
	return float(_can_repair.get(can_index, 0.0)) <= 0.0


# Paint one can's state: active cans play `hittable` at full colour with no tag,
# downed ones keep their place but play `down`, darken, and hang INACTIVE over
# them until they stand back up.
func _refresh_can(can_index: int) -> void:
	if can_index < 0 or can_index >= _cans.size():
		return
	var can: AnimatedSprite2D = _cans[can_index]
	var active := is_can_active(can_index)
	if can.sprite_frames != null and can.sprite_frames.has_animation(CAN_ACTIVE_ANIM if active else CAN_DOWN_ANIM):
		can.play(CAN_ACTIVE_ANIM if active else CAN_DOWN_ANIM)
	can.modulate = Color.WHITE if active else CAN_INACTIVE_DIM
	var tag: Node = _can_labels.get(can_index)
	if tag != null and tag is CanvasItem:
		(tag as CanvasItem).visible = not active


func _process(delta: float) -> void:
	super._process(delta)
	_update_local_bounds()
	_render_slippers()
	_refresh_status()


func _input(event: InputEvent) -> void:
	# A click on one of the favor panels is the HUD's answer, not a throw.
	if super._tap_panel_click(event):
		return
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _phase != Phase.PLAYING or player.locked or dialogue.is_active() or due_menu.is_open():
		return
	# The click is on the screen; the throw is aimed in the world (the follow
	# camera can put the two apart - without it the two are the same point).
	_try_throw(get_canvas_transform().affine_inverse() * event.position)
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _try_throw(mouse_position: Vector2) -> void:
	if _local_mode != "ready" or player.global_position.x > _shoot_x - player.radius:
		return
	var direction := (mouse_position - player.global_position).normalized()
	if direction.length_squared() < 0.01:
		direction = Vector2.RIGHT
	_modes[_my_id] = "flying"
	_local_mode = "flying"
	if _authority:
		_start_throw(_my_id, direction)
	elif _net != null and _net.has_multiplayer_peer():
		_net.rpc_id(1, "request_tala_throw", direction, player.global_position)


func _on_throw_requested(mortal_id: int, direction: Vector2, requested_origin: Vector2) -> void:
	if not _authority or _phase != Phase.PLAYING or direction.length_squared() < 0.01:
		return
	var origin := mortal_position(mortal_id)
	if origin == Vector2.INF:
		origin = requested_origin
	elif origin.distance_to(requested_origin) > 90.0:
		return
	if str(_modes.get(mortal_id, "ready")) != "ready" or not _field.has_point(origin):
		return
	if origin.x > _shoot_x - player.radius:
		return
	_start_throw(mortal_id, direction.normalized(), origin)


func _start_throw(mortal_id: int, direction: Vector2, start_position := Vector2.INF) -> void:
	var origin := start_position if start_position != Vector2.INF else mortal_position(mortal_id)
	if origin == Vector2.INF:
		return
	_modes[mortal_id] = "flying"
	_slippers[mortal_id] = {
		"position": origin + direction * 18.0,
		"direction": direction,
		"travelled": 0.0,
		"state": "flying",
	}
	if mortal_id == _my_id:
		_local_mode = "flying"
	_maybe_seek(mortal_id)


func _move_tala(delta: float) -> void:
	if tala == null:
		return
	if _seeking:
		_tick_seek(delta)
		return
	# With a route drawn for her she walks that route, turning round at both of
	# its ends. Without one (an arena that has no TalaPath) she still paces the
	# authored min/max band, as before.
	if _tala_knots.size() >= 2 and _tala_length > 0.0:
		_tala_distance += _tala_dir * tala_speed * delta
		if _tala_distance >= _tala_length:
			_tala_distance = _tala_length
			_tala_dir = -1.0
		elif _tala_distance <= 0.0:
			_tala_distance = 0.0
			_tala_dir = 1.0
		_place_tala()
		return
	tala.position.y += _tala_dir * tala_speed * delta
	if tala.position.y >= tala_max_y:
		tala.position.y = tala_max_y
		_tala_dir = -1.0
	elif tala.position.y <= tala_min_y:
		tala.position.y = tala_min_y
		_tala_dir = 1.0


# --- THE GUARD WHO CUTS YOU OFF ----------------------------------------------
# Every so often she hurries along her own route to meet a slipper in the air.
# The host rolls seek_chance the moment the slipper is thrown; she then walks to
# the spot of her beat nearest where its path would reach her and plants herself
# there - she never steps off the TalaPath, she anticipates the throw from it.
# The catch itself is the one that already existed (_move_slippers): she has
# simply put her beat in the slipper's way. One intercept at a time, with a
# cooldown, and she carries on along the route from wherever that left her.

func _maybe_seek(mortal_id: int) -> void:
	if _seeking or _seek_cd > 0.0 or tala == null:
		return
	if str(_slippers.get(mortal_id, {}).get("state", "")) != "flying":
		return
	if _rng.randf() >= seek_chance:
		return
	_seeking = true
	_seek_owner = mortal_id
	_seek_time = seek_time
	_seek_point = _intercept_point(_slippers[mortal_id])
	_seek_distance = _nearest_route_distance(_seek_point)
	if mortal_id == _my_id:
		_log("Tala moves to cut off your slipper!", Color(1.0, 0.65, 0.45))


# One frame of an intercept: keep re-aiming at where the slipper would be when
# she could reach it, walk to the spot of her OWN route nearest that point, and
# plant herself there - the path is blocked either way. The seek ends the moment
# that slipper stops flying or the clock runs out.
func _tick_seek(delta: float) -> void:
	_seek_time -= delta
	var slipper: Dictionary = _slippers.get(_seek_owner, {})
	if str(slipper.get("state", "")) != "flying" or _seek_time <= 0.0:
		_end_seek()
		return
	_seek_point = _intercept_point(slipper)
	if _tala_knots.size() < 2:
		_walk_seek_direct(delta)  # no route drawn: there is no beat to stay on
		return
	_seek_distance = _nearest_route_distance(_seek_point)
	_walk_route_toward(_seek_distance, seek_speed, delta)


# The intercept with no route to walk: head straight for the meeting point.
func _walk_seek_direct(delta: float) -> void:
	var toward := _seek_point - tala.global_position
	if toward.length() > 3.0:
		tala.global_position += toward.normalized() * maxf(1.0, seek_speed) * delta


# One step along her own route towards `wanted` (a distance along it), hurrying
# at `speed` and turning to face the way she walks - the same walk the patrol
# does, only faster, so an intercept never steps off the path.
func _walk_route_toward(wanted: float, speed: float, delta: float) -> void:
	var gap := clampf(wanted, 0.0, _tala_length) - _tala_distance
	if absf(gap) < 3.0:
		return  # planted: her beat is in the slipper's way from here
	var step := maxf(1.0, speed) * delta
	_tala_dir = 1.0 if gap > 0.0 else -1.0
	_tala_distance = clampf(_tala_distance + step * _tala_dir, 0.0, _tala_length)
	_place_tala()


# The point of her route nearest to `point`, as a distance along it.
func _nearest_route_distance(point: Vector2) -> float:
	if _tala_knots.size() < 2:
		return _tala_distance
	var travelled := 0.0
	var best_distance := _tala_distance
	var best_gap := INF
	for index in range(1, _tala_knots.size()):
		var from := _tala_knots[index - 1]
		var segment := _tala_knots[index] - from
		var length_squared := segment.length_squared()
		var length := sqrt(length_squared)
		var along := 0.0 if length_squared <= 0.0001 else clampf((point - from).dot(segment) / length_squared, 0.0, 1.0)
		var gap := point.distance_to(from + segment * along)
		if gap < best_gap:
			best_gap = gap
			best_distance = travelled + length * along
		travelled += length
	return clampf(best_distance, 0.0, _tala_length)


# Where the slipper will be when she could be standing there. It flies at
# throw_speed along a straight line and she walks at seek_speed, so this solves
# |slipper + velocity * wait - tala| = seek_speed * wait for the first moment
# she can plant herself on its path. When no such moment exists (she cannot get
# there in time) she aims straight at the slipper instead - walking at it is
# still walking into its direction.
func _intercept_point(slipper: Dictionary) -> Vector2:
	var position: Vector2 = slipper.get("position", tala.global_position)
	var velocity: Vector2 = slipper.get("direction", Vector2.ZERO) * throw_speed
	var offset := position - tala.global_position
	var a := velocity.length_squared() - seek_speed * seek_speed
	var b := 2.0 * velocity.dot(offset)
	var c := offset.length_squared()
	var wait := 0.0
	if absf(a) > 0.001:
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var root := sqrt(discriminant)
			var first := (-b - root) / (2.0 * a)
			var second := (-b + root) / (2.0 * a)
			wait = first if first > 0.0 else (second if second > 0.0 else 0.0)
	return position + velocity * wait


func _end_seek() -> void:
	if not _seeking:
		return
	_seeking = false
	_seek_owner = -1
	_seek_point = Vector2.INF
	_seek_cd = seek_cooldown
	# She never left the route, so `_tala_distance` already says where she
	# stands: the patrol simply carries on from there.


func _move_slippers(delta: float) -> void:
	for owner in _slippers.keys().duplicate():
		var slipper: Dictionary = _slippers[owner]
		if slipper.get("state", "") != "flying":
			continue
		var start: Vector2 = slipper["position"]
		var direction: Vector2 = slipper["direction"]
		var finish := start + direction * throw_speed * delta
		var nearest_t := INF
		var result := ""
		var target_can := -1
		for index in range(_cans.size()):
			if not is_can_active(index):
				continue
			var hit_t := _segment_circle(start, finish, _cans[index].global_position, can_radius)
			if hit_t < nearest_t:
				nearest_t = hit_t
				result = "can"
				target_can = index
		if tala != null:
			var tala_t := _segment_circle(start, finish, tala.global_position, tala_radius)
			if tala_t < nearest_t:
				nearest_t = tala_t
				result = "tala"
		var distance := start.distance_to(finish)
		var travelled := float(slipper.get("travelled", 0.0))
		if not _field.has_point(finish):
			var boundary_t := _rect_exit_t(start, finish, _field)
			if boundary_t < nearest_t:
				nearest_t = boundary_t
				result = "ground"
		if travelled + distance >= slipper_range:
			var range_t := clampf((slipper_range - travelled) / maxf(0.001, distance), 0.0, 1.0)
			if range_t < nearest_t:
				nearest_t = range_t
				result = "ground"
		if result == "":
			slipper["position"] = finish
			slipper["travelled"] = travelled + distance
			_slippers[owner] = slipper
			continue
		var landing := start.lerp(finish, clampf(nearest_t, 0.0, 1.0))
		if result == "can":
			_resolve_can(int(owner), target_can)
			_slippers.erase(owner)
		elif result == "tala":
			_resolve_tala_catch(int(owner))
		else:
			_drop_slipper(int(owner), landing)


func _resolve_tala_catch(owner: int) -> void:
	# Her catch lands with weight: the thrower's screen answers with the shared
	# shake and wash. The host owns the count, so the thrower shakes on their
	# own screen whichever peer hosts the round: a direct kick here covers the
	# host's own screen, the mirrored count covers a client's (arena_read_tick).
	if tala != null:
		announce_hit(-1, tala.global_position, Vector2.RIGHT, 0.0)  # the slipper lands on her
		_drop_slipper(owner, tala.global_position + Vector2(28.0, 18.0))
	lose_favor(tala_penalty, "Tala caught your slipper", owner)
	_tala_hits += 1
	_tala_hit_owner = owner
	_seen_tala_hits = _tala_hits
	if owner == _my_id:
		_shake_tala_hit()


func _resolve_can(owner: int, can_index: int) -> void:
	if can_index < 0 or can_index >= _cans.size():
		return
	_can_repair[can_index] = can_repair_time
	announce_hit(-1, _cans[can_index].global_position, Vector2.RIGHT, 0.0)  # ...and on the can
	_refresh_can(can_index)
	bank_favor(can_favor, "knocking down a tin can", owner)
	_modes[owner] = "ready"
	if owner == _my_id:
		_local_mode = "ready"
	# A landed throw lands with weight: the thrower's screen answers with the
	# shared shake and a white flicker. The host owns the count, so the thrower
	# shakes on their own screen whichever peer hosts the round: a direct kick
	# here covers the host's own screen, the mirrored count covers a client's
	# (arena_read_tick).
	_can_hits += 1
	_can_hit_owner = owner
	_seen_can_hits = _can_hits
	if owner == _my_id:
		_shake_can_hit()
	_log("A tin can falls! +%d FAVOR" % can_favor, god.color)


func _drop_slipper(owner: int, position: Vector2) -> void:
	_slippers[owner] = {"position": position, "state": "dropped"}
	_modes[owner] = "retrieve"
	if owner == _my_id:
		_local_mode = "retrieve"
	_log("Retrieve your slipper, then return to the line.", Color(1.0, 0.65, 0.45))


func _check_pickups() -> void:
	for entry in mortal_entries():
		var owner := int(entry["id"])
		var mode := str(_modes.get(owner, "ready"))
		if mode == "retrieve" and _slippers.has(owner):
			var position: Vector2 = _slippers[owner]["position"]
			if (entry["pos"] as Vector2).distance_to(position) <= player.radius + 16.0:
				_slippers.erase(owner)
				_modes[owner] = "return"
				if owner == _my_id:
					_local_mode = "return"
		elif mode == "return" and (entry["pos"] as Vector2).x <= _shoot_x - player.radius:
			_modes[owner] = "ready"
			if owner == _my_id:
				_local_mode = "ready"


# TALA HERSELF: walking into her is no different from her catching your slipper -
# it costs tala_penalty FAVOR and shoves the mortal back the same way a Mayari
# clone does (MayariArena._on_clone_hit is the model). The host runs it
# (arena_rules_tick), the mercy seconds keep her from charging the same mortal
# twice in a row, and the shove reaches whichever screen simulates that mortal
# (knock_mortal splits the local / remote case).
func _check_tala_touch() -> void:
	if tala == null:
		return
	for entry in mortal_entries():
		var mortal_id := int(entry["id"])
		if is_mortal_invulnerable(mortal_id):
			continue
		var position: Vector2 = entry["pos"]
		if position.distance_to(tala.global_position) > tala_radius + player.radius:
			continue
		set_mortal_invuln(mortal_id, invuln_time)
		var lost := lose_favor(tala_penalty, "walking into Tala", mortal_id)
		# Her touch lands with weight: the shared shake answers on the victim's
		# screen - here for us, across the wire for a rival (the same `impact`
		# flag Mayari's clones raise). No light counter on top of it: the impact
		# already shook that screen, and a second kick would double it.
		knock_mortal(mortal_id, tala.global_position, 0.0, 0.0, true)
		if mortal_id != _my_id:
			if lost > 0:
				_log("%s ran into Tala  (-%d FAVOR)" % [mortal_label(mortal_id), lost], Color(1, 0.6, 0.5))
			continue
		if lost > 0:
			_log("You ran into Tala  (-%d FAVOR)" % lost, Color(1, 0.5, 0.45))
		else:
			_log("Tala caught you but your favor held", god.color)


func _repair_cans(delta: float) -> void:
	for index in _can_repair.keys():
		var left := maxf(0.0, float(_can_repair[index]) - delta)
		_can_repair[index] = left
		if left <= 0.0 and index < _cans.size():
			_refresh_can(index)


func _segment_circle(start: Vector2, finish: Vector2, center: Vector2, radius: float) -> float:
	if start.distance_squared_to(center) <= radius * radius:
		return 0.0
	var delta := finish - start
	var length_squared := delta.length_squared()
	if length_squared <= 0.0001:
		return 0.0 if start.distance_to(center) <= radius else INF
	var offset := start - center
	var b := 2.0 * offset.dot(delta)
	var c := offset.length_squared() - radius * radius
	var discriminant := b * b - 4.0 * length_squared * c
	if discriminant < 0.0:
		return INF
	var root := sqrt(discriminant)
	var first := (-b - root) / (2.0 * length_squared)
	if first >= 0.0 and first <= 1.0:
		return first
	var second := (-b + root) / (2.0 * length_squared)
	return second if second >= 0.0 and second <= 1.0 else INF


func _rect_exit_t(start: Vector2, finish: Vector2, bounds: Rect2) -> float:
	var direction := finish - start
	var t := INF
	if direction.x > 0.0 and finish.x > bounds.end.x:
		t = minf(t, (bounds.end.x - start.x) / direction.x)
	elif direction.x < 0.0 and finish.x < bounds.position.x:
		t = minf(t, (bounds.position.x - start.x) / direction.x)
	if direction.y > 0.0 and finish.y > bounds.end.y:
		t = minf(t, (bounds.end.y - start.y) / direction.y)
	elif direction.y < 0.0 and finish.y < bounds.position.y:
		t = minf(t, (bounds.position.y - start.y) / direction.y)
	return clampf(t, 0.0, 1.0)


func arena_tick_fields() -> Dictionary:
	var can_repairs: Dictionary = {}
	for index in range(_cans.size()):
		can_repairs[index] = float(_can_repair.get(index, 0.0))
	return {
		"tala_y": tala.global_position.y if tala != null else 0.0,
		"tala_distance": _tala_distance,
		"tala_direction": _tala_dir,
		# Where she stands while cutting a slipper off - the route alone cannot
		# say it, so every screen walks her to the very spot the host chose.
		"tala_seek": tala.global_position if _seeking else Vector2.INF,
		"slippers": _slippers.duplicate(true),
		"modes": _modes.duplicate(true),
		"can_repairs": can_repairs,
		# Who just got hit, so the thrower's / victim's own screen can answer with
		# the shared shake and wash (the counts are the host's).
		"can_hits": _can_hits,
		"can_hit_owner": _can_hit_owner,
		"tala_hits": _tala_hits,
		"tala_hit_owner": _tala_hit_owner,
	}


func arena_read_tick(state: Dictionary) -> void:
	# Tala is placed by how far along her route the host says she is, so every
	# screen walks the very path the designer drew - unless she is cutting a
	# slipper off, where the host's own word puts her instead.
	_tala_seek = state.get("tala_seek", Vector2.INF)
	_tala_dir = float(state.get("tala_direction", _tala_dir))
	if state.has("tala_distance"):
		_tala_distance = clampf(float(state.get("tala_distance", _tala_distance)), 0.0, _tala_length)
		_place_tala()
	elif tala != null:
		tala.position.y = float(state.get("tala_y", tala.position.y))
	_slippers = state.get("slippers", {}).duplicate(true)
	_modes = state.get("modes", {}).duplicate(true)
	_can_repair = state.get("can_repairs", {}).duplicate(true)
	_local_mode = str(_modes.get(_my_id, _local_mode))
	for index in range(_cans.size()):
		_refresh_can(index)
	# A new hit meant for THIS screen lands with weight: the shared shake and a
	# wash answer it - white for a landed throw, red for her touch. Runs on
	# every peer (host and client alike), because the counts are the host's.
	_can_hits = int(state.get("can_hits", _can_hits))
	if _can_hits > _seen_can_hits:
		_seen_can_hits = _can_hits
		if int(state.get("can_hit_owner", -1)) == _my_id:
			_shake_can_hit()
	_tala_hits = int(state.get("tala_hits", _tala_hits))
	if _tala_hits > _seen_tala_hits:
		_seen_tala_hits = _tala_hits
		if int(state.get("tala_hit_owner", -1)) == _my_id:
			_shake_tala_hit()
	_update_local_bounds()
	_render_slippers()


func _update_local_bounds() -> void:
	if player == null:
		return
	_local_mode = str(_modes.get(_my_id, _local_mode))
	if _local_mode == "retrieve" or _local_mode == "return":
		player.bounds = _field
	else:
		player.bounds = Rect2(_field.position, Vector2(maxf(1.0, _shoot_x - _field.position.x), _field.size.y))


# THE FEEL OF A HIT. A slipper that lands rings the field lightly under a faint
# white flicker - a can downed and Tala reached both kick the same small way.
# (Her touch on US already shakes through knock_mortal's `impact` flag; this
# covers hits OUR slipper lands, where there is no shove to carry it.)
func _shake_can_hit() -> void:
	_shake_screen(can_hit_shake_time, 0.45)
	_flash_screen(Color(1.0, 1.0, 1.0), 0.1)


func _shake_tala_hit() -> void:
	_shake_screen(tala_hit_shake_time, 0.55)
	_flash_screen(Color(1.0, 1.0, 1.0), 0.12)


func _render_slippers() -> void:
	if slippers_root == null:
		return
	# Owner keys arrive as ints from local throws and as strings off the wire
	# (JSON dictionaries only carry string keys): normalise them here so every
	# lookup below agrees and no slipper blinks out after a sync.
	var owners: Dictionary = {}
	for raw_owner in _slippers.keys():
		owners[int(str(raw_owner))] = _slippers[raw_owner]
	_slippers = owners
	for owner in _slippers.keys():
		var key := str(owner)
		var node: Node2D = _slipper_nodes.get(key)
		if not is_instance_valid(node):
			node = SLIPPER_SCENE.instantiate()
			slippers_root.add_child(node)
			_slipper_nodes[key] = node
		var slipper: Dictionary = _slippers[owner]
		node.global_position = slipper["position"]
		_set_slipper_anim(node, int(owner), str(slipper.get("state", "dropped")))
	for key in _slipper_nodes.keys().duplicate():
		if not _slippers.has(int(key)):
			_slipper_nodes[key].queue_free()
			_slipper_nodes.erase(key)


# A slipper wears your scene's clips: `toss` while it flies (spun along its
# flight), `grounded` once it lands. Type 1 is your own, type 2 a rival's.
func _set_slipper_anim(node: Node2D, owner: int, state: String) -> void:
	var sprite: AnimatedSprite2D = node.get_node_or_null("AnimatedSprite2D")
	if sprite == null or sprite.sprite_frames == null:
		return
	var variant := 1 if owner == _my_id else 2
	var suffix := SLIPPER_TOSS_SUFFIX if state == "flying" else SLIPPER_GROUNDED_SUFFIX
	var clip := StringName("slipper-type-%d-%s" % [variant, suffix])
	if sprite.sprite_frames.has_animation(clip):
		if sprite.animation != clip or not sprite.is_playing():
			sprite.play(clip)
	if state == "flying":
		var direction: Vector2 = _slippers.get(owner, {}).get("direction", Vector2.RIGHT)
		node.rotation = direction.angle()
	else:
		node.rotation = 0.0


func _refresh_status() -> void:
	if status_label == null:
		return
	match _local_mode:
		"ready":
			status_label.text = "THROW FROM THE LINE"
		"flying":
			status_label.text = "SLIPPER IN FLIGHT"
		"retrieve":
			status_label.text = "FETCH YOUR SLIPPER"
		"return":
			status_label.text = "RETURN TO THE LINE"
	if hint_label != null:
		hint_label.text = "LEFT CLICK - THROW    WASD / ARROWS - MOVE    E / Q - FAVORS"


func nearby_movement_favors_enabled() -> bool:
	return true
