extends Node

## Manual single-slot persistence.
## No writes occur on scene changes or death.

const SAVE_PATH: String = "user://savegame.json"
const LEVEL_ID: String = "level_01"
const LEGACY_LEVEL_SCENE: String = "res://scenes/levels/level_1/level_01.tscn"
const MAX_LIVES: int = 2
const SAVE_VERSION: int = 5

const LEGACY_MINERAL_IDS: Dictionary = {
	"res://scenes/levels/level_1/level_01.tscn::Phase01/MineralPhase1": "mineral_01",
	"res://scenes/levels/level_1/level_01.tscn::Phase02/MineralPhase2": "mineral_02",
	"res://scenes/levels/level_1/level_01.tscn::Phase03/MineralPhase3": "mineral_03",
}
const MINERAL_CATALOG: MineralCatalog = preload(
	"res://resources/minerals/level_01_mineral_catalog.tres"
)
const MIN_SAVED_MINERAL_ID_LIMIT: int = 32

var save_path: String = SAVE_PATH
var life: int = MAX_LIVES
var level_01_completed: bool = false

# Se conserva para compatibilidad con otras partes del proyecto.
var minerals: int = 0

# Minerales recogidos.
var collected_mineral_ids: Array[String] = []

# Minerales que ya fueron detectados durante el recorrido del juego.
var implemented_mineral_ids: Array[String] = []

# Total conocido actualmente.
var total_minerals: int = 0

var last_error: String = ""
var pending_load: Dictionary = {}
var _authoritative_mineral_ids: Array[String] = []
var _catalog_valid: bool = false
var _live_mineral_sources: Dictionary = {}
var _duplicate_mineral_ids: Array[String] = []


func _ready() -> void:
	_initialize_mineral_catalog()


func new_game() -> void:
	pending_load.clear()
	life = MAX_LIVES
	level_01_completed = false

	collected_mineral_ids.clear()
	implemented_mineral_ids.clear()
	_live_mineral_sources.clear()
	_duplicate_mineral_ids.clear()

	total_minerals = _authoritative_mineral_ids.size()

	_sync_mineral_count()


# =========================================================
# MINERALES
# =========================================================

func _initialize_mineral_catalog() -> void:
	_authoritative_mineral_ids.clear()
	_catalog_valid = true

	if MINERAL_CATALOG == null:
		push_error("No se pudo cargar el catálogo de minerales del Nivel 1.")
		_catalog_valid = false
		total_minerals = 0
		return

	for raw_id: String in MINERAL_CATALOG.mineral_ids:
		var mineral_id: String = raw_id.strip_edges()

		if mineral_id.is_empty():
			push_error("El catálogo de minerales contiene un ID vacío.")
			_catalog_valid = false
			continue

		if mineral_id in _authoritative_mineral_ids:
			push_error(
				"ID duplicado en el catálogo de minerales: "
				+ mineral_id
			)
			_catalog_valid = false
			continue

		_authoritative_mineral_ids.append(mineral_id)

	total_minerals = _authoritative_mineral_ids.size()

	if total_minerals <= 0:
		push_error("El catálogo de minerales del Nivel 1 está vacío.")
		_catalog_valid = false


func get_authoritative_mineral_ids() -> Array[String]:
	return _authoritative_mineral_ids.duplicate()


func is_valid_mineral_id(mineral_id: String) -> bool:
	return mineral_id.strip_edges() in _authoritative_mineral_ids


func register_mineral(
	mineral_id: String,
	source: Node = null
) -> bool:
	var clean_id: String = mineral_id.strip_edges()

	if clean_id.is_empty():
		push_error("Se intentó registrar un mineral sin ID.")
		return false

	if not is_valid_mineral_id(clean_id):
		push_warning(
			"El mineral usa un ID que no existe en el catálogo: "
			+ clean_id
		)
		return false

	if clean_id not in implemented_mineral_ids:
		implemented_mineral_ids.append(clean_id)

	if source == null:
		_sync_mineral_count()
		return true

	var sources: Array = _get_live_mineral_sources(clean_id)

	for source_ref: WeakRef in sources:
		if source_ref.get_ref() == source:
			return clean_id not in _duplicate_mineral_ids

	sources.append(weakref(source))
	_live_mineral_sources[clean_id] = sources

	if sources.size() > 1:
		if clean_id not in _duplicate_mineral_ids:
			_duplicate_mineral_ids.append(clean_id)

		push_error(
			"Dos minerales vivos comparten el ID persistente: "
			+ clean_id
		)
		return false

	_sync_mineral_count()
	return true


