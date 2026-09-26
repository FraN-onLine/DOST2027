extends Node

# ============================================
# LAN Lobby Network + Lobby ID joining
# ============================================

const DEFAULT_PORT := 12345
const DISCOVERY_PORT := 12346
const DISCOVERY_PORT_RANGE := 10
const DISCOVERY_INTERVAL := 1.0
const DISCOVERY_TIMEOUT_MS := 5000
const LOBBY_JOIN_TIMEOUT_MS := 4000
const MAX_PLAYERS := 4
const MIN_PLAYERS_TO_START := 2

const LOBBY_ID_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

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
signal host_discovered(host_key, host_name, ip, port, lobby_id)
signal host_lost(host_key, ip)
signal player_stats_updated(player_stats)

# --- God's Games (Bathala) ---
signal god_games_started
signal god_state_received(state)          # host -> clients: absolute FAVOR snapshot
signal god_favor_requested(peer_id, amount, reason)
signal god_skill_requested(peer_id, slot)
signal god_grant_requested(peer_id, favor_id)
signal arena_layout_received(layout)      # host -> clients: field / corners / clones
signal arena_state_received(state)        # host -> clients: 10 Hz world tick
signal dialogue_released(dialogue_id)

var host_name := "Host"
var my_name := "" # The name the user chose before hosting/joining
var lobby_id := "" # Short code used to join a specific host
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
var _host_listen_port := DISCOVERY_PORT
var _discovered_hosts := {}  # "ip:discovery_port" -> {name, ip, port, lobby_id, discovery_port, last_seen}
var god_state := {}         # peer_id -> {favor, due, favors, cooldowns, ...} (host: authoritative)
var mortal_positions := {}  # peer_id -> Vector2 (host: latest reported position)
var _discovery_active := false
var _is_host_broadcasting := false
var _game_in_progress := false
var _dialogue_done := {}

# --- Lobby ID join state ---
var _pending_lobby_join_id := ""
var _pending_lobby_join_timer: Timer = null

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
	_game_in_progress = false

	# Use the name the user entered (or a random one if empty)
	var host_id := multiplayer.get_unique_id()
	var name := my_name
	if name.is_empty():
		name = _assign_random_name()
	players[host_id] = name
	host_name = name
	_used_names[name] = true
	player_data[host_id] = PlayerData.new(name)

	# Create a short, human-friendly lobby ID so friends can join directly
	lobby_id = _generate_lobby_id()

	broadcast_player_list()
	start_host_discovery()

	print("========================================")
	print("Server started on port %d" % port)
	print("Host name: %s" % name)
	print("Lobby ID: %s" % lobby_id)
	print("Broadcasting presence on LAN (port %d)..." % _host_listen_port)
	print("========================================")
	emit_signal("connected", true, "host_started")


func stop_host() -> void:
	stop_host_discovery()
	_cancel_lobby_join()
	lobby_id = ""
	_game_in_progress = false
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


func join_lobby(lobby_id_to_join: String) -> void:
	var clean_id := lobby_id_to_join.strip_edges().to_upper()
	if clean_id.is_empty():
		emit_signal("connected", false, "invalid_lobby_id")
		return

	# Make sure discovery is running so we can hear the host's reply
	if not _discovery_active:
		start_discovery()

	# If we already discovered a host with this lobby ID, join immediately
	for host_key in _discovered_hosts.keys():
		var info: Dictionary = _discovered_hosts[host_key]
		if str(info.get("lobby_id", "")).to_upper() == clean_id:
			_cancel_lobby_join()
			join_host(str(info["ip"]), int(info["port"]))
			return

	# Otherwise broadcast a resolve request and wait for the matching host
	_pending_lobby_join_id = clean_id
	_start_lobby_join_timeout()
	_send_lobby_resolve_request(clean_id)
	print("[Network] Looking for lobby ID: %s" % clean_id)
	emit_signal("connected", false, "resolving_lobby_id")


