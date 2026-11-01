class_name RunSettings
extends RefCounted

# Everything the host sets up in the lobby before pressing START: how many trials,
# in what order, how long each lasts, how long the rest between two trials lasts,
# how often FAVOR pays a God's Due, how much the gods say when they open a trial,
# whether the story cutscene opens the run
# and what the camera shows.
#
# One object for all of it so the lobby, the network sync, the saved
# user://lobby_settings.cfg and the game shell can never disagree: the host edits
# a RunSettings, Network sends its to_dict() to every peer, and Game.gd reads the
# same fields when it builds each arena.
#
# Bathala's finale is never part of `trials` or `custom_order`: it is always
# appended last by planned_order(), so it cannot be removed, moved or counted.

const ORDER_RANDOM := "random"
const ORDER_CUSTOM := "custom"
const INTRO_FULL := "full"    # a god's full intro on its first visit, the short line after
const INTRO_SHORT := "short"  # always the short "take your place" line
const OPENING_FULL := "full"  # the story cutscene plays before the first trial
const OPENING_SKIP := "skip"  # straight to the first god
const TRIAL_TIMES := [60.0, 90.0, 120.0, 150.0]
const PREP_TIMES := [10.0, 20.0, 30.0, 45.0, 60.0]  # the preparation area (PAHINGA)
const DUE_STEPS := [750, 1000, 1500]
const DEFAULT_TRIAL_TIME := 90.0
const DEFAULT_PREP_TIME := 20.0
const CAMERA_ARENA := "arena"    # the whole field at once, world = screen (the default)
const CAMERA_FOLLOW := "follow"  # a Camera2D on the local mortal (Arena.follow_camera)
const STARTER_OFF := "off"       # every mortal starts with empty hands
const STARTER_RANDOM := "random" # each mortal draws its own E and Q
const STARTER_CUSTOM := "custom" # each player picks its own two in the lobby

var trials: int = Gods.TRIALS_DEFAULT
var order_mode: String = ORDER_RANDOM
var custom_order: Array[StringName] = []  # one god per trial slot, Bathala excluded
var trial_time: float = DEFAULT_TRIAL_TIME
var prep_time: float = DEFAULT_PREP_TIME
var due_step: int = GodMatch.MILESTONE_STEP
var intro_mode: String = INTRO_FULL
var opening_cutscene: String = OPENING_FULL
# Each god's blitz (last-stand mode) can be switched off here; default is on.
var god_blitz_mode: bool = true
# Only what this screen draws: the host's rules never read the camera.
var camera_mode: String = CAMERA_ARENA
# STARTER SKILLS: what every mortal opens the run holding. RANDOM deals each
# mortal a unique pair from the host's seed; CUSTOM lets each player pick its own
# two in the lobby (Network.custom_builds), not a shared run-wide pair. The host
# draws the seed at START and it rides the setup to every peer.
var starter_mode: String = STARTER_OFF
var starter_seed: int = 0


static func defaults() -> RunSettings:
	var settings := RunSettings.new()
	settings.validate()
	return settings


func to_dict() -> Dictionary:
	var order: Array = []
	for god_id in custom_order:
		order.append(str(god_id))
	return {
		"trials": trials,
		"order_mode": order_mode,
		"custom_order": order,
		"trial_time": trial_time,
		"prep_time": prep_time,
		"due_step": due_step,
		"intro_mode": intro_mode,
		"opening_cutscene": opening_cutscene,
		"god_blitz_mode": god_blitz_mode,
		"camera_mode": camera_mode,
		"starter_mode": starter_mode,
		"starter_seed": starter_seed,
	}


# Raw copy of whatever arrived (a peer, a saved file): call validate() before
# trusting it.
static func from_dict(data: Dictionary) -> RunSettings:
	var settings := RunSettings.new()
	settings.trials = int(data.get("trials", Gods.TRIALS_DEFAULT))
	settings.order_mode = str(data.get("order_mode", ORDER_RANDOM))
	var order = data.get("custom_order", [])
	if order is Array:
		for god_id in order:
			settings.custom_order.append(StringName(str(god_id)))
	settings.trial_time = float(data.get("trial_time", DEFAULT_TRIAL_TIME))
	settings.prep_time = float(data.get("prep_time", DEFAULT_PREP_TIME))
	settings.due_step = int(data.get("due_step", GodMatch.MILESTONE_STEP))
	settings.intro_mode = str(data.get("intro_mode", INTRO_FULL))
	settings.opening_cutscene = str(data.get("opening_cutscene", OPENING_FULL))
	settings.god_blitz_mode = bool(data.get("god_blitz_mode", true))
	settings.camera_mode = str(data.get("camera_mode", CAMERA_ARENA))
	# A file saved before CUSTOM loadouts existed only knew "starter_skills".
	var legacy_random := bool(data.get("starter_skills", false))
	settings.starter_mode = str(data.get("starter_mode", STARTER_RANDOM if legacy_random else STARTER_OFF))
	settings.starter_seed = int(data.get("starter_seed", 0))
	return settings


