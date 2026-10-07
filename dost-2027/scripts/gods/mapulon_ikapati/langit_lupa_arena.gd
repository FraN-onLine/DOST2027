class_name LangitLupaArena
extends Arena

# MAPULON & IKAPATI - Langit Lupa. (scripts/gods/mapulon_ikapati +
# scenes/gods/mapulon_ikapati)
#
# EVERYTHING SHARED LIVES IN THE BASE (scripts/gods/common/arena.gd): the clock,
# the countdown, the mortal, the dialogues, the God's Due menu, the popups and the
# network plumbing. This file is only what makes the game the Harvest Pair's.
#
# A SHARED FIELD (like Mayari's): every mortal runs on the same field and sees the
# others. The host runs the rules from the positions it has; the clients mirror
# them through arena_tick_fields().
#
# THE TAYA (the one who is "it")
#   When the countdown ends the mortal with the most FAVOR becomes the Taya (ties:
#   random). The Taya passes on a touch (tag_radius) to any mortal on the Lupa -
#   the ground - and the new Taya cannot tag back for tagback_immunity seconds
#   (its marker blinks). Every second as Taya costs taya_drain FAVOR.
#
# LANGIT (the sky platforms)
#   langit_count() raised platforms, one mortal each, musical-chairs style: the
#   first runner to step on one claims it and cannot be tagged; anyone else on it
#   can. Every shift_interval seconds they crumble (after shift_warning seconds of
#   shaking) and reappear somewhere new, never within taya_clearance of the Taya.
#
# THE PAYOUT
#   When the clock runs out the pair pays by least time as Taya: payout_best for
#   first place down to payout_worst for last, evenly spread. Times within
#   tie_window seconds share the better payout.
#
# SOLO: two small bots take the simulated rivals' places - they flee the Taya and
# run for a free Langit, and chase when they are it.
#
# The art is drop-in (see Assets/Gods/MapulonIkapati/README.md): each file is used
# when it exists and the placeholder stays when it does not. Every number is an
# @export - tune it in the inspector. The dash itself lives in the base (Dash).

const ART_DIR := "res://Assets/Gods/MapulonIkapati/"
const SCREEN_SIZE := Vector2(1152.0, 648.0)  # the authored arena (see arena.gd)
const SAFE_COLOR := Color(0.7, 1, 0.8)
const TAYA_COLOR := Color(1, 0.5, 0.45)

@export_category("Langit Lupa")
@export var fixed_trial_time := 60.0     # the round length here (0 = the lobby's)
@export var tag_radius := 26.0           # how close the Taya must get to tag
@export var tagback_immunity := 1.0      # seconds a new Taya cannot tag
@export var shift_interval := 3.0        # seconds between two crumbles
@export var shift_warning := 0.75        # seconds of shaking before a crumble
@export var taya_clearance := 120.0      # no Langit lands this close to the Taya
@export var taya_drain := 10             # FAVOR per second as Taya
@export var payout_best := 1200          # least time as Taya
@export var payout_worst := 200          # most time as Taya
@export var tie_window := 0.25           # Taya times this close are a tie
@export var langit_size := Vector2(96.0, 60.0)
@export var langit_fade_in := 0.3        # seconds a new Langit takes to appear
@export var bot_speed := 175.0           # solo bots (the player walks 215)

@onready var langits_root: Node2D = get_node_or_null("ArenaField/Langits")
@onready var taya_marker: Node2D = get_node_or_null("TayaMarker")
@onready var taya_sprite: Sprite2D = get_node_or_null("TayaMarker/Sprite")
@onready var overseer: Sprite2D = get_node_or_null("ArenaField/Overseer")
@onready var background: Sprite2D = get_node_or_null("Background")
@onready var bots_root: Node2D = get_node_or_null("Bots")
@onready var taya_list: Label = get_node_or_null("LangitHud/TayaList")
@onready var status_label: Label = get_node_or_null("LangitHud/Status")
@onready var callout_label: Label = get_node_or_null("LangitHud/Callout")
@onready var hint_label: Label = get_node_or_null("LangitHud/Hint")

var _taya := -1
var _tagback := 0.0
var _taya_time: Dictionary = {}      # mortal id -> seconds spent as Taya
var _drain_pending: Dictionary = {}  # mortal id -> FAVOR owed, banked once a second
var _drain_tick := 1.0
var _langits: Array[Vector2] = []    # platform centres
var _claims: Dictionary = {}         # platform index -> mortal id standing safe on it
var _shift_timer := 0.0
var _shift_count := 0
var _shown_shift := -1               # the last layout drawn on this screen
var _fade := 1.0
var _bots: Dictionary = {}           # mortal id -> ArenaMortal (solo only)
var _callout_time := 0.0
var _paid := false


