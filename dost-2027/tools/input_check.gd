extends SceneTree

# Validation: the input actions every arena counts on exist (see the contract in
# scripts/gods/god_arena.gd). attack must be the LEFT MOUSE BUTTON - Arnis and
# Tumbang Preso use it as the mortal's attack.
# Run: godot --headless --path <project> -s res://tools/input_check.gd

const KEY_ACTIONS := [
	"move_left", "move_right", "move_up", "move_down",
	"skill_e", "skill_q", "due_menu", "advance_dialogue",
]
const MOUSE_ACTIONS := {
	"attack": MOUSE_BUTTON_LEFT,
}


func _initialize() -> void:
	var problems := 0
	for action in KEY_ACTIONS:
		problems += _check_action(action)
	for action in MOUSE_ACTIONS.keys():
		problems += _check_action(action, MOUSE_ACTIONS[action])
	print("input actions: %d problem(s)" % problems)
	print("--- DONE ---")
	quit()


func _check_action(action: String, button := 0) -> int:
	if not InputMap.has_action(action):
		print("%s -> MISSING" % action)
		return 1
	var events := InputMap.action_get_events(action)
	if button == 0:
		print("%s -> %s" % [action, str(events)])
		return 0
	var bound := false
	for event in events:
		if event is InputEventMouseButton and int(event.button_index) == button:
			bound = true
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.pressed = true
	var live := InputMap.event_is_action(click, action)
	print("%s -> LEFT MOUSE bound: %s | left click triggers it: %s | %s" % [
		action, str(bound), str(live), str(events)])
	return 0 if (bound and live) else 1