# Puts every field back inside the rules: trials 3..6, only known choices for the
# times / steps / modes, custom_order made of playable gods and exactly `trials`
# long (new slots are filled with gods not playing yet, extra ones are cut from
# the end). With `fix_repeats` it also replaces a god that already plays in an
# earlier slot - every god hosts at most one trial of a run.
#
# The lobby passes fix_repeats = false while the host is editing: a repeat that
# arrived some other way must stay on screen as a warning (and keep START
# disabled) rather than being silently changed under them. Returns the problems
# that are left - an empty array means the run can start.
func validate(fix_repeats := true) -> Array[String]:
	trials = clampi(trials, Gods.TRIALS_MIN, Gods.TRIALS_MAX)
	if order_mode != ORDER_CUSTOM:
		order_mode = ORDER_RANDOM
	if intro_mode != INTRO_SHORT:
		intro_mode = INTRO_FULL
	if opening_cutscene != OPENING_SKIP:
		opening_cutscene = OPENING_FULL
	if not TRIAL_TIMES.has(trial_time):
		trial_time = DEFAULT_TRIAL_TIME
	if not PREP_TIMES.has(prep_time):
		prep_time = DEFAULT_PREP_TIME
	if camera_mode != CAMERA_FOLLOW:
		camera_mode = CAMERA_ARENA
	if not DUE_STEPS.has(due_step):
		due_step = GodMatch.MILESTONE_STEP
	if starter_mode != STARTER_RANDOM and starter_mode != STARTER_CUSTOM:
		starter_mode = STARTER_OFF
	var playable := playable_ids()
	var kept: Array[StringName] = []
	for god_id in custom_order:
		if playable.has(god_id):
			kept.append(god_id)
	custom_order = kept
	if custom_order.size() > trials:
		custom_order.resize(trials)
	while custom_order.size() < trials and not playable.is_empty():
		custom_order.append(next_god(custom_order))
	if fix_repeats:
		for index in repeat_slots():
			for god_id in playable:
				if not custom_order.has(god_id):
					custom_order[index] = god_id
					break
	return problems()


# What would stop the run, without changing anything.
func problems() -> Array[String]:
	var found: Array[String] = []
	if order_mode == ORDER_CUSTOM and playable_ids().size() > 1:
		for index in repeat_slots():
			var god := Gods.by_id(custom_order[index])
			found.append("Trial %d: %s already plays in trial %d" % [index + 1,
				god.display_name if god != null else str(custom_order[index]), custom_order.find(custom_order[index]) + 1])
	return found


# Indexes of the custom slots whose god already plays in an earlier slot.
func repeat_slots() -> Array[int]:
	var slots: Array[int] = []
	for index in range(1, custom_order.size()):
		if custom_order.slice(0, index).has(custom_order[index]):
			slots.append(index)
	return slots


# The full run: one god per trial, then Bathala. RANDOM draws a fresh order every
# call (the host draws once, at START, and sends the result to everyone).
func planned_order() -> Array[StringName]:
	var order: Array[StringName] = custom_order.duplicate() if order_mode == ORDER_CUSTOM else draw_order(trials)
	order.append(Gods.BATHALA)
	return order


# Every god a trial can be played against. Bathala never is - it closes the run.
static func playable_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for god in Gods.all():
		if god.id != Gods.BATHALA and god.implemented and god.arena_scene != "":
			ids.append(god.id)
	return ids


# The god that should come next after `order`: one that has not played yet when
# there is one (the one that has waited longest otherwise), and never the god just
# played (nor `avoid`, the slot after it) when another is available.
static func next_god(order: Array[StringName], avoid: StringName = &"") -> StringName:
	var playable := playable_ids()
	if playable.is_empty():
		return Gods.MAYARI
	var last: StringName = order[order.size() - 1] if not order.is_empty() else &""
	var best: StringName = &""
	var best_seen := INF
	for god_id in playable:
		if playable.size() > 1 and god_id == last:
			continue
		if playable.size() > 2 and god_id == avoid:
			continue
		var seen := float(order.rfind(god_id))
		if seen < best_seen:
			best_seen = seen
			best = god_id
	return best if best != &"" else playable[0]


# A random run of `count` gods, each playable god at most once (a shuffled pool;
# only a run longer than the pool - fewer playable gods than TRIALS_MAX - opens a
# second pool, never on the god that just played). Shared by the host's draw and
# the offline game shell.
static func draw_order(count: int) -> Array[StringName]:
	var playable := playable_ids()
	if playable.is_empty():
		playable.append(Gods.MAYARI)
	var order: Array[StringName] = []
	var pool: Array[StringName] = []
	for index in range(count):
		if pool.is_empty():
			pool = playable.duplicate()
			pool.shuffle()
			if pool.size() > 1 and not order.is_empty() and pool[0] == order[order.size() - 1]:
				var swap := randi_range(1, pool.size() - 1)
				pool[0] = pool[swap]
				pool[swap] = order[order.size() - 1]
		order.append(pool.pop_front())
	return order