func unregister_mineral(mineral_id: String, source: Node) -> void:
	var clean_id: String = mineral_id.strip_edges()

	if clean_id.is_empty() or source == null:
		return

	var remaining_sources: Array = []

	for source_ref: WeakRef in _get_live_mineral_sources(clean_id):
		var registered_source: Object = source_ref.get_ref()

		if registered_source != null and registered_source != source:
			remaining_sources.append(source_ref)

	if remaining_sources.is_empty():
		_live_mineral_sources.erase(clean_id)
		_duplicate_mineral_ids.erase(clean_id)
	else:
		_live_mineral_sources[clean_id] = remaining_sources


func _get_live_mineral_sources(mineral_id: String) -> Array:
	var live_sources: Array = []
	var stored_sources: Array = _live_mineral_sources.get(
		mineral_id,
		[]
	)

	for source_ref: Variant in stored_sources:
		if not source_ref is WeakRef:
			continue

		if source_ref.get_ref() != null:
			live_sources.append(source_ref)

	if live_sources.is_empty():
		_live_mineral_sources.erase(mineral_id)
		_duplicate_mineral_ids.erase(mineral_id)
	else:
		_live_mineral_sources[mineral_id] = live_sources

	return live_sources


func has_duplicate_mineral_ids() -> bool:
	for mineral_id: String in _duplicate_mineral_ids.duplicate():
		_get_live_mineral_sources(mineral_id)

		if not _live_mineral_sources.has(mineral_id):
			_duplicate_mineral_ids.erase(mineral_id)

	return not _duplicate_mineral_ids.is_empty()


func collect_mineral(mineral_id: String) -> bool:
	var clean_id: String = mineral_id.strip_edges()

	if clean_id.is_empty():
		push_error("Se intentó recoger un mineral sin ID.")
		return false

	if not is_valid_mineral_id(clean_id):
		push_warning(
			"Se ignoró un mineral fuera del catálogo: "
			+ clean_id
		)
		return false

	if clean_id in collected_mineral_ids:
		return false

	collected_mineral_ids.append(clean_id)

	_sync_mineral_count()

	return true


func is_mineral_collected(mineral_id: String) -> bool:
	var clean_id: String = mineral_id.strip_edges()

	if clean_id.is_empty():
		return false

	if not is_valid_mineral_id(clean_id):
		return false

	return clean_id in collected_mineral_ids


func get_collected_mineral_count() -> int:
	var count: int = 0

	for mineral_id: String in collected_mineral_ids:
		if mineral_id in _authoritative_mineral_ids:
			count += 1

	return count


func get_mineral_percentage() -> float:
	if total_minerals <= 0:
		return 0.0

	return (
		float(get_collected_mineral_count())
		/ float(total_minerals)
	) * 100.0


func has_all_minerals() -> bool:
	if not _catalog_valid or total_minerals <= 0:
		return false

	if has_duplicate_mineral_ids():
		return false

	for mineral_id: String in _authoritative_mineral_ids:
		if mineral_id not in collected_mineral_ids:
			return false

	return true


func set_collected_mineral_ids(ids: Array) -> void:
	collected_mineral_ids.clear()

	for raw_id: Variant in ids:
		if not raw_id is String:
			continue

		var mineral_id: String = String(raw_id).strip_edges()

		if mineral_id.is_empty():
			continue

		if not is_valid_mineral_id(mineral_id):
			push_warning(
				"Se ignoró un ID recogido fuera del catálogo: "
				+ mineral_id
			)
			continue

		if mineral_id in collected_mineral_ids:
			continue

		collected_mineral_ids.append(mineral_id)

	_sync_mineral_count()


func set_implemented_mineral_ids(ids: Array) -> void:
	implemented_mineral_ids.clear()

	for raw_id: Variant in ids:
		if not raw_id is String:
			continue

		var mineral_id: String = String(raw_id).strip_edges()

		if mineral_id.is_empty():
			continue

		if not is_valid_mineral_id(mineral_id):
			push_warning(
				"Se ignoró un ID implementado fuera del catálogo: "
				+ mineral_id
			)
			continue

		if mineral_id in implemented_mineral_ids:
			continue

		implemented_mineral_ids.append(mineral_id)

	_sync_mineral_count()


