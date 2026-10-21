class_name GodMatch
extends Node

# Rules engine for one Bathala trial (and the run of trials around it).
# It owns every mortal's FAVOR, their God's Due vouchers, the favors they hold
# and the state of their E / Q skills. Arenas push events in and listen to the
# signals, so the rules live in one place for when the other gods and the
# network layer arrive.
#
# It also runs the Pamana (heirlooms, scripts/pamana/) a mortal buys at the
# Tindahan between two trials: what they paid (spend_favor - never a loss), the
# item waiting for the next trial, and every item's rule (THE PAMANA below).

signal favor_changed(player_id: int, favor: int, delta: int, reason: String)
signal due_changed(player_id: int, due: int)
signal due_earned(player_id: int, due: int, milestone: int)
signal favor_granted(player_id: int, favor: GodFavor)
# An E / Q skill just took its slot - from a God's Due, a boon or a god's gift here on
# the host, or read off the host's snapshot on a client (see announce_gains). `replaced`
# is the skill it pushed out of the slot, null when the slot was empty. The HUD's gain
# popup listens to this.
signal skill_gained(player_id: int, favor: GodFavor, replaced: GodFavor)
signal skill_used(player_id: int, favor: GodFavor)
signal skill_recharged(player_id: int, favor: GodFavor)
signal notice(text: String)
# A favor just did something other than sit there (Hanan's favors): the arena
# turns this into a banner / event line in the favor's colour.
signal favor_fired(player_id: int, favor: GodFavor, text: String)
# A Pamana just did something (it awoke, cancelled a loss, recharged a skill...):
# the arena turns it into a banner / event line in the item's colour.
signal pamana_fired(player_id: int, pamana: Pamana, text: String)

const MILESTONE_STEP := 1000  # default: every 1000 FAVOR hands out one God's Due
const LOCAL_ID := 1
const LOSS_HISTORY_SECONDS := 10.0  # longest look-back any favor may ask for (Bagong Umaga)
# The reason on a favor_changed that only MOVED FAVOR between a mortal's total and
# their Kamalig (the granary): it is not a loss and not a gain, so the loss
# listeners (The Sun God, The Ruler, the red popup) skip it.
const TRANSFER_REASON := "Kamalig"
# The reason on a favor_changed that SPENT FAVOR at the Tindahan (spend_favor). A
# purchase is not a loss either: every loss listener skips it, like a transfer.
const PURCHASE_REASON := "Tindahan"
# FAVOR for one boon (a favor of the god who just hosted) bought at the preparation
# area's altar without a voucher (PrepArea.boon_cost starts here). Paid with
# PURCHASE_REASON too: buying is never a loss.
const BOON_COST := 750


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
	# Bathala's sacrifices (see the BATHALA'S FAVORS section below):
	var mayari_curse: float = 0.0      # Mayari's blindness promised on the field (s)
	var apolaki_curse: float = 0.0     # Apolaki's Sun Patches promised (s)
	var apolaki_patches: int = 0       # how many Sun Patches that promise carries
	var batman_shield: bool = false    # Si Batman: nothing can take FAVOR until the game ends
	var bathala_regrowth: Array = []   # [seconds left, per_second, remaining] slow returns
	# The Pamana (see THE PAMANA section below):
	var pamana_next: StringName = &""  # bought at the Tindahan, waiting for the next trial
	var pamana_active: StringName = &"" # live this trial
	var pamana_window: float = 0.0     # a FIRST_WINDOW item: seconds of it left
	var agimat_charges: int = 0        # The Agimat: losses it can still cancel
	var jar_lost: int = 0              # Manunggul Jar: FAVOR lost this trial
	var kampilan_ready: bool = false   # Kampilan: the first cast is still to come
	var surigao_early: int = 0         # Surigao Gold: FAVOR early for the next God's Due (0 = none)

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
# A client learns of a new skill only through the host's snapshots, which also carry the
# favors a mortal already had when the trial began. The shell switches this on once the
# run's carried snapshot is in (Game._on_arena_ready), so only what changes after that
# is announced - never what the mortal simply arrived with.
var announce_gains := false
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
	if pamana_in_window(m, Pamanas.MUTYA):
		mult *= Pamanas.by_id(Pamanas.MUTYA).param("gain_multiplier", 1.2)
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


