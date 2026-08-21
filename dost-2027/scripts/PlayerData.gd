class_name PlayerData
extends RefCounted

# Player data/stats for the game.
# Server-authoritative: the server holds PlayerData instances in
# Network.player_data. Clients receive synced copies via
# Network.player_stats (plain Dictionary).

var name: String = ""
var hp: int = 100
var attack: int = 10


func _init(player_name: String = "", start_hp: int = 100, start_attack: int = 10) -> void:
	name = player_name
	hp = start_hp
	attack = start_attack


func to_dict() -> Dictionary:
	return {
		"name": name,
		"hp": hp,
		"attack": attack,
	}


static func from_dict(data: Dictionary) -> PlayerData:
	var pd := PlayerData.new(
		str(data.get("name", "")),
		int(data.get("hp", 100)),
		int(data.get("attack", 10))
	)
	return pd