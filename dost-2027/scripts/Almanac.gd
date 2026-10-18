extends Control

# The Almanac, after the Plants vs. Zombies one: an index of two big framed
# choices - MGA DIYOS (the gods) and MGA PABOR (the favors) - each opening a page
# laid out the same way:
#
#   left ~45%   a grid of cards on an inset "book page" (shrine tiles for gods,
#               seed packets for favors), scrolling inside its own panel
#   right ~55%  the selected card in full: a framed portrait on a backdrop in
#               the god's accent, the name, a subtitle, stat chips, the
#               description and a muted flavour line
#
# Progressive disclosure is the whole model: the grid is the summary, a card's
# details appear only once it is selected (the first card is, on opening).
#
# It reads the gods themselves (Gods.all() -> each god's favors), so a god or a
# favor is listed the moment it exists in a .tres - nobody has to remember to
# add it to a page. Nothing here is authored by hand.
#
# Keys: arrows move through the grid and a card is selected as it is reached
# (Enter / click select too); Tab and Shift+Tab cycle the favor filter chips;
# Esc goes back (page -> index -> main menu).

const MENU_SCENE := "res://scenes/MainMenu.tscn"
const GODS := "gods"
const FAVORS := "favors"
const TILE_SIZE := Vector2(96, 112)
const PACKET_SIZE := Vector2(80, 100)
const MINI_PACKET := Vector2(48, 60)
const FAN_ICON := Vector2(56, 56)
const BACKDROP_TINT := 0.22  # how much of the god's accent the portrait backdrop takes

@onready var index_page: Control = $Index
@onready var gods_choice: Button = $Index/Center/VBox/Choices/GodsChoice
@onready var favors_choice: Button = $Index/Center/VBox/Choices/FavorsChoice
@onready var back_button: Button = $Index/BackButton
@onready var page: Control = $Page
@onready var page_title: Label = $Page/VBox/PageTitle
@onready var filters: HFlowContainer = $Page/VBox/Filters
@onready var book_page: PanelContainer = $Page/VBox/Body/BookPage
@onready var card_scroll: ScrollContainer = $Page/VBox/Body/BookPage/CardScroll
@onready var card_grid: GridContainer = $Page/VBox/Body/BookPage/CardScroll/Margin/CardGrid
@onready var detail_scroll: ScrollContainer = $Page/VBox/Body/Detail/DetailScroll
@onready var portrait_frame: PanelContainer = $Page/VBox/Body/Detail/DetailScroll/VBox/Top/PortraitFrame
@onready var portrait: TextureRect = $Page/VBox/Body/Detail/DetailScroll/VBox/Top/PortraitFrame/Portrait
@onready var ornament: OrnamentFrame = $Page/VBox/Body/Detail/DetailScroll/VBox/Top/PortraitFrame/Ornament
@onready var detail_name: Label = $Page/VBox/Body/Detail/DetailScroll/VBox/Top/Info/Name
@onready var detail_subtitle: Label = $Page/VBox/Body/Detail/DetailScroll/VBox/Top/Info/Subtitle
@onready var detail_chips: HFlowContainer = $Page/VBox/Body/Detail/DetailScroll/VBox/Top/Info/Chips
@onready var detail_description: Label = $Page/VBox/Body/Detail/DetailScroll/VBox/Description
@onready var detail_flavor: Label = $Page/VBox/Body/Detail/DetailScroll/VBox/Flavor
@onready var detail_condition: Label = $Page/VBox/Body/Detail/DetailScroll/VBox/Condition
@onready var detail_packets_label: Label = $Page/VBox/Body/Detail/DetailScroll/VBox/PacketsLabel
@onready var detail_packets: HFlowContainer = $Page/VBox/Body/Detail/DetailScroll/VBox/Packets
@onready var page_back: Button = $Page/VBox/Footer/BackButton
@onready var hint: Label = $Page/VBox/Footer/Hint

var page_kind := ""            # "" on the index, GODS or FAVORS on a page
var selected_id: StringName = &""
var filter_god: StringName = &""  # favors page: "" = ALL
var _filter_chips: Array[Button] = []


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	page_back.pressed.connect(_show_index)
	gods_choice.pressed.connect(_open_page.bind(GODS))
	favors_choice.pressed.connect(_open_page.bind(FAVORS))
	book_page.resized.connect(_fit_columns)
	_build_index()
	_show_index()


