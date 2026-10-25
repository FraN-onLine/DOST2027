class_name HananArena
extends Arena

# HANAN - Luksong Baka. (scripts/gods/hanan + scenes/gods/hanan)
#
# EVERYTHING SHARED LIVES IN THE BASE (scripts/gods/common/arena.gd): the clock,
# the countdown, the mortal, the dialogues, the God's Due menu, the popups and the
# network plumbing. This file is only what makes the game Hanan's.
#
# A PERSONAL TRIAL (like Apolaki's)
#   Every mortal vaults their OWN Baka on their own screen: no rival is drawn and
#   no position travels (separate_players). What is shared is FAVOR and the favors
#   - the FAVOR a vault earns or costs goes through score_favor(), so a client asks
#   the host and the host banks it.
#
# THE VAULT
#   RUN      run (WASD) into the Baka, from either side.
#   READY    every vault opens with `ready_time` seconds of "READY... LEAP!": the
#            bar shows, the box is still, the indicator is held in it and the
#            mortal crouches. Nothing is earned and the grace clock does not run.
#   VAULT    for `vault_window` seconds the mortal leaps OVER the Baka: their x
#            moves smoothly across `vault_span` (centred on the Baka) while the
#            balance bar drives their height. HOLD LEFT CLICK (the `attack`
#            action) to push the jump indicator up, let go and it falls. Keep it
#            inside the target box and FAVOR flows every second, times the combo
#            (the rate shows beside the bar). Drift out for longer than
#            `grace_time` and the mortal TRIPS.
#   A clean vault lands them on the FAR side, free to move and facing the Baka
#   again - the next vault goes back the other way. It adds `combo_step` to the
#   combo (up to `combo_cap`), and every `vaults_per_level` clean vaults the Baka
#   gets harder:
#     1 Low Baka, 2 Sitting Baka, 3 Standing Baka, 4 High Baka, 5+ Over the Moon.
#   Hanan herself is the Baka (HananBaka.tscn): this file hands her the level
#   (set_level: crouched, sitting, standing - taller past Standing Baka) and a
#   trip (bump). Her art is only a look: every vault number is the level's.
#   STUMBLE  a trip drops the mortal at the Baka's feet on the side they came
#            from and shoves them back; it costs trip_penalty_base +
#            trip_penalty_per_level for each level above the first (40 at Low
#            Baka, 120 at Over the Moon) and resets the combo. They stay where
#            they landed and run in again.
#   IDLE     a mortal who has not started a vault for `idle_time` seconds loses
#            `idle_penalty` FAVOR (never below 0), again every idle_time while they
#            keep standing about. The clock runs only while they are running free
#            (not in a vault or stumble, not locked, no dialogue or God's Due menu
#            open) and starts afresh after each vault, trip or penalty. The last 2
#            seconds warn "LEAP! 2... 1..." and the effect timers count it down.
#   HANAN'S MERCY  `mercy_trips` trips in a row at the same level drop the level
#            by one (never below 1): "THE BAKA CROUCHES". A clean vault resets
#            the count.
#   FIRST VISIT  the first vault of the trial is a practice vault: the box is
#            `practice_box_scale` times its size, a trip costs nothing and does
#            not count for mercy, and "HOLD LEFT CLICK" waits beside the bar
#            until the button is first held. It still pays FAVOR.
#
# THE BLITZ (the last baka_blitz_time seconds, derived from the shared clock so every
# screen enters it together). The vault stays this mortal's own, so the state is local.
#   - FAVOR earned in the box pays baka_blitz_favor times (trip and idle penalties do not change).
#   - From the NEXT vault on (never one already running) the bar is INVERTED: HOLD
#     LEFT CLICK to sink the indicator, let go and it rises. The bar is gentler too:
#     it rises at most at blitz_rise_accel, sinks at blitz_sink_accel and is capped
#     at blitz_max_speed (normal vaults keep lift_accel, gravity and max_speed).
#     That vault's window also runs baka_blitz_extra_time seconds longer.
#   - The field pulses in Hanan's colour (a field-only overlay, never the mortal,
#     the Baka or the HUD), and the HUD says the controls are inverted: a banner, a
#     line in the bottom band, the hint strip, an arrow on the bar while held, and an
#     INVERTED! callout at the start of each blitz vault.
#
# The bar works in 0..1 "bar heights" (0 = bottom of the gauge), so the HUD only
# has to scale it to pixels. Every number is an @export - tune it in the inspector.

