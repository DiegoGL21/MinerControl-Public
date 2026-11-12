extends CanvasLayer
## Only this UI processes while the gameplay tree is paused.

const MAIN_MENU := "res://scenes/ui/menus/main_menu.tscn"
var _changing_scene := false
@onready var pause_button: Button = $PauseButton
@onready var pause_panel: Control = $PausePanel
@onready var resume_button: Button = $PausePanel/Center/Panel/Buttons/ResumeButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_button.pressed.connect(_set_paused.bind(true))
	resume_button.pressed.connect(_set_paused.bind(false))
	$PausePanel/Center/Panel/Buttons/RestartButton.pressed.connect(_restart)
	$PausePanel/Center/Panel/Buttons/MainMenuButton.pressed.connect(_main_menu)
	_set_paused(false)
	$PausePanel/Center/Panel/Buttons/SaveButton.pressed.connect(_save_game)

func _save_game() -> void:
	var saved := SaveManager.save_game()
	$PausePanel/Center/Panel/Buttons/SaveStatus.text = "Partida guardada" if saved else SaveManager.last_error

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if not _changing_scene:
			_set_paused(not get_tree().paused)

func _set_paused(value: bool) -> void:
	if _changing_scene:
		return
	if value and not _can_open_pause():
		return
	if value:
		_prepare_player_for_pause()
	get_tree().paused = value
	pause_panel.visible = value
	pause_button.visible = not value
	if value:
		$PausePanel/Center/Panel/Buttons/SaveStatus.text = ""
		resume_button.grab_focus()
	else:
		resume_button.release_focus()
		pause_button.release_focus()

func _can_open_pause() -> bool:
	var level := get_parent()
	return (
		level == null
		or not level.has_method("can_pause_gameplay")
		or bool(level.call("can_pause_gameplay"))
	)

func _prepare_player_for_pause() -> void:
	var level := get_parent()
	if level != null and level.has_method("prepare_player_for_pause"):
		level.call("prepare_player_for_pause")

func _restart() -> void:
	_change_scene(true)

func _main_menu() -> void:
	_change_scene(false)

func _change_scene(restart: bool) -> void:
	if _changing_scene:
		return
	_changing_scene = true
	get_tree().paused = false
	var error: Error
	if restart:
		error = get_tree().reload_current_scene()
	else:
		error = get_tree().change_scene_to_file(MAIN_MENU)
	if error != OK:
		_changing_scene = false
		_set_paused(true)
		push_error("PauseUI: could not change scene: %s" % error_string(error))
