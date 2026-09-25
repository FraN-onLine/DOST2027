extends Control

# Arena HUD.
# Top-left: the two stats - FAVOR and the GOD'S DUE voucher count - with the two
# favor bars (E on the left, Q on the right) directly underneath them.
# Also carries the trial clock, the rival mortals, the event line, the
# disruption banner and the end-of-trial results panel.

const COLOR_TIME_OK := Color(1, 1, 1, 1)
const COLOR_TIME_LOW := Color(1, 0.4, 0.35, 1)

@onready var god_label: Label = $StatsPanel/Margin/VBox/GodLabel
@onready var game_label: Label = $StatsPanel/Margin/VBox/GameLabel
@onready var favor_value: Label = $StatsPanel/Margin/VBox/StatsRow/FavorBox/FavorValue
@onready var due_value: Label = $StatsPanel/Margin/VBox/StatsRow/DueBox/DueValue
@onready var bar_e: PanelContainer = $StatsPanel/Margin/VBox/SkillRow/SkillBarE
@onready var bar_q: PanelContainer = $StatsPanel/Margin/VBox/SkillRow/SkillBarQ
@onready var time_label: Label = $TrialPanel/Margin/VBox/TimeLabel
@onready var trial_label: Label = $TrialPanel/Margin/VBox/TrialLabel
@onready var leader_panel: PanelContainer = $LeaderPanel
@onready var rival_list: VBoxContainer = $LeaderPanel/Margin/VBox/RivalList
@onready var event_label: Label = $EventLabel
@onready var banner_label: Label = $BannerLabel
@onready var results_panel: PanelContainer = $ResultsPanel
@onready var results_title: Label = $ResultsPanel/Margin/VBox/ResultsTitle
@onready var results_label: Label = $ResultsPanel/Margin/VBox/ResultsLabel
@onready var results_hint: Label = $ResultsPanel/Margin/VBox/ResultsHint

var _match: GodMatch = null
var _god: God = null
var _bar_favor: Dictionary = {}
var _rival_rows: Dictionary = {}
var _banner_time := 0.0


func _ready() -> void:
	bar_e.setup("E")
	bar_q.setup("Q")
	results_panel.visible = false
	banner_label.visible = false
	leader_panel.visible = false
	event_label.text = ""


func bind(match_ref: GodMatch, god_ref: God) -> void:
	_match = match_ref
	_god = god_ref
	if _god != null:
		god_label.text = _god.display_name
		god_label.add_theme_color_override("font_color", _god.color)
		game_label.text = _god.game_name
		game_label.add_theme_color_override("font_color", Color(_god.color.r, _god.color.g, _god.color.b, 0.75))
	_build_rivals()
	log_event("The trial begins.", _god.color if _god != null else Color.WHITE)


func set_trial(index: int, total: int) -> void:
	trial_label.text = "TRIAL %d OF %d" % [index, total]


func set_time_left(seconds: float) -> void:
	var clamped := maxf(0.0, seconds)
	time_label.text = "%d:%02d" % [int(clamped / 60.0), int(clamped) % 60]
	time_label.add_theme_color_override("font_color", COLOR_TIME_LOW if clamped <= 10.0 else COLOR_TIME_OK)


func show_banner(text: String, color: Color, duration := 2.0) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", color)
	banner_label.visible = true
	_banner_time = duration


func hide_banner() -> void:
	_banner_time = 0.0
	banner_label.visible = false


func log_event(text: String, color: Color) -> void:
	event_label.text = text
	event_label.add_theme_color_override("font_color", color)


func show_results(summary: Dictionary, title := "TRIAL COMPLETE") -> void:
	results_title.text = title
	var lines: Array[String] = []
	for id in summary.keys():
		var row: Dictionary = summary[id]
		var line := "%s   %d FAVOR" % [str(row.get("name", "?")), int(row.get("favor", 0))]
		if int(row.get("bonus", 0)) > 0:
			line += "   (+%d)" % int(row["bonus"])
		if int(row.get("due", 0)) > 0:
			line += "   [%d GOD'S DUE]" % int(row["due"])
		lines.append(line)
	results_label.text = "\n".join(lines)
	results_panel.visible = true


func hide_results() -> void:
	results_panel.visible = false


func set_results_hint(text: String) -> void:
	results_hint.text = text


func _build_rivals() -> void:
	for child in rival_list.get_children():
		rival_list.remove_child(child)
		child.queue_free()
	_rival_rows.clear()
	if _match == null:
		leader_panel.visible = false
		return
	for id in _match.mortals.keys():
		var mortal := _match.mortal(id)
		if mortal == null or mortal.is_local:
			continue
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 12)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rival_list.add_child(label)
		_rival_rows[mortal.id] = label
	leader_panel.visible = not _rival_rows.is_empty()


func _process(delta: float) -> void:
	if _banner_time > 0.0:
		_banner_time = maxf(0.0, _banner_time - delta)
		if _banner_time <= 0.0:
			banner_label.visible = false
	if _match == null:
		return
	var mortal := _match.local()
	if mortal == null:
		return
	favor_value.text = str(mortal.favor)
	due_value.text = str(mortal.due)
	for id in _rival_rows.keys():
		var rival := _match.mortal(id)
		if rival != null:
			_rival_rows[id].text = "%s   %d" % [rival.display_name, rival.favor]
	_sync_bar(bar_e, GodFavor.Slot.E)
	_sync_bar(bar_q, GodFavor.Slot.Q)


func _sync_bar(bar: PanelContainer, slot: int) -> void:
	var favor := _match.skill_favor(slot)
	if _bar_favor.get(bar, null) != favor:
		_bar_favor[bar] = favor
		bar.set_favor(favor)
	var remaining := 0.0
	if favor != null:
		var mortal := _match.local()
		if mortal != null:
			remaining = mortal.cooldown_left(favor.id)
	bar.set_state(_match.skill_cooldown_ratio(slot), remaining)