enum Vault { RUN, VAULT, STUMBLE }

const LEVEL_NAMES := ["LOW BAKA", "SITTING BAKA", "STANDING BAKA", "HIGH BAKA", "OVER THE MOON"]
# Hanan's art is drop-in (see Assets/Gods/Hanan/README.md): each file is used when
# it exists and the placeholder stays when it does not.
const ART_DIR := "res://Assets/Gods/Hanan/"
const SCREEN_SIZE := Vector2(1152.0, 648.0)  # the authored arena (see arena.gd)
const CLEAN_COLOR := Color(0.7, 1, 0.8)
const TRIP_COLOR := Color(1, 0.5, 0.45)

@export_category("Luksong Baka")
@export var vault_window := 3.0            # seconds the balance bar runs per vault
@export var baka_blitz_time := 30.0        # the last seconds: inverted bar, more FAVOR, longer vaults
@export var baka_blitz_favor := 1.2        # times the FAVOR earned in the box during the blitz
@export var baka_blitz_extra_time := 2.0   # seconds added to vault_window for a vault that opens in the blitz
@export var blitz_rise_accel := 1.1        # bar heights/s^2 a blitz vault's indicator rises while let go (1.3 flung it out of a level-1 box)
@export var blitz_sink_accel := 1.6        # bar heights/s^2 it sinks while held
@export var blitz_max_speed := 0.7         # fastest a blitz vault's indicator may move
@export var grace_time := 0.35             # seconds outside the box before a trip
@export var vaults_per_level := 3          # clean vaults that advance the level
@export var favor_per_second := 40.0       # FAVOR/s inside the box, times the combo
@export var combo_step := 0.25             # combo gained per clean vault
@export var combo_cap := 3.0
@export var trip_penalty_base := 40       # FAVOR lost on a trip at Low Baka...
@export var trip_penalty_per_level := 20  # ...plus this for every level above it
@export var idle_time := 5.0               # seconds running free before standing about costs FAVOR
@export var idle_penalty := 200            # FAVOR lost each time idle_time runs out
@export var mercy_trips := 2              # trips in a row at one level that lower it
@export var ready_time := 0.6             # the READY beat before each vault
@export var vault_span := 140.0           # how far the leap carries the mortal, centred on the Baka
@export var practice_box_scale := 1.5     # the first-visit practice vault's box
@export var bank_interval := 0.5           # the host is asked for FAVOR this often, not every frame
@export var stumble_time := 1.0            # seconds the mortal stumbles after a trip
@export var stumble_force := 320.0
# How close to the Baka a run starts the vault. Keep it under vault_span / 2, so
# a mortal who just landed is not caught by the next vault before they turn.
@export var vault_trigger_distance := 60.0
@export var jump_height := 90.0            # pixels the mortal rises at the top of the bar

@export_category("Balance Bar")
@export var lift_accel := 2.6              # bar heights/s^2 while the button is held
@export var gravity := 2.2                 # bar heights/s^2 while it is not
@export var max_speed := 1.1               # fastest the indicator may move
@export var bounce := 0.25                 # how much speed survives hitting the floor / ceiling
@export var indicator_size := 0.06         # the indicator's height, in bar heights
# One entry per level (the last one repeats for level 5 and beyond).
@export var box_sizes := PackedFloat32Array([0.42, 0.30, 0.26, 0.15, 0.13])
@export var drift_speeds := PackedFloat32Array([0.14, 0.18, 0.38, 0.30, 0.50])
@export var burst_multiplier := 3.2        # level 4: how much faster the box moves in a burst
# Over the Moon's shake (level 5+) is the base's shake_pixels (Arena, Screen
# Impact), set to 5 in HananArena.tscn - redeclaring it here is a parse error.
@export var bar_offset := Vector2(36.0, 0.0)  # where the bar hangs, from the mortal's feet

