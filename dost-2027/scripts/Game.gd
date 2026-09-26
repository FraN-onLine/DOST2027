extends Control

# Bathala's game shell. The shell owns shared player panels and chooses the
# current trial; each god arena remains a replaceable child controller.

const OPPONENT_PANEL_SCENE := preload("res://UI/opponentpanels.tscn")
const TRIAL_COUNT := 5

@onready var own_name_label: Label = $TopLeft/VBoxContainer/NameLabel
@onready var favor_label: Label = $TopLeft/VBoxContainer/StatsRow/FavorBox/FavorValue
@onready var due_label: Label = $TopLeft/VBoxContainer/StatsRow/DueBox/DueValue
@onready var other_players_vbox: VBoxContainer = $OtherPlayersPanel/Margin/VBox
@onready var timer_label: Label = $TrialTimer

var arena: Node = null
var rules: GodMatch = null
var trial_order: Array[God] = []
var trial_index := 0
var run_snapshot := {}
var other_player_panels := {}


func _ready() -> void:
	_build_hud()
	_build_trial_order()
	_start_current_trial()


func _build_hud() -> void:
	var my_id := multiplayer.get_unique_id()
	own_name_label.text = str(Network.players.get(my_id, Network.my_name if Network.my_name != "" else "Mortal"))
	$TopLeft/VBoxContainer/StatsRow/FavorBox/FavorCaption.text = "FAVOR"
	$TopLeft/VBoxContainer/StatsRow/DueBox/DueCaption.text = "DUE"
	_build_other_player_panels()


func _build_other_player_panels() -> void:
	for child in other_players_vbox.get_children():
		child.queue_free()
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


func _build_trial_order() -> void:
	var playable: Array[God] = []
	for god in Gods.all():
		if god.implemented:
			playable.append(god)
	playable.shuffle()
	if playable.is_empty():
		playable.append(Gods.mayari())
	trial_order.clear()
	for index in range(TRIAL_COUNT - 1):
		trial_order.append(playable[index % playable.size()])
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
	arena_instance.embedded = true
	arena_instance.dialogue_prefix = "trial_%d" % (trial_index + 1)
	arena_instance.embedded_rect = _arena_rect()
	$ArenaPanel.add_child(arena_instance)
	arena = arena_instance
	arena.tree_exited.connect(_on_arena_exited)
	arena.trial_complete.connect(_on_trial_complete)
	call_deferred("_on_arena_ready")


func _arena_rect() -> Rect2:
	# The right-hand play area, beside the stat panels on the left.
	return Rect2(270.0, 180.0, maxf(460.0, size.x - 520.0), maxf(280.0, size.y - 270.0))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_arena_rect()


func _update_arena_rect() -> void:
	if arena == null or not is_instance_valid(arena):
		return
	arena.embedded_rect = _arena_rect()
	arena.refresh_field()


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
	_update_skill_bar($TopLeft/VBoxContainer/StatsRow/FavorBox/EBar, GodFavor.Slot.E, mortal)
	_update_skill_bar($TopLeft/VBoxContainer/StatsRow/DueBox/QBar, GodFavor.Slot.Q, mortal)
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
