extends Control

# Bathala's game shell. The shell owns shared player panels and chooses the
# current trial; each god arena remains a replaceable child controller.
#
# The shell's own panel is a vertical stack - the mortal's name, FAVOR with DUE
# on the row below it, then the E favor bar and the Q favor bar, one per row -
# and one panel per rival mortal hangs underneath it. Game.tscn authors the
# first rival panel so the layout can be seen without a second player.
#
# Both panels only ever grow downwards inside that strip: the rival column is
# sized so every rival of Network.MAX_PLAYERS (three) fits above the bottom of
# the screen, and a lobby name is clipped to its own panel with an ellipsis
# instead of being allowed to widen it.
#
# Arena contract (scripts/gods/common/arena.gd): every arena scene is authored in
# screen space exactly as it is played - the scene fills the screen and keeps
# the left Arena.UI_STRIP_WIDTH pixels clear for the panels below. The shell
# therefore just instantiates the arena: it never resizes, scales or re-centres
# it, so every player sees the same authored layout.
#
# One trial = one arena child of ArenaPanel (a full-screen, input-transparent
# Control), which is why the arena's own coordinates are already screen
# coordinates.

const OPPONENT_PANEL_SCENE := preload("res://UI/opponentpanels.tscn")

@onready var own_name_label: Label = $TopLeft/VBoxContainer/NameLabel
@onready var favor_label: Label = $TopLeft/VBoxContainer/StatsRow/FavorBox/FavorValue
@onready var due_label: Label = $TopLeft/VBoxContainer/StatsRow/DueBox/DueValue
@onready var e_bar: ProgressBar = $TopLeft/VBoxContainer/EBar
@onready var q_bar: ProgressBar = $TopLeft/VBoxContainer/QBar
@onready var other_players_vbox: VBoxContainer = $OtherPlayersPanel/Margin/VBox
@onready var opponent_placeholder: Control = $OtherPlayersPanel/Margin/VBox/OpponentPlaceholder
@onready var timer_label: Label = $TrialTimer

var arena: Node = null
var rules: GodMatch = null
var trial_order: Array[God] = []
var trial_index := 0
var run_snapshot := {}
var other_player_panels := {}


func _ready() -> void:
	_build_hud()
	# A name is live data: the lobby's UPDATE NAME can land at any time, and so can
	# a join or a leave, so the panels follow the roster instead of being written
	# once at start-up.
	Network.player_list_updated.connect(_on_player_list_updated)
	Network.player_name_changed.connect(_on_player_name_changed)
	_build_trial_order()
	_start_current_trial()


func _build_hud() -> void:
	var my_id := multiplayer.get_unique_id()
	own_name_label.text = str(Network.players.get(my_id, Network.my_name if Network.my_name != "" else "Mortal"))
	$TopLeft/VBoxContainer/StatsRow/FavorBox/FavorCaption.text = "FAVOR"
	$TopLeft/VBoxContainer/StatsRow/DueBox/DueCaption.text = "DUE"
	_build_other_player_panels()


func _build_other_player_panels() -> void:
	for panel in other_player_panels.values():
		if is_instance_valid(panel):
			panel.queue_free()
	other_player_panels.clear()
	var my_id := multiplayer.get_unique_id()
	for peer_id in Network.players.keys():
		var id := int(peer_id)
		if id == my_id:
			continue
		var panel := OPPONENT_PANEL_SCENE.instantiate()
		other_players_vbox.add_child(panel)
		panel.setup(id, str(Network.players[peer_id]), 0, 0)
		other_player_panels[id] = panel
	# OpponentPlaceholder is the panel authored in Game.tscn: it previews the
	# layout while you are alone and steps aside for the first real rival.
	opponent_placeholder.visible = other_player_panels.is_empty()


func _on_player_list_updated(_players: Dictionary) -> void:
	# The roster changed (a rival joined or left): rebuild the column, which also
	# repaints every name in it.
	_build_hud()


func _on_player_name_changed(peer_id: int, name: String) -> void:
	var clean := name.strip_edges()
	if clean.is_empty():
		return
	if peer_id == multiplayer.get_unique_id():
		own_name_label.text = clean
		return
	var panel = other_player_panels.get(peer_id)
	if panel != null and is_instance_valid(panel):
		panel.set_name_text(clean)


func _build_trial_order() -> void:
	# 4 to 6 challenges drawn from the gods that ship an arena, in a random
	# order, and then Bathala's final challenge - Bathala is always last.
	var playable: Array[God] = []
	for god in Gods.all():
		if god.implemented and god.arena_scene != "":
			playable.append(god)
	if playable.is_empty():
		playable.append(Gods.mayari())
	var challenges := randi_range(Gods.CHALLENGE_MIN, Gods.CHALLENGE_MAX)
	trial_order.clear()
	var pool: Array[God] = []
	for index in range(challenges):
		# A god can come back - the order and the appearances are random - but
		# never twice before everyone else has had their turn.
		if pool.is_empty():
			pool = playable.duplicate()
			pool.shuffle()
		trial_order.append(pool.pop_front())
	trial_order.append(Gods.bathala())


