extends SceneTree

# Validation: the free placeholder art (Assets/Placeholders, CREDITS.md) and the
# one-shot effects built on it (Arena.spawn_effect / hit_effects / announce_hit).
#   * nothing in the project - scenes, resources, scripts, project.godot - points at
#     the Godot logo any more, and the logo file is gone; the one copy kept on
#     purpose (GODOT_PLACEHOLDER) is credited but used by no scene
#     (ALLOWED_GODOT), and fails for any user
#   * every picture under Assets/Placeholders has a line in CREDITS.md with a source
#     URL and the CC0 licence
#   * every effect in Arena.EFFECTS spawns a sprite that grows, fades and frees
#     itself; an unknown name spawns nothing
#   * a hit that lands (knock_mortal) draws its ring, spark and slash and puts the
#     stars over the mortal's head; a rival's ghost shown stunned gets them without
#     being moved; a broken chant stuns the Taya's stars too
#   * Network carries the look to every other screen (send_arena_fx / arena_fx_received),
#     and a client draws the host's hit where it was told
# Run: godot --headless --path <project> -s res://tools/placeholder_check.gd

const ROOT := "res://"
const SKIP_DIRS: Array[String] = ["addons", ".godot", "tools"]
const EXTENSIONS: Array[String] = ["tscn", "tres", "gd", "godot", "cfg"]
# The Godot logo, kept as the stand-in art of no scene any more (CREDITS.md).
const GODOT_PLACEHOLDER := "godot_placeholder" + ".svg"  # (split, so this file never finds itself)
const ALLOWED_GODOT: Array[String] = []

var _problems := 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _files(dir_path: String, extensions: Array[String], out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_directories():
		if name in SKIP_DIRS and dir_path == ROOT:
			continue
		_files(dir_path.path_join(name), extensions, out)
	for name in dir.get_files():
		if name.get_extension() in extensions:
			out.append(dir_path.path_join(name))


func _run() -> void:
	# --- the logo is gone -----------------------------------------------------------------
	var logo := "icon" + ".svg"  # (not spelled whole, so this file never finds itself)
	var users: Array[String] = []
	var files: Array[String] = []
	_files(ROOT, EXTENSIONS, files)
	for path in files:
		if FileAccess.get_file_as_string(path).contains(logo):
			users.append(path)
	_check(users.is_empty(), "nothing points at the Godot logo (%s)" % str(users))
	_check(not FileAccess.file_exists(ROOT + logo), "...and the logo file is not in the project")
	var godot_users: Array[String] = []
	for path in files:
		if FileAccess.get_file_as_string(path).contains(GODOT_PLACEHOLDER):
			godot_users.append(path)
	var strays := godot_users.filter(func(path: String) -> bool: return not ALLOWED_GODOT.has(path))
	_check(strays.is_empty() and godot_users.size() == ALLOWED_GODOT.size(),
		"the Godot placeholder stands in only for %s (used by %s)" % [str(ALLOWED_GODOT), str(godot_users)])

	# --- every placeholder is credited ------------------------------------------------------
	var credits := FileAccess.get_file_as_string("res://Assets/Placeholders/CREDITS.md")
	var pictures: Array[String] = []
	_files("res://Assets/Placeholders", ["png", "svg"], pictures)
	var missing: Array[String] = []
	for path in pictures:
		if not credits.contains(path.trim_prefix("res://Assets/Placeholders/")):
			missing.append(path)
	_check(pictures.size() >= 9 and missing.is_empty(), "every one of the %d placeholder pictures is in CREDITS.md (missing: %s)" % [pictures.size(), str(missing)])
	_check(credits.contains("https://kenney.nl") and credits.contains("CC0"), "...with its source and the CC0 licence")
	_check(credits.contains(GODOT_PLACEHOLDER) and credits.contains("Andrea Calabr") and credits.contains("CC BY 4.0"),
		"...and the Godot placeholder with its author and CC BY 4.0")

	# --- the effects ----------------------------------------------------------------------------
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)
	var arena: LangitLupaArena = load("res://scenes/gods/mapulon_ikapati/LangitLupaArena.tscn").instantiate()
	view.add_child(arena)
	await _frames(3)
	var at := Vector2(500, 300)
	var spawned := true
	for effect in Arena.EFFECTS.keys():
		var sprite := arena.spawn_effect(effect, at, 0.5)
		spawned = spawned and sprite != null and sprite.texture != null and sprite.global_position == at and sprite.get_parent() == arena.popups_root
	_check(spawned and Arena.EFFECTS.size() >= 3, "every effect in Arena.EFFECTS spawns a sprite at the point (%s)" % str(Arena.EFFECTS.keys()))
	_check(arena.spawn_effect(&"nope", at) == null, "an unknown effect spawns nothing")
	var live := arena.popups_root.get_child_count()
	await create_timer(0.6).timeout
	_check(arena.popups_root.get_child_count() < live, "the one-shot sprites free themselves (%d -> %d)" % [live, arena.popups_root.get_child_count()])

	var before := arena.popups_root.get_child_count()
	arena.knock_mortal(arena._my_id, arena.player.global_position + Vector2(-30, 0), 0.5, 100.0)
	await _frames(2)
	_check(arena.popups_root.get_child_count() >= before + 3, "a hit that lands draws a ring, a spark and a slash (%d new)" % (arena.popups_root.get_child_count() - before))
	_check(arena.player.stun_stars.visible, "...and puts the stars over the mortal's head")

	# A rival's ghost: only ever placed, so the stars must not move it.
	var ghost: ArenaMortal = Arena.MORTAL_SCENE.instantiate()
	arena.ghosts_root.add_child(ghost)
	ghost.set_lock(true)
	ghost.global_position = Vector2(700, 300)
	arena._ghosts[777] = ghost
	arena.show_stun(777, 0.5)
	await _frames(4)
	_check(ghost.stun_stars.visible and ghost.global_position == Vector2(700, 300), "a ghost the host says is stunned shows the stars and stays where it was placed")
	arena._ghosts.erase(777)
	ghost.queue_free()

	# The Taya's broken chant stumbles with stars.
	var taya: ArenaMortal = arena.mortal_node(arena._my_id)
	taya._stun_fx = 0.0
	arena._taya = arena._my_id
	arena._break_chant()
	await _frames(2)
	_check(taya.stun_stars.visible, "a broken chant puts the stars over the Taya")

	# The wire.
	var network: Node = root.get_node("Network")
	_check(network.has_signal("arena_fx_received") and network.has_method("send_arena_fx") and network.has_method("rpc_arena_fx"),
		"Network carries the hit and stun looks to the other screens")
	var effects_before := arena.popups_root.get_child_count()
	arena._authority = false
	arena._on_arena_fx_received({"kind": "hit", "id": 12345, "at": Vector2(400, 300), "dir": Vector2.RIGHT, "stun": 0.5})
	_check(arena.popups_root.get_child_count() >= effects_before + 3, "a client draws the host's hit at the spot it was told")

	view.queue_free()
	print("placeholder checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
