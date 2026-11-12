extends Node

## Central source of truth for level navigation.
## Persistence uses stable level IDs; scene paths stay here.

const FIRST_LEVEL_ID: String = "level_01"

const LEVEL_ORDER: Array[String] = [
	"level_01",
	"level_02",
	"level_03",
	"level_04",
]

const LEVELS: Dictionary = {
	"level_01": {
		"display_name": "Mina profunda",
		"scene_path": "res://scenes/levels/level_1/level_01.tscn",
		"implemented": true,
	},
	"level_02": {
		"display_name": "Mina intermedia",
		"scene_path": "",
		"implemented": false,
	},
	"level_03": {
		"display_name": "Zona de cristales",
		"scene_path": "",
		"implemented": false,
	},
	"level_04": {
		"display_name": "Salida",
		"scene_path": "",
		"implemented": false,
	},
}


func has_level(level_id: String) -> bool:
	return LEVELS.has(level_id.strip_edges())


func get_level_ids() -> Array[String]:
	return LEVEL_ORDER.duplicate()


func get_level_data(level_id: String) -> Dictionary:
	var clean_id: String = level_id.strip_edges()

	if not LEVELS.has(clean_id):
		return {}

	return (LEVELS[clean_id] as Dictionary).duplicate(true)


func get_scene_path(level_id: String) -> String:
	var data: Dictionary = get_level_data(level_id)

	if data.is_empty():
		return ""

	return String(data.get("scene_path", "")).strip_edges()


func is_level_available(level_id: String) -> bool:
	var data: Dictionary = get_level_data(level_id)

	if data.is_empty() or not bool(data.get("implemented", false)):
		return false

	var scene_path: String = String(
		data.get("scene_path", "")
	).strip_edges()

	return (
		not scene_path.is_empty()
		and ResourceLoader.exists(scene_path)
	)


func get_next_level_id(level_id: String) -> String:
	var clean_id: String = level_id.strip_edges()
	var index: int = LEVEL_ORDER.find(clean_id)

	if index < 0 or index + 1 >= LEVEL_ORDER.size():
		return ""

	return LEVEL_ORDER[index + 1]


func change_to_level(level_id: String) -> Error:
	var clean_id: String = level_id.strip_edges()

	if not has_level(clean_id):
		push_error("Nivel no registrado: " + clean_id)
		return ERR_DOES_NOT_EXIST

	if not is_level_available(clean_id):
		push_error("Nivel todavía no disponible: " + clean_id)
		return ERR_UNAVAILABLE

	var scene_path: String = get_scene_path(clean_id)

	return get_tree().change_scene_to_file(scene_path)