# What every mortal opens the run holding, keyed by mortal id. RANDOM deals the
# shuffled pools so no two mortals open with the same pair. CUSTOM is each
# player's own build (Network.build_favors), so it deals nothing here. The host
# runs this once, from one seed, so the deal is the same on every screen.
func starter_deal(mortal_ids: Array) -> Dictionary:
	var ids: Array[int] = []
	for id in mortal_ids:
		ids.append(int(id))
	ids.sort()
	if starter_mode != STARTER_RANDOM:
		return {}
	return starter_deal_for(starter_seed, ids)


# One random god's E and a DIFFERENT god's Q for each mortal, from `seed_value`.
# Dealing from one shuffled pool - instead of drawing per mortal - is what makes
# the sets unique: a favor is taken out of the pool once, and only a run with more
# mortals than starter favors sees one come round again.
static func starter_deal_for(seed_value: int, mortal_ids: Array) -> Dictionary:
	var ids: Array[int] = []
	for id in mortal_ids:
		ids.append(int(id))
	ids.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var es := starter_pool(GodFavor.Slot.E)
	var qs := starter_pool(GodFavor.Slot.Q)
	_shuffle(es, rng)
	_shuffle(qs, rng)
	var used_e := {}
	var used_q := {}
	var deal := {}
	for id in ids:
		var e := _deal_favor(es, used_e, &"")
		var q := _deal_favor(qs, used_q, e.god_id if e != null else &"")
		if e == null or q == null:
			continue
		used_e[e.id] = true
		used_q[q.id] = true
		var pair: Array[GodFavor] = [e, q]
		deal[id] = pair
	return deal


# Every favor a starter can draw: an implemented god's, in its slot, that asks
# for nothing else to be held first. Bathala's are never in it - he closes the run.
static func starter_pool(slot: int) -> Array[GodFavor]:
	var pool: Array[GodFavor] = []
	for god in Gods.all():
		if god.id == Gods.BATHALA or not god.implemented:
			continue
		pool.append_array(_starter_favors_of(god, slot))
	return pool


# The pick a CUSTOM loadout falls back to when its box was left unselected:
# Mayari's own E or Q.
static func default_starter(slot: int) -> GodFavor:
	var mayari := Gods.mayari()
	if mayari == null:
		return null
	var favors := _starter_favors_of(mayari, slot)
	return favors[0] if not favors.is_empty() else null


# The starter favor with this id in this slot, or null when a CUSTOM build may
# not pick it (another slot, a favor that asks for something to be held first).
static func starter_favor(slot: int, favor_id: StringName) -> GodFavor:
	if favor_id == &"":
		return null
	for favor in starter_pool(slot):
		if favor.id == favor_id:
			return favor
	return null


# An unused favor, preferring one from a different god than the partner
# (`avoid_god`); once the pool is spent, a used one comes round again.
static func _deal_favor(pool: Array[GodFavor], used: Dictionary, avoid_god: StringName) -> GodFavor:
	if pool.is_empty():
		return null
	for favor in pool:
		if not used.has(favor.id) and favor.god_id != avoid_god:
			return favor
	for favor in pool:
		if favor.god_id != avoid_god:
			return favor
	return pool[0]


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for index in range(items.size() - 1, 0, -1):
		var swap := rng.randi_range(0, index)
		var held = items[index]
		items[index] = items[swap]
		items[swap] = held


static func _starter_favors_of(god: God, slot: int) -> Array[GodFavor]:
	var open: Array[GodFavor] = []
	for favor in god.favors:
		if favor.slot != slot:
			continue
		if favor.requires_favor_id() != &"" or favor.requires_slot() >= 0:
			continue
		if favor.requires_god_id() != &"" or not favor.requires_any_god_ids().is_empty():
			continue
		open.append(favor)
	return open


# The run as text, e.g. "Mayari -> Tala -> Apolaki -> BATHALA". A random run
# shows one RANDOM per trial, since its gods are only drawn at START. An
# unwanted visitor is never named: the plan shows "??? - ???".
func run_line() -> String:
	var names: Array[String] = []
	for index in range(trials):
		if order_mode == ORDER_CUSTOM and index < custom_order.size():
			var god := Gods.by_id(custom_order[index])
			if god != null and god.hidden_visitor:
				names.append("??? - ???")
			else:
				names.append(god.display_name.capitalize() if god != null else str(custom_order[index]))
		else:
			names.append("Random")
	names.append("BATHALA")
	return "  ->  ".join(names)


# Whether the run hands out opening favors at all.
func has_starters() -> bool:
	return starter_mode == STARTER_RANDOM or starter_mode == STARTER_CUSTOM


# The one-line read-only summary everyone sees under the player list.
func summary() -> String:
	var line := "%d trials + Bathala   |   %s order   |   %ds" % [
		trials, "Custom" if order_mode == ORDER_CUSTOM else "Random", int(trial_time)]
	if starter_mode == STARTER_RANDOM:
		line += "   |   random starters"
	elif starter_mode == STARTER_CUSTOM:
		line += "   |   custom builds"
	return line
