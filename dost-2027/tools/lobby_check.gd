extends SceneTree

# Throwaway probe: renders scenes/Lobby.tscn in a real window and saves a
# screenshot so the layout can be looked at, not just measured.

func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


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
	await _frames(2)
	quit()
