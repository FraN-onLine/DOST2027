extends PanelContainer

# The lobby's OPTIONS popup: the host sets up the run before pressing START.
#
# Every control is a view of Network.run_settings and writes back through
# Network.set_run_setting(), never to a field of its own - so the panel, the
# summary under the player list, the saved user://lobby_settings.cfg and every
# client's lobby all show the same setup, and a change from anywhere (a sync from
# the host, RESET) simply repaints the panel through run_settings_changed.
#
# Everyone can open it. Only the host's copy is `editable`; a client sees the
# same rows with every control disabled, so they know what is about to be played.
#
# The panel is hidden until OPTIONS opens it, so it never sits over the
# START / LEAVE row while closed. Only the custom order list scrolls.

signal closed

const BATHALA_ROW_TEXT := "BATHALA (finale)"
const REPEAT_COLOR := Color(1, 0.45, 0.4)
const NUMBER_COLOR := Color(0.6, 0.65, 0.75)

@onready var minus_button: Button = $Margin/VBox/Body/TrialsRow/Minus
@onready var plus_button: Button = $Margin/VBox/Body/TrialsRow/Plus
@onready var trials_value: Label = $Margin/VBox/Body/TrialsRow/Value
@onready var run_line: Label = $Margin/VBox/Body/RunLine
@onready var random_box: CheckBox = $Margin/VBox/Body/OrderRow/RandomBox
@onready var custom_box: CheckBox = $Margin/VBox/Body/OrderRow/CustomBox
@onready var order_scroll: ScrollContainer = $Margin/VBox/Body/OrderScroll
@onready var order_list: VBoxContainer = $Margin/VBox/Body/OrderScroll/OrderList
@onready var warning_label: Label = $Margin/VBox/Body/Warning
@onready var time_option: OptionButton = $Margin/VBox/Body/TimeRow/TimeOption
@onready var due_option: OptionButton = $Margin/VBox/Body/DueRow/DueOption
@onready var intro_option: OptionButton = $Margin/VBox/Body/IntroRow/IntroOption
@onready var host_note: Label = $Margin/VBox/Body/HostNote
@onready var reset_button: Button = $Margin/VBox/Buttons/ResetButton
@onready var done_button: Button = $Margin/VBox/Buttons/DoneButton

var editable := false
var _syncing := false  # true while refresh() repaints, so the controls' signals are ignored


func _ready() -> void:
	visible = false
	# RANDOM / CUSTOM are one choice: a ButtonGroup keeps exactly one ticked.
	var group := ButtonGroup.new()
	random_box.button_group = group
	custom_box.button_group = group
	random_box.toggled.connect(_on_mode_toggled.bind(RunSettings.ORDER_RANDOM))
	custom_box.toggled.connect(_on_mode_toggled.bind(RunSettings.ORDER_CUSTOM))
	minus_button.pressed.connect(_step_trials.bind(-1))
	plus_button.pressed.connect(_step_trials.bind(1))
	for seconds in RunSettings.TRIAL_TIMES:
		time_option.add_item("%d seconds" % int(seconds))
	for step in RunSettings.DUE_STEPS:
		due_option.add_item("%d FAVOR" % step)
	intro_option.add_item("FULL (first visit)")
	intro_option.add_item("SHORT (always)")
	time_option.item_selected.connect(func(index: int) -> void: _change("trial_time", RunSettings.TRIAL_TIMES[index]))
	due_option.item_selected.connect(func(index: int) -> void: _change("due_step", RunSettings.DUE_STEPS[index]))
	intro_option.item_selected.connect(func(index: int) -> void:
		_change("intro_mode", RunSettings.INTRO_FULL if index == 0 else RunSettings.INTRO_SHORT))
	reset_button.pressed.connect(_on_reset_pressed)
	done_button.pressed.connect(close)
	Network.run_settings_changed.connect(func(_settings: Dictionary) -> void: refresh())
	refresh()


func open(can_edit: bool) -> void:
	editable = can_edit
	refresh()
	visible = true
	done_button.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