@onready var baka: HananBaka = get_node_or_null("ArenaField/Baka")
@onready var overseer: Sprite2D = get_node_or_null("ArenaField/Overseer")
@onready var background: Sprite2D = get_node_or_null("Background")
# The labels sit high (the callout in the base's popup pill, the status and hint
# in the base's bottom band, both above every field effect) so they stay readable.
# The bar sits LOW (BarLayer, below Mayari's VisionLayer and Apolaki's Patches):
# a blackout or a sun patch must hide it like it hides any other trial's field.
@onready var bar_layer: CanvasLayer = get_node_or_null("BarLayer")
@onready var bar: BakaGauge = get_node_or_null("BarLayer/Bar")  # drawn by scripts/gods/hanan/baka_gauge.gd
@onready var rate_label: Label = get_node_or_null("BarLayer/Bar/Rate")
@onready var hold_prompt: Label = get_node_or_null("BarLayer/Bar/HoldPrompt")
@onready var status_label: Label = get_node_or_null(BAND_STATE + "Status")
@onready var blitz_glow: Sprite2D = get_node_or_null("ArenaBG/BlitzGlow")  # a soft oval on the arena floor, under the Baka and the mortal
@onready var sink_arrow: Polygon2D = get_node_or_null("BarLayer/Bar/SinkArrow")

var _vault_state := Vault.RUN
var _level := 1
var _clean_in_level := 0
var _clean_total := 0
var _trips := 0
var _trips_in_row := 0  # trips at this level since the last clean vault (Hanan's mercy)
var _combo := 1.0
var _holding := false
var _vault_left := 0.0
var _vault_total := 0.0   # this vault's window (longer when it opened in the blitz)
var _blitz := false       # the last baka_blitz_time seconds (from the shared clock, same on every screen)
var _blitz_vault := false # this vault opened in the blitz: inverted bar, longer window
var _blitz_phase := 0.0   # the field pulse's clock
var _outside_time := 0.0
var _state_timer := 0.0
var _ind_pos := 0.0
var _ind_vel := 0.0
var _box_center := 0.5
var _box_goal := 0.5
var _box_dir := 1.0
var _box_timer := 0.0
var _box_paused := false
var _box_speed_factor := 1.0
var _pending_gain := 0.0
var _bank_timer := 0.0
var _ground_y := 0.0
var _idle_left := 5.0   # seconds of running free before the idle penalty
var _frozen := false  # the God's Due menu or a dialogue is open over a vault
var _ready_left := 0.0  # the READY beat still to run before the vault itself
var _from_x := 0.0      # the leap: from the approach side...
var _to_x := 0.0        # ...to the landing side
var _practice := false  # first visit: the next vault is the practice vault
var _practice_vault := false
var _held_once := false


# --- ARENA HOOKS (see scripts/gods/common/arena.gd) --------------------------

func separate_players() -> bool:
	return true


func shares_mortal_positions() -> bool:
	return false


# The Guidance reads "another mortal is nearby" - there is nobody else on this field.
func nearby_movement_favors_enabled() -> bool:
	return false


# The follow camera's edge arrow: the Baka, which the mortal has to run into.
func edge_targets() -> Array:
	return [baka] if baka != null else []


func collect_units() -> void:
	_apply_art()


func arena_round_reset() -> void:
	_level = 1
	_clean_in_level = 0
	_clean_total = 0
	_trips = 0
	_trips_in_row = 0
	_combo = 1.0
	_practice = first_visit
	_practice_vault = false
	_held_once = false
	_pending_gain = 0.0
	_holding = false
	_blitz = false
	_blitz_vault = false
	if blitz_glow != null:
		blitz_glow.visible = false
	_leave_vault()
	_enter_run(false)  # the base put the mortal on its spawn and unlocks it when the round starts
	_set_callout("", Color.WHITE, 0.0)


# The round ends while a vault is still paying: bank it BEFORE the base settles
# the trial (rules.end_trial() writes the results), so it shows in this trial's
# standings and not only in the next one.
func _end_trial() -> void:
	if _vault_state == Vault.VAULT:
		_bank()
	super._end_trial()


# --- THE LEVEL TABLE ---------------------------------------------------------

func level_name() -> String:
	return LEVEL_NAMES[mini(_level, LEVEL_NAMES.size()) - 1]


