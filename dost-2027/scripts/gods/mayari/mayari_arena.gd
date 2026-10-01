class_name MayariArena
extends Arena

# MAYARI - patintero. (scripts/gods/mayari + scenes/gods/mayari)
#
# EVERYTHING SHARED LIVES IN THE BASE: the round clock, the countdown, the
# mortal, the intro / closing dialogues, the God's Due menu, the FAVOR popups
# and all the network plumbing come from Arena (scripts/gods/common/arena.gd)
# and scenes/gods/common/Arena.tscn, the scene this arena's scene inherits.
# This file is only what makes the game Mayari's:
#
#   * the four goals are the favor zones. Only the ONE Mayari is lighting burns
#     - yellow - and only that one pays: every other zone draws nothing at all
#     and is invisible on screen.
#   * the two clones (one horizontal, one vertical, authored in
#     MayariArena.tscn) walk the Line2D path drawn on each of them and never
#     leave it.
#   * every so often a clone stops patrolling and hunts the nearest mortal: it
#     still walks its own line, it just walks it towards whoever is closest.
#   * a clone touching a mortal costs that mortal FAVOR and knocks it back.
#   * standing in the lit zone banks FAVOR until the clock runs out.
# That is the whole game. Everything else comes later, in due time.
#
# The arena owns no art: MayariArena.tscn holds the backdrop, the field, its
# border and the patintero lines, the four favor zones (MayariGoal.tscn), the
# two clones (MayariClone.tscn) and the mortal's spawn. This script only runs
# the rules - it never draws and never re-lays-out the scene, so the editor
# layout is the played one.

@export_category("Patintero")
@export var favor_rate := 82               # FAVOR banked per second in the lit zone
@export var clone_penalty := 50            # FAVOR lost when a clone touches a mortal
@export_range(0, 3, 1) var starting_zone := 3  # the zone Mayari lights first
@export var goal_switch_interval := 12.0   # seconds before the light moves on

@export_category("Attack")
@export var shock_radius := 130.0        # how far the attack's shockwave reaches
@export var shock_expand_time := 0.45    # seconds the wave takes to reach full size
@export var shock_cooldown := 1.2        # seconds between two attacks
@export var shock_stun := 0.22           # control lost by a mortal the wave catches
@export var shock_force := 320.0         # how hard the wave shoves them away

# The round clock (1:30), the countdown, the mercy seconds, the popup colours and
# every network rate are NOT declared here: they come from the shared arena base
# (Arena.trial_time and friends), the one place they are edited.

const SHOCK_SCENE := preload("res://scenes/gods/mayari/Shockwave.tscn")

@onready var zones_root: Node2D = $Zones
@onready var clones_root: Node2D = $Clones
@onready var shocks_root: Node2D = $Shocks
@onready var attack_bar: ProgressBar = get_node_or_null("AttackHud/Bar")
@onready var attack_label: Label = get_node_or_null("AttackHud/Label")
@onready var attack_icon: TextureRect = get_node_or_null("AttackHud/Icon")

var _zones: Array = []
var _clones: Array = []
var _zone_pending: Dictionary = {}    # mortal id -> fractional FAVOR not banked
var _active_goal_index := 3
var _goal_switch_timer := 0.0
var _shock_cd := 0.0
var _shocks: Array = []               # the waves the host is growing


# --- ARENA HOOKS (see scripts/gods/common/arena.gd) --------------------------

func collect_units() -> void:
	# Both lists are built on EVERY peer: the zones and the clones are the
	# authored scene nodes, so each screen already has the same boxes and the
	# same two Mayaris. Only the lit one and the walked positions travel.
	_collect_zones()
	_collect_clones()
	if _authority:
		_light_zone(starting_zone)


func arena_rules_tick(delta: float) -> void:
	# The host's frame of patintero: the light moves on, the clones walk, the lit
	# zone pays and Mayari costs FAVOR to whoever she touches.
	_goal_switch_timer -= delta
	if _goal_switch_timer <= 0.0:
		_advance_active_goal()
	# Where the mortals are, so a clone can decide to hunt the nearest one.
	_feed_clones()
	_check_goals(delta)
	_check_clones()
	_tick_shocks(delta)


