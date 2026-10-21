class_name BandanaSwatch
extends Button

# One bandana colour (UITokens.BANDANA_COLORS) as a small square, in two jobs:
#
#   * a MARK beside a player's name - their panel on the shell's left strip, the
#     lobby list, the results - so a name and the bandana on the field match.
#     BandanaSwatch.mark() builds one: it takes no mouse and no focus.
#   * a PICKER in the lobby: one swatch per colour in the player's own row. A
#     colour another player holds is `locked` - greyed out with a padlock, disabled
#     - and the colour the player wears is `chosen` (a gold frame). Pressing a free
#     one asks the host for it (Network.choose_bandana_color); the host decides.
#
# Everything is drawn here, from UITokens, so a colour swapped in the palette shows
# up everywhere at once. The Button's own styles are emptied: the swatch is the
# colour, and its frame says what state it is in.

const MARK_SIZE := Vector2(16, 16)
const PICK_SIZE := Vector2(32, 32)
const FRAME := 2.0

var index := 0
var locked := false
var chosen := false


# A non-interactive mark of colour `color_index`.
static func mark(color_index: int, size := MARK_SIZE) -> BandanaSwatch:
	var swatch := BandanaSwatch.new()
	swatch.setup(color_index)
	swatch.custom_minimum_size = size
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.focus_mode = Control.FOCUS_NONE
	return swatch


# One line of a list of players - a results row: the mark of their bandana, then
# `text`, centred. The text is in the Label named "Text" (so a check can read it).
static func player_row(color_index: int, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UITokens.SPACE_8)
	row.add_child(mark(color_index))
	var label := Label.new()
	label.name = "Text"
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	return row


func _init() -> void:
	flat = true
	custom_minimum_size = PICK_SIZE
	for state in [&"normal", &"hover", &"pressed", &"disabled", &"focus", &"hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())


func setup(color_index: int, is_locked := false, is_chosen := false, holder := "") -> void:
	index = posmod(color_index, UITokens.BANDANA_COLORS.size())
	locked = is_locked
	chosen = is_chosen
	disabled = is_locked
	var color_name := UITokens.BANDANA_NAMES[index]
	tooltip_text = "%s - taken by %s" % [color_name, holder] if locked and holder != "" else color_name
	queue_redraw()


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	var color := UITokens.bandana_color(index)
	if locked:
		# Greyed out: the colour is still there to read, but dimmed to the night.
		color = color.lerp(UITokens.NIGHT_700, 0.7)
	draw_rect(box, color)
	var frame_color := UITokens.GOLD if chosen else (UITokens.FAINT if locked else UITokens.LINE)
	draw_rect(box, frame_color, false, FRAME)
	if chosen:
		draw_rect(box.grow(-FRAME), UITokens.NIGHT_900, false, 1.0)
	if locked:
		_draw_padlock(box)


# A padlock out of two shapes, in the middle of the square: a body and a shackle.
func _draw_padlock(box: Rect2) -> void:
	var unit := minf(box.size.x, box.size.y) / 8.0
	var centre := box.get_center()
	var body := Rect2(centre + Vector2(-2.0, 0.0) * unit, Vector2(4.0, 3.0) * unit)
	draw_rect(body, UITokens.IVORY)
	var top := centre + Vector2(0.0, 0.0)
	var shackle := PackedVector2Array([
		top + Vector2(-1.2, 0.0) * unit, top + Vector2(-1.2, -1.6) * unit,
		top + Vector2(1.2, -1.6) * unit, top + Vector2(1.2, 0.0) * unit])
	draw_polyline(shackle, UITokens.IVORY, maxf(1.0, unit * 0.7))
