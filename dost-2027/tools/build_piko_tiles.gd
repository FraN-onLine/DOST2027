extends SceneTree

# Art build for Sidapa's Piko court: the chalk squares and the start slab.
# Transparent PNGs, so the tile scene can tint them and the court shows through.
# Run: godot --headless --path <project> -s res://tools/build_piko_tiles.gd

const OUT := "res://Assets/Gods/Sidapa"
const CHALK := Color(0.96, 0.95, 0.91)


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_save(_square(84, 6.0, 11), "piko_tile_chalk.png")
	_save(_slab(150, 64, 5.0, 23), "piko_pad_chalk.png")
	print("--- DONE ---")
	quit(0)


func _save(image: Image, file: String) -> void:
	var path := ProjectSettings.globalize_path(OUT.path_join(file))
	print("%s -> %s" % [file, error_string(image.save_png(path))])


# A hand-drawn chalk square: every edge is a wobbly wet stroke, laid down in
# three passes, overshooting the corners the way a kid would.
func _square(size: int, inset: float, seed: int) -> Image:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var low := Vector2(inset, inset)
	var high := Vector2(size - inset, size - inset)
	_edge(image, rng, low, Vector2(high.x, low.y))
	_edge(image, rng, Vector2(high.x, low.y), high)
	_edge(image, rng, high, Vector2(low.x, high.y))
	_edge(image, rng, Vector2(low.x, high.y), low)
	_dust(image, rng, inset - 3.0, size - inset + 3.0, 46)
	return image


# The pad is a slab: one wide chalk box with the same wobble, plus three short
# hatch marks at each end (a starting line, chalked in by hand).
func _slab(width: int, height: int, inset: float, seed: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var low := Vector2(inset, inset)
	var high := Vector2(width - inset, height - inset)
	_edge(image, rng, low, Vector2(high.x, low.y))
	_edge(image, rng, Vector2(high.x, low.y), high)
	_edge(image, rng, high, Vector2(low.x, high.y))
	_edge(image, rng, Vector2(low.x, high.y), low)
	for mark in range(3):
		var y := lerpf(low.y + 13.0, high.y - 13.0, float(mark) / 2.0)
		_rough(image, rng, Vector2(low.x + 9.0, y), Vector2(low.x + 20.0, y), 2.0, 0.5, 1.5)
		_rough(image, rng, Vector2(high.x - 20.0, y), Vector2(high.x - 9.0, y), 2.0, 0.5, 1.5)
	_dust(image, rng, inset - 3.0, height - inset + 3.0, 46)
	return image


func _edge(image: Image, rng: RandomNumberGenerator, from: Vector2, to: Vector2) -> void:
	# Three passes: a soft wide haze, the body, and a bright grain on top.
	_rough(image, rng, from, to, 4.2, 0.16, 5.0)
	_rough(image, rng, from, to, 2.6, 0.30, 4.0)
	_rough(image, rng, from, to, 1.3, 0.42, 3.0)


func _rough(image: Image, rng: RandomNumberGenerator, from: Vector2, to: Vector2,
		width: float, alpha: float, overshoot: float) -> void:
	var way := to - from
	var length := way.length()
	if length < 0.5:
		return
	var direction := way / length
	var normal := Vector2(-direction.y, direction.x)
	var runs := maxi(2, int(length / 5.0))
	var points: Array[Vector2] = []
	for index in range(runs + 1):
		var point := from + way * (float(index) / runs)
		point += normal * rng.randf_range(-1.5, 1.5)
		points.append(point)
	points[0] -= direction * rng.randf_range(overshoot * 0.3, overshoot)
	points[runs] += direction * rng.randf_range(overshoot * 0.3, overshoot)
	for index in range(runs):
		_chalk_line(image, rng, points[index], points[index + 1], width, alpha)


func _chalk_line(image: Image, rng: RandomNumberGenerator, from: Vector2, to: Vector2,
		width: float, alpha: float) -> void:
	var length := from.distance_to(to)
	var steps := maxi(1, int(length / 0.7))
	for step in range(steps + 1):
		var point := from.lerp(to, float(step) / steps)
		point += Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
		_chalk_dot(image, rng, point, width * 0.5, alpha)


func _chalk_dot(image: Image, rng: RandomNumberGenerator, center: Vector2,
		radius: float, alpha: float) -> void:
	var left := int(floor(center.x - radius))
	var top := int(floor(center.y - radius))
	var right := int(ceil(center.x + radius))
	var bottom := int(ceil(center.y + radius))
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
			if distance > radius:
				continue
			var falloff := 1.0 - distance / maxf(0.01, radius)
			# Grit: every grain lands differently, so the stroke never looks solid.
			var grain := rng.randf_range(0.35, 1.0)
			_blend(image, x, y, CHALK, alpha * (0.25 + 0.75 * falloff) * grain)


# A handful of loose chalk crumbs around the drawing.
func _dust(image: Image, rng: RandomNumberGenerator, low: float, high: float, count: int) -> void:
	for speck in range(count):
		var point := Vector2(rng.randf_range(low, high), rng.randf_range(low, high))
		var edge := rng.randf() < 0.5
		if not edge:
			# Keep most crumbs near the outline, where a hand would scuff it.
			var side := rng.randi_range(0, 3)
			if side == 0:
				point.y = low + rng.randf_range(-2.0, 4.0)
			elif side == 1:
				point.y = high + rng.randf_range(-4.0, 2.0)
			elif side == 2:
				point.x = low + rng.randf_range(-2.0, 4.0)
			else:
				point.x = high + rng.randf_range(-4.0, 2.0)
		_chalk_dot(image, rng, point, rng.randf_range(0.6, 1.4), rng.randf_range(0.08, 0.24))


func _blend(image: Image, x: int, y: int, color: Color, alpha: float) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	if alpha <= 0.001:
		return
	var under := image.get_pixel(x, y)
	var out_alpha := alpha + under.a * (1.0 - alpha)
	if out_alpha <= 0.001:
		return
	var mix := alpha / out_alpha
	image.set_pixel(x, y, Color(
		under.r * (1.0 - mix) + color.r * mix,
		under.g * (1.0 - mix) + color.g * mix,
		under.b * (1.0 - mix) + color.b * mix,
		out_alpha))
