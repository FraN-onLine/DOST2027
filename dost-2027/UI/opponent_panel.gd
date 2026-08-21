extends PanelContainer

@onready var name_label = $MarginContainer/VBoxContainer/NameLabel
@onready var hp_label = $MarginContainer/VBoxContainer/StatsLabel/HpValue
@onready var attack_label = $MarginContainer/VBoxContainer/StatsLabel/AttackValue

var player_id := 0


func setup(id: int, player_name: String, hp: int, attack: int) -> void:
	player_id = id
	name_label.text = player_name
	hp_label.text = str(hp)
	attack_label.text = str(attack)


func update_stats(hp: int, attack: int) -> void:
	hp_label.text = str(hp)
	attack_label.text = str(attack)