class_name LuksongLubidArena
extends Arena

# ANITUN TABU - Luksong Lubid. (scripts/gods/anitun_tabu + scenes/gods/anitun_tabu)
#
# EVERYTHING SHARED LIVES IN THE BASE (scripts/gods/common/arena.gd); this file
# is only what makes the game Tabu's.
#
# A PRIVATE PLAYGROUND
#   Like Apolaki's duel, every mortal plays this one on their own screen: the
#   rope and the gusts never cross the wire, and only FAVOR does (separate_players).
#   The gales of her E are still the host's shared clock (Arena._wind_time), so a
#   cast anywhere blows on every screen.
#
# THE LUBID
#   A rope strung across the field (scenes/gods/anitun_tabu/Lubid.tscn, held by
#   two wind fairies) sweeps right to left and pongs back at the walls. ATTACK
#   (LEFT MOUSE) hops the mortal over it - the sprite lifts and lands, only its
#   look (drop_offset), drawn over the rope while it is up (JUMP_Z), so the hop
#   never costs a step. Crossing the rope in the air pays jump_favor; crossing it
#   on the ground costs rope_penalty, shoves the mortal away from the rope and
#   starts the mercy seconds.
#
# THE GUSTS
#   Every few seconds a wind burst (WindBurst.tscn) swells on or around the mortal.
#   The middle of that swell is live: standing in it costs burst_penalty. A mortal
#   in the air is above it.
#
# THE BLITZ (the last blitz_time seconds)
#   Winds and Gales of Yesterday blow over the field by themselves (wind_forced),
#   dragging every walking mortal west - every mortal but the one holding The West
#   Wind. The rope pays more: blitz_jump_favor, or blitz_immune_jump_favor for a
#   mortal the gales cannot touch.

@export_category("Lubid")
@export var rope_speed := 230.0       # px/s the rope sweeps across the field
@export var rope_margin := 26.0       # how far from the walls it turns around
@export var jump_favor := 125         # clearing the rope in the air
@export var rope_penalty := 75        # the rope catching a mortal on the ground
@export var jump_time := 0.55         # seconds off the ground
@export var jump_height := 30.0       # px the figure lifts at the top of the hop

@export_category("Wind Bursts")
@export var burst_min_time := 5.0     # seconds between gusts, rolled fresh each time
@export var burst_max_time := 8.0
@export var burst_penalty := 150      # FAVOR lost standing in a live gust
@export var burst_spawn_radius := 60.0  # how far from the mortal one may swell
@export var burst_hit_radius := 48.0    # how close the mortal must stand to be caught

@export_category("Blitz")
@export var blitz_time := 30.0        # the last seconds: the gales blow on their own
@export var blitz_jump_favor := 200   # clearing the rope while they blow
@export var blitz_immune_jump_favor := 150  # ...for a mortal holding The West Wind

const LUBID_SCENE := preload("res://scenes/gods/anitun_tabu/Lubid.tscn")
const WIND_BURST_SCENE := preload("res://scenes/gods/anitun_tabu/WindBurst.tscn")
const JUMP_Z := 6  # the lubid draws at 5 (its 4 over the field's 1); a hop lifts over it

@onready var lubid: LuksongLubid = get_node_or_null("ArenaField/Lubid")
@onready var bursts_root: Node2D = get_node_or_null("ArenaField/WindBursts")
@onready var state_label: Label = get_node_or_null(BAND_STATE + "Status")

var _rng := RandomNumberGenerator.new()
var _rope_x := 0.0
var _rope_dir := -1.0
var _prev_rel := 0.0          # the rope's side of the mortal last frame
var _cross_guard := 0.0       # seconds before another crossing can count
var _jump_left := 0.0
var _burst_timer := 0.0
var _bursts: Array = []       # {node, hit}
var _blitz_announced := false
var _player_z := 0            # the player's authored draw order, back to it on landing


func _ready() -> void:
	super._ready()
	_player_z = player.z_index
	_rng.randomize()
	if lubid == null and field_root != null:
		lubid = LUBID_SCENE.instantiate()
		lubid.name = "Lubid"
		field_root.add_child(lubid)


# --- ARENA HOOKS (see scripts/gods/common/arena.gd) --------------------------