# A DRAIN is a loss that ticks a little at a time (the Taya's once-a-second drain
# in Langit Lupa, Tagtuyot's bites): The Agimat lets those through, or three
# seconds of one would burn all of its charges. The Manunggul Jar still counts them.
func lose_favor(amount: int, reason: String = "", player_id: int = -1, drain := false) -> int:
	var m := _resolve(player_id)
	if m == null or amount <= 0:
		return 0
	# Si Batman: once the shield is up, nothing takes this mortal's FAVOR away.
	if m.batman_shield:
		notice.emit("%s cannot lose FAVOR (Si Batman)" % m.display_name)
		return 0
	var lost := int(round(float(amount) * loss_multiplier(m)))
	if lost <= 0:
		notice.emit("FAVOR shielded - nothing lost")
		return 0
	lost = mini(lost, m.favor)
	if lost <= 0:
		return 0
	# The Agimat: a loss that would really land is cancelled while charges last.
	if not drain and m.pamana_active == Pamanas.AGIMAT and m.agimat_charges > 0:
		m.agimat_charges -= 1
		_fire_pamana(m, Pamanas.AGIMAT, "AGIMAT - LOSS CANCELLED (%d LEFT)" % m.agimat_charges)
		return 0
	_apply(m, -lost, reason)
	if m.pamana_active == Pamanas.MANUNGGUL_JAR:
		m.jar_lost += lost  # carried across: a share comes back at the trial's end
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
	var step := maxi(1, milestone_step)
	# Surigao Gold: the lowest milestone not claimed yet pays surigao_early FAVOR
	# early, once. Every later milestone keeps its own number.
	if m.surigao_early > 0:
		var next := 1
		while m.claimed_milestones.has(next):
			next += 1
		if m.favor >= next * step - m.surigao_early:
			m.surigao_early = 0
			_claim_milestone(m, next)
			_fire_pamana(m, Pamanas.SURIGAO_GOLD, "SURIGAO GOLD - GOD'S DUE ARRIVES EARLY")
	var reached := int(floor(float(m.favor) / float(step)))
	for index in range(1, reached + 1):
		if not m.claimed_milestones.has(index):
			_claim_milestone(m, index)


func _claim_milestone(m: Mortal, index: int) -> void:
	m.claimed_milestones[index] = true
	m.due += 1
	due_earned.emit(m.id, m.due, index * milestone_step)
	due_changed.emit(m.id, m.due)


