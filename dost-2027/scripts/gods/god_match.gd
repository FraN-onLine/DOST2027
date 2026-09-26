class_name GodMatch
extends Node

# Rules engine for one Bathala trial (and the run of trials around it).
# It owns every mortal's FAVOR, their God's Due vouchers, the favors they hold
# and the state of their E / Q skills. Arenas push events in and listen to the
# signals, so the rules live in one place for when the other gods and the
# network layer arrive.

signal favor_changed(player_id: int, favor: int, delta: int, reason: String)
signal due_changed(player_id: int, due: int)
signal due_earned(player_id: int, due: int, milestone: int)
signal favor_granted(player_id: int, favor: GodFavor)
signal skill_used(player_id: int, favor: GodFavor)
signal skill_recharged(player_id: int, favor: GodFavor)
signal notice(text: String)
signal trial_ended(summary: Dictionary)

const MILESTONE_STEP := 1000  # every 1000 FAVOR hands out one God's Due
const LOCAL_ID := 1


class Mortal:
	var id: int = 0
	var display_name: String = "Mortal"
	var is_local: bool = false
	var favor: int = 0
	var due: int = 0
	var pending_favor: float = 0.0  # fractional FAVOR not banked yet
	var claimed_milestones: Dictionary = {}  # milestone -> true (first pass only)
	var favors: Array[GodFavor] = []
	var cooldowns: Dictionary = {}  # favor id -> seconds left
	var durations: Dictionary = {}  # favor id -> seconds left (timed effect)
	var loss_immunity: float = 0.0
	var rivalry_targets: Dictionary = {}  # player id -> already punished

	func favor_by_id(favor_id: StringName) -> GodFavor:
		for favor in favors:
			if favor.id == favor_id:
				return favor
		return null

	func has_favor(favor_id: StringName) -> bool:
		return favor_by_id(favor_id) != null

	func favor_in_slot(slot: int) -> GodFavor:
		for favor in favors:
			if int(favor.slot) == slot:
				return favor
		return null

	func cooldown_left(favor_id: StringName) -> float:
		return float(cooldowns.get(favor_id, 0.0))

	func duration_left(favor_id: StringName) -> float:
		return float(durations.get(favor_id, 0.0))


var god: God
var mortals: Dictionary = {}  # player id -> Mortal
var local_id: int = LOCAL_ID
var simulate_rivals: bool = false
var trial_active: bool = false


func setup(match_god: God, local_name: String, rival_names: Array = [], simulate := false) -> void:
	god = match_god
	mortals.clear()
	simulate_rivals = simulate
	local_id = LOCAL_ID
	mortals[local_id] = _new_mortal(local_id, local_name, true)
	var next_id := local_id + 1
	for rival_name in rival_names:
		mortals[next_id] = _new_mortal(next_id, str(rival_name), false)
		next_id += 1


func _new_mortal(id: int, display_name: String, is_local: bool) -> Mortal:
	var mortal := Mortal.new()
	mortal.id = id
	mortal.display_name = display_name
	mortal.is_local = is_local
	return mortal


func local() -> Mortal:
	return mortal(local_id)


func mortal(player_id: int) -> Mortal:
	return mortals.get(player_id, null)


func _resolve(player_id: int) -> Mortal:
	if player_id < 0:
		return local()
	return mortal(player_id)


# --- FAVOR ------------------------------------------------------------------

func gain_multiplier(m: Mortal) -> float:
	var mult := 1.0
	for favor in m.favors:
		if favor.id == &"full_moon":
			mult *= favor.param("gain_mult", 1.1)
		if favor.is_skill() and m.duration_left(favor.id) > 0.0:
			mult *= favor.param("gain_mult_while_active", 1.0)
	return mult


func loss_multiplier(m: Mortal) -> float:
	if m.loss_immunity > 0.0:
		return 0.0
	var mult := 1.0
	for favor in m.favors:
		if favor.id == &"waning_moon":
			mult *= favor.param("loss_mult", 0.5)
		if favor.is_skill() and m.duration_left(favor.id) > 0.0:
			mult *= favor.param("loss_mult_while_active", 1.0)
	return mult


