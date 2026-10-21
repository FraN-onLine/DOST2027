extends Control

# The lobby, in two columns.
#
#   Left:  the roster - MAX_PLAYERS fixed slots, so the table's size reads at a
#          glance. A filled slot shows the mortal's god icon in a frame of that
#          god's accent, a swatch of the bandana colour that player wears on the
#          field, the name, and a gold HOST nameplate for peer 1; an empty one is a
#          dashed outline still "Waiting for a mortal...". YOUR slot also carries
#          the bandana picker: one swatch per colour, a colour another player holds
#          greyed out with a padlock; pressing a free one asks the host for it
#          (Network.choose_bandana_color) and the roster comes back with the answer.
#   Right: "You" (name + UPDATE, the god icon picker as a row of icon buttons)
#          and "The run" (the run summary and OPTIONS).
#   Top right: the lobby ID as a big key, with COPY (host only).
#   Bottom: LEAVE (ghost, left) and START GAME (the one gold primary, right).
#          While START is disabled the caption beside it says why - a disabled
#          button that does not say why is a dead end.

const EMPTY_TEXT := "Waiting for a mortal..."
const SLOT_ICON := Vector2(32, 32)
const COPIED_SECONDS := 1.5

@onready var player_list_vbox = $Page/VBox/Scroll/Columns/Roster/VBox/PlayerListVBox
@onready var roster_label: Label = $Page/VBox/Scroll/Columns/Roster/VBox/PlayerListLabel
@onready var name_input = $Page/VBox/Scroll/Columns/Side/YouCard/VBox/NameRow/NameInput
@onready var change_name_button = $Page/VBox/Scroll/Columns/Side/YouCard/VBox/NameRow/ChangeNameButton
@onready var god_icon_row: HBoxContainer = $Page/VBox/Scroll/Columns/Side/YouCard/VBox/GodIconRow
@onready var god_icon_preview: TextureRect = $Page/VBox/Scroll/Columns/Side/YouCard/VBox/NameRow/GodIconPreview
@onready var start_game_button = $Page/VBox/BottomBar/StartGameButton
@onready var start_caption: Label = $Page/VBox/BottomBar/StartCaption
@onready var options_button = $Page/VBox/Scroll/Columns/Side/RunCard/VBox/Row/OptionsButton
@onready var leave_button = $Page/VBox/BottomBar/LeaveButton
@onready var status_label = $Page/VBox/BottomBar/StatusLabel
@onready var lobby_id_box: HBoxContainer = $Page/VBox/Header/LobbyIdBox
@onready var lobby_id_label = $Page/VBox/Header/LobbyIdBox/LobbyIdLabel
@onready var copy_button: Button = $Page/VBox/Header/LobbyIdBox/CopyButton
# The run setup: everyone reads it in one line in "The run", and OPTIONS opens
# the full panel (editable for the host, read-only for clients).
@onready var run_summary_label: Label = $Page/VBox/Scroll/Columns/Side/RunCard/VBox/Row/RunSummaryLabel
@onready var lobby_options = $LobbyOptions

var connected_players = {}
var is_host = false
# The icon picker, one toggle button per god with an icon (metadata "god_id").
var god_icon_buttons: Array[Button] = []

