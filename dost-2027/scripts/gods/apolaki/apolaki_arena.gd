class_name ApolakiArena
extends Arena

# APOLAKI - arnis. (scripts/gods/apolaki + scenes/gods/apolaki)
#
# EVERYTHING SHARED LIVES IN THE BASE (scripts/gods/common/arena.gd): the clock,
# the countdown, the mortal, the dialogues, the God's Due menu, the popups and
# the network plumbing. This file is only what makes the game Apolaki's.
#
# A PRIVATE DUEL
#   This is the one arena where the mortals are NOT in the same room. Each player
#   duels their OWN Apolaki on their OWN screen (Apolaki.tscn, driven by
#   apolaki_duelist.gd). His position is never sent anywhere - what travels
#   between mortals is FAVOR, the favors they hold and the effects those favors
#   play out (separate_players).
#
# THE DUEL - three states each, and every outcome falls out of them
#   Apolaki is IDLE (he stalks you), ATTACKING, or DEFENDING - and he walks
#   through all three, so neither his swing nor his guard freezes him in place.
#   The mortal is IDLE, ATTACKing, or DEFENDING. That is the whole game.
#   ATTACK (LEFT MOUSE) - the mortal plays its "hit-arnis" clip; the strike lands
#   on frames strike_hit_open_frame..strike_hit_close_frame of it, once per swing:
#   hitting him while he is IDLE or ATTACKING pays strike_favor, hitting his
#   DEFEND costs strike_defend_penalty. Nothing else - all three states covered.
#   DEFEND (RIGHT MOUSE) - the mortal plays its "defend-arnis" clip.
#   HIS SWING (ApolakiDuelist.attack_landed) only reaches a mortal standing
#   inside his area, and only while its frames are live (frames 4..7 of his
#   clip - the window stays open across all of them, so a swing is only spent
#   once it truly connects). A mortal who is IDLE or ATTACKing then loses
#   hit_penalty and is shoved back (knock_mortal), with a sun patch blotting
#   their own screen for hit_patch_time seconds); one who is DEFENDING gains
#   block_favor instead.
#   Both buttons run on their own cooldown, drawn as the two bars on the duel HUD.
#
# THE WEIGHT OF A HIT - there is no shared hitbox to react to (both blows land
# in code), so the impact is BUILT here, and both directions get it:
#   YOUR strike lands    -> he is shoved away from you and flares up
#                           (ApolakiDuelist.hit_from), the field jumps, the
#                           screen flashes gold.
#   you strike his GUARD -> a clash: he braces back softer, a short jump, a
#                           white flicker.
#   HIS swing lands       -> the mortal is shoved (knock_mortal, which also
#                           lights its glow - ArenaMortal.hit), the field jumps
#                           hardest, the screen flashes red, the sun patch drops.
#   you BLOCK his swing   -> a short jump and a white flicker, no shove.
#   The SHAKE and the WASH are the shared ones in the base (scripts/gods/common/
#   arena.gd): the field only ever moves (the HUD and its labels stay readable),
#   the wash is the rect Arena.tscn authors, and both obey the two comfort
#   options in Settings - screen shake off = no shake at all, reduce flashing =
#   a soft, steady tint instead of a bright one.
#
# SUN PATCHES
#   The Apolaki favors blot part of a mortal's own screen. The host owns the
#   authoritative patch list and mirrors it with every arena tick, so each player
#   only ever sees the patches that fell on themselves.
#
# SUNBURSTS
#   Every 8-10 seconds a sunburst falls ON or around the mortal: the spawned
#   AnimatedSprite2D plays its one-shot clip (sunbursts.tscn) and frames 9..11
#   are live - a mortal standing in its area on one of those frames loses
#   sunburst_penalty FAVOR and is shoved away from its center (knock_mortal).
#   At 30 seconds left and again at 10, BLITZ: five fall at once instead of one.
@export_category("Sunbursts")
@export var sunburst_min_time := 8.0       # seconds between falls, rolled fresh each time
@export var sunburst_max_time := 10.0
@export var sunburst_penalty := 100        # FAVOR lost standing in a live burst
@export var sunburst_open_frame := 9       # the burst is live from this frame...
@export var sunburst_close_frame := 11     # ...through this one
@export var sunburst_hit_radius := 60.0    # how close the mortal must stand to be caught
@export var sunburst_spawn_radius := 40.0  # how far from the mortal one may land (kept inside hit_radius so bursts are a real threat)
@export var sunburst_blitz_count := 5      # bursts that fall at once during blitz
@export var blitz_marks := PackedFloat32Array([30.0, 25.0, 20.0, 15.0, 10.0, 8.0, 6.0, 4.0, 2.0])  # seconds left that trigger blitz waves
#
# The arena owns no art: ApolakiArena.tscn holds the sky, the board, the border
# and the duelist (the patch quads are the shared layer in Arena.tscn). This
# script only runs the rules.

