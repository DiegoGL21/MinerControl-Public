extends Node2D

func _on_exit_area_body_entered(body):
	if body == $Player:
		print("Fase 1 completada")
