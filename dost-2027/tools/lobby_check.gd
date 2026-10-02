extends SceneTree

# Throwaway probe: renders scenes/Lobby.tscn in a real window and saves a
# screenshot so the layout can be looked at, not just measured.

func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


# A left mouse button at a point on the screen, for the hit-test probes.
func _mouse(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	return event


func _run() -> void:
	await _frames(10)
	var shots := {
		"lobby": "res://scenes/Lobby.tscn",
		"mainmenu": "res://scenes/MainMenu.tscn",
		"multiplayersetup": "res://UI/Server and Lobby handlers/Multiplayersetup.tscn",
		"hosting": "res://UI/Server and Lobby handlers/hosting.tscn",
		"scenes_hosting": "res://scenes/Hosting.tscn",
		"joingame": "res://scenes/JoinGame.tscn",
	}
	for key in shots:
		if not ResourceLoader.exists(shots[key]):
			print("missing %s" % shots[key])
			continue
		var scene: Node = load(shots[key]).instantiate()
		root.add_child(scene)
		await _frames(20)
		var image := root.get_texture().get_image()
		image.save_png("res://shot_%s.png" % key)
		print("saved shot_%s.png" % key)
		scene.queue_free()
		await _frames(5)

	# The lobby's OPTIONS panel: opened, switched to CUSTOM, and with the second
	# god walked up the list - the whole trial-order UI in one picture.
	var lobby: Control = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby)
	await _frames(10)
	lobby._on_options_pressed()
	await _frames(4)

	# Click the CUSTOM tick box with a real mouse event: what the player does.
	var box: CheckBox = lobby._custom_box
	var at := box.get_global_rect().get_center()
	print("CUSTOM box rect=%s -> clicking %s" % [str(box.get_global_rect()), str(at)])
	Input.parse_input_event(_mouse(at, true))
	await _frames(3)
	Input.parse_input_event(_mouse(at, false))
	await _frames(6)
	# A -s script cannot name an autoload at compile time; go through the tree.
	var network = root.get_node_or_null("Network")
	print("after click: CUSTOM pressed=%s RANDOM pressed=%s custom=%s rows=%d" % [
		str(lobby._custom_box.button_pressed), str(lobby._random_box.button_pressed),
		str(network.trial_order_custom) if network != null else "no Network",
		lobby._order_rows.get_child_count()])

	lobby._custom_box.button_pressed = true
	await _frames(4)
	var ids: Array = lobby._order_list()
	if ids.size() >= 2:
		lobby._on_order_move_pressed(ids[1], -1)
	await _frames(8)
	root.get_texture().get_image().save_png("res://shot_lobby_options.png")
	print("saved shot_lobby_options.png | title='%s' | plan='%s' | rows=%d" % [
		lobby._order_title.text, lobby._order_label.text, lobby._order_rows.get_child_count()])
	lobby.queue_free()
	await _frames(5)
	await _frames(2)
	quit()