@export_category("Arnis")
# The whole duel economy, halved from its first tuning: the swing pays 100, his
# guard punishes 50, a block earns 50 and taking his swing costs 40.
@export var strike_favor := 100          # hitting him while he IDLES or ATTACKS
@export var strike_defend_penalty := 50  # hitting him while he DEFENDS
@export var block_favor := 50            # a DEFENDING mortal beats his swing
@export var hit_penalty := 40            # an idle / attacking mortal takes his swing
@export var strike_cooldown := 1.0       # seconds between two strikes
@export var strike_hit_open_frame := 3   # the mortal's swing lands from this frame
@export var strike_hit_close_frame := 5  # ...through this one (hit-arnis)
@export var strike_reach_bonus := 26.0   # a strike lands this past his reach
@export var defend_cooldown := 1.0      # seconds before another guard
@export var hit_patch_count := 1         # blots his landed swing leaves on screen
@export var hit_patch_time := 3.0        # seconds each blot stays

@export_category("Impact")
# Every blow in the duel shakes the field and washes the screen - his swing on
# you, your swing on him, and a clash on either guard (all four are wired up
# below). The shake and the wash themselves live in the base arena
# (scripts/gods/common/arena.gd); only the timings are this duel's own.
@export var hit_shake_time := 0.3      # HIS swing lands on you (the hardest)
@export var strike_shake_time := 0.22  # YOUR swing lands on him
@export var block_shake_time := 0.12   # a clash on a guard, either way
# How hard your own blows shove HIM (a clean hit, and the softer brace when you
# strike his guard) - the mortal's own shove is the shared knock_stun/knock_force.
@export var strike_knock_force := 560.0
@export var block_knock_force := 220.0

@onready var duelist: ApolakiDuelist = get_node_or_null("ArenaField/Apolaki")
@onready var state_label: Label = get_node_or_null(BAND_STATE + "State")
@onready var strike_bar: PanelContainer = get_node_or_null(BAND_STATE + "Bars/StrikeBar")
@onready var defend_bar: PanelContainer = get_node_or_null(BAND_STATE + "Bars/DefendBar")

# The mortal's own clips (authored in Mortal.tscn). The swing lands on one of its
# frames and both clips hand the mortal back to its idle once they run out.
const STRIKE_ANIM := &"hit-arnis"
const DEFEND_ANIM := &"defend-arnis"
# The hazard that falls around the mortal (scenes/gods/apolaki/sunbursts.tscn):
# a one-shot AnimatedSprite2D whose frames 9..11 are live.
const SUNBURST_SCENE := preload("res://scenes/gods/apolaki/sunbursts.tscn")

@onready var bursts_root: Node2D = get_node_or_null("ArenaField/Sunbursts")

var _strike_cd := 0.0
var _defend_cd := 0.0
var _swinging := false      # a strike clip is running
var _swing_resolved := false # this swing has already landed its one hit
var _guarding := false      # a guard clip is running
var _rng := RandomNumberGenerator.new()
var _burst_timer := 0.0        # seconds until the next sunburst falls
var _bursts: Array = []        # the falling hazards: {node, hit}
var _blitz_fired: Array = []   # blitz marks already spent this round


func _ready() -> void:
	super._ready()
	if duelist != null:
		duelist.attack_landed.connect(_on_duelist_attack_landed)


# --- ARENA HOOKS (see scripts/gods/common/arena.gd) --------------------------

# The mortals play this one alone: no rival is drawn and no position travels.
func separate_players() -> bool:
	return true


func shares_mortal_positions() -> bool:
	return false


# The Guidance reads "another mortal is nearby" - there is no other mortal on
# this field, so the favor simply never lights up here (it says as much itself).
func nearby_movement_favors_enabled() -> bool:
	return false


