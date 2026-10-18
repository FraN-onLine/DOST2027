extends Control

# BATHALA - Ang Laro ng mga diyos (the God Games).
# Title / story screen that leads into the first god's arena.

const FALLBACK_ARENA := "res://scenes/Game.tscn"

@onready var story_label: Label = $CenterContainer/VBox/StoryLabel
@onready var gods_list: VBoxContainer = $CenterContainer/VBox/GodsList
@onready var prompt_key: Label = $CenterContainer/VBox/PromptRow/PromptKey
@onready var prompt_label: Label = $CenterContainer/VBox/PromptRow/PromptLabel
@onready var status_label: Label = $StatusLabel


func _ready() -> void:
	var bathala := Gods.bathala()
	story_label.text = "\n".join(bathala.intro_lines)
	# The key as the player bound it, drawn as a key (recognition over recall).
	prompt_key.text = UITokens.key_text(&"advance_dialogue")
	prompt_label.text = "FACE THE GODS"
	_build_god_list()
	status_label.text = "Bathala is watching."


func _build_god_list() -> void:
	for child in gods_list.get_children():
		gods_list.remove_child(child)
		child.queue_free()
	var order := Gods.trial_order()
	for index in range(order.size()):
		var god: God = order[index]
		var label := Label.new()
		var suffix := "" if god.implemented else "   (COMING SOON)"
		label.text = "%d.  %s  -  %s%s" % [index + 1, god.display_name, _game_name(god), suffix]
		label.add_theme_color_override("font_color", UITokens.god_text(god) if god.implemented else UITokens.FAINT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gods_list.add_child(label)


func _game_name(god: God) -> String:
	if god.game_name == "":
		return "the final challenge"
	return god.game_name


func _start() -> void:
	var order := Gods.trial_order()
	var target := FALLBACK_ARENA
	# God trials always run inside the shared Game shell.
	status_label.text = "Entering %s's arena..." % order[0].display_name
	get_tree().change_scene_to_file(target)


func _unhandled_input(event: InputEvent) -> void:
	# Grab the viewport BEFORE switching scenes: change_scene_to_file() takes
	# this node out of the tree, and get_viewport() would then return null.
	var viewport := get_viewport()
	if viewport == null:
		return
	if event.is_action_pressed("advance_dialogue") or event.is_action_pressed("ui_accept"):
		viewport.set_input_as_handled()
		_start()
	elif event.is_action_pressed("ui_cancel"):
		viewport.set_input_as_handled()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
