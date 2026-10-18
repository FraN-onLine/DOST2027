extends Control

# Title screen: the God Games' name on top, then the doors into a run. The words
# come from the registry (Gods) so the title screen and Bathala's own dialogue
# can never drift apart.
#
# Hick's law shapes the stack: three groups, 24 px apart - play (HOST, the one
# gold primary, and JOIN), browse (ALMANAC, OPTIONS), and leave (QUIT, a quiet
# ghost button) - so the eye picks a group first and a button second.

@onready var title_label: Label = $CenterContainer/VBoxContainer/Lockup/TitleLabel
@onready var subtitle_label: Label = $CenterContainer/VBoxContainer/Lockup/SubtitleLabel
@onready var host_button = $CenterContainer/VBoxContainer/HostButton
@onready var join_button = $CenterContainer/VBoxContainer/JoinButton
@onready var almanac_button = $CenterContainer/VBoxContainer/AlmanacButton
@onready var options_button = $CenterContainer/VBoxContainer/OptionsButton
@onready var quit_button =$CenterContainer/VBoxContainer/QuitButton
@onready var status_label = $Footer/StatusLabel

func _ready():
	# Connect button signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	almanac_button.pressed.connect(_on_almanac_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Connect to network signals
	Network.connected.connect(_on_network_connected)

	_brand_title()
	status_label.text = "Ready to play!"
	# Keyboard and pad players start on the primary action.
	host_button.grab_focus()


# BATHALA / Ang Laro ng mga diyos - straight out of the registry, never typed
# twice. The colours are the theme's (HeroLabel gold), not Bathala's raw grey.
func _brand_title() -> void:
	title_label.text = Gods.GAME_TITLE
	subtitle_label.text = Gods.bathala().epithet

func _on_host_pressed():
	# Go to the hosting screen where the player sets their name
	get_tree().change_scene_to_file("res://scenes/Hosting.tscn")

func _on_join_pressed():
	# Switch to join scene which auto-discovers hosts on LAN
	get_tree().change_scene_to_file("res://scenes/JoinGame.tscn")

# The Almanac lists every Favor of every god - its own BACK button brings the
# player straight back here.
func _on_almanac_pressed():
	get_tree().change_scene_to_file("res://scenes/Almanac.tscn")

func _on_options_pressed():
	get_tree().change_scene_to_file("res://scenes/Options.tscn")

func _on_quit_pressed():
	get_tree().quit()

func _on_network_connected(success: bool, reason: String):
	if success:
		if reason == "connected":
			status_label.text = "Connected to host!"
			# Switch to lobby scene
			get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
	else:
		status_label.text = "Connection failed: " + reason
