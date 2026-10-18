class_name AgawanGod
extends Node2D

# One of Bathala's gods in AGAWAN BASE - Apolaki, Mayari, Tala, Hanan - or
# Bathala himself, circling the base he guards. (scripts/gods/bathala)
#
# A god does four things, in this order of priority:
#   * GUARD   Bathala (and the defensive gods, Tala and Hanan) stay near their
#             own base and circle it; an attacker that steps close still gets a
#             chance to be tagged, so the base is never truly safe to walk past.
#   * ATTACK  the offensive gods (Apolaki, Hanan) push towards the enemy base and
#             tag any mortal they catch in the common field - they may switch to
#             defending when a mortal threatens the base, and a defensive god may
#             seize the moment to attack when a mortal is close and exposed.
#   * TAG     touching a mortal freezes it for freeze_time seconds (or until a
#             teammate attacks it): the frozen god/mortal carries a countdown over
#             its head. The same attack that freezes a god UNFREEZES a frozen one.
#   * FROZEN  while frozen a god stands still, cannot tag, and slowly thaws on its
#             own (freeze_time) - or instantly when an enemy attacks it.
#
# A mortal is NEVER taggable on its own base (the safe zone), and a god is never
# taggable on its own base either. The BathalaArena owns the rules; this node only
# walks, decides a role moment to moment and draws the freeze countdown.
#
# The art lives in AgawanGod.tscn (Icon, Ring, Name, Timer); this script never
# draws. Host-driven only: the host moves every god, the clients mirror the pose
# through the arena's tick fields (see BathalaArena.gd).

enum Role { ATTACK, DEFEND }

const ROLE_COLOR := {
	"apolaki": Color(1.0, 0.55, 0.2),
	"mayari": Color(0.55, 0.85, 1.0),
	"tala": Color(0.7, 0.8, 1.0),
	"hanan": Color(1.0, 0.62, 0.55),
	"bathala": Color(0.78, 0.78, 0.82),
}

@export var move_speed := 150.0        # how fast the god walks (the mortal runs 215)
@export var tag_radius := 24.0         # how close before a touch counts as a tag
@export var guard_radius := 90.0       # how far a guarding god circles its base
@export var defend_wake := 210.0       # a mortal this close wakes a defensive god to attack
@export var attack_switch := 170.0     # an attacker this close to its base drops back to guard
@export var decision_interval := 0.5   # seconds between role re-decisions (not every frame)

var god_id: StringName = &""
var role: Role = Role.ATTACK
var base_center := Vector2.ZERO       # the base this god defends (its own base)
var target_center := Vector2.ZERO     # the base this god is trying to capture
var circle_phase := 0.0               # where around its base a guarding god stands
var circle_dir := 1.0

var frozen := false                   # true while tagged / thawing
var freeze_left := 0.0

var _think := 0.0
var _wander := Vector2.ZERO
var _pulse := 0.0

@onready var icon: Sprite2D = get_node_or_null("Icon")
@onready var ring: Line2D = get_node_or_null("Ring")
@onready var name_label: Label = get_node_or_null("Name")
@onready var timer_label: Label = get_node_or_null("Timer")


func _ready() -> void:
	_refresh_visual()


func god_color() -> Color:
	return ROLE_COLOR.get(str(god_id), Color.WHITE)


# The base this god protects, and the enemy base it would love to capture.
func set_stage(own_base: Vector2, enemy_base: Vector2) -> void:
	base_center = own_base
	target_center = enemy_base


# An enemy attack: the god freezes for freeze_time. The arena passes it in.
func freeze_for(seconds: float) -> void:
	frozen = true
	freeze_left = maxf(0.0, seconds)


# A friendly attack: the same swing that tags a foe thaws an ally god instantly.
func unfreeze() -> void:
	frozen = false
	freeze_left = 0.0


# Where this god wants to walk this frame. Bathala always circles his base; the
# others keep a little distance from whoever is nearest so they do not all stack.
func _desired_position(nearest_mortal: Vector2) -> Vector2:
	if god_id == &"bathala":
		return _circle_point(base_center)
	# A guarding god keeps its base in reach; an attacker pushes for the enemy base.
	var anchor: Vector2 = base_center if role == Role.DEFEND else target_center
	# If the closest mortal is right here, react: defenders wake to attack, attackers
	# drop back to guard - Bathala's gods read the moment, they are not scripted.
	if role == Role.DEFEND and nearest_mortal != Vector2.INF \
			and nearest_mortal.distance_to(base_center) < defend_wake:
		return nearest_mortal
	if role == Role.ATTACK and nearest_mortal != Vector2.INF \
			and nearest_mortal.distance_to(target_center) < attack_switch:
		return base_center
	# Otherwise drift towards the anchor with a slow wander so they spread out.
	if _wander == Vector2.ZERO:
		_wander = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 40.0
	return anchor + _wander


# A point on the circle Bathala walks around his base - he never leaves the guard.
func _circle_point(center: Vector2) -> Vector2:
	circle_phase += circle_dir * 0.9 * 0.016  # a slow, steady orbit
	return center + Vector2(cos(circle_phase), sin(circle_phase) * 0.55) * guard_radius


# The host walks the god here each frame (a client mirrors it through the tick).
# A frozen god stands still and simply counts down; when the count reaches zero it
# thaws on its own and rejoins the fight. (A friendly attack thaws it early.)
func step(delta: float, nearest_mortal: Vector2) -> void:
	if frozen:
		freeze_left = maxf(0.0, freeze_left - delta)
		if freeze_left <= 0.0:
			frozen = false  # thawed on its own
		_pulse += delta
		_refresh_visual()
		return
	_think -= delta
	if _think <= 0.0:
		_think = decision_interval
		_wander = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 40.0
		if randf() < 0.5:
			circle_dir = -circle_dir
	var goal := _desired_position(nearest_mortal)
	global_position = global_position.move_toward(goal, move_speed * delta)
	_pulse += delta
	_refresh_visual()


# Mirror pose on a client.
func place(at: Vector2) -> void:
	global_position = at


func is_frozen() -> bool:
	return frozen


func _refresh_visual() -> void:
	var tint := god_color()
	if icon != null:
		# A frozen god dims; a hunting one burns a little brighter.
		var alpha := 0.55 if frozen else 0.92 + 0.08 * sin(_pulse * 5.0)
		icon.modulate = Color(tint.r, tint.g, tint.b, alpha)
	if ring != null:
		ring.default_color = Color(tint.r, tint.g, tint.b, 0.5)
		ring.visible = not frozen
	if name_label != null:
		name_label.text = str(god_id).to_upper()
		name_label.modulate = Color(1, 1, 1, 0.55 if frozen else 0.75)
	if timer_label != null:
		if frozen:
			timer_label.visible = true
			timer_label.text = "%d" % int(ceil(freeze_left))
			timer_label.add_theme_color_override("font_color", UITokens.EMBER)
		else:
			timer_label.visible = false

