extends Node2D


const NORMAL_ENDING_SCENE: String = (
	"res://scenes/endings/ending_normal.tscn"
)

const COMPLETE_ENDING_SCENE: String = (
	"res://scenes/endings/ending_100.tscn"
)

const END_FADE_DELAY: float = 0.15
const END_FADE_DURATION: float = 1.0
const END_BLACK_HOLD: float = 0.20


@export_node_path("CharacterBody2D")
var player_path: NodePath = ^"Player"


var _active_player: CharacterBody2D
var _ending_started: bool = false


@onready var _fade: ColorRect = $TransitionLayer/Fade


func _ready() -> void:
	_active_player = (
		get_node_or_null(player_path)
		as CharacterBody2D
	)

	if _active_player == null:
		push_error(
			"Phase03: no se encontro el Player configurado."
		)
		return

	# F6 usa el Player y suelo locales.
	# Level01 proporciona el Player compartido.
	if _active_player != $Player:
		for standalone_node: Node in [
			$Player,
			$GroundCollision
		]:
			remove_child(standalone_node)
			standalone_node.queue_free()

	_fade.visible = true

	var fade_color: Color = _fade.color
	fade_color.a = 0.0
	_fade.color = fade_color


func _on_exit_area_body_entered(body: Node2D) -> void:
	if body != _active_player:
		return

	if _ending_started:
		return

	if not _try_begin_final_transition():
		return

	_ending_started = true

	await _play_ending_transition()

	_open_ending()


func _try_begin_final_transition() -> bool:
	var level: Node = get_parent()

	if level != null and level.has_method("try_begin_final_transition"):
		return bool(level.call("try_begin_final_transition"))

	# F6: Phase 3 no tiene Level01 ni PauseUI compartidos.
	get_tree().paused = false
	return true


func _play_ending_transition() -> void:
	# El jugador conserva su movimiento al cruzar el ExitArea,
	# para que no se sienta como una pared invisible.
	await get_tree().create_timer(
		END_FADE_DELAY
	).timeout

	var tween: Tween = create_tween()

	tween.set_trans(
		Tween.TRANS_CUBIC
	)

	tween.set_ease(
		Tween.EASE_IN
	)

	tween.tween_property(
		_fade,
		"color:a",
		1.0,
		END_FADE_DURATION
	)

	# Dejamos avanzar al jugador durante el inicio del fade.
	await get_tree().create_timer(0.30).timeout

	if _active_player != null:
		_active_player.velocity = Vector2.ZERO
		_active_player.set_physics_process(false)

	await tween.finished

	await get_tree().create_timer(
		END_BLACK_HOLD
	).timeout


func _open_ending() -> void:
	var ending_scene: String

	if SaveManager.has_all_minerals():
		ending_scene = COMPLETE_ENDING_SCENE
		print("Nivel 1 completado al 100%")
	else:
		ending_scene = NORMAL_ENDING_SCENE
		print("Nivel 1 completado")

	var level: Node = get_parent()
	if (
		level != null
		and level.has_method("mark_level_01_completed")
		and not bool(level.call("mark_level_01_completed"))
	):
		push_error(
			"No se pudo persistir la finalización del Nivel 1: "
			+ SaveManager.last_error
		)

	_change_to_ending(ending_scene)


func _change_to_ending(ending_scene: String) -> void:
	var error: Error = get_tree().change_scene_to_file(
		ending_scene
	)

	if error != OK:
		push_error(
			"No se pudo abrir el final: "
			+ ending_scene
			+ " - "
			+ error_string(error)
		)
		_recover_failed_ending_transition()


func _recover_failed_ending_transition() -> void:
	_fade.color.a = 0.0
	_ending_started = false

	if _active_player != null:
		_active_player.velocity = Vector2.ZERO
		_active_player.set_physics_process(true)

	var level: Node = get_parent()

	if level != null and level.has_method("cancel_final_transition"):
		level.call("cancel_final_transition")
