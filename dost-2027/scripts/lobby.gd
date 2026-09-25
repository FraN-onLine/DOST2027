extends Control

@onready var player_list_vbox = $CenterContainer/VBoxContainer/PlayerListScroll/PlayerListVBox
@onready var name_input = $CenterContainer/VBoxContainer/NameInput
@onready var change_name_button = $CenterContainer/VBoxContainer/ChangeNameButton
@onready var start_game_button = $CenterContainer/VBoxContainer/ButtonContainer/StartGameButton
@onready var god_games_button = $CenterContainer/VBoxContainer/ButtonContainer/GodGamesButton
@onready var leave_button = $CenterContainer/VBoxContainer/ButtonContainer/LeaveButton
@onready var status_label = $StatusLabel
@onready var lobby_id_label = $LobbyIdLabel

var connected_players = {}
var is_host = false

func _ready():
	# Connect button signals
	start_game_button.pressed.connect(_on_start_game_pressed)
	god_games_button.pressed.connect(_on_god_games_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	change_name_button.pressed.connect(_on_change_name_pressed)
	name_input.text_submitted.connect(_on_name_submitted)
	
	# Connect to network signals
	Network.player_joined.connect(_on_player_joined)
	Network.player_left.connect(_on_player_left)
	Network.player_list_updated.connect(_on_player_list_updated)
	
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
		god_games_button.visible = false
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

func _on_start_game_pressed():
	if is_host and connected_players.size() >= Network.MIN_PLAYERS_TO_START:
		Network.start_game()

func _on_god_games_pressed():
	# Bathala's God's Games - every mortal in the lobby drops into the arena.
	if is_host:
		Network.start_god_games()

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
		hbox.custom_minimum_size = Vector2(0, 28)
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