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
#   RUN      run (WASD) up to the Baka.
#   VAULT    a balance bar appears for `vault_window` seconds. HOLD LEFT CLICK
#            (the `attack` action) to push the jump indicator up, let go and it
#            falls. Keep it inside the target box and FAVOR flows every second,
#            multiplied by the combo. Drift out for longer than `grace_time` and
#            the mortal TRIPS.
#   STUMBLE  a trip costs `trip_penalty` FAVOR, resets the combo and shoves the
#            mortal back; then it is back to RUN for the next vault.
#   A clean vault adds `combo_step` to the combo (up to `combo_cap`). Every
#   `vaults_per_level` clean vaults the Baka gets harder:
#     1 Low Baka, 2 Sitting Baka, 3 Standing Baka, 4 High Baka, 5+ Over the Moon.
#
# The bar works in 0..1 "bar heights" (0 = bottom of the gauge), so the HUD only
# has to scale it to pixels. Every number is an @export - tune it in the inspector.

enum Vault { RUN, VAULT, STUMBLE }

const LEVEL_NAMES := ["LOW BAKA", "SITTING BAKA", "STANDING BAKA", "HIGH BAKA", "OVER THE MOON"]
const CLEAN_COLOR := Color(0.7, 1, 0.8)
const TRIP_COLOR := Color(1, 0.5, 0.45)

@export_category("Luksong Baka")
@export var vault_window := 3.0            # seconds the balance bar runs per vault
@export var grace_time := 0.35             # seconds outside the box before a trip
@export var vaults_per_level := 3          # clean vaults that advance the level
@export var favor_per_second := 40.0       # FAVOR/s inside the box, times the combo
@export var combo_step := 0.25             # combo gained per clean vault
@export var combo_cap := 3.0
@export var trip_penalty := 120            # FAVOR lost on a trip
@export var bank_interval := 0.5           # the host is asked for FAVOR this often, not every frame
@export var stumble_time := 1.0            # seconds the mortal stumbles after a trip
@export var stumble_force := 320.0
@export var vault_trigger_distance := 90.0 # how close to the Baka a run starts the vault
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
@export var shake_pixels := 5.0            # level 5+: how hard the screen shakes
@export var bar_offset := Vector2(36.0, 0.0)  # where the bar hangs, from the mortal's feet

@onready var baka: Node2D = get_node_or_null("ArenaField/Baka")
# The labels sit high (HananHud, above everything) so they always stay readable.
# The bar sits LOW (BarLayer, below Mayari's VisionLayer and Apolaki's Patches):
# a blackout or a sun patch must hide it like it hides any other trial's field.
@onready var hud_layer: CanvasLayer = get_node_or_null("HananHud")
@onready var bar_layer: CanvasLayer = get_node_or_null("BarLayer")
@onready var bar: Control = get_node_or_null("BarLayer/Bar")
@onready var box: ColorRect = get_node_or_null("BarLayer/Bar/Box")
@onready var indicator: ColorRect = get_node_or_null("BarLayer/Bar/Indicator")
@onready var status_label: Label = get_node_or_null("HananHud/Status")
@onready var callout_label: Label = get_node_or_null("HananHud/Callout")
@onready var hint_label: Label = get_node_or_null("HananHud/Hint")

var _vault_state := Vault.RUN
var _level := 1
var _clean_in_level := 0
var _clean_total := 0
var _trips := 0
var _combo := 1.0
var _holding := false
var _vault_left := 0.0
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
var _callout_time := 0.0
var _frozen := false  # the God's Due menu or a dialogue is open over a vault


# --- ARENA HOOKS (see scripts/gods/common/arena.gd) --------------------------

func separate_players() -> bool:
	return true


func shares_mortal_positions() -> bool:
	return false


# The Guidance reads "another mortal is nearby" - there is nobody else on this field.
func nearby_movement_favors_enabled() -> bool:
	return false


func arena_round_reset() -> void:
	_level = 1
	_clean_in_level = 0
	_clean_total = 0
	_trips = 0
	_combo = 1.0
	_pending_gain = 0.0
	_holding = false
	_leave_vault()
	_enter_run(false)  # the base unlocks the mortal when the round starts
	_set_callout("", Color.WHITE, 0.0)


# --- THE LEVEL TABLE ---------------------------------------------------------

func level_name() -> String:
	return LEVEL_NAMES[mini(_level, LEVEL_NAMES.size()) - 1]


func current_box_size() -> float:
	return box_sizes[mini(_level, box_sizes.size()) - 1]


func current_drift_speed() -> float:
	return drift_speeds[mini(_level, drift_speeds.size()) - 1]


# --- FRAME -------------------------------------------------------------------

func _process(delta: float) -> void:
	super._process(delta)
	_tick_hanan(delta)
	_refresh_hud(delta)


func _tick_hanan(delta: float) -> void:
	if _phase != Phase.PLAYING:
		_holding = false
		if _vault_state != Vault.RUN:
			_leave_vault()
			_enter_run(false)
		return
	match _vault_state:
		Vault.RUN:
			if baka != null and not player.locked and player.global_position.distance_to(baka.global_position) <= vault_trigger_distance:
				begin_vault()
		Vault.VAULT:
			_tick_vault(delta)
		Vault.STUMBLE:
			_state_timer -= delta
			if _state_timer <= 0.0:
				_enter_run()