func _ready() -> void:
	if fixed_trial_time > 0.0:
		trial_time = fixed_trial_time
	super._ready()
	_spawn_bots()


# --- ARENA HOOKS (see scripts/gods/common/arena.gd) --------------------------

func collect_units() -> void:
	_apply_art()


func arena_round_reset() -> void:
	_taya = -1
	_tagback = 0.0
	_taya_time.clear()
	_drain_pending.clear()
	_drain_tick = 1.0
	_claims.clear()
	_paid = false
	_shift_timer = shift_interval
	if _authority:
		_place_langits()
	for id in _bots.keys():
		_bots[id].global_position = _bot_start(int(id))
		_mortal_positions[int(id)] = _bots[id].global_position


func arena_rules_tick(delta: float) -> void:
	_move_bots(delta)
	_tick_shift(delta)
	_update_claims()
	if _taya == -1 or rules.mortal(_taya) == null:
		_choose_taya(_highest_favor_ids())
	_tagback = maxf(0.0, _tagback - delta)
	if _taya != -1:
		_taya_time[_taya] = float(_taya_time.get(_taya, 0.0)) + delta
		_drain_pending[_taya] = float(_drain_pending.get(_taya, 0.0)) + float(taya_drain) * delta
		_check_tag()
	_drain_tick -= delta
	if _drain_tick <= 0.0:
		_drain_tick += 1.0
		_bank_drain()


func arena_tick_fields() -> Dictionary:
	return {
		"taya": _taya,
		"tagback": _tagback,
		"taya_time": _taya_time.duplicate(),
		"langits": _langits.duplicate(),
		"claims": _claims.duplicate(),
		"shift": _shift_count,
		"shift_left": _shift_timer,
	}


func arena_read_tick(state: Dictionary) -> void:
	var previous := _taya
	_taya = int(state.get("taya", _taya))
	_tagback = float(state.get("tagback", _tagback))
	_taya_time = state.get("taya_time", _taya_time).duplicate()
	_claims = state.get("claims", _claims).duplicate()
	_shift_timer = float(state.get("shift_left", _shift_timer))
	var langits: Array = state.get("langits", [])
	_langits.clear()
	for spot in langits:
		_langits.append(spot)
	_shift_count = int(state.get("shift", _shift_count))
	if _taya != previous:
		_announce_taya(_taya)


# The first Taya is chosen once begin_trial() has paid (First Light), so the
# "most FAVOR" it reads is the real one.
func _start_trial() -> void:
	super._start_trial()
	if _authority:
		_choose_taya(_highest_favor_ids())


# The payout is banked BEFORE the base settles the trial (rules.end_trial()
# writes the results), so it shows in this trial's standings.
func _end_trial() -> void:
	if _authority and not _paid and _phase == Phase.PLAYING:
		_paid = true
		rules.time_left = INF  # a payout is never Panahon ng Anihan's harvest
		_bank_drain(true)
		pay_out()
	super._end_trial()


func _on_peer_left(peer_id: int) -> void:
	super._on_peer_left(peer_id)
	for index in _claims.keys().duplicate():
		if int(_claims[index]) == peer_id:
			_claims.erase(index)
	if _authority and peer_id == _taya:
		_choose_taya(_highest_favor_ids())


# --- THE TAYA ----------------------------------------------------------------

# Every mortal tied for the most FAVOR (Kamalig's store does not count).
func _highest_favor_ids() -> Array[int]:
	var best: Array[int] = []
	var top := -1
	for m in rules.mortals.values():
		if m.favor > top:
			top = m.favor
			best = [m.id]
		elif m.favor == top:
			best.append(m.id)
	return best


func _choose_taya(candidates: Array[int]) -> void:
	if candidates.is_empty():
		_taya = -1
		return
	set_taya(candidates[randi() % candidates.size()])


# Taya passes to `mortal_id`, who cannot tag back for tagback_immunity seconds.
func set_taya(mortal_id: int) -> void:
	_taya = mortal_id
	_tagback = tagback_immunity
	for index in _claims.keys().duplicate():
		if int(_claims[index]) == mortal_id:
			_claims.erase(index)  # the Taya never holds a Langit
	_announce_taya(mortal_id)


