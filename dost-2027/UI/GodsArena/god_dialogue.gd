extends Control

# God dialogue box: the god speaks (name colored with the god's color), you read,
# press SPACE or click to advance. Used for the intro, the hand-off to the next
# god and the closing lines after the trial.

signal finished()

@onready var speaker_label: Label = $Box/Margin/HBox/VBox/SpeakerLabel
@onready var line_label: Label = $Box/Margin/HBox/VBox/LineLabel
@onready var hint_label: Label = $Box/Margin/HBox/VBox/HintLabel
@onready var portrait: TextureRect = $Box/Margin/HBox/Portrait

var _lines: Array = []
var _index := 0
var _active := false


func _ready() -> void:
	visible = false


func is_active() -> bool:
	return _active


# entries: Array of Dictionaries -> {"speaker": String, "color": Color, "text": String}
func show_lines(entries: Array, portrait_texture: Texture2D = null) -> void:
	if entries.is_empty():
		return
	_lines = entries.duplicate()
	_index = 0
	_active = true
	visible = true
	if portrait_texture != null:
		portrait.texture = portrait_texture
	_render()


func _render() -> void:
	if _index >= _lines.size():
		_close()
		return
	var entry: Dictionary = _lines[_index]
	speaker_label.text = str(entry.get("speaker", ""))
	speaker_label.add_theme_color_override("font_color", entry.get("color", Color.WHITE))
	line_label.text = str(entry.get("text", ""))
	hint_label.text = "SPACE  CLOSE" if _index == _lines.size() - 1 else "SPACE  NEXT"


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
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
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
