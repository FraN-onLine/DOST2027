extends SceneTree

# Focused regression check for the personal Arnis duel and Apolaki favor rules.
# Run: godot --headless --path <project> -s res://tools/apolaki_check.gd

var _arena: ApolakiArena
var _problems := 0
var _landed := 0


# Counts ApolakiDuelist.attack_landed without going through the arena's scoring.
func _on_attack_landed() -> void:
	_landed += 1


func _initialize() -> void:
	_run()


func _run() -> void:
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	get_root().add_child(view)
	_arena = load("res://scenes/gods/apolaki/ApolakiArena.tscn").instantiate()
	view.add_child(_arena)
	await process_frame
	await process_frame
	if _arena.duelist == null:
		printerr("FAIL: the arena did not resolve its authored Apolaki")
		quit(1)
		return

	var guard := 0
	while _arena.dialogue.is_active() and guard < 40:
		_arena.dialogue.advance()
		guard += 1
	_arena._phase = Arena.Phase.PLAYING
	_arena.player.set_lock(false)
	_arena.rules.local().favor = 500
	_arena.rules.ensure_mortal(2, "RIVAL").favor = 500
	var rival_visual := Node2D.new()
	_arena.ghosts_root.add_child(rival_visual)
	_arena._ghosts[2] = rival_visual
	_arena._sync_ghosts()
	_check(_arena._ghosts.is_empty(), "Apolaki does not render other players")
	# --- his ground shadow, like the mortals' ------------------------------------------
	var duel_shadow := _arena.duelist.get_node_or_null("Shadow") as Sprite2D
	var duel_icon := _arena.duelist.icon
	var duel_frame := duel_icon.sprite_frames.get_frame_texture(duel_icon.animation, duel_icon.frame)
	var duel_art := duel_frame.get_image().get_used_rect()
	var duel_feet := duel_icon.position.y + (duel_art.end.y - duel_frame.get_height() * 0.5) * duel_icon.scale.y
	_check(duel_shadow != null and duel_shadow.get_index() < duel_icon.get_index() and duel_shadow.texture != null, "Apolaki has a Shadow drawn behind his Icon")
	if duel_shadow != null:
		_check(absf(duel_shadow.position.y - duel_feet) <= 3.0, "...centred under his feet (%.0f vs %.0f)" % [duel_shadow.position.y, duel_feet])
		var duel_width := duel_shadow.texture.get_width() * duel_shadow.scale.x
		_check(duel_width >= duel_art.size.x * duel_icon.scale.x * 0.7 and duel_width <= duel_art.size.x * duel_icon.scale.x * 1.1, "...sized to his body (%.0f px under %.0f px)" % [duel_width, duel_art.size.x * duel_icon.scale.x])
		var duel_offset := duel_shadow.global_position - _arena.duelist.global_position
		_arena.duelist.global_position += Vector2(123, -45)
		_check((duel_shadow.global_position - _arena.duelist.global_position).is_equal_approx(duel_offset), "...and it follows him wherever he goes")
	_arena.duelist.global_position = _arena.player.global_position

	# --- THE MORAL'S STRIKE: frames 3..5 of hit-arnis --------------------------
	_check(_arena._strike_frame_in_window(3), "the mortal's strike is live on frame 3 (opens)")
	_check(_arena._strike_frame_in_window(5), "the mortal's strike is live on frame 5 (closes)")
	_check(not _arena._strike_frame_in_window(2), "the mortal's strike is not live before frame 3")
	_check(not _arena._strike_frame_in_window(6), "the mortal's strike is not live after frame 5")

	# The mouse path matters: the shell draws a full-screen Control over the
	# arena, so ATTACK is read in _input - a left click that never reaches
	# _unhandled_input still has to start the swing.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_arena._strike_cd = 0.0
	_arena._swinging = false
	_arena._input(click)
	_check(_arena._swinging, "a left click starts the swing (the _input path)")
	_arena._swinging = false
	_arena._strike_cd = 0.0

	# --- THE BALANCE, SPELLED OUT ----------------------------------------------
	# The whole duel economy is halved from its first tuning (100 / 50 / 50 / 40).
	_check(_arena.strike_favor == 100, "hitting him while he IDLES or ATTACKS is worth 100 FAVOR")
	_check(_arena.strike_defend_penalty == 50, "hitting his DEFEND costs 50 FAVOR")
	_check(_arena.block_favor == 50, "DEFENDING his swing is worth 50 FAVOR")
	_check(_arena.hit_penalty == 40, "taking his swing while idle or mid-swing costs 40 FAVOR")

	# --- MORTAL -> APOLAKI: all three of his states -----------------------------
	_arena.duelist.global_position = _arena.player.global_position

	_arena.duelist._enter(ApolakiDuelist.State.IDLE)
	_arena.rules.local().favor = 500
	_arena._try_strike()
	_arena._resolve_strike()
	_check(_arena.rules.local().favor == 500 + _arena.strike_favor, "striking him while he IDLES pays 100")
	_arena._strike_cd = 0.0
	_arena._swinging = false

	_arena.duelist._enter(ApolakiDuelist.State.ATTACK)
	_arena.rules.local().favor = 500
	_arena._try_strike()
	_arena._resolve_strike()
	_check(_arena.rules.local().favor == 500 + _arena.strike_favor, "striking him while he ATTACKS pays the same 100")
	_arena._strike_cd = 0.0
	_arena._swinging = false

	_arena.duelist._enter(ApolakiDuelist.State.DEFEND)
	_arena.rules.local().favor = 500
	_arena._try_strike()
	_arena._resolve_strike()
	_check(_arena.rules.local().favor == 500 - _arena.strike_defend_penalty, "striking his DEFEND costs 50")
	_arena._strike_cd = 0.0
	_arena._swinging = false

	# --- WHAT A BLOW FEELS LIKE: shove, flare, shake, flash --------------------
	# Neither direction has a shared hitbox to react to (both blows land in
	# code), so the weight is built in the arena and the duelist: he is shoved
	# away and lit up, the field jumps, the screen flashes. The shake only runs
	# while the player's Screen shake option is on; the flash is a clock of its
	# own that paints the rect on the duel HUD and takes it back down.
	_arena._shake_left = 0.0
	_arena._shake_span = 0.0
	_arena._shake_power = 1.0
	_arena._flash_left = 0.0
	_arena.duelist._knock_velocity = Vector2.ZERO
	_arena.duelist._hit_flash = 0.0
	_arena.duelist._stagger = 0.0
	_arena.duelist._enter(ApolakiDuelist.State.IDLE)
	_arena.duelist.global_position = _arena.player.global_position + Vector2(80.0, 0.0)
	_arena.rules.local().favor = 500
	_arena._try_strike()
	_arena._resolve_strike()
	_check(is_equal_approx(_arena.duelist._knock_velocity.length(), _arena.strike_knock_force),
		"a landed strike shoves him away at strike_knock_force")
	_check(_arena.duelist._knock_velocity.x > 0.0, "the shove points away from the mortal")
	_check(_arena.duelist._hit_flash > 0.0, "a landed strike lights him up")
	_check(_arena.duelist.is_reeling(), "he reels for a moment after a clean hit")
	_check((_arena._shake_left > 0.0) == _arena.screen_shake_allowed(),
		"a landed strike shakes the field (whenever shaking is on)")
	_check(_arena.hit_flash != null and _arena.hit_flash.visible,
		"the screen flashes when your strike lands")
	var shove_from := _arena.duelist.global_position
	_arena.duelist._tick_knockback(0.1)
	_check(_arena.duelist.global_position != shove_from, "the shove really moves him")
	_arena.duelist._tick_knockback(5.0)
	_check(_arena.duelist._knock_velocity == Vector2.ZERO, "the shove runs out of force")
	# The shake and the flash each run down over their own clock and settle.
	_arena._tick_shake(10.0)
	_check(_arena.field_root.position == Vector2.ZERO, "the field settles back to rest")
	_arena._tick_flash(10.0)
	_check(_arena.hit_flash == null or not _arena.hit_flash.visible, "the screen flash fades out")
	# A clash on his guard: the same feedback, softer - he only braces back.
	_arena._shake_left = 0.0
	_arena._shake_span = 0.0
	_arena._flash_left = 0.0
	_arena.duelist._knock_velocity = Vector2.ZERO
	_arena.duelist._enter(ApolakiDuelist.State.DEFEND)
	_arena.duelist.global_position = _arena.player.global_position + Vector2(80.0, 0.0)
	_arena.rules.local().favor = 500
	_arena._try_strike()
	_arena._resolve_strike()
	_check(is_equal_approx(_arena.duelist._knock_velocity.length(), _arena.block_knock_force),
		"striking his guard only braces him back")
	_check((_arena._shake_left > 0.0) == _arena.screen_shake_allowed(),
		"a clash on his guard rings the field too (when shaking is on)")
	_check(_arena.hit_flash != null and _arena.hit_flash.visible,
		"a clash flickers the screen white")
	# A new round starts with the screen at rest - no shake mid-flight and no
	# flash left over from the last blow.
	_arena.arena_round_reset()
	_check(_arena._shake_left == 0.0 and _arena.field_root.position == Vector2.ZERO,
		"a new round starts with the field at rest")
	_check(_arena.hit_flash == null or not _arena.hit_flash.visible,
		"and with no flash left over from the last blow")

	# --- HIS SWING -> THE MORTAL: all three of the mortal's states --------------
	# Idle and mid-swing both pay; only DEFENDING turns it into FAVOR.
	_arena._guarding = false
	_arena._swinging = false
	_arena._invuln.clear()
	_arena.player._knockback = Vector2.ZERO
	_arena.rules.local().favor = 500
	_arena._on_duelist_attack_landed()
	_check(_arena.rules.local().favor == 500 - _arena.hit_penalty, "his swing costs 40 while the mortal is IDLE")
	_check(_arena.player._knockback != Vector2.ZERO, "his swing shoves the mortal back")
	_check(_arena._invuln.has(_arena._my_id), "the mercy seconds start when his swing lands")
	_check(_arena.active_sun_patches() == _arena.hit_patch_count, "a landed swing blots one sun patch on your screen")
	_check(is_equal_approx(_arena.sun_patch_time_left(0), _arena.hit_patch_time), "the blot starts at hit_patch_time (3s)")
	# It has to burn down over REAL frames, not merely vanish on one big tick:
	# the game loop calls this sixty times a second, so a timer that is never
	# stored back would sit at 3.0 forever.
	_arena._tick_sun_patch_slots(_arena.hit_patch_time * 0.5)
	_check(_arena.active_sun_patches() == 1, "the blot is still up half way through its 3 seconds")
	_check(_arena.sun_patch_time_left(0) < _arena.hit_patch_time, "the blot timer burns down every frame")
	var elapsed := _arena.hit_patch_time * 0.5   # the half-way tick above counts too
	while elapsed < _arena.hit_patch_time + 0.5 and _arena.active_sun_patches() > 0:
		_arena._tick_sun_patch_slots(1.0 / 60.0)
		elapsed += 1.0 / 60.0
	_check(_arena.active_sun_patches() == 0, "the blot clears after 3 seconds of real frames")
	_check(elapsed >= _arena.hit_patch_time, "and it lasted the whole 3 seconds")

	_arena._invuln.clear()
	_arena._swinging = true
	_arena.rules.local().favor = 500
	_arena._on_duelist_attack_landed()
	_check(_arena.rules.local().favor == 500 - _arena.hit_penalty, "being mid-swing does not save you")
	_arena._swinging = false
	_arena.clear_sun_patches()

	_arena._invuln.clear()
	_arena._guarding = true
	_arena.player._knockback = Vector2.ZERO
	_arena.rules.local().favor = 500
	_arena._on_duelist_attack_landed()
	_check(_arena.rules.local().favor == 500 + _arena.block_favor, "DEFENDING his swing gains 50")
	_check(_arena.player._knockback == Vector2.ZERO, "a defended swing does not shove the mortal")
	_check(_arena.active_sun_patches() == 0, "a defended swing leaves no sun patch")
	_arena._guarding = false
	_arena._invuln.clear()

	# --- HIS SWING'S WEIGHT ON YOUR SCREEN --------------------------------------
	# The mortal is shoved and its glow lights with the shove (knock_mortal ->
	# ArenaMortal.hit); the field and the screen answer the blow too. A blocked
	# swing still rings the field, but nothing is shoved.
	_arena._shake_left = 0.0
	_arena._shake_span = 0.0
	_arena._flash_left = 0.0
	_arena._guarding = false
	_arena._swinging = false
	_arena._invuln.clear()
	_arena.player._knockback = Vector2.ZERO
	_arena._on_duelist_attack_landed()
	_check(_arena.player._knockback != Vector2.ZERO, "his swing shoves the mortal (again)")
	_check(_arena.player._flash > 0.0, "his swing lights the mortal's glow")
	_check((_arena._shake_left > 0.0) == _arena.screen_shake_allowed(),
		"his swing shakes your screen (whenever shaking is on)")
	_check(_arena.hit_flash != null and _arena.hit_flash.visible,
		"his swing reddens your screen")
	_arena._tick_shake(10.0)
	_check(_arena.field_root.position == Vector2.ZERO, "the field settles after his swing")
	_arena.clear_sun_patches()
	_arena._shake_left = 0.0
	_arena._flash_left = 0.0
	_arena._invuln.clear()
	_arena._guarding = true
	_arena.player._knockback = Vector2.ZERO
	_arena._on_duelist_attack_landed()
	_check(_arena.player._knockback == Vector2.ZERO, "a blocked swing still does not shove")
	_check((_arena._shake_left > 0.0) == _arena.screen_shake_allowed(),
		"a blocked swing still rings the field (when shaking is on)")
	_check(_arena.hit_flash != null and _arena.hit_flash.visible,
		"a blocked swing flickers the screen white")
	_arena._tick_flash(10.0)
	_arena._guarding = false
	_arena._invuln.clear()
	_arena.clear_sun_patches()

	# --- THE BLOTS THEMSELVES ----------------------------------------------------
	# Every blot - the one his swing drops and the ones another player's favors
	# drop - claims a rect at random out of the free ones, and each one comes down
	# on its own clock.
	_arena.clear_sun_patches()
	var rect_count := _arena._sun_patch_rects.size()
	for _index in range(3):
		_arena.show_sun_patch(5.0)
	_check(_arena.active_sun_patches() == 3, "three blots can be on screen at once")
	var used := {}
	for slot in range(_arena.active_sun_patches()):
		used[_arena.sun_patch_rect_at(slot)] = true
	_check(used.size() == 3, "each blot claimed a rect of its own (none overwritten)")
	# Two blots with two different lives: the short one must take itself down while
	# the long one is still up. A last-in-first-out fill would have killed the
	# wrong one - the newest - and left the stale blot sitting there.
	_arena.clear_sun_patches()
	_arena.show_sun_patch(0.5)
	_arena.show_sun_patch(3.0)
	_arena._tick_sun_patch_slots(0.6)
	_check(_arena.active_sun_patches() == 1, "the short blot came down while the long one stayed up")
	_arena._tick_sun_patch_slots(2.5)
	_check(_arena.active_sun_patches() == 0, "the long blot came down on its own time")
	# Every rect can hold a blot at once, and one more is refused rather than
	# landing on top of a blot that is already showing.
	_arena.clear_sun_patches()
	for _index in range(rect_count):
		_arena.show_sun_patch(5.0)
	_check(_arena.active_sun_patches() == rect_count, "every rect holds its own blot")
	_check(not _arena.show_sun_patch(5.0), "a blot is refused while every rect is busy")
	_arena.clear_sun_patches()
	# A blot aimed at us by another player's favor goes through the same allocator.
	_arena._add_sun_patches(_arena._my_id, 1, 1.5)
	_check(_arena.active_sun_patches() == 1, "another player's favor blot is drawn the same way")
	_arena.clear_sun_patches()

	# --- HIS AREA AND HIS WINDOW -----------------------------------------------
	# Count the signal only: hold the arena in RESULTS so its own scoring
	# handler no-ops and this measures the duelist on its own.
	_landed = 0
	_arena.duelist.attack_landed.connect(_on_attack_landed)
	_arena._phase = Arena.Phase.RESULTS
	_arena.duelist.target = _arena.player.global_position
	_arena.duelist.global_position = _arena.player.global_position + Vector2(600.0, 0.0)
	_arena.duelist._enter(ApolakiDuelist.State.ATTACK)
	_arena.duelist.icon.frame = 5
	_arena.duelist._tick_attack_window()
	_check(_landed == 0, "his swing misses while the mortal stands outside his area")
	# The window itself: 4 is too early, 5 and 8 are live, 9 is too late.
	_arena.duelist.global_position = _arena.player.global_position
	_arena.duelist._enter(ApolakiDuelist.State.ATTACK)
	_arena.duelist.icon.frame = 4
	_arena.duelist._tick_attack_window()
	_check(_landed == 0, "his swing is not live before frame 5")
	_arena.duelist.icon.frame = 5
	_arena.duelist._tick_attack_window()
	_arena.duelist._tick_attack_window()
	_check(_landed == 1, "his swing connects once per swing inside his area")
	_arena.duelist._enter(ApolakiDuelist.State.ATTACK)
	_arena.duelist.icon.frame = 9
	_arena.duelist._tick_attack_window()
	_check(_landed == 1, "his swing is closed after frame 8")
	_check(_arena.duelist.attack_hit_open_frame == 5 and _arena.duelist.attack_hit_close_frame == 8,
		"his swing is live on frames 5..8")
	# The window stays open across all of its frames: a mortal that was out of
	# reach on one live frame and steps in on a later one still gets hit - this
	# is the rule that stops his stick from passing through a mortal untouched.
	_arena.duelist.global_position = _arena.player.global_position + Vector2(600.0, 0.0)
	_arena.duelist._enter(ApolakiDuelist.State.ATTACK)
	_arena.duelist.icon.frame = 5
	_arena.duelist._tick_attack_window()
	_check(_landed == 1, "a live frame outside his area spends nothing")
	_arena.duelist.global_position = _arena.player.global_position
	_arena.duelist.icon.frame = 6
	_arena.duelist._tick_attack_window()
	_arena.duelist.icon.frame = 8
	_arena.duelist._tick_attack_window()
	_check(_landed == 2, "stepping into his area on a later live frame lands the swing")

	# --- HE TURNS TO FACE WHOMEVER HE IS DUELLING ------------------------------
	# The sheet is drawn facing one way (art_facing); the sprite mirrors whenever
	# the mortal stands on the other side.
	_arena.duelist.global_position = _arena.player.global_position
	_arena.duelist.target = _arena.player.global_position + Vector2(120.0, 0.0)
	_arena.duelist._face_target()
	_check(_arena.duelist.icon.flip_h == (_arena.duelist.art_facing != 1),
		"he mirrors his art when the mortal stands to his right")
	_arena.duelist.target = _arena.player.global_position + Vector2(-120.0, 0.0)
	_arena.duelist._face_target()
	_check(_arena.duelist.icon.flip_h == (_arena.duelist.art_facing != -1),
		"he turns back when the mortal stands to his left")

	# --- HE KEEPS WALKING THROUGH A SWING AND A GUARD --------------------------
	# Neither action plants him any more: the walk runs in every state.
	_arena.duelist.frozen = false
	_arena.duelist.global_position = _arena.player.global_position
	_arena.duelist.target = _arena.player.global_position + Vector2(240.0, 0.0)
	var walk_from := _arena.duelist.global_position
	_arena.duelist._enter(ApolakiDuelist.State.ATTACK)
	_arena.duelist._move(0.5)
	_check(_arena.duelist.global_position.distance_to(walk_from) > 1.0,
		"he keeps closing the distance while he swings")
	walk_from = _arena.duelist.global_position
	_arena.duelist._enter(ApolakiDuelist.State.DEFEND)
	_arena.duelist._move(0.5)
	_check(_arena.duelist.global_position.distance_to(walk_from) > 1.0,
		"he keeps walking while he guards")
	_arena._phase = Arena.Phase.PLAYING

	var rivalry: GodFavor = _arena.god.get_favor(&"siblings_rivalry")
	_check(not _arena.rules.is_favor_eligible(rivalry), "Sibling's Rivalry is locked without a Mayari favor")
	_arena.rules.bestow_favor(Gods.mayari().favors[0])
	_check(_arena.rules.is_favor_eligible(rivalry), "a Mayari favor unlocks Sibling's Rivalry")
	_arena.rules.bestow_favor(rivalry)
	_arena.rules.local().favor = 2000
	_arena.rules.mortal(2).favor = 1000
	_arena._tick_siblings_rivalry()
	_check((_arena._sun_patches.get(2, []) as Array).size() == 4, "Sibling's Rivalry drops patches after a 1000 FAVOR lead")
	_arena._tick_siblings_rivalry()
	_check((_arena._sun_patches.get(2, []) as Array).size() == 4, "Sibling's Rivalry triggers only once per opponent")

	_arena._sun_patches.clear()
	_arena.rules.bestow_favor(_arena.god.get_favor(&"the_sun_god"))
	_arena.lose_favor(1, "test loss", 2)
	_check((_arena._sun_patches.get(2, []) as Array).size() == 1, "The Sun God patches an opponent who loses FAVOR")
	_arena._sun_patches.clear()
	_arena.rules.bestow_favor(_arena.god.get_favor(&"the_ruler"))
	var ruler_patches_before := _patch_total_except(_arena._my_id)
	_arena.lose_favor(1, "owner loss", _arena._my_id)
	_check(_patch_total_except(_arena._my_id) > ruler_patches_before, "The Ruler patches a random opponent on owner loss")

	_arena.rules.bestow_favor(_arena.god.get_favor(&"the_victor"))
	var rival_favor_before: int = _arena.rules.mortal(2).favor
	_arena.rules.bestow_favor(_arena.god.get_favor(&"the_victor"), 3)
	_arena._add_sun_patches(2, 5, 1.5)
	_check(_arena.rules.mortal(2).favor == rival_favor_before - 200, "each Victor owner removes 100 FAVOR at five patches")
	var immune_id := 4
	_arena.rules.ensure_mortal(immune_id, "IMMUNE")
	_arena.rules.bestow_favor(_arena.god.get_favor(&"the_victor"), immune_id)
	var immune_favor_before: int = _arena.rules.mortal(immune_id).favor
	_arena._add_sun_patches(immune_id, 5, 1.5)
	_check(_arena.rules.mortal(immune_id).favor == immune_favor_before, "a mortal with The Victor ignores other Victor owners")
	_arena.rules.bestow_favor(_arena.god.get_favor(&"the_great"))
	var great_before: int = _arena.rules.local().favor
	_arena._tick_the_great(1.0)
	_check(_arena.rules.local().favor == great_before + 1, "The Great gains 1 FAVOR while any patch is active")

	var compromise: GodFavor = _arena.god.get_favor(&"siblings_compromise_sun")
	_check(_arena.rules.is_favor_eligible(compromise, 2), "Sibling's Compromise needs no Mayari favor")
	_arena.rules.bestow_favor(compromise)
	var patches_before := (_arena._sun_patches.get(immune_id, []) as Array).size()
	_arena._apply_skill_effect(compromise, _arena._my_id)
	_check((_arena._sun_patches.get(immune_id, []) as Array).size() == patches_before + 7,
		"Sibling's Compromise drops seven sun patches at once (%d -> %d)" % [patches_before, (_arena._sun_patches.get(immune_id, []) as Array).size()])
	_check(is_equal_approx(float(_arena._loss_boost.get(2, 0.0)), 3.0), "Sibling's Compromise boosts opponent losses for three seconds")
	var boosted_before: int = _arena.rules.mortal(2).favor
	_arena.lose_favor(10, "boosted test", 2)
	_check(_arena.rules.mortal(2).favor == boosted_before - 11, "active Compromise makes a FAVOR loss 10% larger")
	var caster_before: int = _arena.rules.local().favor
	_arena.lose_favor(10, "caster test", _arena._my_id)
	_check(_arena.rules.local().favor == caster_before - 5, "Sibling's Compromise leaves the caster's loss alone")

	var unmoving: GodFavor = _arena.god.get_favor(&"the_unmoving")
	_arena.rules.bestow_favor(unmoving)
	_arena.rules.use_skill(GodFavor.Slot.Q)
	var shielded_before: int = _arena.rules.local().favor
	_arena.lose_favor(50, "shield test", _arena._my_id)
	_check(_arena.rules.local().favor == shielded_before, "The Unmoving prevents FAVOR loss")

	# --- THE TWO FAVOR PANELS ARE TAPPABLE -------------------------------------
	# A click on the Q panel is the same as pressing its key: claimed before the
	# duel's own mouse buttons could read it as an attack. The arena scenes are
	# authored embedded (the shell owns these panels in a real run), so the stats
	# panel is put back on screen here to exercise the arena's own bars.
	_arena.hud.get_node("StatsPanel").visible = true
	await _frames(2)  # let the panel lay its rows out before any rect is trusted
	# The panel's own click answer (the GUI path: bar -> HUD -> arena).
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	_arena.rules.local().cooldowns.clear()
	_arena.hud.bar_q.gui_input.emit(tap)
	_check(_arena.rules.local().cooldown_left(&"the_unmoving") > 0.0,
		"the Q panel's own click answer fires its favor")
	# The preemption path: the duel's mouse buttons run before the GUI, so a
	# click on the panel is claimed there - never read as an attack.
	_arena._swinging = false
	_arena.rules.local().cooldowns.clear()
	var panel_click := InputEventMouseButton.new()
	panel_click.button_index = MOUSE_BUTTON_LEFT
	panel_click.pressed = true
	panel_click.position = _arena.hud.bar_q.get_global_rect().get_center()
	_check(_arena._tap_panel_click(panel_click), "a click on the Q panel is claimed by the panel")
	_check(_arena.rules.local().cooldown_left(&"the_unmoving") > 0.0, "the tap fires that favor")
	_check(not _arena._swinging, "and it is not read as a swing")
	# A click anywhere else is the duel's business.
	var world_click := InputEventMouseButton.new()
	world_click.button_index = MOUSE_BUTTON_LEFT
	world_click.pressed = true
	world_click.position = _arena.player.global_position
	_arena._input(world_click)
	_check(_arena._swinging, "a click in the world still starts the duel's swing")

	_arena._sun_patches[_arena._my_id] = [1.0]
	_arena._refresh_sun_patches()
	var visible_patches := 0
	for patch in _arena._sun_patch_rects:
		if patch.visible:
			visible_patches += 1
	_check(visible_patches == 1, "sun patches render on the affected player's screen")

	print("Apolaki checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _patch_total_except(player_id: int) -> int:
	var total := 0
	for id in _arena._sun_patches.keys():
		if int(id) != player_id:
			total += (_arena._sun_patches[id] as Array).size()
	return total


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1