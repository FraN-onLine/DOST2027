extends Node

# Player options, kept per machine in user://settings.cfg. Nothing here is sent
# over the network and nothing changes a gameplay rule: audio, window, key
# bindings, the default name and a few comfort toggles only.
#
# set_value() applies a change at once and emits setting_changed; save() writes
# the file. Bad or missing values fall back to DEFAULTS.
#
# Audio: there are no sounds yet. When they arrive, play music on the "Music"
# bus, gameplay effects on "SFX" and menu clicks on "UI" (default_bus_layout.tres).
# Future code should also check screen_shake_enabled() before shaking a camera.

signal setting_changed(section: String, key: String, value: Variant)

const FONT := preload("res://Assets/fonts/Minecraftia-Regular.ttf")
const BUSES := {"master": "Master", "music": "Music", "sfx": "SFX", "ui": "UI"}
const WINDOW_MODES := ["Windowed", "Fullscreen", "Borderless fullscreen"]
const FPS_CHOICES := [30, 60, 120, 144, 0]  # 0 = unlimited
const UI_SCALES := [80, 90, 100, 110, 125, 150]
const RESOLUTIONS := [
	Vector2i(1152, 648), Vector2i(1280, 720), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]
# Actions the Controls tab can rebind, in display order.
const ACTIONS := {
	"move_up": "Move Up", "move_down": "Move Down", "move_left": "Move Left",
	"move_right": "Move Right", "attack": "Attack", "defend": "Defend",
	"skill_e": "Skill E", "skill_q": "Skill Q", "due_menu": "God's Due menu",
	"advance_dialogue": "Advance dialogue", "due_choice_1": "God's Due choice 1",
	"due_choice_2": "God's Due choice 2", "due_choice_3": "God's Due choice 3",
}
const DEFAULTS := {
	"audio": {"master": 100, "music": 80, "sfx": 100, "ui": 100, "mute_unfocused": false},
	"video": {"window_mode": 0, "resolution": Vector2i(1152, 648), "vsync": true, "max_fps": 0, "ui_scale": 100},
	"gameplay": {"player_name": "", "reduce_flashing": false, "screen_shake": true, "show_fps": false},
}

var config_path := "user://settings.cfg"
var _values := {}                # section -> {key: value}; "controls" -> {action: spec}
var _default_events := {}        # action -> Array[InputEvent], captured from project.godot
var _focused := true
var _fps_layer: CanvasLayer
var _fps_label: Label


func _ready() -> void:
	for action in ACTIONS:
		_default_events[action] = InputMap.action_get_events(action).duplicate()
	_fps_layer = CanvasLayer.new()
	_fps_layer.layer = 100
	_fps_label = Label.new()
	_fps_label.position = Vector2(6, 4)
	_fps_label.add_theme_font_override("font", FONT)
	_fps_label.add_theme_font_size_override("font_size", 12)
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_layer.add_child(_fps_label)
	add_child(_fps_layer)
	load_config()


func _process(_delta: float) -> void:
	if _fps_layer.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = what == NOTIFICATION_APPLICATION_FOCUS_IN
		_apply_bus("master")


# --- reading / writing -----------------------------------------------------

func get_value(section: String, key: String) -> Variant:
	var stored: Dictionary = _values.get(section, {})
	return stored.get(key, DEFAULTS[section][key])


func set_value(section: String, key: String, value: Variant) -> void:
	if not DEFAULTS.has(section) or not DEFAULTS[section].has(key):
		return
	value = _clean(section, key, value)
	if not _values.has(section):
		_values[section] = {}
	_values[section][key] = value
	_apply(section, key)
	setting_changed.emit(section, key, value)


func load_config() -> void:
	reset_controls()
	_values.clear()
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		_apply_all()
		return
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			if cfg.has_section_key(section, key):
				_values[section] = _values.get(section, {})
				_values[section][key] = _clean(section, key, cfg.get_value(section, key))
	if cfg.has_section("controls"):
		_values["controls"] = {}
		for action in ACTIONS:
			if not cfg.has_section_key("controls", action):
				continue
			var spec: Variant = cfg.get_value("controls", action)
			if spec is Dictionary and spec_to_event(spec) != null:
				_values["controls"][action] = spec
	_apply_all()


