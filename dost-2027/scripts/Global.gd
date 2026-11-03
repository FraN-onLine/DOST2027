extends Node

var winner = ""
# The god the Playground's game list asked to test (trial_test.gd reads it).
var test_god_id: StringName = &"mayari"


# Every button gets the design system's hover / press motion (UITokens).
func _ready() -> void:
	UITokens.install_motion(get_tree())
