extends Node

# ============================================
# Stripped-down LAN Lobby Network
# ============================================

const DEFAULT_PORT := 12345
const DISCOVERY_PORT := 12346
const DISCOVERY_INTERVAL := 1.0
const DISCOVERY_TIMEOUT_MS := 5000
const MAX_PLAYERS := 4
const MIN_PLAYERS_TO_START := 2

const RANDOM_NAMES := [
	"SunnyReign",
	"TracerKhoi",
	"BrrBrrPataLin",
	"KingJames",
	"HackerMacoy",
]

signal player_joined(peer_id)
signal player_left(peer_id)
signal connected(success, reason)
signal player_list_updated(players)
signal game_started
signal host_discovered(host_name, ip)
signal host_lost(ip)
signal player_stats_updated(player_stats)

var host_name := "Host"
var my_name := "" # The name the user chose before hosting/joining
var players := {} # peer_id -> name
var player_stats := {} # peer_id -> {hp: int, attack: int} (client-side synced copy)
var player_data := {} # peer_id -> PlayerData (server-side authoritative)
var _used_names := {} # name -> true (server-side, to avoid duplicates)

# --- Discovery state ---
var _discovery_udp: PacketPeerUDP = null
var _discovery_listen_timer: Timer = null
var _discovery_broadcast_timer: Timer = null
var _discovery_request_timer: Timer = null
var _host_listen_udp: PacketPeerUDP = null
var _host_listen_timer: Timer = null
var _discovered_hosts := {}  # ip -> {name: String, last_seen: int}
var _discovery_active := false
var _is_host_broadcasting := false

var peer: ENetMultiplayerPeer
var _join_port := DEFAULT_PORT
var _current_port := DEFAULT_PORT


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connection_succeeded)
	multiplayer.connection_failed.connect(_on_connection_failed)


# ============================================
# Hosting
# ============================================

func set_my_name(name: String) -> void:
	my_name = name.strip_edges()
	if my_name.is_empty():
		my_name = _assign_random_name()


func start_host(port: int = DEFAULT_PORT) -> void:
	# If the requested port is taken, try the next few ports so multiple
	# hosts can run on the same machine/LAN simultaneously.
	var actual_port := port
	var err := ERR_ALREADY_IN_USE
	for attempt in range(10):
		peer = ENetMultiplayerPeer.new()
		err = peer.create_server(actual_port, MAX_PLAYERS)
		if err == OK:
			break
		actual_port += 1
	if err != OK:
		push_error("Failed to create server: %s" % err)
		emit_signal("connected", false, "create_server_failed")
		return
	port = actual_port
	multiplayer.multiplayer_peer = peer
	_current_port = port

	# Use the name the user entered (or a random one if empty)
	var host_id := multiplayer.get_unique_id()
	var name := my_name
	if name.is_empty():
		name = _assign_random_name()
	players[host_id] = name
	host_name = name
	_used_names[name] = true
	player_data[host_id] = PlayerData.new(name)

	broadcast_player_list()
	start_host_discovery()

	print("========================================")
	print("Server started on port %d" % port)
	print("Host name: %s" % name)
	print("Broadcasting presence on LAN (port %d)..." % DISCOVERY_PORT)
	print("========================================")
	emit_signal("connected", true, "host_started")


func stop_host() -> void:
	stop_host_discovery()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
		peer = null
		players.clear()
		player_stats.clear()
		player_data.clear()
		_used_names.clear()
		print("Server stopped")
		emit_signal("connected", false, "host_stopped")


# ============================================
# Joining
# ============================================

func join_host(ip: String, port: int = DEFAULT_PORT) -> void:
	peer = ENetMultiplayerPeer.new()
	print("========================================")
	print("Attempting to connect to %s:%d" % [ip, port])
	print("========================================")
	var err = peer.create_client(ip, port)
	if err != OK:
		push_error("Failed to create client: Error code %s" % err)
		emit_signal("connected", false, "create_client_failed")
		return
	multiplayer.multiplayer_peer = peer
	# Store the port we're joining so we can send our name after connecting
	_join_port = port


func leave_host() -> void:
	stop_host_discovery()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
		peer = null
		players.clear()
		player_stats.clear()
		player_data.clear()
		print("Left host / disconnected")


# ============================================
# Random Name Assignment
# ============================================

func _assign_random_name() -> String:
	# Pick a random name that isn't already in use
	var available := []
	for candidate in RANDOM_NAMES:
		if not _used_names.has(candidate):
			available.append(candidate)
	if available.is_empty():
		# All names taken - fall back to a numbered variant
		var base: String = RANDOM_NAMES[randi() % RANDOM_NAMES.size()]
		var suffix := 2
		while _used_names.has("%s%d" % [base, suffix]):
			suffix += 1
		var fallback := "%s%d" % [base, suffix]
		_used_names[fallback] = true
		return fallback
	var chosen: String = available[randi() % available.size()]
	_used_names[chosen] = true
	return chosen


