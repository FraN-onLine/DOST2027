extends Control

# Arena HUD.
# Top-left: the two stats - FAVOR and the GOD'S DUE voucher count - with the two
# favor bars (E on the left, Q on the right) directly underneath them.
# The two bars are TAPPABLE: a click on one fires the favor it holds, the same
# as its key (skill_pressed carries that to the arena).
# Also carries the trial clock, the event line, the banner and the end-of-trial
# results panel, and the TOP-RIGHT COLUMN (top_right): first a small note for the favors
# that keep something of the mortal's somewhere else - Kabiyak's other half and Kamalig's
# granary - then, under it, the EFFECT TIMERS: one row (EffectRow) for each effect running
# on the local mortal, with its icon, name and the seconds left on a shrinking bar,
# removed the moment it ends. A buff (our own lasting skill, a Pamana's opening window)
# is drawn in its own colour; a debuff a rival's skill or a knock put on us is EMBER.
# What is running is the arena's to say (Arena.local_effects, handed over through
# effect_source); this only draws it. An arena with a list of its own in the corner
# (Langit Lupa's TAYA list) hangs it in the same column, so nothing covers anything.
#
# SKILL CARDS (UI/GodsArena/skill_card.tscn), in a stack at the side of the field, next
# to the skill bars - never in the middle, and they never pause the game or take input
# that is not a click on the card itself:
#   * a POPUP for ~popup_seconds when the local mortal gains an E / Q skill (God's Due,
#     a boon, a god's gift): the key, icon, name, description, cooldown and what it
#     REPLACES. A click on it, or the skill's own key, closes it early; two gains
#     close together queue and show one after the other.
#   * INFO while the mouse is over a skill bar (the shell's two bars in an embedded
#     run, or this HUD's own), and, for both skills at once, while skill_info (Tab by
#     default) is held.
#
# Presentation (UI/theme): translucent PanelHud panels; every colour a god or a
# favor hands in is drawn through UITokens.readable_on_dark, since the HUD's
# words sit on night plates and dark rims. The banner sits high, under the
# clock, so the middle of the field stays clear.

const COLOR_TIME_OK := UITokens.IVORY
const COLOR_TIME_LOW := UITokens.EMBER
const SKILL_CARD_SCENE := preload("res://UI/GodsArena/skill_card.tscn")
const EFFECT_ROW_SCENE := preload("res://UI/GodsArena/effect_row.tscn")
# Where the cards stand: right of the shell's left strip, just under its skill bars - or,
# when this HUD draws its own stats panel (a standalone arena), just under that.
const CARDS_LEFT := Arena.UI_STRIP_WIDTH + 8.0
const CARDS_TOP := 132.0
const CARDS_GAP := 8.0

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
@onready var top_right: VBoxContainer = $TopRight
@onready var favor_note: Label = $TopRight/FavorNote
@onready var effects_box: VBoxContainer = $TopRight/Effects
@onready var card_stack: VBoxContainer = $SkillCards

# How long a gain popup stays up, seconds.
@export var popup_seconds := 4.0

var _match: GodMatch = null
var _god: God = null
var _bar_favor: Dictionary = {}
var _banner_time := 0.0
var _popup: SkillCard = null          # the gain popup on screen (null: none)
var _popup_left := 0.0
var _popup_queue: Array[Dictionary] = []  # gains waiting: {favor, replaced}
var _info_cards: Dictionary = {}      # slot -> the info card on screen
var _hover_slot := -1                 # the skill bar the mouse is over (-1: none)
# What is running on the local mortal: a Callable returning Arena.effect() entries.
var effect_source := Callable()
var _effect_rows: Dictionary = {}     # effect key -> its EffectRow
var _effect_totals: Dictionary = {}   # effect key -> the longest it has been seen to run (the bar's 100%)


func _ready() -> void:
	bar_e.setup("E")
	bar_q.setup("Q")
	bar_e.pressed.connect(_on_bar_pressed.bind(GodFavor.Slot.E))
	bar_q.pressed.connect(_on_bar_pressed.bind(GodFavor.Slot.Q))
	bar_e.hovered.connect(func(on: bool) -> void: set_hover_slot(GodFavor.Slot.E if on else -1))
	bar_q.hovered.connect(func(on: bool) -> void: set_hover_slot(GodFavor.Slot.Q if on else -1))
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
	_match.skill_gained.connect(_on_skill_gained)
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


