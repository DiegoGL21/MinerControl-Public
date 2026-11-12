extends ColorRect
## Visual-only extension. Does not change the hazard, timer or collision.
@export var minimum_depth: float = 3072.0
@export var camera_bottom: float = 720.0
@export var bottom_margin: float = 720.0
@onready var surface: AnimatedSprite2D = get_node("../LavaLeft")

func _process(_delta: float) -> void:
	# Cover the entire level plus a screen below its lowest camera boundary.
	size.y = maxf(minimum_depth, camera_bottom + bottom_margin - global_position.y)
	var fill_material := material as ShaderMaterial
	fill_material.set_shader_parameter("frame_index", float(surface.frame))
	fill_material.set_shader_parameter("fill_height", size.y)
