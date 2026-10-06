extends Control

# The Options screen: Audio, Video, Controls and Gameplay tabs over the
# Settings autoload. Every change applies live; BACK (or Esc) saves and leaves.
#
# The screen does not care which scene it sits in: opened as the current scene
# (title menu) BACK returns to the main menu, opened as an overlay it frees
# itself and emits `closed`.

signal closed

const MENU_SCENE := "res://scenes/MainMenu.tscn"
const REVERT_SECONDS := 10
const TAB_SECTIONS := ["audio", "video", "controls", "gameplay"]
const VOLUMES := {"master": "Master volume", "music": "Music volume", "sfx": "SFX volume", "ui": "UI volume"}
const IGNORED_MOUSE := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]

@onready var tabs: TabContainer = $Panel/Margin/VBox/Tabs
@onready var audio_tab: VBoxContainer = $Panel/Margin/VBox/Tabs/Audio
@onready var video_tab: VBoxContainer = $Panel/Margin/VBox/Tabs/Video
@onready var controls_scroll: ScrollContainer = $Panel/Margin/VBox/Tabs/Controls
@onready var controls_list: VBoxContainer = $Panel/Margin/VBox/Tabs/Controls/List
@onready var gameplay_tab: VBoxContainer = $Panel/Margin/VBox/Tabs/Gameplay
@onready var reset_button: Button = $Panel/Margin/VBox/Buttons/ResetButton
@onready var back_button: Button = $Panel/Margin/VBox/Buttons/BackButton
@onready var confirm: ConfirmationDialog = $ConfirmDialog

var _bind_buttons := {}                 # action -> Button
var _rebind_action := ""                # action waiting for its next input, "" when idle
var _conflict_dialog: ConfirmationDialog
var _pending_action := ""
var _pending_event: InputEvent
var _revert_values := {}                # video values to restore if the confirm times out
var _revert_left := 0
var _revert_timer: Timer
var _resolution_option: OptionButton


func _ready() -> void:
	controls_scroll.follow_focus = true
	back_button.pressed.connect(_on_back_pressed)
	reset_button.pressed.connect(_on_reset_pressed)

	_revert_timer = Timer.new()
	_revert_timer.wait_time = 1.0
	_revert_timer.timeout.connect(_on_revert_tick)
	add_child(_revert_timer)
	confirm.confirmed.connect(_keep_video)
	confirm.canceled.connect(_revert_video)

	_conflict_dialog = ConfirmationDialog.new()
	_conflict_dialog.title = "Key already in use"
	_conflict_dialog.ok_button_text = "SWAP"
	_conflict_dialog.cancel_button_text = "CANCEL"
	_conflict_dialog.confirmed.connect(_swap_pending)
	add_child(_conflict_dialog)

	for index in TAB_SECTIONS.size():
		tabs.set_tab_title(index, TAB_SECTIONS[index].capitalize())
	_build_all()
	tabs.get_tab_bar().grab_focus()


func _build_all() -> void:
	for tab in [audio_tab, video_tab, controls_list, gameplay_tab]:
		_clear(tab)
	_build_audio()
	_build_video()
	_build_controls()
	_build_gameplay()


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


# --- row helpers -------------------------------------------------------------

func _row(parent: Control, text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 280
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)


func _slider_row(parent: Control, text: String, section: String, key: String) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var slider := HSlider.new()
	slider.max_value = 100
	slider.step = 1
	slider.value = Settings.get_value(section, key)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var readout := Label.new()
	readout.custom_minimum_size.x = 48
	readout.text = "%d" % slider.value
	slider.value_changed.connect(func(value: float) -> void:
		readout.text = "%d" % value
		Settings.set_value(section, key, int(value)))
	box.add_child(slider)
	box.add_child(readout)
	_row(parent, text, box)


func _check_row(parent: Control, text: String, section: String, key: String) -> void:
	var check := CheckButton.new()
	check.button_pressed = Settings.get_value(section, key)
	check.toggled.connect(func(on: bool) -> void: Settings.set_value(section, key, on))
	check.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_row(parent, text, check)


func _option_row(parent: Control, text: String, labels: Array, selected: int, on_pick: Callable) -> OptionButton:
	var option := OptionButton.new()
	for label in labels:
		option.add_item(str(label))
	option.selected = selected
	option.item_selected.connect(on_pick)
	_row(parent, text, option)
	return option


# --- tabs --------------------------------------------------------------------

func _build_audio() -> void:
	for key in VOLUMES:
		_slider_row(audio_tab, VOLUMES[key], "audio", key)
	_check_row(audio_tab, "Mute when window loses focus", "audio", "mute_unfocused")


