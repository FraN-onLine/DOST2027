extends CanvasLayer

# BATHALA - the opening cutscene, played once at the start of a run, before the
# first god's intro (Game.gd). Bathala takes Ines from her suitors and drops them
# into the gods' arena; the roll call is after the God Games in EPIC: The Musical.
#
# WRITERS' NOTE (the lead's intent): Bathala wants to determine whether mortals
# understand what it means to love someone or whether they merely want to possess
# someone they believe they deserve. Keep his tone amused and a little cruel, never
# a plain villain - he is testing them, and the gods' trials echo the same question.
#
# The script is DATA (resources/opening_cutscene.tres, a Cutscene): each step is a
# line {speaker, text, call?} or a stage direction {action}. ACTIONS below is every
# direction this scene can stage; each one is a short placeholder tween (coloured
# shapes, the existing god portraits) that real art drops into - see the OPENING
# CUTSCENE slots in UI/theme/ART_SLOTS.md.
#
# SKIP: hold the advance key (or press Esc) to skip the whole cutscene. In
# multiplayer only the host may skip, and the host's skip skips it for everyone.
#
# MULTIPLAYER: it goes through the same dialogue handshake as the trials
# (Network.report_dialogue_finished / release_dialogue). Every line is a barrier
# ("opening_<step>") so all screens read in step; the host's skip is the barrier
# "opening_skip"; "opening" is the end, released when everyone has finished.

signal finished()

const SCRIPT_DATA: Cutscene = preload("res://resources/opening_cutscene.tres")
const DIALOGUE_SCENE := preload("res://UI/GodsArena/god_dialogue.tscn")

const ACTIONS := ["ines_and_suitors", "hand_seizes", "bathala_appears", "regards",
	"suitors_fall", "gods_appear", "fade"]
const ROLL_CALL: Array[StringName] = [Gods.MAYARI, Gods.APOLAKI, Gods.HANAN, Gods.TALA, Gods.MAPULON_IKAPATI]

const HOLD_TO_SKIP := 0.8      # seconds the advance key is held to skip
const END_TOKEN := "opening"
const SKIP_TOKEN := "opening_skip"
const POLL := 0.1              # how often a screen looks for the handshake's release

const DAY_SKY := Color("#78B8F0")
const DAY_GROUND := Color("#5E8F4E")
const STORM_SKY := UITokens.NIGHT_900
const ARENA_SKY := UITokens.NIGHT_700
const ARENA_FLOOR := UITokens.NIGHT_600
const ACTOR := Vector2(72, 96)
const HAND := Vector2(80, 100)
const SLOT := Vector2(120, 120)

@onready var stage: Control = $Stage
@onready var sky: ColorRect = $Stage/Sky
@onready var ground: ColorRect = $Stage/Ground
@onready var ines: TextureRect = $Stage/Ines
@onready var suitors: Array[TextureRect] = [$Stage/Suitor1, $Stage/Suitor2]
@onready var god_row: Control = $Stage/GodRow
@onready var bathala: TextureRect = $Stage/Bathala
@onready var hand: ColorRect = $Stage/Hand
@onready var arm: ColorRect = $Stage/Hand/Arm
@onready var call_label: Label = $Stage/CallLabel
@onready var skip_hint: Label = $Stage/SkipHint
@onready var fade: ColorRect = $Stage/Fade

var can_skip := true      # Game.gd turns it off for a client: the host decides
var skipped := false
var dialogue: Control
var _size := Vector2(1152, 648)
var _floor_y := 0.0
var _slots := {}          # god id -> TextureRect
var _active: Tween        # the stage direction being played
var _hold := 0.0
var _networked := false
var _released := {}       # handshake token -> true


func _ready() -> void:
	_size = get_viewport().get_visible_rect().size
	_floor_y = _size.y * 0.62
	_networked = Network.has_multiplayer_peer()
	if _networked:
		Network.dialogue_released.connect(_on_released)
	dialogue = DIALOGUE_SCENE.instantiate()
	add_child(dialogue)  # it draws no shade of its own: the art is the point of this scene
	_set_stage()
	skip_hint.visible = can_skip
	skip_hint.text = "HOLD %s OR PRESS ESC TO SKIP" % UITokens.key_text(&"advance_dialogue")


