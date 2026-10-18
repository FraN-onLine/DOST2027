class_name UICards
extends RefCounted

# The game's two collectible-card looks, built in one place so the Almanac and
# the God's Due menu show a favor the same way (recognition: the packet a player
# picks mid-trial is the packet they browsed in the Almanac).
#
#   shrine_tile(god)    a god: icon, name, an accent-coloured base strip
#   seed_packet(favor)  a favor, after PvZ's seed packets: paper face with the
#                       god's accent as its top band, the icon in the middle,
#                       the name under it and a corner badge (E, Q, PASSIVE,
#                       ONCE, END)
#
# A card is a focusable CardButton (draws nothing) holding a SelectionRing and
# the card Body. The body rests 2 px low; hovering lifts it 1 px and selecting
# lifts it the full 2 px with a gold ring - the card is "picked up".

const PLACEHOLDER_ICON := preload("res://icon.svg")
const LIFT := 2.0
const LIFT_TIME := 0.1


static func shrine_tile(god: God, size: Vector2 = Vector2(96, 112)) -> Button:
	var card := _shell(size, &"ShrineTile")
	card.tooltip_text = "%s, %s" % [god.display_name, god.epithet]
	var body: PanelContainer = card.get_node("Body")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UITokens.SPACE_4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_icon(god.icon, Vector2(size.x - 32, size.x - 32), Color.WHITE))
	var title := Label.new()
	title.text = god.display_name
	title.theme_type_variation = &"CaptionLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(title)
	var strip := ColorRect.new()
	strip.name = "Strip"
	strip.color = UITokens.god_accent(god)
	strip.custom_minimum_size.y = 6
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(strip)
	body.add_child(box)
	return card


# `with_name` off draws a mini packet (icon and band only) - the tooltip names it.
static func seed_packet(favor: GodFavor, size: Vector2 = Vector2(80, 100), with_name: bool = true) -> Button:
	var card := _shell(size, &"SeedPacket")
	var god := Gods.by_id(favor.god_id)
	card.tooltip_text = favor.display_name
	var body: PanelContainer = card.get_node("Body")
	body.add_theme_stylebox_override("panel",
		UITokens.accent_box(body.get_theme_stylebox("panel", &"SeedPacket"), UITokens.god_accent(god), true))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_side := floorf(minf(size.x - 24, size.y * 0.45))
	box.add_child(_icon(favor.icon if favor.icon != null else PLACEHOLDER_ICON, Vector2(icon_side, icon_side), favor.color))
	if with_name:
		var title := Label.new()
		title.text = favor.display_name
		title.theme_type_variation = &"PacketLabel"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size.x = size.x - 8
		box.add_child(title)
	body.add_child(box)

	# The corner badge, pinned to the top-right corner (a mini packet is too
	# small for one; its tooltip says it all).
	if with_name:
		var corner := HBoxContainer.new()  # sizes the badge to its text once the theme applies
		corner.name = "Badge"
		corner.alignment = BoxContainer.ALIGNMENT_END
		corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		corner.position = Vector2(0, LIFT)
		corner.size = Vector2(size.x, 0)
		var badge := Label.new()
		badge.text = badge_text(favor)
		badge.theme_type_variation = &"BadgeLabel"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		corner.add_child(badge)
		card.add_child(corner)
	return card


# The packet's corner: the key it binds to, or what kind of boon it is.
static func badge_text(favor: GodFavor) -> String:
	if favor.is_skill():
		return favor.slot_name()
	match favor.kind:
		GodFavor.Kind.INSTANT:
			return "ONCE"
		GodFavor.Kind.END_OF_TRIAL:
			return "END"
		GodFavor.Kind.ACTIVE:
			return "ACTIVE"
	return "PASSIVE"


static func set_selected(card: Control, on: bool) -> void:
	card.set_meta("selected", on)
	card.get_node("Ring").visible = on
	_lift(card)


static func _shell(size: Vector2, body_type: StringName) -> Button:
	var card := Button.new()
	card.theme_type_variation = &"CardButton"
	card.custom_minimum_size = size + Vector2(0, LIFT)
	card.focus_mode = Control.FOCUS_ALL
	card.set_meta("selected", false)
	card.set_meta("hovered", false)

	var ring := Panel.new()
	ring.name = "Ring"
	ring.theme_type_variation = &"SelectionRing"
	ring.visible = false
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.size = size
	card.add_child(ring)

	var body := PanelContainer.new()
	body.name = "Body"
	body.theme_type_variation = body_type
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.position = Vector2(0, LIFT)
	body.size = size
	body.custom_minimum_size = size
	card.add_child(body)
	ring.position = body.position

	card.mouse_entered.connect(func() -> void:
		card.set_meta("hovered", true)
		_lift(card))
	card.mouse_exited.connect(func() -> void:
		card.set_meta("hovered", false)
		_lift(card))
	return card


# Rest 2 px low, hover 1 px up, selected 2 px up (80-150 ms, Motion with restraint).
static func _lift(card: Control) -> void:
	var rise := LIFT if card.get_meta("selected", false) else (LIFT * 0.5 if card.get_meta("hovered", false) else 0.0)
	var target := LIFT - rise
	for part in card.get_children():  # Ring, Body and (packets) Badge move as one
		if not card.is_inside_tree():
			part.position.y = target
			continue
		var tween := card.create_tween()
		tween.tween_property(part, "position:y", target, LIFT_TIME)


static func _icon(texture: Texture2D, side: Vector2, tint: Color) -> TextureRect:
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = texture
	icon.custom_minimum_size = side
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate = tint
	return icon