func current_box_size() -> float:
	var size: float = box_sizes[mini(_level, box_sizes.size()) - 1]
	return size * (practice_box_scale if _practice_vault else 1.0)


func current_drift_speed() -> float:
	return drift_speeds[mini(_level, drift_speeds.size()) - 1]


# 40 at Low Baka, 20 more a level, 120 at Over the Moon (and beyond).
func trip_penalty() -> int:
	return trip_penalty_base + trip_penalty_per_level * (mini(_level, LEVEL_NAMES.size()) - 1)


# --- FRAME -------------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	_tick_hanan(delta)
	_refresh_hud(delta)


func _tick_hanan(delta: float) -> void:
	_update_blitz(delta)
	if _phase != Phase.PLAYING:
		_holding = false
		if _vault_state != Vault.RUN:
			if _vault_state == Vault.VAULT:
				_bank()  # what the vault earned so far is the mortal's, round over or not
			_leave_vault()
			_enter_run(false)
		return
	match _vault_state:
		Vault.RUN:
			if baka != null and not player.locked and player.global_position.distance_to(baka.global_position) <= vault_trigger_distance:
				begin_vault()
			else:
				_tick_idle(delta)
		Vault.VAULT:
			_tick_vault(delta)
		Vault.STUMBLE:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_enter_run()


# --- IDLE --------------------------------------------------------------------

# Running free (the clock only counts then): not locked for the countdown or the
# GO drop, and no dialogue or God's Due menu open over the arena.
func _idle_ticking() -> bool:
	return _phase == Phase.PLAYING and _vault_state == Vault.RUN and not player.locked 		and not dialogue.is_active() and not due_menu.is_open()


func _tick_idle(delta: float) -> void:
	if not _idle_ticking():
		return
	_idle_left -= delta
	if _idle_left > 0.0:
		if _idle_left <= 2.0:
			_set_callout("LEAP! %d..." % ceili(_idle_left), TRIP_COLOR, 0.25)
		return
	_idle_left = idle_time
	var lost := mini(idle_penalty, local_favor())  # never below 0
	if lost > 0:
		score_favor(-lost, "Idle at the Baka")
		_set_callout("-%d IDLE" % lost, TRIP_COLOR, 1.0)


# The countdown in the effect timers once the penalty is under 3 s away.
func arena_local_effects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _idle_ticking() and _idle_left < 3.0:
		out.append(effect(&"idle", "IDLE", null, TRIP_COLOR, _idle_left, 3.0, true))
	return out


# --- THE BLITZ ---------------------------------------------------------------

func _update_blitz(delta: float) -> void:
	var blitz_now := _phase == Phase.PLAYING and _trial_time <= baka_blitz_time
	if blitz_now != _blitz:
		_blitz = blitz_now
		if _blitz:
			_show_banner("BLITZ! CONTROLS INVERTED", UITokens.god_accent(god), 2.5)
			_log("BLITZ! The bar is inverted from the next leap: hold to sink. FAVOR x%.1f" % baka_blitz_favor, UITokens.god_accent(god))
	if blitz_glow == null:
		return
	blitz_glow.visible = _blitz
	if not _blitz:
		return
	blitz_glow.global_position = _field.get_center()
	blitz_glow.scale = _field.size / Vector2(blitz_glow.texture.get_size())
	_blitz_phase += delta * 3.0
	var accent := UITokens.god_accent(god)
	blitz_glow.modulate = Color(accent.r, accent.g, accent.b, 0.12 if reduce_flashing() else 0.08 + 0.2 * (sin(_blitz_phase) * 0.5 + 0.5))


# Hold LEFT CLICK to rise (in a blitz vault: to sink). Read in _input (not _unhandled_input) because the shell
# draws a full-screen Control over the arena and a GUI mouse event would never
# reach us otherwise - the same reason Apolaki reads his buttons here.
func _input(event: InputEvent) -> void:
	# A click on one of the favor panels is the HUD's answer, not a rise.
	if super._tap_panel_click(event):
		return
	if not (event is InputEventMouseButton):
		return
	if event.is_action_pressed("attack"):
		_holding = _phase == Phase.PLAYING and not dialogue.is_active() and not due_menu.is_open()
		_held_once = _held_once or (_holding and _vault_state == Vault.VAULT)
	elif event.is_action_released("attack"):
		_holding = false