func arena_round_reset() -> void:
	# Both Mayaris back to the start of their paths, so every round begins the
	# same way.
	for clone in _clones:
		if is_instance_valid(clone) and clone.self_moving:
			clone.restart()
	# No wave carries into the new round, and the attack is ready again.
	_shocks.clear()
	_shock_cd = 0.0
	if shocks_root != null:
		for wave in shocks_root.get_children():
			wave.queue_free()


func arena_layout_fields() -> Dictionary:
	return {"active_goal": _active_goal_index, "zones": _zone_definitions()}


func arena_read_layout(layout: Dictionary) -> void:
	var definitions: Array = layout.get("zones", [])
	for index in range(mini(definitions.size(), _zones.size())):
		var definition: Dictionary = definitions[index]
		var lit := bool(definition.get("lit", definition.get("favor_enabled", false)))
		if lit:
			_active_goal_index = index
		_zones[index].set_active(lit)
	if definitions.is_empty():
		# No zone list on the wire (an older host, or a hand-made state): fall
		# back to the index of the lit zone.
		_light_zone(int(layout.get("active_goal", _active_goal_index)))


func arena_tick_fields() -> Dictionary:
	var clones: Array = []
	var hunts: Array = []
	for clone in _clones:
		if is_instance_valid(clone):
			clones.append(clone.global_position)
			hunts.append(clone.is_hunting())
	return {"clones": clones, "hunts": hunts}


func arena_read_tick(state: Dictionary) -> void:
	# The clones are the authored ones on every peer: a client only mirrors the
	# positions the host sends, it never walks them itself.
	var clone_positions: Array = state.get("clones", [])
	var hunts: Array = state.get("hunts", [])
	for index in range(mini(clone_positions.size(), _clones.size())):
		var clone = _clones[index]
		if not is_instance_valid(clone):
			continue
		clone.sync_position(clone_positions[index])
		if index < hunts.size():
			clone.set_hunting(bool(hunts[index]))


# --- ZONES -------------------------------------------------------------------

func _collect_zones() -> void:
	# The four goals are authored scene nodes and they are only ever lit: their
	# place and their box size come from the scene, so the boxes drawn in the
	# editor are the boxes the mortals hold. Started dark - whoever is
	# authoritative lights one in _light_zone().
	_zones.clear()
	for node in zones_root.get_children():
		var zone: MayariGoal = node
		zone.sync_authored_size()
		zone.rate = favor_rate
		zone.set_active(false)
		_zones.append(zone)
	_goal_switch_timer = goal_switch_interval


# Exactly one zone burns at a time: Mayari lights one and every other zone goes
# dark - invisible and paying nothing.
func _light_zone(index: int) -> void:
	if _zones.is_empty():
		return
	_active_goal_index = clampi(index, 0, _zones.size() - 1)
	for i in range(_zones.size()):
		_zones[i].set_active(i == _active_goal_index)


# The one thing about the zones that is NOT in the scene is which one Mayari is
# lighting, so that single bit is all that travels. Local coordinates: every peer
# owns the same authored scene, so the same child index sits at the same spot on
# every screen and the same box has the same size.
func _zone_definitions() -> Array:
	var out: Array = []
	for zone in _zones:
		if is_instance_valid(zone):
			out.append({"lit": zone.favor_enabled})
	return out


# Mayari moves her light from corner to corner: exactly one goal pays at a time.
func _advance_active_goal() -> void:
	if _zones.is_empty():
		return
	_light_zone((_active_goal_index + 1) % _zones.size())
	_goal_switch_timer = goal_switch_interval
	_log("Mayari's light moves to the %s" % str(_zones[_active_goal_index].zone_label), god.color)
	_publish_layout()


# --- CLONES ------------------------------------------------------------------

