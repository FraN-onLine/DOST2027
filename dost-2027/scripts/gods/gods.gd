class_name Gods
extends RefCounted

# Registry of every god of the God Games plus the favors they can bestow.
# Data lives here instead of .tres files so tuning is a readable diff, but
# GodFavor / God are still Resources - any entry can be saved out to .tres
# later (ResourceSaver.save()) without touching the arena code.

const TEMP_ICON := "res://icon.svg"  # placeholder art for every god / favor

const MAYARI := &"mayari"
const APOLAKI := &"apolaki"
const BATHALA := &"bathala"

static var _cache: Dictionary = {}


static func all() -> Array[God]:
	return [mayari(), apolaki(), bathala()]


static func by_id(god_id: StringName) -> God:
	for god in all():
		if god.id == god_id:
			return god
	return mayari()


static func next_god(god_id: StringName) -> God:
	# The god that takes over after the given one (Bathala always closes).
	var order := trial_order()
	for index in range(order.size() - 1):
		if order[index].id == god_id:
			return order[index + 1]
	return bathala()


static func trial_order() -> Array[God]:
	# Random order of the playable gods, Bathala always last.
	var playing: Array[God] = []
	for god in all():
		if god.id != BATHALA and god.implemented:
			playing.append(god)
	playing.shuffle()
	var order: Array[God] = []
	order.append_array(playing)
	order.append(bathala())
	return order


static func _new_favor(favor_id: StringName, god_id: StringName, display_name: String,
		description: String, slot: int, kind: int, color: Color,
		cooldown: float = 0.0, duration: float = 0.0, params: Dictionary = {}) -> GodFavor:
	var favor := GodFavor.new()
	favor.id = favor_id
	favor.god_id = god_id
	favor.display_name = display_name
	favor.description = description
	favor.slot = slot
	favor.kind = kind
	favor.color = color
	favor.cooldown = cooldown
	favor.duration = duration
	favor.params = params
	favor.icon = load(TEMP_ICON)
	return favor


static func mayari() -> God:
	if _cache.has(MAYARI):
		return _cache[MAYARI]

	var color := Color(0.55, 0.85, 1.0)  # light blue
	var favors: Array[GodFavor] = [
		_new_favor(&"waning_moon", MAYARI, "Waning Moon",
			"Whenever FAVOR is lost in any way, you lose 50% less.",
			GodFavor.Slot.PASSIVE, GodFavor.Kind.PASSIVE, color,
			0.0, 0.0, {"loss_mult": 0.5}),
		_new_favor(&"full_moon", MAYARI, "Full Moon",
			"Whenever FAVOR is gained, you gain 10% more.",
			GodFavor.Slot.PASSIVE, GodFavor.Kind.PASSIVE, color,
			0.0, 0.0, {"gain_mult": 1.1}),
		_new_favor(&"blind_spot", MAYARI, "Blind Spot",
			"Once per trial: immediately gain +100 FAVOR.",
			GodFavor.Slot.PASSIVE, GodFavor.Kind.INSTANT, color,
			0.0, 0.0, {"instant_favor": 100}),
		_new_favor(&"favorable_outcome", MAYARI, "Favorable Outcome",
			"At the end of a trial, if you hold the highest FAVOR, gain an extra +200.",
			GodFavor.Slot.PASSIVE, GodFavor.Kind.END_OF_TRIAL, color,
			0.0, 0.0, {"bonus": 200}),
		_new_favor(&"half_vision", MAYARI, "Half Vision",
			"E - blinds every other mortal for 1.5s, only a circle around them stays lit.",
			GodFavor.Slot.E, GodFavor.Kind.ACTIVE, color,
			25.0, 1.5, {"vision_radius": 0.16}),
		_new_favor(&"siblings_compromise", MAYARI, "Sibling's Compromise",
			"Q - doubles the FAVOR you gain for the next 5s.",
			GodFavor.Slot.Q, GodFavor.Kind.ACTIVE, color,
			30.0, 5.0, {"gain_mult_while_active": 2.0}),
		_new_favor(&"siblings_rivalry", MAYARI, "Sibling's Rivalry",
			"Fall 1000 FAVOR behind another mortal and Mayari blots out part of their screen for 5s (once per mortal, once per trial). Needs an Apolaki favor in the match.",
			GodFavor.Slot.PASSIVE, GodFavor.Kind.PASSIVE, color,
			0.0, 5.0, {"behind_by": 1000, "requires_god": "apolaki"}),
	]

	var god := God.new()
	god.id = MAYARI
	god.display_name = "MAYARI"
	god.epithet = "Goddess of the Moon"
	god.color = color
	god.game_name = "PATINTERO x KING OF THE HILL"
	god.game_blurb = "Cross Mayari's lines. Stand inside the glowing boxes she lights up and hold them while her two clones sweep the field - go the whole way down and back for extra FAVOR."
	god.arena_scene = "res://scenes/gods/mayari/MayariArena.tscn"
	god.implemented = true
	god.favors = favors
	god.intro_lines = [
		"Mayari watches you from the moon.",
		"Patintero was always a game of lines - mine are alive. Cross them, take my boxes and I will light your way.",
		"Do not make me send my clones twice.",
	]
	god.success_lines = [
		"You moved like moonlight on water. The moon remembers this.",
	]
	god.failure_lines = [
		"Hm. The night is long - try again before the moon sets.",
	]
	_cache[MAYARI] = god
	return god


