extends Control

@onready var host_list = $CenterContainer/VBoxContainer/HostListScroll
@onready var host_list_vbox = $CenterContainer/VBoxContainer/HostListScroll/HostListVBox
@onready var refresh_button = $CenterContainer/VBoxContainer/RefreshButton
@onready var back_button = $CenterContainer/VBoxContainer/BackButton
@onready var status_label = $StatusLabel
@onready var search_spinner = $CenterContainer/VBoxContainer/SearchLabel

var host_items := {}  # ip -> Button
var _search_timer: Timer

func _ready():
	# Connect button signals
	refresh_button.pressed.connect(_on_refresh_pressed)
	back_button.pressed.connect(_on_back_pressed)
	
	# Connect to network discovery signals
	Network.host_discovered.connect(_on_host_discovered)
	Network.host_lost.connect(_on_host_lost)
	Network.connected.connect(_on_network_connected)
	
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

func _on_host_discovered(host_name: String, ip: String):
	print("JoinGame: host discovered: %s at %s" % [host_name, ip])
	_refresh_host_list()

func _on_host_lost(ip: String):
	print("JoinGame: host lost: %s" % ip)
	_refresh_host_list()

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
	
	# Deduplicate by host name - the same host may be discovered via multiple
	# broadcast destinations (255.255.255.255 + subnet broadcast) and unicast responses
	var seen_names := {}
	var hosts := []
	for ip in discovered.keys():
		var name = str(discovered[ip]["name"])
		var name_key = name.to_lower()
		if seen_names.has(name_key):
			continue  # skip duplicate host with same name
		seen_names[name_key] = true
		hosts.append({"ip": ip, "name": name})
	
	status_label.text = "Found %d host(s) on LAN - tap to join" % hosts.size()
	
	# Sort by host name for a clean list
	hosts.sort_custom(func(a, b): return a["name"].to_lower() < b["name"].to_lower())
	
	for host_info in hosts:
		var ip = host_info["ip"]
		var name = host_info["name"]
		
		var button = Button.new()
		button.custom_minimum_size = Vector2(360, 48)
		button.text = name
		button.tooltip_text = "Join %s (%s)" % [name, ip]
		button.pressed.connect(_on_host_pressed.bind(ip, name))
		button.add_theme_font_size_override("font_size", 16)
		host_list_vbox.add_child(button)
		host_items[ip] = button

func _on_host_pressed(ip: String, host_name: String):
	status_label.text = "Connecting to %s..." % host_name
	refresh_button.disabled = true
	back_button.disabled = true
	
	# Join the host - auto uses the discovered IP on the LAN
	Network.join_host(ip)

func _on_network_connected(success: bool, reason: String):
	refresh_button.disabled = false
	back_button.disabled = false
	
	if success:
		Network.stop_discovery()
		status_label.text = "Connected successfully!"
		# Switch to lobby scene
		get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
	else:
		status_label.text = "Connection failed: " + reason