func _collect_clones() -> void:
	# Exactly TWO Mayaris, both authored in the scene: one horizontal, one
	# vertical. Each one walks the Line2D path drawn on it (MayariClone.gd), so
	# there is nothing to lay out here - only the colour the clones burn in and
	# which side is allowed to move them.
	_clones.clear()
	for node in clones_root.get_children():
		var clone: MayariClone = node
		clone.color = god.color
		clone.set_moving(_authority)
		_clones.append(clone)
	if _clones.size() != 2:
		push_warning("MayariArena: the arena wants exactly 2 authored clones, found %d" % _clones.size())


# Where every mortal stands - a clone that is allowed to walk uses it to hunt
# the nearest one (MayariClone.gd). Only the host feeds it: a client's clones
# are driven by the positions the host sends.
func _feed_clones() -> void:
	var mortals := PackedVector2Array()
	for entry in mortal_entries():
		mortals.append(entry["pos"])
	for clone in _clones:
		if is_instance_valid(clone):
			clone.set_targets(mortals)


# --- SCORING -----------------------------------------------------------------

func _check_goals(delta: float) -> void:
	# Only the lit corner pays; holding it banks FAVOR over time.
	for zone in _zones:
		if is_instance_valid(zone):
			zone.held = false
	for entry in mortal_entries():
		var mortal_id := int(entry["id"])
		var position: Vector2 = entry["pos"]
		var best: MayariGoal = null
		for zone in _zones:
			if not is_instance_valid(zone):
				continue
			if not zone.favor_enabled or not zone.contains(position):
				continue
			zone.held = true
			if best == null or float(zone.rate) > float(best.rate):
				best = zone
		if best == null:
			continue
		# FAVOR is banked one whole unit at a time (bank_favor keeps the
		# fraction), so the popup and the HUD count in whole FAVOR.
		var pending := float(_zone_pending.get(mortal_id, 0.0)) + float(best.rate) * delta
		while pending >= 1.0:
			pending -= 1.0
			bank_favor(best.favor_amount, "holding the %s" % str(best.zone_label), mortal_id)
		_zone_pending[mortal_id] = pending


func _check_clones() -> void:
	for entry in mortal_entries():
		var mortal_id := int(entry["id"])
		if is_mortal_invulnerable(mortal_id):
			continue
		var position: Vector2 = entry["pos"]
		for clone in _clones:
			if not is_instance_valid(clone):
				continue
			if clone.hits(position, player.radius):
				_on_clone_hit(clone, mortal_id)
				break


func _on_clone_hit(clone: MayariClone, mortal_id: int) -> void:
	set_mortal_invuln(mortal_id, invuln_time)
	var lost := lose_favor(clone_penalty, "Mayari's clone", mortal_id)
	# Shove the mortal away from the clone it ran into - on whichever screen
	# simulates that mortal (the base does the local / remote split).
	knock_mortal(mortal_id, clone.global_position)
	if mortal_id != _my_id:
		if lost > 0:
			_log("%s was caught by a clone  (-%d FAVOR)" % [mortal_label(mortal_id), lost], Color(1, 0.6, 0.5))
		return
	if lost > 0:
		_log("Mayari's clone caught you  (-%d FAVOR)" % lost, Color(1, 0.5, 0.45))
	else:
		_show_banner("FAVOR SHIELDED", god.color, 1.2)
		_log("A clone caught you but your favor held", god.color)


# --- ATTACK: THE SHOCKWAVE ---------------------------------------------------
# The mortal's attack (the `attack` action - LEFT MOUSE) throws a small shockwave
# out around itself. It starts really small and grows to its full size and area
# over shock_expand_time, shoving every OTHER mortal it reaches a little way away
# from the caster. It cannot be used again for shock_cooldown seconds.
#
# The wave is each player's own to start, but the shove it deals is the host's to
# decide: a client asks the host (request_arena_shock), the host grows the real
# area and reports the hit to whoever owns the mortal it caught, and the wave
# itself is drawn on every screen.