# Spend FAVOR (the Tindahan): refused when the mortal holds too little. It is NOT
# a loss - no multiplier, no Si Batman, no Agimat, no loss history, no Manunggul
# Jar - and `reason` should be PURCHASE_REASON, which every loss listener skips.
# A milestone already claimed stays claimed, and passing it again pays nothing.
func spend_favor(amount: int, reason: String, player_id: int = -1) -> bool:
	var m := _resolve(player_id)
	if m == null or amount < 0 or m.favor < amount:
		return false
	if amount > 0:
		_apply(m, -amount, reason)
	return true


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
	var replaced: GodFavor = null
	if favor.is_skill():
		for index in range(m.favors.size() - 1, -1, -1):
			if m.favors[index].slot == favor.slot:
				replaced = m.favors[index]
				m.cooldowns.erase(m.favors[index].id)
				m.durations.erase(m.favors[index].id)
				m.favors.remove_at(index)
	m.favors.append(favor)
	if favor.cooldown > 0.0:
		m.cooldowns[favor.id] = 0.0
	favor_granted.emit(m.id, favor)
	if favor.is_skill():
		skill_gained.emit(m.id, favor, replaced)
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
		&"our_partnership_ends_mayari":
			var cost := int(favor.param("cost", 500.0))
			var lost := lose_favor(cost, favor.display_name, holder.id)
			# Mayari's blindness is a screen effect: the arena fires it (see
			# _apply_skill_effect), so here we only mark it and pay the cost.
			holder.mayari_curse = maxf(holder.mayari_curse, favor.param("blind_duration", 10.0))
			favor_fired.emit(holder.id, favor, "Our Partnership Ends Here - %s pays %d FAVOR, Mayari blinds the field" % [holder.display_name, lost])
		&"our_partnership_ends_apolaki":
			var cost := int(favor.param("cost", 500.0))
			var lost := lose_favor(cost, favor.display_name, holder.id)
			# Apolaki's Sun Patches are a screen effect the arena fires; the match
			# only pays the cost and records how many patches were promised.
			holder.apolaki_curse = maxf(holder.apolaki_curse, favor.param("sun_duration", 10.0))
			holder.apolaki_patches = int(favor.param("sun_count", 4))
			favor_fired.emit(holder.id, favor, "Our Partnership Ends Here - %s pays %d FAVOR, Apolaki sears the field" % [holder.display_name, lost])
		&"bathala_na":
			var per := int(favor.param("per_due", 350.0))
			var spent := holder.due
			if spent > 0:
				holder.due = 0
				due_changed.emit(holder.id, holder.due)
				# Paid through _apply, not add_favor: it is the DUE being poured out,
				# not a favour being multiplied by Full Moon and friends.
				_apply(holder, per * spent, favor.display_name)
			favor_fired.emit(holder.id, favor, "Bathala Na - %s pours out %d God's Due for %d FAVOR" % [holder.display_name, spent, per * spent])
		&"si_batman":
			var cost := int(favor.param("cost", 1500.0))
			# The one cost is paid straight to the total (it must land even though
			# the shield is about to go up), then nothing can take this mortal's
			# FAVOR away again until the game ends - lose_favor checks the shield.
			_apply(holder, -mini(cost, holder.favor), favor.display_name)
			holder.batman_shield = true
			favor_fired.emit(holder.id, favor, "Si Batman - %s pays %d FAVOR and cannot lose FAVOR until the game ends" % [holder.display_name, cost])


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


# --- BATHALA'S FAVORS (the sacrifices) ----------------------------------------
# Blindside (E, Bathala): cut the leading opponent's FAVOR in half. The amount actually
# taken is queued to grow back over `regrow_time` seconds at `regrow` of it (the
# note "delete and recover 20% per second" - 80% of the half over 4s). Returns the
# target's id, or -1 when nobody else is playing.
func cast_half_vision(caster_id: int, favor: GodFavor) -> int:
	var target := _highest_other(caster_id)
	if target == null:
		return -1
	var half := int(round(float(target.favor) * favor.param("halve", 0.5)))
	var lost := lose_favor(half, favor.display_name, target.id)
	var back := int(round(float(lost) * favor.param("regrow", 0.8)))
	if back > 0:
		_queue_regrowth(target, back, favor.param("regrow_time", 4.0))
	return target.id


# Vantage Point (Q, Bathala): cut your OWN FAVOR in half, then grow 120% of the
# amount back over `regrow_time` seconds - a net gain if you can survive it.
func cast_siblings_compromise(player_id: int, favor: GodFavor) -> int:
	var m := _resolve(player_id)
	if m == null:
		return 0
	var half := int(round(float(m.favor) * favor.param("halve", 0.5)))
	var lost := lose_favor(half, favor.display_name, m.id)
	var back := int(round(float(lost) * favor.param("regrow", 1.2)))
	if back > 0:
		_queue_regrowth(m, back, favor.param("regrow_time", 6.0))
	return lost


# Queue `amount` FAVOR to grow back onto `m` smoothly over `seconds` (a little
# each second, so it reads as a slow return rather than a lump). Paid through
# _apply so no gain multiplier inflates it a second time.
func _queue_regrowth(m: Mortal, amount: int, seconds: float) -> void:
	if amount <= 0 or seconds <= 0.0:
		return
	var per_second := float(amount) / seconds
	m.bathala_regrowth.append([seconds, per_second, float(amount)])


