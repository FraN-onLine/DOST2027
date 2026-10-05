extends SceneTree

# Validation: the "OTHER MORTALS" upper-right panel is gone from the arena HUD,
# and the mortal mirrors sprite / strike area / standing collision to its facing.
# Run: godot --headless --path <project> -s res://tools/flip_panel_check.gd

var _problems := 0


func _initialize() -> void:
	_run()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  %s" % label)
	else:
		_problems += 1
		printerr("FAIL  %s" % label)


func _run() -> void:
	# --- the arena HUD no longer carries the OTHER MORTALS leader panel ---------
	var hud = load("res://UI/GodsArena/god_hud.tscn").instantiate()
	_check(hud.has_node("LeaderPanel") == false, "god_hud scene has no LeaderPanel node")
	var found := false
	for child in hud.find_children("*", "PanelContainer", true, false):
		var title = child.get_node_or_null("Margin/VBox/LeaderTitle")
		if title != null and title.text.contains("OTHER MORTALS"):
			found = true
	_check(not found, "no panel in god_hud shows an 'OTHER MORTALS' title")
	hud.free()

	# --- the mortal mirrors its pieces to the facing direction ------------------
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	get_root().add_child(view)
	var mortal = load("res://scenes/gods/common/Mortal.tscn").instantiate()
	view.add_child(mortal)
	await process_frame
	_check(mortal.damage_area != null, "mortal resolved its Arnis-Damage-Area")
	_check(mortal.body_collision != null, "mortal resolved its standing collision")
	_check(mortal.sprite != null, "mortal resolved its sprite")
	_check(mortal.facing == 1, "mortal starts facing right (the authored art)")

	# A move to the LEFT mirrors everything.
	mortal.velocity = Vector2(-120, 0)
	mortal._update_facing()
	_check(mortal.facing == -1, "mortal turns to face left after a leftward move")
	_check(mortal.sprite.flip_h, "sprite flip_h is set when facing left")
	_check(is_equal_approx(mortal.damage_area.scale.x, -1.0), "strike area scale flips when facing left")
	_check(is_equal_approx(mortal.body_collision.scale.x, -1.0), "standing collision scale flips when facing left")
	_check(is_equal_approx(mortal.damage_area.position.x, mortal._area_offset_x * -1.0), "strike area offset mirrors to the left")
	_check(is_equal_approx(mortal.body_collision.position.x, mortal._collision_offset_x * -1.0), "standing collision offset mirrors to the left")

	# A move back to the RIGHT restores the authored pose.
	mortal.velocity = Vector2(120, 0)
	mortal.global_position.x += 80.0
	mortal._update_facing()
	_check(mortal.facing == 1, "mortal turns back to the right")
	_check(not mortal.sprite.flip_h, "sprite flip_h clears when facing right")
	_check(is_equal_approx(mortal.damage_area.scale.x, 1.0), "strike area scale restores when facing right")
	_check(is_equal_approx(mortal.body_collision.scale.x, 1.0), "standing collision scale restores when facing right")

	# A ghost glides with no velocity of its own: the travelled distance decides.
	mortal.velocity = Vector2.ZERO
	mortal._last_position = mortal.global_position
	mortal.global_position.x -= 40.0
	mortal._update_facing()
	_check(mortal.facing == -1, "a ghost with no velocity turns from the distance it travelled")

	# Standing still keeps the last facing instead of flickering.
	mortal._last_position = mortal.global_position
	mortal.velocity = Vector2.ZERO
	mortal._update_facing()
	_check(mortal.facing == -1, "a standing mortal keeps its last facing")

	mortal.free()
	view.free()

	if _problems == 0:
		print("flip_panel_check: OK")
		quit(0)
	else:
		printerr("flip_panel_check: %d problem(s)" % _problems)
		quit(1)