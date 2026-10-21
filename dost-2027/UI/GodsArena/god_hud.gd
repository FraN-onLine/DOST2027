extends Control

# Arena HUD.
# Top-left: the two stats - FAVOR and the GOD'S DUE voucher count - with the two
# favor bars (E on the left, Q on the right) directly underneath them.
# The two bars are TAPPABLE: a click on one fires the favor it holds, the same
# as its key (skill_pressed carries that to the arena).
# Also carries the trial clock, the event line, the banner and the end-of-trial
# results panel, and a small note (top right) for the favors that keep something
# of the mortal's somewhere else: Kabiyak's other half and Kamalig's granary.
#
# Presentation (UI/theme): translucent PanelHud panels; every colour a god or a
# favor hands in is drawn through UITokens.readable_on_dark, since the HUD's
# words sit on night plates and dark rims. The banner sits high, under the
# clock, so the middle of the field stays clear.

const COLOR_TIME_OK := UITokens.IVORY
const COLOR_TIME_LOW := UITokens.EMBER

signal skill_pressed(slot: int)   # one of the two favor bars was tapped

@onready var god_label: Label = $StatsPanel/Margin/VBox/GodLabel
@onready var game_label: Label = $StatsPanel/Margin/VBox/GameLabel
@onready var favor_value: Label = $StatsPanel/Margin/VBox/StatsRow/FavorBox/FavorValue
@onready var due_value: Label = $StatsPanel/Margin/VBox/StatsRow/DueBox/DueValue
@onready var bar_e: SkillBar = $StatsPanel/Margin/VBox/SkillRow/SkillBarE
@onready var bar_q: SkillBar = $StatsPanel/Margin/VBox/SkillRow/SkillBarQ
@onready var time_label: Label = $TrialPanel/Margin/VBox/TimeLabel
@onready var trial_label: Label = $TrialPanel/Margin/VBox/TrialLabel
@onready var event_label: Label = $EventLabel
@onready var banner_label: Label = $BannerLabel
@onready var results_panel: PanelContainer = $ResultsPanel
@onready var results_title: Label = $ResultsPanel/Margin/VBox/ResultsTitle
@onready var results_rows: VBoxContainer = $ResultsPanel/Margin/VBox/ResultsRows
@onready var results_hint: Label = $ResultsPanel/Margin/VBox/ResultsHint
@onready var favor_note: Label = $FavorNote

var _match: GodMatch = null
var _god: God = null
var _bar_favor: Dictionary = {}
var _banner_time := 0.0


func _ready() -> void:
	bar_e.setup("E")
	bar_q.setup("Q")
	bar_e.pressed.connect(_on_bar_pressed.bind(GodFavor.Slot.E))
	bar_q.pressed.connect(_on_bar_pressed.bind(GodFavor.Slot.Q))
	results_panel.visible = false
	banner_label.visible = false
	event_label.text = ""


# A bar was tapped: the arena answers it exactly like its key would.
func _on_bar_pressed(slot: int) -> void:
	skill_pressed.emit(slot)


# Was that click on one of the two favor bars? (The arena asks this before the
# GUI ever sees the mouse - see Arena._input.)
func hit_skill_bar(slot: int, point: Vector2) -> bool:
	var bar: PanelContainer = bar_e if slot == GodFavor.Slot.E else bar_q
	return bar != null and bar.handles(point)


func bind(match_ref: GodMatch, god_ref: God) -> void:
	_match = match_ref
	_god = god_ref
	if _god != null:
		god_label.text = _god.display_name
		god_label.add_theme_color_override("font_color", UITokens.god_text(_god))
		game_label.text = _god.game_name
	log_event("The trial begins.", _god.color if _god != null else Color.WHITE)


func set_trial(index: int, total: int) -> void:
	trial_label.text = "TRIAL %d OF %d" % [index, total]


func set_time_left(seconds: float) -> void:
	var clamped := maxf(0.0, seconds)
	time_label.text = "%d:%02d" % [int(clamped / 60.0), int(clamped) % 60]
	time_label.add_theme_color_override("font_color", COLOR_TIME_LOW if clamped <= 10.0 else COLOR_TIME_OK)


func show_banner(text: String, color: Color, duration := 2.0) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", UITokens.readable_on_dark(color, UITokens.NIGHT_900))
	banner_label.visible = true
	_banner_time = duration


func log_event(text: String, color: Color) -> void:
	event_label.text = text
	event_label.add_theme_color_override("font_color", UITokens.readable_on_dark(color, UITokens.NIGHT_900))


# One row per player - their bandana's swatch, then the line - so the names on
# the results match the headbands on the field.
func show_results(summary: Dictionary, title := "TRIAL COMPLETE") -> void:
	results_title.text = title
	for child in results_rows.get_children():
		results_rows.remove_child(child)
		child.queue_free()
	for id in summary.keys():
		var row: Dictionary = summary[id]
		var line := "%s   %d FAVOR" % [str(row.get("name", "?")), int(row.get("favor", 0))]
		if int(row.get("bonus", 0)) > 0:
			line += "   (+%d)" % int(row["bonus"])
		if int(row.get("due", 0)) > 0:
			line += "   [%d GOD'S DUE]" % int(row["due"])
		results_rows.add_child(BandanaSwatch.player_row(_bandana_of(int(id)), line))
	results_panel.visible = true
	UITokens.reveal(results_panel)


# The colour of a player's bandana. Looked up by path, not by name, so this HUD
# still compiles when it is loaded before the autoloads exist (the tools/ checks).
func _bandana_of(player_id: int) -> int:
	var net := get_node_or_null("/root/Network")
	return int(net.call("bandana_of", player_id)) if net != null else 0


# The results as text, one line per player.
func results_text() -> String:
	var lines: Array[String] = []
	for row in results_rows.get_children():
		lines.append((row.get_node("Text") as Label).text)
	return "\n".join(lines)


func set_results_hint(text: String) -> void:
	results_hint.text = text


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
	_sync_bar(bar_e, GodFavor.Slot.E)
	_sync_bar(bar_q, GodFavor.Slot.Q)
	_sync_favor_note(mortal)


func _sync_favor_note(mortal: GodMatch.Mortal) -> void:
	var lines: Array[String] = []
	if mortal.has_favor(&"kabiyak"):
		var partner := _match.mortal(mortal.kabiyak)
		lines.append("KABIYAK: %s" % (partner.display_name if partner != null else "-"))
	if mortal.granary > 0:
		lines.append("KAMALIG: %d STORED" % mortal.granary)
	favor_note.text = "\n".join(lines)
	favor_note.visible = not lines.is_empty()


func _sync_bar(bar: SkillBar, slot: int) -> void:
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
