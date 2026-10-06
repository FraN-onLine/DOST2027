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
# The run setup: everyone reads it in one line under the roster, and OPTIONS opens
# the full panel (editable for the host, read-only for clients).
@onready var run_summary_label: Label = $CenterContainer/VBoxContainer/RunSummaryLabel
@onready var lobby_options = $LobbyOptions

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
	Network.run_settings_changed.connect(_on_run_settings_changed)
	
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
	_refresh_run_summary()


func _on_run_settings_changed(_settings: Dictionary) -> void:
	_refresh_run_summary()
	_update_start_button()


func _refresh_run_summary() -> void:
	run_summary_label.text = Network.run_settings.summary()


# START needs enough players AND a legal setup (no god twice in a row in a
# CUSTOM order) - the panel shows the warning, this keeps the button honest.
func _update_start_button() -> void:
	if not is_host:
		return
	start_game_button.disabled = connected_players.size() < Network.MIN_PLAYERS_TO_START 		or not Network.run_settings.problems().is_empty()


func _on_options_pressed() -> void:
	if lobby_options.visible:
		lobby_options.close()
	else:
		lobby_options.open(is_host)


func _on_start_game_pressed():
	if is_host and connected_players.size() >= Network.MIN_PLAYERS_TO_START and Network.run_settings.problems().is_empty():
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
		_update_start_button()
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