static func apolaki() -> God:
	if _cache.has(APOLAKI):
		return _cache[APOLAKI]

	var color := Color(1.0, 0.85, 0.25)  # yellow gold
	var favors: Array[GodFavor] = [
		_new_favor(&"the_sun_god", APOLAKI, "The Sun God",
			"If an opponent loses FAVOR, a sun patch blocks their screen for 1.5s.",
			GodFavor.Slot.PASSIVE, GodFavor.Kind.PASSIVE, color,
			0.0, 0.0, {"patch_duration": 1.5}),
		_new_favor(&"the_ruler", APOLAKI, "The Ruler",
			"If you lose FAVOR, a random opponent gets a sun patch on their screen for 1.5s.",
			GodFavor.Slot.PASSIVE, GodFavor.Kind.PASSIVE, color,
			0.0, 0.0, {"patch_duration": 1.5}),
		_new_favor(&"the_victor", APOLAKI, "The Victor",
			"At 5 sun patches on one opponent they lose 200 FAVOR - once per trial. You are immune to other mortals holding this favor.",
			GodFavor.Slot.PASSIVE, GodFavor.Kind.PASSIVE, color,
			0.0, 0.0, {"patch_threshold": 5, "penalty": 200}),
		_new_favor(&"the_great", APOLAKI, "The Great",
			"Gain 2 FAVOR per second for as long as any sun patch is shining.",
			GodFavor.Slot.PASSIVE, GodFavor.Kind.PASSIVE, color,
			0.0, 0.0, {"favor_per_sec": 2.0}),
		_new_favor(&"siblings_compromise", APOLAKI, "Sibling's Compromise",
			"E - sun patches every opponent for 5s and doubles any FAVOR they lose while it lasts.",
			GodFavor.Slot.E, GodFavor.Kind.ACTIVE, color,
			30.0, 5.0, {"patch_duration": 5.0, "loss_mult_while_active": 2.0}),
		_new_favor(&"the_unmoving", APOLAKI, "The Unmoving",
			"Q - you cannot lose FAVOR in any way for 3s.",
			GodFavor.Slot.Q, GodFavor.Kind.ACTIVE, color,
			25.0, 3.0, {"loss_immunity": 3.0}),
		_new_favor(&"siblings_rivalry", APOLAKI, "Sibling's Rivalry",
			"Get 1000 FAVOR ahead of another mortal and Apolaki blots out part of their screen with sun patches for 5s (once per mortal, once per trial). Needs a Mayari favor in the match.",
			GodFavor.Slot.PASSIVE, GodFavor.Kind.PASSIVE, color,
			0.0, 5.0, {"ahead_by": 1000, "requires_god": "mayari"}),
	]

	var god := God.new()
	god.id = APOLAKI
	god.display_name = "APOLAKI"
	god.epithet = "God of the Sun and War"
	god.color = color
	god.game_name = "ARNIS"
	god.game_blurb = "Duel Apolaki one on one. Strike him while he is open, guard while he is not, and watch for his blind spots."
	god.arena_scene = ""  # TODO: ApolakiArena.tscn
	god.implemented = false
	god.favors = favors
	god.intro_lines = [
		"Apolaki does not blink while the sun is up.",
	]
	god.success_lines = [
		"You struck true. The sun saw it.",
	]
	god.failure_lines = [
		"Not enough fire in you yet.",
	]
	_cache[APOLAKI] = god
	return god


static func bathala() -> God:
	if _cache.has(BATHALA):
		return _cache[BATHALA]

	var god := God.new()
	god.id = BATHALA
	god.display_name = "BATHALA"
	god.epithet = "Ang Laro ng mga diyos"
	god.color = Color(1.0, 0.95, 0.78)
	god.game_name = "THE FINAL CHALLENGE"
	god.game_blurb = "Bathala judges the FAVOR you gathered from every god."
	god.implemented = false
	god.favors = []
	# Story text for the title screen / the finale.
	god.intro_lines = [
		"Bathala took the dearest of the mortals.",
		"Convince him that they ought to be released by earning FAVOR from the gods' challenges.",
		"FAVOR is the sum of every point you win across the challenges.",
		"You and your fellow mortals take on 4 to 6 challenges, and then one final challenge.",
		"Play well. The gods are watching.",
	]
	god.success_lines = [
		"The gods keep their word. Your mortal goes free.",
	]
	god.failure_lines = [
		"Not yet. The gods are not finished watching you.",
	]
	_cache[BATHALA] = god
	return god