func _sync_mineral_count() -> void:
	minerals = get_collected_mineral_count()


# =========================================================
# GUARDADO
# =========================================================

func read_save() -> Dictionary:
	last_error = ""

	if not FileAccess.file_exists(save_path):
		last_error = "No hay partida guardada."
		return {}

	var file: FileAccess = FileAccess.open(
		save_path,
		FileAccess.READ
	)

	if file == null:
		last_error = "No se pudo abrir la partida."
		return {}

	var json: JSON = JSON.new()

	if (
		json.parse(file.get_as_text()) != OK
		or not json.data is Dictionary
	):
		last_error = (
			"La partida guardada está dañada. "
			+ "Puedes iniciar con JUGAR."
		)
		return {}

	var data: Dictionary = json.data

	var save_version: int = 3

	if data.has("version"):
		if not (
			data["version"] is int
			or data["version"] is float
		):
			last_error = "Versión de guardado inválida."
			return {}

		var raw_version: float = float(data["version"])

		if (
			not is_finite(raw_version)
			or not is_equal_approx(raw_version, roundf(raw_version))
		):
			last_error = "Versión de guardado inválida."
			return {}

		save_version = int(raw_version)

	if save_version > SAVE_VERSION:
		last_error = "Versión de guardado no compatible."
		return {}

	if save_version <= 4:
		if data.get("level_scene", LEGACY_LEVEL_SCENE) != LEGACY_LEVEL_SCENE:
			last_error = "Nivel guardado no compatible."
			return {}

		data["level_id"] = LEVEL_ID
	else:
		var saved_level_id: Variant = data.get("level_id", "")

		if not saved_level_id is String:
			last_error = "Identificador de nivel inválido."
			return {}

		if String(saved_level_id).strip_edges() != LEVEL_ID:
			last_error = "Nivel guardado no compatible."
			return {}

		data["level_id"] = LEVEL_ID

	if (
		data.has("level_01_completed")
		and not data["level_01_completed"] is bool
	):
		last_error = "Estado de finalización inválido."
		return {}

	data["level_01_completed"] = bool(
		data.get("level_01_completed", false)
	)

	for key: String in [
		"phase",
		"life",
		"minerals",
		"checkpoint_x",
		"checkpoint_y"
	]:
		if data.has(key):
			if not (
				data[key] is float
				or data[key] is int
			):
				last_error = "Datos de guardado inválidos."
				return {}

			if not is_finite(float(data[key])):
				last_error = "Datos de guardado inválidos."
				return {}

	var phase: int = int(
		data.get(
			"phase",
			1
		)
	)

	if phase < 1 or phase > 3:
		last_error = "Fase guardada inválida."
		return {}

	data["phase"] = phase

	var raw_facing_direction: Variant = data.get(
		"facing_direction",
		1
	)

	if not (
		raw_facing_direction is int
		or raw_facing_direction is float
	):
		last_error = "Dirección del jugador inválida."
		return {}

	var facing_value: float = float(raw_facing_direction)

	if (
		not is_finite(facing_value)
		or not is_equal_approx(facing_value, roundf(facing_value))
		or absi(int(facing_value)) != 1
	):
		last_error = "Dirección del jugador inválida."
		return {}

	data["facing_direction"] = int(facing_value)

	var checkpoint_id: String = String(
		data.get(
			"checkpoint_id",
			_checkpoint_id_for_phase(phase)
		)
	).strip_edges()

	if checkpoint_id != _checkpoint_id_for_phase(phase):
		last_error = "Checkpoint guardado inválido."
		return {}

	data["checkpoint_id"] = checkpoint_id

	var has_position: bool = (
		data.has("player_position_x")
		and data.has("player_position_y")
	)

	for key: String in [
		"player_position_x",
		"player_position_y"
	]:
		if data.has(key):
			if not (
				data[key] is float
				or data[key] is int
			):
				last_error = "Posición guardada inválida."
				return {}

			if not is_finite(float(data[key])):
				last_error = "Posición guardada inválida."
				return {}

	if has_position:
		var point: Vector2 = Vector2(
			float(data["player_position_x"]),
			float(data["player_position_y"])
		)

		if (
			point.x < 0.0
			or point.x > 1280.0
			or point.y < -1440.0
			or point.y > 720.0
		):
			last_error = "La posición guardada está fuera del Nivel 1."
			return {}

	data["life"] = clampi(
		int(
			data.get(
				"life",
				MAX_LIVES
			)
		),
		0,
		MAX_LIVES
	)

	if data["life"] <= 0 and not data["level_01_completed"]:
		last_error = (
			"La partida guardada terminó sin vidas. "
			+ "Inicia una nueva partida con JUGAR."
		)
		return {}

	if not _validate_lava_state(data):
		last_error = "Estado de lava guardado inválido."
		return {}

	# =====================================================
	# MINERALES - SAVE VERSION 5
	# =====================================================

	if save_version <= 3:
		push_warning(
			"Save v3 cargado: el progreso de minerales se reinició "
			+ "porque no contiene IDs persistentes."
		)

		data["collected_mineral_ids"] = []
		data["implemented_mineral_ids"] = []
		data["minerals"] = 0
		return data

	if (
		not data.has("collected_mineral_ids")
		or not data.has("implemented_mineral_ids")
	):
		last_error = "Esquema de minerales incompleto."
		return {}

	if save_version == 4:
		var migrated_collected: Dictionary = _migrate_legacy_mineral_ids(
			data["collected_mineral_ids"],
			"collected_mineral_ids"
		)

		if not migrated_collected.get("valid", false):
			return {}

		var migrated_implemented: Dictionary = _migrate_legacy_mineral_ids(
			data["implemented_mineral_ids"],
			"implemented_mineral_ids"
		)

		if not migrated_implemented.get("valid", false):
			return {}

		data["collected_mineral_ids"] = migrated_collected["ids"]
		data["implemented_mineral_ids"] = migrated_implemented["ids"]
		data["minerals"] = (migrated_collected["ids"] as Array).size()
		return data

	var collected_result: Dictionary = _parse_saved_mineral_ids(
		data["collected_mineral_ids"],
		"collected_mineral_ids"
	)

	if not collected_result.get("valid", false):
		return {}

	var implemented_result: Dictionary = _parse_saved_mineral_ids(
		data["implemented_mineral_ids"],
		"implemented_mineral_ids"
	)

	if not implemented_result.get("valid", false):
		return {}

	data["collected_mineral_ids"] = collected_result["ids"]
	data["implemented_mineral_ids"] = implemented_result["ids"]
	data["minerals"] = (collected_result["ids"] as Array).size()

	return data


