class_name RunSettings
extends RefCounted

# Everything the host sets up in the lobby before pressing START: how many trials,
# in what order, how long each lasts, how often FAVOR pays a God's Due and how
# much the gods say when they open a trial.
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
const TRIAL_TIMES := [60.0, 90.0, 120.0, 150.0]
const DUE_STEPS := [750, 1000, 1500]
const DEFAULT_TRIAL_TIME := 90.0

var trials: int = Gods.TRIALS_DEFAULT
var order_mode: String = ORDER_RANDOM
var custom_order: Array[StringName] = []  # one god per trial slot, Bathala excluded
var trial_time: float = DEFAULT_TRIAL_TIME
var due_step: int = GodMatch.MILESTONE_STEP
var intro_mode: String = INTRO_FULL


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
		"due_step": due_step,
		"intro_mode": intro_mode,
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
	settings.due_step = int(data.get("due_step", GodMatch.MILESTONE_STEP))
	settings.intro_mode = str(data.get("intro_mode", INTRO_FULL))
	return settings


# Puts every field back inside the rules: trials 3..5, only known choices for the
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
	if not TRIAL_TIMES.has(trial_time):
		trial_time = DEFAULT_TRIAL_TIME
	if not DUE_STEPS.has(due_step):
		due_step = GodMatch.MILESTONE_STEP
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


# The run as text, e.g. "Mayari -> Tala -> Apolaki -> BATHALA". A random run
# shows one RANDOM per trial, since its gods are only drawn at START.
func run_line() -> String:
	var names: Array[String] = []
	for index in range(trials):
		if order_mode == ORDER_CUSTOM and index < custom_order.size():
			var god := Gods.by_id(custom_order[index])
			names.append(god.display_name.capitalize() if god != null else str(custom_order[index]))
		else:
			names.append("Random")
	names.append("BATHALA")
	return "  ->  ".join(names)


# The one-line read-only summary everyone sees under the player list.
func summary() -> String:
	return "%d trials + Bathala   |   %s order   |   %ds" % [
		trials, "Custom" if order_mode == ORDER_CUSTOM else "Random", int(trial_time)]
