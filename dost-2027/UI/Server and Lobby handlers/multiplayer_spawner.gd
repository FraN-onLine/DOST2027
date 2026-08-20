extends MultiplayerSpawner

@export var player_scene: PackedScene

func _ready():
    multiplayer.peer_connected.connect(setup_player)

func setup_player(id):
    var player = player_scene.instantiate()
    # set network master so RPCs from this peer map correctly
    if player.has_method("set_network_master"):
        player.set_network_master(id)
    # if the player node has a 'peer_id' or 'name' property, set it as well
    if player.has_variable("peer_id"):
        player.peer_id = id
    if player.has_variable("player_name"):
        player.player_name = "Player %d" % id
    add_child(player)