func _announce_taya(mortal_id: int) -> void:
	if mortal_id < 0:
		return
	if mortal_id == _my_id:
		_set_callout("TAYA!", TAYA_COLOR, 1.2)
		_show_banner("YOU ARE TAYA", god.color, 1.0)
	_log("%s is the Taya" % mortal_label(mortal_id), god.color)


func taya_id() -> int:
	return _taya


func _check_tag() -> void:
	if _tagback > 0.0:
		return
	var from := mortal_position(_taya)
	if from == Vector2.INF:
		return
	for entry in mortal_entries():
		var id := int(entry["id"])
		if id == _taya or is_safe(id):
			continue
		if from.distance_to(entry["pos"]) <= tag_radius:
			set_taya(id)
			return


# FAVOR drained while Taya, banked through lose_favor once a second (so Waning
# Moon, The Unmoving, Bagong Umaga and Apolaki's favors all see it).
func _bank_drain(everything := false) -> void:
	for id in _drain_pending.keys():
		var owed := float(_drain_pending[id])
		var amount := int(owed)
		if amount <= 0 and not everything:
			continue
		_drain_pending[id] = owed - float(amount)
		if amount > 0 and rules.mortal(int(id)) != null:
			lose_favor(amount, "Taya", int(id))


func taya_seconds(mortal_id: int) -> float:
	return float(_taya_time.get(mortal_id, 0.0))


# --- THE PAYOUT --------------------------------------------------------------

# What each mortal is paid, by least time as Taya. Returns {id: FAVOR}.
func payouts() -> Dictionary:
	var ids: Array = rules.mortals.keys()
	ids.sort_custom(func(a, b): return taya_seconds(int(a)) < taya_seconds(int(b)))
	var out := {}
	var steps := maxi(1, ids.size() - 1)
	var place := 0
	for index in range(ids.size()):
		if index > 0 and taya_seconds(int(ids[index])) - taya_seconds(int(ids[place])) > tie_window:
			place = index
		var amount := payout_best
		if ids.size() > 1:
			amount = int(round(lerpf(float(payout_best), float(payout_worst), float(place) / float(steps))))
		out[int(ids[index])] = amount
	return out


func pay_out() -> void:
	var paid := payouts()
	for id in paid.keys():
		bank_favor(int(paid[id]), "Langit Lupa payout", int(id))
	_log("The Harvest Pair pays out - least time as Taya earns the most", god.color)


# --- LANGIT ------------------------------------------------------------------

# How many platforms the field holds: always at least one runner is exposed.
func langit_count(mortals: int) -> int:
	return maxi(1, mortals - 2)


func _tick_shift(delta: float) -> void:
	_shift_timer -= delta
	if _shift_timer <= 0.0:
		_shift_timer += shift_interval
		_place_langits()


func is_crumbling() -> bool:
	return _phase == Phase.PLAYING and _shift_timer <= shift_warning


# New spots for every Langit: inside the field and clear of the UI strip, not on
# top of each other, and never within taya_clearance of the Taya.
func _place_langits() -> void:
	_claims.clear()
	_langits.clear()
	var half := langit_size * 0.5
	var area := Rect2(_field.position + half, _field.size - langit_size)
	area.position.x = maxf(area.position.x, UI_STRIP_WIDTH + half.x)
	var taya_at := mortal_position(_taya) if _taya != -1 else Vector2.INF
	for index in range(langit_count(rules.mortals.size())):
		var spot := Vector2.ZERO
		for attempt in range(80):
			spot = Vector2(randf_range(area.position.x, area.end.x), randf_range(area.position.y, area.end.y))
			if _langit_spot_ok(spot, taya_at):
				break
		_langits.append(spot)
	_shift_count += 1
	if _authority and _networked:
		_publish_arena_tick()


func _langit_spot_ok(spot: Vector2, taya_at: Vector2) -> bool:
	if taya_at != Vector2.INF and spot.distance_to(taya_at) < taya_clearance:
		return false
	for other in _langits:
		if absf(spot.x - other.x) < langit_size.x + 8.0 and absf(spot.y - other.y) < langit_size.y + 8.0:
			return false
	return true


func langit_rect(index: int) -> Rect2:
	return Rect2(_langits[index] - langit_size * 0.5, langit_size)


# One runner per Langit: whoever claimed it keeps it while they stand on it; a
# free one goes to the first runner (never the Taya) found standing on it.
func _update_claims() -> void:
	var where := {}
	for entry in mortal_entries():
		where[int(entry["id"])] = entry["pos"]
	for index in _claims.keys().duplicate():
		var owner := int(_claims[index])
		if index >= _langits.size() or not where.has(owner) or not langit_rect(index).has_point(where[owner]):
			_claims.erase(index)
	for index in range(_langits.size()):
		if _claims.has(index):
			continue
		for id in where.keys():
			if id == _taya or _claims.values().has(id):
				continue
			if langit_rect(index).has_point(where[id]):
				_claims[index] = id
				break