# Repaint every control from Network.run_settings.
func refresh() -> void:
	if not is_node_ready():
		return
	var settings: RunSettings = Network.run_settings
	_syncing = true
	trials_value.text = str(settings.trials)
	minus_button.disabled = not editable or settings.trials <= Gods.TRIALS_MIN
	plus_button.disabled = not editable or settings.trials >= Gods.TRIALS_MAX
	run_line.text = settings.run_line()
	var custom := settings.order_mode == RunSettings.ORDER_CUSTOM
	random_box.button_pressed = not custom
	custom_box.button_pressed = custom
	random_box.disabled = not editable
	custom_box.disabled = not editable
	time_option.select(RunSettings.TRIAL_TIMES.find(settings.trial_time))
	due_option.select(RunSettings.DUE_STEPS.find(settings.due_step))
	intro_option.select(0 if settings.intro_mode == RunSettings.INTRO_FULL else 1)
	for option in [time_option, due_option, intro_option]:
		option.disabled = not editable
	reset_button.disabled = not editable
	host_note.visible = not editable
	order_scroll.visible = custom
	_rebuild_rows(settings)
	var problems := settings.problems()
	warning_label.visible = not problems.is_empty()
	warning_label.text = "" if problems.is_empty() else "%s - START is disabled until it is fixed." % problems[0]
	_syncing = false


# One row per trial slot (CUSTOM): number, god dropdown, UP / DOWN. The last row
# is always Bathala's finale - no dropdown, no buttons.
func _rebuild_rows(settings: RunSettings) -> void:
	for child in order_list.get_children():
		order_list.remove_child(child)
		child.queue_free()
	if settings.order_mode != RunSettings.ORDER_CUSTOM:
		return
	var repeats := settings.repeat_slots()
	var playable := RunSettings.playable_ids()
	for slot in range(settings.custom_order.size()):
		order_list.add_child(_slot_row(slot, settings, playable, repeats.has(slot)))
	var finale := Label.new()
	finale.name = "BathalaRow"
	finale.text = "%d.  %s" % [settings.custom_order.size() + 1, BATHALA_ROW_TEXT]
	finale.add_theme_color_override("font_color", Gods.bathala().color)
	order_list.add_child(finale)


func _slot_row(slot: int, settings: RunSettings, playable: Array[StringName], repeated: bool) -> HBoxContainer:
	var god_id: StringName = settings.custom_order[slot]
	var row := HBoxContainer.new()
	row.name = "Slot%d" % (slot + 1)
	row.add_theme_constant_override("separation", 6)

	var number := Label.new()
	number.text = "%d." % (slot + 1)
	number.custom_minimum_size = Vector2(26, 0)
	number.add_theme_color_override("font_color", REPEAT_COLOR if repeated else NUMBER_COLOR)
	row.add_child(number)

	var picker := OptionButton.new()
	picker.name = "God"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in playable:
		picker.add_item(Gods.by_id(id).display_name)
	picker.select(playable.find(god_id))
	var god := Gods.by_id(god_id)
	if god != null:
		picker.add_theme_color_override("font_color", god.color)
		picker.add_theme_color_override("font_disabled_color", Color(god.color, 0.7))
	# Every god hosts at most one trial: a god already in another slot is greyed out.
	for index in range(playable.size()):
		var elsewhere := settings.custom_order.duplicate()
		elsewhere.remove_at(slot)
		picker.set_item_disabled(index, elsewhere.has(playable[index]))
	picker.disabled = not editable
	picker.item_selected.connect(_on_slot_picked.bind(slot))
	row.add_child(picker)

	var up := Button.new()
	up.name = "Up"
	up.text = "UP"
	up.disabled = not editable or slot == 0
	up.pressed.connect(_on_move_pressed.bind(slot, -1))
	row.add_child(up)

	var down := Button.new()
	down.name = "Down"
	down.text = "DOWN"
	down.disabled = not editable or slot == settings.custom_order.size() - 1
	down.pressed.connect(_on_move_pressed.bind(slot, 1))
	row.add_child(down)
	return row


# --- edits (the host's only) ---------------------------------------------------

func _change(key: String, value) -> void:
	if _syncing or not editable:
		return
	Network.set_run_setting(key, value)


func _step_trials(step: int) -> void:
	_change("trials", Network.run_settings.trials + step)


func _on_mode_toggled(pressed: bool, mode: String) -> void:
	if pressed:
		_change("order_mode", mode)


func _on_slot_picked(index: int, slot: int) -> void:
	var order := Network.run_settings.custom_order.duplicate()
	order[slot] = RunSettings.playable_ids()[index]
	_change("custom_order", order)


func _on_move_pressed(slot: int, step: int) -> void:
	var order := Network.run_settings.custom_order.duplicate()
	var target := slot + step
	if target < 0 or target >= order.size():
		return
	var moving: StringName = order[slot]
	order[slot] = order[target]
	order[target] = moving
	_change("custom_order", order)


func _on_reset_pressed() -> void:
	if editable:
		Network.set_run_settings(RunSettings.defaults().to_dict())


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
