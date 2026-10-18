extends Node

var winner = ""


# Every button gets the design system's hover / press motion (UITokens).
func _ready() -> void:
	UITokens.install_motion(get_tree())
