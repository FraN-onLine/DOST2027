class_name PlayerData
extends RefCounted

# Player data for the lobby: the name the host confirmed for a peer.
# Server-authoritative: the server holds PlayerData instances in
# Network.player_data.
#
# Mortals in the God Games carry FAVOR, not hit points - the old hp / attack
# stats and the client-side mirror that synced them (Network.player_stats) were
# leftovers from an earlier plan and are gone. Everything a run tracks per
# player lives in GodMatch.Mortal (favor, due, favors, cooldowns).

var name: String = ""
var god_icon_id: StringName = &"mayari"
var bandana_index: int = 0  # which UITokens.BANDANA_COLORS this player wears (host-decided)


func _init(player_name: String = "") -> void:
	name = player_name


func to_dict() -> Dictionary:
	return {"name": name, "god_icon_id": str(god_icon_id), "bandana_index": bandana_index}


static func from_dict(data: Dictionary) -> PlayerData:
	var player := PlayerData.new(str(data.get("name", "")))
	player.god_icon_id = StringName(str(data.get("god_icon_id", "mayari")))
	player.bandana_index = int(data.get("bandana_index", 0))
	return player
