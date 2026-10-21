class_name BathalaArena
extends Arena

# BATHALA - AGAWAN BASE, the finale. (scripts/gods/bathala + scenes/gods/bathala)
#
# EVERYTHING SHARED LIVES IN THE BASE (scripts/gods/common/arena.gd): the clock,
# the countdown, the mortal, the dialogues, the God's Due menu, the FAVOR popups
# and all the network plumbing. This file is only what makes the game Bathala's.
#
# A SHARED FIELD (like Mayari's): everyone runs on one field and sees the others.
# The host runs every rule from the positions it has; the clients only draw what
# arena_tick_fields() / arena_layout_fields() send them.
#
# THE FIELD
#   The field is split into THREE sections by the two authored base zones:
#     * your base (left, Bases/Mine) - a mortal is safe here, a god is NOT: the
#       attacking gods raid it, and the mortals defend it by tagging them in it.
#     * the common field (middle)    - where the chasing and tagging happen.
#     * Bathala's base (right)       - a god is safe here; a mortal holding it
#       captures it.
#   Nobody can be tagged on their own base.
#
# THE GODS: one per mortal, plus Bathala (2 players: 2+1 ... 4 players: 4+1;
#   solo testing meets 2+1). The slots fill in ROSTER order - Apolaki (offense),
#   Tala (defense), Mayari (offense), Hanan (defense) - and Bathala always circles
#   his own base. Each god plays like their own trial (see agawan_god.gd):
#     * Apolaki lunges, Mayari reaches further and guards the lanes, Bathala walks
#       at whoever holds his base.
#     * Tala throws a slow star every star_interval at the nearest mortal in the
#       common field: it freezes on a hit, it can be dodged, and a swing breaks
#       it (+star_break_favor). The host moves the stars; the tick carries them.
#     * Hanan pulses a ring of dawn every dawn_interval that thaws every frozen
#       god within dawn_radius - the gods' medic, so freeze her first.
#
# TAGGING / FREEZING
#   A mortal ATTACKS (left click / `attack`). The swing reaches tag_radius:
#     * a live enemy GOD outside Bathala's base -> it FREEZES, +tag_god_favor.
#     * a FROZEN ally mortal                   -> it THAWS, +unfreeze_favor.
#     * one of Tala's stars                    -> it breaks, +star_break_favor.
#   A god touching a mortal off its base freezes it: -tagged_favor. FROZEN MEANS
#   FROZEN: a frozen mortal cannot move, attack, dash or capture until it thaws
#   (freeze_time, a 5-4-3-2-1 over its head) or a teammate's swing thaws it, and
#   it then gets invuln_time of mercy. A live god touching a frozen god (within
#   thaw_touch) thaws it at once - the gods rescue each other too.
#
# THE TWO CAPTURES (each one ends the round)
#   * Mortals hold Bathala's base (frozen ones do not count). It falls after
#     hold_to_capture / (1 + team_hold_bonus x (holders - 1)) seconds, so a team
#     push is faster; the last-place mortal holds for only pity_hold (BATHALA'S
#     PITY, picked at the start of each round, off with one mortal). A gold ring
#     fills on his base. The holders get capture_favor, every other mortal
#     capture_share_favor - nobody loses FAVOR to it.
#   * An attacking god that stays live inside the mortals' base for
#     god_hold_to_capture seconds takes it: EVERY mortal loses base_lost_favor.
#     A red ring fills on your base so the defenders see it coming; freezing the
#     god stops its hold.
#   After either capture the field freezes for round_pause seconds under the
#   banner, everyone goes back to spawn, and a "3 - 2 - 1" (countdown_time)
#   starts the next round.
#
# THE FINALE
#   * BATHALA GROWS WARY: every capture, by either side, makes the gods
#     wary_speed_step faster, up to wary_speed_cap.
#   * THE FINAL JUDGMENT: with judgment_time left the field border turns gold,
#     "ANG HULING PAGHUHUSGA" is called, Bathala says "Now I judge you." and both
#     capture payouts double - the last seconds can still flip the standings.
#
# SCORING (every number below is an @export)
#   + tag_god_favor        you tag a god.
#   + star_break_favor     your swing breaks Tala's star.
#   + unfreeze_favor       you unfreeze an ally mortal.
#   + capture_favor        you are inside Bathala's base when it falls (x2 judgment).
#   + capture_share_favor  a teammate captures Bathala's base (x2 judgment).
#   - tagged_favor         you are tagged.
#   - base_lost_favor      the gods capture your base (EVERY mortal).
#   All of it goes through bank_favor / lose_favor, so the loss multipliers,
#   Si Batman and the loss history keep working.
#
# This script only runs the rules; BathalaArena.tscn authors the field, the two
# bases (and their Hold rings), the Stars and Marks layers and the HUD labels.

const GOD_SCENE := preload("res://scenes/gods/bathala/AgawanGod.tscn")
const SHOCK_SCENE := preload("res://scenes/gods/mayari/Shockwave.tscn")
# Per-god scenes so each god can author its own animated sprite art.
const GOD_SCENES := {
	"apolaki": preload("res://scenes/gods/bathala/Apolaki.tscn"),
	"tala": preload("res://scenes/gods/bathala/Tala.tscn"),
	"mayari": preload("res://scenes/gods/bathala/Mayari.tscn"),
	"hanan": preload("res://scenes/gods/bathala/Hanan.tscn"),
	"bathala": preload("res://scenes/gods/bathala/Bathala.tscn"),
}
# The slots fill in this order, one per mortal (at least two); Bathala is added on top.
const ROSTER := ["apolaki", "tala", "mayari", "hanan"]
const OFFENSE := {"apolaki": true, "mayari": true}
const MIN_GODS := 2
const MARK_OFFSET := Vector2(-30.0, -78.0)   # a frozen mortal's countdown, as over a god
const PITY_OFFSET := Vector2(-80.0, -96.0)

