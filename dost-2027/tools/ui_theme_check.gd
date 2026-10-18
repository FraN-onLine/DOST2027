extends SceneTree

# Validation for the design system (UI/theme/):
#   * the project theme (project.godot gui/theme/custom) loads and carries every
#     type variation the screens pick by name
#   * every font size in the theme, the scenes and the scripts is on the type
#     scale (UITokens.TYPE_SCALE: 8, 16, 24, 32, 48) - Minecraftia is drawn on an
#     8 px grid, anything else renders soft
#   * no scene under scenes/ or UI/ still styles itself with a
#     theme_override_styles/ entry - the theme does that now
# A file may be excused only through ALLOW, with the reason it is excused.
# Run: godot --headless --path <project> -s res://tools/ui_theme_check.gd

const VARIATIONS := [
	"PrimaryButton", "SecondaryButton", "GhostButton", "SmallButton", "DangerButton",
	"TabButton", "IconButton", "KeycapButton", "KeycapLabel", "PanelCard", "PanelInset", "PanelHud",
	"Nameplate", "PanelEmpty", "PanelRow", "CodeField", "CodeLabel", "ShrineTile", "SeedPacket", "HeroLabel", "DisplayLabel",
	"HeadingLabel", "CaptionLabel", "MutedLabel", "WarningLabel", "ChipLabel", "FlavorLabel", "PacketLabel", "BadgeLabel", "CardButton", "SelectionRing",
]
const SCAN_DIRS := ["res://scenes", "res://UI", "res://scripts"]

# path -> why it may keep its own styling / off-scale sizes.
const ALLOW := {
	"res://UI/Server and Lobby handlers/hosting.tscn": "unused leftover (see tools/lobby_check.gd); nothing loads it",
	# Phase 4 restyles the in-game UI.
	"res://scenes/Game.tscn": "in-game: phase 4",
	"res://scenes/GodIntro.tscn": "in-game: phase 4",
	"res://scripts/GodIntro.gd": "in-game: phase 4",
	"res://scripts/Settings.gd": "in-game: phase 4 (FPS counter)",
	"res://UI/opponentpanels.tscn": "in-game: phase 4",
	"res://UI/GodsArena/god_hud.tscn": "in-game: phase 4",
	"res://UI/GodsArena/skill_bar.tscn": "in-game: phase 4",
	"res://UI/GodsArena/gods_due_menu.tscn": "in-game: phase 4",
	"res://UI/GodsArena/gods_due_menu.gd": "in-game: phase 4",
	"res://UI/GodsArena/god_dialogue.tscn": "in-game: phase 4",
	"res://UI/Popups/favor_popup.tscn": "in-game: phase 4",
	"res://scenes/gods/apolaki/Apolaki.tscn": "in-game: phase 4",
	"res://scenes/gods/apolaki/ApolakiArena.tscn": "in-game: phase 4",
	"res://scenes/gods/bathala/AgawanGod.tscn": "in-game: phase 4",
	"res://scenes/gods/bathala/BathalaArena.tscn": "in-game: phase 4",
	"res://scenes/gods/common/Mortal.tscn": "in-game: phase 4",
	"res://scenes/gods/hanan/HananArena.tscn": "in-game: phase 4",
	"res://scenes/gods/mapulon_ikapati/LangitLupaArena.tscn": "in-game: phase 4",
	"res://scenes/gods/mayari/MayariClone.tscn": "in-game: phase 4",
	"res://scenes/gods/tala/TalaArena.tscn": "in-game: phase 4",
}

var _problems := 0


func _initialize() -> void:
	# --- the theme -------------------------------------------------------------
	var path: String = ProjectSettings.get_setting("gui/theme/custom", "")
	var theme: Theme = load(path) if not path.is_empty() else null
	_check(theme != null, "the project theme loads (%s)" % path)
	if theme != null:
		_check(theme.default_font != null and theme.default_font_size == UITokens.BODY,
			"the theme's default font is Minecraftia at %d px" % UITokens.BODY)
		for variation in VARIATIONS:
			_check(theme.get_type_variation_base(variation) != &"", "the theme defines %s" % variation)
		for type in theme.get_font_size_type_list():
			for name in theme.get_font_size_list(type):
				var size := theme.get_font_size(name, type)
				_check(size in UITokens.TYPE_SCALE, "theme %s/%s = %d is on the type scale" % [type, name, size])

	# --- every scene and script ------------------------------------------------
	var size_pattern := RegEx.create_from_string("font_size(?:\\s*=\\s*|\"\\s*,\\s*)(\\d+)")
	for file in _files():
		var text := FileAccess.get_file_as_string(file)
		var excused := ALLOW.has(file)
		var off_scale: Array[String] = []
		for found in size_pattern.search_all(text):
			if not int(found.get_string(1)) in UITokens.TYPE_SCALE:
				off_scale.append(found.get_string(1))
		var styled := file.ends_with(".tscn") and not file.begins_with("res://scripts") \
			and text.contains("theme_override_styles/")
		if excused:
			if off_scale.is_empty() and not styled:
				print("NOTE: %s is clean now - drop it from ALLOW" % file)
			continue
		_check(off_scale.is_empty(), "%s uses type-scale font sizes only%s" % [
			file, "" if off_scale.is_empty() else " (found %s)" % ", ".join(off_scale)])
		if file.ends_with(".tscn"):
			_check(not styled, "%s has no theme_override_styles/ entry" % file)

	print("ui theme checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _files() -> Array[String]:
	var found: Array[String] = []
	var pending: Array[String] = []
	pending.append_array(SCAN_DIRS)
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			pending.append("%s/%s" % [dir_path, sub])
		for file in dir.get_files():
			if file.ends_with(".tscn") or file.ends_with(".gd"):
				found.append("%s/%s" % [dir_path, file])
	found.sort()
	return found


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
