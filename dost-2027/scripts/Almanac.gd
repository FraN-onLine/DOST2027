extends Control

@onready var card_grid = $CenterContainer/VBoxContainer/ScrollContainer/GridContainer
@onready var detail_panel = $DetailPanel
@onready var detail_texture = $DetailPanel/VBoxContainer/CardTexture
@onready var detail_name = $DetailPanel/VBoxContainer/NameLabel
@onready var detail_type = $DetailPanel/VBoxContainer/TypeLabel
@onready var detail_cost = $DetailPanel/VBoxContainer/CostLabel
@onready var detail_desc = $DetailPanel/VBoxContainer/DescLabel
@onready var close_button = $DetailPanel/CloseButton
@onready var back_button = $CenterContainer/VBoxContainer/BackButton

# All card IDs in the game, ordered for display
var card_ids := [0, 1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13]

func _ready():
	back_button.pressed.connect(_on_back_pressed)
	close_button.pressed.connect(_on_close_detail)
	detail_panel.visible = false
	_build_card_grid()

func _build_card_grid():
	# Clear existing children
	for child in card_grid.get_children():
		card_grid.remove_child(child)
		child.queue_free()
	
	for cid in card_ids:
		var res_path = "res://cards/card_%d.tres" % cid
		if not ResourceLoader.exists(res_path):
			continue
		var card_res = ResourceLoader.load(res_path)
		if card_res == null:
			continue
		
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(120, 150)
		btn.text = ""
		btn.tooltip_text = str(card_res.name)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(_on_card_pressed.bind(cid))
		
		# Add the card texture as an icon
		if card_res.texture_face_up:
			btn.icon = card_res.texture_face_up
			btn.expand_icon = true
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		
		card_grid.add_child(btn)

func _on_card_pressed(card_id: int):
	var res_path = "res://cards/card_%d.tres" % card_id
	if not ResourceLoader.exists(res_path):
		return
	var card_res = ResourceLoader.load(res_path)
	if card_res == null:
		return
	
	# Populate detail panel
	if card_res.texture_face_up:
		detail_texture.texture = card_res.texture_face_up
	detail_name.text = str(card_res.name)
	detail_type.text = "Type: " + str(card_res.type)
	detail_cost.text = "Cost: " + str(card_res.cost) + " Energy"
	
	var desc = str(card_res.description)
	if desc.is_empty():
		desc = _get_card_description(card_id)
	detail_desc.text = desc
	
	detail_panel.visible = true

func _get_card_description(card_id: int) -> String:
	match card_id:
		0:
			return "The heart of your city. Place it first to unlock your full hand."
		1:
			return "Pumps water to protect nearby buildings from fire and drought."
		2:
			return "Houses emergency equipment. Reduces damage from disasters."
		3:
			return "Broadcasts warnings across the city, boosting defense."
		4:
			return "Stacks sandbags to shield buildings from floods and quakes."
		5:
			return "Deploys fire drones to quickly extinguish fires."
		6:
			return "Reinforces structures against seismic activity."
		9:
			return "Strikes a building with a blackout burst, disabling it temporarily."
		10:
			return "Triggers an earthquake, damaging the target and adjacent buildings."
		11:
			return "Calls down a fire strike, burning the target and nearby buildings."
		12:
			return "Summons a tornado that sweeps across the board, damaging buildings."
		13:
			return "Releases a toxic surge that damages and weakens resistances."
		_:
			return ""

func _on_close_detail():
	detail_panel.visible = false

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