@export_category("Agawan Base")
@export var freeze_time := 5.0              # seconds a tagged god/mortal stays frozen
@export var tag_radius := 34.0              # the mortal's attack reach
@export var attack_cooldown := 0.6          # seconds between two attacks (shockwave cooldown)

@export_category("Shockwave (replaces arnis)")
@export var shock_radius := 130.0           # full radius of the attack wave
@export var shock_expand_time := 0.45       # seconds the wave takes to reach full size
@export var base_radius := 46.0             # how big a base zone reads, in pixels
@export var thaw_touch := 40.0              # a live god this close to a frozen god thaws it
@export var hold_to_capture := 1.0          # seconds one mortal holds Bathala's base to catch it
@export var team_hold_bonus := 0.5          # each extra holder speeds the hold by this much
@export var god_hold_to_capture := 1.5      # seconds a god holds the mortals' base to catch it
@export var round_pause := 1.5              # the field stands still this long after a capture

@export_category("Favor")
@export var tag_god_favor := 50             # you tag a god
@export var star_break_favor := 25          # your swing breaks Tala's star
@export var unfreeze_favor := 100           # you unfreeze an ally mortal
@export var capture_favor := 500            # you are inside Bathala's base when it falls
@export var capture_share_favor := 150      # a teammate captures Bathala's base
@export var tagged_favor := 100             # you are tagged
@export var base_lost_favor := 500          # the gods capture your base (every mortal)

@export_category("Tala - the star throw")
@export var star_interval := 5.0            # seconds between throws (0 = off)
@export var star_speed := 150.0             # slow enough to dodge
@export var star_radius := 10.0
@export var star_life := 4.0                # seconds before a missed star fades

@export_category("Hanan - the dawn")
@export var dawn_interval := 6.0            # seconds between pulses (0 = off)
@export var dawn_radius := 120.0            # the pulse thaws every frozen god this close
@export var dawn_flash := 0.5               # how long the ring of light shows

@export_category("Bathala's pity")
@export var pity_hold := 0.6                # the last-place mortal's hold (0 = off)

@export_category("Bathala grows wary")
@export var wary_speed_step := 0.05         # the gods get this much faster per capture
@export var wary_speed_cap := 0.25          # ...up to this much

@export_category("The final judgment")
@export var judgment_time := 20.0           # seconds left when it begins (0 = off)
@export var judgment_mult := 2              # both capture payouts are multiplied by this
@export var callout_time := 2.5             # how long a callout stays up

@onready var gods_root: Node2D = get_node_or_null("Gods")
@onready var bases_root: Node2D = get_node_or_null("Bases")
@onready var stars_root: Node2D = get_node_or_null("Stars")
@onready var marks_root: Node2D = get_node_or_null("Marks")
@onready var pity_label: Label = get_node_or_null("Marks/Pity")
@onready var mine_hold_ring: Line2D = get_node_or_null("Bases/Mine/Hold")
@onready var bathala_hold_ring: Line2D = get_node_or_null("Bases/Bathala/Hold")
@onready var status_label: Label = get_node_or_null("AgawanHud/Status")
@onready var hint_label: Label = get_node_or_null("AgawanHud/Hint")
@onready var callout_label: Label = get_node_or_null("AgawanHud/Callout")
@onready var shocks_root: Node2D = get_node_or_null("Shocks")

var _gods: Array[AgawanGod] = []       # every god on the field, host-run
var _my_base := Vector2.ZERO          # the mortal team's base (safe for mortals)
var _bathala_base := Vector2.ZERO     # Bathala's base (safe for gods, the one to capture)
var _round := 1
var _frozen_mortals := {}             # mortal id -> seconds left frozen (host; mirrored)
var _frozen_gods := {}                # god index -> seconds left frozen (host)
var _shocks: Array = []               # the waves the host is growing: {origin, radius, caster, wave, hit}
var _shock_cd := 0.0                  # shockwave cooldown
var _hold_progress := 0.0             # 0..1, the mortals' hold on Bathala's base
var _holders := 0                     # how many mortals are holding it
var _holder_pos := Vector2.INF        # where the first holder stands (Bathala walks at it)
var _god_hold := 0.0                  # 0..1, the gods' hold on the mortals' base
var _stars: Array[Dictionary] = []    # Tala's stars: {pos, vel, left}
var _star_cd := 0.0
var _dawn_timer := 0.0                # seconds to Hanan's next pulse
var _wary := 0                        # captures so far: each one speeds the gods up
var _pity_id := -1                    # the mortal Bathala pities this round (-1 = none)
var _judgment := false                # the final judgment is on
var _pause := 0.0                     # seconds the field still stands still after a capture
var _count := 0.0                     # seconds left in the round's "3 - 2 - 1"
var _round_count_shown := -1
var _rule_lock := false               # this script locked the local mortal (frozen / reset)
var _callout_left := 0.0
var _star_nodes: Array[Sprite2D] = []
var _mark_labels: Dictionary = {}     # mortal id -> Label (the frozen countdown)


# --- ARENA HOOKS (see scripts/gods/common/arena.gd) --------------------------

func _ready() -> void:
	super._ready()
	_apply_tint()