func _release_name(name: String) -> void:
	_used_names.erase(name)


# ============================================
# LAN Host Discovery (UDP broadcast)
# ============================================

func get_discovered_hosts() -> Dictionary:
	return _discovered_hosts.duplicate()


func start_host_discovery() -> void:
	if _is_host_broadcasting:
		return
	_is_host_broadcasting = true

	_host_listen_udp = PacketPeerUDP.new()
	var err = _host_listen_udp.bind(DISCOVERY_PORT)
	if err != OK:
		push_warning("Failed to bind host discovery listen port %d: %s" % [DISCOVERY_PORT, err])
		_host_listen_udp = null

	_discovery_broadcast_timer = Timer.new()
	_discovery_broadcast_timer.wait_time = DISCOVERY_INTERVAL
	_discovery_broadcast_timer.one_shot = false
	add_child(_discovery_broadcast_timer)
	_discovery_broadcast_timer.timeout.connect(_broadcast_host_presence)
	_discovery_broadcast_timer.start()

	if _host_listen_udp:
		_host_listen_timer = Timer.new()
		_host_listen_timer.wait_time = 0.5
		_host_listen_timer.one_shot = false
		add_child(_host_listen_timer)
		_host_listen_timer.timeout.connect(_process_host_discovery_requests)
		_host_listen_timer.start()

	_broadcast_host_presence()
	print("[Network] Host discovery broadcasting started (name: %s)" % host_name)


func stop_host_discovery() -> void:
	_is_host_broadcasting = false
	if _discovery_broadcast_timer:
		_discovery_broadcast_timer.stop()
		_discovery_broadcast_timer.queue_free()
		_discovery_broadcast_timer = null
	if _host_listen_timer:
		_host_listen_timer.stop()
		_host_listen_timer.queue_free()
		_host_listen_timer = null
	if _host_listen_udp:
		_host_listen_udp.close()
		_host_listen_udp = null


func _broadcast_host_presence() -> void:
	if not _is_host_broadcasting:
		return
	# Include the game port so clients know which port to join
	var msg := "DOST_LEVELUP_HOST|%s|%d" % [host_name, _current_port]
	var payload := msg.to_utf8_buffer()
	var destinations := ["255.255.255.255"]
	for ip in IP.get_local_addresses():
		if typeof(ip) == TYPE_STRING and not ip.begins_with("127.") and ":" not in ip:
			var parts := ip.split(".")
			if parts.size() == 4:
				parts[3] = "255"
				var subnet_bcast := ".".join(parts)
				if subnet_bcast not in destinations:
					destinations.append(subnet_bcast)
	for dest in destinations:
		var udp := PacketPeerUDP.new()
		udp.set_broadcast_enabled(true)
		var err := udp.set_dest_address(dest, DISCOVERY_PORT)
		if err == OK:
			udp.put_packet(payload)
		udp.close()


func _process_host_discovery_requests() -> void:
	if not _is_host_broadcasting or not _host_listen_udp:
		return
	while _host_listen_udp.get_available_packet_count() > 0:
		var packet := _host_listen_udp.get_packet()
		var from_ip := _host_listen_udp.get_packet_ip()
		var from_port := _host_listen_udp.get_packet_port()
		var data := packet.get_string_from_utf8()
		if data == "DOST_LEVELUP_DISCOVER":
			var udp := PacketPeerUDP.new()
			var err := udp.set_dest_address(from_ip, from_port)
			if err == OK:
				var msg := "DOST_LEVELUP_HOST|%s|%d" % [host_name, _current_port]
				udp.put_packet(msg.to_utf8_buffer())
			udp.close()
			print("[Network] Responded to discovery request from %s:%d" % [from_ip, from_port])


func start_discovery() -> void:
	if _discovery_active:
		return
	_discovery_active = true
	_discovered_hosts.clear()
	_discovery_udp = PacketPeerUDP.new()
	var err := _discovery_udp.bind(0)
	if err != OK:
		push_error("Failed to bind discovery UDP: %s" % err)
		_discovery_active = false
		return
	_send_discovery_request()
	_discovery_listen_timer = Timer.new()
	_discovery_listen_timer.wait_time = 0.5
	_discovery_listen_timer.one_shot = false
	add_child(_discovery_listen_timer)
	_discovery_listen_timer.timeout.connect(_process_discovery_packets)
	_discovery_listen_timer.start()
	_discovery_request_timer = Timer.new()
	_discovery_request_timer.wait_time = 2.0
	_discovery_request_timer.one_shot = false
	add_child(_discovery_request_timer)
	_discovery_request_timer.timeout.connect(_send_discovery_request)
	_discovery_request_timer.start()
	print("[Network] LAN discovery started")