func _ready():
	# Connect button signals
	start_game_button.pressed.connect(_on_start_game_pressed)
	options_button.pressed.connect(_on_options_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	change_name_button.pressed.connect(_on_change_name_pressed)
	name_input.text_submitted.connect(_on_name_submitted)
	copy_button.pressed.connect(_on_copy_pressed)

	# Connect to network signals
	Network.player_joined.connect(_on_player_joined)
	Network.player_left.connect(_on_player_left)
	Network.player_list_updated.connect(_on_player_list_updated)
	Network.player_god_icon_changed.connect(_on_player_god_icon_changed)
	_populate_god_icons()
	Network.run_settings_changed.connect(_on_run_settings_changed)

	# Check if we're the host
	is_host = multiplayer.is_server()

	if is_host:
		status_label.text = "You are the host. Waiting for players..."
		# Show the lobby ID so friends can join directly - no IP/port needed
		lobby_id_label.text = Network.lobby_id
		lobby_id_box.visible = true
		# Prefill name with the host's random name
		var my_id = multiplayer.get_unique_id()
		if my_id in Network.players:
			name_input.text = str(Network.players[my_id])
	else:
		status_label.text = "Connected to host. Waiting for game to start..."
		start_game_button.visible = false
		# Only the host shares the lobby ID
		lobby_id_box.visible = false

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
	_refresh_run_summary()
	_update_start_button()
	for button in god_icon_buttons:
		if button.button_pressed:
			button.grab_focus()


func _on_run_settings_changed(_settings: Dictionary) -> void:
	_refresh_run_summary()
	_update_start_button()


func _refresh_run_summary() -> void:
	run_summary_label.text = Network.run_settings.summary()


# START needs enough players AND a legal setup (no god twice in a row in a
# CUSTOM order) - the panel shows the warning, this keeps the button honest and
# its caption says which of the two is missing.
func _update_start_button() -> void:
	if not is_host:
		start_caption.text = "The host starts the game"
		start_caption.remove_theme_color_override("font_color")
		return
	var reason := ""
	if connected_players.size() < Network.MIN_PLAYERS_TO_START:
		reason = "Need %d+ players" % Network.MIN_PLAYERS_TO_START
	else:
		var problems: Array[String] = Network.run_settings.problems()
		if not problems.is_empty():
			reason = problems[0]
	start_game_button.disabled = not reason.is_empty()
	start_game_button.tooltip_text = reason
	start_caption.text = reason if not reason.is_empty() else "Everyone ready?"
	if reason.is_empty():
		start_caption.add_theme_color_override("font_color", UITokens.JADE)
	else:
		start_caption.add_theme_color_override("font_color", UITokens.readable_on_dark(UITokens.EMBER, UITokens.NIGHT_900))


func _on_options_pressed() -> void:
	if lobby_options.visible:
		lobby_options.close()
	else:
		lobby_options.open(is_host)
		UITokens.reveal(lobby_options)


func _on_start_game_pressed():
	if is_host and connected_players.size() >= Network.MIN_PLAYERS_TO_START and Network.run_settings.problems().is_empty():
		Network.start_game()

func _on_leave_pressed():
	if is_host:
		Network.stop_host()
	else:
		Network.leave_host()

	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


# Lobby ID -> clipboard, with a moment of "COPIED" as the feedback.
func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(Network.lobby_id)
	copy_button.text = "COPIED"
	get_tree().create_timer(COPIED_SECONDS).timeout.connect(func() -> void:
		if is_instance_valid(copy_button):
			copy_button.text = "COPY")


# Esc means back - but here "back" closes the lobby for everyone (host) or drops
# the player out of it, so Esc only takes focus to LEAVE; Enter confirms. The
# OPTIONS panel handles its own Esc first while it is open.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not lobby_options.visible:
		get_viewport().set_input_as_handled()
		leave_button.grab_focus()

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
	# Clear existing slots immediately (not deferred) to prevent overlap
	for child in player_list_vbox.get_children():
		player_list_vbox.remove_child(child)
		child.queue_free()

	# One slot per seat at the table: the players in join order, then the empty seats.
	var ids: Array = connected_players.keys()
	for seat in range(Network.MAX_PLAYERS):
		if seat < ids.size():
			player_list_vbox.add_child(_player_slot(ids[seat]))
		else:
			player_list_vbox.add_child(_empty_slot())
	roster_label.text = "MORTALS  %d/%d" % [connected_players.size(), Network.MAX_PLAYERS]

	# Update start game button state
	if is_host:
		_update_start_button()
		status_label.text = "Players: " + str(connected_players.size()) + "/" + str(Network.MAX_PLAYERS)


# A filled seat: [icon in its god's accent frame] name ............ [HOST]
func _player_slot(player_id) -> PanelContainer:
	var player_god := Gods.by_id(StringName(str(Network.player_icons.get(player_id, &"mayari"))))
	var accent := UITokens.god_accent(player_god)
	var slot := PanelContainer.new()
	slot.theme_type_variation = &"PanelRow"
	slot.add_theme_stylebox_override("panel", UITokens.accent_box(slot.get_theme_stylebox("panel", &"PanelRow"), accent))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UITokens.SPACE_8)

	var frame := PanelContainer.new()
	frame.theme_type_variation = &"PanelInset"
	var frame_box: StyleBox = UITokens.accent_box(frame.get_theme_stylebox("panel", &"PanelInset"), accent)
	frame_box.set_content_margin_all(UITokens.SPACE_4)
	frame.add_theme_stylebox_override("panel", frame_box)
	var icon_rect := TextureRect.new()
	icon_rect.name = "Icon"
	icon_rect.custom_minimum_size = SLOT_ICON
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if player_god != null:
		icon_rect.texture = player_god.icon
	frame.add_child(icon_rect)
	hbox.add_child(frame)

	var bandana := BandanaSwatch.mark(int(Network.player_bandanas.get(player_id, 0)))
	bandana.name = "Bandana"
	hbox.add_child(bandana)

	var label = Label.new()
	label.text = str(connected_players[player_id])
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hbox.add_child(label)

	# Add host indicator
	if int(player_id) == 1:
		var plate := PanelContainer.new()
		plate.theme_type_variation = &"Nameplate"
		plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var host_label := Label.new()
		host_label.text = "HOST"
		host_label.add_theme_color_override("font_color", UITokens.GOLD)
		plate.add_child(host_label)
		hbox.add_child(plate)
	if int(player_id) == multiplayer.get_unique_id():
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", UITokens.SPACE_8)
		column.add_child(hbox)
		column.add_child(_bandana_picker(int(player_id)))
		slot.add_child(column)
	else:
		slot.add_child(hbox)
	return slot