func save() -> void:
	var cfg := ConfigFile.new()
	for section in _values:
		for key in _values[section]:
			cfg.set_value(section, key, _values[section][key])
	cfg.save(config_path)


func reset_section(section: String) -> void:
	if section == "controls":
		reset_controls()
		return
	for key in DEFAULTS.get(section, {}):
		set_value(section, key, DEFAULTS[section][key])
	_values.erase(section)


func reset_all() -> void:
	for section in DEFAULTS:
		reset_section(section)
	reset_controls()


# Out-of-range or wrong-typed values become the default.
func _clean(section: String, key: String, value: Variant) -> Variant:
	var fallback: Variant = DEFAULTS[section][key]
	if typeof(value) != typeof(fallback):
		if typeof(fallback) == TYPE_INT and typeof(value) == TYPE_FLOAT:
			value = int(value)
		else:
			return fallback
	match key:
		"master", "music", "sfx", "ui":
			return clampi(value, 0, 100)
		"window_mode":
			return value if value in range(WINDOW_MODES.size()) else fallback
		"max_fps":
			return value if value in FPS_CHOICES else fallback
		"ui_scale":
			return value if value in UI_SCALES else fallback
		"resolution":
			return value if value.x >= 640 and value.y >= 360 else fallback
		"player_name":
			return (value as String).strip_edges().left(20)
	return value


# --- applying --------------------------------------------------------------

func _apply_all() -> void:
	for section in DEFAULTS:
		for key in DEFAULTS[section]:
			_apply(section, key)
	reset_bindings_to_saved()


func _apply(section: String, key: String) -> void:
	match section:
		"audio":
			if key == "mute_unfocused":
				_apply_bus("master")
			else:
				_apply_bus(key)
		"video":
			_apply_video(key)
		"gameplay":
			if key == "show_fps":
				_fps_layer.visible = get_value("gameplay", "show_fps")


func _apply_bus(key: String) -> void:
	var bus := AudioServer.get_bus_index(BUSES[key])
	if bus < 0:
		return
	var volume: int = get_value("audio", key)
	var silent := volume == 0
	if key == "master" and not _focused and get_value("audio", "mute_unfocused"):
		silent = true
	AudioServer.set_bus_mute(bus, silent)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume / 100.0, 0.0001)))


func _apply_video(key: String) -> void:
	if DisplayServer.get_name() == "headless":
		return  # no window to configure (checks, servers)
	match key:
		"window_mode", "resolution":
			_apply_window()
		"vsync":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if get_value("video", "vsync") else DisplayServer.VSYNC_DISABLED)
		"max_fps":
			Engine.max_fps = get_value("video", "max_fps")
		"ui_scale":
			if is_inside_tree():
				get_tree().root.content_scale_factor = int(get_value("video", "ui_scale")) / 100.0


func _apply_window() -> void:
	match int(get_value("video", "window_mode")):
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var size: Vector2i = get_value("video", "resolution")
			DisplayServer.window_set_size(size)
			var screen := DisplayServer.window_get_current_screen()
			var origin := DisplayServer.screen_get_position(screen)
			DisplayServer.window_set_position(origin + (DisplayServer.screen_get_size(screen) - size) / 2)


# Windowed sizes that fit the current screen (always includes the saved one).
func available_resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var list: Array[Vector2i] = []
	for size in RESOLUTIONS:
		if size.x <= screen.x and size.y <= screen.y:
			list.append(size)
	var current: Vector2i = get_value("video", "resolution")
	if not list.has(current):
		list.append(current)
	return list


# --- small helpers for the rest of the game --------------------------------

func screen_shake_enabled() -> bool:
	return get_value("gameplay", "screen_shake")


func reduce_flashing() -> bool:
	return get_value("gameplay", "reduce_flashing")


# Saved name if the player set one, otherwise a random suggestion.
func suggested_name() -> String:
	var saved: String = get_value("gameplay", "player_name")
	return saved if not saved.is_empty() else Network.RANDOM_NAMES[randi() % Network.RANDOM_NAMES.size()]