func shares_mortal_positions() -> bool:
	return true


# The god slots for `mortals` players, in fill order: one god per mortal, never
# fewer than two, never more than the four names (Bathala comes on top).
static func roster_for(mortals: int) -> Array:
	return ROSTER.slice(0, clampi(mortals, MIN_GODS, ROSTER.size()))


func collect_units() -> void:
	# The bases are authored nodes (Bases/Mine and Bases/Bathala). The gods are
	# built once - a client is handed the host's roster in the layout and rebuilds
	# only when it differs (arena_read_layout).
	_my_base = _base_center("Mine")
	_bathala_base = _base_center("Bathala")
	if _gods.is_empty():
		_build_gods(roster_for(_field_mortal_ids().size()))


# The follow camera's edge arrows: every god on the field and both bases.
func edge_targets() -> Array:
	var targets: Array = []  # untyped: the gods and the bases are different nodes
	targets.append_array(_gods)
	if bases_root != null:
		targets.append_array(bases_root.get_children())
	return targets


# Build the field's gods for `roster` (ids from ROSTER), plus Bathala himself.
func _build_gods(roster: Array) -> void:
	for god_node in _gods:
		if is_instance_valid(god_node):
			god_node.queue_free()
	_gods.clear()
	_frozen_gods.clear()
	if gods_root == null or _bathala_base == Vector2.ZERO:
		return
	for id in roster + ["bathala"]:
		var god_scene = GOD_SCENES.get(id, GOD_SCENE)
		var god_node: AgawanGod = god_scene.instantiate()
		god_node.god_id = StringName(id)
		god_node.role = AgawanGod.Role.ATTACK if OFFENSE.get(id, false) else AgawanGod.Role.DEFEND
		god_node.set_stage(_bathala_base, _my_base, base_radius)
		god_node.pulse_radius = dawn_radius
		gods_root.add_child(god_node)
		_gods.append(god_node)
		god_node.global_position = _god_spawn(god_node, _gods.size() - 1)


func roster_ids() -> Array:
	var ids: Array = []
	for god_node in _gods:
		ids.append(str(god_node.god_id))
	return ids


# The mortals on the field: every peer when networked; solo, us plus anyone whose
# position is known (the simulated rivals are not on the field).
func _field_mortal_ids() -> Array:
	if _networked:
		return rules.mortals.keys()
	var ids: Array = []
	for entry in mortal_entries():
		ids.append(int(entry["id"]))
	return ids if not ids.is_empty() else [_my_id]


func arena_round_reset() -> void:
	# Both sides back to their spawns, no freeze, no hold, no star in the air -
	# every round starts the same way. The pity is weighed again here.
	_shock_cd = 0.0
	_hold_progress = 0.0
	_holders = 0
	_holder_pos = Vector2.INF
	_god_hold = 0.0
	_stars.clear()
	_star_cd = star_interval
	_dawn_timer = dawn_interval
	_pause = 0.0
	_count = 0.0
	_frozen_mortals.clear()
	_frozen_gods.clear()
	for index in range(_gods.size()):
		var god_node: AgawanGod = _gods[index]
		god_node.reset_round()
		god_node.global_position = _god_spawn(god_node, index)
	if _authority:
		_pity_id = _pick_pity()


# A spawn spot around a base so the gods do not all pile onto the same pixel.
func _spawn_near(center: Vector2, index: int) -> Vector2:
	return center + Vector2(cos(index * 1.7) * 70.0, sin(index * 1.7) * 45.0)


func _god_spawn(god_node: AgawanGod, index: int) -> Vector2:
	if god_node.god_id == &"bathala":
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


func _god_by_id(id: StringName) -> AgawanGod:
	for god_node in _gods:
		if god_node.god_id == id:
			return god_node
	return null


# The last-place mortal, when there is exactly one (a tie pities nobody).
func _pick_pity() -> int:
	var ids := _field_mortal_ids()
	if ids.size() < 2 or pity_hold <= 0.0:
		return -1
	var lowest := -1
	var lowest_favor := 0
	var tied := false
	for id in ids:
		var mortal := rules.mortal(int(id))
		if mortal == null:
			continue
		if lowest < 0 or mortal.favor < lowest_favor:
			lowest = int(id)
			lowest_favor = mortal.favor
			tied = false
		elif mortal.favor == lowest_favor:
			tied = true
	return -1 if tied else lowest


# Bathala grows wary: how much faster the gods are after `_wary` captures.
func wary_speed() -> float:
	return 1.0 + minf(wary_speed_step * _wary, wary_speed_cap)


# --- THE RULES (host only) ---------------------------------------------------

func arena_rules_tick(delta: float) -> void:
	if not _authority:
		return
	if not _judgment and judgment_time > 0.0 and _trial_time <= judgment_time:
		_begin_judgment()
	# After a capture the field stands still, then the "3 - 2 - 1" runs.
	if _pause > 0.0:
		_pause -= delta
		if _pause <= 0.0:
			_start_round()
		return
	if _count > 0.0:
		_tick_round_count(delta)
		return
	var live := _live_mortal_positions()
	for index in range(_gods.size()):
		var god_node: AgawanGod = _gods[index]
		god_node.speed_mult = wary_speed()
		god_node.watch_target = _holder_pos
		god_node.step(delta, live)
		if god_node.is_frozen():
			_frozen_gods[index] = god_node.freeze_left
			continue
		_frozen_gods.erase(index)
		_tag_mortals_from(god_node)
		_thaw_gods_near(god_node)
	_tick_dawn(delta)
	_tick_stars(delta)
	_tick_shocks(delta)
	_tick_god_shocks(delta)
	_tick_frozen_mortals(delta)
	_check_capture(delta)
	if _pause <= 0.0:
		_check_base_raid(delta)


