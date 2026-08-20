extends Control

@onready var name_input = $CenterContainer/VBoxContainer/NameInput
@onready var start_button = $CenterContainer/VBoxContainer/StartButton
@onready var back_button = $CenterContainer/VBoxContainer/BackButton
@onready var status_label = $StatusLabel

func _ready():
	# Connect button signals
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)
	name_input.text_submitted.connect(_on_name_submitted)
	
	# Connect to network signals
	Network.connected.connect(_on_network_connected)
	
	# Focus on the name input so the user can type immediately
	name_input.grab_focus()
	
	# Pre-fill with a random name suggestion
	name_input.text = Network.RANDOM_NAMES[randi() % Network.RANDOM_NAMES.size()]
	
	status_label.text = "You'll get a random name - change it if you want"

func _on_start_pressed():
	_start_hosting()

func _on_name_submitted(_text: String):
	_start_hosting()

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _start_hosting():
	var name = name_input.text.strip_edges()
	if name.is_empty():
		status_label.text = "Please enter a name first"
		return
	
	status_label.text = "Starting host as '%s'..." % name
	start_button.disabled = true
	
	# Start the host - auto uses the local machine's IP on the LAN
	Network.start_host()

func _on_network_connected(success: bool, reason: String):
	start_button.disabled = false
	
	if success and reason == "host_started":
		status_label.text = "Host started! Waiting for players..."
		# Move to lobby
		get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
	else:
		status_label.text = "Failed to start host: " + reason
