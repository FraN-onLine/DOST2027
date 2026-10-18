class_name UITokens
extends RefCounted

# The design system's single source of truth: "the heavens' tournament".
#
# Night-sky indigo surfaces, Bathala's warm gold for anything you can act on,
# ivory text like old paper. tools/build_theme.gd builds UI/theme/bathala_theme.tres
# out of these values, and the few styles that really change at runtime (a god's
# accent on a frame, a FAVOR gain or loss) read them from here too - so retuning a
# colour or a size is a change in this file plus one re-run of the builder.
#
# Rules the values encode:
#   * Type sizes are multiples of 8 only. Minecraftia is drawn on an 8 px grid;
#     any other size lands its pixels between screen pixels and the text goes soft.
#   * Spacing sits on the same 8 px grid (Gestalt proximity: related things share
#     the small gaps, groups are split by the large ones).
#   * A god's colour is an ACCENT (frame, nameplate, underline), never a big fill,
#     and never raw text: readable_on_dark() lightens it until it passes 4.5:1.

# --- colour ------------------------------------------------------------------
# Surfaces, darkest to lightest.
const NIGHT_900 := Color("#0B1020")
const NIGHT_800 := Color("#121A30")
const NIGHT_700 := Color("#1B2545")
const NIGHT_600 := Color("#26335C")
const LINE := Color("#3A4A7A")
# A raised panel's 1 px top highlight: one step lighter than its face.
const HIGHLIGHT := Color("#2C3A66")
# Hard 2 px shadows. A panel casts SHADOW on the night behind it; a button's
# shadow is its own darker lip (LIP, GOLD_LIP), so it still reads on NIGHT_900.
const SHADOW := Color("#04060D")
const LIP := Color("#151C33")

# Text.
const IVORY := Color("#F2E8CF")  # primary text
const MUTED := Color("#A9B3CC")  # secondary text
const FAINT := Color("#6F7A99")  # disabled

# Actions: gold means "you can act on this" (visual hierarchy - one gold thing
# per screen is the primary action).
const GOLD := Color("#E8B84A")
const GOLD_HI := Color("#F6D27A")
const GOLD_LO := Color("#B98A2A")
const GOLD_LIP := Color("#6B4E14")

# States.
const JADE := Color("#5CC48A")   # success / ready / FAVOR gained
const EMBER := Color("#E0614F")  # danger / loss / last seconds
const STAR := Color("#9FD3FF")   # info / keyboard focus ring

# --- type scale (px, multiples of 8 only) ------------------------------------
const CAPTION := 8
const BODY := 16
const HEADING := 24
const DISPLAY := 32
const HERO := 48
const TYPE_SCALE: Array[int] = [CAPTION, BODY, HEADING, DISPLAY, HERO]

# --- spacing -------------------------------------------------------------------
const SPACE_4 := 4
const SPACE_8 := 8
const SPACE_16 := 16
const SPACE_24 := 24
const SPACE_32 := 32
const SPACE_48 := 48

# --- control sizes ---------------------------------------------------------------
# Fitts's law: the primary action is the biggest target on the screen, and
# nothing clickable is shorter than 32 px.
const BUTTON_LARGE := Vector2(260, 52)
const BUTTON_MEDIUM := Vector2(260, 44)
const BUTTON_SMALL := Vector2(120, 32)
const BUTTON_ICON := Vector2(32, 32)
const BUTTON_ICON_LARGE := Vector2(44, 44)
const FIELD_HEIGHT := 44  # LineEdit, OptionButton
const ROW_HEIGHT := 44    # one settings row (Options, Lobby options)
const LABEL_COLUMN := 200 # settings rows: the label column; the control fills the rest

# --- motion ------------------------------------------------------------------
# Restraint: hover and press answer in 80-150 ms, panels slide or fade once.
const HOVER_TIME := 0.1
const PRESS_TIME := 0.08
const PANEL_TIME := 0.15
const HOVER_TINT := Color(1.12, 1.12, 1.12)
const PRESS_TINT := Color(0.82, 0.82, 0.82)

# WCAG: body text needs 4.5:1 against its background; a frame or icon needs 3:1.
const TEXT_CONTRAST := 4.5
const ACCENT_CONTRAST := 3.0


# --- colour helpers ------------------------------------------------------------

static func luminance(color: Color) -> float:
	var channels: Array[float] = []
	for value in [color.r, color.g, color.b]:
		channels.append(value / 12.92 if value <= 0.03928 else pow((value + 0.055) / 1.055, 2.4))
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


