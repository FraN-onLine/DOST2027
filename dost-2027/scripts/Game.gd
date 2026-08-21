extends Control

# Game HUD
# Shows own HP/Attack top-left, other players' HP/Attack in opponent panels.
# Stats are server-authoritative and broadcast in real time.

@onready var own_name_label = $TopLeft/VBoxContainer/NameLabel
@onready var own_hp_label = $TopLeft/VBoxContainer/StatsRow/HpValue
@onready var own_attack_label = $TopLeft/VBoxContainer/StatsRow/AttackValue
@onready var opponent_vbox = $OpponentPanelContainer/VBoxContainer

const OPPONENT_PANEL_SCENE := preload("res://UI/opponentpanels.tscn")

var opponent_panels := {} # peer_id -> PanelContainer

func _ready() -> void:
	# Connect to stat updates
	Network.player_stats_updated.connect(_on_player_stats_updated)

	# Ask server for current stats (or use local copy if host)
	if multiplayer.is_server():
		Network.request_player_stats()
	else:
		Network.rpc_id(1, "request_player_stats")

	# Build the HUD from the player list
	_build_hud()

func _build_hud() -> void:
	# Get my ID and name
	var my_id := multiplayer.get_unique_id()
	var my_name := "Player"
	if my_id in Network.players:
		my_name = str(Network.players[my_id])

	own_name_label.text = my_name

	# Clear existing opponent panels
	for child in opponent_vbox.get_children():
		opponent_vbox.remove_child(child)
		child.queue_free()
	opponent_panels.clear()

	# Create one panel per other player
	for pid in Network.players.keys():
		var id_int := int(pid)
		if id_int == my_id:
			continue
		var panel = OPPONENT_PANEL_SCENE.instantiate()
		var pname = str(Network.players[pid])
		opponent_vbox.add_child(panel)
		panel.setup(id_int, pname, 100, 10)
		opponent_panels[id_int] = panel

	# If there are no stats yet, use defaults
	_update_own_stats(100, 10)

func _on_player_stats_updated(stats: Dictionary) -> void:
	var my_id := multiplayer.get_unique_id()
	var my_stats := Network.get_player_stats(my_id)
	_update_own_stats(int(my_stats.get("hp", 100)), int(my_stats.get("attack", 10)))

	# Update opponent panels
	for pid in stats.keys():
		var id_int := int(pid)
		if id_int == my_id:
			continue
		if opponent_panels.has(id_int):
			var data = stats[pid]
			opponent_panels[id_int].update_stats(
				int(data.get("hp", 100)),
				int(data.get("attack", 10))
			)

func _update_own_stats(hp: int, attack: int) -> void:
	own_hp_label.text = str(hp)
	own_attack_label.text = str(attack)

# Convenience for tests / debugging: simulate updating your own stats
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H:
			var my_id := multiplayer.get_unique_id()
			if multiplayer.is_server():
				Network.update_player_stat(my_id, "hp", int(own_hp_label.text) - 10)
			else:
				Network.rpc_id(1, "request_update_stat", my_id, "hp", int(own_hp_label.text) - 10)
		elif event.keycode == KEY_A:
			var my_id := multiplayer.get_unique_id()
			if multiplayer.is_server():
				Network.update_player_stat(my_id, "attack", int(own_attack_label.text) + 5)
			else:
				Network.rpc_id(1, "request_update_stat", my_id, "attack", int(own_attack_label.text) + 5)