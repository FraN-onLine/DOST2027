extends SceneTree

# Generator for the project theme, UI/theme/bathala_theme.tres (project.godot
# gui/theme/custom). Every colour and size comes from UITokens, so the theme
# and the few runtime tints can never disagree - change a token, re-run this.
#
# Each style is a PixelStyleBox: placeholder pixel art (flat faces, 2 px
# borders, a hard 2 px shadow, a 1 px top highlight on raised surfaces). When
# the artist's 9-slices arrive (UI/theme/ART_SLOTS.md), swap each one for a
# StyleBoxTexture here or straight in the .tres - nothing else names them.
# The small icons (check boxes, toggles, the slider grab) are drawn into the
# .tres as pixel images for the same reason.
#
# Run: godot --headless --path <project> -s res://tools/build_theme.gd

const OUT := "res://UI/theme/bathala_theme.tres"
const FONT := preload("res://Assets/fonts/Minecraftia-Regular.ttf")


var theme := Theme.new()
var spaced := FontVariation.new()  # headings and buttons: uppercase, letter-spaced


func _initialize() -> void:
	spaced.base_font = FONT
	spaced.spacing_glyph = 2
	theme.default_font = FONT
	theme.default_font_size = UITokens.BODY

	_labels()
	_buttons()
	_panels()
	_fields()
	_toggles()
	_ranges()
	_scrolling()
	_tabs()
	_popups()

	var err := ResourceSaver.save(theme, OUT)
	print("saved %s (err=%d)" % [OUT, err])
	quit(err)


# --- helpers -------------------------------------------------------------------

func _box(bg: Color, border: Color, options: Dictionary = {}) -> PixelStyleBox:
	var box := PixelStyleBox.new()
	box.bg_color = bg
	box.border_color = border
	box.border_width = options.get("border", 2)
	box.shadow_color = options.get("shadow", Color(0, 0, 0, 0))
	box.shadow_offset = options.get("shadow_offset", Vector2(0, 2))
	box.highlight_color = options.get("highlight", Color(0, 0, 0, 0))
	box.highlight_width = options.get("highlight_width", 1)
	box.face_offset = options.get("face_offset", Vector2.ZERO)
	box.grow = options.get("grow", 0)
	box.dash = options.get("dash", 0)
	var margin: Vector4 = options.get("margin", Vector4(8, 8, 8, 8))  # left, top, right, bottom
	box.content_margin_left = margin.x
	box.content_margin_top = margin.y
	box.content_margin_right = margin.z
	box.content_margin_bottom = margin.w
	return box


# The keyboard focus ring: STAR, 2 px, 2 px clear of the control.
func _focus_ring() -> PixelStyleBox:
	return _box(Color(0, 0, 0, 0), UITokens.STAR, {"grow": 4, "margin": Vector4.ZERO})


func _empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


func _image(size: Vector2i) -> Image:
	return Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)


func _texture(image: Image) -> ImageTexture:
	return ImageTexture.create_from_image(image)


func _font_colors(type: StringName, normal: Color, hover: Color, pressed: Color, disabled: Color) -> void:
	theme.set_color("font_color", type, normal)
	theme.set_color("font_focus_color", type, hover)
	theme.set_color("font_hover_color", type, hover)
	theme.set_color("font_pressed_color", type, pressed)
	theme.set_color("font_hover_pressed_color", type, pressed)
	theme.set_color("font_disabled_color", type, disabled)
	theme.set_color("icon_normal_color", type, normal)
	theme.set_color("icon_hover_color", type, hover)
	theme.set_color("icon_pressed_color", type, pressed)
	theme.set_color("icon_focus_color", type, hover)
	theme.set_color("icon_disabled_color", type, disabled)


# One button look: a face with a hard 2 px shadow that drops to 0 when pressed
# (the face moves 2 px down into it - the button reads as pushed in).
func _button_styles(type: StringName, face: Color, face_hover: Color, border: Color,
		border_hover: Color, shadow: Color, pad: Vector2 = Vector2(16, 8)) -> void:
	var margin := Vector4(pad.x, pad.y, pad.x, pad.y)
	var pressed_margin := Vector4(pad.x, pad.y + 2, pad.x, pad.y - 2)
	theme.set_stylebox("normal", type, _box(face, border, {"shadow": shadow, "margin": margin}))
	theme.set_stylebox("hover", type, _box(face_hover, border_hover, {"shadow": shadow, "margin": margin}))
	theme.set_stylebox("pressed", type, _box(face, border_hover, {"face_offset": Vector2(0, 2), "margin": pressed_margin}))
	theme.set_stylebox("hover_pressed", type, _box(face_hover, border_hover, {"face_offset": Vector2(0, 2), "margin": pressed_margin}))
	theme.set_stylebox("disabled", type, _box(UITokens.NIGHT_700, UITokens.NIGHT_600, {"margin": margin}))
	theme.set_stylebox("focus", type, _focus_ring())


