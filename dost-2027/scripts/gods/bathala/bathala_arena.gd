class_name BathalaArena
extends Arena

# BATHALA - AGAWAN BASE. (scripts/gods/bathala + scenes/gods/bathala)
#
# EVERYTHING SHARED LIVES IN THE BASE (scripts/gods/common/arena.gd): the clock,
# the countdown, the mortal, the dialogues, the God's Due menu, the FAVOR popups
# and all the network plumbing. This file is only what makes the game Bathala's.
#
# A SHARED FIELD (like Mayari's): everyone runs on one field and sees the others.
# The host runs the rules from the positions it has; the clients mirror them
# through arena_tick_fields().
#
# THE FIELD
#   The field is split into THREE sections by the two authored base zones:
#     * your base (left)   - safe: neither you nor the gods can be tagged here.
#     * the common field (middle) - where the chasing and tagging happen.
#     * Bathala's base (right)    - safe for the gods: capture it to win the round.
#   A mortal reaching Bathala's base and standing in it holds the capture.
#
# THE GODS (Apolaki, Mayari, Tala, Hanan, and Bathala himself)
#   Up to 4 opponent gods plus Bathala always guarding his base (circling it).
#   The number scales with the players: solo still meets 4 + Bathala. Apolaki and
#   Hanan are the offensive attackers; Hanan and Tala are defensive - though either
#   may flip to the other job the moment an enemy is close or an opening appears.
#   Gods tag mortals the same way mortals tag gods: an attack freezes them for
#   freeze_time, with a countdown ticking over their head, OR thaws an ally.
#
# TAGGING / FREEZING (the one rule that binds both sides)
#   A mortal ATTACKS (left click / the `attack` action). The swing reaches a small
#   radius. Whatever it touches:
#     * an enemy GOD        -> it FREEZES for freeze_time, +tag_god_favor FAVOR.
#     * a FROZEN ally god   -> it THAWS instantly (same swing, both jobs).
#     * a FROZEN ally mortal-> it THAWS them, +unfreeze_favor FAVOR.
#   A god touching a mortal in the common field freezes that mortal: -tagged_favor
#   FAVOR, a countdown over its head, and it thaws after freeze_time or when a
#   teammate attacks it.
#
# SCORING
#   + tag_god_favor      you tag an enemy god.
#   + unfreeze_favor     you unfreeze an ally mortal.
#   + capture_favor      you catch the opponent's base.
#   - tagged_favor       you are tagged.
#   - base_lost_favor    your base is captured (EVERY mortal loses this).
#
# ROUNDS
#   Capturing a base resets everyone to spawn and a fresh round begins, until the
#   clock runs out. Bathala's base must never be touched - so defend yours and take
#   his. The trial ends with the scoreboard; Bathala's cutscene is still to come.
#
# Every number is an @export - tune it in the inspector. This script only runs the
# rules; BathalaArena.tscn authors the field, the two bases and the gods.

const GOD_SCENE := preload("res://scenes/gods/bathala/AgawanGod.tscn")
const ROSTER := ["apolaki", "mayari", "tala", "hanan"]  # Bathala is added on top
const OFFENSE := {"apolaki": true, "hanan": true}
const HOLD_TO_CAPTURE := 1.0  # seconds inside the base before it is caught

@export_category("Agawan Base")
@export var freeze_time := 5.0              # seconds a tagged god/mortal stays frozen
@export var tag_radius := 34.0              # the mortal's attack reach
@export var attack_cooldown := 0.6          # seconds between two swings
@export var base_radius := 46.0             # how big a base zone reads, in pixels

@export_category("Favor")
@export var tag_god_favor := 50             # you tag an enemy god
@export var unfreeze_favor := 100           # you unfreeze an ally mortal
@export var capture_favor := 350            # you catch the opponent's base
@export var tagged_favor := 100             # you are tagged
@export var base_lost_favor := 500          # your base is captured (everyone)

@onready var gods_root: Node2D = get_node_or_null("Gods")
@onready var bases_root: Node2D = get_node_or_null("Bases")
@onready var status_label: Label = get_node_or_null("AgawanHud/Status")
@onready var hint_label: Label = get_node_or_null("AgawanHud/Hint")
@onready var callout_label: Label = get_node_or_null("AgawanHud/Callout")