# --- index -------------------------------------------------------------------

func _build_index() -> void:
	var gods := Gods.all()
	var favor_count := 0
	var fan_favors: Array[GodFavor] = []
	for god in gods:
		favor_count += god.favors.size()
		if not god.favors.is_empty():
			fan_favors.append(god.favors[0])
	var god_icons: Array[Control] = []
	for god in gods:
		var icon := TextureRect.new()
		icon.texture = god.icon
		icon.custom_minimum_size = FAN_ICON
		icon.size = FAN_ICON
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		god_icons.append(icon)
	var packets: Array[Control] = []
	for favor in fan_favors:
		var packet := UICards.seed_packet(favor, MINI_PACKET, false)
		packet.focus_mode = Control.FOCUS_NONE
		packet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		packets.append(packet)
	_dress_choice(gods_choice, "MGA DIYOS", "The Gods", "%d gods" % gods.size(), god_icons, 36.0)
	_dress_choice(favors_choice, "MGA PABOR", "The Favors", "%d favors" % favor_count, packets, 30.0)


# A choice is a big button holding an ornament frame, a fan of pictures and
# its three lines of text. The children ignore the mouse; the button takes it.
func _dress_choice(choice: Button, title: String, subtitle: String, caption: String,
		fan_items: Array[Control], step: float) -> void:
	var frame := OrnamentFrame.new()
	frame.color = UITokens.GOLD_LO
	frame.inset = 8
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	choice.add_child(frame)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_top = UITokens.SPACE_32
	box.offset_bottom = -UITokens.SPACE_24
	box.add_theme_constant_override("separation", UITokens.SPACE_8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choice.add_child(box)

	var fan := Control.new()
	fan.custom_minimum_size = Vector2(0, 112)
	fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(fan)
	# A fan without rotation (rotating pixel art breaks its grid): the pictures
	# overlap and arc, the middle one highest.
	var count := fan_items.size()
	var centre := (count - 1) * 0.5
	for index in count:
		var item: Control = fan_items[index]
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fan.add_child(item)
		var item_size := item.custom_minimum_size
		var x := (choice.custom_minimum_size.x - item_size.x) * 0.5 + (index - centre) * step
		var y := 16.0 + absf(index - centre) * 6.0
		item.size = item_size
		item.position = Vector2(roundf(x), roundf(y))
		item.z_index = count - int(absf(index - centre) * 2)

	for line in [[title, &"HeadingLabel"], [subtitle, &"MutedLabel"], [caption, &"CaptionLabel"]]:
		var label := Label.new()
		label.text = line[0]
		label.theme_type_variation = line[1]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(label)


func _show_index() -> void:
	page_kind = ""
	page.visible = false
	index_page.visible = true
	UITokens.reveal(index_page)
	gods_choice.grab_focus()


# --- pages -------------------------------------------------------------------

# Open the gods or favors page; `select_id` picks the card to start on (the
# first card when empty).
func _open_page(kind: String, select_id: StringName = &"") -> void:
	page_kind = kind
	index_page.visible = false
	page.visible = true
	UITokens.reveal(page)
	page_title.text = "MGA DIYOS  -  THE GODS" if kind == GODS else "MGA PABOR  -  THE FAVORS"
	filters.visible = kind == FAVORS
	hint.text = "Arrows: move   Enter: select   Esc: back"
	if kind == FAVORS:
		hint.text = "Tab: next filter   " + hint.text
		if select_id != &"":
			filter_god = &""  # a jump from a god's packet lands on ALL, so the packet is there
		_build_filters()
	_build_cards(select_id)


func _build_filters() -> void:
	_clear(filters)
	_filter_chips.clear()
	var group := ButtonGroup.new()
	var ids: Array[StringName] = [&""]
	for god in Gods.all():
		if not god.favors.is_empty():
			ids.append(god.id)
	for id in ids:
		var chip := Button.new()
		chip.theme_type_variation = &"TabButton"
		chip.toggle_mode = true
		chip.button_group = group
		chip.focus_mode = Control.FOCUS_NONE  # Tab cycles the chips; arrows stay in the grid
		chip.custom_minimum_size.y = UITokens.BUTTON_SMALL.y
		chip.set_meta("god_id", id)
		if id == &"":
			chip.text = "ALL"
		else:
			var god := Gods.by_id(id)
			chip.text = god.display_name
			var accent := UITokens.god_accent(god)
			for state in ["normal", "hover", "pressed", "hover_pressed"]:
				chip.add_theme_stylebox_override(state, UITokens.accent_box(chip.get_theme_stylebox(state, &"TabButton"), accent))
			chip.add_theme_color_override("font_color", UITokens.god_text(god))
		chip.button_pressed = id == filter_god
		chip.pressed.connect(_set_filter.bind(id))
		filters.add_child(chip)
		_filter_chips.append(chip)


func _set_filter(god_id: StringName) -> void:
	filter_god = god_id
	for chip in _filter_chips:
		chip.set_pressed_no_signal(StringName(str(chip.get_meta("god_id"))) == god_id)
	_build_cards(selected_id)


func _build_cards(select_id: StringName) -> void:
	_clear(card_grid)
	if page_kind == GODS:
		for god in Gods.all():
			var tile := UICards.shrine_tile(god, TILE_SIZE)
			tile.set_meta("id", god.id)
			card_grid.add_child(tile)
	else:
		for god in Gods.all():
			if filter_god != &"" and god.id != filter_god:
				continue
			for favor in god.favors:
				var packet := UICards.seed_packet(favor, PACKET_SIZE)
				packet.set_meta("id", favor.id)
				card_grid.add_child(packet)
	for card in card_grid.get_children():
		var id := StringName(str(card.get_meta("id")))
		card.pressed.connect(select.bind(id))
		card.focus_entered.connect(select.bind(id))
	_fit_columns()
	var first := select_id
	if first == &"" or _card(first) == null:
		first = StringName(str(card_grid.get_child(0).get_meta("id"))) if card_grid.get_child_count() > 0 else &""
	if first != &"":
		select(first)
		_card(first).grab_focus()
	if select_id == &"":
		card_scroll.set_deferred("scroll_vertical", 0)  # a fresh page starts at its top row


# As many columns as the book page holds (it narrows at large UI scales).
func _fit_columns() -> void:
	var card_width := (TILE_SIZE.x if page_kind == GODS else PACKET_SIZE.x)
	var gap := card_grid.get_theme_constant("h_separation")
	var room := book_page.size.x - 32.0
	card_grid.columns = maxi(1, int((room + gap) / (card_width + gap)))


func _card(id: StringName) -> Control:
	for card in card_grid.get_children():
		if StringName(str(card.get_meta("id"))) == id:
			return card
	return null


func select(id: StringName) -> void:
	selected_id = id
	for card in card_grid.get_children():
		UICards.set_selected(card, StringName(str(card.get_meta("id"))) == id)
	if page_kind == GODS:
		_show_god(Gods.by_id(id))
	else:
		_show_favor(Gods.favor_by_id(id))
	detail_scroll.scroll_vertical = 0


# --- the detail display ----------------------------------------------------------

func _show_god(god: God) -> void:
	_frame_portrait(god.portrait if god.portrait != null else god.icon, god, Color.WHITE)
	detail_name.text = god.display_name
	detail_subtitle.text = god.epithet
	detail_subtitle.add_theme_color_override("font_color", UITokens.god_text(god))
	_set_chips([god.game_name, "%d favor%s" % [god.favors.size(), "" if god.favors.size() == 1 else "s"]])
	detail_description.text = god.game_blurb
	detail_flavor.text = god.intro_lines[0] if not god.intro_lines.is_empty() else ""
	detail_flavor.visible = not detail_flavor.text.is_empty()
	detail_condition.visible = false
	# The god's own favors as packets: one click jumps to that favor's page.
	_clear(detail_packets)
	detail_packets_label.text = "FAVORS OF %s" % god.display_name
	detail_packets_label.visible = not god.favors.is_empty()
	detail_packets.visible = not god.favors.is_empty()
	for favor in god.favors:
		var packet := UICards.seed_packet(favor, MINI_PACKET, false)
		packet.set_meta("id", favor.id)
		packet.pressed.connect(_open_page.bind(FAVORS, favor.id))
		detail_packets.add_child(packet)


func _show_favor(favor: GodFavor) -> void:
	var god := Gods.by_id(favor.god_id)
	_frame_portrait(favor.icon if favor.icon != null else UICards.PLACEHOLDER_ICON, god, favor.color)
	detail_name.text = favor.display_name
	detail_subtitle.text = "Bestowed by %s" % god.display_name
	detail_subtitle.add_theme_color_override("font_color", UITokens.god_text(god))
	var chips: Array[String] = [favor.slot_name() if favor.is_skill() else "PASSIVE SLOT"]
	chips.append(_kind_name(favor))
	if favor.cooldown > 0.0:
		chips.append("%.0fs cooldown" % favor.cooldown)
	if favor.duration > 0.0:
		chips.append("lasts %ss" % _seconds(favor.duration))
	_set_chips(chips)
	detail_description.text = favor.description
	detail_flavor.visible = false
	detail_condition.text = _condition_text(god, favor)
	detail_condition.visible = not detail_condition.text.is_empty()
	detail_packets_label.visible = false
	detail_packets.visible = false


# The portrait sits on a backdrop washed with the god's accent, inside the
# ornament frame in that accent. The wash is light: the accent stays an accent.
func _frame_portrait(texture: Texture2D, god: God, tint: Color) -> void:
	var accent := UITokens.god_accent(god)
	portrait.texture = texture
	portrait.modulate = tint
	ornament.color = accent
	var box := UITokens.accent_box(portrait_frame.get_theme_stylebox("panel", &"PanelInset"), accent)
	if box is PixelStyleBox:
		(box as PixelStyleBox).bg_color = UITokens.NIGHT_900.lerp(accent, BACKDROP_TINT)
	box.set_content_margin_all(UITokens.SPACE_16)
	portrait_frame.add_theme_stylebox_override("panel", box)


func _set_chips(texts: Array) -> void:
	_clear(detail_chips)
	for text in texts:
		if str(text).is_empty():
			continue
		var chip := Label.new()
		chip.text = str(text)
		chip.theme_type_variation = &"ChipLabel"
		detail_chips.add_child(chip)


func _kind_name(favor: GodFavor) -> String:
	match favor.kind:
		GodFavor.Kind.ACTIVE:
			return "ACTIVE"
		GodFavor.Kind.INSTANT:
			return "ONCE, AT ONCE"
		GodFavor.Kind.END_OF_TRIAL:
			return "AT TRIAL END"
	return "ALWAYS ON"


func _seconds(value: float) -> String:
	return ("%.1f" % value).trim_suffix(".0")


# What the favor asks for before a god will offer it. The slot, cooldown and
# duration are chips and "Bestowed by" is the subtitle, so this line keeps only
# the conditions: a `requires_god` favor is only OFFERED while the mortal
# already holds a favor of that god (Mayari's and Apolaki's Sibling's Rivalry
# each ask for a favor of the other sibling), and a `requires_any_god` favor
# while they hold a favor of at least one of those gods.
func _condition_text(_god: God, favor: GodFavor) -> String:
	var parts: Array[String] = []
	var required := favor.requires_god_id()
	if required != &"":
		var other := Gods.by_id(required)
		var other_name := other.display_name if other != null else str(required).to_upper()
		parts.append("CONDITION: only offered while you already hold a %s favor" % other_name)
	var any_of := favor.requires_any_god_ids()
	if not any_of.is_empty():
		var names: Array[String] = []
		for id in any_of:
			var other := Gods.by_id(id)
			names.append(other.display_name if other != null else str(id).to_upper())
		parts.append("CONDITION: only offered while you already hold a favor of %s" % " or ".join(names))
	return "\n".join(parts)


# --- input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if page_kind.is_empty():
			_on_back_pressed()
		else:
			_show_index()


func _input(event: InputEvent) -> void:
	# Tab would otherwise move keyboard focus out of the grid before
	# _unhandled_input sees it: on the favors page it cycles the filter instead.
	if page_kind == FAVORS and not _filter_chips.is_empty() and event is InputEventKey \
			and (event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev")):
		get_viewport().set_input_as_handled()
		_cycle_filter(-1 if event.is_action_pressed("ui_focus_prev") else 1)


func _cycle_filter(step: int) -> void:
	var index := 0
	for i in _filter_chips.size():
		if StringName(str(_filter_chips[i].get_meta("god_id"))) == filter_god:
			index = i
	var next: Button = _filter_chips[posmod(index + step, _filter_chips.size())]
	_set_filter(StringName(str(next.get_meta("god_id"))))


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
