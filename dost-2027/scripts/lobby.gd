extends Control

@onready var player_list_vbox = $CenterContainer/VBoxContainer/PlayerListScroll/PlayerListVBox
@onready var name_input = $CenterContainer/VBoxContainer/NameInput
@onready var change_name_button = $CenterContainer/VBoxContainer/ChangeNameButton
@onready var god_icon_option: OptionButton = $CenterContainer/VBoxContainer/GodIconRow/GodIconOption
@onready var god_icon_preview: TextureRect = $CenterContainer/VBoxContainer/GodIconRow/GodIconPreview
@onready var start_game_button = $CenterContainer/VBoxContainer/ButtonContainer/StartGameButton
@onready var options_button = $CenterContainer/VBoxContainer/ButtonContainer/OptionsButton
@onready var leave_button = $CenterContainer/VBoxContainer/ButtonContainer/LeaveButton
@onready var status_label = $StatusLabel
@onready var lobby_id_label = $LobbyIdLabel

var connected_players = {}
var is_host = false

func _ready():
	# Connect button signals
	start_game_button.pressed.connect(_on_start_game_pressed)
	options_button.pressed.connect(_on_options_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	change_name_button.pressed.connect(_on_change_name_pressed)
	name_input.text_submitted.connect(_on_name_submitted)
	god_icon_option.item_selected.connect(_on_god_icon_selected)
	
	# Connect to network signals
	Network.player_joined.connect(_on_player_joined)
	Network.player_left.connect(_on_player_left)
	Network.player_list_updated.connect(_on_player_list_updated)
	Network.player_god_icon_changed.connect(_on_player_god_icon_changed)
	_populate_god_icons()
	_build_order_panel()
	Network.trial_order_changed.connect(_on_trial_order_changed)
	
	# Check if we're the host
	is_host = multiplayer.is_server()
	
	if is_host:
		status_label.text = "You are the host. Waiting for players..."
		# Show the lobby ID so friends can join directly - no IP/port needed
		if lobby_id_label:
			lobby_id_label.text = "Lobby ID: %s" % Network.lobby_id
			lobby_id_label.visible = true
		# Prefill name with the host's random name
		var my_id = multiplayer.get_unique_id()
		if my_id in Network.players:
			name_input.text = str(Network.players[my_id])
	else:
		status_label.text = "Connected to host. Waiting for game to start..."
		start_game_button.visible = false
		# Hide lobby ID label for clients
		if lobby_id_label:
			lobby_id_label.visible = false
	
	# Request current player list from server
	if is_host:
		Network.broadcast_player_list()
		connected_players = Network.players.duplicate()
		_update_player_list()
		var my_id = multiplayer.get_unique_id()
		if my_id in connected_players:
			name_input.text = str(connected_players[my_id])
	else:
		Network.rpc_id(1, "request_player_list")
	
	_update_player_list()
	_refresh_order_panel()


func _on_trial_order_changed(_ids: Array) -> void:
	_refresh_order_panel()


func _on_start_game_pressed():
	if is_host and connected_players.size() >= Network.MIN_PLAYERS_TO_START:
		Network.start_game()

func _on_leave_pressed():
	if is_host:
		Network.stop_host()
	else:
		Network.leave_host()
	
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_player_joined(player_id: int):
	print("Player joined lobby: ", player_id)
	_update_player_list()

func _on_player_left(player_id: int):
	print("Player left lobby: ", player_id)
	connected_players.erase(player_id)
	_update_player_list()

func _on_change_name_pressed():
	_change_name()

func _on_name_submitted(_text: String):
	_change_name()

func _change_name():
	var new_name = name_input.text.strip_edges()
	if new_name.is_empty():
		status_label.text = "Please enter a valid name"
		return
	
	var my_id = multiplayer.get_unique_id()
	if is_host:
		Network.request_name_change(my_id, new_name)
	else:
		Network.rpc_id(1, "request_name_change", my_id, new_name)
	status_label.text = "Changing name to: " + new_name

func _on_player_list_updated(players: Dictionary):
	connected_players = players.duplicate()
	_update_player_list()

func _update_player_list():
	# Clear existing player labels immediately (not deferred) to prevent overlap
	for child in player_list_vbox.get_children():
		player_list_vbox.remove_child(child)
		child.queue_free()
	
	# Add current players
	for player_id in connected_players.keys():
		var hbox = HBoxContainer.new()
		hbox.custom_minimum_size = Vector2(0, 34)
		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(28, 28)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var player_god := Gods.by_id(StringName(str(Network.player_icons.get(player_id, &"mayari"))))
		if player_god != null:
			icon_rect.texture = player_god.icon
		hbox.add_child(icon_rect)
		var label = Label.new()
		label.text = str(connected_players[player_id])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.add_theme_font_size_override("font_size", 16)
		hbox.add_child(label)
		
		# Add host indicator
		if int(player_id) == 1:
			var host_label = Label.new()
			host_label.text = " [HOST]"
			host_label.add_theme_color_override("font_color", Color.YELLOW)
			host_label.add_theme_font_size_override("font_size", 13)
			hbox.add_child(host_label)
		
		player_list_vbox.add_child(hbox)
	
	# Update start game button state
	if is_host:
		start_game_button.disabled = connected_players.size() < Network.MIN_PLAYERS_TO_START
		status_label.text = "Players: " + str(connected_players.size()) + "/" + str(Network.MAX_PLAYERS)


func _populate_god_icons() -> void:
	god_icon_option.clear()
	var selected_id := Network.my_god_icon_id
	var selected_index := 0
	for god in Gods.all():
		if god.icon == null:
			continue
		var index := god_icon_option.item_count
		god_icon_option.add_item(god.display_name)
		god_icon_option.set_item_metadata(index, god.id)
		if god.id == selected_id:
			selected_index = index
	if god_icon_option.item_count == 0:
		return
	god_icon_option.select(selected_index)
	_show_god_icon(selected_id)


func _on_god_icon_selected(index: int) -> void:
	var god_id := StringName(str(god_icon_option.get_item_metadata(index)))
	_show_god_icon(god_id)
	Network.choose_player_god_icon(god_id)


func _show_god_icon(god_id: StringName) -> void:
	var god := Gods.by_id(god_id)
	if god != null:
		god_icon_preview.texture = god.icon


func _on_player_god_icon_changed(peer_id: int, god_id: StringName) -> void:
	if peer_id == multiplayer.get_unique_id():
		_show_god_icon(god_id)
		for index in range(god_icon_option.item_count):
			if StringName(str(god_icon_option.get_item_metadata(index))) == god_id:
				god_icon_option.select(index)
				break
	_update_player_list()


# ============================================
# Trial order (the host's OPTIONS)
# ============================================
# The run faces a god per trial, in an order only the HOST holds: RANDOM (the
# default - every run is drawn fresh) or CUSTOM, where the gods sit in a stacked
# list the host walks up and down with the arrow buttons beside each of them.
# Bathala always closes the run, so it is never one of the rows.
#
# The panel is built in code (the authored scene keeps its own layout untouched)
# and only appears when OPTIONS is pressed - it must never sit on top of the
# START / LEAVE buttons. A client never sees OPTIONS at all: the order belongs
# to the host and travels to every screen when the run starts.

var _order_panel: PanelContainer = null
var _order_title: Label = null
var _order_label: Label = null
var _random_box: CheckBox = null
var _custom_box: CheckBox = null
var _order_rows: VBoxContainer = null
var _syncing_order_panel := false


func _on_options_pressed() -> void:
	if _order_panel == null or not is_host:
		return
	_refresh_order_panel()
	_rebuild_order_rows()
	_order_panel.visible = not _order_panel.visible


func _build_order_panel() -> void:
	_order_panel = PanelContainer.new()
	_order_panel.name = "TrialOrderPanel"
	# A popup over the lobby: it opens from OPTIONS, covers the roster while it is
	# read and never sits half-hidden behind the START / LEAVE row.
	_order_panel.set_anchors_preset(Control.PRESET_CENTER, true)
	_order_panel.offset_left = -260.0
	_order_panel.offset_top = -115.0
	_order_panel.offset_right = 260.0
	_order_panel.offset_bottom = 115.0
	_order_panel.visible = false
	add_child(_order_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.34, 0.38, 0.5, 1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	_order_panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_order_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	_order_title = Label.new()
	_order_title.text = "TRIAL ORDER"
	_order_title.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_order_title.add_theme_font_size_override("font_size", 12)
	box.add_child(_order_title)

	# RANDOM or CUSTOM - the host checks one of the two tick boxes.
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 20)
	_random_box = _mode_box("RANDOM")
	_random_box.tooltip_text = "Each run draws the order of the gods fresh."
	_random_box.toggled.connect(_on_order_mode_toggled.bind(false))
	_custom_box = _mode_box("CUSTOM")
	_custom_box.tooltip_text = "Walk the gods up and down into the order you want."
	_custom_box.toggled.connect(_on_order_mode_toggled.bind(true))
	mode_row.add_child(_random_box)
	mode_row.add_child(_custom_box)
	box.add_child(mode_row)

	_order_label = Label.new()
	_order_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_order_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	_order_label.add_theme_font_size_override("font_size", 11)
	box.add_child(_order_label)

	# The stacked list the host walks up and down (CUSTOM only).
	_order_rows = VBoxContainer.new()
	_order_rows.add_theme_constant_override("separation", 4)
	box.add_child(_order_rows)


func _mode_box(text: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.add_theme_font_size_override("font_size", 12)
	return box


# Every god a trial can be played against. Bathala is never one of them - it
# always closes the run.
func _playable_god_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for god in Gods.all():
		if god.id == Gods.BATHALA or not god.implemented or god.arena_scene == "":
			continue
		ids.append(god.id)
	return ids


# What the stacked list shows: the host's custom order, or the plain list of
# playable gods while the run is still random.
func _order_list() -> Array[StringName]:
	if Network.trial_order_custom.is_empty():
		return _playable_god_ids()
	return Network.trial_order_custom.duplicate()


func _rebuild_order_rows() -> void:
	for child in _order_rows.get_children():
		_order_rows.remove_child(child)
		child.queue_free()
	# RANDOM draws its own order at the start of the run - no list to walk.
	if Network.trial_order_custom.is_empty():
		return
	var ids := _order_list()
	for index in range(ids.size()):
		_order_rows.add_child(_order_row(index, ids))


func _order_row(index: int, ids: Array[StringName]) -> HBoxContainer:
	var god_id := ids[index]
	var god := Gods.by_id(god_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var number := Label.new()
	number.text = "%d." % (index + 1)
	number.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	number.add_theme_font_size_override("font_size", 12)
	number.custom_minimum_size = Vector2(26, 0)
	row.add_child(number)

	var name_label := Label.new()
	name_label.text = god.display_name
	name_label.add_theme_color_override("font_color", god.color)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var up := Button.new()
	up.name = "Up_%s" % god_id
	up.text = "UP"
	up.disabled = index == 0  # the first god has nothing above it
	up.add_theme_font_size_override("font_size", 10)
	up.pressed.connect(_on_order_move_pressed.bind(god_id, -1))
	row.add_child(up)

	var down := Button.new()
	down.name = "Down_%s" % god_id
	down.text = "DOWN"
	down.disabled = index == ids.size() - 1  # and the last nothing below
	down.add_theme_font_size_override("font_size", 10)
	down.pressed.connect(_on_order_move_pressed.bind(god_id, 1))
	row.add_child(down)
	return row


func _refresh_order_panel() -> void:
	if _order_panel == null:
		return
	# Only the host holds the order: a client never gets the OPTIONS button and
	# never sees the panel - it is told the order when the run starts.
	options_button.visible = is_host
	if not is_host:
		_order_panel.visible = false
		return
	var chosen: Array = Network.trial_order_custom
	_syncing_order_panel = true
	_random_box.button_pressed = chosen.is_empty()
	_custom_box.button_pressed = not chosen.is_empty()
	_syncing_order_panel = false
	if chosen.is_empty():
		_order_title.text = "TRIAL ORDER  -  RANDOM"
		_order_label.text = "RANDOM  (each run is drawn fresh)"
	else:
		_order_title.text = "TRIAL ORDER  -  CUSTOM"
		var names: Array[String] = []
		for god_id in chosen:
			var god := Gods.by_id(StringName(str(god_id)))
			if god != null:
				names.append("%d. %s" % [names.size() + 1, god.display_name])
		_order_label.text = "  ->  ".join(names) + "  ->  BATHALA"


func _on_order_mode_toggled(pressed: bool, custom: bool) -> void:
	if _syncing_order_panel or not is_host:
		return
	if pressed:
		# The host picks exactly one: checking a mode clears the other.
		_syncing_order_panel = true
		_custom_box.button_pressed = custom
		_random_box.button_pressed = not custom
		_syncing_order_panel = false
		if custom:
			Network.set_custom_trial_order(_playable_god_ids())
		else:
			Network.clear_custom_trial_order()
		_refresh_order_panel()
		_rebuild_order_rows()
		return
	# Unchecking the only mode leaves the run undecided: put back the mode the
	# order it currently holds.
	if not _random_box.button_pressed and not _custom_box.button_pressed:
		var custom_mode := not Network.trial_order_custom.is_empty()
		_syncing_order_panel = true
		_custom_box.button_pressed = custom_mode
		_random_box.button_pressed = not custom_mode
		_syncing_order_panel = false


func _on_order_move_pressed(god_id: StringName, step: int) -> void:
	if not is_host:
		return
	var order := _order_list()
	var index := order.find(god_id)
	if index < 0:
		return
	var target := index + step
	if target < 0 or target >= order.size():
		return
	order[index] = order[target]
	order[target] = god_id
	# Walking the list only means something in CUSTOM: RANDOM is drawn at the
	# start of the run, so a move settles it as a custom order.
	Network.set_custom_trial_order(order)
	_refresh_order_panel()
	_rebuild_order_rows()