# --- RUN / VAULT / STUMBLE ---------------------------------------------------

# Back to running, wherever the mortal stands: the far side after a clean vault,
# the approach side after a trip. (The base puts it on its spawn each round.)
func _enter_run(unlock := true) -> void:
	_vault_state = Vault.RUN
	_idle_left = idle_time
	if unlock:
		player.set_lock(false)
	_show_baka_height()


# The mortal ran into the Baka: the leap goes from this side to the other one,
# and opens with the READY beat - the bar up, the indicator held in the box.
func begin_vault() -> void:
	_vault_state = Vault.VAULT
	_idle_left = idle_time
	_blitz_vault = _blitz
	_vault_total = vault_window + (baka_blitz_extra_time if _blitz_vault else 0.0)
	_vault_left = _vault_total
	_ready_left = ready_time
	_practice_vault = _practice
	_practice = false
	var centre := baka.global_position.x if baka != null else player.global_position.x
	var side := -1.0 if player.global_position.x < centre else 1.0
	_from_x = centre + side * vault_span * 0.5
	_to_x = centre - side * vault_span * 0.5
	player.global_position.x = _from_x
	_outside_time = 0.0
	_bank_timer = bank_interval
	_ind_vel = 0.0
	_box_dir = 1.0 if randf() < 0.5 else -1.0
	_box_timer = 0.0
	_box_paused = false
	_box_speed_factor = 1.0
	var half := current_box_size() * 0.5
	_box_center = clampf(0.35, half, 1.0 - half)
	_box_goal = _box_center
	_ind_pos = _box_center
	_ground_y = player.global_position.y
	player.set_lock(true)
	player.scale = Vector2(1.0, 0.85)  # the crouch
	_set_callout("READY...
INVERTED!" if _blitz_vault else "READY...", god.color, ready_time)


func _tick_vault(delta: float) -> void:
	# Opening the God's Due menu (or a dialogue landing) mid-vault must not cost a
	# trip: the whole vault - indicator, box, clock, grace - waits, and nothing is
	# banked, until it closes.
	if dialogue.is_active() or due_menu.is_open():
		_frozen = true
		return
	if _frozen:
		_frozen = false
		# A click spent inside the menu is not a hold: take the button as it is now.
		_holding = Input.is_action_pressed("attack")
	if _ready_left > 0.0:
		# READY: the box waits, the indicator is held in it, nothing is earned.
		_ready_left -= delta
		_ind_pos = _box_center
		_ind_vel = 0.0
		if _ready_left <= 0.0:
			player.scale = Vector2.ONE
			_set_callout("LEAP!", god.color, 0.5)
		return
	_step_indicator(delta)
	_step_box(delta)
	if is_inside_box():
		_outside_time = 0.0
		_pending_gain += earn_rate() * delta
	else:
		_outside_time += delta
		if _outside_time > grace_time:
			_trip()
			return
	_bank_timer -= delta
	if _bank_timer <= 0.0:
		_bank_timer = bank_interval
		_bank()
	_vault_left -= delta
	var across := smoothstep(0.0, 1.0, 1.0 - _vault_left / maxf(0.01, _vault_total))
	player.global_position = Vector2(lerpf(_from_x, _to_x, across), _ground_y - _ind_pos * jump_height)
	if _vault_left <= 0.0:
		_clean_vault()


# FAVOR per second inside the box: the rate, the combo and the blitz's bonus.
func earn_rate() -> float:
	return favor_per_second * _combo * (baka_blitz_favor if _blitz else 1.0)


# Floaty on purpose: the button is an acceleration, not a position. A blitz vault
# is inverted and gentler: held sinks, let go rises, on its own blitz_* numbers.
func _step_indicator(delta: float) -> void:
	var accel := lift_accel if _holding else -gravity
	var cap := max_speed
	if _blitz_vault:
		accel = -blitz_sink_accel if _holding else blitz_rise_accel
		cap = blitz_max_speed
	_ind_vel = clampf(_ind_vel + accel * delta, -cap, cap)
	_ind_pos += _ind_vel * delta
	if _ind_pos < 0.0:
		_ind_pos = 0.0
		_ind_vel = maxf(0.0, -_ind_vel * bounce)
	elif _ind_pos > 1.0:
		_ind_pos = 1.0
		_ind_vel = minf(0.0, -_ind_vel * bounce)


# How the Baka's box moves, level by level:
#   1-2  a slow, smooth drift between resting points
#   3    erratic: new goals at random moments and random speeds
#   4    bursts of speed and sudden pauses
#   5+   straight runs that flip direction instantly
func _step_box(delta: float) -> void:
	var half := current_box_size() * 0.5
	var speed := current_drift_speed()
	_box_timer -= delta
	match mini(_level, 5):
		1, 2:
			if is_equal_approx(_box_center, _box_goal) and _box_timer <= 0.0:
				_box_goal = randf_range(half, 1.0 - half)
				_box_timer = randf_range(0.3, 0.8)
			_box_center = move_toward(_box_center, _box_goal, speed * delta)
		3:
			if _box_timer <= 0.0:
				_box_goal = randf_range(half, 1.0 - half)
				_box_speed_factor = randf_range(0.6, 1.6)
				_box_timer = randf_range(0.3, 0.9)
			_box_center = move_toward(_box_center, _box_goal, speed * _box_speed_factor * delta)
		4:
			if _box_timer <= 0.0:
				_box_paused = not _box_paused
				_box_timer = randf_range(0.3, 0.8) if _box_paused else randf_range(0.25, 0.5)
				_box_goal = randf_range(half, 1.0 - half)
			if not _box_paused:
				_box_center = move_toward(_box_center, _box_goal, speed * burst_multiplier * delta)
		_:
			if _box_timer <= 0.0:
				_box_dir = -_box_dir
				_box_timer = randf_range(0.2, 0.6)
			_box_center += _box_dir * speed * delta
			if _box_center <= half or _box_center >= 1.0 - half:
				_box_dir = -_box_dir
	_box_center = clampf(_box_center, half, 1.0 - half)


func is_inside_box() -> bool:
	return absf(_ind_pos - _box_center) <= (current_box_size() + indicator_size) * 0.5


# FAVOR earned inside the box, asked of the host in whole points every
# bank_interval (not every frame) and once more when the vault ends.
func _bank() -> void:
	var amount := int(_pending_gain)
	if amount <= 0:
		return
	_pending_gain -= float(amount)
	score_favor(amount, "Luksong Baka")


func _clean_vault() -> void:
	_bank()
	_combo = minf(combo_cap, _combo + combo_step)
	_clean_total += 1
	_clean_in_level += 1
	_trips_in_row = 0
	var leveled := _clean_in_level >= vaults_per_level
	if leveled:
		_level += 1
		_clean_in_level = 0
	_set_callout("CLEAN!  COMBO x%.2f" % _combo, CLEAN_COLOR, 1.2)
	if bar != null:
		bar.flash_clean()
	_leave_vault()
	player.global_position.x = _to_x  # landed on the far side...
	_face(baka.global_position.x if baka != null else _from_x)  # ...turned to the Baka again
	_enter_run()
	if leveled:
		_show_level_banner()


func _trip() -> void:
	_bank()
	_pending_gain = 0.0
	var penalty := 0 if _practice_vault else trip_penalty()
	if penalty > 0:
		score_favor(-penalty, "Tripped over the Baka")
	_combo = 1.0
	_trips += 1
	var text := "TRIP!  -%d FAVOR" % penalty if penalty > 0 else "PRACTICE - NO FAVOR LOST"
	if not _practice_vault:
		_trips_in_row += 1
		if _trips_in_row >= mercy_trips and _level > 1:
			# Hanan's mercy: the Baka comes down a level.
			_level -= 1
			_clean_in_level = 0
			_trips_in_row = 0
			text += "\nTHE BAKA CROUCHES"
			_log("Hanan's mercy - the Baka crouches: %s" % level_name(), god.color)
	_set_callout(text, TRIP_COLOR, 1.2)
	if bar != null:
		bar.crack()
	_leave_vault()
	player.global_position.x = _from_x  # at the Baka's feet, on the side they came from
	if baka != null:
		baka.bump()
	_vault_state = Vault.STUMBLE
	_state_timer = stumble_time
	player.set_lock(false)
	var from := baka.global_position if baka != null else player.global_position + Vector2.RIGHT
	_apply_knockback(player.global_position - from, stumble_time, stumble_force)


# Back on the ground (the vault ended one way or the other).
func _leave_vault() -> void:
	if _vault_state == Vault.VAULT:
		player.global_position.y = _ground_y
	player.scale = Vector2.ONE
	_practice_vault = false
	_ready_left = 0.0
	_ind_vel = 0.0
	_ind_pos = 0.0


func _face(x: float) -> void:
	player.facing = 1 if x > player.global_position.x else -1
	player._apply_facing()


func _show_level_banner() -> void:
	_show_banner("LEVEL %d  -  %s" % [_level, level_name()], god.color, 1.8)
	_log("The Baka grows: %s" % level_name(), god.color)


# --- ART ---------------------------------------------------------------------

static func art(file: String) -> Texture2D:
	var path := ART_DIR + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _apply_art() -> void:
	_show_baka_height()
	var watcher := art("Hanan-Overseer.png")
	if overseer != null:
		overseer.texture = watcher
		overseer.visible = watcher != null
	var backdrop := art("Arena-Background.png")
	if background != null and backdrop != null:
		# The placeholder's transform was tuned for Mayari's image; a real
		# background simply fills the authored screen.
		background.texture = backdrop
		background.position = SCREEN_SIZE * 0.5
		background.scale = SCREEN_SIZE / backdrop.get_size()


# Hanan shows the level: crouched, sitting, standing, taller past Standing Baka.
func _show_baka_height() -> void:
	if baka != null:
		baka.set_level(_level)


# --- HUD ---------------------------------------------------------------------

# READY... / LEAP! / CLEAN! / TRIP! over the mortal, in the base's callout pill.
func _set_callout(text: String, tint: Color, seconds: float) -> void:
	callout(text, tint, seconds)


func _refresh_hud(_delta: float) -> void:
	var in_vault := _vault_state == Vault.VAULT
	if rate_label != null:
		rate_label.visible = in_vault and _ready_left <= 0.0 and is_inside_box()
		rate_label.text = "+%d/s  x%.2f" % [int(round(earn_rate())), _combo]
	if hold_prompt != null:
		hold_prompt.visible = in_vault and _practice_vault and not _held_once
		if hold_prompt.visible:
			hold_prompt.modulate.a = 1.0 if reduce_flashing() else 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.006))
	if bar != null:
		bar.visible = in_vault or bar.lingering()
		if in_vault:
			_place_bar()
			bar.feed({
				"ind_pos": _ind_pos, "box_center": _box_center, "box_size": current_box_size(),
				"marker_size": indicator_size, "inside": _ready_left > 0.0 or is_inside_box(),
				"grace": clampf(_outside_time / maxf(0.01, grace_time), 0.0, 1.0),
				"vault": 0.0 if _ready_left > 0.0 else 1.0 - _vault_left / maxf(0.01, _vault_total),
				"level": _level, "level_name": level_name(), "inverted": _blitz_vault,
				"earning": _ready_left <= 0.0 and is_inside_box(), "calm": reduce_flashing(),
				"accent": UITokens.god_accent(god),
			})
		_place_bar_pills(in_vault)
	if status_label != null:
		status_label.text = "LEVEL %d  %s     COMBO x%.2f     CLEAN %d  TRIPS %d" % [
			_level, level_name(), _combo, _clean_total, _trips]
		if _blitz:  # (a leap already running keeps the old controls until it ends)
			status_label.text = ("INVERTED: HOLD TO SINK" if _blitz_vault or not in_vault else "INVERTED AFTER THIS LEAP") + "     " + status_label.text
	if hint_label != null:
		if in_vault and _blitz_vault:
			hint_label.text = "%s HOLD TO SINK, LET GO TO RISE   KEEP THE JUMP IN THE BOX" % key_cap(&"attack")
		elif in_vault:
			hint_label.text = "HOLD %s TO RISE   LET GO TO FALL   KEEP THE JUMP IN THE BOX" % key_cap(&"attack")
		else:
			hint_label.text = "RUN INTO THE BAKA TO LEAP   %s" % favor_keys_hint()
	# Over the Moon shakes the field and the bar - never the labels, which must
	# stay readable - unless the player turned shaking off.
	var shake := Vector2.ZERO
	if in_vault and _level >= 5 and screen_shake_allowed():
		shake = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_pixels
	if bar_layer != null:
		bar_layer.offset = shake
	field_root.position = shake


