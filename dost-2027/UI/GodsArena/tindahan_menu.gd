extends Control

# The Tindahan (the shop) in the preparation area between two trials - walk up to
# the stall and LEFT CLICK. Built like the God's Due menu (gods_due_menu.gd): up
# to three Pamana cards side by side, each under its key (1 / 2 / 3, the same
# due_choice_* actions) with its effect and its price - or simply CLICK one. Esc,
# or walking away from the stall, closes it.
#
# The offers are this player's own (the host rolled them, see prep_area.gd) and
# this panel never decides a purchase: it only asks (pamana_chosen) and redraws
# from what it is told - affordable, too dear (the price in EMBER), bought
# (BINILI) or locked once the player is out of purchases.

signal pamana_chosen(pamana: Pamana)

const PACKET_SIZE := Vector2(160, 150)
const COLUMN_WIDTH := 200.0

@onready var title_label: Label = $SidePanel/Margin/VBox/TitleLabel
@onready var status_label: Label = $SidePanel/Margin/VBox/StatusLabel
@onready var rows: HBoxContainer = $SidePanel/Margin/VBox/Rows
@onready var close_key: Label = $SidePanel/Margin/VBox/HintRow/CloseKey

var _offers: Array[Pamana] = []
var _favor := 0
var _bought: Array = []   # pamana ids this player bought here
var _locked := false      # out of purchases: every card left is locked
var _shown_state := []    # what the rows were last drawn from (redraw on change only)


func _ready() -> void:
	visible = false


func is_open() -> bool:
	return visible


func open(offers: Array[Pamana], favor: int, bought: Array, locked: bool) -> void:
	_offers = offers
	_shown_state = []
	refresh(favor, bought, locked)
	visible = true
	UITokens.reveal(self)


# The arena calls this every frame while the panel is open; it only redraws when
# the FAVOR, the purchases or the offers really changed.
func refresh(favor: int, bought: Array, locked: bool) -> void:
	_favor = favor
	_bought = bought
	_locked = locked
	var state := [favor, bought.duplicate(), locked, _offers.map(func(p: Pamana) -> StringName: return p.id)]
	if state == _shown_state:
		return
	_shown_state = state
	_rebuild()


func close() -> void:
	visible = false


func _rebuild() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	title_label.text = "TINDAHAN"
	close_key.text = "Esc"
	status_label.text = "ONE PAMANA PER REST  -  YOUR FAVOR: %d" % _favor
	for index in range(_offers.size()):
		rows.add_child(_make_row(index + 1, _offers[index]))
	if _offers.is_empty():
		var note := Label.new()
		note.text = "Nothing on the shelf for you this time."
		note.theme_type_variation = &"MutedLabel"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = COLUMN_WIDTH
		rows.add_child(note)


func _make_row(number: int, pamana: Pamana) -> VBoxContainer:
	var bought := _bought.has(pamana.id)
	var affordable := _favor >= pamana.cost
	var buyable := not bought and not _locked and affordable

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UITokens.SPACE_8)
	column.custom_minimum_size.x = COLUMN_WIDTH
	column.modulate.a = 1.0 if buyable or bought else 0.5

	var key := Label.new()
	key.text = UITokens.key_text(StringName("due_choice_%d" % number))
	key.theme_type_variation = &"KeycapLabel"
	key.custom_minimum_size.x = UITokens.BUTTON_ICON.x
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(key)

	var card := UICards.pamana_card(pamana, PACKET_SIZE)
	card.focus_mode = Control.FOCUS_NONE
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(card)

	var desc := Label.new()
	desc.text = pamana.effect
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(desc)

	var price := Label.new()
	var price_color := UITokens.JADE
	if bought:
		price.text = "BINILI"
		price_color = UITokens.GOLD
	elif _locked:
		price.text = "%d FAVOR - LOCKED" % pamana.cost
		price_color = UITokens.FAINT
	elif not affordable:
		price.text = "%d FAVOR" % pamana.cost
		price_color = UITokens.EMBER
	else:
		price.text = "COST: %d FAVOR" % pamana.cost
	price.name = "Price"
	price.theme_type_variation = &"CaptionLabel"
	price.add_theme_color_override("font_color", UITokens.readable_on_dark(price_color, UITokens.NIGHT_800))
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(price)

	# The whole column is the tap target, exactly like a God's Due row.
	column.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in [key, card, desc, price]:
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.gui_input.connect(_on_row_input.bind(number - 1))
	column.mouse_entered.connect(UICards.set_selected.bind(card, true))
	column.mouse_exited.connect(UICards.set_selected.bind(card, false))
	return column


func _on_row_input(event: InputEvent, index: int) -> void:
	if not visible or not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	choose(index)


# Ask for the card at `index`, when it can be bought at all. Returns true when
# the request went out (the arena still has the final word).
func choose(index: int) -> bool:
	if index < 0 or index >= _offers.size():
		return false
	var pamana: Pamana = _offers[index]
	if _locked or _bought.has(pamana.id) or _favor < pamana.cost:
		return false
	pamana_chosen.emit(pamana)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var viewport := get_viewport()
	if event.is_action_pressed("ui_cancel"):
		if viewport != null:
			viewport.set_input_as_handled()
		close()
		return
	for choice in range(3):
		if event.is_action_pressed("due_choice_%d" % (choice + 1)):
			if viewport != null:
				viewport.set_input_as_handled()
			choose(choice)
			return