func _checkpoint_id_for_phase(phase: int) -> String:
	return "checkpoint_%02d" % phase


func _migrate_legacy_mineral_ids(
	raw_value: Variant,
	field_name: String
) -> Dictionary:
	if not raw_value is Array:
		last_error = "Datos de minerales inválidos: " + field_name
		return {"valid": false}

	var raw_ids: Array = raw_value
	var maximum_ids: int = maxi(
		MIN_SAVED_MINERAL_ID_LIMIT,
		total_minerals + 8
	)

	if raw_ids.size() > maximum_ids:
		last_error = "Demasiados IDs de minerales en el guardado."
		return {"valid": false}

	var migrated_ids: Array[String] = []

	for raw_id: Variant in raw_ids:
		if not raw_id is String:
			last_error = "Datos de minerales inválidos: " + field_name
			return {"valid": false}

		var legacy_id: String = String(raw_id).strip_edges()

		if legacy_id.is_empty():
			last_error = "Datos de minerales inválidos: " + field_name
			return {"valid": false}

		var stable_id: String = String(
			LEGACY_MINERAL_IDS.get(
				legacy_id,
				legacy_id
			)
		).strip_edges()

		if not is_valid_mineral_id(stable_id):
			push_warning(
				"Se ignoró un ID desconocido del save v4: "
				+ legacy_id
			)
			continue

		if stable_id not in migrated_ids:
			migrated_ids.append(stable_id)

	return {
		"valid": true,
		"ids": migrated_ids
	}