# --- key bindings ----------------------------------------------------------
# Only the PRIMARY (first) event of an action is rebindable; secondary events
# (the arrow keys, keypad digits) stay unless a swap takes them.

func event_to_spec(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"type": "key", "code": int((event as InputEventKey).physical_keycode)}
	if event is InputEventMouseButton:
		return {"type": "mouse", "button": int((event as InputEventMouseButton).button_index)}
	return {}


func spec_to_event(spec: Dictionary) -> InputEvent:
	if spec.get("type") == "key" and spec.get("code") is int and spec["code"] > 0:
		var key := InputEventKey.new()
		key.physical_keycode = spec["code"]
		return key
	if spec.get("type") == "mouse" and spec.get("button") is int and spec["button"] > 0:
		var click := InputEventMouseButton.new()
		click.button_index = spec["button"]
		return click
	return null


func same_input(a: InputEvent, b: InputEvent) -> bool:
	return not event_to_spec(a).is_empty() and event_to_spec(a) == event_to_spec(b)


func primary_event(action: String) -> InputEvent:
	var events := InputMap.action_get_events(action)
	return events[0] if not events.is_empty() else null


# Display text such as "W", "Left Click", "Kp 1", matched to the player's layout.
func event_label(event: InputEvent) -> String:
	if event is InputEventMouseButton:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Left Click"
			MOUSE_BUTTON_RIGHT: return "Right Click"
			MOUSE_BUTTON_MIDDLE: return "Middle Click"
			_: return "Mouse %d" % (event as InputEventMouseButton).button_index
	if event is InputEventKey:
		var code := DisplayServer.keyboard_get_keycode_from_physical((event as InputEventKey).physical_keycode)
		return OS.get_keycode_string(code)
	return "Unbound"


# The other action already using `event` (any of its events), or "".
func conflict_for(action: String, event: InputEvent) -> String:
	for other in ACTIONS:
		if other == action:
			continue
		for existing in InputMap.action_get_events(other):
			if same_input(existing, event):
				return other
	return ""


func set_binding(action: String, event: InputEvent) -> void:
	var spec := event_to_spec(event)
	if not ACTIONS.has(action) or spec.is_empty():
		return
	_replace_primary(action, spec_to_event(spec))
	_values["controls"] = _values.get("controls", {})
	_values["controls"][action] = spec
	setting_changed.emit("controls", action, spec)


# Give `event` to `action` and hand the action's old primary to whoever held `event`.
func swap_binding(action: String, event: InputEvent) -> void:
	var other := conflict_for(action, event)
	var old := primary_event(action)
	set_binding(action, event)
	if other.is_empty():
		return
	var events := InputMap.action_get_events(other)
	for index in events.size():
		if same_input(events[index], event):
			if old == null:
				InputMap.action_erase_event(other, events[index])
			else:
				InputMap.action_erase_event(other, events[index])
				InputMap.action_add_event(other, old)
				# keep the replacement first when it took the primary slot
				if index == 0:
					_move_to_front(other, old)
			_values["controls"] = _values.get("controls", {})
			_values["controls"][other] = event_to_spec(primary_event(other))
			setting_changed.emit("controls", other, _values["controls"][other])
			return


func reset_controls() -> void:
	for action in ACTIONS:
		InputMap.action_erase_events(action)
		for event in _default_events.get(action, []):
			InputMap.action_add_event(action, event)
		setting_changed.emit("controls", action, event_to_spec(primary_event(action)))
	_values.erase("controls")


func reset_bindings_to_saved() -> void:
	for action in _values.get("controls", {}):
		_replace_primary(action, spec_to_event(_values["controls"][action]))


func _replace_primary(action: String, event: InputEvent) -> void:
	var rest := InputMap.action_get_events(action).slice(1)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	for extra in rest:
		if not same_input(extra, event):
			InputMap.action_add_event(action, extra)


func _move_to_front(action: String, event: InputEvent) -> void:
	var rest: Array = []
	for existing in InputMap.action_get_events(action):
		if not same_input(existing, event):
			rest.append(existing)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	for extra in rest:
		InputMap.action_add_event(action, extra)