func stop_discovery() -> void:
	_discovery_active = false
	if _discovery_udp:
		_discovery_udp.close()
		_discovery_udp = null
	if _discovery_listen_timer:
		_discovery_listen_timer.stop()
		_discovery_listen_timer.queue_free()
		_discovery_listen_timer = null
	if _discovery_request_timer:
		_discovery_request_timer.stop()
		_discovery_request_timer.queue_free()
		_discovery_request_timer = null
	_discovered_hosts.clear()


func _send_discovery_request() -> void:
	if not _discovery_active or not _discovery_udp:
		return
	var payload := "DOST_LEVELUP_DISCOVER".to_utf8_buffer()
	var destinations := ["255.255.255.255"]
	for ip in IP.get_local_addresses():
		if typeof(ip) == TYPE_STRING and not ip.begins_with("127.") and ":" not in ip:
			var parts := ip.split(".")
			if parts.size() == 4:
				parts[3] = "255"
				var subnet_bcast := ".".join(parts)
				if subnet_bcast not in destinations:
					destinations.append(subnet_bcast)
	_discovery_udp.set_broadcast_enabled(true)
	for dest in destinations:
		var err := _discovery_udp.set_dest_address(dest, DISCOVERY_PORT)
		if err == OK:
			_discovery_udp.put_packet(payload)


func _process_discovery_packets() -> void:
	if not _discovery_active or not _discovery_udp:
		return
	var now := Time.get_ticks_msec()
	while _discovery_udp.get_available_packet_count() > 0:
		var packet := _discovery_udp.get_packet()
		var from_ip := _discovery_udp.get_packet_ip()
		var data := packet.get_string_from_utf8()
		if data.begins_with("DOST_LEVELUP_HOST|"):
			var parts := data.split("|")
			var host_name_from_packet := parts[1] if parts.size() > 1 else "Host"
			var host_port := int(parts[2]) if parts.size() > 2 else DEFAULT_PORT
			if not _discovered_hosts.has(from_ip):
				_discovered_hosts[from_ip] = {"name": host_name_from_packet, "port": host_port, "last_seen": now}
				print("[Network] Discovered host: %s at %s:%d" % [host_name_from_packet, from_ip, host_port])
				emit_signal("host_discovered", host_name_from_packet, from_ip)
			else:
				_discovered_hosts[from_ip]["last_seen"] = now
				_discovered_hosts[from_ip]["name"] = host_name_from_packet
				_discovered_hosts[from_ip]["port"] = host_port
	var to_remove := []
	for ip in _discovered_hosts.keys():
		if now - int(_discovered_hosts[ip]["last_seen"]) > DISCOVERY_TIMEOUT_MS:
			to_remove.append(ip)
	for ip in to_remove:
		_discovered_hosts.erase(ip)
		print("[Network] Host lost: %s" % ip)
		emit_signal("host_lost", ip)


# ============================================
# Multiplayer Events
# ============================================

func _on_peer_connected(id: int) -> void:
	print("Peer connected: %d" % id)
	if multiplayer.is_server():
		if players.size() >= MAX_PLAYERS:
			print("Max players reached (%d). Disconnecting peer %d" % [MAX_PLAYERS, id])
			if peer:
				peer.disconnect_peer(id)
			return
		# Assign a temporary name; the client will send their chosen name via RPC
		players[id] = _assign_random_name()
		player_data[id] = PlayerData.new()
		broadcast_player_list()
	emit_signal("player_joined", id)


@rpc("any_peer", "reliable")
func register_player_name(player_name: String) -> void:
	# Called by a client right after connecting to set their chosen name
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var clean_name := player_name.strip_edges()
	if clean_name.is_empty() or clean_name.length() > 16:
		clean_name = _assign_random_name()
	# Release the temporary name and claim the chosen one
	if sender in players:
		_release_name(players[sender])
	players[sender] = clean_name
	_used_names[clean_name] = true
	if sender in player_data:
		player_data[sender].name = clean_name
	broadcast_player_list()


func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	if multiplayer.is_server():
		if id in players:
			_release_name(players[id])
			players.erase(id)
			if id in player_data:
				player_data.erase(id)
			broadcast_player_list()
	emit_signal("player_left", id)


func _on_connection_succeeded() -> void:
	print("Connection succeeded")
	# Send our chosen name to the server so it's used instead of a random one
	if my_name.is_empty():
		my_name = _assign_random_name()
	rpc_id(1, "register_player_name", my_name)
	emit_signal("connected", true, "connected")


func _on_connection_failed() -> void:
	print("Connection failed")
	emit_signal("connected", false, "failed")


