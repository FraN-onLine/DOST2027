extends SceneTree

# Throwaway probe: instantiate a scene, wait a few frames and print the on-screen
# rectangle of every Control/Label so an off-screen text can be found by number.
# Run: godot --headless --path <project> -s res://tools/rect_probe.gd -- <scene>

func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _rect(node: Node, out: Array) -> void:
	if node is Control:
		out.append(node)


func _run() -> void:
	var path := "res://scenes/Lobby.tscn"
	for arg in OS.get_cmdline_user_args():
		path = arg
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	get_root().add_child(view)
	var scene: Node = load(path).instantiate()
	view.add_child(scene)
	await _frames(5)
	print("=== %s (viewport 1152x648) ===" % path)
	_walk(scene)
	await _frames(1)
	quit()


func _walk(node: Node, depth := 0) -> void:
	if node is Label or node is LineEdit or node is Button:
		var c := node as Control
		var r := c.get_global_rect()
		var flag := ""
		if r.position.y < 0.0 or r.position.x < 0.0:
			flag = "  <== OFF SCREEN (top/left)"
		if r.end.y > 648.0 or r.end.x > 1152.0:
			flag += "  <== OFF SCREEN (bottom/right)"
		if node is Label:
			print("%s%s '%s' rect=%s%s" % ["  ".repeat(depth), node.get_class(), c.text if c is Label else "", str(r), flag])
		else:
			print("%s%s '%s' rect=%s%s" % ["  ".repeat(depth), node.get_class(), c.text if "text" in c else "", str(r), flag])
	for child in node.get_children():
		_walk(child, depth + 1)
