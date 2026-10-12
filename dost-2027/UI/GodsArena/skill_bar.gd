class_name SkillBar
extends PanelContainer

# One FAVOR skill slot - the E bar on the left, the Q bar on the right.
#   no favor bound to the slot -> the bar stays blank
#   favor ready to use         -> the bar is full
#   favor on cooldown          -> the bar slowly refills
#
# The bar is TAPPABLE: a click on it is the same as pressing its key (the arena
# answers it, see Arena._input and god_hud's skill_pressed signal). It also
# answers hit tests (`handles`) so the paths that claim the mouse before the GUI
# ever sees it can ask "was that click on me?".

signal pressed

const COLOR_READY := Color(1, 1, 1, 1)
const COLOR_COOLING := Color(1, 1, 1, 0.6)
const COLOR_EMPTY := Color(0.42, 0.45, 0.55, 1)

@onready var fill: ColorRect = $Body/Fill
@onready var text_label: Label = $Body/Text

var key_text := "E"
var favor: GodFavor = null

var _ratio := 0.0
var _remaining := 0.0
var _hovering := false
var _border_color := Color(0.28, 0.32, 0.44, 1)


func _ready() -> void:
	# Each bar gets its own copy of the authored stylebox: the authored one is
	# shared by every instance of the scene, and the hover tint below would
	# otherwise brighten one bar's border on all of them.
	var authored := get_theme_stylebox("panel")
	if authored is StyleBoxFlat:
		add_theme_stylebox_override("panel", authored.duplicate())
		_border_color = (authored as StyleBoxFlat).border_color
	set_favor(null)
	# A tap target: the panel itself takes the mouse, its contents stay see-through.
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


# Was that click (in screen coordinates) on this bar?
func handles(point: Vector2) -> bool:
	return is_visible_in_tree() and get_global_rect().has_point(point)


func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	pressed.emit()


func _on_mouse_entered() -> void:
	_hovering = true
	_refresh_border()


func _on_mouse_exited() -> void:
	_hovering = false
	_refresh_border()


# The border brightens under the mouse, so the bar reads as something you can
# press - the same affordance the God's Due rows get.
func _refresh_border() -> void:
	var style := get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.border_color = _border_color.lightened(0.45 if _hovering else 0.0)


# Call once so the bar knows which key it stands for.
func setup(new_key: String) -> void:
	key_text = new_key
	_refresh_text()


# Only call when the bound favor actually changes - it resets the fill.
func set_favor(new_favor: GodFavor) -> void:
	favor = new_favor
	if favor == null:
		_ratio = 0.0
		_remaining = 0.0
		fill.visible = false
	else:
		fill.visible = true
		fill.color = favor.color
		_ratio = 1.0
		_remaining = 0.0
		_border_color = favor.color
	_refresh_text()
	_refresh_border()


# ratio: 1.0 = ready, 0.0 = just used. remaining: seconds of cooldown left.
func set_state(ratio: float, remaining: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	_remaining = maxf(0.0, remaining)
	if fill.visible:
		fill.anchor_right = _ratio
	_refresh_text()


func _refresh_text() -> void:
	if favor == null:
		text_label.text = "%s  --" % key_text
		text_label.add_theme_color_override("font_color", COLOR_EMPTY)
		return
	if _ratio >= 1.0:
		text_label.text = "%s  %s  READY" % [key_text, favor.display_name.to_upper()]
		text_label.add_theme_color_override("font_color", COLOR_READY)
		return
	text_label.text = "%s  %s  %ds" % [key_text, favor.display_name.to_upper(), int(ceil(_remaining))]
	text_label.add_theme_color_override("font_color", COLOR_COOLING)
