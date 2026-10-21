class_name SkillBar
extends PanelContainer

# One FAVOR skill slot - the E slot on the left, the Q slot on the right.
#   [E] [icon] name
#   no favor bound to the slot -> an empty slot and "--"
#   favor ready to use         -> the icon, bright, and its name
#   favor on cooldown          -> a dark curtain over the icon that drains from
#                                 the top down as the cooldown runs out, with
#                                 the seconds left written on it
#
# The key is a keycap read from the player's bindings (Settings.event_label), so
# a rebinding shows here too - recognition over recall.
#
# The bar is TAPPABLE: a click on it is the same as pressing its key (the arena
# answers it, see Arena._input and god_hud's skill_pressed signal). It also
# answers hit tests (`handles`) so the paths that claim the mouse before the GUI
# ever sees it can ask "was that click on me?".

signal pressed
signal hovered(on: bool)  # the mouse entered / left the bar (the HUD shows the skill's card)

const PLACEHOLDER_ICON := preload("res://icon.svg")

@onready var key_label: Label = $Row/Key
@onready var icon: TextureRect = $Row/Slot/Icon
@onready var fill: ColorRect = $Row/Slot/Fill
@onready var seconds_label: Label = $Row/Slot/Seconds
@onready var text_label: Label = $Row/Text

var key_text := "E"
var favor: GodFavor = null

var _ratio := 0.0
var _remaining := 0.0
var _hovering := false
var _base_box: StyleBox


func _ready() -> void:
	_base_box = get_theme_stylebox("panel", &"PanelHud")
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
	hovered.emit(true)


func _on_mouse_exited() -> void:
	_hovering = false
	_refresh_border()
	hovered.emit(false)


# The border takes the bound favor's colour, and turns gold under the mouse, so
# the slot reads as something you can press - the same affordance as a button.
func _refresh_border() -> void:
	if _base_box == null:
		return
	var border := UITokens.LINE
	if _hovering:
		border = UITokens.GOLD
	elif favor != null:
		border = UITokens.readable_on_dark(favor.color, UITokens.NIGHT_900, UITokens.ACCENT_CONTRAST)
	add_theme_stylebox_override("panel", UITokens.accent_box(_base_box, border))


# Call once so the bar knows which key it stands for ("E" or "Q").
func setup(new_key: String) -> void:
	key_text = new_key
	key_label.text = UITokens.key_text(StringName("skill_%s" % new_key.to_lower()))
	_refresh_text()


# Only call when the bound favor actually changes - it resets the fill.
func set_favor(new_favor: GodFavor) -> void:
	favor = new_favor
	_ratio = 0.0 if favor == null else 1.0
	_remaining = 0.0
	icon.visible = favor != null
	if favor != null:
		icon.texture = favor.icon if favor.icon != null else PLACEHOLDER_ICON
		icon.modulate = favor.color  # the placeholder icon is tinted until real art lands
	_refresh_fill()
	_refresh_text()
	_refresh_border()


# ratio: 1.0 = ready, 0.0 = just used. remaining: seconds of cooldown left.
func set_state(ratio: float, remaining: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	_remaining = maxf(0.0, remaining)
	_refresh_fill()
	_refresh_text()


# The curtain covers the part of the cooldown still to run: its top edge moves
# down as the slot recovers (drains from the top to the bottom).
func _refresh_fill() -> void:
	var cooling := favor != null and _ratio < 1.0
	fill.visible = cooling
	fill.anchor_top = _ratio
	seconds_label.visible = cooling
	seconds_label.text = "%d" % int(ceil(_remaining))


func _refresh_text() -> void:
	if favor == null:
		text_label.text = "--"
		text_label.add_theme_color_override("font_color", UITokens.FAINT)
		return
	text_label.text = favor.display_name.to_upper()
	text_label.add_theme_color_override("font_color", UITokens.IVORY if _ratio >= 1.0 else UITokens.MUTED)