# The slow returns tick a little each second: "recover 20% per second" reads as a
# steady drip back, not a lump. Runs on the host; clients mirror through snapshots.
func _tick_bathala_regrowth(m: Mortal, delta: float) -> void:
	if m.bathala_regrowth.is_empty():
		return
	var alive: Array = []
	for entry in m.bathala_regrowth:
		var left := float(entry[0]) - delta
		var per_second := float(entry[1])
		var remaining := float(entry[2]) - per_second * delta
		var grew := int(per_second * delta)
		if grew > 0:
			_apply(m, grew, "Bathala's sacrifice")
		if left > 0.0 and remaining > 0.5:
			alive.append([left, per_second, maxf(0.0, remaining)])
	m.bathala_regrowth = alive




# --- THE PAMANA (heirlooms from the Tindahan) ----------------------------------
# A mortal buys one at the Tindahan (buy_pamana); it waits in pamana_next and
# wakes at the next trial's "GO!" (begin_trial). Each item's rule sits where the
# rule it bends lives:
#   Manunggul Jar  lose_favor counts jar_lost; end_trial returns a share of it
#   The Agimat     lose_favor cancels the first `charges` losses (not drains)
#   Torn Cedulas / The Mighty Pen   skill_cooldown, while the window lasts
#   Banton Cloth   the arena's move speed (Arena._update_movement_favors)
#   The Mutya      gain_multiplier, while the window lasts
#   Kampilan       use_skill: the first cast recharges at once
#   Surigao Gold   _check_milestones: the next God's Due comes early (it waits
#                  for that milestone, not for a trial - surigao_early)
# Everything but Surigao Gold expires at end_trial, used or not.

func pamana_in_window(m: Mortal, pamana_id: StringName) -> bool:
	return m.pamana_active == pamana_id and m.pamana_window > 0.0


# Would `pamana` help this mortal at all? A skill item needs a skill in its slot,
# and a second Surigao Gold is never offered while one is still waiting.
func pamana_useful(pamana: Pamana, player_id: int = -1) -> bool:
	var m := _resolve(player_id)
	if m == null or pamana == null:
		return false
	var has_e := m.favor_in_slot(GodFavor.Slot.E) != null
	var has_q := m.favor_in_slot(GodFavor.Slot.Q) != null
	match pamana.needs:
		Pamana.Needs.E_SKILL:
			return has_e
		Pamana.Needs.Q_SKILL:
			return has_q
		Pamana.Needs.ANY_SKILL:
			return has_e or has_q
	if pamana.id == Pamanas.SURIGAO_GOLD:
		return m.surigao_early <= 0
	return true


# Buy `pamana` for this mortal: pays its cost (spend_favor) and puts it in
# pamana_next - or, for Surigao Gold, starts waiting for the next milestone at
# once. Refused when it cannot be paid for. Host only.
func buy_pamana(pamana: Pamana, player_id: int = -1) -> bool:
	var m := _resolve(player_id)
	if m == null or pamana == null or not spend_favor(pamana.cost, PURCHASE_REASON, m.id):
		return false
	if pamana.id == Pamanas.SURIGAO_GOLD:
		m.surigao_early = int(pamana.param("early_by", 200.0))
		_check_milestones(m)  # already within reach of the next milestone
	else:
		m.pamana_next = pamana.id
	return true


# Could this mortal buy `favor` as a boon for `cost` FAVOR? Only a favor of this
# match's god (the altar's), one bestow_favor would hand over (not held yet, and
# eligible), and only when they can pay. Nothing changes.
func can_buy_boon(favor: GodFavor, player_id: int = -1, cost := BOON_COST) -> bool:
	var m := _resolve(player_id)
	if m == null or favor == null or god == null or god.get_favor(favor.id) != favor:
		return false
	if m.has_favor(favor.id) or not is_favor_eligible(favor, m.id):
		return false
	return cost >= 0 and m.favor >= cost


# Buy `favor` as a boon: every check first (can_buy_boon), then spend_favor - not a
# loss - and bestow_favor, which puts a skill in its slot in place of the old one.
# Host only. Returns true when it went through.
func buy_boon(favor: GodFavor, player_id: int = -1, cost := BOON_COST) -> bool:
	if not can_buy_boon(favor, player_id, cost):
		return false
	var m := _resolve(player_id)
	spend_favor(cost, PURCHASE_REASON, m.id)
	return bestow_favor(favor, m.id)