# --- labels ----------------------------------------------------------------------

func _labels() -> void:
	theme.set_color("font_color", "Label", UITokens.IVORY)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))

	# Title lockup: gold, with a hard pixel shadow one font-pixel down.
	theme.set_type_variation("HeroLabel", "Label")
	theme.set_font("font", "HeroLabel", spaced)
	theme.set_font_size("font_size", "HeroLabel", UITokens.HERO)
	theme.set_color("font_color", "HeroLabel", UITokens.GOLD)
	theme.set_color("font_shadow_color", "HeroLabel", UITokens.GOLD_LIP)
	theme.set_constant("shadow_offset_x", "HeroLabel", 0)
	theme.set_constant("shadow_offset_y", "HeroLabel", 6)

	# Page titles (the Almanac's pages, Options): gold, one step down.
	theme.set_type_variation("DisplayLabel", "Label")
	theme.set_font("font", "DisplayLabel", spaced)
	theme.set_font_size("font_size", "DisplayLabel", UITokens.DISPLAY)
	theme.set_color("font_color", "DisplayLabel", UITokens.GOLD)
	theme.set_color("font_shadow_color", "DisplayLabel", UITokens.GOLD_LIP)
	theme.set_constant("shadow_offset_x", "DisplayLabel", 0)
	theme.set_constant("shadow_offset_y", "DisplayLabel", 4)

	theme.set_type_variation("HeadingLabel", "Label")
	theme.set_font("font", "HeadingLabel", spaced)
	theme.set_font_size("font_size", "HeadingLabel", UITokens.HEADING)
	theme.set_color("font_color", "HeadingLabel", UITokens.IVORY)

	theme.set_type_variation("MutedLabel", "Label")
	theme.set_color("font_color", "MutedLabel", UITokens.MUTED)

	theme.set_type_variation("CaptionLabel", "Label")
	theme.set_font_size("font_size", "CaptionLabel", UITokens.CAPTION)
	theme.set_color("font_color", "CaptionLabel", UITokens.MUTED)

	# A key, drawn as a key: recognition over recall wherever a binding is shown.
	theme.set_type_variation("KeycapLabel", "Label")
	theme.set_color("font_color", "KeycapLabel", UITokens.IVORY)
	theme.set_stylebox("normal", "KeycapLabel", _box(UITokens.NIGHT_600, UITokens.LINE,
		{"shadow": UITokens.LIP, "highlight": UITokens.HIGHLIGHT, "margin": Vector4(8, 4, 8, 4)}))

	theme.set_color("default_color", "RichTextLabel", UITokens.IVORY)
	theme.set_stylebox("normal", "RichTextLabel", _empty())


# --- buttons ---------------------------------------------------------------------

