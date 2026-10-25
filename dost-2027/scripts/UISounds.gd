extends Node

# Hover and press sounds for every button, wired once here (like the motion in
# UITokens.install_motion) so no screen has to remember. Open scenes/UISounds.tscn
# and drop the streams in the Inspector; with a stream unset that sound is skipped.

@export var hover_stream: AudioStream
@export var press_stream: AudioStream

var _hover := AudioStreamPlayer.new()
var _press := AudioStreamPlayer.new()


func _ready() -> void:
	for player in [_hover, _press]:
		player.bus = &"UI"
		add_child(player)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if not node is BaseButton:
		return
	var button := node as BaseButton
	button.mouse_entered.connect(_play.bind(_hover, hover_stream, button))
	button.focus_entered.connect(_play.bind(_hover, hover_stream, button))
	button.button_down.connect(_play.bind(_press, press_stream, button))


func _play(player: AudioStreamPlayer, stream: AudioStream, button: BaseButton) -> void:
	if stream == null or button.disabled:
		return
	player.stream = stream
	player.play()
