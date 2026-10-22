class_name SkillCard
extends PanelContainer

# What one E / Q skill is, on a card:
#   [E] [icon]  NAME
#               the favor's one-line description
#               COOLDOWN 12s   LASTS 5s
#               REPLACES <the skill it pushed out of the slot>
#
# One card, two uses (god_hud.gd decides which):
#   * the POPUP shown for a few seconds when a skill is gained - it takes the mouse
#     (a click on it dismisses it) and says how else to dismiss it;
#   * the INFO tooltip shown while the mouse is over a skill bar, or the skill_info
#     key (Tab) is held - it takes no mouse at all.
# Neither pauses the game or blocks input: the card sits at the side of the field.
#
# The key is read from the player's bindings (Settings.event_label, through
# UITokens.key_text), so a rebinding shows here too; the border takes the favor's
# colour, like the skill bar's.

signal dismissed

const PLACEHOLDER_ICON := preload("res://Assets/Placeholders/favor.png")

@onready var key_label: Label = $Row/Key
@onready var icon: TextureRect = $Row/Icon
@onready var name_label: Label = $Row/Body/NameLabel
@onready var desc_label: Label = $Row/Body/DescLabel
@onready var cooldown_label: Label = $Row/Body/CooldownLabel
@onready var replaces_label: Label = $Row/Body/ReplacesLabel
@onready var hint_label: Label = $Row/Body/HintLabel

var slot := GodFavor.Slot.E
var favor: GodFavor = null


# Fill the card. `cooldown` is the skill's cooldown for this mortal right now (the
# match knows the multipliers); `replaced` is the skill that was in the slot, if this
# one took its place; `popup` makes the card clickable and adds the dismiss hint.
func show_skill(skill_slot: int, skill: GodFavor, cooldown: float, replaced: GodFavor = null, popup := false) -> void:
	slot = skill_slot
	favor = skill
	var action := &"skill_e" if slot == GodFavor.Slot.E else &"skill_q"
	key_label.text = UITokens.key_text(action)
	icon.texture = skill.icon if skill.icon != null else PLACEHOLDER_ICON
	icon.modulate = skill.color  # the placeholder icon is tinted until real art lands
	var tint := UITokens.readable_on_dark(skill.color, UITokens.NIGHT_900)
	name_label.text = skill.display_name.to_upper()
	name_label.add_theme_color_override("font_color", tint)
	desc_label.text = skill.description
	var timing := "COOLDOWN %ds" % ceili(cooldown) if cooldown > 0.0 else "NO COOLDOWN"
	if skill.duration > 0.0:
		timing += "     LASTS %ds" % ceili(skill.duration)
	cooldown_label.text = timing
	replaces_label.visible = replaced != null
	if replaced != null:
		replaces_label.text = "REPLACES %s" % replaced.display_name.to_upper()
		replaces_label.add_theme_color_override("font_color", UITokens.readable_on_dark(UITokens.GOLD, UITokens.NIGHT_900))
	hint_label.visible = popup
	hint_label.text = "CLICK OR PRESS %s TO CLOSE" % key_label.text.to_upper()
	hint_label.add_theme_color_override("font_color", UITokens.FAINT)
	add_theme_stylebox_override("panel", UITokens.accent_box(get_theme_stylebox("panel", &"PanelHud"),
		UITokens.readable_on_dark(skill.color, UITokens.NIGHT_900, UITokens.ACCENT_CONTRAST)))
	mouse_filter = Control.MOUSE_FILTER_STOP if popup else Control.MOUSE_FILTER_IGNORE


func _gui_input(event: InputEvent) -> void:
	if mouse_filter != Control.MOUSE_FILTER_STOP or not (event is InputEventMouseButton):
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		dismissed.emit()