# Everything back to the start: a bright day, the ground, nobody on stage yet.
func _set_stage() -> void:
	sky.color = DAY_SKY
	ground.color = DAY_GROUND
	ground.position = Vector2(0, _floor_y)
	ground.size = Vector2(_size.x, _size.y - _floor_y)
	var xs := [0.5, 0.28, 0.72]
	for index in range(3):
		var actor: TextureRect = ines if index == 0 else suitors[index - 1]
		actor.size = ACTOR
		actor.pivot_offset = ACTOR / 2.0
		actor.position = Vector2(_size.x * xs[index] - ACTOR.x / 2.0, _floor_y - ACTOR.y)
		actor.modulate = Color(1, 1, 1, 0)
	ines.self_modulate = Color("#F4A6C0")                 # placeholder: art slot ines
	suitors[0].self_modulate = UITokens.bandana_color(0)  # placeholders: art slot suitor_1 / suitor_2
	suitors[1].self_modulate = UITokens.bandana_color(1)
	bathala.size = Vector2(180, 180)
	bathala.pivot_offset = bathala.size / 2.0
	bathala.position = Vector2(_size.x / 2.0 - 90.0, -220.0)
	hand.size = HAND
	arm.position = Vector2(HAND.x * 0.25, -700.0)
	arm.size = Vector2(HAND.x * 0.5, 700.0)
	hand.position = Vector2(0, -200.0)
	hand.modulate.a = 0.0
	call_label.size = Vector2(_size.x, 110)
	call_label.position = Vector2(0, _size.y * 0.38)
	call_label.pivot_offset = call_label.size / 2.0
	call_label.modulate.a = 0.0
	skip_hint.size = Vector2(420, 24)
	skip_hint.position = Vector2(_size.x - 420 - 16, 12)
	skip_hint.modulate.a = 0.5
	var row_w := SLOT.x * ROLL_CALL.size() + 16.0 * (ROLL_CALL.size() - 1)
	for index in range(ROLL_CALL.size()):
		var god := Gods.by_id(ROLL_CALL[index])
		var slot := TextureRect.new()
		slot.texture = god.portrait if god.portrait != null else god.icon
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.size = SLOT
		slot.position = Vector2((_size.x - row_w) / 2.0 + index * (SLOT.x + 16.0), 214.0)
		slot.modulate = Color(0.04, 0.05, 0.1, 0.0)  # a silhouette, until its name is called
		god_row.add_child(slot)
		_slots[god.id] = slot


# --- PLAY -------------------------------------------------------------------

func play() -> void:
	for index in range(SCRIPT_DATA.steps.size()):
		if skipped:
			break
		var step: Dictionary = SCRIPT_DATA.steps[index]
		if step.has("action"):
			await call("_do_%s" % step["action"])
		else:
			await _say(step, index)
	if skipped and fade.color.a < 1.0:
		var quick := _tween()
		quick.tween_property(fade, "color:a", 1.0, 0.3)
		await quick.finished
	await _barrier(END_TOKEN)
	finished.emit()


func _say(step: Dictionary, index: int) -> void:
	dialogue.show_lines([Cutscene.entry_for(step)])
	if step.has("call"):
		_call_out(StringName(str(step["call"])), str(step["text"]))
	await dialogue.finished
	if not skipped:
		await _barrier("%s_%d" % [END_TOKEN, index])


# Waits until every screen has reached `token` (the dialogue handshake). A solo run
# never waits. The host releases it once all have reported - or at once for a late
# joiner it is told about - and a client simply waits for that release.
func _barrier(token: String) -> void:
	if not _networked:
		return
	Network.report_dialogue_finished(token)
	var waited := 0.0
	while not _released.has(token) and not (skipped and token != END_TOKEN):
		await get_tree().create_timer(POLL).timeout
		waited += POLL
		if multiplayer.is_server():
			if Network.dialogue_finished_count(token) >= Network.players.size():
				Network.release_dialogue(token)
			elif skipped and fmod(waited, 1.0) < POLL:
				# A screen that loaded after the host skipped never heard it: say it again.
				Network.release_dialogue(SKIP_TOKEN)


func _on_released(token: String) -> void:
	_released[token] = true
	if token == SKIP_TOKEN:
		skip(true)


# --- SKIP -------------------------------------------------------------------

func _process(delta: float) -> void:
	if not can_skip or skipped:
		return
	if Input.is_action_pressed(&"advance_dialogue"):
		_hold += delta
		skip_hint.modulate.a = lerpf(0.5, 1.0, clampf(_hold / HOLD_TO_SKIP, 0.0, 1.0))
		if _hold >= HOLD_TO_SKIP:
			skip()
	else:
		_hold = 0.0
		skip_hint.modulate.a = 0.5


func _input(event: InputEvent) -> void:
	if can_skip and not skipped and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		skip()


# `ordered` is the host's skip arriving at a client; a local skip is the host's own.
func skip(ordered := false) -> void:
	if skipped or not (can_skip or ordered):
		return
	skipped = true
	if _networked and multiplayer.is_server():
		Network.release_dialogue(SKIP_TOKEN)
	if _active != null and _active.is_valid():
		_active.custom_step(100.0)  # finish the stage direction on the spot
	if dialogue.is_active():
		dialogue.close_now()


# --- STAGE DIRECTIONS ---------------------------------------------------------

func _tween() -> Tween:
	return create_tween()


# Plays a tween to its end (a skip finishes it at once, and later ones not at all).
func _run(tween: Tween) -> void:
	if skipped:
		tween.kill()
		return
	_active = tween
	await tween.finished
	_active = null


func _shake(strength: float, seconds: float) -> void:
	var tween := create_tween()
	for step in range(int(seconds / 0.04)):
		tween.tween_property(stage, "position", Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength, 0.04)
	tween.tween_property(stage, "position", Vector2.ZERO, 0.04)