var _gods: Array[AgawanGod] = []       # every opponent god on the field, host-run
var _my_base := Vector2.ZERO          # the mortal team's base (safe zone)
var _bathala_base := Vector2.ZERO     # Bathala's base (the one to capture)
var _attack_cd := 0.0
var _hold_timer := 0.0                # seconds the local mortal has held the enemy base
var _round := 1
var _frozen_mortals := {}             # mortal id -> seconds left frozen (host)
var _frozen_gods := {}                # god index -> seconds left frozen (host)
var _round_note := ""


# --- ARENA HOOKS (see scripts/gods/common/arena.gd) --------------------------

func _ready() -> void:
	super._ready()
	_apply_tint()


func shares_mortal_positions() -> bool:
	return true


func collect_units() -> void:
	# Build the gods once the field and the two bases are known. The bases are
	# authored nodes (Bases/Mine and Bases/Bathala); the roster is fixed by the
	# rules, so the same five gods appear on every screen and the host drives them.
	_gods.clear()
	_my_base = _base_center("Mine")
	_bathala_base = _base_center("Bathala")
	if gods_root == null or _bathala_base == Vector2.ZERO:
		return
	var roster := ROSTER.duplicate()
	# The opposing gods scale with the players, capped at the four names (Bathala
	# is always the fifth): solo still meets the full roster so the base is tested.
	var count := clampi(roster.size(), 1, roster.size())
	for index in range(count):
		var god: AgawanGod = GOD_SCENE.instantiate()
		god.god_id = StringName(roster[index])
		god.role = AgawanGod.Role.ATTACK if OFFENSE.get(roster[index], false) else AgawanGod.Role.DEFEND
		god.set_stage(_bathala_base, _my_base)   # gods defend Bathala's base, chase ours
		god.global_position = _spawn_near(_bathala_base, index)
		gods_root.add_child(god)
		_gods.append(god)
	# Bathala himself: always present, always circling his own base.
	var bathala: AgawanGod = GOD_SCENE.instantiate()
	bathala.god_id = &"bathala"
	bathala.role = AgawanGod.Role.DEFEND
	bathala.set_stage(_bathala_base, _bathala_base)
	bathala.global_position = _bathala_base + Vector2(0, guard_offset())
	gods_root.add_child(bathala)
	_gods.append(bathala)


func arena_round_reset() -> void:
	# Both sides back to their spawns, no freeze, a fresh hold - the round starts
	# the same way every time, the mortals through the "3 - 2 - 1".
	_attack_cd = 0.0
	_hold_timer = 0.0
	_round_note = ""
	_frozen_mortals.clear()
	_frozen_gods.clear()
	for index in range(_gods.size()):
		var god: AgawanGod = _gods[index]
		god.unfreeze()
		god.global_position = _god_spawn(god, index)


# A spawn spot around a base so the gods do not all pile onto the same pixel.
func _spawn_near(center: Vector2, index: int) -> Vector2:
	return center + Vector2(cos(index * 1.7) * 70.0, sin(index * 1.7) * 45.0)


func _god_spawn(god: AgawanGod, index: int) -> Vector2:
	if god.god_id == &"bathala":
		return _bathala_base + Vector2(0, guard_offset())
	return _spawn_near(_bathala_base, index)


func guard_offset() -> float:
	return base_radius * 0.6


# Where a base sits, read back from the authored zone node named `which`
# (Bases/Mine, Bases/Bathala). Vector2.ZERO when it was not authored.
func _base_center(which: String) -> Vector2:
	if bases_root == null:
		return Vector2.ZERO
	var zone: Node2D = bases_root.get_node_or_null(which)
	return zone.global_position if zone != null else Vector2.ZERO


# --- THE RULES (host only) ---------------------------------------------------

func arena_rules_tick(delta: float) -> void:
	if not _authority:
		return
	# Move every god, let the frozen ones thaw, then let the live ones tag mortals.
	for index in range(_gods.size()):
		var god: AgawanGod = _gods[index]
		var nearest := _nearest_mortal(god.global_position)
		god.step(delta, nearest)
		if god.is_frozen():
			_frozen_gods[index] = god.freeze_left
			continue
		_frozen_gods.erase(index)
		_tag_mortals_from(god)
	# The frozen mortals thaw on their own clock too, and a mortal standing in
	# Bathala's base is holding the capture.
	_tick_frozen_mortals(delta)
	_check_capture(delta)


