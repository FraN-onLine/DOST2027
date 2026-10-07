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
# A favor just did something other than sit there (Hanan's favors): the arena
# turns this into a banner / event line in the favor's colour.
signal favor_fired(player_id: int, favor: GodFavor, text: String)

const MILESTONE_STEP := 1000  # default: every 1000 FAVOR hands out one God's Due
const LOCAL_ID := 1
const LOSS_HISTORY_SECONDS := 10.0  # longest look-back any favor may ask for (Bagong Umaga)
# The reason on a favor_changed that only MOVED FAVOR between a mortal's total and
# their Kamalig (the granary): it is not a loss and not a gain, so the loss
# listeners (The Sun God, The Ruler, the red popup) skip it.
const TRANSFER_REASON := "Kamalig"


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
	var loss_history: Array = []  # [time, amount] of FAVOR actually lost, newest last
	# Mapulon & Ikapati's favors (see the HARVEST PAIR section below):
	var binhi_trials: int = 0          # trials ended while holding Binhi
	var kabiyak: int = -1              # the mortal this one is paired with (-1 = none)
	var kabiyak_pending: float = 0.0   # fractional share not paid yet
	var weeds_time: float = 0.0        # Ligaw na Damo on this mortal: seconds left
	var weeds_caster: int = -1
	var weeds_pending: float = 0.0
	var drought_time: float = 0.0      # Tagtuyot on this mortal: seconds left
	var drought_caster: int = -1
	var drought_total: int = 0         # FAVOR it has taken so far (capped)
	var drought_tick: float = 0.0      # seconds to the next once-a-second bite
	var rain_lost: int = 0             # Unang Ulan: FAVOR lost while the rain falls
	var regrowths: Array = []          # [seconds left, amount] waiting to grow back
	var granary: int = 0               # Kamalig: FAVOR stored, out of the total

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
# FAVOR per God's Due for this run. The lobby can change it (RunSettings.due_step);
# a standalone arena keeps the default.
var milestone_step: int = MILESTONE_STEP
# False on a client: it mirrors the host and must never run a rule that changes
# FAVOR on its own (Tagtuyot's bites, Unang Ulan's regrowth).
var authority := true
# Seconds left on the trial clock, kept up to date by the host's arena (INF when no
# clock is running). Panahon ng Anihan reads it; the arena puts it back to INF
# before the end-of-trial payouts so they never count as the harvest.
var time_left := INF
var _clock := 0.0  # seconds since the match began - stamps the loss history


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
		if favor.id == &"panahon_ng_anihan" and time_left <= favor.param("window", 15.0):
			mult *= favor.param("gain_mult", 1.3)
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
	# Ligaw na Damo: weeds in this mortal's field send a share to the caster.
	var weeded := 0
	var caster := mortal(m.weeds_caster) if m.weeds_time > 0.0 else null
	var weeds: GodFavor = Gods.favor_by_id(&"ligaw_na_damo")
	if caster != null and caster != m and weeds != null:
		var siphoned := float(gained) * weeds.param("siphon", 0.3) + m.weeds_pending
		weeded = int(siphoned)
		m.weeds_pending = siphoned - float(weeded)
	gained -= weeded
	if gained != 0:
		_apply(m, gained, reason)
	if weeded > 0:
		_apply(caster, weeded, "Ligaw na Damo")
	_share_with_kabiyak(m, gained)
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
	if m.duration_left(&"unang_ulan") > 0.0:
		m.rain_lost += lost  # watered: it grows back once the rain stops
	m.loss_history.append([_clock, lost])
	while not m.loss_history.is_empty() and _clock - float(m.loss_history[0][0]) > LOSS_HISTORY_SECONDS:
		m.loss_history.pop_front()
	return lost


func _apply(m: Mortal, delta: int, reason: String) -> void:
	m.favor = maxi(0, m.favor + delta)
	favor_changed.emit(m.id, m.favor, delta, reason)
	_check_milestones(m)


