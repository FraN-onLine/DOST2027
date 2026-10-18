extends Control

# Join a game: the same form card as Hosting (name, lobby ID, the gold primary)
# beside a card listing the games found on the LAN as row cards, each with its
# own JOIN. While the list is empty it says so - "Searching your network..." with
# slow dots - next to REFRESH, so an empty list never looks broken.

const SEARCH_TEXT := "Searching your network"
const DOT_SECONDS := 0.6

@onready var host_list = $CenterContainer/Columns/NetworkCard/VBox/List/HostListScroll
@onready var host_list_vbox = $CenterContainer/Columns/NetworkCard/VBox/List/HostListScroll/HostListVBox
@onready var no_hosts_label = $CenterContainer/Columns/NetworkCard/VBox/List/NoHostsLabel
@onready var refresh_button = $CenterContainer/Columns/NetworkCard/VBox/SearchRow/RefreshButton
@onready var back_button = $BackButton
@onready var status_label = $StatusLabel
@onready var search_spinner = $CenterContainer/Columns/NetworkCard/VBox/SearchRow/SearchLabel
@onready var name_input = $CenterContainer/Columns/FormCard/VBox/NameInput
@onready var lobby_id_input = $CenterContainer/Columns/FormCard/VBox/LobbyIdInput
@onready var join_lobby_button = $CenterContainer/Columns/FormCard/VBox/JoinLobbyButton

var host_items := {}  # host_key -> PanelContainer (one row card)
var _search_timer: Timer
var _dots := 0
var _searching := true

func _ready():
	# Connect button signals
	refresh_button.pressed.connect(_on_refresh_pressed)
	back_button.pressed.connect(_on_back_pressed)
	join_lobby_button.pressed.connect(_on_join_lobby_pressed)
	lobby_id_input.text_submitted.connect(_on_lobby_id_submitted)
	lobby_id_input.text_changed.connect(_on_lobby_id_changed)
	
	# Connect to network discovery signals
	Network.host_discovered.connect(_on_host_discovered)
	Network.host_lost.connect(_on_host_lost)
	Network.connected.connect(_on_network_connected)
	
	# Pre-fill with a random name suggestion
	name_input.text = Settings.suggested_name()

	refresh_button.disabled = true
	status_label.text = ""
	
	# Start LAN discovery automatically
	Network.start_discovery()
	
	# Build the list (or the "no hosts" message) right away instead of waiting for the first scan tick
	_refresh_host_list()
	
	# Refresh the host list periodically so new hosts appear automatically
	_search_timer = Timer.new()
	_search_timer.wait_time = 2.0
	_search_timer.one_shot = false
	add_child(_search_timer)
	_search_timer.timeout.connect(_on_search_timer_timeout)

	# The empty state's dots: slow, and still (no motion) with reduce flashing on.
	var dot_timer := Timer.new()
	dot_timer.wait_time = DOT_SECONDS
	dot_timer.autostart = true
	add_child(dot_timer)
	dot_timer.timeout.connect(_tick_dots)
	_tick_dots()
	name_input.grab_focus()

func _tick_dots() -> void:
	if not _searching:
		return
	_dots = (_dots + 1) % 4
	search_spinner.text = SEARCH_TEXT + ("..." if Settings.reduce_flashing() else ".".repeat(_dots))

# A lobby ID is four capitals: type it in any case, read it in capitals.
func _on_lobby_id_changed(text: String) -> void:
	var upper := text.to_upper()
	if upper != text:
		var caret: int = lobby_id_input.caret_column
		lobby_id_input.text = upper
		lobby_id_input.caret_column = caret

# Esc means back, on every screen.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not back_button.disabled:
		get_viewport().set_input_as_handled()
		_on_back_pressed()

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
		# Nothing to list - show the "no hosts" message inside the list area instead of a long status line
		_show_host_list(false)
		_searching = true
		status_label.text = ""
		return
	
	_show_host_list(true)
	_searching = false
	
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
	
	status_label.text = "Found %d host(s) on LAN - press JOIN" % hosts.size()
	search_spinner.text = "%d game%s found" % [hosts.size(), "" if hosts.size() == 1 else "s"]
	
	# Sort by host name for a clean list
	hosts.sort_custom(func(a, b): return a["name"].to_lower() < b["name"].to_lower())
	
	for host_info in hosts:
		var host_key = host_info["key"]
		var ip = host_info["ip"]
		var name = host_info["name"]
		var lobby_id = host_info["lobby_id"]
		
		var row := _host_row(name, lobby_id)
		row.tooltip_text = "Join %s (%s) - Lobby ID: %s" % [name, ip, lobby_id]
		row.get_node("Items/Join").pressed.connect(_on_host_pressed.bind(host_key))
		host_list_vbox.add_child(row)
		host_items[host_key] = row

# One discovered game: its host's name, its lobby ID (the discovery packet does
# not carry a player count) and a JOIN button at the right, where the eye ends.
func _host_row(host_name: String, lobby_id: String) -> PanelContainer:
	var row := PanelContainer.new()
	row.theme_type_variation = &"PanelRow"
	var items := HBoxContainer.new()
	items.name = "Items"
	items.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = host_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	items.add_child(name_label)
	if lobby_id != "":
		var code := Label.new()
		code.text = lobby_id
		code.theme_type_variation = &"MutedLabel"
		code.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		items.add_child(code)
	var join := Button.new()
	join.name = "Join"
	join.text = "JOIN"
	join.theme_type_variation = &"SmallButton"
	join.custom_minimum_size = UITokens.BUTTON_SMALL
	items.add_child(join)
	row.add_child(items)
	return row

func _show_host_list(has_hosts: bool):
	# Swap between the scrollable host list and the "no hosts" message
	host_list.visible = has_hosts
	no_hosts_label.visible = not has_hosts

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
