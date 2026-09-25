extends PanelContainer

# One FAVOR skill slot - the E bar on the left, the Q bar on the right.
#   no favor bound to the slot -> the bar stays blank
#   favor ready to use         -> the bar is full
#   favor on cooldown          -> the bar slowly refills

const COLOR_READY := Color(1, 1, 1, 1)
const COLOR_COOLING := Color(1, 1, 1, 0.6)
const COLOR_EMPTY := Color(0.42, 0.45, 0.55, 1)

@onready var fill: ColorRect = $Body/Fill
@onready var text_label: Label = $Body/Text

var key_text := "E"
var favor: GodFavor = null

var _ratio := 0.0
var _remaining := 0.0


func _ready() -> void:
	set_favor(null)


# Call once so the bar knows which key it stands for.
func setup(new_key: String) -> void:
	key_text = new_key
	_refresh_text()


# Only call when the bound favor actually changes - it resets the fill.
func set_favor(new_favor: GodFavor) -> void:
	favor = new_favor
	if favor == null:
		_ratio = 0.0
		_remaining = 0.0
		fill.visible = false
	else:
		fill.visible = true
		fill.color = favor.color
		_ratio = 1.0
		_remaining = 0.0
	_refresh_text()


# ratio: 1.0 = ready, 0.0 = just used. remaining: seconds of cooldown left.
func set_state(ratio: float, remaining: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	_remaining = maxf(0.0, remaining)
	if fill.visible:
		fill.anchor_right = _ratio
	_refresh_text()


func _refresh_text() -> void:
	if favor == null:
		text_label.text = "%s  --" % key_text
		text_label.add_theme_color_override("font_color", COLOR_EMPTY)
		return
	if _ratio >= 1.0:
		text_label.text = "%s  %s  READY" % [key_text, favor.display_name.to_upper()]
		text_label.add_theme_color_override("font_color", COLOR_READY)
		return
	text_label.text = "%s  %s  %ds" % [key_text, favor.display_name.to_upper(), int(ceil(_remaining))]
	text_label.add_theme_color_override("font_color", COLOR_COOLING)
