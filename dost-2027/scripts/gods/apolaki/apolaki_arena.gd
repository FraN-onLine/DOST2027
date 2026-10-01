class_name ApolakiArena
extends Arena

# APOLAKI - arnis. (scripts/gods/apolaki + scenes/gods/apolaki)
#
# EVERYTHING SHARED LIVES IN THE BASE (scripts/gods/common/arena.gd): the clock,
# the countdown, the mortal, the dialogues, the God's Due menu, the popups and
# the network plumbing. This file is only what makes the game Apolaki's:
#
#   * A one-on-one duel. Every player fights their OWN Apolaki on their own
#     screen (the Apolaki node, scripts/gods/apolaki/apolaki_duelist.gd) - he
#     walks, guards and lunges at that player alone. His position never travels;
#     what travels is FAVOR and the favors themselves.
#   * ATTACK (LEFT MOUSE) - strike. Land it while Apolaki is OPEN (his blind
#     spot) for the most FAVOR; a strike while he only watches pays a little;
#     strike into his GUARD and you lose FAVOR.
#   * DEFEND (RIGHT MOUSE) - guard. Block his lunge inside the window and you
#     gain FAVOR; take the hit and you lose FAVOR and are shoved back.
#   * SUN PATCHES - the favors blot part of a mortal's own screen. The host owns
#     the authoritative patch list and mirrors it with every arena tick, so each
#     player only ever sees the patches that fell on themselves.
#
# The arena owns no art: ApolakiArena.tscn holds the sky, the board, its border,
# the duelist and the ten authored patch quads. This script only runs the
# rules - it never draws and never re-lays-out the scene.

@export_category("Arnis")
@export var strike_open_favor := 35       # a clean strike on his blind spot
@export var strike_neutral_favor := 10    # a strike while he only watches
@export var strike_guard_penalty := 25    # striking into his guard
@export var block_favor := 20             # a blocked lunge
@export var hit_penalty := 30             # a lunge that got through
@export var strike_cooldown := 0.45       # seconds between two strikes
@export var strike_reach_bonus := 26.0    # a strike lands this past his reach
@export var defend_window := 0.7          # long enough to cover the full windup
@export var defend_cooldown := 0.7        # seconds before another guard

@onready var duelist: ApolakiDuelist = get_node_or_null("ArenaField/Apolaki")
@onready var duel_state_label: Label = get_node_or_null("DuelHud/State")

var _strike_cd := 0.0
var _defend_time := 0.0
var _defend_cd := 0.0
var _duelist_spawned := false


func _ready() -> void:
	super._ready()
	if duelist != null:
		duelist.lunge.connect(_on_duelist_lunge)
		duelist.state_changed.connect(_on_duelist_state_changed)
		if not _duelist_spawned:
			var spawn_rng := RandomNumberGenerator.new()
			spawn_rng.seed = int(_my_id) * 7919 + 5
			var offset := Vector2(spawn_rng.randf_range(-55.0, 55.0), spawn_rng.randf_range(-35.0, 35.0))
			var spawn := (duelist.global_position + offset).clamp(_field.position + Vector2(30.0, 30.0), _field.end - Vector2(30.0, 30.0))
			duelist.set_duel_spawn(spawn)
			duelist.bounds = _field.grow(-28.0)
			_duelist_spawned = true


func collect_units() -> void:
	# One Apolaki per screen, the same authored node on every peer (his position
	# never travels).
	if duelist != null:
		duelist.color = god.color
		duelist.target = player.global_position


func arena_round_reset() -> void:
	_strike_cd = 0.0
	_defend_cd = 0.0
	_defend_time = 0.0
	if duelist != null:
		duelist.restart()


