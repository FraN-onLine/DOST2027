extends Control

# "God's Due" menu - press F in the arena to spend a voucher on one of the
# hosting god's favors, then press 1 / 2 / 3 - or simply CLICK one of the
# packets - to pick which one. The offer is three seed packets side by side,
# drawn exactly like the Almanac's (UICards), each under its key.
# If a god intervenes between trials you get a free grant instead of a voucher.
#
# THE ALTAR (the preparation area only, open(..., boon_cost, boons_left)): with
# no voucher left the same cards are a boon shop - each one priced at boon_cost
# FAVOR (greyed, the price in EMBER, when it cannot be paid; locked once the
# player's boons here are bought), a skill that would take an occupied slot warns
# REPLACES <old skill>, and the choice is only ASKED for (boon_chosen): the arena
# - the host - decides. A voucher is always spent first, exactly as in a trial.
# In a trial boon_cost is 0 and nothing of this shows.

signal favor_chosen(favor: GodFavor, free_grants_left: int)
signal boon_chosen(favor: GodFavor)

const MAX_ROWS := 3
const PACKET_SIZE := Vector2(160, 150)
const COLUMN_WIDTH := 200.0

@onready var title_label: Label = $SidePanel/Margin/VBox/TitleLabel
@onready var due_label: Label = $SidePanel/Margin/VBox/DueLabel
@onready var rows: HBoxContainer = $SidePanel/Margin/VBox/Rows
@onready var close_key: Label = $SidePanel/Margin/VBox/HintRow/CloseKey

var _god: God = null
var _match: GodMatch = null
var _free_grants := 0
var _remote := false  # multiplayer client: only ask, never change local rules
var _boon_cost := 0   # > 0 at the altar: no voucher means the cards are for sale
var _boons_left := 0  # boons this player may still buy here
var _shown: Array[GodFavor] = []


func _ready() -> void:
	visible = false


func is_open() -> bool:
	return visible


func open(host_god: God, host_match: GodMatch, free_grants := 0, remote := false, boon_cost := 0, boons_left := 0) -> void:
	_god = host_god
	_match = host_match
	_free_grants = free_grants
	_remote = remote
	_boon_cost = boon_cost
	_boons_left = boons_left
	_rebuild()
	visible = true
	UITokens.reveal(self)


func close() -> void:
	visible = false


func _rebuild() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	_shown.clear()
	if _god == null or _match == null:
		return

	title_label.text = "%s'S FAVORS" % _god.display_name
	title_label.add_theme_color_override("font_color", UITokens.god_text(_god))
	close_key.text = UITokens.key_text(&"due_menu")

	var mortal := _match.local()
	var due := 0
	if mortal != null:
		due = mortal.due
	if _free_grants > 0:
		due_label.text = "A GOD INTERVENES - ONE FAVOR IS FREE"
	elif selling(due):
		due_label.text = "BUY A BOON - %d FAVOR" % _boon_cost
	else:
		due_label.text = "GOD'S DUE VOUCHERS: %d" % due

	# Every opening rolls a fresh set. E/Q candidates stay eligible because
	# selecting one replaces the currently owned skill in that slot.
	var candidates: Array[GodFavor] = []
	if mortal != null:
		for favor in _god.favors:
			if not mortal.has_favor(favor.id) and _match.is_favor_eligible(favor):
				candidates.append(favor)
	candidates.shuffle()

	var count := mini(MAX_ROWS, candidates.size())
	for index in range(count):
		var favor: GodFavor = candidates[index]
		_shown.append(favor)
		rows.add_child(_make_row(index + 1, favor, due))

	if candidates.size() > count:
		rows.add_child(_make_note("+%d more favor(s) show once these are taken." % (candidates.size() - count)))
	elif candidates.is_empty():
		rows.add_child(_make_note("You already hold every favor %s can give." % _god.display_name))


# The cards are for sale: at the altar, with no voucher and no free grant.
func selling(due: int) -> bool:
	return _boon_cost > 0 and due <= 0 and _free_grants <= 0


func _make_note(text: String) -> Label:
	var note := Label.new()
	note.text = text
	note.theme_type_variation = &"MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = COLUMN_WIDTH
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return note


