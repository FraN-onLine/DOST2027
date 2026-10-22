extends SceneTree

# Validation: the players' bandana and vest colours (UITokens.BANDANA_COLORS and
# art_shades, the shader scenes/gods/common/bandana_swap.gdshader,
# Network.request_bandana_color).
#   * the current art (Assets/Gods/lam-ang.png, lam-ang-walking.png) draws the
#     bandana and the vest in exactly three reds, #581010 #410B0B #2A0000, and
#     nothing else on either sheet is within the shader's tolerance of them;
#     art_shades gives the art's own reds for colour 0 and the colour, x0.74 and
#     x0.48 of it for the rest
#   * LEGACY, the rest of this list: the defend-arnis clip is still on the old sheet.
#   * Assets/Player/Lamang-Sheet.png draws the bandana in exactly two colours,
#     #7A0E0E and #570303, and the cloak in exactly three, #581010 #4B0000 #2A0000;
#     no other colour on the sheet is within the shader's tolerance of any of the
#     five - so the swap touches the bandana and the cloak and nothing else
#   * the swap, run over the whole sheet the way the shader runs it: colour 0
#     gives the sheet back exactly, every other colour changes only those five
#     colours, to the palette colour, its darker shadow and the three cloak shades
#   * a tint (modulate) on top of the swap still colours the cloak, which a
#     multiplier on the drawn red could not (its mid and dark reds have no green
#     or blue)
#   * the palette: 8 colours, 0 is the drawn red, no two alike, shadows darker
#   * a mortal owns its material (two mortals, two colours), and its modulate is
#     still free for hit flashes and fades
#   * the host's rules: a joiner gets the first free colour, a taken colour is
#     refused, nobody holds two, the answer replicates through the roster call,
#     nothing changes once the run has started, and a player who leaves and comes
#     back gets their colour back; solo rivals and bots take the free colours
# Run: godot --headless --path <project> -s res://tools/bandana_check.gd

const SHEET := "res://Assets/Player/Lamang-Sheet.png"
const NEW_SHEETS: Array[String] = ["res://Assets/Gods/lam-ang.png", "res://Assets/Gods/lam-ang-walking.png"]
# What the shader tolerates (see bandana_swap.gdshader): channels within this many
# 8-bit steps of the drawn red count as the bandana.
const SHADER_TOLERANCE := 0.012

var _problems := 0


func _initialize() -> void:
	_run()


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


# The five drawn colours the shader replaces, and what each becomes for colour `index`.
func _drawn() -> Array[Color]:
	return [UITokens.BANDANA_LIGHT, UITokens.BANDANA_SHADOW, UITokens.CLOAK_LIGHT, UITokens.CLOAK_MID, UITokens.CLOAK_DARK]


func _targets(index: int) -> Array[Color]:
	var cloak := UITokens.cloak_shades(index)
	return [UITokens.bandana_color(index), UITokens.bandana_shadow(index), cloak[0], cloak[1], cloak[2]]


# The shader, in GDScript: what a drawn pixel becomes for colour `index` (before the
# node's modulate, which multiplies the result).
func _swap(pixel: Color, index: int) -> Color:
	if pixel.a <= 0.0:
		return pixel  # not drawn (the shader skips it too)
	var drawn := _drawn()
	for i in range(drawn.size()):
		if _near(pixel, drawn[i]):
			var to := _targets(index)[i]
			return Color(to.r, to.g, to.b, pixel.a)
	return pixel


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= SHADER_TOLERANCE and absf(a.g - b.g) <= SHADER_TOLERANCE and absf(a.b - b.b) <= SHADER_TOLERANCE


func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.004 and absf(a.g - b.g) < 0.004 and absf(a.b - b.b) < 0.004 and is_equal_approx(a.a, b.a)