func _parse_saved_mineral_ids(
	raw_value: Variant,
	field_name: String
) -> Dictionary:
	if not raw_value is Array:
		last_error = "Datos de minerales inválidos: " + field_name
		return {"valid": false}

	var raw_ids: Array = raw_value
	var maximum_ids: int = maxi(
		MIN_SAVED_MINERAL_ID_LIMIT,
		total_minerals + 8
	)

	if raw_ids.size() > maximum_ids:
		last_error = "Demasiados IDs de minerales en el guardado."
		return {"valid": false}

	var valid_ids: Array[String] = []

	for raw_id: Variant in raw_ids:
		if not raw_id is String:
			last_error = "Datos de minerales inválidos: " + field_name
			return {"valid": false}

		var mineral_id: String = String(raw_id).strip_edges()

		if mineral_id.is_empty():
			last_error = "Datos de minerales inválidos: " + field_name
			return {"valid": false}

		if not is_valid_mineral_id(mineral_id):
			push_warning(
				"Se ignoró un ID desconocido del save: "
				+ mineral_id
			)
			continue

		if mineral_id not in valid_ids:
			valid_ids.append(mineral_id)

	return {
		"valid": true,
		"ids": valid_ids
	}


func _validate_lava_state(data: Dictionary) -> bool:
	var keys: Array[String] = [
		"lava_position_x",
		"lava_position_y",
		"lava_activated",
		"lava_rising",
		"lava_delay_remaining"
	]

	var has_lava: bool = data.has("lava_completed")

	for key: String in keys:
		has_lava = has_lava or data.has(key)

	if not has_lava:
		return true

	for key: String in keys:
		if not data.has(key):
			return false

	for key: String in [
		"lava_position_x",
		"lava_position_y",
		"lava_delay_remaining"
	]:
		if not (
			data[key] is int
			or data[key] is float
		):
			return false

		if not is_finite(float(data[key])):
			return false

	for key: String in [
		"lava_activated",
		"lava_rising"
	]:
		if not data[key] is bool:
			return false

	if (
		data.has("lava_completed")
		and not data["lava_completed"] is bool
	):
		return false

	var remaining: float = float(
		data["lava_delay_remaining"]
	)

	if (
		remaining < 0.0
		or remaining > 60.0
		or absf(float(data["lava_position_x"])) > 10000000.0
		or absf(float(data["lava_position_y"])) > 10000000.0
	):
		return false

	if bool(data.get("lava_completed", false)):
		return (
			not bool(data["lava_rising"])
			and remaining == 0.0
		)

	if bool(data["lava_rising"]):
		return (
			bool(data["lava_activated"])
			and remaining == 0.0
		)

	return (
		bool(data["lava_activated"])
		or remaining == 0.0
	)


func load_game() -> bool:
	pending_load = read_save()

	if pending_load.is_empty():
		return false

	level_01_completed = bool(
		pending_load.get("level_01_completed", false)
	)

	set_implemented_mineral_ids(
		pending_load.get(
			"implemented_mineral_ids",
			[]
		)
	)

	set_collected_mineral_ids(
		pending_load.get(
			"collected_mineral_ids",
			[]
		)
	)

	return true


func save_game() -> bool:
	var level: Node = get_tree().current_scene

	if (
		level == null
		or not level.has_method("get_save_checkpoint")
	):
		last_error = "Solo puedes guardar dentro del Nivel 1."
		return false

	var data: Dictionary = level.get_save_checkpoint()

	data.merge(
		{
			"level_id": LEVEL_ID,
			"life": life,
			"level_01_completed": level_01_completed,
			"minerals": get_collected_mineral_count(),
			"collected_mineral_ids":
				collected_mineral_ids.duplicate(),
			"implemented_mineral_ids":
				implemented_mineral_ids.duplicate(),
			"version": SAVE_VERSION
		}
	)

	var file: FileAccess = FileAccess.open(
		save_path + ".tmp",
		FileAccess.WRITE
	)

	if file == null:
		last_error = "No se pudo escribir la partida."
		return false

	file.store_string(
		JSON.stringify(
			data,
			"\t"
		)
	)

	file.flush()

	var error: Error = file.get_error()

	file.close()

	if error == OK:
		error = DirAccess.rename_absolute(
			save_path + ".tmp",
			save_path
		)

	if error != OK:
		last_error = (
			"Error al guardar: "
			+ error_string(error)
		)
		return false

	last_error = ""

	return true