func _check_milestones(m: Mortal) -> void:
	# A God's Due is only ever awarded on the FIRST pass of a milestone.
	var reached := int(floor(float(m.favor) / float(maxi(1, milestone_step))))
	for index in range(1, reached + 1):
		if m.claimed_milestones.has(index):
			continue
		m.claimed_milestones[index] = true
		m.due += 1
		due_earned.emit(m.id, m.due, index * milestone_step)
		due_changed.emit(m.id, m.due)


func top_player_id() -> int:
	var best_id := -1
	var best := -1
	for m in mortals.values():
		if m.favor > best:
			best = m.favor
			best_id = m.id
	return best_id


# --- GOD'S DUE / FAVORS -----------------------------------------------------

func is_favor_eligible(favor: GodFavor, player_id: int = -1) -> bool:
	var m := _resolve(player_id)
	if m == null or favor == null:
		return false
	var required_god := favor.requires_god_id()
	var any_of := favor.requires_any_god_ids()
	if required_god == &"" and any_of.is_empty():
		return true
	for owned in m.favors:
		if (required_god != &"" and owned.god_id == required_god) or any_of.has(owned.god_id):
			return true
	return false


func can_grant(favor: GodFavor, player_id: int = -1) -> bool:
	var m := _resolve(player_id)
	if m == null or favor == null or m.has_favor(favor.id) or not is_favor_eligible(favor, player_id):
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
	if m == null or favor == null or m.has_favor(favor.id) or not is_favor_eligible(favor, player_id):
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
		_fire_instant_effect(m, favor)
	return true


# --- HANAN'S FAVORS ---------------------------------------------------------
# Rules that live here (not in an arena) because they only read and change the
# match: the host runs them, the clients mirror the result through snapshots.

func _fire_instant_effect(holder: Mortal, favor: GodFavor) -> void:
	match favor.id:
		&"the_dawn":
			var cut := int(favor.param("due_reduction", 1.0))
			for m in mortals.values():
				var before: int = m.due
				m.due = maxi(0, m.due - cut)
				if m.due != before:
					due_changed.emit(m.id, m.due)
			favor_fired.emit(holder.id, favor, "The Dawn - every mortal's God's Due drops by %d" % cut)
		&"even_playing_field":
			var target := _highest_other(holder.id)
			if target == null:
				return
			var lowest := target.favor
			for m in mortals.values():
				lowest = mini(lowest, m.favor)
			var amount := int(float(target.favor - lowest) * favor.param("gap_fraction", 0.5))
			var lost := lose_favor(amount, favor.display_name, target.id)
			favor_fired.emit(holder.id, favor, "An Even Playing Field - %s loses %d FAVOR" % [target.display_name, lost])
		&"kabiyak":
			_pair_kabiyak(holder)
			var partner := mortal(holder.kabiyak)
			if partner != null:
				favor_fired.emit(holder.id, favor, "Kabiyak - %s is paired with %s" % [holder.display_name, partner.display_name])


# The mortal with the most FAVOR other than `excluded_id` (ties: random).
func _highest_other(excluded_id: int) -> Mortal:
	var best: Array[Mortal] = []
	for m in mortals.values():
		if m.id == excluded_id:
			continue
		if best.is_empty() or m.favor > best[0].favor:
			best = [m]
		elif m.favor == best[0].favor:
			best.append(m)
	return null if best.is_empty() else best[randi() % best.size()]


# Host, at the start of every trial: First Light pays the mortals in last place.
func begin_trial() -> void:
	# Kabiyak: an other half who left during an earlier trial is replaced now.
	for m in mortals.values():
		if m.has_favor(&"kabiyak") and not mortals.has(m.kabiyak):
			_pair_kabiyak(m)
	var lowest := 1 << 60
	var highest := -1
	for m in mortals.values():
		lowest = mini(lowest, m.favor)
		highest = maxi(highest, m.favor)
	if lowest == highest:
		return  # everybody is tied - nobody is last
	for m in mortals.values():
		var light: GodFavor = m.favor_by_id(&"first_light")
		if light != null and m.favor == lowest:
			var bonus := int(light.param("last_place_bonus", 150.0))
			add_favor(bonus, light.display_name, m.id)
			favor_fired.emit(m.id, light, "First Light - %s gains %d FAVOR for being last" % [m.display_name, bonus])