func _process(delta: float) -> void:
	super._process(delta)
	_tick_attack_ui(delta)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _phase != Phase.PLAYING or player.locked or dialogue.is_active() or due_menu.is_open():
			return
		_try_shockwave()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _try_shockwave() -> void:
	# A dialogue, the God's Due menu or the countdown all keep the mortal still:
	# the attack is the arena's during PLAYING only.
	if _phase != Phase.PLAYING or player.locked:
		return
	if due_menu != null and due_menu.is_open():
		return
	if _shock_cd > 0.0:
		_log("Shockwave recharging  (%.1fs)" % _shock_cd, god.color)
		return
	_shock_cd = shock_cooldown
	var origin := player.global_position
	var wave := _spawn_shockwave(origin)
	if _authority:
		_start_shock(origin, _my_id, wave)
		if _networked and _net != null:
			_net.send_arena_shock(_my_id, origin)
	elif _net != null and _net.has_multiplayer_peer():
		_net.rpc_id(1, "request_arena_shock", origin)


# Shove every mortal the growing ring has reached, and stop once it is full.
func _tick_shocks(delta: float) -> void:
	if _shocks.is_empty():
		return
	var alive: Array = []
	for shock in _shocks:
		var wave: MayariShockwave = shock.get("wave")
		var radius := wave.advance(delta) if is_instance_valid(wave) else float(shock["radius"])
		shock["radius"] = radius
		for entry in mortal_entries():
			var mortal_id := int(entry["id"])
			if mortal_id == int(shock["caster"]) or shock["hit"].has(mortal_id):
				continue
			var contact_radius := maxf(0.0, (entry["pos"] as Vector2).distance_to(shock["origin"] as Vector2) - player.radius)
			if contact_radius <= radius:
				shock["hit"][mortal_id] = true
				knock_mortal(mortal_id, shock["origin"], shock_stun, shock_force)
		if is_instance_valid(wave) and not wave.is_finished():
			alive.append(shock)
	_shocks = alive


# The host's copy of a wave: it grows the real area the attack covers.
func _start_shock(origin: Vector2, caster_id: int, wave: MayariShockwave) -> void:
	wave.set_manual_animation(true)
	_shocks.append({"origin": origin, "radius": wave.reach(), "caster": caster_id, "hit": {}, "wave": wave})


# The wave every screen draws. It uses the same size and timing as the rules.
func _spawn_shockwave(origin: Vector2) -> MayariShockwave:
	if shocks_root == null:
		return null
	var wave: MayariShockwave = SHOCK_SCENE.instantiate()
	shocks_root.add_child(wave)
	wave.global_position = origin
	wave.expand_time = shock_expand_time
	wave.max_scale = shock_radius / maxf(0.01, wave.base_radius)
	return wave


func _tick_attack_ui(delta: float) -> void:
	_shock_cd = maxf(0.0, _shock_cd - delta)
	if attack_bar != null:
		attack_bar.value = (1.0 - _shock_cd / maxf(0.01, shock_cooldown)) * 100.0
		attack_bar.modulate = Color(1, 1, 1, 1) if _shock_cd <= 0.0 else Color(1, 1, 1, 0.5)
	if attack_label != null:
		attack_label.text = "ATTACK  READY" if _shock_cd <= 0.0 else "ATTACK  %.1fs" % _shock_cd
	if attack_icon != null:
		attack_icon.modulate = Color(1, 1, 1, 1) if _shock_cd <= 0.0 else Color(1, 1, 1, 0.45)


# A client attacked: the host grows the real wave here and shares it.
func _on_arena_shock_requested(caster_id: int, origin: Vector2) -> void:
	var wave := _spawn_shockwave(origin)
	if wave == null:
		return
	_start_shock(origin, caster_id, wave)
	if _net != null:
		_net.send_arena_shock(caster_id, origin)


func _on_arena_shock_received(caster_id: int, origin: Vector2) -> void:
	if caster_id == _my_id:
		return
	_spawn_shockwave(origin)


# The shared plumbing is the base's; the shock signal is ours.
func _connect_network() -> void:
	super._connect_network()
	if _net == null:
		return
	if _net.has_signal("arena_shock_received"):
		_net.connect("arena_shock_received", _on_arena_shock_received)
	if _authority and _net.has_signal("arena_shock_requested"):
		_net.connect("arena_shock_requested", _on_arena_shock_requested)
