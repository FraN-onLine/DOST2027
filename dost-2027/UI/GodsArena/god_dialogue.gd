extends Control

# God dialogue box: the god speaks (name colored with the god's color), you read,
# press SPACE or click to advance. Used for the intro, the hand-off to the next
# god and the closing lines after the trial.
#
# LAYERING: this scene is instanced into Arena's UILayer (CanvasLayer layer 10)
# and re-parented into a dedicated DialogueLayer (layer 50) on ready, so the
# portrait + box sit ABOVE every game UI element (attack bars at layer 11-12,
# HUD, popups). The god's photo docks right; the box sits bottom, kept short so
# most of the field stays in view; the name nub sticks out ABOVE the box like a
# folder tab. The arena dims the FIELD while a line is up (Arena.field_dim) -
# never the HUD, so this scene draws no shade of its own.
#
# ONE PORTRAIT: the god is shown once, as the big photo. The small framed portrait
# in the box is only used for a SECOND face ("beside", Ines next to Bathala).
#
# Presentation (UI/theme): the name tab is a Nameplate in the speaker's accent
# with the name, upper case, in its readable form (readable_on_dark); the
# small portrait (when shown) is framed in the same accent; the line is BODY ivory; the
# advance key is a keycap from the player's bindings (advance_dialogue) that
# blinks slowly - and holds still with reduce flashing on.
#
# VOICE: each entry may carry "voice" (AudioStream) and "portrait" (Texture2D).
# "voice" plays alongside that line; "portrait" swaps the side photo for that
# line only. Both optional - missing means silent / keep current photo.
# Two more optional keys: "hide_photo" (no big photo for this line - a speaker with
# no art yet) and "beside" (a Texture2D for the small portrait only, so a second
# face stands next to the speaker's photo - Ines beside Bathala).

signal finished()

@onready var photo: TextureRect = $Photo
@onready var voice: AudioStreamPlayer = $Voice
@onready var box: PanelContainer = $Box
@onready var name_tab: PanelContainer = $NameTab
@onready var name_label: Label = $NameTab/NameLabel
@onready var portrait_frame: PanelContainer = $Box/Margin/HBox/PortraitFrame
@onready var portrait: TextureRect = $Box/Margin/HBox/PortraitFrame/Portrait
@onready var line_label: Label = $Box/Margin/HBox/VBox/LineLabel
@onready var advance_key: Label = $Box/Margin/HBox/VBox/HintRow/AdvanceKey
@onready var hint_label: Label = $Box/Margin/HBox/VBox/HintRow/HintLabel

const BLINK_SECONDS := 0.8   # each half of the advance key's slow blink

var _lines: Array = []
var _index := 0
var _active := false
var _blink: Tween

func _ready() -> void:
	visible = false
	# Overlay over everything: lift out of UILayer (10) into our own layer
	# above attack bars (11-12) and any arena CanvasLayers.
	_ensure_top_layer()


# Move this Control under a dedicated CanvasLayer (layer 50) when it lives
# inside a CanvasLayer at a lower level (Arena's UILayer is 10, attack bars
# are 11-12). Safe to call repeatedly; no-op when already topmost or when
# there is no CanvasLayer ancestor (unit tests add it straight to the root).
func _ensure_top_layer() -> void:
	var on_layer := false
	var ancestor: Node = get_parent()
	while ancestor != null:
		if ancestor is CanvasLayer:
			on_layer = true
			if (ancestor as CanvasLayer).layer >= 50 and ancestor.name == &"DialogueLayer":
				return
			break
		ancestor = ancestor.get_parent()
	if not on_layer:
		return
	var host: Node = get_parent()
	var layer := CanvasLayer.new()
	layer.name = &"DialogueLayer"
	layer.layer = 50
	host.add_child(layer)
	host.remove_child(self)
	layer.add_child(self)


func is_active() -> bool:
	return _active


# entries: Array of Dictionaries -> {"speaker": String, "color": Color, "text": String,
#                                    "portrait": Texture2D (opt), "voice": AudioStream (opt)}
# `fallback_portrait` is the god's Tres portrait (used when an entry has none).
func show_lines(entries: Array, fallback_portrait: Texture2D = null) -> void:
	if entries.is_empty():
		return
	_lines = entries.duplicate()
	_index = 0
	_active = true
	visible = true
	for entry in _lines:
		if entry is Dictionary and not entry.has("portrait") and fallback_portrait != null:
			(entry as Dictionary)["portrait"] = fallback_portrait
	advance_key.text = UITokens.key_text(&"advance_dialogue")
	_start_blink()
	_render()


# The advance key breathes slowly so a reader knows the box is waiting on them.
func _start_blink() -> void:
	if _blink != null and _blink.is_valid():
		_blink.kill()
	advance_key.modulate.a = 1.0
	if not is_inside_tree() or UITokens.calm():
		return
	_blink = create_tween().set_loops()
	_blink.tween_property(advance_key, "modulate:a", 0.35, BLINK_SECONDS)
	_blink.tween_property(advance_key, "modulate:a", 1.0, BLINK_SECONDS)


func _render() -> void:
	if _index >= _lines.size():
		_close()
		return
	var entry: Dictionary = _lines[_index]
	var speaker_color: Color = entry.get("color", Color.WHITE)
	var accent := UITokens.readable_on_dark(speaker_color, UITokens.NIGHT_800, UITokens.ACCENT_CONTRAST)
	name_label.text = str(entry.get("speaker", "")).to_upper()
	name_label.add_theme_color_override("font_color", UITokens.readable_on_dark(speaker_color, UITokens.NIGHT_700))
	name_tab.add_theme_stylebox_override("panel", UITokens.accent_box(name_tab.get_theme_stylebox("panel", &"Nameplate"), accent))
	portrait_frame.add_theme_stylebox_override("panel", UITokens.accent_box(portrait_frame.get_theme_stylebox("panel", &"PanelInset"), accent))
	line_label.text = str(entry.get("text", ""))
	hint_label.text = "CLOSE" if _index == _lines.size() - 1 else "NEXT"
	var tex = entry.get("portrait", null)
	if tex is Texture2D:
		photo.texture = tex
		photo.visible = true
	else:
		photo.visible = photo.texture != null
	if entry.get("hide_photo", false):
		photo.visible = false
	# The speaker is already the big photo: the small frame only carries a second
	# face - or the speaker, when a line hides the big photo.
	var beside = entry.get("beside", null)
	portrait.visible = false
	if beside is Texture2D:
		portrait.texture = beside
		portrait.visible = true
	elif not photo.visible and tex is Texture2D:
		portrait.texture = tex
		portrait.visible = true
	portrait_frame.visible = portrait.visible
	_play_voice(entry.get("voice", null))


# One voice line at a time: stop the previous line before starting the next so
# overlapping advances never stack audio. Null / missing = silent advance.
func _play_voice(stream) -> void:
	if voice.playing:
		voice.stop()
	if stream is AudioStream:
		voice.stream = stream
		voice.play()


func advance() -> void:
	if not _active:
		return
	_index += 1
	if _index >= _lines.size():
		_close()
	else:
		_render()


func close_now() -> void:
	# Used when the host's trial moves on before we finished reading.
	if _active:
		_close()


func _close() -> void:
	_active = false
	visible = false
	if _blink != null and _blink.is_valid():
		_blink.kill()
	if voice.playing:
		voice.stop()
	finished.emit()


func _input(event: InputEvent) -> void:
	if not _active:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var advance_pressed := event.is_action_pressed("advance_dialogue")
	var clicked := false
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		clicked = mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
	if advance_pressed or clicked:
		viewport.set_input_as_handled()
		advance()