# One offered favor: its key, its seed packet - the same packet the Almanac
# shows, so it is recognised at a glance - what it does, and what it costs: a
# God's Due, or at the altar with none (selling) its price in FAVOR - JADE, EMBER
# on a greyed card that cannot be paid, FAINT and locked once the boons here are
# bought - plus a REPLACES warning for a skill that would take an occupied slot.
func _make_row(number: int, favor: GodFavor, due: int) -> VBoxContainer:
	var mortal := _match.local()
	var for_sale := selling(due)
	var affordable := _free_grants > 0 or due > 0
	if for_sale:
		affordable = mortal != null and mortal.favor >= _boon_cost
	var current_skill: GodFavor = mortal.favor_in_slot(favor.slot) if mortal != null and favor.is_skill() else null

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UITokens.SPACE_8)
	column.custom_minimum_size.x = COLUMN_WIDTH
	column.modulate.a = 1.0 if affordable and not (for_sale and _boons_left <= 0) else 0.5

	var key := Label.new()
	key.text = UITokens.key_text(StringName("due_choice_%d" % number))
	key.theme_type_variation = &"KeycapLabel"
	key.custom_minimum_size.x = UITokens.BUTTON_ICON.x
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(key)

	var packet := UICards.seed_packet(favor, PACKET_SIZE)
	packet.focus_mode = Control.FOCUS_NONE
	packet.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(packet)

	var desc := Label.new()
	desc.text = favor.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(desc)

	var cost_color := UITokens.JADE if affordable else UITokens.EMBER
	var cost_text := ""
	if for_sale and _boons_left <= 0:
		cost_text = "%d FAVOR - LOCKED" % _boon_cost
		cost_color = UITokens.FAINT
	elif for_sale:
		cost_text = "%d FAVOR" % _boon_cost
	elif current_skill != null:
		cost_text = "REPLACES: %s" % current_skill.display_name
		cost_color = UITokens.GOLD
	elif _free_grants > 0:
		cost_text = "FREE - GIFT OF %s" % _god.display_name
	elif due > 0:
		cost_text = "COST: 1 GOD'S DUE"
	else:
		cost_text = "NEEDS 1 GOD'S DUE"
	var cost := _caption(cost_text, cost_color)
	cost.name = "Price"
	column.add_child(cost)
	if for_sale and current_skill != null:
		var warning := _caption("REPLACES %s" % current_skill.display_name, UITokens.GOLD)
		warning.name = "Replaces"
		column.add_child(warning)

	# The whole column is the tap target: it takes the mouse (its contents stay
	# see-through) and answers it the way its number key does. Under the mouse
	# the packet is picked up - lifted, with the gold ring - so it reads as
	# something you can press.
	column.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in column.get_children():
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.gui_input.connect(_on_row_input.bind(number - 1))
	column.mouse_entered.connect(UICards.set_selected.bind(packet, true))
	column.mouse_exited.connect(UICards.set_selected.bind(packet, false))
	return column


func _caption(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"CaptionLabel"
	label.add_theme_color_override("font_color", UITokens.readable_on_dark(color, UITokens.NIGHT_800))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


# A click on a row claims the favor it shows, exactly like its number key.
# `index` arrives as the BOUND argument (see _make_row), so it comes AFTER the
# event the gui_input signal carries.
func _on_row_input(event: InputEvent, index: int) -> void:
	if not visible:
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	_choose(index)


func _choose(index: int) -> void:
	if index < 0 or index >= _shown.size():
		return
	var favor: GodFavor = _shown[index]
	var mortal := _match.local()
	if selling(mortal.due if mortal != null else 0):
		# A boon: asked for, never decided here - the arena (the host) checks it
		# and the next snapshot brings it back.
		if _boons_left <= 0 or mortal == null or mortal.favor < _boon_cost:
			return
		boon_chosen.emit(favor)
		close()
		return
	if _free_grants <= 0 and (mortal == null or mortal.due <= 0):
		# Nothing to spend: the row is greyed, and a click or key does nothing but say so.
		due_label.text = "NO GOD'S DUE YET"
		return
	if _remote:
		# Multiplayer client: the host decides. Emit once we know there is a
		# voucher to spend - the arena forwards the request, and only the next
		# snapshot (not this click) proves the favor is ours.
		favor_chosen.emit(favor, _free_grants)
		close()
		return
	var granted := false
	if _free_grants > 0:
		granted = _match.bestow_favor(favor)
		if granted:
			_free_grants -= 1
	else:
		granted = _match.grant_favor(favor)
	if granted:
		favor_chosen.emit(favor, _free_grants)
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey):
		return
	var index := -1
	for choice in range(3):
		if event.is_action_pressed("due_choice_%d" % (choice + 1)):
			index = choice
	if index >= 0:
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		_choose(index)