func _buttons() -> void:
	theme.set_font("font", "Button", spaced)
	theme.set_constant("h_separation", "Button", UITokens.SPACE_8)
	theme.set_constant("outline_size", "Button", 0)

	# Plain Button (and every button made in code) is a Secondary button.
	_button_styles("Button", UITokens.NIGHT_600, Color("#30406E"), UITokens.LINE, UITokens.GOLD_LO, UITokens.LIP)
	_font_colors("Button", UITokens.IVORY, UITokens.GOLD_HI, UITokens.IVORY, UITokens.FAINT)

	# Primary: the one gold thing on the screen.
	theme.set_type_variation("PrimaryButton", "Button")
	_button_styles("PrimaryButton", UITokens.GOLD, UITokens.GOLD_HI, UITokens.GOLD_LO, UITokens.GOLD_LO, UITokens.GOLD_LIP)
	_font_colors("PrimaryButton", UITokens.NIGHT_900, UITokens.NIGHT_900, UITokens.NIGHT_900, UITokens.FAINT)

	theme.set_type_variation("SecondaryButton", "Button")
	_button_styles("SecondaryButton", UITokens.NIGHT_600, Color("#30406E"), UITokens.LINE, UITokens.GOLD_LO, UITokens.LIP)
	_font_colors("SecondaryButton", UITokens.IVORY, UITokens.GOLD_HI, UITokens.IVORY, UITokens.FAINT)

	# Ghost: BACK, LEAVE, QUIT - present, but never competing with the primary.
	theme.set_type_variation("GhostButton", "Button")
	var ghost_margin := Vector4(16, 8, 16, 8)
	theme.set_stylebox("normal", "GhostButton", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), {"margin": ghost_margin}))
	theme.set_stylebox("hover", "GhostButton", _box(Color(UITokens.NIGHT_700, 0.6), UITokens.LINE, {"margin": ghost_margin}))
	theme.set_stylebox("pressed", "GhostButton", _box(Color(UITokens.NIGHT_900, 0.6), UITokens.LINE,
		{"face_offset": Vector2(0, 2), "margin": Vector4(16, 10, 16, 6)}))
	theme.set_stylebox("hover_pressed", "GhostButton", theme.get_stylebox("pressed", "GhostButton"))
	theme.set_stylebox("disabled", "GhostButton", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), {"margin": ghost_margin}))
	theme.set_stylebox("focus", "GhostButton", _focus_ring())
	_font_colors("GhostButton", UITokens.MUTED, UITokens.IVORY, UITokens.IVORY, UITokens.FAINT)

	theme.set_type_variation("SmallButton", "Button")
	_button_styles("SmallButton", UITokens.NIGHT_600, Color("#30406E"), UITokens.LINE, UITokens.GOLD_LO, UITokens.LIP, Vector2(8, 4))
	_font_colors("SmallButton", UITokens.IVORY, UITokens.GOLD_HI, UITokens.IVORY, UITokens.FAINT)

	theme.set_type_variation("DangerButton", "Button")
	_button_styles("DangerButton", Color("#3A1A22"), Color("#4E222B"), UITokens.EMBER, UITokens.EMBER, Color("#1E0D12"))
	_font_colors("DangerButton", Color("#F3A397"), UITokens.IVORY, UITokens.IVORY, UITokens.FAINT)

	# Tabs and filter chips: a toggle. Off is quiet; on is lit gold. A god's chip
	# swaps only its border for that god's accent (UITokens.accent_box).
	theme.set_type_variation("TabButton", "Button")
	var tab_margin := Vector4(12, 6, 12, 6)
	theme.set_stylebox("normal", "TabButton", _box(UITokens.NIGHT_800, UITokens.LINE, {"margin": tab_margin}))
	theme.set_stylebox("hover", "TabButton", _box(UITokens.NIGHT_700, UITokens.LINE, {"margin": tab_margin}))
	theme.set_stylebox("pressed", "TabButton", _box(UITokens.NIGHT_600, UITokens.GOLD, {"highlight": UITokens.GOLD_LO, "margin": tab_margin}))
	theme.set_stylebox("hover_pressed", "TabButton", theme.get_stylebox("pressed", "TabButton"))
	theme.set_stylebox("disabled", "TabButton", _box(UITokens.NIGHT_800, UITokens.NIGHT_700, {"margin": tab_margin}))
	theme.set_stylebox("focus", "TabButton", _focus_ring())
	_font_colors("TabButton", UITokens.MUTED, UITokens.IVORY, UITokens.GOLD, UITokens.FAINT)

	# A rebind button looks like the key it shows.
	theme.set_type_variation("KeycapButton", "Button")
	theme.set_font("font", "KeycapButton", FONT)
	_button_styles("KeycapButton", UITokens.NIGHT_600, Color("#30406E"), UITokens.LINE, UITokens.GOLD_LO, UITokens.LIP, Vector2(12, 4))
	theme.get_stylebox("normal", "KeycapButton").highlight_color = UITokens.HIGHLIGHT
	theme.get_stylebox("hover", "KeycapButton").highlight_color = UITokens.HIGHLIGHT
	_font_colors("KeycapButton", UITokens.IVORY, UITokens.GOLD_HI, UITokens.IVORY, UITokens.FAINT)


# --- panels ----------------------------------------------------------------------

