class_name Gods
extends RefCounted

# Registry of every god of the God Games plus the favors they can bestow.
#
# The gods are DATA now: each one is a God resource under res://resources/gods/,
# openable and tunable in the editor exactly like the cards in res://cards/.
# A god's favors ride along as sub-resources inside its own file, so adding a
# favor is an editor change and never a code change. This class only finds the
# files, keeps them in one place and answers the few questions the rest of the
# game asks (which gods exist, in what order, and which favor has this id).
#
# (Re)generate the files with the code definitions in tools/build_gods.gd, or
# just edit the .tres by hand - both end up in the same place.

const GOD_DIR := "res://resources/gods"

const TEMP_ICON := "res://icon.svg"  # placeholder art for every god / favor

const MAYARI := &"mayari"
const APOLAKI := &"apolaki"
const TALA := &"tala"
const HANAN := &"hanan"
const BATHALA := &"bathala"

# The God Games' own name: the title screen and the finale read these, so the
# branding lives in exactly one place. They mirror the Bathala resource.
const GAME_TITLE := "BATHALA"
const GAME_SUBTITLE := "Ang Laro ng mga diyos"
const GAME_ALT_NAME := "Bathala: the God Games"
const GAME_PROLOGUE := "Bathala took the dearest of the mortals, convince him that they are ought to be released by getting FAVOR from God's challenges."

# How many challenges a run holds, plus Bathala's final challenge.
const CHALLENGE_MIN := 4
const CHALLENGE_MAX := 6

static var _gods: Dictionary = {}    # god id -> God
static var _favors: Dictionary = {}  # favor id -> GodFavor (across every god)
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_gods.clear()
	_favors.clear()
	var dir := DirAccess.open(GOD_DIR)
	if dir == null:
		push_error("Gods: cannot open %s - the god resources are missing" % GOD_DIR)
		return
	# The filenames sort the gods into a stable order (apolaki, bathala, mayari).
	var files := dir.get_files()
	files.sort()
	for file in files:
		if not file.ends_with(".tres"):
			continue
		var god: God = load("%s/%s" % [GOD_DIR, file])
		if god == null or god.id == &"":
			continue
		_gods[god.id] = god
		for favor in god.favors:
			_favors[favor.id] = favor


static func all() -> Array[God]:
	_load()
	var gods: Array[God] = []
	for id in _gods.keys():
		gods.append(_gods[id])
	gods.sort_custom(func(a: God, b: God): return str(a.id) < str(b.id))
	return gods


static func by_id(god_id: StringName) -> God:
	_load()
	if _gods.has(god_id):
		return _gods[god_id]
	# An unknown id (a scene that still names an old god): the moon watches first.
	if _gods.has(MAYARI):
		return _gods[MAYARI]
	return null


# The favor with this id, wherever it comes from. A mortal carries its favors
# across trials - a Mayari buff still reads while Apolaki hosts the next game -
# so this lookup cannot stop at today's god.
static func favor_by_id(favor_id: StringName) -> GodFavor:
	_load()
	return _favors.get(favor_id, null)


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
	var finale := bathala()
	if finale != null:
		order.append(finale)
	return order


static func mayari() -> God:
	return by_id(MAYARI)


static func apolaki() -> God:
	return by_id(APOLAKI)


static func tala() -> God:
	return by_id(TALA)


static func hanan() -> God:
	return by_id(HANAN)


static func bathala() -> God:
	return by_id(BATHALA)