# The follow camera's edge arrow: Apolaki himself, who comes for the mortal.
func edge_targets() -> Array:
	return [duelist] if duelist != null else []


func collect_units() -> void:
	# One Apolaki per screen - the same authored node on every peer. He is told
	# where the mortal is every frame (arena_rules_tick); nothing about him is
	# ever put on the wire.
	if duelist == null:
		return
	duelist.color = god.color
	duelist.target = player.global_position


func arena_round_reset() -> void:
	_strike_cd = 0.0
	_defend_cd = 0.0
	_swinging = false
	_swing_resolved = false
	_guarding = false
	_rng.randomize()
	_reset_hazards()
	clear_sun_patches()
	_reset_screen_impact()  # a new round starts with the screen at rest
	player.play_locomotion()
	if duelist != null:
		duelist.restart()


func arena_rules_tick(_delta: float) -> void:
	# The duel is PRIVATE and therefore personal clockwork, not host scoring: it
	# all runs in _process below, on every peer. Kept so the base's hook has an
	# explicit (empty) answer here.
	pass


func _process(delta: float) -> void:
	super._process(delta)
	# Every peer runs its OWN Apolaki, so his states, his walk and both cooldowns
	# all tick here, on every screen - not just the host's. The FAVOR they pay is
	# still the host's to decide (score_favor).
	_strike_cd = maxf(0.0, _strike_cd - delta)
	_defend_cd = maxf(0.0, _defend_cd - delta)
	# The swing and the guard are driven by the mortal's own clips: the frame the
	# sprite is on decides when the strike lands, and a finished clip returns the
	# mortal to its idle. Runs on every screen, like the rest of the duel.
	_tick_actions()
	_tick_sunbursts(delta)
	_refresh_bars()
	if duelist == null:
		return
	duelist.frozen = _phase != Phase.PLAYING
	duelist.target = player.global_position
	_refresh_state_label()


# --- INPUT -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# The duel's two mouse buttons are read in _input() below. The shell draws a
	# full-screen Control over the arena, and a GUI mouse event never reaches
	# _unhandled_input - so this stays only for the base's keyboard shortcuts
	# (E/Q favors, the God's Due menu, ESC, R).
	super._unhandled_input(event)


func _input(event: InputEvent) -> void:
	# A click on one of the favor panels is the HUD's answer, not a swing.
	if super._tap_panel_click(event):
		return
	# ATTACK / DEFEND are mouse buttons, so they have to be caught before the GUI
	# consumes them (Mayari and Tala read their attack the same way). Only during
	# PLAYING: a dialogue, the God's Due menu or the countdown keep the mortal
	# still.
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if _phase != Phase.PLAYING or player.locked or dialogue.is_active() or due_menu.is_open():
		return
	if event.is_action_pressed("attack"):
		_try_strike()
	elif event.is_action_pressed("defend"):
		_try_defend()
	else:
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


# Pressing attack starts the swing. The strike itself does not resolve here: it
# waits for the clip to reach its hit frames (_tick_actions watches the frame),
# so the swing reads as a swing and the hit lands where the art says it should.
func _try_strike() -> void:
	if _strike_cd > 0.0:
		_log("Strike recharging  (%.1fs)" % _strike_cd, god.color)
		return
	if duelist == null:
		return
	_strike_cd = strike_cooldown
	# In the final 30 seconds Apolaki presses harder: strikes recharge faster.
	if _trial_time <= 30.0:
		_strike_cd *= 0.5
	_swinging = true
	_swing_resolved = false
	_guarding = false
	player.play_animation(STRIKE_ANIM)


# The strike's hit window: "the hit opens at frame 3 and closes at frame 5" of
# the hit-arnis clip (strike_hit_open_frame / strike_hit_close_frame).
func _strike_frame_in_window(frame: int) -> bool:
	return frame >= strike_hit_open_frame and frame <= strike_hit_close_frame


# One frame of the two action clips. The swing resolves exactly once, on the
# first frame inside its window; either clip hands the mortal back to its idle
# once it has played out.
func _tick_actions() -> void:
	if _swinging:
		if not _swing_resolved and _strike_frame_in_window(player.animation_frame()):
			_swing_resolved = true
			_resolve_strike()
		if not player.is_animation_playing(STRIKE_ANIM):
			_swinging = false
			player.play_locomotion()
	elif _guarding:
		if not player.is_animation_playing(DEFEND_ANIM):
			_guarding = false
			player.play_locomotion()