func _panels() -> void:
	# PanelCard: a raised card - the default for any panel.
	var card := _box(UITokens.NIGHT_800, UITokens.LINE, {"shadow": UITokens.SHADOW, "highlight": UITokens.HIGHLIGHT,
		"margin": Vector4(UITokens.SPACE_16, UITokens.SPACE_16, UITokens.SPACE_16, UITokens.SPACE_16)})
	theme.set_stylebox("panel", "PanelContainer", card)
	theme.set_stylebox("panel", "Panel", card)
	theme.set_type_variation("PanelCard", "PanelContainer")
	theme.set_stylebox("panel", "PanelCard", card)

	# PanelInset: a sunken list area (the Almanac's book page, the host list).
	theme.set_type_variation("PanelInset", "PanelContainer")
	theme.set_stylebox("panel", "PanelInset", _box(UITokens.NIGHT_900, UITokens.NIGHT_700,
		{"highlight": Color("#070A15"), "highlight_width": 2, "margin": Vector4(8, 8, 8, 8)}))

	# PanelHud: in-game, translucent so the field still reads through it.
	theme.set_type_variation("PanelHud", "PanelContainer")
	theme.set_stylebox("panel", "PanelHud", _box(Color(UITokens.NIGHT_900, 0.82), Color(UITokens.LINE, 0.9),
		{"margin": Vector4(8, 8, 8, 8)}))

	# Nameplate: a small plate under a name or over a dialogue box; its border
	# takes the speaker's / owner's accent at runtime.
	theme.set_type_variation("Nameplate", "PanelContainer")
	theme.set_stylebox("panel", "Nameplate", _box(UITokens.NIGHT_700, UITokens.GOLD, {"shadow": UITokens.SHADOW,
		"margin": Vector4(8, 4, 8, 4)}))

	# PanelEmpty: a dashed outline for a place still waiting to be filled.
	theme.set_type_variation("PanelEmpty", "PanelContainer")
	theme.set_stylebox("panel", "PanelEmpty", _box(Color(UITokens.NIGHT_900, 0.4), UITokens.LINE,
		{"dash": 4, "margin": Vector4(8, 8, 8, 8)}))

	# The Almanac's cards (and the God's Due packets that copy them). Their top
	# band and frame take the god's accent at runtime.
	theme.set_type_variation("ShrineTile", "PanelContainer")
	theme.set_stylebox("panel", "ShrineTile", _box(UITokens.NIGHT_700, UITokens.LINE, {"shadow": UITokens.SHADOW,
		"highlight": UITokens.HIGHLIGHT, "margin": Vector4(4, 8, 4, 4)}))
	theme.set_type_variation("SeedPacket", "PanelContainer")
	theme.set_stylebox("panel", "SeedPacket", _box(Color("#E9DDBC"), Color("#8C7A55"), {"shadow": UITokens.SHADOW,
		"highlight": UITokens.GOLD, "highlight_width": 10, "margin": Vector4(4, 14, 4, 4)}))

	var line := StyleBoxLine.new()
	line.color = UITokens.LINE
	line.thickness = 2
	theme.set_stylebox("separator", "HSeparator", line)
	theme.set_constant("separation", "HSeparator", UITokens.SPACE_8)
	var vline := StyleBoxLine.new()
	vline.color = UITokens.LINE
	vline.thickness = 2
	vline.vertical = true
	theme.set_stylebox("separator", "VSeparator", vline)


# --- text fields and dropdowns ----------------------------------------------------

func _fields() -> void:
	var margin := Vector4(12, 8, 12, 8)
	theme.set_stylebox("normal", "LineEdit", _box(UITokens.NIGHT_900, UITokens.LINE, {"margin": margin}))
	theme.set_stylebox("focus", "LineEdit", _box(Color(0, 0, 0, 0), UITokens.STAR, {"margin": margin}))
	theme.set_stylebox("read_only", "LineEdit", _box(UITokens.NIGHT_800, UITokens.NIGHT_700, {"margin": margin}))
	theme.set_color("font_color", "LineEdit", UITokens.IVORY)
	theme.set_color("font_placeholder_color", "LineEdit", UITokens.FAINT)
	theme.set_color("font_uneditable_color", "LineEdit", UITokens.FAINT)
	theme.set_color("caret_color", "LineEdit", UITokens.GOLD)
	theme.set_color("selection_color", "LineEdit", Color(UITokens.STAR, 0.35))
	theme.set_color("font_selected_color", "LineEdit", UITokens.IVORY)
	theme.set_constant("caret_width", "LineEdit", 2)

	# OptionButton: a Secondary button with a pixel arrow.
	_button_styles("OptionButton", UITokens.NIGHT_600, Color("#30406E"), UITokens.LINE, UITokens.GOLD_LO, UITokens.LIP, Vector2(12, 8))
	_font_colors("OptionButton", UITokens.IVORY, UITokens.GOLD_HI, UITokens.IVORY, UITokens.FAINT)
	theme.set_font("font", "OptionButton", FONT)
	theme.set_icon("arrow", "OptionButton", _arrow_icon(UITokens.IVORY))
	theme.set_constant("arrow_margin", "OptionButton", UITokens.SPACE_8)


