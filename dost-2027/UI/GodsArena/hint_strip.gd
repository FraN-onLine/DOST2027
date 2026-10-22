class_name HintStrip
extends PanelContainer

# The controls hint under the field: one line of BODY (16 px) text on the HUD plate,
# with every key drawn as a keycap. An arena writes it like a label -
#
#     hint_label.text = "[%s] THROW    [WASD] MOVE" % UITokens.key_text(&"attack")
#
# - and each [...] becomes a KeycapLabel, the words between them captions. Setting
# the same text again (the arenas refresh their HUD every frame) changes nothing.

const CAPTION_COLOR := UITokens.MUTED

var text := "":
	set = set_text

var _row: HBoxContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", UITokens.SPACE_8)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)


func _ready() -> void:
	add_theme_stylebox_override("panel", get_theme_stylebox("normal", &"HudLabel"))
	_build()


func set_text(value: String) -> void:
	if value == text:
		return
	text = value
	if is_node_ready():
		_build()


# The pieces of `text`: [{"key": bool, "text": String}], keys and captions in order.
static func parse(markup: String) -> Array[Dictionary]:
	var pieces: Array[Dictionary] = []
	var regex := RegEx.create_from_string("\\[([^\\]]+)\\]")
	var at := 0
	for found in regex.search_all(markup):
		var before := markup.substr(at, found.get_start() - at).strip_edges()
		if before != "":
			pieces.append({"key": false, "text": before})
		pieces.append({"key": true, "text": found.get_string(1).strip_edges()})
		at = found.get_end()
	var rest := markup.substr(at).strip_edges()
	if rest != "":
		pieces.append({"key": false, "text": rest})
	return pieces


func _build() -> void:
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	var pieces := parse(text)
	visible = not pieces.is_empty()
	for index in pieces.size():
		var piece: Dictionary = pieces[index]
		var label := Label.new()
		label.text = str(piece["text"]).to_upper()
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if piece["key"]:
			label.theme_type_variation = &"KeycapLabel"
		else:
			label.add_theme_color_override("font_color", CAPTION_COLOR)
			# a caption closes its group: the next key starts a new one, further off
			if index + 1 < pieces.size():
				var gap := Control.new()
				gap.custom_minimum_size.x = UITokens.SPACE_8
				gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_row.add_child(label)
				_row.add_child(gap)
				continue
		_row.add_child(label)


# The hint as plain words, the keys in brackets (what the checks read).
func plain_text() -> String:
	return text
