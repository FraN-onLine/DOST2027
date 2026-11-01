class_name GodFavor
extends Resource

# A God's Favor - a boon the gods can bestow on a mortal.
# Favors are unlocked with a "God's Due" voucher and either apply passively,
# bind to the E / Q skill slot, or fire once (instant / end of trial).
# Everything here is data so the same Resource can be reused by the arena,
# the HUD, the God's Due menu and (later) the network layer.

enum Slot { PASSIVE, E, Q }
enum Kind { PASSIVE, ACTIVE, INSTANT, END_OF_TRIAL }

@export var id: StringName = &""
@export var god_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var slot: Slot = Slot.PASSIVE
@export var kind: Kind = Kind.PASSIVE
@export var cooldown: float = 0.0
@export var duration: float = 0.0
@export var color: Color = Color.WHITE
@export var icon: Texture2D
@export var params: Dictionary = {}


func slot_name() -> String:
	match slot:
		Slot.E:
			return "E"
		Slot.Q:
			return "Q"
	return "PASSIVE"


func is_skill() -> bool:
	return slot == Slot.E or slot == Slot.Q


func requires_god_id() -> StringName:
	return StringName(str(params.get("requires_god", "")))


# "requires_favor": "mustve_been_the_wind" - only offered while the mortal holds
# that exact favor (Mayari's and Apolaki's siblings ask for each other).
func requires_favor_id() -> StringName:
	return StringName(str(params.get("requires_favor", "")))


# "requires_slot": "Q" - only offered while the mortal holds any skill of that
# slot (It's Kinda Tabu rides whichever Q they carry).
func requires_slot() -> int:
	match str(params.get("requires_slot", "")).to_upper():
		"E":
			return Slot.E
		"Q":
			return Slot.Q
	return -1


# "requires_any_god": ["mayari", "tala"] - offered while the mortal holds a favor
# of at least one of them (empty = no such rule).
func requires_any_god_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in params.get("requires_any_god", []):
		ids.append(StringName(str(id)))
	return ids


func param(key: String, fallback: float) -> float:
	return float(params.get(key, fallback))


# "gale_immunity": true - while this favor is held its owner walks through the
# gales untouched (The West Wind makes its own wind).
func gale_immunity() -> bool:
	return bool(params.get("gale_immunity", false))