# --- check boxes and toggles ---------------------------------------------------------

func _toggles() -> void:
	for type in ["CheckBox", "CheckButton"]:
		var margin := Vector4(4, 4, 4, 4)
		for state in ["normal", "pressed", "hover", "hover_pressed", "disabled"]:
			theme.set_stylebox(state, type, _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), {"margin": margin}))
		theme.set_stylebox("hover", type, _box(Color(UITokens.NIGHT_700, 0.6), Color(0, 0, 0, 0), {"margin": margin}))
		theme.set_stylebox("hover_pressed", type, theme.get_stylebox("hover", type))
		theme.set_stylebox("focus", type, _focus_ring())
		_font_colors(type, UITokens.IVORY, UITokens.GOLD_HI, UITokens.IVORY, UITokens.FAINT)
		theme.set_constant("h_separation", type, UITokens.SPACE_8)
	theme.set_icon("unchecked", "CheckBox", _check_icon(UITokens.LINE, Color(0, 0, 0, 0)))
	theme.set_icon("checked", "CheckBox", _check_icon(UITokens.GOLD_LO, UITokens.GOLD))
	theme.set_icon("unchecked_disabled", "CheckBox", _check_icon(UITokens.NIGHT_600, Color(0, 0, 0, 0)))
	theme.set_icon("checked_disabled", "CheckBox", _check_icon(UITokens.NIGHT_600, UITokens.FAINT))
	# A radio choice is a diamond - the ornament's own stud.
	theme.set_icon("radio_unchecked", "CheckBox", _diamond_icon(UITokens.LINE, Color(0, 0, 0, 0)))
	theme.set_icon("radio_checked", "CheckBox", _diamond_icon(UITokens.GOLD_LO, UITokens.GOLD))
	theme.set_icon("radio_unchecked_disabled", "CheckBox", _diamond_icon(UITokens.NIGHT_600, Color(0, 0, 0, 0)))
	theme.set_icon("radio_checked_disabled", "CheckBox", _diamond_icon(UITokens.NIGHT_600, UITokens.FAINT))
	theme.set_icon("unchecked", "CheckButton", _toggle_icon(false, false))
	theme.set_icon("checked", "CheckButton", _toggle_icon(true, false))
	theme.set_icon("unchecked_disabled", "CheckButton", _toggle_icon(false, true))
	theme.set_icon("checked_disabled", "CheckButton", _toggle_icon(true, true))
	theme.set_icon("unchecked_mirrored", "CheckButton", _toggle_icon(false, false))
	theme.set_icon("checked_mirrored", "CheckButton", _toggle_icon(true, false))
	theme.set_icon("unchecked_disabled_mirrored", "CheckButton", _toggle_icon(false, true))
	theme.set_icon("checked_disabled_mirrored", "CheckButton", _toggle_icon(true, true))


# --- sliders and bars ------------------------------------------------------------------