# ============================================
# Player List & Name Management
# ============================================

func broadcast_player_list() -> void:
	print("Broadcasting player list: %s" % players)
	emit_signal("player_list_updated", players)
	if multiplayer.get_multiplayer_peer():
		rpc("rpc_update_player_list", players)


@rpc("any_peer", "reliable")
func request_player_list() -> void:
	if not multiplayer.is_server():
		return
	broadcast_player_list()


@rpc("any_peer", "reliable")
func request_name_change(peer_id: int, new_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# Allow the server to change its own name (sender==0 when called locally)
	# Otherwise, only allow a player to change their own name
	if sender != 0 and sender != peer_id:
		push_warning("Player %d attempted to change name for %d" % [sender, peer_id])
		return
	var clean_name := new_name.strip_edges()
	if clean_name.is_empty() or clean_name.length() > 16:
		push_warning("Invalid name: '%s'" % clean_name)
		return
	# Release the old name and claim the new one
	if peer_id in players:
		_release_name(players[peer_id])
	players[peer_id] = clean_name
	_used_names[clean_name] = true
	if peer_id == multiplayer.get_unique_id():
		host_name = clean_name
	broadcast_player_list()


@rpc("any_peer", "reliable")
func rpc_update_player_list(remote_players: Dictionary) -> void:
	players = remote_players.duplicate()
	emit_signal("player_list_updated", players)
	print("[Network] Received player list update: %s" % players)


# ============================================
# Game Start
# ============================================

@rpc("any_peer", "call_local", "reliable")
func start_game() -> void:
	if not multiplayer.is_server():
		return
	if players.size() < MIN_PLAYERS_TO_START:
		push_warning("Need at least %d players to start (currently %d)" % [MIN_PLAYERS_TO_START, players.size()])
		return
	if players.size() > MAX_PLAYERS:
		push_warning("Too many players to start (currently %d)" % players.size())
		return
	print("[Network] Starting game with %d players" % players.size())

	# Initialize stats for all players
	for pid in players.keys():
		var pid_int := int(pid)
		if not player_data.has(pid_int):
			player_data[pid_int] = PlayerData.new()

	# Broadcast stats to all clients
	_broadcast_player_stats()

	# Change scene for everyone
	rpc("rpc_change_scene", "res://scenes/Game.tscn")
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

	emit_signal("game_started")


@rpc("any_peer", "reliable")
func rpc_change_scene(scene_path: String) -> void:
	if ResourceLoader.exists(scene_path):
		get_tree().change_scene_to_file(scene_path)


# ============================================
# Player Stats (server-authoritative)
# ============================================

func get_player_stats(peer_id: int) -> Dictionary:
	for pid in player_stats.keys():
		if int(pid) == peer_id:
			return player_stats[pid]
	return PlayerData.new().to_dict()


func update_player_stat(peer_id: int, stat_name: String, value: int) -> void:
	# Server-authoritative stat update + real-time broadcast
	if not multiplayer.is_server():
		return
	if stat_name not in ["hp", "attack"]:
		push_warning("Invalid stat name: %s" % stat_name)
		return
	var pd: PlayerData = null
	for pid in player_data.keys():
		if int(pid) == peer_id:
			pd = player_data[pid]
			break
	if pd == null:
		pd = PlayerData.new()
		player_data[peer_id] = pd
	match stat_name:
		"hp":
			pd.hp = max(0, value)
		"attack":
			pd.attack = max(0, value)
	_broadcast_player_stats()


@rpc("any_peer", "reliable")
func request_update_stat(peer_id: int, stat_name: String, value: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# Only allow players to modify their own stats
	if sender != 0 and sender != peer_id:
		push_warning("Player %d attempted to modify stats for %d" % [sender, peer_id])
		return
	update_player_stat(peer_id, stat_name, value)


@rpc("any_peer", "reliable")
func request_player_stats() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	# Send current stats directly to the requesting peer
	var serialized := {}
	for pid in player_data.keys():
		serialized[pid] = player_data[pid].to_dict()
	if sender == 0:
		# Local call (host)
		player_stats = serialized.duplicate()
		emit_signal("player_stats_updated", player_stats)
	else:
		rpc_id(sender, "rpc_broadcast_player_stats", serialized)


@rpc("any_peer", "reliable")
func rpc_broadcast_player_stats(remote_stats: Dictionary) -> void:
	player_stats = remote_stats.duplicate()
	emit_signal("player_stats_updated", player_stats)


func _broadcast_player_stats() -> void:
	var serialized := {}
	for pid in player_data.keys():
		serialized[pid] = player_data[pid].to_dict()
	rpc("rpc_broadcast_player_stats", serialized)
	call_deferred("rpc_broadcast_player_stats", serialized)
