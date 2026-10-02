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
@export var tala_penalty := 100

@onready var tala: Sprite2D = get_node_or_null("ArenaField/Tala")
@onready var cans_root: Node2D = get_node_or_null("ArenaField/Cans")
@onready var barrier: Line2D = get_node_or_null("ArenaField/Barrier")
@onready var slippers_root: Node2D = get_node_or_null("Slippers")
@onready var status_label: Label = get_node_or_null("TalaHud/Status")
@onready var hint_label: Label = get_node_or_null("TalaHud/Hint")
@onready var slipper_texture: Texture2D = preload("res://Assets/Gods/Tala/Slipper-Vertical.png")

var _cans: Array[Sprite2D] = []
var _slippers: Dictionary = {}
var _slipper_nodes: Dictionary = {}
var _modes: Dictionary = {}
var _can_repair: Dictionary = {}
var _shoot_x := 465.0
var _tala_dir := 1.0
var _local_mode := "ready"


func _ready() -> void:
	super._ready()
	for id in rules.mortals.keys():
		_modes.get_or_add(int(id), "ready")
	_update_local_bounds()
	_refresh_status()


func _connect_network() -> void:
	super._connect_network()
	if _net != null and _authority and _net.has_signal("tala_throw_requested"):
		_net.tala_throw_requested.connect(_on_throw_requested)


func collect_units() -> void:
	_cans.clear()
	if cans_root != null:
		for child in cans_root.get_children():
			if child is Sprite2D:
				_cans.append(child)
	if barrier != null and barrier.points.size() > 0:
		_shoot_x = barrier.to_global(barrier.points[0]).x
	for index in range(_cans.size()):
		_can_repair.get_or_add(index, 0.0)
	if _authority and rules != null:
		for id in rules.mortals.keys():
			_modes.get_or_add(int(id), "ready")


func arena_rules_tick(delta: float) -> void:
	if not _authority:
		return
	_move_tala(delta)
	_move_slippers(delta)
	_check_pickups()
	_repair_cans(delta)


func arena_round_reset() -> void:
	_slippers.clear()
	_modes.clear()
	_can_repair.clear()
	_tala_dir = 1.0
	if tala != null:
		tala.position.y = (tala_min_y + tala_max_y) * 0.5
	for id in rules.mortals.keys():
		_modes[int(id)] = "ready"
	for can in _cans:
		can.visible = true
	for slipper in _slipper_nodes.values():
		if is_instance_valid(slipper):
			slipper.queue_free()
	_slipper_nodes.clear()
	_local_mode = "ready"
	_update_local_bounds()


func _process(delta: float) -> void:
	super._process(delta)
	_update_local_bounds()
	_render_slippers()
	_refresh_status()


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _phase != Phase.PLAYING or player.locked or dialogue.is_active() or due_menu.is_open():
		return
	_try_throw(event.position)
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


func _move_tala(delta: float) -> void:
	if tala == null:
		return
	tala.position.y += _tala_dir * tala_speed * delta
	if tala.position.y >= tala_max_y:
		tala.position.y = tala_max_y
		_tala_dir = -1.0
	elif tala.position.y <= tala_min_y:
		tala.position.y = tala_min_y
		_tala_dir = 1.0


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
			if not _cans[index].visible or float(_can_repair.get(index, 0.0)) > 0.0:
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
			lose_favor(tala_penalty, "Tala caught your slipper", int(owner))
			_drop_slipper(int(owner), tala.global_position + Vector2(28.0, 18.0))
		else:
			_drop_slipper(int(owner), landing)


func _resolve_can(owner: int, can_index: int) -> void:
	if can_index < 0 or can_index >= _cans.size():
		return
	_cans[can_index].visible = false
	_can_repair[can_index] = can_repair_time
	bank_favor(can_favor, "knocking down a tin can", owner)
	_modes[owner] = "ready"
	if owner == _my_id:
		_local_mode = "ready"
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


func _repair_cans(delta: float) -> void:
	for index in _can_repair.keys():
		var left := maxf(0.0, float(_can_repair[index]) - delta)
		_can_repair[index] = left
		if left <= 0.0 and index < _cans.size():
			_cans[index].visible = true


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
		"tala_y": tala.position.y if tala != null else 0.0,
		"tala_direction": _tala_dir,
		"slippers": _slippers.duplicate(true),
		"modes": _modes.duplicate(true),
		"can_repairs": can_repairs,
	}


func arena_read_tick(state: Dictionary) -> void:
	if tala != null:
		tala.position.y = float(state.get("tala_y", tala.position.y))
	_tala_dir = float(state.get("tala_direction", _tala_dir))
	_slippers = state.get("slippers", {}).duplicate(true)
	_modes = state.get("modes", {}).duplicate(true)
	_can_repair = state.get("can_repairs", {}).duplicate(true)
	_local_mode = str(_modes.get(_my_id, _local_mode))
	for index in range(_cans.size()):
		_cans[index].visible = float(_can_repair.get(index, 0.0)) <= 0.0
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


func _render_slippers() -> void:
	if slippers_root == null:
		return
	for owner in _slippers.keys():
		var key := str(owner)
		var node: Sprite2D = _slipper_nodes.get(key)
		if not is_instance_valid(node):
			node = Sprite2D.new()
			node.texture = slipper_texture
			node.scale = Vector2(0.34, 0.34)
			slippers_root.add_child(node)
			_slipper_nodes[key] = node
		var slipper: Dictionary = _slippers[owner]
		node.global_position = slipper["position"]
		var direction: Vector2 = slipper.get("direction", Vector2.RIGHT)
		node.rotation = direction.angle()
	for key in _slipper_nodes.keys().duplicate():
		if not _slippers.has(int(key)):
			_slipper_nodes[key].queue_free()
			_slipper_nodes.erase(key)


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