# "GO!": every mortal's waiting item wakes for this trial.
func _wake_pamana(m: Mortal) -> void:
	m.pamana_active = m.pamana_next
	m.pamana_next = &""
	m.pamana_window = 0.0
	m.agimat_charges = 0
	m.jar_lost = 0
	m.kampilan_ready = false
	var pamana := Pamanas.by_id(m.pamana_active)
	if pamana == null:
		m.pamana_active = &""
		return
	if pamana.timing == Pamana.Timing.FIRST_WINDOW:
		m.pamana_window = pamana.window
	if pamana.id == Pamanas.AGIMAT:
		m.agimat_charges = int(pamana.param("charges", 3.0))
	m.kampilan_ready = pamana.id == Pamanas.KAMPILAN
	_fire_pamana(m, pamana.id, "%s AWAKENS" % pamana.display_name.to_upper())


func _fire_pamana(m: Mortal, pamana_id: StringName, text: String) -> void:
	var pamana := Pamanas.by_id(pamana_id)
	if pamana != null:
		pamana_fired.emit(m.id, pamana, text)


# What a mortal carries, for the HUD badges: [{pamana, text}], the live item (with
# its seconds or charges), the one waiting for the next trial, and Surigao Gold.
static func pamana_badges(m: Mortal) -> Array:
	var out: Array = []
	if m == null:
		return out
	var active := Pamanas.by_id(m.pamana_active)
	if active != null:
		var text := active.display_name
		if active.timing == Pamana.Timing.FIRST_WINDOW:
			text += " %ds" % int(ceil(m.pamana_window)) if m.pamana_window > 0.0 else " (spent)"
		elif active.id == Pamanas.AGIMAT:
			text += " x%d" % m.agimat_charges
		elif active.id == Pamanas.KAMPILAN and not m.kampilan_ready:
			text += " (spent)"
		out.append({"pamana": active, "text": text})
	var waiting := Pamanas.by_id(m.pamana_next)
	if waiting != null:
		out.append({"pamana": waiting, "text": "%s (next trial)" % waiting.display_name})
	if m.surigao_early > 0:
		var gold := Pamanas.by_id(Pamanas.SURIGAO_GOLD)
		if gold != null:
			out.append({"pamana": gold, "text": gold.display_name})
	return out