func _build_video() -> void:
	var mode: int = Settings.get_value("video", "window_mode")
	_option_row(video_tab, "Window mode", Settings.WINDOW_MODES, mode, func(index: int) -> void:
		_change_window("window_mode", index)
		_resolution_option.disabled = index != 0)

	var sizes := Settings.available_resolutions()
	var current: Vector2i = Settings.get_value("video", "resolution")
	var names: Array = sizes.map(func(size: Vector2i) -> String: return "%d x %d" % [size.x, size.y])
	_resolution_option = _option_row(video_tab, "Resolution (windowed)", names, sizes.find(current), func(index: int) -> void:
		_change_window("resolution", sizes[index]))
	_resolution_option.disabled = mode != 0

	_check_row(video_tab, "VSync", "video", "vsync")
	var fps_names: Array = Settings.FPS_CHOICES.map(func(fps: int) -> String: return "Unlimited" if fps == 0 else str(fps))
	_option_row(video_tab, "Max FPS", fps_names, Settings.FPS_CHOICES.find(Settings.get_value("video", "max_fps")), func(index: int) -> void:
		Settings.set_value("video", "max_fps", Settings.FPS_CHOICES[index]))
	var scale_names: Array = Settings.UI_SCALES.map(func(percent: int) -> String: return "%d%%" % percent)
	_option_row(video_tab, "UI scale", scale_names, Settings.UI_SCALES.find(Settings.get_value("video", "ui_scale")), func(index: int) -> void:
		Settings.set_value("video", "ui_scale", Settings.UI_SCALES[index]))


func _build_controls() -> void:
	_bind_buttons.clear()
	for action in Settings.ACTIONS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(220, 32)
		button.pressed.connect(_begin_rebind.bind(action))
		_bind_buttons[action] = button
		_row(controls_list, Settings.ACTIONS[action], button)
	_refresh_bindings()


func _build_gameplay() -> void:
	var name_input := LineEdit.new()
	name_input.max_length = 20
	name_input.placeholder_text = "Random name each time"
	name_input.text = Settings.get_value("gameplay", "player_name")
	name_input.text_changed.connect(func(text: String) -> void: Settings.set_value("gameplay", "player_name", text))
	_row(gameplay_tab, "Default player name", name_input)
	_check_row(gameplay_tab, "Reduce flashing", "gameplay", "reduce_flashing")
	_check_row(gameplay_tab, "Screen shake", "gameplay", "screen_shake")
	_check_row(gameplay_tab, "Show FPS counter", "gameplay", "show_fps")


# --- video: keep-or-revert -----------------------------------------------------

func _change_window(key: String, value: Variant) -> void:
	if _revert_values.is_empty():
		_revert_values = {
			"window_mode": Settings.get_value("video", "window_mode"),
			"resolution": Settings.get_value("video", "resolution"),
		}
	Settings.set_value("video", key, value)
	_revert_left = REVERT_SECONDS
	_update_confirm_text()
	_revert_timer.start()
	confirm.popup_centered()


func _update_confirm_text() -> void:
	confirm.dialog_text = "Keep these settings?\nReverting in %ds" % _revert_left


func _on_revert_tick() -> void:
	_revert_left -= 1
	if _revert_left <= 0:
		confirm.hide()
		_revert_video()
	else:
		_update_confirm_text()


func _keep_video() -> void:
	_revert_timer.stop()
	_revert_values.clear()


func _revert_video() -> void:
	_revert_timer.stop()
	for key in _revert_values:
		Settings.set_value("video", key, _revert_values[key])
	_revert_values.clear()
	_clear(video_tab)
	_build_video()


# --- controls: rebinding -------------------------------------------------------

func _refresh_bindings() -> void:
	for action in _bind_buttons:
		_bind_buttons[action].text = Settings.event_label(Settings.primary_event(action))


func _begin_rebind(action: String) -> void:
	_cancel_rebind()
	_rebind_action = action
	_bind_buttons[action].text = "Press a key..."


func _cancel_rebind() -> void:
	_rebind_action = ""
	_refresh_bindings()


func _input(event: InputEvent) -> void:
	if _rebind_action.is_empty():
		return
	var pressed_key: bool = event is InputEventKey and event.pressed and not event.echo
	var pressed_mouse: bool = event is InputEventMouseButton and event.pressed and not IGNORED_MOUSE.has(event.button_index)
	if not (pressed_key or pressed_mouse):
		return
	get_viewport().set_input_as_handled()
	if pressed_key and event.physical_keycode == KEY_ESCAPE:
		_cancel_rebind()
		return
	var action := _rebind_action
	_rebind_action = ""
	var conflict := Settings.conflict_for(action, event)
	if conflict.is_empty():
		Settings.set_binding(action, event)
		_refresh_bindings()
		return
	_pending_action = action
	_pending_event = event
	_conflict_dialog.dialog_text = "%s is already used by \"%s\".\nSwap the two bindings?" % [
		Settings.event_label(event), Settings.ACTIONS[conflict]]
	_conflict_dialog.popup_centered()
	_refresh_bindings()


func _swap_pending() -> void:
	Settings.swap_binding(_pending_action, _pending_event)
	_refresh_bindings()


# --- buttons -----------------------------------------------------------------

func _on_reset_pressed() -> void:
	Settings.reset_section(TAB_SECTIONS[tabs.current_tab])
	_build_all()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _rebind_action.is_empty():
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _on_back_pressed() -> void:
	Settings.save()
	closed.emit()
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file(MENU_SCENE)
	else:
		queue_free()