# The mortal's own three states. They are exactly what its clips are running:
# a strike clip means ATTACKING, a guard clip means DEFENDING, nothing running
# means IDLE. His swing reads these two.
func _player_is_attacking() -> bool:
	return _swinging


func _player_is_defending() -> bool:
	return _guarding


# The moment the mortal's swing connects. Two outcomes, and they cover all three
# of his states: a hit pays while he is IDLE or ATTACKING and costs on his
# DEFEND. It only reaches him at all inside his reach plus the bonus.
# Both outcomes land with weight: he is shoved either way (a clean hit hard, a
# clash on his guard softly), the field jumps and the screen flashes.
func _resolve_strike() -> void:
	if duelist == null:
		return
	if not duelist.in_reach_with_bonus(player.global_position, strike_reach_bonus):
		_log("Out of reach - close the distance", Color(0.8, 0.8, 0.85))
		return
	if duelist.is_defending():
		score_favor(-strike_defend_penalty, "%s's guard" % god.display_name)
		_log("You struck his guard: -%d FAVOR" % strike_defend_penalty, Color(1, 0.5, 0.45))
		# CLASH: his guard holds, but the blow lands on it - he braces back a
		# step, the field rings once and the screen gives a white flicker.
		duelist.hit_from(player.global_position, block_knock_force)
		hit_effects(duelist.global_position, duelist.global_position - player.global_position)
		_shake_screen(block_shake_time, 0.55)
		_flash_screen(Color(1.0, 1.0, 1.0), 0.16)
	else:
		# A CLEAN HIT: he is shoved away, flares up and reels for a moment, the
		# field jumps and the screen flashes gold - the same weight his own
		# swing carries when it lands on you. In the final 30 seconds the
		# stake rises: landing a blow pays strike_favor plus a +50 bonus.
		var favor_gain: int = strike_favor
		if _trial_time <= 30.0:
			favor_gain += 50
		score_favor(favor_gain, god.display_name)
		_log("Strike landed: +%d FAVOR" % favor_gain, Color(0.7, 1, 0.8))
		duelist.hit_from(player.global_position, strike_knock_force)
		hit_effects(duelist.global_position, duelist.global_position - player.global_position)
		_shake_screen(strike_shake_time)
		_flash_screen(Color(1.0, 0.95, 0.78), 0.28)


# Pressing defend plays the guard clip. That clip RUNNING is the mortal's
# defending state, and it is what turns his swing into FAVOR.
func _try_defend() -> void:
	if _defend_cd > 0.0:
		return
	_defend_cd = defend_cooldown
	_guarding = true
	_swinging = false
	player.play_animation(DEFEND_ANIM)


# HIS SWING CONNECTED inside his area. The duelist already checked the distance
# and the frame window, so this only reads what the mortal was doing when it
# arrived: DEFENDING gains, and being IDLE or mid-swing both pay - and BOTH pay
# in full: the FAVOR is taken, the mortal is shoved away from his stick
# (knock_mortal - the same shove Mayari's clones deal), the blot drops on the
# screen and the mercy seconds start, so the next swing cannot charge the same
# hit twice.
func _on_duelist_attack_landed() -> void:
	if _phase != Phase.PLAYING or player.locked:
		return
	if _player_is_defending():
		score_favor(block_favor, "Blocked %s's swing" % god.display_name)
		_log("Blocked! +%d FAVOR" % block_favor, Color(0.7, 1, 0.8))
		# A BLOCK still has to feel like two sticks meeting: the field rings once
		# and the screen gives a white flicker - but nothing is shoved.
		_shake_screen(block_shake_time, 0.55)
		_flash_screen(Color(1.0, 1.0, 1.0), 0.16)
		return
	if is_mortal_invulnerable(_my_id):
		return
	score_favor(-hit_penalty, "%s's swing" % god.display_name)
	set_mortal_invuln(_my_id, invuln_time)
	if duelist != null:
		knock_mortal(_my_id, duelist.global_position)
	_drop_hit_patch()
	# HIS swing landed, in full: the mortal is shoved and its glow lights with
	# the shove (knock_mortal -> ArenaMortal.hit), the field jumps hardest of
	# all and the screen flashes red under the blot that drops on top.
	_shake_screen(hit_shake_time, 1.25)
	_flash_screen(Color(1.0, 0.32, 0.28), 0.4)
	_log("His swing landed: -%d FAVOR" % hit_penalty, Color(1, 0.5, 0.45))