func add_favor(amount: int, reason: String = "", player_id: int = -1) -> int:
	var m := _resolve(player_id)
	if m == null or amount == 0:
		return 0
	# Scale by the gain modifiers, but keep the leftover fraction pending so a
	# +10% (Full Moon) really is +10% over a run of small ticks.
	var scaled := float(amount) * gain_multiplier(m) + m.pending_favor
	var gained := int(scaled)
	m.pending_favor = scaled - float(gained)
	if gained == 0:
		return 0
	_apply(m, gained, reason)
	return gained


func lose_favor(amount: int, reason: String = "", player_id: int = -1) -> int:
	var m := _resolve(player_id)
	if m == null or amount <= 0:
		return 0
	var lost := int(round(float(amount) * loss_multiplier(m)))
	if lost <= 0:
		notice.emit("FAVOR shielded - nothing lost")
		return 0
	lost = mini(lost, m.favor)
	if lost <= 0:
		return 0
	_apply(m, -lost, reason)
	return lost


func _apply(m: Mortal, delta: int, reason: String) -> void:
	m.favor = maxi(0, m.favor + delta)
	favor_changed.emit(m.id, m.favor, delta, reason)
	_check_milestones(m)


func _check_milestones(m: Mortal) -> void:
	# A God's Due is only ever awarded on the FIRST pass of a milestone.
	var reached := int(floor(float(m.favor) / float(MILESTONE_STEP)))
	for index in range(1, reached + 1):
		if m.claimed_milestones.has(index):
			continue
		m.claimed_milestones[index] = true
		m.due += 1
		due_earned.emit(m.id, m.due, index * MILESTONE_STEP)
		due_changed.emit(m.id, m.due)


func top_player_id() -> int:
	var best_id := -1
	var best := -1
	for m in mortals.values():
		if m.favor > best:
			best = m.favor
			best_id = m.id
	return best_id


func rival_high_score(player_id: int = -1) -> int:
	var mine := _resolve(player_id)
	var best := 0
	for m in mortals.values():
		if mine != null and m.id == mine.id:
			continue
		best = maxi(best, m.favor)
	return best


# --- GOD'S DUE / FAVORS -----------------------------------------------------

func can_grant(favor: GodFavor, player_id: int = -1) -> bool:
	var m := _resolve(player_id)
	if m == null or favor == null or m.has_favor(favor.id):
		return false
	return m.due > 0


func grant_favor(favor: GodFavor, player_id: int = -1) -> bool:
	# Spend one God's Due voucher on a favor.
	var m := _resolve(player_id)
	if not can_grant(favor, player_id):
		return false
	m.due -= 1
	due_changed.emit(m.id, m.due)
	return bestow_favor(favor, player_id)


func bestow_favor(favor: GodFavor, player_id: int = -1) -> bool:
	# A god handing a favor over directly - no voucher spent.
	var m := _resolve(player_id)
	if m == null or favor == null or m.has_favor(favor.id):
		return false
	# E and Q are single slots. A newly chosen skill replaces the old skill
	# while passive and end-of-trial favors remain owned for the whole run.
	if favor.is_skill():
		for index in range(m.favors.size() - 1, -1, -1):
			if m.favors[index].slot == favor.slot:
				m.cooldowns.erase(m.favors[index].id)
				m.durations.erase(m.favors[index].id)
				m.favors.remove_at(index)
	m.favors.append(favor)
	if favor.cooldown > 0.0:
		m.cooldowns[favor.id] = 0.0
	favor_granted.emit(m.id, favor)
	if favor.kind == GodFavor.Kind.INSTANT:
		var instant := int(favor.param("instant_favor", 0.0))
		if instant != 0:
			add_favor(instant, favor.display_name, m.id)
	return true


func any_mortal_holds_god(god_id: String) -> bool:
	for m in mortals.values():
		for favor in m.favors:
			if str(favor.god_id) == god_id:
				return true
	return false


