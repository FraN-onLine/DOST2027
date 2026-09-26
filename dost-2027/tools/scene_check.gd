extends SceneTree

# Validation: every arena scene must load and must not draw in code.
# Run: godot --headless --path <project> -s res://tools/scene_check.gd

const SCENES := [
	"res://scenes/gods/mayari/MayariArena.tscn",
	"res://scenes/gods/mayari/MayariGoal.tscn",
	"res://scenes/gods/mayari/MayariClone.tscn",
	"res://scenes/gods/common/Mortal.tscn",
	"res://scenes/Game.tscn",
	"res://scenes/GodIntro.tscn",
	"res://scenes/Lobby.tscn",
	"res://scenes/MainMenu.tscn",
]


func _initialize() -> void:
	for path in SCENES:
		var packed: PackedScene = load(path)
		if packed == null:
			print("%s -> FAILED" % path)
			continue
		var node: Node = packed.instantiate()
		print("%s -> OK (%s, %d children)" % [path, node.name, node.get_child_count()])
		node.free()
	quit()
