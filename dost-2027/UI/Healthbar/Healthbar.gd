extends TextureProgressBar

@onready var timer = $Timer

var health = 0 : set = _set_health

func _set_health(new_health):
	var previous_health = health
	health = min(max_value, new_health)
	value = health
	
	if health <= 0:
		value = 0


# Called when the node enters the scene tree for the first time.
func init_health(_health):
	health = _health
	max_value = health
	value = health
