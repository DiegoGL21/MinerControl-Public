extends Area2D

signal mineral_collected


# Normalmente se deja vacío.
# Solo se usa si algún día necesitas conservar el mismo ID
# aunque muevas o renombres este mineral.
@export var persistent_id_override: String = ""

@export var mineral_frames: SpriteFrames:
	set(value):
		mineral_frames = value

		if is_node_ready():
			_apply_frames()

@export_range(1, 10, 1)
var hits_required: int = 1

var _hits_received: int = 0
var _collected: bool = false
var _registration_valid: bool = false
var _registered_id: String = ""

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	_apply_frames()
	_initialize_persistence.call_deferred()


func _initialize_persistence() -> void:
	if not is_inside_tree():
		return

	var persistent_id: String = get_persistent_id()

	if persistent_id.is_empty():
		push_error(
			"No se pudo generar el ID persistente del mineral: "
			+ str(get_path())
		)
		return

	_registered_id = persistent_id

	# Le informa al SaveManager que este mineral existe.
	_registration_valid = SaveManager.register_mineral(
		persistent_id,
		self
	)

	if not _registration_valid:
		return

	# Si ya había sido recogido, no debe reaparecer.
	if SaveManager.is_mineral_collected(persistent_id):
		_collected = true
		_disable_mineral()
		queue_free()


func receive_mine_hit() -> void:
	if _collected or not _registration_valid:
		return

	_hits_received += 1

	if _hits_received < hits_required:
		return

	var persistent_id: String = get_persistent_id()

	if persistent_id.is_empty():
		push_error(
			"No se pudo identificar el mineral: "
			+ str(get_path())
		)
		return

	if not SaveManager.collect_mineral(persistent_id):
		return

	_collected = true
	mineral_collected.emit()

	_disable_mineral()
	queue_free()


func _exit_tree() -> void:
	if not _registered_id.is_empty():
		SaveManager.unregister_mineral(
			_registered_id,
			self
		)


func get_persistent_id() -> String:
	var override_id: String = persistent_id_override.strip_edges()

	if not override_id.is_empty():
		return override_id

	var current_scene: Node = get_tree().current_scene

	if current_scene == null:
		return ""

	var scene_path: String = current_scene.scene_file_path

	if scene_path.is_empty():
		return ""

	var relative_path: String = str(
		current_scene.get_path_to(self)
	)

	if relative_path.is_empty():
		return ""

	return "%s::%s" % [
		scene_path,
		relative_path
	]


func _disable_mineral() -> void:
	monitoring = false
	monitorable = false

	var collision: CollisionShape2D = (
		get_node_or_null("CollisionShape2D")
		as CollisionShape2D
	)

	if collision != null:
		collision.set_deferred(
			&"disabled",
			true
		)


func _apply_frames() -> void:
	if mineral_frames == null:
		return

	_sprite.sprite_frames = mineral_frames
	_sprite.play(&"idle")