# The banner is one family with the floating text (UI/Popups/favor_popup.gd): the
# theme's night plate gets a 1 px border in the banner's colour, and it pops in
# with a slight overshoot (no pop with reduce flashing).
func show_banner(text: String, color: Color, duration := 2.0) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", UITokens.readable_on_dark(color, UITokens.NIGHT_900))
	var plate := banner_label.get_theme_stylebox("normal").duplicate() as PixelStyleBox
	if plate != null:
		plate.border_color = color
		plate.border_width = 1
		banner_label.add_theme_stylebox_override("normal", plate)
	var fresh := not banner_label.visible
	banner_label.visible = true
	_banner_time = duration
	if fresh and not UITokens.calm():
		banner_label.pivot_offset = banner_label.size * 0.5
		banner_label.scale = Vector2.ONE * 0.6
		create_tween().tween_property(banner_label, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	_tick_skill_cards(delta)
	_sync_effects()
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


# --- EFFECT TIMERS ---------------------------------------------------------------------

# Bring the stack in line with what is running now: a row appears when an effect starts,
# counts down while it runs and goes when it ends. Buffs first, then debuffs.
func _sync_effects() -> void:
	var entries: Array = effect_source.call() if effect_source.is_valid() else []
	var running := {}
	for entry in entries:
		if float(entry["left"]) <= 0.0:
			continue
		running[entry["key"]] = entry
	for key in _effect_rows.keys().duplicate():
		if not running.has(key):
			var gone: EffectRow = _effect_rows[key]
			effects_box.remove_child(gone)
			gone.queue_free()
			_effect_rows.erase(key)
			_effect_totals.erase(key)
	var position := 0
	for harmful in [false, true]:
		for key in running.keys():
			var entry: Dictionary = running[key]
			if bool(entry.get("harmful", false)) != harmful:
				continue
			var row: EffectRow = _effect_rows.get(key)
			if row == null:
				row = EFFECT_ROW_SCENE.instantiate()
				effects_box.add_child(row)
				_effect_rows[key] = row
			# The bar is measured against the effect's own length when it is known, else
			# against the longest it has been seen to run.
			var total := maxf(float(_effect_totals.get(key, 0.0)), maxf(float(entry.get("total", 0.0)), float(entry["left"])))
			_effect_totals[key] = total
			row.show_effect(entry, total)
			effects_box.move_child(row, position)
			position += 1


# --- SKILL CARDS ---------------------------------------------------------------------

func _on_skill_gained(player_id: int, favor: GodFavor, replaced: GodFavor) -> void:
	if _match != null and player_id == _match.local_id:
		queue_skill_popup(favor, replaced)


# Show the card of a skill the mortal just got - now, or after the ones before it.
func queue_skill_popup(favor: GodFavor, replaced: GodFavor = null) -> void:
	_popup_queue.append({"favor": favor, "replaced": replaced})
	if _popup == null:
		_next_skill_popup()


func _next_skill_popup() -> void:
	if _popup_queue.is_empty():
		return
	var gain: Dictionary = _popup_queue.pop_front()
	var favor: GodFavor = gain["favor"]
	_popup = SKILL_CARD_SCENE.instantiate()
	card_stack.add_child(_popup)
	card_stack.move_child(_popup, 0)
	_popup.show_skill(favor.slot, favor, _cooldown_of(favor), gain["replaced"], true)
	_popup.dismissed.connect(dismiss_skill_popup)
	_popup_left = popup_seconds
	_place_cards()


# Close the popup now (a click, its key) and bring up the next one, if any.
func dismiss_skill_popup() -> void:
	if _popup != null:
		card_stack.remove_child(_popup)
		_popup.queue_free()
		_popup = null
	_popup_left = 0.0
	_next_skill_popup()


# Was this click (screen coordinates) on the popup? If so it is closed and the click is
# the HUD's - the arena asks this before its own attack reads the mouse (Arena._tap_panel_click).
func click_skill_popup(point: Vector2) -> bool:
	if _popup == null or not _popup.get_global_rect().has_point(point):
		return false
	dismiss_skill_popup()
	return true


# The skill bar the mouse is over (-1: none left): its card shows until it leaves.
func set_hover_slot(slot: int) -> void:
	_hover_slot = slot


func _cooldown_of(favor: GodFavor) -> float:
	return _match.skill_cooldown(favor.slot) if _match != null else favor.cooldown


func _tick_skill_cards(delta: float) -> void:
	if card_stack.get_child_count() > 0:
		_place_cards()  # follows the stats panel if it is shown or hidden meanwhile
	if _popup != null:
		_popup_left -= delta
		if _popup_left <= 0.0:
			dismiss_skill_popup()
	# The info cards: both skills while skill_info is held, else the hovered bar's.
	var wanted: Array[int] = []
	if _match != null:
		if Input.is_action_pressed(&"skill_info"):
			wanted = [GodFavor.Slot.E, GodFavor.Slot.Q]
		elif _hover_slot >= 0:
			wanted = [_hover_slot]
		if _popup != null:
			wanted.erase(_popup.slot)  # its popup is already showing that very card
	for slot in _info_cards.keys().duplicate():
		var shown: SkillCard = _info_cards[slot]
		var favor := _match.skill_favor(slot) if _match != null else null
		if not wanted.has(slot) or favor == null or shown.favor != favor:
			card_stack.remove_child(shown)
			shown.queue_free()
			_info_cards.erase(slot)
	for slot in wanted:
		var favor := _match.skill_favor(slot)
		if favor == null or _info_cards.has(slot):
			continue
		var card: SkillCard = SKILL_CARD_SCENE.instantiate()
		card_stack.add_child(card)
		card.show_skill(slot, favor, _cooldown_of(favor))
		_info_cards[slot] = card
		_place_cards()


# The stack's corner: beside the shell's strip under its bars, or under this HUD's own
# stats panel when that one is showing.
func _place_cards() -> void:
	var stats := get_node_or_null("StatsPanel") as Control
	if stats != null and stats.visible:
		card_stack.position = Vector2(stats.position.x, stats.position.y + stats.size.y + CARDS_GAP)
	else:
		card_stack.position = Vector2(CARDS_LEFT, CARDS_TOP)


# The key that closes the popup is the skill's own: pressing it dismisses the card (the
# cast itself still goes through - this never takes the event).
func _unhandled_input(event: InputEvent) -> void:
	if _popup == null or not (event is InputEventKey):
		return
	var action := &"skill_e" if _popup.slot == GodFavor.Slot.E else &"skill_q"
	if event.is_action_pressed(action):
		dismiss_skill_popup()


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