func leave_host() -> void:
	stop_host_discovery()
	_cancel_lobby_join()
	lobby_id = ""
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
		peer = null
		players.clear()
		player_stats.clear()
		player_data.clear()
		print("Left host / disconnected")


# ============================================
# Lobby ID Join (pending resolve)
# ============================================

func _start_lobby_join_timeout() -> void:
	_cancel_lobby_join()
	_pending_lobby_join_timer = Timer.new()
	_pending_lobby_join_timer.wait_time = float(LOBBY_JOIN_TIMEOUT_MS) / 1000.0
	_pending_lobby_join_timer.one_shot = true
	add_child(_pending_lobby_join_timer)
	_pending_lobby_join_timer.timeout.connect(_on_lobby_join_timeout)
	_pending_lobby_join_timer.start()


func _cancel_lobby_join() -> void:
	_pending_lobby_join_id = ""
	if _pending_lobby_join_timer:
		_pending_lobby_join_timer.stop()
		_pending_lobby_join_timer.queue_free()
		_pending_lobby_join_timer = null


func _on_lobby_join_timeout() -> void:
	if _pending_lobby_join_id != "":
		print("[Network] Lobby not found: %s" % _pending_lobby_join_id)
		_pending_lobby_join_id = ""
		_pending_lobby_join_timer = null
		emit_signal("connected", false, "lobby_not_found")


func _send_lobby_resolve_request(lobby_id_to_find: String) -> void:
	var msg := "DOST_LEVELUP_RESOLVE|%s" % lobby_id_to_find
	_udp_broadcast_message(msg)


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


func _generate_lobby_id() -> String:
	var id := ""
	var alphabet := LOBBY_ID_ALPHABET
	id += alphabet[randi() % alphabet.length()]
	id += alphabet[randi() % alphabet.length()]
	id += alphabet[randi() % alphabet.length()]
	id += alphabet[randi() % alphabet.length()]
	return id


# ============================================
# LAN Host Discovery (UDP broadcast)
# ============================================

func get_discovered_hosts() -> Dictionary:
	return _discovered_hosts.duplicate()


func _discovery_port_range() -> Array:
	var ports := []
	for p in range(DISCOVERY_PORT, DISCOVERY_PORT + DISCOVERY_PORT_RANGE):
		ports.append(p)
	return ports


func start_host_discovery() -> void:
	if _is_host_broadcasting:
		return
	_is_host_broadcasting = true

	# Bind a unique discovery port so multiple hosts on the same machine/LAN
	# can all respond to discovery requests instead of only the first one.
	_host_listen_port = DISCOVERY_PORT
	var bind_ok := false
	for attempt in range(DISCOVERY_PORT_RANGE):
		_host_listen_udp = PacketPeerUDP.new()
		var err := _host_listen_udp.bind(_host_listen_port)
		if err == OK:
			bind_ok = true
			break
		_host_listen_udp = null
		_host_listen_port += 1
	if not bind_ok:
		push_warning("Failed to bind any host discovery listen port!")
		_host_listen_udp = null
		_is_host_broadcasting = false
		return

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
	print("[Network] Host discovery broadcasting started (name: %s, listen port: %d)" % [host_name, _host_listen_port])


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


func _host_presence_message() -> String:
	return "DOST_LEVELUP_HOST|%s|%d|%d|%s" % [host_name, _current_port, _host_listen_port, lobby_id]


func _broadcast_host_presence() -> void:
	if not _is_host_broadcasting:
		return
	# Include the game port + discovery listen port + lobby ID so clients know
	# how to join, where to find this specific host, and what code to share.
	var msg := _host_presence_message()
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


func _respond_host_presence(request_ip: String, request_port: int) -> void:
	var udp := PacketPeerUDP.new()
	var err := udp.set_dest_address(request_ip, request_port)
	if err == OK:
		udp.put_packet((_host_presence_message()).to_utf8_buffer())
	udp.close()
	print("[Network] Responded to discovery request from %s:%d" % [request_ip, request_port])


