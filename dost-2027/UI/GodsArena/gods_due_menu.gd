extends Control

# "God's Due" menu - press F in the arena to spend a voucher on one of the
# hosting god's favors, then press 1 / 2 / 3 to pick which one.
# If a god intervenes between trials you get a free grant instead of a voucher.

signal favor_chosen(favor: GodFavor, free_grants_left: int)
signal closed()

const MAX_ROWS := 3

@onready var title_label: Label = $SidePanel/Margin/VBox/TitleLabel
@onready var due_label: Label = $SidePanel/Margin/VBox/DueLabel
@onready var rows: VBoxContainer = $SidePanel/Margin/VBox/Rows

var _god: God = null
var _match: GodMatch = null
var _free_grants := 0
var _remote := false  # multiplayer client: only ask, never change local rules
var _shown: Array[GodFavor] = []


func _ready() -> void:
	visible = false


func is_open() -> bool:
	return visible


func open(host_god: God, host_match: GodMatch, free_grants := 0, remote := false) -> void:
	_god = host_god
	_match = host_match
	_free_grants = free_grants
	_remote = remote
	_rebuild()
	visible = true


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _rebuild() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	_shown.clear()
	if _god == null or _match == null:
		return

	title_label.text = "%s'S FAVORS" % _god.display_name
	title_label.add_theme_color_override("font_color", _god.color)

	var mortal := _match.local()
	var due := 0
	if mortal != null:
		due = mortal.due
	if _free_grants > 0:
		due_label.text = "A GOD INTERVENES - ONE FAVOR IS FREE"
	else:
		due_label.text = "GOD'S DUE VOUCHERS: %d" % due

	# Candidates: this god's favors you do not hold yet. Skills and instant
	# boons first - those are the ones you can spend mid-trial.
	var candidates: Array[GodFavor] = []
	if mortal != null:
		for favor in _god.favors:
			if not mortal.has_favor(favor.id):
				candidates.append(favor)
	candidates.sort_custom(func(a, b): return _kind_rank(a) < _kind_rank(b))

	var count := mini(MAX_ROWS, candidates.size())
	for index in range(count):
		var favor: GodFavor = candidates[index]
		_shown.append(favor)
		rows.add_child(_make_row(index + 1, favor, due))

	if candidates.size() > count:
		rows.add_child(_make_note("+%d more favor(s) show once these are taken." % (candidates.size() - count)))
	elif candidates.is_empty():
		rows.add_child(_make_note("You already hold every favor %s can give." % _god.display_name))


func _kind_rank(favor: GodFavor) -> int:
	match favor.kind:
		GodFavor.Kind.ACTIVE:
			return 0
		GodFavor.Kind.INSTANT:
			return 1
		GodFavor.Kind.PASSIVE:
			return 2
		GodFavor.Kind.END_OF_TRIAL:
			return 3
	return 4


func _make_note(text: String) -> Label:
	var note := Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	return note


func _make_row(number: int, favor: GodFavor, due: int) -> PanelContainer:
	var affordable := _free_grants > 0 or due > 0

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.2, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = favor.color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.modulate.a = 1.0 if affordable else 0.5

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)

	var head := Label.new()
	head.text = "%d.  %s   [%s]" % [number, favor.display_name.to_upper(), favor.slot_name()]
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", favor.color)

	var desc := Label.new()
	desc.text = favor.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 10)
	desc.add_theme_color_override("font_color", Color(0.72, 0.76, 0.85))

	var cost := Label.new()
	if _free_grants > 0:
		cost.text = "FREE - GIFT OF %s" % _god.display_name
	elif due > 0:
		cost.text = "COST: 1 GOD'S DUE"
	else:
		cost.text = "NEEDS 1 GOD'S DUE"
	cost.add_theme_font_size_override("font_size", 10)
	cost.add_theme_color_override("font_color", Color(0.55, 0.9, 0.6) if affordable else Color(0.85, 0.45, 0.4))

	box.add_child(head)
	box.add_child(desc)
	box.add_child(cost)
	margin.add_child(box)
	panel.add_child(margin)
	return panel


func _choose(index: int) -> void:
	if index < 0 or index >= _shown.size():
		return
	var favor: GodFavor = _shown[index]
	if _remote:
		# Multiplayer client: the host decides. Emit straight away - the arena
		# forwards the request and the next snapshot updates our favor list.
		favor_chosen.emit(favor, _free_grants)
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
		_rebuild()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var index := -1
	match key_event.keycode:
		KEY_1, KEY_KP_1:
			index = 0
		KEY_2, KEY_KP_2:
			index = 1
		KEY_3, KEY_KP_3:
			index = 2
	if index >= 0:
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		_choose(index)
