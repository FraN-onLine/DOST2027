extends SceneTree

# One-off generator. Turns the code-defined gods (scripts/gods/gods.gd) into
# God .tres resources under res://resources/gods/ so a god becomes data the
# editor can open and tune - exactly like the cards in res://cards/. Favours
# ride along as sub-resources inside the god's own file.
# Run: godot --headless --path <project> -s res://tools/build_gods.gd

const OUT_DIR := "res://resources/gods"


func _initialize() -> void:
	var dir := DirAccess.open(OUT_DIR)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for god in Gods.all():
		var path := "%s/%s.tres" % [OUT_DIR, str(god.id)]
		var err := ResourceSaver.save(god, path)
		print("saved %s -> %s (err=%d)" % [god.display_name, path, err])
	quit()