# The bar hangs beside the mortal (on the ground they jumped from, so it does not
# ride up and down with the jump), on the side away from Hanan, and never over her
# body, the overseer's face, the UI strip or the bottom band. Under Half Vision
# only the lit circle round the mortal shows - and part of the bar with it, the
# same way a blinded player still sees the field near them.
func _place_bar() -> void:
	var anchor := player.get_global_transform_with_canvas().origin
	anchor.y += _ground_y - player.global_position.y
	var view := get_viewport_rect().size
	var low := view.y
	if band != null and band.is_visible_in_tree():
		low = minf(low, band.get_global_rect().position.y)
	var hanan := baka.screen_rect().grow(4.0) if baka != null else Rect2()
	var away_right := not hanan.has_area() or anchor.x >= hanan.get_center().x
	var size := bar.size
	var x := anchor.x + bar_offset.x if away_right else anchor.x - bar_offset.x - size.x
	var rect := Rect2(Vector2(x, anchor.y + bar_offset.y - size.y * 0.5), size)
	for block in [hanan, _face_rect()]:
		if block.has_area() and rect.intersects(block):
			rect.position.x = block.end.x if away_right else block.position.x - size.x
	var lowest := Vector2(UI_STRIP_WIDTH + 2.0, 2.0)
	rect.position = rect.position.clamp(lowest, (Vector2(view.x, low) - size - Vector2(2.0, 2.0)).max(lowest))
	if hanan.has_area() and rect.intersects(hanan):  # pushed back into her by a screen edge: above her instead
		rect.position.y = maxf(2.0, hanan.position.y - size.y)
	bar.position = rect.position.round()
	bar.outer_left = not away_right


