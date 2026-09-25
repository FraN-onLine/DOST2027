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


func param(key: String, fallback: float) -> float:
	return float(params.get(key, fallback))