func consume_rivalry_triggers(player_id: int = -1) -> Array:
	# Mayari's "Sibling's Rivalry": mortals that just fell far enough behind get
	# marked here (once per rival, once per trial) so the arena can blind them.
	var out: Array = []
	var me := _resolve(player_id)
	if me == null:
		return out
	for favor in me.favors:
		if favor.id != &"siblings_rivalry":
			continue
		var requires := str(favor.params.get("requires_god", ""))
		if requires != "" and not any_mortal_holds_god(requires):
			continue
		var behind_by := favor.param("behind_by", float(MILESTONE_STEP))
		for other in mortals.values():
			if other.id == me.id or me.rivalry_targets.has(other.id):
				continue
			if float(other.favor - me.favor) < behind_by:
				continue
			me.rivalry_targets[other.id] = true
			out.append(other)
	return out


func set_local_id(id: int) -> void:
	local_id = id
	for m in mortals.values():
		m.is_local = m.id == id


# Multiplayer: the host builds one mortal per connected peer. Clients build the
# same list and then mirror the host numbers through apply_snapshot().
func setup_peers(match_god: God, peer_names: Dictionary, my_id: int, simulate := false) -> void:
	god = match_god
	mortals.clear()
	simulate_rivals = simulate
	local_id = my_id
	for pid in peer_names.keys():
		var id := int(pid)
		mortals[id] = _new_mortal(id, str(peer_names[pid]), id == local_id)
	if not mortals.has(local_id):
		mortals[local_id] = _new_mortal(local_id, "Mortal", true)


func ensure_mortal(id: int, display_name: String) -> Mortal:
	var m: Mortal = mortals.get(id, null)
	if m != null:
		return m
	m = _new_mortal(id, display_name, id == local_id)
	mortals[id] = m
	return m


func remove_mortal(id: int) -> void:
	mortals.erase(id)


# Absolute snapshot of every mortal - the host broadcasts this to the clients.
func snapshot() -> Dictionary:
	var out := {}
	for m in mortals.values():
		var favors: Array = []
		for favor in m.favors:
			favors.append(str(favor.id))
		var cooldowns := {}
		for favor_id in m.cooldowns.keys():
			cooldowns[str(favor_id)] = float(m.cooldowns[favor_id])
		var durations := {}
		for favor_id in m.durations.keys():
			durations[str(favor_id)] = float(m.durations[favor_id])
		out[m.id] = {
			"name": m.display_name,
			"favor": m.favor,
			"due": m.due,
			"pending": m.pending_favor,
			"favors": favors,
			"cooldowns": cooldowns,
			"durations": durations,
			"immunity": m.loss_immunity,
			"claimed": m.claimed_milestones.duplicate(),
		}
	return out


# Client side: adopt the host's numbers. Cooldowns are only corrected when they
# drift, so the E / Q bars keep ticking smoothly between snapshots.
func apply_snapshot(state: Dictionary) -> void:
	for pid in state.keys():
		var id := int(pid)
		var entry: Dictionary = state[pid]
		var m := ensure_mortal(id, str(entry.get("name", "Mortal")))
		m.display_name = str(entry.get("name", m.display_name))
		var previous_favor := m.favor
		m.favor = int(entry.get("favor", m.favor))
		m.due = int(entry.get("due", m.due))
		m.pending_favor = float(entry.get("pending", 0.0))
		m.loss_immunity = float(entry.get("immunity", 0.0))
		m.claimed_milestones = entry.get("claimed", {}).duplicate()
		var owned: Array[GodFavor] = []
		for favor_id in entry.get("favors", []):
			var favor: GodFavor = god.get_favor(StringName(favor_id)) if god != null else null
			if favor != null:
				owned.append(favor)
		m.favors = owned
		var cooldowns: Dictionary = entry.get("cooldowns", {})
		for favor_id in cooldowns.keys():
			var remote_left := float(cooldowns[favor_id])
			var local_left := float(m.cooldowns.get(favor_id, 0.0))
			if remote_left <= 0.0:
				m.cooldowns.erase(favor_id)
			elif absf(local_left - remote_left) > 0.3:
				m.cooldowns[favor_id] = remote_left
		for favor_id in m.cooldowns.keys().duplicate():
			if not cooldowns.has(str(favor_id)):
				m.cooldowns.erase(favor_id)
		var durations: Dictionary = entry.get("durations", {})
		for favor_id in m.durations.keys().duplicate():
			if not durations.has(str(favor_id)):
				m.durations.erase(favor_id)
		for favor_id in durations.keys():
			m.durations[favor_id] = float(durations[favor_id])
		if m.is_local and m.favor != previous_favor:
			favor_changed.emit(m.id, m.favor, m.favor - previous_favor, "")