func _ranges() -> void:
	theme.set_stylebox("slider", "HSlider", _box(UITokens.NIGHT_900, UITokens.LINE, {"margin": Vector4(0, 4, 0, 4)}))
	theme.set_stylebox("grabber_area", "HSlider", _box(UITokens.GOLD_LO, UITokens.LINE, {"margin": Vector4(0, 4, 0, 4)}))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(UITokens.GOLD, UITokens.LINE, {"margin": Vector4(0, 4, 0, 4)}))
	theme.set_icon("grabber", "HSlider", _grabber_icon(UITokens.GOLD))
	theme.set_icon("grabber_highlight", "HSlider", _grabber_icon(UITokens.GOLD_HI))
	theme.set_icon("grabber_disabled", "HSlider", _grabber_icon(UITokens.FAINT))
	theme.set_constant("center_grabber", "HSlider", 1)

	theme.set_stylebox("background", "ProgressBar", _box(UITokens.NIGHT_900, UITokens.LINE, {"margin": Vector4(2, 2, 2, 2)}))
	theme.set_stylebox("fill", "ProgressBar", _box(UITokens.GOLD, Color(0, 0, 0, 0), {"border": 0,
		"highlight": UITokens.GOLD_HI, "highlight_width": 2, "margin": Vector4.ZERO}))
	theme.set_color("font_color", "ProgressBar", UITokens.IVORY)
	theme.set_color("font_outline_color", "ProgressBar", UITokens.NIGHT_900)
	theme.set_font_size("font_size", "ProgressBar", UITokens.CAPTION)


func _scrolling() -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, _box(UITokens.NIGHT_900, Color(0, 0, 0, 0), {"border": 0, "margin": Vector4(4, 4, 4, 4)}))
		theme.set_stylebox("scroll_focus", type, theme.get_stylebox("scroll", type))
		theme.set_stylebox("grabber", type, _box(UITokens.LINE, Color(0, 0, 0, 0), {"border": 0, "margin": Vector4(4, 4, 4, 4)}))
		theme.set_stylebox("grabber_highlight", type, _box(UITokens.GOLD_LO, Color(0, 0, 0, 0), {"border": 0, "margin": Vector4(4, 4, 4, 4)}))
		theme.set_stylebox("grabber_pressed", type, _box(UITokens.GOLD, Color(0, 0, 0, 0), {"border": 0, "margin": Vector4(4, 4, 4, 4)}))
	theme.set_stylebox("panel", "ScrollContainer", _empty())


func _tabs() -> void:
	var margin := Vector4(16, 8, 16, 8)
	for type in ["TabContainer", "TabBar"]:
		theme.set_stylebox("tab_selected", type, _box(UITokens.NIGHT_800, UITokens.LINE, {"highlight": UITokens.GOLD, "highlight_width": 2, "margin": margin}))
		theme.set_stylebox("tab_unselected", type, _box(UITokens.NIGHT_900, UITokens.NIGHT_700, {"margin": margin}))
		theme.set_stylebox("tab_hovered", type, _box(UITokens.NIGHT_700, UITokens.LINE, {"margin": margin}))
		theme.set_stylebox("tab_disabled", type, _box(UITokens.NIGHT_900, UITokens.NIGHT_700, {"margin": margin}))
		theme.set_stylebox("tab_focus", type, _focus_ring())
		theme.set_color("font_selected_color", type, UITokens.GOLD)
		theme.set_color("font_unselected_color", type, UITokens.MUTED)
		theme.set_color("font_hovered_color", type, UITokens.IVORY)
		theme.set_color("font_disabled_color", type, UITokens.FAINT)
		theme.set_font("font", type, spaced)
	theme.set_stylebox("panel", "TabContainer", _box(UITokens.NIGHT_800, UITokens.LINE, {"margin": Vector4(16, 16, 16, 16)}))
	theme.set_stylebox("tabbar_background", "TabContainer", _empty())
	theme.set_constant("side_margin", "TabContainer", 0)


# --- tooltips, menus, dialogs -------------------------------------------------------------

