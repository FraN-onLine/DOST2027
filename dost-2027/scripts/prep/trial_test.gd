extends Node

# THE PLAYGROUND'S SOLO TRIAL TEST: one god's arena, played on its own.
#
# Playground.gd picks the god (Global.test_god_id) at the campfire's game list
# and switches to this scene. The wrapper instantiates that god's arena the way
# a standalone round runs - the arena's own HUD, dialogue, countdown and results,
# the whole field in view - with first_visit false (the short opening line) and
# final_trial true (no hand-over to a god that is not coming). The rules keep
# their usual solo stand-in rivals, which is also what gives Langit Lupa its
# bots; nothing is networked and no run state is touched.
#
# It leaves in one of three ways, all back to the Playground:
#   * the trial ends and the results have been read for RETURN_DELAY seconds;
#   * Esc (the arena's own Esc would go to the title screen);
#   * the RETURN button.
# SPACE on the results still plays the same test again.

const PLAYGROUND_SCENE := "res://scenes/prep/Playground.tscn"
const RETURN_DELAY := 10.0

@onready var hint_label: Label = $Overlay/Row/Hint
@onready var return_button: Button = $Overlay/Row/Return

var arena: Arena = null
var god: God = null
var _return_left := -1.0
var _leaving := false


func _ready() -> void:
	god = Gods.by_id(Global.test_god_id)
	if god == null or not god.implemented or god.arena_scene == "":
		god = Gods.mayari()
	var packed: PackedScene = load(god.arena_scene)
	if packed == null:
		_finish()
		return
	var instance := packed.instantiate()
	if not (instance is Arena):
		instance.queue_free()
		_finish()
		return
	arena = instance as Arena
	var network := get_node_or_null("/root/Network")
	var settings: RunSettings = RunSettings.defaults()
	if network != null:
		settings = network.run_settings
	arena.god_id = god.id
	arena.embedded = false
	arena.first_visit = false
	arena.final_trial = true
	arena.simulate_rivals = true
	arena.follow_camera = false
	arena.dialogue_prefix = "test_%s" % god.id
	arena.trial_time = settings.trial_time
	arena.due_step = settings.due_step
	if arena.get("god_blitz_mode") != null:
		arena.god_blitz_mode = settings.god_blitz_mode
	add_child(arena)
	return_button.pressed.connect(_finish)
	hint_label.text = "%s TEST - ESC RETURNS" % god.game_name.to_upper()


func _process(delta: float) -> void:
	if _leaving or arena == null or not is_instance_valid(arena):
		return
	if _return_left < 0.0:
		if _results_ready():
			_return_left = RETURN_DELAY
			_refresh_return_hint(int(RETURN_DELAY))
		return
	_return_left -= delta
	var left := maxi(0, ceili(_return_left))
	_refresh_return_hint(left)
	if _return_left <= 0.0:
		_finish()


# The results are up and the god is done speaking.
func _results_ready() -> bool:
	if arena._phase != Arena.Phase.RESULTS:
		return false
	if arena.dialogue != null and arena.dialogue.is_active():
		return false
	return arena.hud != null and arena.hud.results_panel.visible


func _refresh_return_hint(left: int) -> void:
	hint_label.text = "RETURNING TO THE PLAYGROUND IN %d" % left
	if arena.hud != null:
		arena.hud.set_results_hint("ESC - PLAYGROUND      SPACE - PLAY AGAIN      back in %ds" % left)


func _input(event: InputEvent) -> void:
	if _leaving or not event.is_action_pressed("ui_cancel"):
		return
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
	# Esc first closes a God's Due menu; a second press leaves the test.
	if arena != null and is_instance_valid(arena) and arena.due_menu != null and arena.due_menu.is_open():
		arena.due_menu.close()
		return
	_finish()


func _finish() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(PLAYGROUND_SCENE)
