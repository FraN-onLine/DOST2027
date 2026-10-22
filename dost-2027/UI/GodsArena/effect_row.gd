class_name EffectRow
extends PanelContainer

# One running effect in the HUD's top-right stack (god_hud.gd):
#   [icon]  NAME              4s
#           ==========----------      the bar shrinks with the seconds left
#
# A BUFF (one of our own skills running, a Pamana's window) is drawn in its own colour;
# a DEBUFF - something a rival's skill, a trap or a knock has put on us - is EMBER
# throughout (border, name, bar), so the two never read alike. The row only draws what
# it is told; the HUD removes it when the effect ends.

const PLACEHOLDER_ICON := preload("res://Assets/Placeholders/favor.png")

@onready var icon: TextureRect = $Row/Icon
@onready var name_label: Label = $Row/Body/Line/NameLabel
@onready var seconds_label: Label = $Row/Body/Line/SecondsLabel
@onready var bar: ProgressBar = $Row/Body/Bar

var key: StringName = &""
var harmful := false
var _fill: StyleBoxFlat = null


# Paint the effect described by `entry` (Arena.effect()) - `total` is the length the bar
# is measured against.
func show_effect(entry: Dictionary, total: float) -> void:
	var first := key == &""
	key = entry["key"]
	harmful = bool(entry.get("harmful", false))
	var left := maxf(0.0, float(entry["left"]))
	var tint: Color = UITokens.EMBER if harmful else UITokens.readable_on_dark(entry.get("color", UITokens.GOLD), UITokens.NIGHT_900)
	if first:
		var texture: Texture2D = entry.get("icon")
		icon.texture = texture if texture != null else PLACEHOLDER_ICON
		icon.modulate = tint if texture == null or harmful else entry.get("color", Color.WHITE)
		name_label.add_theme_color_override("font_color", tint)
		seconds_label.add_theme_color_override("font_color", tint)
		add_theme_stylebox_override("panel", UITokens.accent_box(get_theme_stylebox("panel", &"PanelHud"),
			UITokens.EMBER if harmful else UITokens.readable_on_dark(entry.get("color", UITokens.GOLD), UITokens.NIGHT_900, UITokens.ACCENT_CONTRAST)))
		_fill = StyleBoxFlat.new()
		_fill.bg_color = tint
		bar.add_theme_stylebox_override("fill", _fill)
	name_label.text = str(entry["name"])
	seconds_label.text = "%.1fs" % left if left < 10.0 else "%ds" % ceili(left)
	bar.value = clampf(left / maxf(0.001, total), 0.0, 1.0)
