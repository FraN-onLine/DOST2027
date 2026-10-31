class_name Pamanas
extends RefCounted

# Registry of every Pamana (heirloom) the Tindahan can sell, modelled on Gods:
# the items are DATA, one Pamana resource per file under res://resources/pamana/,
# and this class only finds the files and answers which items exist and which one
# has this id. A new .tres in that folder is sold, ruled and listed in the
# Almanac without touching code - except its rule, which GodMatch keys by id.
#
# (Re)generate the files with tools/build_pamana.gd, or edit the .tres by hand.

const PAMANA_DIR := "res://resources/pamana"

# The ids GodMatch's rules are keyed by.
const MANUNGGUL_JAR := &"manunggul_jar"
const TORN_CEDULAS := &"torn_cedulas"
const BANTON_CLOTH := &"banton_cloth"
const BATO_BATO_SA_LANGIT := &"bato_bato_sa_langit"
const AGIMAT := &"agimat"
const MIGHTY_PEN := &"mighty_pen"
const MUTYA := &"mutya"
const KAMPILAN := &"kampilan"
const MINIATURE_BALANGAY := &"miniature_balangay"
const SURIGAO_GOLD := &"surigao_gold"

static var _items: Dictionary = {}  # id -> Pamana
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_items.clear()
	var dir := DirAccess.open(PAMANA_DIR)
	if dir == null:
		push_error("Pamanas: cannot open %s - the Pamana resources are missing" % PAMANA_DIR)
		return
	var files := dir.get_files()
	files.sort()
	for file in files:
		# Exported builds list foo.tres.remap, not foo.tres (load() follows the
		# remap to the packed .res). Strip it so the registry still finds items.
		if file.ends_with(".remap"):
			file = file.trim_suffix(".remap")
		if not file.ends_with(".tres"):
			continue
		var item: Pamana = load("%s/%s" % [PAMANA_DIR, file])
		if item == null or item.id == &"":
			continue
		_items[item.id] = item


# Every Pamana, sorted by id so every screen lists them in the same order.
static func all() -> Array[Pamana]:
	_load()
	var items: Array[Pamana] = []
	for id in _items.keys():
		items.append(_items[id])
	items.sort_custom(func(a: Pamana, b: Pamana): return str(a.id) < str(b.id))
	return items


# The Pamana with this id, or null.
static func by_id(pamana_id: StringName) -> Pamana:
	_load()
	return _items.get(pamana_id, null)