# Bagong Umaga: give back what the mortal really lost in the last `lookback`
# seconds. Written straight to the total so Full Moon cannot inflate it.
func restore_recent_losses(player_id: int, lookback: float) -> int:
	var m := _resolve(player_id)
	if m == null:
		return 0
	var total := 0
	for entry in m.loss_history:
		if _clock - float(entry[0]) <= lookback:
			total += int(entry[1])
	m.loss_history.clear()
	if total > 0:
		_apply(m, total, "Bagong Umaga")
	return total


# Break of Day: the best other mortal (the leader, or second place when the caster
# leads; ties random) loses every running favor effect and has E and Q start over
# at a full cooldown. Returns that mortal's id, or -1 when nobody else is playing.
func break_of_day(caster_id: int) -> int:
	var target := _highest_other(caster_id)
	if target == null:
		return -1
	target.durations.clear()
	target.loss_immunity = 0.0
	# Their Mapulon & Ikapati casts end too: the drought and the weeds they sent,
	# and the rain they were standing in (what it watered does not grow back).
	target.rain_lost = 0
	for m in mortals.values():
		if m.drought_caster == target.id:
			m.drought_time = 0.0
		if m.weeds_caster == target.id:
			m.weeds_time = 0.0
	for slot in [GodFavor.Slot.E, GodFavor.Slot.Q]:
		var skill := target.favor_in_slot(slot)
		if skill != null and skill.cooldown > 0.0:
			target.cooldowns[skill.id] = skill_cooldown(slot, target.id)
	return target.id


# --- MAPULON & IKAPATI'S FAVORS (the Harvest Pair) ------------------------------
# Everything they give grows over time. The host runs these; clients mirror the
# numbers through snapshots (binhi_trials, kabiyak and granary travel with them).

# Kabiyak: pair `m` with the mortal closest to them in FAVOR (ties random).
func _pair_kabiyak(m: Mortal) -> void:
	var best: Array[Mortal] = []
	for other in mortals.values():
		if other.id == m.id:
			continue
		var gap := absi(other.favor - m.favor)
		if best.is_empty() or gap < absi(best[0].favor - m.favor):
			best = [other]
		elif gap == absi(best[0].favor - m.favor):
			best.append(other)
	m.kabiyak = -1 if best.is_empty() else best[randi() % best.size()].id


# Whoever holds Kabiyak paired with `m` gets a share of what `m` really gained.
# Paid through _apply, never add_favor: two mortals paired with each other cannot
# feed each other forever, and Full Moon does not stack on the share.
func _share_with_kabiyak(m: Mortal, gained: int) -> void:
	if gained <= 0:
		return
	for holder in mortals.values():
		if holder.id == m.id or holder.kabiyak != m.id:
			continue
		var perk: GodFavor = holder.favor_by_id(&"kabiyak")
		if perk == null:
			continue
		var share: float = float(gained) * perk.param("share", 0.1) + holder.kabiyak_pending
		var paid := int(share)
		holder.kabiyak_pending = share - float(paid)
		if paid > 0:
			_apply(holder, paid, "Kabiyak")


# Tagtuyot: the leader (second place when the caster leads; same targeting as
# Break of Day) withers for the favor's duration. Returns the target's id or -1.
func cast_tagtuyot(caster_id: int, favor: GodFavor) -> int:
	var target := _highest_other(caster_id)
	if target == null:
		return -1
	target.drought_time = maxf(0.0, favor.duration)
	target.drought_caster = caster_id
	target.drought_total = 0
	return target.id