# The mortal standing nearest to `from` (Vector2.INF when none is known).
func _nearest_mortal(from: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_gap := INF
	for entry in mortal_entries():
		var pos: Vector2 = entry["pos"]
		if pos == Vector2.INF:
			continue
		var gap := pos.distance_squared_to(from)
		if gap < best_gap:
			best_gap = gap
			best = pos
	return best


# A god touching a mortal in the common field freezes it - but never on the
# mortal's own base, where neither side may be tagged. Bathala guards his base,
# so a mortal that walks up to it is the one he tags.
func _tag_mortals_from(god: AgawanGod) -> void:
	for entry in mortal_entries():
		var mortal_id := int(entry["id"])
		var pos: Vector2 = entry["pos"]
		if pos == Vector2.INF or _is_frozen(mortal_id):
			continue
		if pos.distance_to(_my_base) <= base_radius:
			continue  # the mortal is safe on its own base
		if pos.distance_to(god.global_position) <= maxf(god.tag_radius, player.radius):
			_freeze_mortal(mortal_id)


func _freeze_mortal(mortal_id: int) -> void:
	_frozen_mortals[mortal_id] = freeze_time
	lose_favor(tagged_favor, "Tagged by a god", mortal_id)
	knock_mortal(mortal_id, player.global_position, 0.3, 260.0)
	spawn_popup("TAGGED", Arena.POPUP_LOSS_COLOR, popup_origin(mortal_id))


func _is_frozen(mortal_id: int) -> bool:
	return float(_frozen_mortals.get(mortal_id, 0.0)) > 0.0


func _tick_frozen_mortals(delta: float) -> void:
	for mortal_id in _frozen_mortals.keys().duplicate():
		var left := float(_frozen_mortals[mortal_id]) - delta
		if left <= 0.0:
			_frozen_mortals.erase(mortal_id)
		else:
			_frozen_mortals[mortal_id] = left


# A mortal standing inside Bathala's base holds the capture for HOLD_TO_CAPTURE
# seconds, then the base is caught: the holder gains capture_favor, every OTHER
# mortal loses base_lost_favor, and a fresh round resets everyone to spawn.
func _check_capture(delta: float) -> void:
	if _bathala_base == Vector2.ZERO:
		return
	var holder := -1
	for entry in mortal_entries():
		var pos: Vector2 = entry["pos"]
		if pos != Vector2.INF and pos.distance_to(_bathala_base) <= base_radius:
			holder = int(entry["id"])
			break
	if holder < 0:
		_hold_timer = 0.0
		return
	_hold_timer += delta
	if _hold_timer < HOLD_TO_CAPTURE:
		return
	_capture_base(holder)


func _capture_base(holder_id: int) -> void:
	_hold_timer = 0.0
	bank_favor(capture_favor, "Caught the base", holder_id)
	for entry in mortal_entries():
		var mortal_id := int(entry["id"])
		if mortal_id != holder_id:
			lose_favor(base_lost_favor, "Base captured", mortal_id)
	_show_banner("BASE CAPTURED!", god.color, 2.0)
	_round += 1
	_round_note = "ROUND %d" % _round
	# Everyone resets to spawn and a fresh round begins.
	arena_round_reset()
	if _authority and _net != null and _net.has_multiplayer_peer():
		_publish_layout()


# --- THE MORTAL'S ATTACK -----------------------------------------------------
# Left click / the `attack` action: one swing that reaches tag_radius. Whatever it
# touches decides what happens - the SAME attack does both jobs:
#   * a live enemy GOD  -> it FREEZES (a tag), +tag_god_favor FAVOR.
#   * a FROZEN ally god  -> it THAWS (the friendly side of the same swing).
#   * a FROZEN ally mortal -> it THAWS them, +unfreeze_favor FAVOR.

func _input(event: InputEvent) -> void:
	# A click on one of the favor panels is the HUD's answer, not a swing.
	if super._tap_panel_click(event):
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if _phase != Phase.PLAYING or player.locked or dialogue.is_active() or due_menu.is_open():
		return
	if event.is_action_pressed("attack"):
		_try_attack()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _try_attack() -> void:
	if _attack_cd > 0.0:
		_log("Attack recharging  (%.1fs)" % _attack_cd, god.color)
		return
	_attack_cd = attack_cooldown
	player.play_animation(&"hit-arnis")
	if _authority:
		_resolve_attack(_my_id, player.global_position)
	elif _net != null and _net.has_multiplayer_peer():
		_net.rpc_id(1, "request_agawan_attack", player.global_position)


# The host resolves a swing from `caster_id` at `origin`: freeze a live enemy god,
# or thaw a frozen ally (god or mortal). Returns the god index it froze, or -1.
func _resolve_attack(caster_id: int, origin: Vector2) -> int:
	var hit_god := -1
	for index in range(_gods.size()):
		var god: AgawanGod = _gods[index]
		if origin.distance_to(god.global_position) > maxf(tag_radius, 18.0):
			continue
		if god.is_frozen():
			# A frozen god is on the OPPONING team, so thawing it would help them -
			# a mortal only ever FREEZES enemy gods. (Allies thaw each other; here
			# every god is an enemy to the mortals, so a swing only ever freezes.)
			continue
		if hit_god < 0:
			hit_god = index
			god.freeze_for(freeze_time)
			_frozen_gods[index] = freeze_time
	# A frozen ally MORTAL in reach thaws on the same swing.
	for entry in mortal_entries():
		var mortal_id := int(entry["id"])
		if mortal_id == caster_id:
			continue
		if _is_frozen(mortal_id) and (entry["pos"] as Vector2).distance_to(origin) <= tag_radius:
			_frozen_mortals.erase(mortal_id)
			bank_favor(unfreeze_favor, "Unfroze an ally", caster_id)
			spawn_popup("THAWED", Arena.POPUP_GAIN_COLOR, popup_origin(mortal_id))
	if hit_god >= 0:
		bank_favor(tag_god_favor, "Tagged a god", caster_id)
		_show_banner("GOD FROZEN!", god.color, 1.2)
	# A swing that caught nothing simply pays nothing - its cooldown still ticks.
	return hit_god


# --- NETWORK (the gods and the freezes travel to every screen) ---------------

func _connect_network() -> void:
	super._connect_network()
	if _net == null:
		return
	if _net.has_signal("agawan_attack_requested") and _authority:
		_net.connect("agawan_attack_requested", _on_agawan_attack_requested)


func _on_agawan_attack_requested(caster_id: int, origin: Vector2) -> void:
	if not _authority or _phase != Phase.PLAYING:
		return
	var known := mortal_position(caster_id)
	if known != Vector2.INF and known.distance_to(origin) > 90.0:
		return  # the swing is nowhere near where the host last saw that mortal
	_resolve_attack(caster_id, known if known != Vector2.INF else origin)


# The fixed world that only travels once per round: where the two bases are and
# which god stands where. The god poses move every tick (arena_tick_fields).
func arena_layout_fields() -> Dictionary:
	var gods: Array = []
	for god in _gods:
		gods.append({"id": str(god.god_id), "role": int(god.role), "pos": [god.global_position.x, god.global_position.y]})
	return {"mine": [_my_base.x, _my_base.y], "bathala": [_bathala_base.x, _bathala_base.y], "gods": gods, "round": _round}


func arena_read_layout(layout: Dictionary) -> void:
	var mine: Array = layout.get("mine", [])
	if mine.size() == 2:
		_my_base = Vector2(float(mine[0]), float(mine[1]))
	var bathala: Array = layout.get("bathala", [])
	if bathala.size() == 2:
		_bathala_base = Vector2(float(bathala[0]), float(bathala[1]))
	_round = int(layout.get("round", _round))
	var gods: Array = layout.get("gods", [])
	for index in range(mini(gods.size(), _gods.size())):
		var entry: Dictionary = gods[index]
		var god: AgawanGod = _gods[index]
		god.god_id = StringName(str(entry.get("id", "")))
		god.role = entry.get("role", AgawanGod.Role.ATTACK) as int
		var pos: Array = entry.get("pos", [])
		if pos.size() == 2:
			god.place(Vector2(float(pos[0]), float(pos[1])))
		god._refresh_visual()


# The fast per-tick state: each god's live position and freeze countdown, plus the
# mortals that are frozen. The host runs the rules; the clients only mirror this.
func arena_tick_fields() -> Dictionary:
	var gods: Array = []
	for god in _gods:
		gods.append({
			"pos": [god.global_position.x, god.global_position.y],
			"frozen": god.is_frozen(),
			"left": god.freeze_left,
		})
	var frozen: Dictionary = {}
	for mortal_id in _frozen_mortals.keys():
		frozen[str(mortal_id)] = float(_frozen_mortals[mortal_id])
	return {"gods": gods, "frozen": frozen, "hold": _hold_timer}


func arena_read_tick(state: Dictionary) -> void:
	var gods: Array = state.get("gods", [])
	for index in range(mini(gods.size(), _gods.size())):
		var entry: Dictionary = gods[index]
		var god: AgawanGod = _gods[index]
		var pos: Array = entry.get("pos", [])
		if pos.size() == 2:
			god.place(Vector2(float(pos[0]), float(pos[1])))
		if bool(entry.get("frozen", false)):
			god.freeze_for(float(entry.get("left", 0.0)))
		else:
			god.unfreeze()
		god._refresh_visual()
	_frozen_mortals.clear()
	var frozen: Dictionary = state.get("frozen", {})
	for key in frozen.keys():
		_frozen_mortals[int(key)] = float(frozen[key])
	_hold_timer = float(state.get("hold", 0.0))


# --- FRAME / HUD -------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_refresh_hud()


# --- BATHALA'S FAVORS --------------------------------------------------------
# The two E / Q skills resolve on the host (they cut FAVOR), and their screen
# effects reuse the field's blindness (Mayari) and Sun Patches (Apolaki): Bathala
# borrowed both sisters' curses for his own sacrifices.
func _apply_skill_effect(favor: GodFavor, caster_id: int) -> void:
	if favor == null:
		return
	if favor.id == &"half_vision_sacrifice" and _authority:
		var target_id := rules.cast_half_vision(caster_id, favor)
		if target_id >= 0:
			_publish_god_state()
		# The leading opponent's screen dims, the way Mayari's Half Vision does.
		_fire_curse_blind(caster_id, favor)
	elif favor.id == &"siblings_compromise_bathala" and _authority:
		rules.cast_siblings_compromise(caster_id, favor)
		_publish_god_state()
		return  # cutting your own FAVOR blinds nobody
	else:
		super._apply_skill_effect(favor, caster_id)


# The two INSTANT curses ("Our Partnership Ends Here"): the host pays the cost and
# marks the curse, then every OPPOSING mortal's screen carries Mayari's blindness
# or Apolaki's Sun Patches for the promise's duration.
func _on_favor_fired(player_id: int, favor: GodFavor, text: String) -> void:
	super._on_favor_fired(player_id, favor, text)
	if not _authority:
		return
	if favor.id == &"our_partnership_ends_mayari":
		_fire_curse_blind(player_id, favor)
	elif favor.id == &"our_partnership_ends_apolaki":
		var duration := favor.param("sun_duration", 10.0)
		var count := int(favor.param("sun_count", 4.0))
		for other in rules.mortals.values():
			if other.id != player_id:
				_add_sun_patches(other.id, count, duration, player_id)
		_publish_god_state()


# Darken every screen but the caster's, for the favor's duration (Mayari's curse).
func _fire_curse_blind(caster_id: int, favor: GodFavor) -> void:
	var duration := maxf(0.0, favor.duration if favor.duration > 0.0 else favor.param("blind_duration", 10.0))
	if caster_id == _my_id:
		_log("The field goes dark for everyone else", favor.color)
	else:
		_blind_time = maxf(_blind_time, duration)
		_log("Mayari's curse - you see only a circle around your mortal", favor.color)
	if _authority and _networked and _net != null:
		_net.send_arena_blind(caster_id, _blind_radius, duration)



# The god's colour is the only thing the code paints: the field border glows in it.
func _apply_tint() -> void:
	if field_root != null:
		field_root.apply_tint(god.color)


func _refresh_hud() -> void:
	if status_label != null:
		var stance := "DEFENDING" if player.global_position.distance_to(_my_base) < base_radius \
			else ("CAPTURING!" if player.global_position.distance_to(_bathala_base) < base_radius else "ON THE FIELD")
		var swing := "ATTACK READY" if _attack_cd <= 0.0 else "ATTACK %.1fs" % _attack_cd
		status_label.text = "%s     %s     ROUND %d" % [stance, swing, _round]
		status_label.add_theme_color_override("font_color", god.color)
	if hint_label != null:
		hint_label.text = "CLICK - ATTACK (freeze a god / thaw an ally)     E / Q - FAVORS     F - GOD'S DUE"
	if _round_note != "" and callout_label != null:
		callout_label.text = _round_note
		callout_label.add_theme_color_override("font_color", god.color)
		callout_label.visible = true
		_round_note = ""






