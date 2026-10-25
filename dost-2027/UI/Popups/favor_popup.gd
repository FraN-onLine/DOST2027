class_name FavorPopup
extends PanelContainer

# One piece of floating game text in the house style: plain outlined text, no
# frame - "+500 FAVOR" in JADE when FAVOR arrives, "-120 FAVOR" in EMBER when it
# is taken, the reason (if any) on a second line at 8 px in muted ivory. The same
# popup, at 24 px, carries a trial's callouts ("TAYA!", "TRIP!") and a god's E
# icon (show_icon) - an icon row instead of a number.
#
# It lives in SCREEN space, on the arena's popup layer (above every field effect -
# Mayari's blackout, Apolaki's sun patches, Hanan's bar - and below the bottom band).
# The arena owns where it goes: each frame Arena._layout_popups() hands place() the
# point its bottom edge should sit on (the mortal's screen position, stacked above
# the newer popups); this script only animates itself there:
#   pop in   POP_TIME with a slight overshoot (none with reduce flashing)
#   hold     HOLD_TIME (a callout: as long as the arena keeps it up)
#   go       rise RISE px and fade over FADE_TIME, then free itself
# A loss gives a tiny sideways shake as it appears (not with reduce flashing).
# Positions are whole pixels, so the pixel font stays crisp at the game's 2x.
#
# Arena.spawn_popup() / Arena.favor_popup() / Arena.callout() / Arena.cast_popup()
# make them; nothing else draws game text over a mortal.

const POP_TIME := 0.12
const HOLD_TIME := 0.7
const FADE_TIME := 0.4
const RISE := 20.0
const RETIRE_TIME := 0.15  # an oldest popup pushed out of a full stack fades this fast
const SHAKE_TIME := 0.18
const SHAKE_PIXELS := 2.0
const BIG := 24
const NORMAL := 16
const ICON := 36.0
const OUTLINE := 6
const REASON_OUTLINE := 4

@onready var rows: VBoxContainer = $Rows
@onready var icon: TextureRect = $Rows/Row/Icon
@onready var number_label: Label = $Rows/Row/Number
@onready var reason_label: Label = $Rows/Reason

var persistent := false   # a callout: holds until the arena lets it go (expire())
var keep := false         # the arena's one callout pill: hidden when done, never freed
var base_scale := 1.0     # a rival's popup: 0.75
var base_alpha := 1.0     # ...and 75% opaque
var _age := 0.0
var _hold := HOLD_TIME
var _going_at := -1.0     # the age the rise-and-fade began (-1: not yet)
var _go_time := FADE_TIME
var _calm := false
var _shake := false
var _bump := 0.0          # a merge's little pop, 0..1
var _anchor := Vector2.ZERO


func _ready() -> void:
	# No frame: the text carries its own dark outline, so it reads over the field
	# without a panel behind it.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	number_label.add_theme_constant_override("outline_size", OUTLINE)
	number_label.add_theme_color_override("font_outline_color", UITokens.NIGHT_900)
	reason_label.add_theme_constant_override("outline_size", REASON_OUTLINE)
	reason_label.add_theme_color_override("font_outline_color", UITokens.NIGHT_900)
	modulate.a = 0.0  # placed (and shown) on its first frame


# A FAVOR change: `number` ("+500 FAVOR"), `tint` (gain / loss), an optional
# reason under it, at 24 px when `big`. `calm` is reduce flashing (no overshoot,
# no shake); a loss shakes as it appears.
func show_text(number: String, tint: Color, reason := "", big := false, calm := false, loss := false) -> void:
	if not is_node_ready():
		await ready
	_calm = calm
	_shake = loss and not calm
	_paint(number, tint, reason, big)
	_age = 0.0
	_going_at = -1.0
	_bump = 0.0
	visible = true
	set_process(true)