func _run() -> void:
	await _frames(2)
	var network: Node = root.get_node("Network")

	# --- the art: exactly two bandana colours, nothing else near them -----------------
	var sheet: Image = (load(SHEET) as Texture2D).get_image()
	sheet.decompress()
	var counts := {}
	var colors := {}
	for y in range(sheet.get_height()):
		for x in range(sheet.get_width()):
			var pixel: Color = sheet.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			colors[pixel.to_html(false)] = pixel
			counts[pixel.to_html(false)] = int(counts.get(pixel.to_html(false), 0)) + 1
	var names: Array[String] = []
	for color in _drawn():
		names.append(color.to_html(false))
	_check(names == ["7a0e0e", "570303", "581010", "4b0000", "2a0000"],
		"the palette names the drawn colours: bandana #7A0E0E #570303, cloak #581010 #4B0000 #2A0000")
	var drawn_all := true
	for html in names:
		drawn_all = drawn_all and int(counts.get(html, 0)) > 0
	_check(drawn_all, "the sheet draws all five (%s)" % str(names.map(func(html): return counts.get(html, 0))))
	var strays: Array[String] = []
	for html in colors.keys():
		if html in names:
			continue
		var pixel: Color = colors[html]
		for color in _drawn():
			if _near(pixel, color):
				strays.append("#" + html)
	_check(strays.is_empty(), "no other colour on the sheet is within the shader's tolerance of the bandana or the cloak (%s)" % str(strays))

	# --- the current art: three reds shared by the bandana and the vest ---------------
	var new_drawn: Array[Color] = [UITokens.SHADE_LIGHT, UITokens.SHADE_MID, UITokens.SHADE_DARK]
	for path in NEW_SHEETS:
		var image: Image = (load(path) as Texture2D).get_image()
		image.decompress()
		var found := [0, 0, 0]
		var near_misses := 0
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var pixel: Color = image.get_pixel(x, y)
				if pixel.a <= 0.0:
					continue
				var hit := -1
				for i in range(3):
					if pixel.to_html(false) == new_drawn[i].to_html(false):
						hit = i
					elif _near(pixel, new_drawn[i]):
						near_misses += 1
				if hit >= 0:
					found[hit] += 1
		_check(found[0] > 0 and found[1] > 0 and found[2] > 0 and near_misses == 0,
			"%s draws #581010 #410B0B #2A0000 (%s) and nothing else near them" % [path.get_file(), str(found)])
	_check(UITokens.art_shades(0) == [UITokens.SHADE_LIGHT, UITokens.SHADE_MID, UITokens.SHADE_DARK],
		"colour 0's shades are the art's own reds")
	var shade_ok := true
	for index in range(1, 8):
		var shades := UITokens.art_shades(index)
		var base := UITokens.bandana_color(index)
		shade_ok = shade_ok and _same(shades[0], base) and absf(shades[1].g - base.g * 0.74) < 0.004 and absf(shades[2].b - base.b * 0.48) < 0.004
	_check(shade_ok, "every other colour is light = the colour, mid = x0.74, dark = x0.48")

	# --- the swap over the whole sheet ------------------------------------------------------
	var identical := true
	var only_those := true
	var painted := true
	var drawn := _drawn()
	for index in range(UITokens.BANDANA_COLORS.size()):
		var changed := 0
		var wrong := 0
		var targets := _targets(index)
		for y in range(sheet.get_height()):
			for x in range(sheet.get_width()):
				var pixel: Color = sheet.get_pixel(x, y)
				var after := _swap(pixel, index)
				# (A see-through pixel can still carry a colour in the file; it is not drawn.)
				var which := -1
				for i in range(drawn.size()):
					if pixel.a > 0.0 and pixel.to_html(false) == drawn[i].to_html(false):
						which = i
				if which >= 0 and not _same(after, targets[which]):
					wrong += 1
				if which < 0 and not _same(after, pixel):
					only_those = false
				if not _same(after, pixel):
					changed += 1
		if index == 0 and changed != 0:
			identical = false
		if wrong != 0:
			painted = false
			printerr("  colour %d: %d bandana or cloak pixels came out wrong" % [index, wrong])
	_check(identical, "colour 0 hands the sheet back exactly as drawn")
	_check(only_those, "no colour changes a pixel that is not the bandana or the cloak")
	_check(painted, "every colour turns the bandana into its colour and shadow, and the cloak into its three shades")

	# The tint the arenas put on a mortal multiplies what the swap produced: a cloak
	# shade that has only red in it (as drawn) can still be tinted blue or faded.
	var blue_tint := Color(0.3, 0.5, 1.0, 0.6)
	_check((UITokens.cloak_shades(1)[1] * blue_tint).b > 0.1, "a blue tint lands on the sky blue cloak's mid shade")
	_check((UITokens.CLOAK_MID * blue_tint).b == 0.0, "...where multiplying the drawn #4B0000 would give no blue at all")

	# --- the palette -----------------------------------------------------------------------------
	_check(UITokens.BANDANA_COLORS.size() == 8 and UITokens.BANDANA_NAMES.size() == 8, "eight bandana colours, each named")
	_check(_same(UITokens.bandana_color(0), UITokens.BANDANA_LIGHT) and _same(UITokens.bandana_shadow(0), UITokens.BANDANA_SHADOW),
		"colour 0 is the art's own red, shadow included")
	_check(_same(UITokens.bandana_color(8), UITokens.bandana_color(0)) and _same(UITokens.bandana_color(-1), UITokens.bandana_color(7)),
		"a stray index wraps instead of breaking a screen")
	var closest := INF
	var closest_pair := ""
	for a in range(8):
		for b in range(a + 1, 8):
			var gap := _gap(UITokens.bandana_color(a), UITokens.bandana_color(b))
			if gap < closest:
				closest = gap
				closest_pair = "%s / %s" % [UITokens.BANDANA_NAMES[a], UITokens.BANDANA_NAMES[b]]
	_check(closest >= 90.0, "no two colours are alike (closest: %s, %.0f apart)" % [closest_pair, closest])
	var darker := true
	for index in range(1, 8):
		darker = darker and UITokens.luminance(UITokens.bandana_shadow(index)) < UITokens.luminance(UITokens.bandana_color(index))
	_check(darker, "every shadow is darker than its colour")
	var cloak_ok := true
	for index in range(1, 8):
		var shades := UITokens.cloak_shades(index)
		var base := UITokens.bandana_color(index)
		cloak_ok = cloak_ok and shades.size() == 3 and UITokens.luminance(shades[2]) < UITokens.luminance(shades[1]) 			and UITokens.luminance(shades[1]) < UITokens.luminance(shades[0]) and UITokens.luminance(shades[0]) < UITokens.luminance(base) 			and absf(shades[0].r - base.r * UITokens.CLOAK_RATIO) < 0.004 and absf(shades[1].g - shades[0].g * UITokens.CLOAK_MID_RATIO) < 0.004
	_check(cloak_ok, "each cloak is three shades, light to dark, and a little darker than its bandana")
	_check(UITokens.cloak_shades(0) == [UITokens.CLOAK_LIGHT, UITokens.CLOAK_MID, UITokens.CLOAK_DARK],
		"colour 0's cloak is the art's own reds")
	var seen := true
	for index in range(1, 8):
		# The bandana sits between the mortal's black hair and brown skin: every
		# colour (the drawn red aside) has to stand off both.
		var color := UITokens.bandana_color(index)
		seen = seen and UITokens.contrast(color, Color8(0x21, 0x1A, 0x1A)) >= 3.0 and _gap(color, Color8(0x97, 0x73, 0x4F)) >= 80.0
	_check(seen, "each colour stands off the mortal's hair and skin tone")

	# --- a mortal owns its colour -------------------------------------------------------------
	var view := SubViewport.new()
	view.size = Vector2i(1152, 648)
	view.disable_3d = true
	root.add_child(view)
	var scene: PackedScene = load("res://scenes/gods/common/Mortal.tscn")
	var first: ArenaMortal = scene.instantiate()
	var second: ArenaMortal = scene.instantiate()
	view.add_child(first)
	view.add_child(second)
	await _frames(2)
	first.set_bandana(1)
	second.set_bandana(5)
	var first_material := first.sprite.material as ShaderMaterial
	var second_material := second.sprite.material as ShaderMaterial
	_check(first_material != null and second_material != null and first_material != second_material,
		"every mortal has a material of its own")
	_check(first_material.get_shader_parameter("shade_light") == UITokens.art_shades(1)[0]
		and second_material.get_shader_parameter("shade_mid") == UITokens.art_shades(5)[1]
		and second_material.get_shader_parameter("shade_dark") == UITokens.art_shades(5)[2],
		"...and its own bandana and vest shades")
	_check(not first_material.get_shader_parameter("legacy"), "idle is on the new art: the shader's legacy switch is off")
	first.sprite.play(&"defend-arnis")
	var legacy_on: bool = first_material.get_shader_parameter("legacy")
	first.sprite.play(&"hit-arnis")
	_check(legacy_on and not first_material.get_shader_parameter("legacy"), "defend-arnis (old sheet) turns it on, hit-arnis (new) off again")
	_check(first_material.get_shader_parameter("bandana_color") == UITokens.bandana_color(1)
		and second_material.get_shader_parameter("bandana_color") == UITokens.bandana_color(5)
		and second_material.get_shader_parameter("bandana_shadow") == UITokens.bandana_shadow(5)
		and first_material.get_shader_parameter("cloak_color") == UITokens.cloak_shades(1)[0]
		and second_material.get_shader_parameter("cloak_mid") == UITokens.cloak_shades(5)[1]
		and second_material.get_shader_parameter("cloak_dark") == UITokens.cloak_shades(5)[2],
		"...and its own colours, shadow and cloak included")
	first.sprite.modulate = Color(1.0, 0.45, 0.35)
	_check(first.sprite.material == first_material and first.sprite.modulate == Color(1.0, 0.45, 0.35),
		"a hit flash (modulate) is still free on top of the swap")
	var third: ArenaMortal = scene.instantiate()
	view.add_child(third)
	await _frames(1)
	_check(third.bandana_index == 0 and third.sprite.material != first_material and third.sprite.material != second_material,
		"a new mortal starts on the drawn red, with a material of its own")
	view.queue_free()

	# --- the host's rules --------------------------------------------------------------------
	var saved_players = network.players
	var saved_bandanas = network.player_bandanas
	var saved_data = network.player_data
	var saved_memory = network._bandana_memory
	network.players = {1: "HOST"}
	network.player_data = {1: PlayerData.new("HOST")}
	network.player_bandanas = {}
	network._bandana_memory = {}
	network._game_in_progress = false
	network._assign_bandana(1, 3)
	_check(network.player_bandanas[1] == 3 and network.player_data[1].bandana_index == 3, "the host starts on the colour it last picked, when it is free")
	for peer in [2, 3, 4]:
		network.players[peer] = "P%d" % peer
		network.player_data[peer] = PlayerData.new("P%d" % peer)
		network._assign_bandana(peer)
	_check(network.player_bandanas == {1: 3, 2: 0, 3: 1, 4: 2}, "a joiner gets the first free colour (%s)" % str(network.player_bandanas))
	_check(not network._set_player_bandana(2, 3), "a colour another player holds is refused")
	_check(network.player_bandanas[2] == 0, "...and the asker keeps the colour they had")
	_check(network._set_player_bandana(2, 7) and network.player_bandanas[2] == 7 and network.player_data[2].bandana_index == 7,
		"a free colour is granted, and recorded with the player data")
	_check(network._set_player_bandana(2, 7), "asking for the colour you already wear is fine")
	_check(network._set_player_bandana(3, 0), "the colour player 2 just left is free for player 3")
	_check(not network._set_player_bandana(3, 8) and not network._set_player_bandana(3, -1), "a colour that does not exist is refused")
	var holders := {}
	for peer in network.player_bandanas.keys():
		holders[network.player_bandanas[peer]] = true
	_check(holders.size() == network.player_bandanas.size(), "nobody ever holds a colour another player holds")
	# Two players ask for the same free colour: the first request to reach the host gets it.
	_check(network._set_player_bandana(2, 5) and not network._set_player_bandana(4, 5) and network.player_bandanas[4] == 2,
		"two asks for one colour: the first wins, the second keeps theirs")

	# The roster call carries the colours to a client.
	var host_view: Dictionary = network.player_bandanas.duplicate()
	network.rpc_update_player_list(network.players.duplicate(), {}, host_view)
	_check(network.player_bandanas == host_view, "the roster call replicates the colours")

	# A player who leaves and comes back gets the colour back.
	network.player_bandanas.erase(2)
	network.players.erase(2)
	network._assign_bandana(9)
	network.players[9] = "P2"
	network.player_data[9] = PlayerData.new("P2")
	network._bandana_memory["P2"] = 5
	network._set_player_bandana(9, int(network._bandana_memory["P2"]), false)
	_check(network.player_bandanas[9] == 5, "a player who rejoins gets their colour back when it is free")

	# Locked once START is pressed.
	network._game_in_progress = true
	_check(not network._set_player_bandana(9, 6) and network.player_bandanas[9] == 5, "nothing changes once the host has pressed START")
	network._game_in_progress = false

	# Solo: the player's pick, then the free colours for rivals and bots.
	network.players = {}
	network.player_bandanas = {}
	var pick: int = network.preferred_bandana()
	_check(network.bandana_of(GodMatch.LOCAL_ID) == pick, "solo: the local player wears their saved pick")
	var rival_one: int = network.bandana_of(GodMatch.LOCAL_ID + 1)
	var rival_two: int = network.bandana_of(GodMatch.LOCAL_ID + 2)
	_check(rival_one != pick and rival_two != pick and rival_one != rival_two, "solo rivals and bots take free colours (%d, %d beside %d)" % [rival_one, rival_two, pick])

	network.players = saved_players
	network.player_bandanas = saved_bandanas
	network.player_data = saved_data
	network._bandana_memory = saved_memory

	# Settings: a saved pick must be a real colour.
	var settings: Node = root.get_node("Settings")
	var kept: Variant = settings.get_value("gameplay", "bandana_color")
	settings.set_value("gameplay", "bandana_color", 99)
	_check(settings.get_value("gameplay", "bandana_color") == 0, "Settings puts a colour that does not exist back to the default")
	settings.set_value("gameplay", "bandana_color", 4)
	_check(settings.get_value("gameplay", "bandana_color") == 4, "...and keeps a real one")
	settings.set_value("gameplay", "bandana_color", kept)

	print("bandana checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


# How far apart two colours look (the "redmean" distance, 0 - 765).
func _gap(a: Color, b: Color) -> float:
	var mean := (a.r + b.r) * 0.5 * 255.0
	var dr := (a.r - b.r) * 255.0
	var dg := (a.g - b.g) * 255.0
	var db := (a.b - b.b) * 255.0
	return sqrt((2.0 + mean / 256.0) * dr * dr + 4.0 * dg * dg + (2.0 + (255.0 - mean) / 256.0) * db * db)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
