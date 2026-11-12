extends CanvasLayer

signal tutorial_started

@export_range(1.0, 20.0, 0.5) var display_seconds := 7.0

@onready var _panel: Control = $TutorialPanel
@onready var _timer: Timer = $HideTimer

var _started := false


func _ready() -> void:
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_timer.stop()


func _input(event: InputEvent) -> void:
	if not visible or _started:
		return

	if (
		event.is_action_pressed(&"move_left")
		or event.is_action_pressed(&"move_right")
		or event.is_action_pressed(&"jump")
	):
		_started = true
		tutorial_started.emit()
		hide_tutorial()


func show_tutorial() -> void:
	_started = false
	_timer.stop()
	visible = true
	set_process_input(true)


func hide_tutorial() -> void:
	_timer.stop()
	visible = false
	set_process_input(false)
