extends Control

# The run's own menu, opened with Esc from the Game shell. It never pauses the
# trials - the clock, the gods and every rival mortal keep going - it only takes
# this screen's input away until it closes. The subtitle says so; the arena goes
# quiet underneath (Game.gd mutes it while this is open).
#
# What it offers depends on who opened it. Everyone can resume or reach the
# Options screen. A host (the only one who can end a run for the table) also gets
# BACK TO LOBBY, and a host with nobody connected may quit the game outright -
# with rivals in the room, MAIN MENU is the honest way out because it tells them.

signal resume_requested
signal options_requested
signal lobby_requested
signal menu_requested
signal quit_requested

@onready var title_label: Label = $Center/Panel/Margin/VBox/Title
@onready var subtitle_label: Label = $Center/Panel/Margin/VBox/Subtitle
@onready var resume_button: Button = $Center/Panel/Margin/VBox/Resume
@onready var options_button: Button = $Center/Panel/Margin/VBox/Options
@onready var lobby_button: Button = $Center/Panel/Margin/VBox/Lobby
@onready var menu_button: Button = $Center/Panel/Margin/VBox/MainMenu
@onready var quit_button: Button = $Center/Panel/Margin/VBox/Quit


func _ready() -> void:
	resume_button.pressed.connect(func() -> void: resume_requested.emit())
	options_button.pressed.connect(func() -> void: options_requested.emit())
	lobby_button.pressed.connect(func() -> void: lobby_requested.emit())
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	quit_button.pressed.connect(func() -> void: quit_requested.emit())


# `can_end_run` is the host's: it is the only player who can send the table home.
# `can_quit` is true when nobody else is connected, so quitting strands no one.
func open(can_end_run: bool, can_quit: bool) -> void:
	lobby_button.visible = can_end_run
	quit_button.visible = can_quit
	# MAIN MENU drops a client out of the session and closes a host's session.
	menu_button.tooltip_text = "Close the session for everyone and return to the title screen." if can_end_run \
		else "Leave this run and return to the title screen."
	visible = true
	UITokens.reveal(self)
	resume_button.grab_focus()


func close() -> void:
	visible = false
	resume_button.release_focus()


func is_open() -> bool:
	return visible