func _process(delta: float) -> void:
	super._process(delta)
	_strike_cd = maxf(0.0, _strike_cd - delta)
	_defend_cd = maxf(0.0, _defend_cd - delta)
	_defend_time = maxf(0.0, _defend_time - delta)
	if duelist != null:
		duelist.target = player.global_position
		duelist.frozen = _phase != Phase.PLAYING or (due_menu != null and due_menu.is_open())
	_update_duel_state()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and not event.double_click:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT or mouse.button_index == MOUSE_BUTTON_RIGHT:
			if _phase != Phase.PLAYING or player.locked or dialogue.is_active() or due_menu.is_open():
				return
			if mouse.button_index == MOUSE_BUTTON_LEFT:
				_try_strike()
			else:
				_try_defend()
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


func _try_strike() -> void:
	if _strike_cd > 0.0 or duelist == null:
		return
	_strike_cd = strike_cooldown
	if duelist.global_position.distance_to(player.global_position) > duelist.reach + strike_reach_bonus:
		_log("Your strike falls short", god.color)
		return
	if duelist.is_guarding():
		_submit_score(&"strike_guard")
		_log("Apolaki turned your strike aside", god.color)
		return
	if duelist.is_open():
		_submit_score(&"strike_open")
		_log("You found Apolaki's blind spot", god.color)
	else:
		_submit_score(&"strike_neutral")
		_log("You landed a strike", god.color)
	duelist.flinch()


func _try_defend() -> void:
	if _defend_cd > 0.0:
		return
	_defend_cd = defend_cooldown
	_defend_time = defend_window
	_log("You brace for Apolaki's strike", god.color)


func _on_duelist_lunge() -> void:
	if _phase != Phase.PLAYING:
		return
	if _defend_time > 0.0:
		_defend_time = 0.0
		_submit_score(&"block")
		_log("You blocked Apolaki's strike", god.color)
	else:
		_submit_score(&"hit")
		knock_mortal(_my_id, duelist.global_position)
		_log("Apolaki struck you", Color(1.0, 0.55, 0.4))


func _submit_score(score_id: StringName) -> void:
	if _authority:
		_resolve_score(_my_id, score_id)
		_publish_god_state()
	elif _net != null and _net.has_multiplayer_peer():
		_net.rpc_id(1, "request_apolaki_score", score_id)


func _on_apolaki_score_requested(peer_id: int, score_id: StringName) -> void:
	if not _authority or _phase != Phase.PLAYING or rules.mortal(peer_id) == null:
		return
	_resolve_score(peer_id, score_id)
	_publish_god_state()


func _resolve_score(mortal_id: int, score_id: StringName) -> void:
	match score_id:
		&"strike_open":
			bank_favor(strike_open_favor, "striking Apolaki's blind spot", mortal_id)
		&"strike_neutral":
			bank_favor(strike_neutral_favor, "striking Apolaki", mortal_id)
		&"strike_guard":
			lose_favor(strike_guard_penalty, "striking Apolaki's guard", mortal_id)
		&"block":
			bank_favor(block_favor, "blocking Apolaki", mortal_id)
		&"hit":
			lose_favor(hit_penalty, "Apolaki's strike", mortal_id)


func _connect_network() -> void:
	super._connect_network()
	if _net != null and _authority and _net.has_signal("apolaki_score_requested"):
		_net.apolaki_score_requested.connect(_on_apolaki_score_requested)


func _on_duelist_state_changed(_state: int) -> void:
	_update_duel_state()


func _update_duel_state() -> void:
	if duel_state_label == null or duelist == null:
		return
	var state_text := "WATCHES"
	match duelist.state:
		ApolakiDuelist.State.OPEN:
			state_text = "BLIND SPOT - STRIKE NOW"
		ApolakiDuelist.State.GUARD:
			state_text = "APOLAKI IS GUARDING"
		ApolakiDuelist.State.WINDUP:
			state_text = "APOLAKI IS WINDING UP"
		ApolakiDuelist.State.STRIKE:
			state_text = "APOLAKI STRIKES"
	duel_state_label.text = state_text
