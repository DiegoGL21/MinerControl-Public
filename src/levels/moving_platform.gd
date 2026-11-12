extends AnimatableBody2D

@export var travel: Vector2 = Vector2(128, 0)
@export_range(2.0, 30.0, 0.1) var cycle_seconds: float = 8.0
@export_range(0.0, 1.0, 0.01) var starting_phase: float = 0.0

var _start_position: Vector2
var _elapsed: float = 0.0


func _ready() -> void:
	_start_position = position
	_elapsed = starting_phase * cycle_seconds
	# Reuse the shared tile's solid outline; only the body supplies collisions.
	var visual: TileMapLayer = $Visual
	var tile_data = visual.tile_set.get_source(21).get_tile_data(Vector2i.ZERO, 0)
	var points: PackedVector2Array = tile_data.get_collision_polygon_points(0, 0)
	for i in range(points.size()):
		points[i] += Vector2(0, 16)
	$CollisionPolygon2D.polygon = points


func _physics_process(delta: float) -> void:
	_elapsed += delta
	var progress = 0.5 - 0.5 * cos(TAU * _elapsed / cycle_seconds)
	position = _start_position + travel * progress