# Where every mortal that can still be tagged stands (the gods chase these).
func _live_mortal_positions() -> Array:
	var out: Array = []
	for entry in mortal_entries():
		if not _is_frozen(int(entry["id"])):
			out.append(entry["pos"])
	return out


func _on_my_base(pos: Vector2) -> bool:
	return pos.distance_to(_my_base) <= base_radius


func _in_bathala_base(pos: Vector2) -> bool:
	return pos.distance_to(_bathala_base) <= base_radius


# Can a god (or a star) freeze this mortal right now? Never on its own base,
# never while frozen, never in its mercy seconds.
func _taggable(mortal_id: int, pos: Vector2) -> bool:
	return pos != Vector2.INF and not _is_frozen(mortal_id) and not _on_my_base(pos) \
		and not is_mortal_invulnerable(mortal_id)


# A god touching a mortal freezes it - anywhere but the mortal's own base.
func _tag_mortals_from(god_node: AgawanGod) -> void:
	for entry in mortal_entries():
		var mortal_id := int(entry["id"])
		var pos: Vector2 = entry["pos"]
		if _taggable(mortal_id, pos) and pos.distance_to(god_node.global_position) <= maxf(god_node.reach(), player.radius):
			_freeze_mortal(mortal_id, god_node.global_position)


# A live god touching a frozen god thaws it ("opponent gods can do the same").
func _thaw_gods_near(god_node: AgawanGod) -> void:
	for index in range(_gods.size()):
		var other: AgawanGod = _gods[index]
		if other != god_node and other.is_frozen() and other.global_position.distance_to(god_node.global_position) <= thaw_touch:
			other.unfreeze()
			_frozen_gods.erase(index)


func _freeze_mortal(mortal_id: int, from: Vector2) -> void:
	_frozen_mortals[mortal_id] = freeze_time
	lose_favor(tagged_favor, "Tagged by a god", mortal_id)
	knock_mortal(mortal_id, from, 0.3, 260.0)
	spawn_popup("TAGGED", Arena.POPUP_LOSS_COLOR, popup_origin(mortal_id))


func _is_frozen(mortal_id: int) -> bool:
	return float(_frozen_mortals.get(mortal_id, 0.0)) > 0.0


func _thaw_mortal(mortal_id: int) -> void:
	_frozen_mortals.erase(mortal_id)
	set_mortal_invuln(mortal_id, invuln_time)  # no god can re-tag it the same instant


func _tick_frozen_mortals(delta: float) -> void:
	for mortal_id in _frozen_mortals.keys().duplicate():
		var left := float(_frozen_mortals[mortal_id]) - delta
		if left <= 0.0:
			_thaw_mortal(mortal_id)
		else:
			_frozen_mortals[mortal_id] = left


# Hanan's dawn: every dawn_interval of her being live, a ring of light thaws
# every frozen god within dawn_radius of her.
func _tick_dawn(delta: float) -> void:
	var hanan := _god_by_id(&"hanan")
	if hanan == null or dawn_interval <= 0.0 or hanan.is_frozen():
		return
	_dawn_timer -= delta
	if _dawn_timer > 0.0:
		return
	_dawn_timer = dawn_interval
	hanan.show_pulse(dawn_flash)
	for index in range(_gods.size()):
		var other: AgawanGod = _gods[index]
		if other.is_frozen() and other.global_position.distance_to(hanan.global_position) <= dawn_radius:
			other.unfreeze()
			_frozen_gods.erase(index)


# Tala's star: every star_interval of her being live she throws one slow star at
# the nearest mortal in the common field. It freezes whoever it hits, and fades
# on the mortals' base, at the field's edge or after star_life.
func _tick_stars(delta: float) -> void:
	var tala := _god_by_id(&"tala")
	if tala != null and star_interval > 0.0 and not tala.is_frozen():
		_star_cd -= delta
		if _star_cd <= 0.0:
			_star_cd = star_interval
			_throw_star(tala.global_position)
	for at in range(_stars.size() - 1, -1, -1):
		var star: Dictionary = _stars[at]
		star["pos"] = (star["pos"] as Vector2) + (star["vel"] as Vector2) * delta
		star["left"] = float(star["left"]) - delta
		var pos: Vector2 = star["pos"]
		var gone := float(star["left"]) <= 0.0 or _on_my_base(pos) or (_field.size != Vector2.ZERO and not _field.has_point(pos))
		if not gone:
			for entry in mortal_entries():
				var mortal_id := int(entry["id"])
				if _taggable(mortal_id, entry["pos"]) and pos.distance_to(entry["pos"]) <= star_radius + player.radius:
					_freeze_mortal(mortal_id, pos)
					gone = true
					break
		if gone:
			_stars.remove_at(at)


func _throw_star(from: Vector2) -> void:
	var best := Vector2.INF
	for entry in mortal_entries():
		var pos: Vector2 = entry["pos"]
		if not _taggable(int(entry["id"]), pos) or _in_bathala_base(pos):
			continue
		if best == Vector2.INF or pos.distance_squared_to(from) < best.distance_squared_to(from):
			best = pos
	if best == Vector2.INF:
		return
	_stars.append({"pos": from, "vel": (best - from).normalized() * star_speed, "left": star_life})


