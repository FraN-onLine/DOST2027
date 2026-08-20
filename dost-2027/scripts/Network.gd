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

var host_name := "Host"
var players := {} # peer_id -> name
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


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connection_succeeded)
	multiplayer.connection_failed.connect(_on_connection_failed)


# ============================================
# Hosting
# ============================================

func start_host(port: int = DEFAULT_PORT) -> void:
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Failed to create server: %s" % err)
		emit_signal("connected", false, "create_server_failed")
		return
	multiplayer.multiplayer_peer = peer

	# Assign the host a random name
	var host_id := multiplayer.get_unique_id()
	var name := _assign_random_name()
	players[host_id] = name
	host_name = name

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


func leave_host() -> void:
	stop_host_discovery()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
		peer = null
		players.clear()
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
	var msg := "DOST_LEVELUP_HOST|%s" % host_name
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
				var msg := "DOST_LEVELUP_HOST|%s" % host_name
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
			var host_name_from_packet := data.substr("DOST_LEVELUP_HOST|".length())
			if not _discovered_hosts.has(from_ip):
				_discovered_hosts[from_ip] = {"name": host_name_from_packet, "last_seen": now}
				print("[Network] Discovered host: %s at %s" % [host_name_from_packet, from_ip])
				emit_signal("host_discovered", host_name_from_packet, from_ip)
			else:
				_discovered_hosts[from_ip]["last_seen"] = now
				_discovered_hosts[from_ip]["name"] = host_name_from_packet
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
		players[id] = _assign_random_name()
		broadcast_player_list()
	emit_signal("player_joined", id)


func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	if multiplayer.is_server():
		if id in players:
			_release_name(players[id])
			players.erase(id)
			broadcast_player_list()
	emit_signal("player_left", id)


func _on_connection_succeeded() -> void:
	print("Connection succeeded")
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
	emit_signal("game_started")
