extends SceneTree

# Throwaway: dump the shell panel rectangles so the stack can be checked exactly.
# Run: godot --headless --path <project> -s res://tools/tmp_shot.gd

func _initialize() -> void:
	_run()


func _run() -> void:
	var shell: Node = load("res://scenes/Game.tscn").instantiate()
	get_root().add_child(shell)
	for i in range(5):
		await process_frame
	var paths := [
		"TopLeft",
		"TopLeft/VBoxContainer",
		"TopLeft/VBoxContainer/NameLabel",
		"TopLeft/VBoxContainer/StatsRow",
		"TopLeft/VBoxContainer/StatsRow/FavorBox/FavorValue",
		"TopLeft/VBoxContainer/StatsRow/DueBox/DueValue",
		"TopLeft/VBoxContainer/EBar",
		"TopLeft/VBoxContainer/QBar",
		"OtherPlayersPanel",
		"OtherPlayersPanel/Margin/VBox",
		"OtherPlayersPanel/Margin/VBox/OpponentPlaceholder",
		"OtherPlayersPanel/Margin/VBox/OpponentPlaceholder/MarginContainer/VBoxContainer/NameLabel",
		"OtherPlayersPanel/Margin/VBox/OpponentPlaceholder/MarginContainer/VBoxContainer/SkillRow/EBar",
	]
	for path in paths:
		var node: Control = shell.get_node(path)
		var rect := Rect2(node.global_position, node.size)
		print("%-62s rect=%s inside_panel=%s" % [
			path, str(rect), str(not _outside(node))])
	quit()


func _outside(node: Control) -> bool:
	var panel: Control = node
	while not (panel is PanelContainer):
		panel = panel.get_parent()
		if panel == null:
			return false
	var inner := Rect2(panel.global_position, panel.size)
	var rect := Rect2(node.global_position, node.size)
	return not inner.encloses(rect)