# Mortals standing in Bathala's base hold the capture. A frozen mortal holds
# nothing. More holders hold faster, and the pitied mortal's hold is shorter.
func _check_capture(delta: float) -> void:
	if _bathala_base == Vector2.ZERO:
		return
	var holders: Array[int] = []
	_holder_pos = Vector2.INF
	for entry in mortal_entries():
		var mortal_id := int(entry["id"])
		if not _is_frozen(mortal_id) and _in_bathala_base(entry["pos"]):
			holders.append(mortal_id)
			if _holder_pos == Vector2.INF:
				_holder_pos = entry["pos"]
	_holders = holders.size()
	if holders.is_empty():
		_hold_progress = 0.0
		return
	_hold_progress += delta / hold_needed(holders)
	if _hold_progress >= 1.0:
		_capture_base(holders)


# Seconds `holders` need to catch Bathala's base.
func hold_needed(holders: Array) -> float:
	var hold := pity_hold if _pity_id >= 0 and holders.has(_pity_id) else hold_to_capture
	return maxf(0.05, hold / (1.0 + team_hold_bonus * (holders.size() - 1)))


func _capture_base(holders: Array[int]) -> void:
	var mult := judgment_mult if _judgment else 1
	for id in _field_mortal_ids():
		if holders.has(int(id)):
			bank_favor(capture_favor * mult, "Caught Bathala's base", int(id))
		else:
			bank_favor(capture_share_favor * mult, "Your team caught the base", int(id))
	_end_round("BASE CAPTURED!", UITokens.GOLD)


# An attacking god that stays live inside the mortals' base takes it.
func _check_base_raid(delta: float) -> void:
	var raiding := false
	for god_node in _gods:
		if god_node.role == AgawanGod.Role.ATTACK and not god_node.is_frozen() and _on_my_base(god_node.global_position):
			raiding = true
			break
	if not raiding:
		_god_hold = 0.0
		return
	_god_hold += delta / maxf(0.05, god_hold_to_capture)
	if _god_hold >= 1.0:
		for id in _field_mortal_ids():
			lose_favor(base_lost_favor, "Your base fell", int(id))
		_end_round("YOUR BASE HAS FALLEN!", UITokens.EMBER)


# Either capture: the banner, the field stands still for round_pause, and the
# gods grow wary. The reset itself waits for the pause to end (_start_round).
func _end_round(banner: String, color: Color) -> void:
	_hold_progress = 0.0
	_holders = 0
	_holder_pos = Vector2.INF
	_god_hold = 0.0
	_stars.clear()
	_wary += 1
	_round += 1
	_pause = maxf(0.01, round_pause)
	_show_banner(banner, color, round_pause)
	if _authority and _net != null and _net.has_multiplayer_peer():
		_publish_god_state()
		_publish_layout()


# The pause is over: everyone back to spawn and the round's "3 - 2 - 1".
func _start_round() -> void:
	arena_round_reset()
	_count = countdown_time
	_round_count_shown = -1
	_on_round_count_began()


func _tick_round_count(delta: float) -> void:
	_count -= delta
	var shown := int(ceil(maxf(0.0, _count)))
	if shown != _round_count_shown:
		_round_count_shown = shown
		if shown > 0:
			_show_banner(str(shown), UITokens.GOLD, 1.0)
	if _count <= 0.0:
		_count = 0.0
		_show_banner("GO!", UITokens.GOLD, 1.0)


# Every screen, as a round's count begins: our mortal back to its spawn, and the
# round callout.
func _on_round_count_began() -> void:
	player.global_position = _start_position
	_callout("ROUND %d · BATHALA GROWS WARY" % _round if _wary > 0 else "ROUND %d" % _round)


func _begin_judgment() -> void:
	_judgment = true
	_show_banner("ANG HULING PAGHUHUSGA", UITokens.GOLD, 2.0)
	_on_judgment_began()


# Every screen: the border turns gold and Bathala speaks - a callout, not a dialogue.
func _on_judgment_began() -> void:
	_apply_tint()
	_callout("BATHALA: \"Now I judge you.\"")


# --- THE MORTAL'S ATTACK -----------------------------------------------------
# Left click / the `attack` action: one swing that reaches tag_radius. Whatever it
# touches decides what happens (see the header).

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
	if _shock_cd > 0.0:
		_log("Attack recharging  (%.1fs)" % _shock_cd, UITokens.GOLD)
		return
	_shock_cd = attack_cooldown
	var origin := player.global_position
	var wave := _spawn_shockwave(origin)
	if _authority:
		_start_shock(origin, _my_id, wave)
		if _net != null:
			_net.send_arena_shock(_my_id, origin)
	elif _net != null and _net.has_multiplayer_peer():
		_net.rpc_id(1, "request_arena_shock", origin)


# A live god's touch (or Hanan's dawn) thaws a frozen god at once.
func _freeze_god(index: int, seconds: float, caster_id: int = -1) -> void:
	var god_node: AgawanGod = _gods[index]
	god_node.freeze_for(seconds)
	_frozen_gods[index] = seconds
	bank_favor(tag_god_favor, "Tagged a god", caster_id)
	_show_banner("GOD FROZEN!", UITokens.GOLD, 1.2)

# The host spawns a shockwave at `origin` and tracks its growth for hit checks.
func _spawn_shockwave(origin: Vector2) -> MayariShockwave:
	if shocks_root == null:
		return null
	var wave: MayariShockwave = SHOCK_SCENE.instantiate()
	shocks_root.add_child(wave)
	wave.global_position = origin
	wave.expand_time = shock_expand_time
	wave.max_scale = shock_radius / maxf(0.01, wave.base_radius)
	return wave