# The mortals play this one alone: no rival is drawn and no position travels.
func separate_players() -> bool:
	return true


func shares_mortal_positions() -> bool:
	return false


# The Guidance reads "another mortal is nearby" - there is none on this field.
func nearby_movement_favors_enabled() -> bool:
	return false


# The hop: the gales (and every other ground effect) leave the mortal alone.
func mortal_airborne() -> bool:
	return _jump_left > 0.0


# The blitz blows the gales by itself, on every screen.
func wind_forced() -> bool:
	return _in_blitz()


func arena_round_reset() -> void:
	_jump_left = 0.0
	player.drop_offset = Vector2.ZERO
	player.z_index = _player_z
	_rope_dir = -1.0
	_rope_x = _field.end.x - rope_margin if _field.size != Vector2.ZERO else player.global_position.x + 200.0
	_prev_rel = _rope_x - player.global_position.x
	_cross_guard = 0.0
	_burst_timer = _roll_burst_time()
	_clear_bursts()
	_blitz_announced = false
	_place_rope()


func _process(delta: float) -> void:
	super._process(delta)
	_tick_jump(delta)
	if _phase == Phase.PLAYING:
		_tick_rope(delta)
		_tick_bursts(delta)
		_tick_blitz()
	_refresh_state_label()


# --- INPUT -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# The hop is a mouse button and is read in _input() below; this stays for the
	# base's keyboard shortcuts.
	super._unhandled_input(event)


func _input(event: InputEvent) -> void:
	if super._tap_panel_click(event):
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if _phase != Phase.PLAYING or player.locked or dialogue.is_active() or due_menu.is_open():
		return
	if not event.is_action_pressed("attack"):
		return
	_try_jump()
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _try_jump() -> void:
	if _jump_left > 0.0 or drop_active():
		return
	_jump_left = jump_time
	player.z_index = JUMP_Z  # up in the air, over the lubid


func _tick_jump(delta: float) -> void:
	if _jump_left <= 0.0:
		if player.drop_offset != Vector2.ZERO and not drop_active():
			player.drop_offset = Vector2.ZERO
		player.z_index = _player_z
		return
	_jump_left = maxf(0.0, _jump_left - delta)
	var up := 1.0 - _jump_left / maxf(0.001, jump_time)
	player.drop_offset = Vector2(0.0, -jump_height * sin(PI * clampf(up, 0.0, 1.0)))
	if _jump_left <= 0.0:
		player.drop_offset = Vector2.ZERO
		player.z_index = _player_z


# --- THE LUBID ---------------------------------------------------------------

func _tick_rope(delta: float) -> void:
	if lubid == null or _field.size == Vector2.ZERO:
		return
	var low := _field.position.x + rope_margin
	var high := _field.end.x - rope_margin
	_rope_x += _rope_dir * rope_speed * delta
	if _rope_x <= low:
		_rope_x = low
		_rope_dir = 1.0
	elif _rope_x >= high:
		_rope_x = high
		_rope_dir = -1.0
	_place_rope()
	_cross_guard = maxf(0.0, _cross_guard - delta)
	var rel := _rope_x - player.global_position.x
	if _prev_rel != 0.0 and (rel > 0.0) != (_prev_rel > 0.0) and _cross_guard <= 0.0:
		_cross_guard = 0.25
		_resolve_crossing()
	_prev_rel = rel


func _place_rope() -> void:
	if lubid == null or _field.size == Vector2.ZERO:
		return
	lubid.place(_rope_x, _field.position.y, _field.end.y)


func _resolve_crossing() -> void:
	if player.locked or is_mortal_invulnerable(_my_id):
		return
	if mortal_airborne():
		var paid := jump_favor
		if _in_blitz():
			paid = blitz_immune_jump_favor if _holds_west_wind() else blitz_jump_favor
		score_favor(paid, "Jumped the lubid")
		_log("Over the lubid: +%d FAVOR" % paid, Color(0.7, 1.0, 0.8))
		return
	score_favor(-rope_penalty, "the lubid")
	set_mortal_invuln(_my_id, invuln_time)
	knock_mortal(_my_id, Vector2(_rope_x, player.global_position.y))
	_shake_screen(impact_shake_time, 1.1)
	_flash_screen(Color(0.72, 0.86, 1.0), 0.32)
	_log("The lubid caught you: -%d FAVOR" % rope_penalty, Color(1.0, 0.5, 0.45))