# Ligaw na Damo: weeds in every other mortal's field (the latest caster wins).
func cast_ligaw_na_damo(caster_id: int, favor: GodFavor) -> void:
	for m in mortals.values():
		if m.id != caster_id:
			m.weeds_time = maxf(0.0, favor.duration)
			m.weeds_caster = caster_id
			m.weeds_pending = 0.0


# Kamalig: move a share of the mortal's FAVOR into the granary. A transfer, not a
# loss: it skips lose_favor (no loss history, no Unang Ulan, no Waning Moon) and
# is marked with TRANSFER_REASON so no loss listener reacts. Returns the amount.
func store_in_granary(player_id: int, favor: GodFavor) -> int:
	var m := _resolve(player_id)
	if m == null:
		return 0
	var amount := mini(int(float(m.favor) * favor.param("store_fraction", 0.25)), int(favor.param("max_store", 400.0)))
	if amount <= 0:
		return 0
	m.granary += amount
	_apply(m, -amount, TRANSFER_REASON)
	return amount


func _tick_harvest(m: Mortal, delta: float) -> void:
	m.weeds_time = maxf(0.0, m.weeds_time - delta)
	if m.drought_time > 0.0:
		# One bite each time the clock crosses a whole second: 5s = 5 bites.
		var before := ceilf(m.drought_time)
		m.drought_time = maxf(0.0, m.drought_time - delta)
		var drought: GodFavor = Gods.favor_by_id(&"tagtuyot")
		if authority and ceilf(m.drought_time) < before and drought != null:
			var room := int(drought.param("max_total", 400.0)) - m.drought_total
			var bite := mini(int(float(m.favor) * drought.param("percent_per_second", 0.03)), room)
			if bite > 0:
				m.drought_total += lose_favor(bite, "Tagtuyot", m.id)
	if not authority:
		return
	for index in range(m.regrowths.size() - 1, -1, -1):
		var entry: Array = m.regrowths[index]
		entry[0] = float(entry[0]) - delta
		if float(entry[0]) <= 0.0:
			m.regrowths.remove_at(index)
			_apply(m, int(entry[1]), "Unang Ulan")
	var rain: GodFavor = m.favor_by_id(&"unang_ulan")
	if rain != null and m.rain_lost > 0 and m.duration_left(&"unang_ulan") <= 0.0:
		# The rain stopped: what it watered grows back after a while.
		m.regrowths.append([rain.param("regrow_delay", 5.0), int(float(m.rain_lost) * rain.param("regrow_mult", 1.25))])
		m.rain_lost = 0


# Trial end, before Favorable Outcome: the granary comes back with interest, rain
# still waiting to regrow is paid at once, and Binhi grows.
func _settle_harvest(m: Mortal) -> int:
	var bonus := 0
	if m.granary > 0:
		var kamalig: GodFavor = Gods.favor_by_id(&"kamalig")
		var interest := kamalig.param("interest", 0.2) if kamalig != null else 0.0
		var returned := m.granary + int(float(m.granary) * interest)
		m.granary = 0
		_apply(m, returned, TRANSFER_REASON)
	var rain: GodFavor = Gods.favor_by_id(&"unang_ulan")
	var waiting := int(float(m.rain_lost) * (rain.param("regrow_mult", 1.25) if rain != null else 1.0))
	for entry in m.regrowths:
		waiting += int(entry[1])
	m.rain_lost = 0
	m.regrowths.clear()
	if waiting > 0:
		_apply(m, waiting, "Unang Ulan")
	var binhi: GodFavor = m.favor_by_id(&"binhi")
	if binhi != null:
		m.binhi_trials += 1
		var grown := int(binhi.param("growth_per_trial", 50.0)) * m.binhi_trials
		_apply(m, grown, "Binhi")
		favor_fired.emit(m.id, binhi, "Binhi - %s's seed grows: +%d FAVOR" % [m.display_name, grown])
		bonus += grown
	m.drought_time = 0.0
	m.weeds_time = 0.0
	return bonus