# --- E / Q SKILLS -----------------------------------------------------------

func skill_favor(slot: int, player_id: int = -1) -> GodFavor:
	var m := _resolve(player_id)
	if m == null:
		return null
	return m.favor_in_slot(slot)


func is_skill_ready(slot: int, player_id: int = -1) -> bool:
	var m := _resolve(player_id)
	if m == null:
		return false
	var favor := m.favor_in_slot(slot)
	return favor != null and m.cooldown_left(favor.id) <= 0.0


func skill_cooldown_ratio(slot: int, player_id: int = -1) -> float:
	# 1.0 = ready to fire, 0.0 = just fired - the E / Q bars read this directly.
	var m := _resolve(player_id)
	if m == null:
		return 0.0
	var favor := m.favor_in_slot(slot)
	if favor == null:
		return 0.0
	if favor.cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - m.cooldown_left(favor.id) / favor.cooldown, 0.0, 1.0)


func skill_active_time(slot: int, player_id: int = -1) -> float:
	# Seconds left of the skill's timed effect (0 when it is not running).
	var m := _resolve(player_id)
	if m == null:
		return 0.0
	var favor := m.favor_in_slot(slot)
	if favor == null:
		return 0.0
	return m.duration_left(favor.id)


func use_skill(slot: int, player_id: int = -1) -> GodFavor:
	var m := _resolve(player_id)
	if m == null:
		return null
	var favor := m.favor_in_slot(slot)
	if favor == null or m.cooldown_left(favor.id) > 0.0:
		return null
	if favor.cooldown > 0.0:
		m.cooldowns[favor.id] = favor.cooldown
	if favor.duration > 0.0:
		m.durations[favor.id] = favor.duration
	var immunity := favor.param("loss_immunity", 0.0)
	if immunity > 0.0:
		m.loss_immunity = maxf(m.loss_immunity, immunity)
	skill_used.emit(m.id, favor)
	return favor


# --- TICK / TRIAL END -------------------------------------------------------

func _process(delta: float) -> void:
	if mortals.is_empty():
		return
	for m in mortals.values():
		_tick_mortal(m, delta)
	if simulate_rivals:
		_simulate_rivals(delta)


func _tick_mortal(m: Mortal, delta: float) -> void:
	m.loss_immunity = maxf(0.0, m.loss_immunity - delta)
	for favor_id in m.cooldowns.keys():
		var left := float(m.cooldowns[favor_id]) - delta
		m.cooldowns[favor_id] = maxf(0.0, left)
		if left <= 0.0:
			var favor := m.favor_by_id(favor_id)
			if favor != null:
				skill_recharged.emit(m.id, favor)
	for favor_id in m.durations.keys():
		m.durations[favor_id] = maxf(0.0, float(m.durations[favor_id]) - delta)


func _simulate_rivals(delta: float) -> void:
	# Placeholder for real networked mortals: they quietly gather FAVOR so the
	# "highest FAVOR" and rivalry rules have somebody to compare against.
	for m in mortals.values():
		if m.is_local:
			continue
		m.pending_favor += delta * 22.0
		if m.pending_favor >= 1.0:
			var banked := int(m.pending_favor)
			m.pending_favor -= float(banked)
			_apply(m, banked, "%s (rival)" % m.display_name)


func end_trial() -> Dictionary:
	# End-of-trial favors (Favorable Outcome) settle here.
	var summary := {}
	var top_id := top_player_id()
	for m in mortals.values():
		var bonus := 0
		if m.id == top_id:
			for favor in m.favors:
				if favor.kind == GodFavor.Kind.END_OF_TRIAL:
					bonus += int(favor.param("bonus", 0.0))
		if bonus > 0:
			_apply(m, bonus, "Favorable Outcome")
		summary[m.id] = {
			"name": m.display_name,
			"favor": m.favor,
			"due": m.due,
			"bonus": bonus,
			"is_local": m.is_local,
		}
	trial_active = false
	trial_ended.emit(summary)
	return summary