# Host, at the start of every trial: every mortal's Pamana wakes, and First Light
# pays the mortals in last place.
func begin_trial() -> void:
	for m in mortals.values():
		_wake_pamana(m)
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
				m.drought_total += lose_favor(bite, "Tagtuyot", m.id, true)  # a drain
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
			"batman": m.batman_shield,
			"pamana_next": str(m.pamana_next),
			"pamana_active": str(m.pamana_active),
			"pamana_window": m.pamana_window,
			"agimat": m.agimat_charges,
			"jar_lost": m.jar_lost,
			"kampilan": m.kampilan_ready,
			"surigao": m.surigao_early,
			# The Harvest Pair's timers on this mortal, so its own screen can show them.
			"weeds": m.weeds_time,
			"weeds_caster": m.weeds_caster,
			"drought": m.drought_time,
			"drought_caster": m.drought_caster,
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
		m.batman_shield = bool(entry.get("batman", m.batman_shield))
		var previous_granary := m.granary
		m.granary = int(entry.get("granary", m.granary))
		var previous_next := m.pamana_next
		var previous_surigao := m.surigao_early
		var previous_favors: Array[StringName] = []
		for favor in m.favors:
			previous_favors.append(favor.id)
		m.pamana_next = StringName(str(entry.get("pamana_next", m.pamana_next)))
		m.pamana_active = StringName(str(entry.get("pamana_active", m.pamana_active)))
		m.pamana_window = float(entry.get("pamana_window", m.pamana_window))
		m.agimat_charges = int(entry.get("agimat", m.agimat_charges))
		m.jar_lost = int(entry.get("jar_lost", m.jar_lost))
		m.kampilan_ready = bool(entry.get("kampilan", m.kampilan_ready))
		m.surigao_early = int(entry.get("surigao", m.surigao_early))
		m.weeds_time = float(entry.get("weeds", 0.0))
		m.weeds_caster = int(entry.get("weeds_caster", m.weeds_caster))
		m.drought_time = float(entry.get("drought", 0.0))
		m.drought_caster = int(entry.get("drought_caster", m.drought_caster))
		# A drop that came with a new Pamana was a purchase, not a loss.
		var bought := (m.pamana_next != previous_next and m.pamana_next != &"") \
			or (m.surigao_early > 0 and previous_surigao <= 0)
		var owned: Array[GodFavor] = []
		for favor_id in entry.get("favors", []):
			var favor: GodFavor = Gods.favor_by_id(StringName(favor_id))
			if favor != null:
				owned.append(favor)
		var held_before := {GodFavor.Slot.E: m.favor_in_slot(GodFavor.Slot.E), GodFavor.Slot.Q: m.favor_in_slot(GodFavor.Slot.Q)}
		m.favors = owned
		if announce_gains:
			for skill_slot in held_before.keys():
				var now := m.favor_in_slot(skill_slot)
				if now != null and now != held_before[skill_slot]:
					skill_gained.emit(m.id, now, held_before[skill_slot])
		# Outside a trial (the preparation area) a drop that came with a new favor
		# was a boon bought at the altar - not a loss either.
		if not trial_active and m.favor < previous_favor:
			for favor in owned:
				if not previous_favors.has(favor.id):
					bought = true
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
			var reason := TRANSFER_REASON if m.granary != previous_granary else (PURCHASE_REASON if bought else "")
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
	# Torn Cedulas (E) / The Mighty Pen (Q): shorter while their window lasts. A
	# cast inside the window keeps the shorter cooldown it was given.
	var paper: StringName = Pamanas.TORN_CEDULAS if slot == GodFavor.Slot.E else Pamanas.MIGHTY_PEN
	if pamana_in_window(m, paper):
		multiplier *= Pamanas.by_id(paper).param("cooldown_multiplier", 0.8)
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
	# Kampilan: the first cast of the trial recharges at once.
	if m.kampilan_ready:
		m.kampilan_ready = false
		m.cooldowns[favor.id] = 0.0
		_fire_pamana(m, Pamanas.KAMPILAN, "KAMPILAN - SKILL RECHARGED")
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
	# Only a running trial ticks the per-second rules (the Harvest Pair's drought,
	# weeds and regrowth) and a Pamana's window: the preparation area between two
	# trials keeps trial_active false, so nothing there pays or takes FAVOR.
	if trial_active:
		m.pamana_window = maxf(0.0, m.pamana_window - delta)
		_tick_harvest(m, delta)
	_tick_bathala_regrowth(m, delta)


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
		# The Manunggul Jar gives back its share of what was lost, before Favorable
		# Outcome judges the top: straight to the total, so Full Moon cannot inflate it.
		harvest[m.id] = int(harvest[m.id]) + _settle_jar(m)
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
		# A Pamana lasts one trial: unused charges and windows expire here (Surigao
		# Gold is not one of them - it waits for its milestone).
		m.pamana_active = &""
		m.pamana_window = 0.0
		m.agimat_charges = 0
		m.kampilan_ready = false
		m.jar_lost = 0
	trial_active = false
	return summary


func _settle_jar(m: Mortal) -> int:
	if m.pamana_active != Pamanas.MANUNGGUL_JAR or m.jar_lost <= 0:
		return 0
	var jar := Pamanas.by_id(Pamanas.MANUNGGUL_JAR)
	var back := int(floor(float(m.jar_lost) * jar.param("return_share", 0.25)))
	m.jar_lost = 0
	if back > 0:
		_apply(m, back, jar.display_name)
		_fire_pamana(m, jar.id, "MANUNGGUL JAR - %d FAVOR CARRIED BACK" % back)
	return back