func is_safe(mortal_id: int) -> bool:
	return _claims.values().has(mortal_id)


# --- SOLO BOTS ---------------------------------------------------------------

func _spawn_bots() -> void:
	if _networked or not simulate_rivals or bots_root == null:
		return
	# The bots earn FAVOR by playing, not by the base's quiet trickle.
	rules.simulate_rivals = false
	for m in rules.mortals.values():
		if m.is_local:
			continue
		var bot: ArenaMortal = MORTAL_SCENE.instantiate()
		bots_root.add_child(bot)
		bot.set_lock(true)  # moved by this script, never by the keyboard
		bot.ring_color = god.color
		bot.set_display_name(m.display_name, god.color)
		bot.global_position = _bot_start(m.id)
		_bots[m.id] = bot
		_mortal_positions[m.id] = bot.global_position


func _bot_start(id: int) -> Vector2:
	return _field.get_center() + Vector2(160.0 * (1 if id % 2 == 0 else -1), -90.0 + 60.0 * float(id))


func _move_bots(delta: float) -> void:
	for id in _bots.keys():
		var bot: ArenaMortal = _bots[id]
		var here := bot.global_position
		var step := _bot_heading(int(id), here)
		if step.length() > 0.01:
			here += step.normalized() * bot_speed * delta
		here = here.clamp(_field.position + Vector2.ONE * bot.radius, _field.end - Vector2.ONE * bot.radius)
		bot.global_position = here
		_mortal_positions[int(id)] = here


# Taya: chase the nearest runner who is not safe. Runner: head for the nearest
# free Langit (stay put on a claimed one) and veer away from a close Taya.
func _bot_heading(id: int, here: Vector2) -> Vector2:
	if id == _taya:
		var prey := Vector2.INF
		for entry in mortal_entries():
			var other := int(entry["id"])
			if other != id and not is_safe(other) and (prey == Vector2.INF or here.distance_to(entry["pos"]) < here.distance_to(prey)):
				prey = entry["pos"]
		return Vector2.ZERO if prey == Vector2.INF else prey - here
	if is_safe(id) and not is_crumbling():
		return Vector2.ZERO
	var heading := Vector2.ZERO
	var goal := Vector2.INF
	for index in range(_langits.size()):
		var holder := int(_claims.get(index, -1))
		if holder != -1 and holder != id:
			continue
		if goal == Vector2.INF or here.distance_to(_langits[index]) < here.distance_to(goal):
			goal = _langits[index]
	if goal != Vector2.INF and not is_crumbling():
		heading = (goal - here).normalized()
	var chaser := mortal_position(_taya) if _taya != -1 else Vector2.INF
	if chaser != Vector2.INF and here.distance_to(chaser) < 170.0:
		heading += (here - chaser).normalized() * 1.3
	return heading


# --- FRAME -------------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	_draw_langits(delta)
	_place_marker()
	_refresh_hud(delta)


# Platforms: lifted with a shadow, shaking while they crumble, fading in when new.
func _draw_langits(delta: float) -> void:
	if langits_root == null:
		return
	if _shown_shift != _shift_count:
		_shown_shift = _shift_count
		_fade = 0.0
	_fade = minf(1.0, _fade + delta / maxf(0.01, langit_fade_in))
	var nodes := langits_root.get_children()
	while nodes.size() < _langits.size() and not nodes.is_empty():
		var extra: Node = nodes[0].duplicate()
		langits_root.add_child(extra)
		nodes.append(extra)
	var shaking := is_crumbling()
	for index in range(nodes.size()):
		var node: Node2D = nodes[index]
		node.visible = index < _langits.size()
		if not node.visible:
			continue
		var jitter := Vector2.ZERO
		if shaking and screen_shake_allowed():
			jitter = Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
		node.position = _langits[index] + jitter
		node.modulate.a = _fade * (0.55 if shaking else 1.0)
		var claimed := _claims.has(index)
		var body := node.get_node_or_null("Body") as ColorRect
		if body != null:
			body.color = Color(0.62, 0.86, 0.95) if claimed else Color(0.9, 0.95, 1.0)
		var crumble := node.get_node_or_null("Crumble") as Sprite2D
		if crumble != null and crumble.texture != null:
			crumble.visible = shaking
			crumble.frame = clampi(int((1.0 - _shift_timer / maxf(0.01, shift_warning)) * crumble.hframes), 0, crumble.hframes - 1)


