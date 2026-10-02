extends Control

# Title screen: the God Games' name on top, then the three doors into a run
# (host, join, quit). The words come from the registry (Gods) so the title
# screen and Bathala's own dialogue can never drift apart.

@onready var title_label: Label = $TitlePanel/Margin/TitleVBox/TitleLabel
@onready var subtitle_label: Label = $TitlePanel/Margin/TitleVBox/SubtitleLabel
@onready var alt_name_label: Label = $TitlePanel/Margin/TitleVBox/AltNameLabel
@onready var prologue_label: Label = $TitlePanel/Margin/TitleVBox/PrologueLabel
@onready var host_button = $CenterContainer/VBoxContainer/HostButton
@onready var join_button = $CenterContainer/VBoxContainer/JoinButton
@onready var almanac_button = $CenterContainer/VBoxContainer/AlmanacButton
@onready var quit_button = $CenterContainer/VBoxContainer/QuitButton
@onready var status_label = $StatusLabel

func _ready():
	# Connect button signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	almanac_button.pressed.connect(_on_almanac_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# Connect to network signals
	Network.connected.connect(_on_network_connected)
	
	_brand_title()
	status_label.text = "Ready to play!"


# BATHALA / Ang Laro ng mga diyos / (Bathala: the God Games) plus the story the
# gods open with - straight out of the registry, never typed twice.
func _brand_title() -> void:
	var bathala := Gods.bathala()
	title_label.text = Gods.GAME_TITLE
	title_label.add_theme_color_override("font_color", bathala.color)
	subtitle_label.text = bathala.epithet
	alt_name_label.text = "(%s)" % Gods.GAME_ALT_NAME
	prologue_label.text = "%s\nFAVOR is the total points among all the challenges." % Gods.GAME_PROLOGUE

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