# --- SUNBURSTS ------------------------------------------------------------
# The sky falls ON or around the mortal: every 8-10 seconds one burst lands
# near them, and at the blitz marks (30s, 10s left) five land at once. The clip
# is a warning AND the weapon: frames 9..11 are live, and a mortal standing in
# the area on one of them loses sunburst_penalty FAVOR and is shoved away from
# its center (knock_mortal - the same shove his swing deals). One hit per burst:
# a burst that already caught the mortal spends itself. The duel is private, so
# every peer runs its own sky off its own clock - nothing travels.
func _tick_sunbursts(delta: float) -> void:
	if _phase != Phase.PLAYING:
		return
	_tick_blitz_marks()
	_burst_timer -= delta
	if _burst_timer <= 0.0:
		_spawn_burst()
		_burst_timer = _roll_burst_time()
	_check_bursts()


func _roll_burst_time() -> float:
	return _rng.randf_range(sunburst_min_time, sunburst_max_time)


# The blitz marks: at marks >= 10s, five bursts fall at once around the mortal
# (sunburst_blitz_count). In the last 10 seconds, each mark drops a single
# burst every 2 seconds. A mark is spent after firing once - crossing the same
# mark twice must never fire twice.
func _tick_blitz_marks() -> void:
	for index in range(blitz_marks.size()):
		if index < _blitz_fired.size() and bool(_blitz_fired[index]):
			continue
		if _trial_time <= float(blitz_marks[index]):
			while _blitz_fired.size() <= index:
				_blitz_fired.append(false)
			_blitz_fired[index] = true
			var mark: float = float(blitz_marks[index])
			var count: int = sunburst_blitz_count if mark >= 10.0 else 1
			for _i in range(count):
				_spawn_burst()
			_log("BLITZ - the sky falls!", Color(1.0, 0.6, 0.2))


func _spawn_blitz() -> void:
	for _i in range(sunburst_blitz_count):
		_spawn_burst()
	_log("BLITZ - the sky falls!", Color(1.0, 0.6, 0.2))


# One burst, ON or around the mortal: at the mortal's feet or up to
# sunburst_spawn_radius away, clamped inside the walking field. The clip plays
# once and frees itself when it runs out; _check_bursts watches its frames.
func _spawn_burst() -> void:
	if player == null:
		return
	var offset := Vector2.RIGHT.rotated(_rng.randf_range(0.0, TAU)) * _rng.randf_range(0.0, sunburst_spawn_radius)
	var spot := player.global_position + offset
	if _field.size != Vector2.ZERO:
		spot.x = clampf(spot.x, _field.position.x, _field.end.x)
		spot.y = clampf(spot.y, _field.position.y, _field.end.y)
	var burst: Node2D = SUNBURST_SCENE.instantiate()
	if bursts_root != null:
		bursts_root.add_child(burst)
	else:
		field_root.add_child(burst)
	burst.global_position = spot
	_bursts.append({"node": burst, "hit": false})


# Every falling burst: read the frame its clip is on, and while it is live
# (frames 9..11) catch a mortal standing in its area. A spent burst frees its
# node and leaves the list; one whose clip ran out without catching anyone
# simply burns itself out.
func _check_bursts() -> void:
	for index in range(_bursts.size() - 1, -1, -1):
		var burst: Dictionary = _bursts[index]
		var node: Node2D = burst.get("node")
		if not is_instance_valid(node):
			_bursts.remove_at(index)
			continue
		var sprite: AnimatedSprite2D = node.get_node_or_null("AnimatedSprite2D")
		if sprite == null:
			_bursts.remove_at(index)
			continue
		if not bool(burst.get("started", false)):
			sprite.play()
			burst["started"] = true
			_bursts[index] = burst
		if not bool(burst.get("hit", false)) and _burst_frame_live(sprite.frame):
			if player != null and player.global_position.distance_to(node.global_position) <= sunburst_hit_radius:
				burst["hit"] = true
				_bursts[index] = burst
				_resolve_burst(node.global_position)
		var total_frames: int = sprite.sprite_frames.get_frame_count(sprite.animation)
		if total_frames > 0 and (not sprite.is_playing() or sprite.frame >= total_frames - 1):
			node.queue_free()
			_bursts.remove_at(index)