# The Three Sisters: +per_sister for each of Mayari and Tala the mortal holds a
# favor from. Works on a run snapshot, so the finale can show it in the standings.
static func three_sisters_bonus(favor_ids: Array) -> int:
	var perk: GodFavor = Gods.favor_by_id(&"the_three_sisters")
	if perk == null or not favor_ids.has(str(perk.id)):
		return 0
	var sisters := 0
	for sister in [Gods.MAYARI, Gods.TALA]:
		for id in favor_ids:
			var owned: GodFavor = Gods.favor_by_id(StringName(str(id)))
			if owned != null and owned.god_id == sister:
				sisters += 1
				break
	return sisters * int(perk.param("per_sister", 150.0))


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
	# Kabiyak: a holder whose other half left is paired with the next closest.
	for m in mortals.values():
		if m.kabiyak == id:
			_pair_kabiyak(m)


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
			"binhi": m.binhi_trials,
			"kabiyak": m.kabiyak,
			"granary": m.granary,
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
		m.binhi_trials = int(entry.get("binhi", m.binhi_trials))
		m.kabiyak = int(entry.get("kabiyak", m.kabiyak))
		var previous_granary := m.granary
		m.granary = int(entry.get("granary", m.granary))
		var owned: Array[GodFavor] = []
		for favor_id in entry.get("favors", []):
			var favor: GodFavor = Gods.favor_by_id(StringName(favor_id))
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
			# FAVOR that moved in or out of the granary is a transfer, not a loss.
			var reason := TRANSFER_REASON if m.granary != previous_granary else ""
			favor_changed.emit(m.id, m.favor, m.favor - previous_favor, reason)


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


func skill_cooldown(slot: int, player_id: int = -1) -> float:
	var m := _resolve(player_id)
	if m == null:
		return 0.0
	var favor := m.favor_in_slot(slot)
	if favor == null:
		return 0.0
	var multiplier := 1.0
	if slot == GodFavor.Slot.E and m.has_favor(&"the_bountiful_e"):
		multiplier *= m.favor_by_id(&"the_bountiful_e").param("cooldown_multiplier", 0.9)
	if slot == GodFavor.Slot.Q and m.has_favor(&"the_bountiful_q"):
		multiplier *= m.favor_by_id(&"the_bountiful_q").param("cooldown_multiplier", 0.9)
	return favor.cooldown * multiplier


func skill_cooldown_ratio(slot: int, player_id: int = -1) -> float:
	# 1.0 = ready to fire, 0.0 = just fired - the E / Q bars read this directly.
	var m := _resolve(player_id)
	if m == null:
		return 0.0
	var favor := m.favor_in_slot(slot)
	if favor == null:
		return 0.0
	var cooldown := skill_cooldown(slot, player_id)
	if cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - m.cooldown_left(favor.id) / cooldown, 0.0, 1.0)


func use_skill(slot: int, player_id: int = -1) -> GodFavor:
	var m := _resolve(player_id)
	if m == null:
		return null
	var favor := m.favor_in_slot(slot)
	if favor == null or m.cooldown_left(favor.id) > 0.0:
		return null
	var cooldown := skill_cooldown(slot, player_id)
	if cooldown > 0.0:
		m.cooldowns[favor.id] = cooldown
	if favor.duration > 0.0:
		m.durations[favor.id] = favor.duration
	var immunity := favor.param("loss_immunity", 0.0)
	if immunity > 0.0:
		m.loss_immunity = maxf(m.loss_immunity, immunity)
	skill_used.emit(m.id, favor)
	return favor


# --- TICK / TRIAL END -------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
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
	_tick_harvest(m, delta)


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
	# End-of-trial favors settle here: first the Harvest Pair's (Kamalig's store
	# comes back, Binhi grows), then Favorable Outcome judges the real totals.
	time_left = INF  # nothing paid from here on is the harvest
	var harvest := {}
	for m in mortals.values():
		harvest[m.id] = _settle_harvest(m)
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
			"bonus": bonus + int(harvest.get(m.id, 0)),
			"is_local": m.is_local,
		}
	trial_active = false
	return summary