func _process_host_discovery_requests() -> void:
	if not _is_host_broadcasting or not _host_listen_udp:
		return
	while _host_listen_udp.get_available_packet_count() > 0:
		var packet := _host_listen_udp.get_packet()
		var from_ip := _host_listen_udp.get_packet_ip()
		var from_port := _host_listen_udp.get_packet_port()
		var data := packet.get_string_from_utf8()
		if data == "DOST_LEVELUP_DISCOVER":
			_respond_host_presence(from_ip, from_port)
		elif data.begins_with("DOST_LEVELUP_RESOLVE|"):
			var requested_id := data.get_slice("|", 1).strip_edges().to_upper()
			if requested_id == lobby_id.to_upper() and not lobby_id.is_empty():
				_respond_host_presence(from_ip, from_port)
				print("[Network] Lobby resolve match for '%s'" % lobby_id)


func start_discovery() -> void:
	if _discovery_active:
		_udp_broadcast_message("DOST_LEVELUP_DISCOVER")
		return
	_discovery_active = true
	_discovered_hosts.clear()

	_discovery_udp = PacketPeerUDP.new()
	var err := _discovery_udp.bind(DISCOVERY_PORT)
	if err != OK:
		# Another local process already owns the port (e.g. a second client on
		# the same machine or a host). Fall back to an ephemeral port - the
		# request/response flow still works because hosts reply to our source
		# port directly.
		_discovery_udp = PacketPeerUDP.new()
		err = _discovery_udp.bind(0)
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
	_cancel_lobby_join()
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


func _udp_broadcast_message(msg: String) -> void:
	if not _discovery_active or not _discovery_udp:
		return
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
	_discovery_udp.set_broadcast_enabled(true)
	for dest in destinations:
		# Probe every host discovery port so hosts that had to pick a higher
		# unique port on this machine still receive the request.
		for p in _discovery_port_range():
			var err := _discovery_udp.set_dest_address(dest, p)
			if err == OK:
				_discovery_udp.put_packet(payload)


func _send_discovery_request() -> void:
	if not _discovery_active or not _discovery_udp:
		return
	_udp_broadcast_message("DOST_LEVELUP_DISCOVER")