func _burst_frame_live(frame: int) -> bool:
	return frame >= sunburst_open_frame and frame <= sunburst_close_frame


# A live burst caught the mortal: sunburst_penalty FAVOR taken, the mortal
# shoved away from the burst's center (knock_mortal only - no freeze, no mercy).
# The field jumps hardest and the screen flashes red.
func _resolve_burst(burst_position: Vector2) -> void:
	score_favor(-sunburst_penalty, "a sunburst")
	knock_mortal(_my_id, burst_position)
	_shake_screen(hit_shake_time, 1.25)
	_flash_screen(Color(1.0, 0.32, 0.28), 0.4)
	_log("A sunburst caught you: -%d FAVOR" % sunburst_penalty, Color(1, 0.5, 0.45))


# A new round starts with a clear sky: no falling burst carries over.
func _clear_bursts() -> void:
	for burst in _bursts:
		var node: Node = burst.get("node")
		if is_instance_valid(node):
			node.queue_free()
	_bursts.clear()
	if bursts_root != null:
		for child in bursts_root.get_children():
			child.queue_free()


# Reset all hazard state at the start of a new round: no falling burst carries
# over, the spawn timer is re-rolled and the blitz marks are unmarked.
func _reset_hazards() -> void:
	_clear_bursts()
	_blitz_fired.clear()
	for _i in range(blitz_marks.size()):
		_blitz_fired.append(false)
	_burst_timer = _roll_burst_time()

# --- THE SUN PATCHES HIS SWING LEAVES ------------------------------------------
# His landed swing blots part of THIS screen. The blots themselves are the
# shared ones (Arena.show_sun_patch), so a blot he drops and a blot another
# player's favor drops behave the same way: each claims a rect at random out of
# the free ones and takes itself back down on its own clock. Nothing is
# published - the duel is private, so nobody else's screen changes.

func _drop_hit_patch() -> void:
	for _i in range(hit_patch_count):
		show_sun_patch(hit_patch_time)


func _refresh_state_label() -> void:
	if state_label == null or duelist == null:
		return
	var text := "APOLAKI CHASES YOU"
	if _player_is_attacking():
		text = "YOU STRIKE"
	elif _player_is_defending():
		text = "YOU GUARD"
	elif duelist.is_reeling():
		text = "APOLAKI REELS - PRESS IT"
	elif duelist.is_attacking():
		text = "APOLAKI SWINGS - GUARD!"
	elif duelist.is_defending():
		text = "APOLAKI GUARDS - DO NOT STRIKE"
	state_label.text = text


# The two duel bars, side by side in the band under the field (BODY text, so they
# read at a glance): the swing and the guard, each refilling over its own
# cooldown so the mortal can see when the next strike or block is ready.
func _refresh_bars() -> void:
	_fill_bar(strike_bar, "%s  STRIKE" % UITokens.key_text(&"attack").to_upper(), _strike_cd, strike_cooldown, Color(1.0, 0.85, 0.35))
	_fill_bar(defend_bar, "%s  DEFEND" % UITokens.key_text(&"defend").to_upper(), _defend_cd, defend_cooldown, Color(0.55, 0.8, 1.0))


func _fill_bar(bar: PanelContainer, caption: String, cooldown: float, total: float, tint: Color) -> void:
	if bar == null:
		return
	var fill: ColorRect = bar.get_node_or_null("Body/Fill")
	var label: Label = bar.get_node_or_null("Body/Text")
	var ratio := 1.0 if total <= 0.0 else clampf(1.0 - cooldown / total, 0.0, 1.0)
	if fill != null:
		fill.anchor_right = ratio
		fill.color = Color(tint.r, tint.g, tint.b, 0.78)
	if label != null:
		if cooldown <= 0.0:
			label.text = "%s  READY" % caption
			label.add_theme_color_override("font_color", UITokens.IVORY)
		else:
			label.text = "%s  %.1fs" % [caption, cooldown]
			label.add_theme_color_override("font_color", UITokens.MUTED)