# A god's E icon over the mortal who cast it: the icon alone, no text.
func show_icon(icon_texture: Texture2D, tint: Color, calm := false) -> void:
	if not is_node_ready():
		await ready
	_calm = calm
	_shake = false
	number_label.visible = false
	reason_label.visible = false
	icon.texture = icon_texture
	icon.modulate = tint
	icon.custom_minimum_size = Vector2.ONE * ICON
	icon.visible = true
	_age = 0.0
	_going_at = -1.0
	_bump = 0.0
	visible = true
	reset_size()
	set_process(true)


# The callout pill put away at once (and its label with it, so its text reads off).
func hide_now() -> void:
	if not is_node_ready():
		await ready
	visible = false
	number_label.visible = false
	icon.visible = false
	persistent = false
	_going_at = -1.0
	set_process(false)


# A second change merged into this popup (Arena.favor_popup): the new total and a
# small bump, so the eye catches that the number moved. The clock starts over.
func relabel(number: String, tint: Color) -> void:
	_paint(number, tint, reason_label.text, number_label.get_theme_font_size("font_size") >= BIG)
	_bump = 0.0 if _calm else 1.0
	_age = minf(_age, POP_TIME)
	_going_at = -1.0


# A callout's text changes while it is up: repainted in place (no new pop).
func repaint(number: String, tint: Color) -> void:
	_paint(number, tint, "", true)


# Pushed out of a full stack: it fades now, quickly, where it stands.
func retire() -> void:
	if _going_at < 0.0 or _go_time > RETIRE_TIME:
		_going_at = _age
		_go_time = RETIRE_TIME


# A callout let go: it rises and fades like any popup.
func expire() -> void:
	persistent = false
	if _going_at < 0.0:
		_going_at = maxf(_age, POP_TIME)
		_go_time = FADE_TIME


func is_going() -> bool:
	return _going_at >= 0.0


func number_text() -> String:
	return number_label.text if number_label != null and number_label.visible else ""


# The height it takes in its mortal's stack (scaled, whole pixels).
func stack_height() -> float:
	return ceilf(size.y * base_scale)


# Where its bottom edge sits this frame (screen pixels); the arena calls it.
func place(bottom_center: Vector2) -> void:
	_anchor = bottom_center


func _paint(number: String, tint: Color, reason: String, big: bool) -> void:
	icon.visible = false
	number_label.visible = true
	number_label.text = number
	number_label.add_theme_color_override("font_color", tint)
	number_label.add_theme_font_size_override("font_size", BIG if big else NORMAL)
	reason_label.text = reason
	reason_label.visible = reason != ""
	reset_size()


func _process(delta: float) -> void:
	_age += delta
	if not persistent and _going_at < 0.0 and _age >= POP_TIME + _hold:
		_going_at = _age
		_go_time = FADE_TIME
	var going := 0.0
	if _going_at >= 0.0:
		going = clampf((_age - _going_at) / maxf(0.01, _go_time), 0.0, 1.0)
		if going >= 1.0:
			if keep:
				hide_now()
			else:
				queue_free()
			return
	var pop := 1.0
	if not _calm and _age < POP_TIME:
		var t := _age / POP_TIME
		pop = 0.6 + 0.4 * t + 0.25 * sin(t * PI)  # 0.6 -> overshoot -> 1.0
	if _bump > 0.0:
		_bump = maxf(0.0, _bump - delta / POP_TIME)
		pop += 0.15 * sin(_bump * PI)
	scale = Vector2.ONE * base_scale * pop
	pivot_offset = Vector2(size.x * 0.5, size.y)
	var shake := 0.0
	if _shake and _age < SHAKE_TIME:
		shake = SHAKE_PIXELS * sin(_age * 70.0) * (1.0 - _age / SHAKE_TIME)
	var rise := RISE * going if _go_time >= FADE_TIME else 0.0
	position = (_anchor - Vector2(size.x * 0.5, size.y) + Vector2(shake, -rise)).round()
	modulate.a = base_alpha * (1.0 - going)