func _process_discovery_packets() -> void:
	if not _discovery_active or not _discovery_udp:
		return
	var now := Time.get_ticks_msec()
	while _discovery_udp.get_available_packet_count() > 0:
		var packet := _discovery_udp.get_packet()
		var from_ip := _discovery_udp.get_packet_ip()
		var from_port := _discovery_udp.get_packet_port()
		var data := packet.get_string_from_utf8()
		if data.begins_with("DOST_LEVELUP_HOST|"):
			var parts := data.split("|")
			var host_name_from_packet := parts[1] if parts.size() > 1 else "Host"
			var host_port := int(parts[2]) if parts.size() > 2 else DEFAULT_PORT
			var host_disc_port := int(parts[3]) if parts.size() > 3 else from_port
			var host_lobby := parts[4] if parts.size() > 4 else ""
			# Key by ip+discovery port so hosts on the same IP don't overwrite
			var host_key := "%s:%d" % [from_ip, host_disc_port]
			if not _discovered_hosts.has(host_key):
				_discovered_hosts[host_key] = {
					"name": host_name_from_packet,
					"ip": from_ip,
					"port": host_port,
					"lobby_id": host_lobby,
					"discovery_port": host_disc_port,
					"last_seen": now,
				}
				print("[Network] Discovered host: %s (%s) at %s:%d" % [host_name_from_packet, host_lobby, from_ip, host_port])
				emit_signal("host_discovered", host_key, host_name_from_packet, from_ip, host_port, host_lobby)
			else:
				_discovered_hosts[host_key]["last_seen"] = now
				_discovered_hosts[host_key]["name"] = host_name_from_packet
				_discovered_hosts[host_key]["port"] = host_port
				_discovered_hosts[host_key]["lobby_id"] = host_lobby

			# If we're waiting to join by lobby ID and this host matches, connect now
			if _pending_lobby_join_id != "" and host_lobby.to_upper() == _pending_lobby_join_id:
				_pending_lobby_join_id = ""
				if _pending_lobby_join_timer:
					_pending_lobby_join_timer.stop()
					_pending_lobby_join_timer.queue_free()
					_pending_lobby_join_timer = null
				print("[Network] Lobby '%s' found, connecting to %s:%d..." % [host_lobby, from_ip, host_port])
				join_host(from_ip, host_port)

	# Deduplicate: a host can broadcast from multiple network interfaces
	# (different source IPs), producing several keys for the same lobby.
	# Keep only the first-seen key per lobby ID so one host shows once.
	var seen_lobby_ids := {}
	var duplicate_keys := []
	for host_key in _discovered_hosts.keys():
		var lid := str(_discovered_hosts[host_key].get("lobby_id", ""))
		if lid == "":
			continue
		var lid_upper := lid.to_upper()
		if seen_lobby_ids.has(lid_upper):
			duplicate_keys.append(host_key)
		else:
			seen_lobby_ids[lid_upper] = true
	for dup_key in duplicate_keys:
		var removed_ip := str(_discovered_hosts.get(dup_key, {}).get("ip", ""))
		_discovered_hosts.erase(dup_key)
		print("[Network] Removed duplicate host entry: %s" % dup_key)
		emit_signal("host_lost", dup_key, removed_ip)

	var to_remove := []
	for host_key in _discovered_hosts.keys():
		if now - int(_discovered_hosts[host_key]["last_seen"]) > DISCOVERY_TIMEOUT_MS:
			to_remove.append(host_key)
	for host_key in to_remove:
		var info: Dictionary = _discovered_hosts[host_key]
		var removed_ip := str(info.get("ip", ""))
		_discovered_hosts.erase(host_key)
		print("[Network] Host lost: %s" % host_key)
		emit_signal("host_lost", host_key, removed_ip)


# ============================================
# Multiplayer Events
# ============================================

func _on_peer_connected(id: int) -> void:
	print("Peer connected: %d" % id)
	if multiplayer.is_server():
		if _game_in_progress:
			print("Game already in progress. Rejecting peer %d" % id)
			if peer:
				peer.disconnect_peer(id)
			return
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

	# A game session has started - stop advertising this lobby on the LAN so
	# unrelated clients no longer see it or receive game RPC broadcasts.
	_game_in_progress = true
	stop_host_discovery()
	_discovered_hosts.clear()

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


# ============================================
# God's Games (Bathala) - FAVOR stays server-authoritative
# ============================================

func has_multiplayer_peer() -> bool:
	# Godot hands out an OfflineMultiplayerPeer when nothing is connected, so a
	# plain null check is not enough.
	var peer := multiplayer.get_multiplayer_peer()
	return peer != null and not (peer is OfflineMultiplayerPeer)


func is_game_host() -> bool:
	return not has_multiplayer_peer() or multiplayer.is_server()


# --- lobby -> God's Games ---------------------------------------------------

func start_god_games(scene_path := "res://scenes/Game.tscn") -> void:
	# Host-only, mirrors start_game(): every peer drops into Bathala's games.
	if has_multiplayer_peer() and not multiplayer.is_server():
		return
	if players.is_empty():
		push_warning("No players to start the God's Games")
		return
	print("[Network] Starting the God's Games with %d player(s)" % players.size())
	_game_in_progress = true
	stop_host_discovery()
	_discovered_hosts.clear()
	god_state.clear()
	mortal_positions.clear()
	for pid in players.keys():
		god_state[int(pid)] = {
			"favor": 0, "due": 0, "favors": [], "cooldowns": {},
			"durations": {}, "immunity": 0.0, "pending": 0.0, "claimed": {},
		}
	if has_multiplayer_peer():
		rpc("rpc_change_scene", scene_path)
	emit_signal("god_games_started")
	get_tree().change_scene_to_file(scene_path)