# `color`, lightened toward ivory until it reads at `ratio` against `background`.
# Raw god colours are tuned for sprites, not text: Tala's deep blue
# (0.12, 0.22, 0.48) is 1.6:1 on NIGHT_800 - invisible as a word. Mixing toward
# IVORY (not white) keeps the hue's warmth and the paper feel of the text.
static func readable_on_dark(color: Color, background: Color = NIGHT_800, ratio: float = TEXT_CONTRAST) -> Color:
	var solid := Color(color, 1.0)
	for step in range(21):
		var candidate := solid.lerp(IVORY, step / 20.0)
		if contrast(candidate, background) >= ratio:
			return Color(candidate, color.a)
	return IVORY


# The colour a god's frames, nameplates and underlines use: its own colour,
# lightened only as far as a frame needs to be seen (3:1). Bathala, or no god at
# all, falls back to the gold of the contest itself.
static func god_accent(god: God) -> Color:
	if god == null:
		return GOLD
	return readable_on_dark(god.color, NIGHT_800, ACCENT_CONTRAST)


# A god's accent when it is TEXT (a nameplate's name, "Bestowed by ...").
static func god_text(god: God) -> Color:
	if god == null:
		return GOLD
	return readable_on_dark(god.color)


# A copy of a theme stylebox with its border in `color`: the one runtime override
# the redesign allows (a god's accent on a frame). Works on the placeholder
# PixelStyleBox and on a StyleBoxTexture once real art lands (it is modulated).
static func accent_box(base: StyleBox, color: Color) -> StyleBox:
	var box: StyleBox = base.duplicate()
	if box is PixelStyleBox:
		(box as PixelStyleBox).border_color = color
	elif box is StyleBoxFlat:
		(box as StyleBoxFlat).border_color = color
	elif box is StyleBoxTexture:
		(box as StyleBoxTexture).modulate_color = color
	return box


# --- motion ------------------------------------------------------------------

static func _calm() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var settings := tree.root.get_node_or_null("Settings") if tree != null else null
	return settings != null and settings.reduce_flashing()


# Hover / focus: the control brightens a touch over 100 ms. The theme's hover
# style already changes the colours; the tween only smooths that change in.
# With reduce flashing on, the style change alone is the feedback.
static func tween_hover(control: CanvasItem, on: bool) -> void:
	if control == null or not control.is_inside_tree():
		return
	var target := HOVER_TINT if on else Color.WHITE
	if _calm():
		control.self_modulate = Color.WHITE
		return
	var tween := control.create_tween()
	tween.tween_property(control, "self_modulate", target, HOVER_TIME)


# Press: a quick 80 ms dip that settles back. The pressed style already drops
# the 2 px shadow so the button reads as pushed in.
static func tween_press(control: CanvasItem) -> void:
	if control == null or not control.is_inside_tree() or _calm():
		return
	var settle := HOVER_TINT if (control is Control and (control as Control).get_global_rect().has_point(
		control.get_global_mouse_position())) else Color.WHITE
	var tween := control.create_tween()
	tween.tween_property(control, "self_modulate", PRESS_TINT, PRESS_TIME * 0.5)
	tween.tween_property(control, "self_modulate", settle, PRESS_TIME)


# Every button the game ever adds gets the same hover / press motion, so a
# screen never has to remember to wire it (consistency: same job, same feel).
# Global calls this once at start-up.
static func install_motion(tree: SceneTree) -> void:
	tree.node_added.connect(_on_node_added)


static func _on_node_added(node: Node) -> void:
	if not node is BaseButton:
		return
	var button := node as BaseButton
	button.mouse_entered.connect(func() -> void: tween_hover(button, not button.disabled))
	button.mouse_exited.connect(func() -> void: tween_hover(button, false))
	button.focus_entered.connect(func() -> void: tween_hover(button, not button.disabled))
	button.focus_exited.connect(func() -> void: tween_hover(button, false))
	button.button_down.connect(func() -> void: tween_press(button))


# A panel opening fades in (a fade, not a slide: most panels sit in containers
# that would fight a moving position). Instant with reduce flashing on.
static func reveal(control: Control) -> void:
	if control == null or not control.is_inside_tree():
		return
	if _calm():
		control.modulate.a = 1.0
		return
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.tween_property(control, "modulate:a", 1.0, PANEL_TIME)


# A keycap's text for an input action, so a rebinding shows everywhere at once
# (recognition over recall).
static func key_text(action: StringName) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var settings := tree.root.get_node_or_null("Settings") if tree != null else null
	if settings == null:
		return str(action)
	return settings.event_label(settings.primary_event(action))