func _place_marker() -> void:
	if taya_marker == null:
		return
	var at := mortal_position(_taya) if _taya != -1 and _phase == Phase.PLAYING else Vector2.INF
	if at != Vector2.INF and _ghosts.has(_taya) and is_instance_valid(_ghosts[_taya]):
		at = (_ghosts[_taya] as Node2D).global_position  # where the rival is drawn
	taya_marker.visible = at != Vector2.INF
	if at == Vector2.INF:
		return
	taya_marker.global_position = at
	# The tag-back buffer: the marker blinks while the new Taya cannot tag.
	if _tagback > 0.0:
		taya_marker.modulate.a = 0.35 if int(_tagback * 8.0) % 2 == 0 else 1.0
	else:
		taya_marker.modulate.a = 1.0


# --- ART ---------------------------------------------------------------------

static func art(file: String) -> Texture2D:
	var path := ART_DIR + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _apply_art() -> void:
	var platform := art("Langit.png")
	var crumble := art("Langit-Crumble.png")
	if langits_root != null:
		for node in langits_root.get_children():
			var sprite := node.get_node_or_null("Sprite") as Sprite2D
			if sprite != null:
				sprite.texture = platform
				sprite.visible = platform != null
			var body := node.get_node_or_null("Body") as ColorRect
			if body != null:
				body.visible = platform == null
			var cracks := node.get_node_or_null("Crumble") as Sprite2D
			if cracks != null:
				cracks.texture = crumble
				cracks.visible = false
				if crumble != null:
					cracks.hframes = maxi(1, int(round(float(crumble.get_width()) / float(maxi(1, crumble.get_height())))))
	var marker := art("Taya-Marker.png")
	if taya_sprite != null:
		taya_sprite.texture = marker
		taya_sprite.visible = marker != null
	var ring := get_node_or_null("TayaMarker/Ring")
	if ring != null:
		ring.visible = marker == null
		(ring as Line2D).default_color = god.color
	var watcher := art("MapulonIkapati-Overseer.png")
	if overseer != null:
		overseer.texture = watcher
		overseer.visible = watcher != null
	var backdrop := art("Arena-Background.png")
	if background != null and backdrop != null:
		background.texture = backdrop
		background.position = SCREEN_SIZE * 0.5
		background.scale = SCREEN_SIZE / backdrop.get_size()


# --- HUD ---------------------------------------------------------------------

func _set_callout(text: String, tint: Color, seconds: float) -> void:
	_callout_time = seconds
	if callout_label == null:
		return
	callout_label.text = text
	callout_label.add_theme_color_override("font_color", tint)
	callout_label.visible = seconds > 0.0


func _refresh_hud(delta: float) -> void:
	if _callout_time > 0.0:
		_callout_time -= delta
		if _callout_time <= 0.0 and callout_label != null:
			callout_label.visible = false
	if is_crumbling() and _callout_time <= 0.0 and callout_label != null:
		callout_label.text = "THE LANGIT CRUMBLE!"
		callout_label.add_theme_color_override("font_color", god.color)
		callout_label.visible = true
	elif not is_crumbling() and _callout_time <= 0.0 and callout_label != null:
		callout_label.visible = false
	if taya_list != null:
		var ids: Array = rules.mortals.keys()
		ids.sort_custom(func(a, b): return taya_seconds(int(a)) < taya_seconds(int(b)))
		var rows: Array[String] = ["TIME AS TAYA"]
		for id in ids:
			rows.append("%s%s  %.1fs" % ["> " if int(id) == _taya else "", mortal_label(int(id)), taya_seconds(int(id))])
		taya_list.text = "\n".join(rows)
	if status_label != null:
		var dash := "DASH READY" if dash_cooldown_left() <= 0.0 else "DASH %.1fs" % dash_cooldown_left()
		var stance := "TAYA" if _taya == _my_id else ("SAFE" if is_safe(_my_id) else "ON THE LUPA")
		status_label.text = "%s     %s" % [stance, dash]
		status_label.add_theme_color_override("font_color", TAYA_COLOR if _taya == _my_id else (SAFE_COLOR if is_safe(_my_id) else god.color))
	if hint_label != null:
		hint_label.text = "TAG A RUNNER ON THE LUPA    SHIFT / SPACE - DASH" if _taya == _my_id \
			else "CLAIM A LANGIT - ONE MORTAL EACH    SHIFT / SPACE - DASH    E / Q - FAVORS    F - GOD'S DUE"