# The callout pill (READY..., TRIP!) sits above the bar, never over its level name.
func callout_keep_out() -> Rect2:
	return Rect2(bar.position, bar.size) if bar != null and bar.visible else Rect2()


# The overseer's face (the scene's FaceFocus marker), on screen: the bar never covers it.
func _face_rect() -> Rect2:
	var face := get_node_or_null("FaceFocus") as Node2D
	if face == null:
		return Rect2()
	return Rect2(face.get_global_transform_with_canvas().origin - Vector2(100.0, 90.0), Vector2(200.0, 180.0))


# The rate pill (it grows a little with the combo) and the practice prompt on the
# bar's outer side, the blitz's sink arrow on the mortal's side of the marker.
func _place_bar_pills(in_vault: bool) -> void:
	var track := bar.track_rect()
	var outer := -6.0 if bar.outer_left else bar.size.x + 6.0
	if rate_label != null and rate_label.visible:
		rate_label.reset_size()
		rate_label.pivot_offset = Vector2(rate_label.size.x if bar.outer_left else 0.0, rate_label.size.y * 0.5)
		rate_label.scale = Vector2.ONE * (1.0 + 0.08 * (_combo - 1.0))
		rate_label.position = Vector2(outer - (rate_label.size.x if bar.outer_left else 0.0), track.get_center().y - rate_label.size.y * 0.5).round()
	if hold_prompt != null and hold_prompt.visible:
		hold_prompt.reset_size()
		hold_prompt.position = Vector2(outer - (hold_prompt.size.x if bar.outer_left else 0.0), track.get_center().y - hold_prompt.size.y - 20.0).round()
	if sink_arrow != null:  # inverted: an arrow beside the marker while the button sinks it
		sink_arrow.visible = in_vault and _blitz_vault and _holding
		var beside := track.end.x + 16.0 if bar.outer_left else track.position.x - 16.0
		sink_arrow.position = Vector2(beside, roundf(track.position.y + (1.0 - _ind_pos) * track.size.y))