func _start_current_trial() -> void:
	var god := trial_order[trial_index]

	# Every god of the trial order ships its own arena scene (res://scenes/gods/
	# <god>/). Bathala has none yet, so it stays the marker that closes the run.
	if not god.implemented or god.arena_scene == "":
		timer_label.text = "THE GODS ARE PLEASED"
		return
	var packed: PackedScene = load(god.arena_scene)
	if packed == null:
		push_warning("Cannot load the %s arena (%s)" % [god.display_name, god.arena_scene])
		return
	var arena_instance: Node2D = packed.instantiate()
	arena_instance.god_id = god.id
	# The shell draws the shared panels; the arena keeps its left strip empty for
	# them and owns the rest of the screen exactly as it was authored.
	arena_instance.embedded = true
	arena_instance.dialogue_prefix = "trial_%d" % (trial_index + 1)
	$ArenaPanel.add_child(arena_instance)
	arena = arena_instance
	arena.tree_exited.connect(_on_arena_exited)
	arena.trial_complete.connect(_on_trial_complete)
	call_deferred("_on_arena_ready")


func _on_arena_ready() -> void:
	if arena == null or not is_instance_valid(arena):
		return
	rules = arena.rules
	if rules == null:
		return
	rules.favor_changed.connect(_on_favor_changed)
	rules.due_changed.connect(_on_due_changed)
	if arena.has_signal("trial_time_changed"):
		arena.trial_time_changed.connect(_on_trial_time_changed)
	# The clock starts at the arena's own round length (Arena.trial_time) and
	# the shell - not the arena - is what knows which trial this is and how many
	# the run holds.
	var round_length = arena.get("trial_time")
	if round_length != null:
		_on_trial_time_changed(float(round_length))
	var arena_hud = arena.get("hud")
	if arena_hud != null:
		arena_hud.set_trial(trial_index + 1, trial_order.size())
	if not run_snapshot.is_empty():
		rules.apply_snapshot(run_snapshot)
	_refresh_local_stats()


func _on_trial_time_changed(seconds: float) -> void:
	var clamped := maxf(0.0, seconds)
	timer_label.text = "%d:%02d" % [int(clamped / 60.0), int(clamped) % 60]


func _process(_delta: float) -> void:
	_refresh_local_stats()
	if rules != null:
		_update_panel_stats()


func _refresh_local_stats() -> void:
	if rules == null:
		return
	var mortal := rules.local()
	if mortal == null:
		return
	favor_label.text = str(mortal.favor)
	due_label.text = str(mortal.due)


func _update_panel_stats() -> void:
	var mortal := rules.local()
	if mortal == null:
		return
	_update_skill_bar(e_bar, GodFavor.Slot.E, mortal)
	_update_skill_bar(q_bar, GodFavor.Slot.Q, mortal)
	for id in other_player_panels.keys():
		var other := rules.mortal(int(id))
		if other == null:
			continue
		other_player_panels[id].update_stats(other.favor, other.due)
		other_player_panels[id].update_skill_bar(rules, other)


func _update_skill_bar(bar: ProgressBar, slot: int, mortal: GodMatch.Mortal) -> void:
	var favor := mortal.favor_in_slot(slot)
	if favor == null:
		bar.value = 0.0
		bar.tooltip_text = "%s  --" % ("E" if slot == GodFavor.Slot.E else "Q")
		return
	var ratio := 1.0
	if favor.cooldown > 0.0:
		ratio = clampf(1.0 - mortal.cooldown_left(favor.id) / favor.cooldown, 0.0, 1.0)
	bar.value = ratio * 100.0
	bar.tooltip_text = "%s  %s" % [("E" if slot == GodFavor.Slot.E else "Q"), favor.display_name]
	bar.modulate = favor.color


func _on_favor_changed(_player_id: int, _favor: int, _delta: int, _reason: String) -> void:
	_refresh_local_stats()


func _on_due_changed(_player_id: int, _due: int) -> void:
	_refresh_local_stats()


func _on_trial_complete() -> void:
	if rules != null:
		run_snapshot = rules.snapshot()
	trial_index += 1
	if trial_index >= trial_order.size():
		return
	if arena != null and is_instance_valid(arena):
		arena.queue_free()
	arena = null
	rules = null
	_start_current_trial()


func _on_arena_exited() -> void:
	arena = null
	rules = null