# YOUR bandana: one swatch per colour. A colour another player holds is locked
# (greyed, a padlock, tooltip says who); the one you wear has the gold frame.
func _bandana_picker(player_id: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "BandanaPicker"
	row.add_theme_constant_override("separation", UITokens.SPACE_8)
	var caption := Label.new()
	caption.text = "BANDANA"
	caption.theme_type_variation = &"CaptionLabel"
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption)
	var mine := int(Network.player_bandanas.get(player_id, 0))
	for index in range(UITokens.BANDANA_COLORS.size()):
		var holder := 0
		for other in Network.player_bandanas.keys():
			if int(Network.player_bandanas[other]) == index:
				holder = int(other)
		var taken := holder != 0 and holder != player_id
		var swatch := BandanaSwatch.new()
		swatch.name = "Color%d" % index
		swatch.setup(index, taken, index == mine, str(connected_players.get(holder, "another player")))
		swatch.focus_mode = Control.FOCUS_ALL
		swatch.pressed.connect(_on_bandana_picked.bind(index))
		row.add_child(swatch)
	return row


func _on_bandana_picked(index: int) -> void:
	Network.choose_bandana_color(index)


func _empty_slot() -> PanelContainer:
	var slot := PanelContainer.new()
	slot.theme_type_variation = &"PanelEmpty"
	slot.custom_minimum_size.y = SLOT_ICON.y + 24
	var label := Label.new()
	label.text = EMPTY_TEXT
	label.theme_type_variation = &"MutedLabel"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot.add_child(label)
	return slot


# The icon picker: one toggle per god that has an icon, exactly one pressed.
func _populate_god_icons() -> void:
	for child in god_icon_row.get_children():
		god_icon_row.remove_child(child)
		child.queue_free()
	god_icon_buttons.clear()
	var group := ButtonGroup.new()
	var selected_id := Network.my_god_icon_id
	for god in Gods.all():
		if god.icon == null:
			continue
		var button := Button.new()
		button.theme_type_variation = &"IconButton"
		button.custom_minimum_size = UITokens.BUTTON_ICON_LARGE
		button.icon = god.icon
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.toggle_mode = true
		button.button_group = group
		button.tooltip_text = "%s, %s" % [god.display_name, god.epithet]
		button.set_meta("god_id", god.id)
		button.button_pressed = god.id == selected_id
		button.pressed.connect(_on_god_icon_selected.bind(god_icon_buttons.size()))
		god_icon_row.add_child(button)
		god_icon_buttons.append(button)
	if god_icon_buttons.is_empty():
		return
	_show_god_icon(selected_id)


func _on_god_icon_selected(index: int) -> void:
	var god_id := StringName(str(god_icon_buttons[index].get_meta("god_id")))
	god_icon_buttons[index].set_pressed_no_signal(true)
	_show_god_icon(god_id)
	Network.choose_player_god_icon(god_id)


func _show_god_icon(god_id: StringName) -> void:
	var god := Gods.by_id(god_id)
	if god != null:
		god_icon_preview.texture = god.icon


func _on_player_god_icon_changed(peer_id: int, god_id: StringName) -> void:
	if peer_id == multiplayer.get_unique_id():
		_show_god_icon(god_id)
		for button in god_icon_buttons:
			if StringName(str(button.get_meta("god_id"))) == god_id:
				button.set_pressed_no_signal(true)
				break
	_update_player_list()
