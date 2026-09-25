extends Control

# Bathala's game shell. The shell owns shared player panels and chooses the
# current trial; each god arena remains a replaceable child controller.

const MAYARI_ARENA_SCENE := preload("res://scenes/MayariArena.tscn")
const OPPONENT_PANEL_SCENE := preload("res://UI/opponentpanels.tscn")
const TRIAL_COUNT := 5

@onready var own_name_label: Label = $TopLeft/VBoxContainer/NameLabel
@onready var favor_label: Label = $BathalaPanel/Margin/VBox/StatsRow/FavorValue
@onready var due_label: Label = $BathalaPanel/Margin/VBox/StatsRow/DueValue
@onready var e_bar: ProgressBar = $BathalaPanel/Margin/VBox/SkillRow/EBar
@onready var q_bar: ProgressBar = $BathalaPanel/Margin/VBox/SkillRow/QBar
@onready var trial_label: Label = $BathalaPanel/Margin/VBox/TrialLabel
@onready var god_label: Label = $BathalaPanel/Margin/VBox/GodLabel
@onready var arena_title: Label = $ArenaPanel/ArenaTitle
@onready var opponent_vbox: VBoxContainer = $OpponentPanelContainer/VBoxContainer

var arena: Node = null
var rules: GodMatch = null
var opponent_panels := {}
var trial_order: Array[God] = []
var trial_index := 0
var run_snapshot := {}


func _ready() -> void:
	_build_hud()
	_build_trial_order()
	_start_current_trial()


func _build_hud() -> void:
	var my_id := multiplayer.get_unique_id()
	$TopLeft/VBoxContainer/StatsRow.visible = false
	own_name_label.text = str(Network.players.get(my_id, Network.my_name if Network.my_name != "" else "Mortal"))
	for child in opponent_vbox.get_children():
		child.queue_free()
	opponent_panels.clear()
	for pid in Network.players.keys():
		var id_int := int(pid)
		if id_int == my_id:
			continue
		var panel := OPPONENT_PANEL_SCENE.instantiate()
		opponent_vbox.add_child(panel)
		panel.setup(id_int, str(Network.players[pid]), 100, 10)
		opponent_panels[id_int] = panel
	e_bar.value = 0.0
	q_bar.value = 0.0


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
	god_label.text = god.display_name
	god_label.add_theme_color_override("font_color", god.color)
	trial_label.text = "TRIAL %d OF %d" % [trial_index + 1, trial_order.size()]
	arena_title.text = "%s  |  %s" % [god.display_name, god.game_name]

	# Bathala is the closing challenge marker until its dedicated arena exists.
	# The modular slot is kept in the shell so adding BathalaArena later does not
	# require changing the lobby or player HUD.
	if god.id == Gods.BATHALA:
		return
	if god.id != Gods.MAYARI:
		god = Gods.mayari()
	var arena_instance := MAYARI_ARENA_SCENE.instantiate()
	arena_instance.embedded = true
	arena_instance.embedded_rect = Rect2(270.0, 180.0, maxf(460.0, size.x - 520.0), maxf(280.0, size.y - 270.0))
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
	if not run_snapshot.is_empty():
		rules.apply_snapshot(run_snapshot)
	_refresh_local_stats()


func _process(_delta: float) -> void:
	_refresh_local_stats()
	if rules != null:
		_update_skill_bar(e_bar, GodFavor.Slot.E)
		_update_skill_bar(q_bar, GodFavor.Slot.Q)


func _refresh_local_stats() -> void:
	if rules == null:
		return
	var mortal := rules.local()
	if mortal == null:
		return
	favor_label.text = str(mortal.favor)
	due_label.text = str(mortal.due)


func _update_skill_bar(bar: ProgressBar, slot: int) -> void:
	var favor := rules.skill_favor(slot)
	if favor == null:
		bar.value = 0.0
		bar.tooltip_text = "%s  --" % ("E" if slot == GodFavor.Slot.E else "Q")
		return
	bar.value = rules.skill_cooldown_ratio(slot) * 100.0
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