# [Ines and the suitors] Ines and two suitors on the ground under a daytime sky.
func _do_ines_and_suitors() -> void:
	var tween := _tween()
	for actor in [ines, suitors[0], suitors[1]]:
		tween.parallel().tween_property(actor, "modulate:a", 1.0, 0.5)
	tween.tween_interval(0.3)
	await _run(tween)


# [A deafening rumble. The sky darkens. A great hand descends from the clouds and
# seizes Ines.] Screen shake, the sky tints dark, a hand lifts Ines out of frame.
func _do_hand_seizes() -> void:
	_shake(7.0, 1.6)
	var hand_x := ines.position.x + ACTOR.x / 2.0 - HAND.x / 2.0
	hand.position = Vector2(hand_x, -200.0)
	hand.modulate.a = 1.0
	var tween := _tween()
	tween.tween_property(sky, "color", STORM_SKY, 0.8)
	tween.parallel().tween_property(ground, "color", DAY_GROUND.darkened(0.7), 0.8)
	tween.tween_property(hand, "position:y", ines.position.y - HAND.y + 20.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(0.15)
	tween.tween_property(hand, "position:y", -_size.y, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(ines, "position:y", -_size.y + HAND.y - 20.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(0.2)
	await _run(tween)


# [BATHALA appears above them, holding Ines in his palm.] Bathala's portrait at the
# top, Ines small in his hand.
func _do_bathala_appears() -> void:
	var palm := Vector2(_size.x / 2.0 + 130.0, 70.0)
	hand.position = Vector2(palm.x, -200.0)
	ines.scale = Vector2(0.5, 0.5)
	ines.position = Vector2(palm.x + 4.0, -266.0)
	var tween := _tween()
	tween.tween_property(bathala, "position:y", 10.0, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(hand, "position", palm, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(ines, "position", Vector2(palm.x + 4.0, palm.y - 66.0), 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.2)
	await _run(tween)


# [He regards the two mortals with amusement.] A slow, pleased sway.
func _do_regards() -> void:
	var tween := _tween()
	for sway in range(2):
		tween.tween_property(bathala, "rotation_degrees", 4.0, 0.3)
		tween.tween_property(bathala, "rotation_degrees", -4.0, 0.3)
	tween.tween_property(bathala, "rotation_degrees", 0.0, 0.2)
	tween.tween_interval(0.1)
	await _run(tween)


# [The ground beneath the suitors disappears... They plummet into a vast celestial
# arena, landing before the assembled Gods.] The suitors drop, a quick fall, and
# land in the celestial arena.
func _do_suitors_fall() -> void:
	var tween := _tween()
	tween.tween_property(ground, "modulate:a", 0.0, 0.25)
	for suitor in suitors:
		tween.parallel().tween_property(suitor, "position:y", _size.y + 100.0, 0.6).set_delay(0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_interval(0.05)
	await _run(tween)
	_shake(5.0, 0.3)
	sky.color = ARENA_SKY
	ground.color = ARENA_FLOOR
	ground.modulate.a = 1.0
	for suitor in suitors:
		suitor.position.y = -ACTOR.y - 40.0
	tween = _tween()
	for suitor in suitors:
		tween.parallel().tween_property(suitor, "position:y", _floor_y - ACTOR.y, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.1)
	await _run(tween)
	_shake(6.0, 0.25)


# [The Gods appear one by one.] Five silhouettes, one after the other.
func _do_gods_appear() -> void:
	var tween := _tween()
	for index in range(ROLL_CALL.size()):
		var slot: TextureRect = _slots[ROLL_CALL[index]]
		tween.tween_property(slot, "modulate:a", 0.85, 0.15).set_delay(0.1 if index > 0 else 0.0)
	tween.tween_interval(0.2)
	await _run(tween)


# [screen fade] To black; the run goes on from there.
func _do_fade() -> void:
	var tween := _tween()
	tween.tween_property(fade, "color:a", 1.0, 0.9)
	await _run(tween)


# The roll call: the name pops up big as Bathala calls it and the god's portrait
# slides in, quick. Not awaited - the line is on the dialogue box meanwhile.
func _call_out(god_id: StringName, text: String) -> void:
	var god := Gods.by_id(god_id)
	call_label.text = text
	call_label.add_theme_color_override("font_color", UITokens.readable_on_dark(god.color, UITokens.NIGHT_900))
	call_label.scale = Vector2(0.4, 0.4)
	call_label.modulate.a = 1.0
	var pop := create_tween()
	pop.tween_property(call_label, "scale", Vector2(1.15, 1.15), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(call_label, "scale", Vector2.ONE, 0.08)
	pop.tween_interval(0.8)
	pop.tween_property(call_label, "modulate:a", 0.0, 0.3)
	var slot: TextureRect = _slots.get(god_id)
	if slot != null:
		var home := slot.position.x
		slot.modulate = Color.WHITE
		slot.position.x = home + (260.0 if slot.position.x > _size.x / 2.0 else -260.0)
		create_tween().tween_property(slot, "position:x", home, 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	elif god_id == Gods.BATHALA:
		var beat := create_tween()
		beat.tween_property(bathala, "scale", Vector2(1.2, 1.2), 0.14)
		beat.tween_property(bathala, "scale", Vector2.ONE, 0.2)
