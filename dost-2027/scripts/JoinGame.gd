extends Control

@onready var host_list = $CenterContainer/VBoxContainer/HostListScroll
@onready var host_list_vbox = $CenterContainer/VBoxContainer/HostListScroll/HostListVBox
@onready var refresh_button = $CenterContainer/VBoxContainer/RefreshButton
@onready var back_button = $CenterContainer/VBoxContainer/BackButton
@onready var status_label = $StatusLabel
@onready var search_spinner = $CenterContainer/VBoxContainer/SearchLabel
@onready var name_input = $CenterContainer/VBoxContainer/NameInput
@onready var lobby_id_input = $CenterContainer/VBoxContainer/LobbyIdInput
@onready var join_lobby_button = $CenterContainer/VBoxContainer/JoinLobbyButton

var host_items := {}  # host_key -> Button
var _search_timer: Timer

func _ready():
	# Connect button signals
	refresh_button.pressed.connect(_on_refresh_pressed)
	back_button.pressed.connect(_on_back_pressed)
	join_lobby_button.pressed.connect(_on_join_lobby_pressed)
	lobby_id_input.text_submitted.connect(_on_lobby_id_submitted)
	
	# Connect to network discovery signals
	Network.host_discovered.connect(_on_host_discovered)
	Network.host_lost.connect(_on_host_lost)
	Network.connected.connect(_on_network_connected)
	
	# Pre-fill with a random name suggestion
	name_input.text = Network.RANDOM_NAMES[randi() % Network.RANDOM_NAMES.size()]
	
	refresh_button.disabled = true
	status_label.text = "Scanning for hosts on LAN..."
	
	# Start LAN discovery automatically
	Network.start_discovery()
	
	# Refresh the host list periodically so new hosts appear automatically
	_search_timer = Timer.new()
	_search_timer.wait_time = 2.0
	_search_timer.one_shot = false
	add_child(_search_timer)
	_search_timer.timeout.connect(_on_search_timer_timeout)

func _on_search_timer_timeout():
	# Update the UI to match current discovered hosts
	_refresh_host_list()

func _on_refresh_pressed():
	_refresh_host_list()

func _on_back_pressed():
	Network.stop_discovery()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _on_host_discovered(_host_key: String, host_name: String, _ip: String, _port: int, _lobby_id: String):
	print("JoinGame: host discovered: %s" % host_name)
	_refresh_host_list()

func _on_host_lost(_host_key: String, _ip: String):
	print("JoinGame: host lost: %s" % _host_key)
	_refresh_host_list()

func _on_join_lobby_pressed():
	_join_by_lobby_id()

func _on_lobby_id_submitted(_text: String):
	_join_by_lobby_id()

func _join_by_lobby_id():
	var lobby_code: String = lobby_id_input.text.strip_edges()
	if lobby_code.is_empty():
		status_label.text = "Enter a lobby ID first"
		return
	
	# Save the chosen name before joining
	var chosen_name: String = name_input.text.strip_edges()
	if chosen_name.is_empty():
		chosen_name = Network.RANDOM_NAMES[randi() % Network.RANDOM_NAMES.size()]
	Network.set_my_name(chosen_name)
	
	status_label.text = "Looking for lobby %s..." % lobby_code.to_upper()
	refresh_button.disabled = true
	back_button.disabled = true
	join_lobby_button.disabled = true
	
	Network.join_lobby(lobby_code)

func _refresh_host_list():
	# Clear existing host entries immediately (not deferred) to prevent overlap
	for child in host_list_vbox.get_children():
		host_list_vbox.remove_child(child)
		child.queue_free()
	host_items.clear()
	
	var discovered = Network.get_discovered_hosts()
	
	if discovered.size() == 0:
		status_label.text = "No hosts found on LAN. Make sure the host started the game."
		search_spinner.visible = true
		search_spinner.text = "Scanning for hosts..."
		return
	
	search_spinner.visible = false
	
	var hosts := []
	var seen_lobbies := {}  # lobby_id (uppercase) -> true, UI-level dedupe
	for host_key in discovered.keys():
		var info = discovered[host_key]
		var lobby_id := str(info.get("lobby_id", ""))
		# Skip duplicate entries for the same lobby (same host via multiple adapters)
		if lobby_id != "":
			var lid_key := lobby_id.to_upper()
			if seen_lobbies.has(lid_key):
				continue
			seen_lobbies[lid_key] = true
		hosts.append({
			"key": host_key,
			"ip": str(info["ip"]),
			"name": str(info["name"]),
			"lobby_id": lobby_id,
		})
	
	status_label.text = "Found %d host(s) on LAN - tap to join" % hosts.size()
	
	# Sort by host name for a clean list
	hosts.sort_custom(func(a, b): return a["name"].to_lower() < b["name"].to_lower())
	
	for host_info in hosts:
		var host_key = host_info["key"]
		var ip = host_info["ip"]
		var name = host_info["name"]
		var lobby_id = host_info["lobby_id"]
		
		var button = Button.new()
		button.custom_minimum_size = Vector2(420, 48)
		button.text = name
		if lobby_id != "":
			button.text += "  [%s]" % lobby_id
		button.tooltip_text = "Join %s (%s) - Lobby ID: %s" % [name, ip, lobby_id]
		button.pressed.connect(_on_host_pressed.bind(host_key))
		button.add_theme_font_size_override("font_size", 16)
		host_list_vbox.add_child(button)
		host_items[host_key] = button

func _on_host_pressed(host_key: String):
	var discovered = Network.get_discovered_hosts()
	if not discovered.has(host_key):
		status_label.text = "That host is no longer available"
		return
	var info = discovered[host_key]
	
	# Save the chosen name before joining
	var chosen_name: String = name_input.text.strip_edges()
	if chosen_name.is_empty():
		chosen_name = Network.RANDOM_NAMES[randi() % Network.RANDOM_NAMES.size()]
	Network.set_my_name(chosen_name)
	
	status_label.text = "Connecting to %s..." % str(info["name"])
	refresh_button.disabled = true
	back_button.disabled = true
	join_lobby_button.disabled = true
	
	# Join the host using the discovered IP and port
	Network.join_host(str(info["ip"]), int(info["port"]))

func _on_network_connected(success: bool, reason: String):
	refresh_button.disabled = false
	back_button.disabled = false
	join_lobby_button.disabled = false
	
	if success:
		Network.stop_discovery()
		status_label.text = "Connected successfully!"
		# Switch to lobby scene
		get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
	else:
		match reason:
			"lobby_not_found":
				status_label.text = "Lobby not found. Check the ID and try again."
			"invalid_lobby_id":
				status_label.text = "Please enter a valid lobby ID."
			"resolving_lobby_id":
				status_label.text = "Searching for lobby... (keep this screen open)"
			_:
				status_label.text = "Connection failed: " + reason