# The host's copy of a wave: it grows the real area and resolves hits.
func _start_shock(origin: Vector2, caster_id: int, wave: MayariShockwave) -> void:
	wave.set_manual_animation(true)
	_shocks.append({"origin": origin, "radius": wave.reach(), "caster": caster_id, "wave": wave, "hit": {}})


# Advance every tracked wave, resolving god freezes, mortal thaws and star breaks.
# Runs on the host (authority) only; clients self-animate their own visual waves.
func _tick_shocks(delta: float) -> void:
	if _shocks.is_empty():
		return
	var alive: Array = []
	for shock in _shocks:
		var wave: MayariShockwave = shock.get("wave")
		var radius := wave.advance(delta) if is_instance_valid(wave) else float(shock.get("radius", 0.0))
		# Freeze enemy gods in reach (never one safe in Bathala's base).
		for index in range(_gods.size()):
			var god_node: AgawanGod = _gods[index]
			if not is_instance_valid(god_node):
				continue
			var hit_key := str(god_node.god_id)
			if shock.get("hit", {}).has(hit_key):
				continue
			if _in_bathala_base(god_node.global_position):
				continue  # a god is safe on its own base
			if god_node.is_frozen():
				continue
			if shock["origin"].distance_to(god_node.global_position) <= radius + 18.0:
				shock.get("hit", {})[hit_key] = true
				_freeze_god(index, god_node.god_freeze_time, int(shock["caster"]))
		# Thaw frozen ally mortals in reach.
		for entry in mortal_entries():
			var mortal_id := int(entry["id"])
			if shock.get("hit", {}).has(mortal_id):
				continue
			var pos = entry["pos"]
			if pos == Vector2.INF:
				continue
			if _is_frozen(mortal_id) and pos.distance_to(shock["origin"]) <= radius + player.radius:
				shock.get("hit", {})[mortal_id] = true
				_thaw_mortal(mortal_id)
				bank_favor(unfreeze_favor, "Unfroze an ally", int(shock["caster"]))
				spawn_popup("THAWED", Arena.POPUP_GAIN_COLOR, popup_origin(mortal_id))
		# Break Tala's stars in reach.
		for at in range(_stars.size() - 1, -1, -1):
			if (_stars[at]["pos"] as Vector2).distance_to(shock["origin"]) <= radius + star_radius:
				_stars.remove_at(at)
				bank_favor(star_break_favor, "Broke Tala's star", int(shock["caster"]))
		if is_instance_valid(wave) and not wave.is_finished():
			alive.append(shock)
	_shocks = alive

# A god releases a shockwave on a 5s cooldown: it tags (freezes) enemy gods
# not at Bathala's base, and thaws (unfreezes) frozen ally gods within reach.
# Runs on the host (authority) only.
func _tick_god_shocks(delta: float) -> void:
	for index in range(_gods.size()):
		var god_node: AgawanGod = _gods[index]
		if not is_instance_valid(god_node) or god_node.is_frozen():
			continue
		god_node._shock_timer = maxf(0.0, god_node._shock_timer - delta)
		if god_node._shock_timer > 0.0:
			continue
		# Look for any target: an enemy god to freeze (not at Bathala's base)
		# or a frozen ally god to thaw.
		var has_target := false
		for other_index in range(_gods.size()):
			var other: AgawanGod = _gods[other_index]
			if not is_instance_valid(other) or other == god_node:
				continue
			if god_node.global_position.distance_to(other.global_position) > god_node.shock_radius:
				continue
			if other.is_frozen():
				if god_node.role == other.role:
					has_target = true
					break
			else:
				if god_node.role != other.role and not _in_bathala_base(other.global_position):
					has_target = true
					break
		if has_target:
			god_node.release_shock()
			_resolve_god_shock(god_node, index)

# Resolve a fired god shockwave: freeze enemy gods, thaw ally gods.
func _resolve_god_shock(god_node: AgawanGod, caster_index: int) -> void:
	var radius := god_node.shock_radius + 18.0
	for other_index in range(_gods.size()):
		var other: AgawanGod = _gods[other_index]
		if not is_instance_valid(other) or other == god_node:
			continue
		if god_node.global_position.distance_to(other.global_position) > radius:
			continue
		if other.is_frozen():
			# Thaw a frozen ally god.
			if god_node.role == other.role:
				other.unfreeze()
				_frozen_gods.erase(other_index)
		else:
			# Freeze an enemy god, never one safe at Bathala's base.
			if god_node.role != other.role and not _in_bathala_base(other.global_position):
				_freeze_god(other_index, other.god_freeze_time, -1)


# A client attacked: the host grows the real wave here and shares it.
func _on_arena_shock_requested(caster_id: int, origin: Vector2) -> void:
	if not _authority or _phase != Phase.PLAYING:
		return
	var known := mortal_position(caster_id)
	if known != Vector2.INF and known.distance_to(origin) > 90.0:
		return  # the attack is nowhere near where the host last saw that mortal
	var wave := _spawn_shockwave(known if known != Vector2.INF else origin)
	if wave == null:
		return
	_start_shock(known if known != Vector2.INF else origin, caster_id, wave)
	if _net != null:
		_net.send_arena_shock(caster_id, known if known != Vector2.INF else origin)

# The wave every screen draws. It uses the same size and timing as the rules.
func _on_arena_shock_received(caster_id: int, origin: Vector2) -> void:
	if caster_id == _my_id:
		return
	_spawn_shockwave(origin)


