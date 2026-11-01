extends CanvasLayer

# The full-screen gale every arena shares (Anitun Tabu's West Wind). The arena
# only says whether it should be blowing; the fade in and out lives here, so a
# cast rolls over the field instead of snapping on.

@onready var gale: ColorRect = $Gale

var _target := 0.0
var _strength := 0.0


func _ready() -> void:
	visible = false
	_apply(0.0)


# Called every frame by the arena (see Arena._tick_wind).
func set_active(active: bool) -> void:
	_target = 1.0 if active else 0.0
	if _target > 0.0:
		visible = true


func _process(delta: float) -> void:
	if is_equal_approx(_strength, _target):
		return
	_strength = move_toward(_strength, _target, delta * 1.8)
	_apply(_strength)
	if _strength <= 0.0:
		visible = false


func _apply(strength: float) -> void:
	if gale == null:
		return
	var mat := gale.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("intensity", strength)
	gale.modulate.a = strength
