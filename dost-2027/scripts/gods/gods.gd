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

# The God Games' own name: the title screen, the HUD and the finale all read
# these, so the branding lives in exactly one place.
const GAME_TITLE := "BATHALA"
const GAME_SUBTITLE := "Ang Laro ng mga diyos"
const GAME_ALT_NAME := "Bathala: the God Games"
const GAME_PROLOGUE := "Bathala took the dearest of the mortals, convince him that they are ought to be released by getting FAVOR from God's challenges."

# How many challenges a run holds, plus Bathala's final challenge.
const CHALLENGE_MIN := 4
const CHALLENGE_MAX := 6

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
	]

	var god := God.new()
	god.id = MAYARI
	god.display_name = "MAYARI"
	god.epithet = "Goddess of the Moon"
	god.color = color
	god.game_name = "PATINTERO"
	god.game_blurb = "Four boxes sit on the field and Mayari lights one at a time. Stand in the lit box and hold it while her two clones walk the lines drawn for them - every so often one hunts the nearest mortal - and let one touch you and you pay for it."
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
	god.display_name = GAME_TITLE
	god.epithet = GAME_SUBTITLE
	god.color = Color(1.0, 0.95, 0.78)
	god.game_name = "THE FINAL CHALLENGE"
	god.game_blurb = "Bathala judges the FAVOR you gathered from every god."
	god.implemented = false
	god.favors = []
	# Story text for the title screen / the finale.
	god.intro_lines = [
		GAME_PROLOGUE,
		"FAVOR is the total points among all the challenges.",
		"You and fellow mortals take on a series of %d to %d challenges, and then one final challenge." % [CHALLENGE_MIN, CHALLENGE_MAX],
		"Each god puts a Filipino sport in an arena and awards whoever entertained them the most.",
		"Every 1000 FAVOR you reach hands you a God's Due to spend on their favors.",
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