# --- NETWORK (the gods and the freezes travel to every screen) ---------------

func _connect_network() -> void:
	super._connect_network()
	if _net == null:
		return
	if _net.has_signal("arena_shock_received"):
		_net.connect("arena_shock_received", _on_arena_shock_received)
	if _authority and _net.has_signal("arena_shock_requested"):
		_net.connect("arena_shock_requested", _on_arena_shock_requested)




# The fixed world that only travels once per round: where the two bases are, the
# roster (which god is in which slot, and its role) and the round.
func arena_layout_fields() -> Dictionary:
	var gods: Array = []
	for god_node in _gods:
		gods.append({"id": str(god_node.god_id), "role": int(god_node.role), "pos": [god_node.global_position.x, god_node.global_position.y]})
	return {"mine": [_my_base.x, _my_base.y], "bathala": [_bathala_base.x, _bathala_base.y], "gods": gods, "round": _round, "wary": _wary}


func arena_read_layout(layout: Dictionary) -> void:
	var mine: Array = layout.get("mine", [])
	if mine.size() == 2:
		_my_base = Vector2(float(mine[0]), float(mine[1]))
	var bathala: Array = layout.get("bathala", [])
	if bathala.size() == 2:
		_bathala_base = Vector2(float(bathala[0]), float(bathala[1]))
	_round = int(layout.get("round", _round))
	_wary = int(layout.get("wary", _wary))
	var gods: Array = layout.get("gods", [])
	# The host's roster wins: rebuild only when this screen guessed another one.
	var ids: Array = []
	for entry in gods:
		ids.append(str((entry as Dictionary).get("id", "")))
	if not ids.is_empty() and ids != roster_ids():
		ids.erase("bathala")
		_build_gods(ids)
	for index in range(mini(gods.size(), _gods.size())):
		var entry: Dictionary = gods[index]
		var god_node: AgawanGod = _gods[index]
		god_node.role = entry.get("role", AgawanGod.Role.ATTACK) as int
		var pos: Array = entry.get("pos", [])
		if pos.size() == 2:
			god_node.place(Vector2(float(pos[0]), float(pos[1])))
		god_node._refresh_visual()
	_apply_tint()  # the base re-tints the field with the god's grey on every layout


# The fast per-tick state: each god's pose, freeze and trait, the frozen mortals,
# both holds, Tala's stars, Hanan's dawn, and the finale's state. The host runs
# the rules; the clients only draw this.
func arena_tick_fields() -> Dictionary:
	var gods: Array = []
	for god_node in _gods:
		gods.append({
			"pos": [god_node.global_position.x, god_node.global_position.y],
			"frozen": god_node.is_frozen(),
			"left": god_node.freeze_left,
			"windup": god_node.windup,
			"lunge": [god_node.lunge_dir.x, god_node.lunge_dir.y],
			"pulse": god_node.pulse_flash,
		})
	var frozen: Dictionary = {}
	for mortal_id in _frozen_mortals.keys():
		frozen[str(mortal_id)] = float(_frozen_mortals[mortal_id])
	var stars: Array = []
	for star in _stars:
		stars.append([(star["pos"] as Vector2).x, (star["pos"] as Vector2).y])
	return {
		"gods": gods, "frozen": frozen,
		"hold": _hold_progress, "holders": _holders, "god_hold": _god_hold,
		"stars": stars, "dawn": _dawn_timer, "wary": _wary, "pity": _pity_id,
		"judgment": _judgment, "pause": _pause, "count": _count, "round": _round,
	}


func arena_read_tick(state: Dictionary) -> void:
	var gods: Array = state.get("gods", [])
	for index in range(mini(gods.size(), _gods.size())):
		var entry: Dictionary = gods[index]
		var god_node: AgawanGod = _gods[index]
		var pos: Array = entry.get("pos", [])
		if pos.size() == 2:
			god_node.place(Vector2(float(pos[0]), float(pos[1])))
		if bool(entry.get("frozen", false)):
			god_node.freeze_for(float(entry.get("left", 0.0)))
		else:
			god_node.unfreeze()
		god_node.windup = float(entry.get("windup", 0.0))
		var lunge: Array = entry.get("lunge", [])
		if lunge.size() == 2:
			god_node.lunge_dir = Vector2(float(lunge[0]), float(lunge[1]))
		god_node.pulse_flash = float(entry.get("pulse", 0.0))
		god_node._refresh_visual()
	_frozen_mortals.clear()
	var frozen: Dictionary = state.get("frozen", {})
	for key in frozen.keys():
		_frozen_mortals[int(key)] = float(frozen[key])
	_hold_progress = float(state.get("hold", 0.0))
	_holders = int(state.get("holders", 0))
	_god_hold = float(state.get("god_hold", 0.0))
	_stars.clear()
	for star in state.get("stars", []):
		_stars.append({"pos": Vector2(float(star[0]), float(star[1])), "vel": Vector2.ZERO, "left": 1.0})
	_dawn_timer = float(state.get("dawn", _dawn_timer))
	_wary = int(state.get("wary", _wary))
	_pity_id = int(state.get("pity", -1))
	_round = int(state.get("round", _round))
	_pause = float(state.get("pause", 0.0))
	var count := float(state.get("count", 0.0))
	if count > 0.0 and _count <= 0.0:
		_on_round_count_began()
	_count = count
	var judgment := bool(state.get("judgment", false))
	if judgment and not _judgment:
		_judgment = true
		_on_judgment_began()


