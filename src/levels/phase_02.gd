extends Node2D

@export_node_path("CharacterBody2D") var player_path: NodePath = ^"Player"

var _active_player: CharacterBody2D


func _ready() -> void:
	_active_player = get_node_or_null(player_path) as CharacterBody2D
	if _active_player == null:
		push_error("Phase02: no se encontro el Player configurado.")
		return

	# F6 uses the local player and floor. Level01 supplies the shared player.
	if _active_player != $Player:
		for standalone_node in [$Player, $GroundCollision]:
			remove_child(standalone_node)
			standalone_node.queue_free()


func _on_exit_area_body_entered(body):
	if body == _active_player:
		print("Fase 2 completada")