func _popups() -> void:
	theme.set_stylebox("panel", "TooltipPanel", _box(UITokens.NIGHT_900, UITokens.GOLD_LO, {"margin": Vector4(8, 4, 8, 4)}))
	theme.set_color("font_color", "TooltipLabel", UITokens.IVORY)
	theme.set_font_size("font_size", "TooltipLabel", UITokens.BODY)

	theme.set_stylebox("panel", "PopupMenu", _box(UITokens.NIGHT_800, UITokens.LINE, {"margin": Vector4(4, 4, 4, 4)}))
	theme.set_stylebox("hover", "PopupMenu", _box(UITokens.NIGHT_600, Color(0, 0, 0, 0), {"border": 0, "margin": Vector4(8, 4, 8, 4)}))
	theme.set_color("font_color", "PopupMenu", UITokens.IVORY)
	theme.set_color("font_hover_color", "PopupMenu", UITokens.GOLD_HI)
	theme.set_color("font_disabled_color", "PopupMenu", UITokens.FAINT)
	theme.set_constant("v_separation", "PopupMenu", UITokens.SPACE_8)
	theme.set_icon("radio_checked", "PopupMenu", _diamond_icon(UITokens.GOLD_LO, UITokens.GOLD))
	theme.set_icon("radio_unchecked", "PopupMenu", _diamond_icon(UITokens.LINE, Color(0, 0, 0, 0)))
	theme.set_icon("checked", "PopupMenu", _check_icon(UITokens.GOLD_LO, UITokens.GOLD))
	theme.set_icon("unchecked", "PopupMenu", _check_icon(UITokens.LINE, Color(0, 0, 0, 0)))

	# ConfirmationDialog / AcceptDialog (embedded windows).
	theme.set_stylebox("embedded_border", "Window", _box(UITokens.NIGHT_800, UITokens.GOLD_LO, {"shadow": UITokens.SHADOW,
		"margin": Vector4(8, 32, 8, 8)}))
	theme.set_stylebox("embedded_unfocused_border", "Window", theme.get_stylebox("embedded_border", "Window"))
	theme.set_color("title_color", "Window", UITokens.GOLD)
	theme.set_font("title_font", "Window", spaced)
	theme.set_font_size("title_font_size", "Window", UITokens.BODY)
	theme.set_constant("title_height", "Window", 32)
	theme.set_stylebox("panel", "AcceptDialog", _box(UITokens.NIGHT_800, Color(0, 0, 0, 0), {"border": 0,
		"margin": Vector4(16, 16, 16, 16)}))
	theme.set_constant("buttons_separation", "AcceptDialog", UITokens.SPACE_16)


# --- pixel icons ----------------------------------------------------------------------------

# 16x16 square box; `pip` fills an 8x8 square inside when checked.
func _check_icon(border: Color, pip: Color) -> ImageTexture:
	var image := _image(Vector2i(16, 16))
	image.fill_rect(Rect2i(0, 0, 16, 16), border)
	image.fill_rect(Rect2i(2, 2, 12, 12), UITokens.NIGHT_900)
	if pip.a > 0.0:
		image.fill_rect(Rect2i(4, 4, 8, 8), pip)
	return _texture(image)


# 16x16 diamond outline; `pip` fills a smaller diamond when chosen.
func _diamond_icon(border: Color, pip: Color) -> ImageTexture:
	var image := _image(Vector2i(16, 16))
	for y in 16:
		for x in 16:
			var d := absf(x - 7.5) + absf(y - 7.5)
			if d <= 7.5 and d > 5.5:
				image.set_pixel(x, y, border)
			elif d <= 5.5:
				image.set_pixel(x, y, pip if d <= 3.5 and pip.a > 0.0 else UITokens.NIGHT_900)
	return _texture(image)


# 32x16 toggle: the knob sits left (off) or right on a gold track (on).
func _toggle_icon(on: bool, disabled: bool) -> ImageTexture:
	var image := _image(Vector2i(32, 16))
	var border := UITokens.NIGHT_600 if disabled else (UITokens.GOLD_LO if on else UITokens.LINE)
	image.fill_rect(Rect2i(0, 0, 32, 16), border)
	image.fill_rect(Rect2i(2, 2, 28, 12), (UITokens.NIGHT_700 if disabled else Color("#5C4718")) if on else UITokens.NIGHT_900)
	var knob := UITokens.FAINT if disabled else (UITokens.GOLD if on else UITokens.MUTED)
	image.fill_rect(Rect2i(18 if on else 4, 4, 10, 8), knob)
	return _texture(image)


# 12x20 slider grab: a gold block with a dark rim and a lit top.
func _grabber_icon(face: Color) -> ImageTexture:
	var image := _image(Vector2i(12, 20))
	image.fill_rect(Rect2i(0, 0, 12, 20), UITokens.NIGHT_900)
	image.fill_rect(Rect2i(2, 2, 8, 16), face)
	image.fill_rect(Rect2i(2, 2, 8, 2), face.lightened(0.3))
	return _texture(image)


# 12x6 downward chevron for dropdowns.
func _arrow_icon(color: Color) -> ImageTexture:
	var image := _image(Vector2i(12, 6))
	for row in 3:
		image.fill_rect(Rect2i(row * 2, row * 2, 12 - row * 4, 2), color)
	return _texture(image)