func _holds_west_wind() -> bool:
	var mortal := rules.local()
	return mortal != null and mortal.has_favor(&"the_west_wind")


# --- THE GUSTS ---------------------------------------------------------------

func _tick_bursts(delta: float) -> void:
	_burst_timer -= delta
	if _burst_timer <= 0.0:
		_spawn_burst()
		_burst_timer = _roll_burst_time()
	for index in range(_bursts.size() - 1, -1, -1):
		var burst: Dictionary = _bursts[index]
		var node: WindBurst = burst.get("node")
		if node == null or not is_instance_valid(node):
			_bursts.remove_at(index)
			continue
		if not bool(burst.get("hit", false)) and node.is_hit_window():
			if not mortal_airborne() and not player.locked and not is_mortal_invulnerable(_my_id) \
					and player.global_position.distance_to(node.global_position) <= burst_hit_radius + player.radius:
				burst["hit"] = true
				_bursts[index] = burst
				_resolve_burst(node.global_position)
		if node.is_finished():
			node.queue_free()
			_bursts.remove_at(index)


func _roll_burst_time() -> float:
	return _rng.randf_range(burst_min_time, burst_max_time)


# One gust, ON or around the mortal: at the mortal's feet or up to
# burst_spawn_radius away, kept inside the field.
func _spawn_burst() -> void:
	if player == null:
		return
	var offset := Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU)) * _rng.randf_range(0.0, burst_spawn_radius)
	var spot := player.global_position + offset
	if _field.size != Vector2.ZERO:
		spot.x = clampf(spot.x, _field.position.x, _field.end.x)
		spot.y = clampf(spot.y, _field.position.y, _field.end.y)
	var burst: WindBurst = WIND_BURST_SCENE.instantiate()
	if bursts_root != null:
		bursts_root.add_child(burst)
	else:
		field_root.add_child(burst)
	burst.global_position = spot
	burst.play()
	_bursts.append({"node": burst, "hit": false})


func _resolve_burst(at: Vector2) -> void:
	score_favor(-burst_penalty, "a wind burst")
	set_mortal_invuln(_my_id, invuln_time)
	knock_mortal(_my_id, at)
	_shake_screen(impact_shake_time, 1.2)
	_flash_screen(Color(0.72, 0.86, 1.0), 0.36)
	_log("A wind burst caught you: -%d FAVOR" % burst_penalty, Color(1.0, 0.5, 0.45))


func _clear_bursts() -> void:
	for burst in _bursts:
		var node: Node = burst.get("node")
		if is_instance_valid(node):
			node.queue_free()
	_bursts.clear()
	if bursts_root != null:
		for child in bursts_root.get_children():
			child.queue_free()


# --- THE BLITZ ---------------------------------------------------------------

func _in_blitz() -> bool:
	return _phase == Phase.PLAYING and _trial_time <= blitz_time


func _tick_blitz() -> void:
	if not _in_blitz() or _blitz_announced:
		return
	_blitz_announced = true
	_show_banner("BLITZ - WINDS AND GALES!", UITokens.god_accent(god), 1.6)
	if _holds_west_wind():
		_log("Winds and Gales of Yesterday - you walk through them", UITokens.JADE)
	else:
		_log("Winds and Gales of Yesterday - the field pushes west", UITokens.EMBER)


func arena_local_effects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _in_blitz():
		return out
	if _holds_west_wind():
		out.append(effect(&"wind", "GALES - YOU WALK THROUGH THEM", null, UITokens.JADE, maxf(0.0, _trial_time), blitz_time, false))
	else:
		out.append(effect(&"wind", "GALES - PUSHED WEST", null, UITokens.EMBER, maxf(0.0, _trial_time), blitz_time, true))
	return out


func edge_targets() -> Array:
	return []


func _refresh_state_label() -> void:
	if state_label == null:
		return
	if _jump_left > 0.0:
		state_label.text = "AIRBORNE - CLEAR THE LUBID"
	elif _in_blitz():
		state_label.text = "BLITZ - THE GALES BLOW WEST"
	else:
		state_label.text = "JUMP THE LUBID"