# --- FAVOR snapshots (host -> everyone) -------------------------------------

func publish_god_state(state: Dictionary) -> void:
	god_state = state.duplicate(true)
	if has_multiplayer_peer():
		rpc("rpc_god_state", god_state)


@rpc("any_peer", "reliable")
func rpc_god_state(remote_state: Dictionary) -> void:
	if multiplayer.is_server():
		return
	god_state = remote_state.duplicate(true)
	emit_signal("god_state_received", god_state)


@rpc("any_peer", "reliable")
func request_god_state() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		emit_signal("god_state_received", god_state)
	elif has_multiplayer_peer():
		rpc_id(sender, "rpc_god_state", god_state)


# --- client intents (client -> host) ----------------------------------------

@rpc("any_peer", "reliable")
func request_god_favor_add(amount: int, reason: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	emit_signal("god_favor_requested", sender, amount, reason)


@rpc("any_peer", "reliable")
func request_god_skill(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	emit_signal("god_skill_requested", sender, slot)


@rpc("any_peer", "reliable")
func request_god_grant(favor_id: StringName) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	emit_signal("god_grant_requested", sender, favor_id)


# --- arena world sync -------------------------------------------------------

@rpc("any_peer", "reliable")
func report_dialogue_finished(dialogue_id: String) -> void:
	if not has_multiplayer_peer():
		return
	if multiplayer.is_server():
		var peer_id := multiplayer.get_remote_sender_id()
		if peer_id == 0:
			peer_id = multiplayer.get_unique_id()
		if not _dialogue_done.has(dialogue_id):
			_dialogue_done[dialogue_id] = {}
		_dialogue_done[dialogue_id][peer_id] = true
		_check_dialogue_complete(dialogue_id)
	else:
		rpc_id(1, "report_dialogue_finished", dialogue_id)


func dialogue_finished_count(dialogue_id: String) -> int:
	return _dialogue_done.get(dialogue_id, {}).size()


func _check_dialogue_complete(dialogue_id: String) -> void:
	if not multiplayer.is_server():
		return
	if dialogue_finished_count(dialogue_id) < players.size():
		return
	_dialogue_done.erase(dialogue_id)
	rpc("rpc_dialogue_release", dialogue_id)
	emit_signal("dialogue_released", dialogue_id)


func release_dialogue(dialogue_id: String) -> void:
	if not multiplayer.is_server():
		return
	_dialogue_done.erase(dialogue_id)
	rpc("rpc_dialogue_release", dialogue_id)
	emit_signal("dialogue_released", dialogue_id)


@rpc("any_peer", "reliable")
func rpc_dialogue_release(dialogue_id: String) -> void:
	_dialogue_done.erase(dialogue_id)
	emit_signal("dialogue_released", dialogue_id)

func publish_arena_layout(layout: Dictionary) -> void:
	if not has_multiplayer_peer():
		return
	rpc("rpc_arena_layout", layout)


@rpc("any_peer", "reliable")
func rpc_arena_layout(layout: Dictionary) -> void:
	if multiplayer.is_server():
		return
	emit_signal("arena_layout_received", layout)


func publish_arena_state(state: Dictionary) -> void:
	if not has_multiplayer_peer():
		return
	rpc("rpc_arena_state", state)


@rpc("any_peer", "unreliable_ordered")
func rpc_arena_state(state: Dictionary) -> void:
	if multiplayer.is_server():
		return
	emit_signal("arena_state_received", state)


@rpc("any_peer", "unreliable_ordered")
func report_mortal_position(position: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	mortal_positions[sender] = position