# --- FRAME / HUD -------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	_shock_cd = maxf(0.0, _shock_cd - delta)
	_refresh_lock()
	_refresh_marks()
	_refresh_hud(delta)


# Frozen means frozen, on every screen: while our id is frozen (or the field
# stands still between rounds) our mortal is locked. Only a lock this script set
# is ever lifted here - the intro, the countdown and the results keep theirs.
func _refresh_lock() -> void:
	var want := _phase == Phase.PLAYING and (_is_frozen(_my_id) or _pause > 0.0 or _count > 0.0)
	if want and not player.locked:
		player.set_lock(true)
		_rule_lock = true
	elif not want and _rule_lock:
		_rule_lock = false
		if _phase == Phase.PLAYING:
			player.set_lock(false)


# The world marks every screen draws from the host's state: a 5-4-3-2-1 over
# each frozen mortal, the pity tag, both hold rings and Tala's stars.
func _refresh_marks() -> void:
	if marks_root != null:
		for id in _frozen_mortals.keys():
			var label: Label = _mark_labels.get(id)
			if not is_instance_valid(label):
				label = Label.new()
				label.theme_type_variation = &"WorldValue"
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				label.size = Vector2(60, 24)
				label.add_theme_color_override("font_color", UITokens.EMBER)
				marks_root.add_child(label)
				_mark_labels[id] = label
			var origin := popup_origin(int(id)) - POPUP_OFFSET
			label.visible = origin != Vector2.INF
			label.global_position = origin + MARK_OFFSET
			label.text = "%d" % int(ceil(float(_frozen_mortals[id])))
		for id in _mark_labels.keys().duplicate():
			if not _frozen_mortals.has(id):
				_mark_labels[id].queue_free()
				_mark_labels.erase(id)
	if pity_label != null:
		var at := popup_origin(_pity_id) if _pity_id >= 0 else Vector2.INF
		pity_label.visible = at != Vector2.INF and _phase == Phase.PLAYING
		if pity_label.visible:
			pity_label.global_position = at - POPUP_OFFSET + PITY_OFFSET
			pity_label.add_theme_color_override("font_color", UITokens.GOLD)
	if bathala_hold_ring != null:
		bathala_hold_ring.points = _arc(base_radius + 6.0, _hold_progress)
	if mine_hold_ring != null:
		mine_hold_ring.points = _arc(base_radius + 6.0, _god_hold)
	if stars_root != null:
		while _star_nodes.size() < _stars.size():
			var node := Sprite2D.new()
			node.texture = Arena.TEMP_ICON
			node.scale = Vector2(0.16, 0.16)
			node.modulate = UITokens.STAR
			stars_root.add_child(node)
			_star_nodes.append(node)
		for index in range(_star_nodes.size()):
			_star_nodes[index].visible = index < _stars.size()
			if index < _stars.size():
				_star_nodes[index].global_position = _stars[index]["pos"]
				_star_nodes[index].rotation += 0.15


# A ring that fills clockwise from the top as `fraction` goes 0 -> 1.
func _arc(radius: float, fraction: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := int(ceil(clampf(fraction, 0.0, 1.0) * 32.0))
	if steps <= 0:
		return points
	for index in range(steps + 1):
		var angle := -PI / 2.0 + TAU * clampf(fraction, 0.0, 1.0) * index / steps
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


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
		# Blindside: the leading opponent's screen dims, the way Mayari's Half Vision does.
		_fire_curse_blind(caster_id, favor)
	elif favor.id == &"siblings_compromise_bathala" and _authority:
		rules.cast_siblings_compromise(caster_id, favor)
		_publish_god_state()
		return  # Vantage Point cuts your own FAVOR and blinds nobody
	else:
		super._apply_skill_effect(favor, caster_id)


# The two INSTANT curses ("Our Partnership Ends Here"): the host pays the cost and
# marks the curse, then EVERY other mortal's screen - teammates included, the
# betrayal is the point - carries Mayari's blindness or Apolaki's Sun Patches for
# the promise's duration.
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


# The code paints only Bathala's gold: the field border glows GOLD_LO, and the
# full gold once the final judgment begins.
func _apply_tint() -> void:
	if field_root != null:
		field_root.apply_tint(UITokens.GOLD_HI if _judgment else UITokens.GOLD_LO)


func _callout(text: String) -> void:
	if callout_label == null:
		return
	callout_label.text = text
	callout_label.add_theme_color_override("font_color", UITokens.god_text(god))
	callout_label.visible = true
	_callout_left = callout_time


func _refresh_hud(delta: float) -> void:
	if status_label != null:
		var here := player.global_position
		var stance := "FROZEN %d" % int(ceil(float(_frozen_mortals[_my_id]))) if _is_frozen(_my_id) \
			else ("DEFENDING" if _on_my_base(here) else ("CAPTURING!" if _in_bathala_base(here) else "ON THE FIELD"))
		var swing := "ATTACK READY" if _shock_cd <= 0.0 else "ATTACK %.1fs" % _shock_cd
		var judged := "     FINAL JUDGMENT" if _judgment else ""
		status_label.text = "%s     %s     ROUND %d%s" % [stance, swing, _round, judged]
		status_label.add_theme_color_override("font_color", UITokens.god_text(god))
	if hint_label != null:
		hint_label.text = "CLICK - ATTACK (freeze a god / thaw an ally)     E / Q - FAVORS     F - GOD'S DUE"
	if callout_label != null and _callout_left > 0.0:
		_callout_left -= delta
		if _callout_left <= 0.0:
			callout_label.visible = false