# Hold LEFT CLICK to rise. Read in _input (not _unhandled_input) because the shell
# draws a full-screen Control over the arena and a GUI mouse event would never
# reach us otherwise - the same reason Apolaki reads his buttons here.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if event.is_action_pressed("attack"):
		_holding = _phase == Phase.PLAYING and not dialogue.is_active() and not due_menu.is_open()
	elif event.is_action_released("attack"):
		_holding = false


# --- RUN / VAULT / STUMBLE ---------------------------------------------------

func _enter_run(unlock := true) -> void:
	_vault_state = Vault.RUN
	player.global_position = _start_position
	if unlock:
		player.set_lock(false)
	if baka != null:
		baka.scale.y = 0.6 + 0.2 * mini(_level, LEVEL_NAMES.size())


# The mortal reached the Baka: the bar starts, with the indicator already in the box.
func begin_vault() -> void:
	_vault_state = Vault.VAULT
	_vault_left = vault_window
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
	_set_callout("VAULT!", god.color, 0.6)


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
	_step_indicator(delta)
	_step_box(delta)
	if is_inside_box():
		_outside_time = 0.0
		_pending_gain += favor_per_second * _combo * delta
	else:
		_outside_time += delta
		if _outside_time > grace_time:
			_trip()
			return
	_bank_timer -= delta
	if _bank_timer <= 0.0:
		_bank_timer = bank_interval
		_bank()
	player.global_position.y = _ground_y - _ind_pos * jump_height
	_vault_left -= delta
	if _vault_left <= 0.0:
		_clean_vault()


# Floaty on purpose: the button is an acceleration, not a position.
func _step_indicator(delta: float) -> void:
	var accel := lift_accel if _holding else -gravity
	_ind_vel = clampf(_ind_vel + accel * delta, -max_speed, max_speed)
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
	var leveled := _clean_in_level >= vaults_per_level
	if leveled:
		_level += 1
		_clean_in_level = 0
	_set_callout("CLEAN!  COMBO x%.2f" % _combo, CLEAN_COLOR, 1.2)
	_leave_vault()
	_enter_run()
	if leveled:
		_show_level_banner()


func _trip() -> void:
	_bank()
	_pending_gain = 0.0
	score_favor(-trip_penalty, "Tripped over the Baka")
	_combo = 1.0
	_trips += 1
	_set_callout("TRIP!  -%d FAVOR" % trip_penalty, TRIP_COLOR, 1.2)
	_leave_vault()
	_vault_state = Vault.STUMBLE
	_state_timer = stumble_time
	player.set_lock(false)
	var from := baka.global_position if baka != null else player.global_position + Vector2.RIGHT
	_apply_knockback(player.global_position - from, stumble_time, stumble_force)


# Back on the ground (the vault ended one way or the other).
func _leave_vault() -> void:
	if _vault_state == Vault.VAULT:
		player.global_position.y = _ground_y
	_ind_vel = 0.0
	_ind_pos = 0.0


func _show_level_banner() -> void:
	_show_banner("LEVEL %d  -  %s" % [_level, level_name()], god.color, 1.8)
	_log("The Baka grows: %s" % level_name(), god.color)


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
	var in_vault := _vault_state == Vault.VAULT
	if bar != null:
		bar.visible = in_vault
		if in_vault:
			_place_bar()
		if in_vault and box != null and indicator != null:
			var track := bar.size.y
			box.size.y = current_box_size() * track
			box.position.y = (1.0 - _box_center - current_box_size() * 0.5) * track
			var marker := maxf(4.0, indicator_size * track)
			indicator.size.y = marker
			indicator.position.y = (1.0 - _ind_pos) * track - marker * 0.5
			box.color = Color(0.7, 1, 0.8, 0.55) if is_inside_box() else Color(1, 0.5, 0.45, 0.55)
	if status_label != null:
		status_label.text = "LEVEL %d  %s     COMBO x%.2f     CLEAN %d  TRIPS %d" % [
			_level, level_name(), _combo, _clean_total, _trips]
	if hint_label != null:
		hint_label.text = "HOLD LEFT CLICK - RISE    RELEASE - FALL    KEEP THE JUMP IN THE BOX" if in_vault \
			else "RUN TO THE BAKA    E / Q - FAVORS    F - GOD'S DUE"
	# Over the Moon shakes the screen - unless the player turned shaking off.
	var shake := Vector2.ZERO
	if in_vault and _level >= 5 and screen_shake_allowed():
		shake = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake_pixels
	if hud_layer != null:
		hud_layer.offset = shake
	if bar_layer != null:
		bar_layer.offset = shake
	field_root.position = shake


# The bar hangs beside the mortal (on the ground they jumped from, so it does not
# ride up and down with the jump), kept on screen and clear of the UI strip. Under
# Half Vision only the lit circle round the mortal shows - and part of the bar
# with it, the same way a blinded player still sees the field near them.
func _place_bar() -> void:
	var anchor := player.get_global_transform_with_canvas().origin
	anchor.y += _ground_y - player.global_position.y
	var view := get_viewport_rect().size
	var top_left := anchor + bar_offset - Vector2(0.0, bar.size.y * 0.5)
	bar.position = top_left.clamp(Vector2(UI_STRIP_WIDTH, 0.0), (view - bar.size).max(Vector2(UI_STRIP_WIDTH, 0.0)))
