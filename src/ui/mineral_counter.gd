extends CanvasLayer

var _last_mineral_count: int = -1
var _last_total_minerals: int = -1

@onready var _count_label: Label = $CounterPanel/Content/CountLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh()


func _process(_delta: float) -> void:
	if (
		SaveManager.get_collected_mineral_count()
		!= _last_mineral_count
		or SaveManager.total_minerals
		!= _last_total_minerals
	):
		refresh()


func refresh() -> void:
	_last_mineral_count = SaveManager.get_collected_mineral_count()
	_last_total_minerals = SaveManager.total_minerals

	_count_label.text = "%d / %d" % [
		_last_mineral_count,
		_last_total_minerals
	]
